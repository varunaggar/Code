import csv
import logging
import os
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.parse import quote

import msal
import requests


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s [%(threadName)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

GRAPH_ROOT = "https://graph.microsoft.com/v1.0"
INPUT_CSV = Path(__file__).with_name("Mailboxes.csv")
OUTPUT_CSV = Path(__file__).with_name("MailFoldersWithStats.csv")
MAILBOX_COLUMN = "PrimarySmtpAddress"
MAX_WORKERS = 20
REQUEST_TIMEOUT = 30
MAX_RETRIES = 4
OUTPUT_FIELDS = (
    "Mailbox",
    "FolderLevel",
    "FolderId",
    "ParentFolderId",
    "DisplayName",
    "ChildFolderCount",
    "WellKnownName",
    "IsHidden",
)


def get_access_token():
    tenant_id = os.environ.get("AZURE_TENANT_ID", "")
    client_id = os.environ.get("AZURE_CLIENT_ID", "")
    client_secret = os.environ.get("AZURE_CLIENT_SECRET", "")
    if not all((tenant_id, client_id, client_secret)):
        raise RuntimeError(
            "Set TENANT_ID, CLIENT_ID, and CLIENT_SECRET environment variables."
        )

    logger.info("Requesting an app-only Microsoft Graph access token.")
    app = msal.ConfidentialClientApplication(
        client_id,
        authority=f"https://login.microsoftonline.com/{tenant_id}",
        client_credential=client_secret,
    )
    result = app.acquire_token_for_client(
        scopes=["https://graph.microsoft.com/.default"]
    )
    if "access_token" not in result:
        raise RuntimeError(
            f"Could not acquire an access token: {result.get('error_description', result)}"
        )
    logger.info("Microsoft Graph access token acquired.")
    return result["access_token"]


def get_graph_items(url, token, params=None):
    headers = {"Authorization": f"Bearer {token}"}
    items = []
    page_number = 0
    while url:
        for attempt in range(MAX_RETRIES):
            response = requests.get(
                url, headers=headers, params=params, timeout=REQUEST_TIMEOUT
            )
            if response.status_code not in (429, 503, 504):
                response.raise_for_status()
                break
            if attempt + 1 == MAX_RETRIES:
                response.raise_for_status()
            retry_after = response.headers.get("Retry-After", "")
            delay = int(retry_after) if retry_after.isdigit() else 2**attempt
            logger.warning(
                "Graph returned HTTP %s; retrying request (%d/%d) in %d seconds.",
                response.status_code,
                attempt + 1,
                MAX_RETRIES,
                delay,
            )
            time.sleep(delay)

        payload = response.json()
        page_items = payload.get("value", [])
        items.extend(page_items)
        page_number += 1
        logger.debug("Fetched Graph page %d with %d item(s).", page_number, len(page_items))
        url = payload.get("@odata.nextLink")
        params = None
    return items


def read_mailboxes():
    logger.info("Reading mailbox addresses from %s.", INPUT_CSV)
    with INPUT_CSV.open("r", newline="", encoding="utf-8-sig") as mailbox_file:
        reader = csv.DictReader(mailbox_file)
        if not reader.fieldnames or MAILBOX_COLUMN not in reader.fieldnames:
            raise ValueError(f"{INPUT_CSV.name} must contain a {MAILBOX_COLUMN} column.")
        mailboxes = [
            row[MAILBOX_COLUMN].strip()
            for row in reader
            if row.get(MAILBOX_COLUMN, "").strip()
        ]
    logger.info("Loaded %d mailbox address(es).", len(mailboxes))
    return mailboxes


def get_root_folders(mailbox, token):
    logger.info("Starting root-folder lookup for %s.", mailbox)
    mailbox_path = quote(mailbox, safe="")
    url = f"{GRAPH_ROOT}/users/{mailbox_path}/mailFolders"
    folders = get_graph_items(url, token, params={"includeHiddenFolders": "false"})
    logger.info("Found %d root folder(s) for %s.", len(folders), mailbox)
    return folders


def get_child_folders(mailbox, folder, token):
    folder_name = folder.get("displayName", "(unnamed folder)")
    logger.info("Starting child-folder lookup for %s / %s.", mailbox, folder_name)
    mailbox_path = quote(mailbox, safe="")
    folder_id = quote(folder["id"], safe="")
    url = f"{GRAPH_ROOT}/users/{mailbox_path}/mailFolders/{folder_id}/childFolders"
    folders = get_graph_items(url, token, params={"includeHiddenFolders": "true"})
    logger.info(
        "Found %d child folder(s) under %s / %s.", len(folders), mailbox, folder_name
    )
    return folders


def folder_row(mailbox, folder, level):
    return {
        "Mailbox": mailbox,
        "FolderLevel": level,
        "FolderId": folder.get("id", ""),
        "ParentFolderId": folder.get("parentFolderId", ""),
        "DisplayName": folder.get("displayName", ""),
        "ChildFolderCount": folder.get("childFolderCount", ""),
        "WellKnownName": folder.get("wellKnownName", ""),
        "IsHidden": folder.get("isHidden", ""),
    }


def process_mailbox(mailbox, token, mailbox_index, mailbox_count):
    worker_name = threading.current_thread().name
    started_at = time.perf_counter()
    rows = []
    errors = []
    logger.info(
        "Worker assigned mailbox %d/%d: %s.", mailbox_index, mailbox_count, mailbox
    )

    try:
        root_folders = get_root_folders(mailbox, token)
    except Exception as error:
        logger.exception("Root-folder lookup failed for %s.", mailbox)
        return worker_name, mailbox, rows, [f"{mailbox}: {error}"]

    rows.extend(folder_row(mailbox, folder, "root") for folder in root_folders)
    for root_folder in root_folders:
        try:
            child_folders = get_child_folders(mailbox, root_folder, token)
            rows.extend(folder_row(mailbox, folder, "child") for folder in child_folders)
        except Exception as error:
            folder_name = root_folder.get("displayName", "(unnamed folder)")
            logger.exception(
                "Child-folder lookup failed for %s / %s.", mailbox, folder_name
            )
            errors.append(f"{mailbox} ({folder_name}): {error}")

    logger.info(
        "Worker completed mailbox %s: %d root folder(s), %d total folder row(s), "
        "%d error(s), %.2f seconds.",
        mailbox,
        len(root_folders),
        len(rows),
        len(errors),
        time.perf_counter() - started_at,
    )
    return worker_name, mailbox, rows, errors


def main():
    if MAX_WORKERS < 1:
        raise ValueError("MAX_WORKERS must be at least 1.")
    logger.info("Starting mailbox-folder inventory with %d worker(s).", MAX_WORKERS)
    mailboxes = read_mailboxes()
    if not mailboxes:
        raise ValueError(f"No mailbox addresses found in {INPUT_CSV.name}.")
    token = get_access_token()
    rows = []
    errors = []
    worker_mailboxes = {}

    with ThreadPoolExecutor(
        max_workers=MAX_WORKERS,
        thread_name_prefix="MailboxWorker",
    ) as executor:
        futures = {}
        for mailbox_index, mailbox in enumerate(mailboxes, start=1):
            logger.info("Queueing mailbox %d/%d: %s.", mailbox_index, len(mailboxes), mailbox)
            future = executor.submit(
                process_mailbox,
                mailbox,
                token,
                mailbox_index,
                len(mailboxes),
            )
            futures[future] = mailbox

        for future in as_completed(futures):
            mailbox = futures[future]
            try:
                worker_name, processed_mailbox, mailbox_rows, mailbox_errors = future.result()
            except Exception:
                logger.exception("Unexpected worker failure for %s.", mailbox)
                errors.append(f"{mailbox}: unexpected worker failure")
                continue

            worker_mailboxes.setdefault(worker_name, []).append(processed_mailbox)
            rows.extend(mailbox_rows)
            errors.extend(mailbox_errors)

    for worker_name, worker_processed in sorted(worker_mailboxes.items()):
        logger.info(
            "Worker summary: %s processed %d mailbox(es): %s",
            worker_name,
            len(worker_processed),
            ", ".join(worker_processed),
        )

    logger.info("Writing %d folder row(s) to %s.", len(rows), OUTPUT_CSV)
    with OUTPUT_CSV.open("w", newline="", encoding="utf-8") as output_file:
        writer = csv.DictWriter(output_file, fieldnames=OUTPUT_FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    logger.info("Finished writing folder results to %s.", OUTPUT_CSV)
    for error in errors:
        logger.error("Mailbox processing error: %s", error)
    logger.info(
        "Inventory complete: %d mailbox(es), %d folder row(s), %d error(s).",
        len(mailboxes),
        len(rows),
        len(errors),
    )
    return 1 if errors else 0


if __name__ == "__main__":
    start_time = time.perf_counter()
    try:
        raise SystemExit(main())
    except Exception as error:
        logger.exception("Mailbox folder inventory failed: %s", error)
        raise SystemExit(1)
    finally:
        logger.info("Total execution time: %.2f seconds.", time.perf_counter() - start_time)