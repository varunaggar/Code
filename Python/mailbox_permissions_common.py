import csv
import json
import logging
import os
import threading
import time
import re
from collections import deque
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.parse import quote

import msal
import requests


GRAPH_ROOT = "https://graph.microsoft.com/v1.0"
GRAPH_SCOPE = "https://graph.microsoft.com/.default"
ADMIN_API_SCOPE = "https://outlook.office365.com/.default"
ADMIN_API_BASE = os.environ.get(
    "EXCHANGE_ADMIN_API_BASE", "https://outlook.office365.com"
).rstrip("/")
ADDRESS_COLUMN = "PrimarySmtpAddress"
logger = logging.getLogger("mailbox_permissions")


def configure_logging(debug_logging=False):
    logging.basicConfig(
        level=logging.DEBUG if debug_logging else logging.INFO,
        format="%(asctime)s %(levelname)s [%(threadName)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        force=True,
    )
    return logger


class TokenProvider:
    def __init__(self, tenant_id, client_id, client_secret):
        self._tenant_id = tenant_id
        self._client_id = client_id
        self._client_secret = client_secret
        self._lock = threading.Lock()
        self._app = self._create_app()
        self._tokens = {}

    def _create_app(self):
        return msal.ConfidentialClientApplication(
            self._client_id,
            authority=f"https://login.microsoftonline.com/{self._tenant_id}",
            client_credential=self._client_secret,
        )

    def get(self, scope, force_refresh=False):
        with self._lock:
            if force_refresh:
                self._app = self._create_app()
                self._tokens.pop(scope, None)
            cached = self._tokens.get(scope)
            if cached and not force_refresh and cached["expires_at"] > time.time() + 120:
                return cached["access_token"]

            result = self._app.acquire_token_for_client(scopes=[scope])
            access_token = result.get("access_token")
            if not access_token:
                raise RuntimeError(
                    f"Token acquisition failed for {scope}: "
                    f"{result.get('error_description', result)}"
                )
            self._tokens[scope] = {
                "access_token": access_token,
                "expires_at": time.time() + int(result.get("expires_in", 3600)),
            }
            return access_token


def load_addresses(csv_path, logger_instance=logger):
    csv_path = Path(csv_path)
    logger_instance.info("Reading mailbox addresses from %s.", csv_path)
    with csv_path.open("r", newline="", encoding="utf-8-sig") as csv_file:
        reader = csv.DictReader(csv_file)
        if not reader.fieldnames or ADDRESS_COLUMN not in reader.fieldnames:
            raise ValueError(f"{csv_path.name} must contain a {ADDRESS_COLUMN} column.")
        addresses = [
            row[ADDRESS_COLUMN].strip()
            for row in reader
            if row.get(ADDRESS_COLUMN, "").strip()
        ]
    logger_instance.info("Loaded %d address(es) from %s.", len(addresses), csv_path.name)
    return addresses


def retry_delay(response, attempt):
    retry_after = response.headers.get("Retry-After", "")
    return int(retry_after) if retry_after.isdigit() else min(2**attempt, 60)


def response_error(response):
    request_id = response.headers.get("request-id") or response.headers.get("x-ms-request-id")
    details = response.text[:1500].replace("\n", " ")
    suffix = f" Request ID: {request_id}." if request_id else ""
    return RuntimeError(f"HTTP {response.status_code}: {details}{suffix}")


def request_with_retry(
    session,
    method,
    url,
    token_provider,
    scope,
    mailbox,
    max_retries,
    timeout,
    logger_instance=logger,
    **kwargs,
):
    refreshed = False
    base_headers = dict(kwargs.pop("headers", {}))
    for attempt in range(max_retries):
        headers = dict(base_headers)
        headers["Authorization"] = f"Bearer {token_provider.get(scope)}"
        logger_instance.debug(
            "Request %s %s for %s (attempt %d/%d).",
            method,
            url,
            mailbox,
            attempt + 1,
            max_retries,
        )
        started_at = time.perf_counter()
        response = session.request(
            method, url, headers=headers, timeout=timeout, **kwargs
        )
        logger_instance.debug(
            "Response HTTP %s for %s in %.2f seconds.",
            response.status_code,
            mailbox,
            time.perf_counter() - started_at,
        )
        if response.status_code == 401 and not refreshed:
            logger_instance.warning("Received HTTP 401 for %s; refreshing token once.", mailbox)
            token_provider.get(scope, force_refresh=True)
            refreshed = True
            continue
        if response.status_code not in (429, 500, 502, 503, 504):
            if not response.ok:
                raise response_error(response)
            return response
        if attempt + 1 == max_retries:
            raise response_error(response)
        delay = retry_delay(response, attempt)
        logger_instance.warning(
            "HTTP %s while processing %s; retrying in %d seconds.",
            response.status_code,
            mailbox,
            delay,
        )
        time.sleep(delay)
    raise RuntimeError("Request retries exhausted.")


