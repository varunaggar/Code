import csv
import os
import sys
import time
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from pathlib import Path
from urllib.parse import quote

import msal
import requests

GRAPH_ROOT = "https://graph.microsoft.com/v1.0"
INPUT_CSV = Path(__file__).with_name("Mailboxes.csv")
OUTPUT_CSV = Path(__file__).with_name("MailFolders.csv")
MAX_WORKERS = 2
OUTPUT_FIELDS = (
	"Mailbox",
	"FolderLevel",
	"FolderId",
	"ParentFolderId",
	"DisplayName",
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
	return result["access_token"]


def get_graph_items(url, token, params=None):
	headers = {"Authorization": f"Bearer {token}"}
	items = []
	while url:
		for attempt in range(4):
			response = requests.get(url, headers=headers, params=params, timeout=30)
			if response.status_code not in (429, 503, 504):
				response.raise_for_status()
				break
			if attempt == 3:
				response.raise_for_status()
			retry_after = response.headers.get("Retry-After")
			delay = int(retry_after) if retry_after and retry_after.isdigit() else 2**attempt
			time.sleep(delay)

		payload = response.json()
		items.extend(payload.get("value", []))
		url = payload.get("@odata.nextLink")
		params = None
	return items


def read_mailboxes():
	with INPUT_CSV.open("r", newline="", encoding="utf-8-sig") as mailbox_file:
		reader = csv.DictReader(mailbox_file)
		if not reader.fieldnames or "PrimarySmtpAddress" not in reader.fieldnames:
			raise ValueError(f"{INPUT_CSV.name} must contain a PrimarySmtpAddress column.")
		return [
			row["PrimarySmtpAddress"].strip()
			for row in reader
			if row.get("PrimarySmtpAddress", "").strip()
		]


def get_root_folders(mailbox, token):
	mailbox_path = quote(mailbox, safe="")
	url = f"{GRAPH_ROOT}/users/{mailbox_path}/mailFolders"
	return get_graph_items(url, token, params={"includeHiddenFolders": "false"})


def get_child_folders(mailbox, folder, token):
	mailbox_path = quote(mailbox, safe="")
	folder_id = quote(folder["id"], safe="")
	url = f"{GRAPH_ROOT}/users/{mailbox_path}/mailFolders/{folder_id}/childFolders"
	return get_graph_items(url, token, params={"includeHiddenFolders": "true"})


def folder_row(mailbox, folder, level):
	return {
		"Mailbox": mailbox,
		"FolderLevel": level,
		"FolderId": folder.get("id", ""),
		"ParentFolderId": folder.get("parentFolderId", ""),
		"DisplayName": folder.get("displayName", ""),
		"WellKnownName": folder.get("wellKnownName", ""),
		"IsHidden": folder.get("isHidden", ""),
	}


def main():
	mailboxes = read_mailboxes()
	if not mailboxes:
		raise ValueError(f"No mailbox addresses found in {INPUT_CSV.name}.")
	token = get_access_token()
	rows = []
	errors = []
	with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
		pending = {
			executor.submit(get_root_folders, mailbox, token): ("root", mailbox, None)
			for mailbox in mailboxes
		}
		while pending:
			completed, _ = wait(pending, return_when=FIRST_COMPLETED)
			for future in completed:
				kind, mailbox, folder = pending.pop(future)
				try:
					folders = future.result()
				except Exception as error:
					label = f"{mailbox} ({folder.get('displayName', 'child folder')})" if folder else mailbox
					errors.append(f"{label}: {error}")
					continue

				if kind == "root":
					rows.extend(folder_row(mailbox, item, "root") for item in folders)
					for root_folder in folders:
						child_future = executor.submit(
							get_child_folders, mailbox, root_folder, token
						)
						pending[child_future] = ("child", mailbox, root_folder)
				else:
					rows.extend(folder_row(mailbox, item, "child") for item in folders)

	with OUTPUT_CSV.open("w", newline="", encoding="utf-8") as output_file:
		writer = csv.DictWriter(output_file, fieldnames=OUTPUT_FIELDS)
		writer.writeheader()
		writer.writerows(rows)
	for error in errors:
		print(f"Error: {error}", file=sys.stderr)
	print(f"Wrote {len(rows)} folders to {OUTPUT_CSV}.")
	return 1 if errors else 0

if __name__ == "__main__":
	start_time = time.perf_counter()
	try:
		raise SystemExit(main())
	except Exception as error:
		print(f"Error: {error}", file=sys.stderr)
		raise SystemExit(1)
	finally:
		elapsed = time.perf_counter() - start_time
		print(f"Execution time: {elapsed:.2f} seconds")