def graph_get(
    session,
    token_provider,
    url,
    mailbox,
    max_retries,
    timeout,
    logger_instance=logger,
    params=None,
):
    response = request_with_retry(
        session,
        "GET",
        url,
        token_provider,
        GRAPH_SCOPE,
        mailbox,
        max_retries,
        timeout,
        logger_instance,
        params=params,
    )
    return response.json()


def graph_collection(
    session,
    token_provider,
    url,
    mailbox,
    max_retries,
    timeout,
    logger_instance=logger,
    params=None,
):
    items = []
    page_number = 0
    while url:
        payload = graph_get(
            session,
            token_provider,
            url,
            mailbox,
            max_retries,
            timeout,
            logger_instance,
            params=params,
        )
        page_items = payload.get("value", [])
        items.extend(page_items)
        page_number += 1
        logger_instance.debug(
            "Graph returned %d item(s) on page %d for %s.",
            len(page_items),
            page_number,
            mailbox,
        )
        url = payload.get("@odata.nextLink")
        params = None
    return items


def list_mailbox_folders(
    session,
    token_provider,
    mailbox,
    include_hidden,
    max_retries,
    timeout,
    logger_instance=logger,
):
    mailbox_path = quote(mailbox, safe="")
    root_url = f"{GRAPH_ROOT}/users/{mailbox_path}/mailFolders"
    include_hidden_value = str(include_hidden).lower()
    pending = deque([(root_url, "", {"includeHiddenFolders": include_hidden_value})])
    folders = []
    seen_folder_ids = set()

    while pending:
        collection_url, parent_path, params = pending.popleft()
        child_folders = graph_collection(
            session,
            token_provider,
            collection_url,
            mailbox,
            max_retries,
            timeout,
            logger_instance,
            params=params,
        )
        for folder in child_folders:
            folder_id = folder.get("id")
            display_name = folder.get("displayName")
            if not folder_id or not display_name:
                logger_instance.warning(
                    "Skipping a folder without an ID or display name in %s.", mailbox
                )
                continue
            if folder_id in seen_folder_ids:
                continue
            seen_folder_ids.add(folder_id)

            folder_path = f"{parent_path}\\{display_name}" if parent_path else f"\\{display_name}"
            folders.append({"id": folder_id, "displayName": display_name, "path": folder_path})
            child_url = (
                f"{GRAPH_ROOT}/users/{mailbox_path}/mailFolders/"
                f"{quote(folder_id, safe='')}/childFolders"
            )
            pending.append((child_url, folder_path, {"includeHiddenFolders": include_hidden_value}))

    return folders


def admin_api_post(
    session,
    token_provider,
    mailbox,
    tenant_id,
    url,
    body,
    max_retries,
    timeout,
    logger_instance=logger,
):
    response = request_with_retry(
        session,
        "POST",
        url,
        token_provider,
        ADMIN_API_SCOPE,
        mailbox,
        max_retries,
        timeout,
        logger_instance,
        headers={
            "Content-Type": "application/json",
            "X-AnchorMailbox": f"AAD-UPN:{mailbox}",
        },
        json=body,
    )
    return response.json() if response.content else {}


def extract_permission_entries(payload):
    if isinstance(payload, list):
        return payload
    if not isinstance(payload, dict):
        return []

    for key in ("value", "Value", "CmdletOutput", "Results", "Items", "Result"):
        value = payload.get(key)
        if isinstance(value, list):
            return value
        if isinstance(value, dict):
            nested = extract_permission_entries(value)
            if nested:
                return nested
    if "User" in payload or "AccessRights" in payload:
        return [payload]
    return []


def get_folder_permissions(
    session,
    token_provider,
    tenant_id,
    mailbox,
    folder_path,
    admin_api_base,
    max_retries,
    timeout,
    logger_instance=logger,
):
    identity = f"{mailbox}:{folder_path}"
    endpoint = (
        f"{admin_api_base}/adminapi/v2.0/{quote(tenant_id, safe='')}"
        "/MailboxFolderPermission"
    )
    body = {
        "CmdletInput": {
            "CmdletName": "Get-MailboxFolderPermission",
            "Parameters": {"Identity": identity, "ResultSize": "Unlimited"},
        }
    }

    permissions = []
    url = endpoint
    page = 0
    while url:
        payload = admin_api_post(
            session,
            token_provider,
            mailbox,
            tenant_id,
            url,
            body,
            max_retries,
            timeout,
            logger_instance,
        )
        permissions.extend(extract_permission_entries(payload))
        page += 1
        logger_instance.debug(
            "Read permission page %d for %s (current count: %d).",
            page,
            identity,
            len(permissions),
        )
        url = payload.get("@odata.nextLink") if isinstance(payload, dict) else None
    return permissions


def permission_exists(entries, user):
    target = user.casefold()
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        candidates = set()
        for key in ("User", "UserPrincipalName", "PrimarySmtpAddress", "EmailAddress"):
            candidates.update(user_values(entry.get(key)))
        if target in candidates:
            return True
    return False


def user_values(value):
    if isinstance(value, str):
        yield value.casefold()
        for address in re.findall(
            r"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}", value, re.IGNORECASE
        ):
            yield address.casefold()
    elif isinstance(value, dict):
        for nested_value in value.values():
            yield from user_values(nested_value)
    elif isinstance(value, list):
        for nested_value in value:
            yield from user_values(nested_value)


def folder_permission_request(cmdlet, identity, user=None, access_right=None):
    parameters = {"Identity": identity}
    if user is not None:
        parameters["User"] = user
    if access_right is not None:
        parameters["AccessRights"] = access_right
    if cmdlet == "Get-MailboxFolderPermission":
        parameters["ResultSize"] = "Unlimited"
    return {"CmdletInput": {"CmdletName": cmdlet, "Parameters": parameters}}


def create_session():
    return requests.Session()


def csv_value(value):
    if value is None:
        return ""
    if isinstance(value, (list, dict)):
        return json.dumps(value, ensure_ascii=True, sort_keys=True)
    return str(value)


def write_csv(output_path, fieldnames, rows, logger_instance=logger):
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", newline="", encoding="utf-8") as output_file:
        writer = csv.DictWriter(output_file, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
    logger_instance.info("Wrote %d result row(s) to %s.", len(rows), output_path)


def mailbox_label(item):
    if isinstance(item, dict):
        return item.get("Mailbox", "(unknown mailbox)")
    return str(item)


def run_mailbox_workers(items, worker, max_workers, logger_instance=logger):
    if max_workers < 1:
        raise ValueError("MAX_WORKERS must be at least 1.")
    if not items:
        return [], []

    outcomes = []
    failures = []
    worker_mailboxes = {}
    logger_instance.info(
        "Submitting %d mailbox task(s) to %d worker(s).", len(items), max_workers
    )
    with ThreadPoolExecutor(
        max_workers=max_workers,
        thread_name_prefix="MailboxWorker",
    ) as executor:
        futures = {}
        for index, item in enumerate(items, start=1):
            label = mailbox_label(item)
            logger_instance.info("Queueing mailbox %d/%d: %s.", index, len(items), label)
            futures[executor.submit(worker, item, index, len(items))] = item

        for future in as_completed(futures):
            item = futures[future]
            label = mailbox_label(item)
            try:
                worker_name, processed_mailbox, rows, error_count = future.result()
            except Exception as error:
                logger_instance.exception("Worker failed for mailbox %s.", label)
                failures.append((item, error))
                continue
            worker_mailboxes.setdefault(worker_name, []).append(processed_mailbox)
            outcomes.append((processed_mailbox, rows, error_count))

    for worker_name, processed_mailboxes in sorted(worker_mailboxes.items()):
        logger_instance.info(
            "Worker summary: %s processed %d mailbox(es): %s",
            worker_name,
            len(processed_mailboxes),
            ", ".join(processed_mailboxes),
        )
    return outcomes, failures


def run_script(main_function, debug_logging=False):
    logger_instance = configure_logging(debug_logging)
    started_at = time.perf_counter()
    exit_code = 0
    try:
        exit_code = main_function(logger_instance)
    except Exception:
        logger_instance.exception("Script failed.")
        exit_code = 1
    finally:
        logger_instance.info(
            "Total execution time: %.2f seconds.", time.perf_counter() - started_at
        )
    raise SystemExit(exit_code)
