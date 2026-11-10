import csv
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.parse import quote

import msal
import requests


# Edit these settings to control which default folders receive child folders.
GRAPH_ROOT = "https://graph.microsoft.com/v1.0"
MAILBOX_CSV = Path(__file__).with_name("Mailboxes.csv")
MAILBOX_COLUMN = "PrimarySmtpAddress"
MAX_WORKERS = 10
REQUEST_TIMEOUT = 30
MAX_RETRIES = 10
DRY_RUN = False

# Each depth is the child count at that level, applied to every parent in the
# previous level: (level 1, level 2, level 3, level 4).
DEFAULT_FOLDER_SETTINGS = (
	("msgfolderroot", "Top of Information Store", True, (4, 0, 0, 0)),
	("inbox", "Inbox", True, (20, 2, 3, 1)),
	("drafts", "Drafts", False, (0, 0, 0, 0)),
	("sentitems", "Sent Items", True, (2, 1, 1, 1)),
	("deleteditems", "Deleted Items", True, (2, 0, 0, 0)),
	("junkemail", "Junk Email", False, (0, 0, 0, 0)),
	("archive", "Archive", True, (1, 0, 0, 0)),
	("outbox", "Outbox", False, (0, 0, 0, 0)),
	("conversationhistory", "Conversation History", False, (0, 0, 0, 0)),
	("clutter", "Clutter", False, (0, 0, 0, 0)),
	("conflicts", "Conflicts", False, (0, 0, 0, 0)),
	("localfailures", "Local Failures", False, (0, 0, 0, 0)),
	("recoverableitemsdeletions", "Recoverable Items Deletions", False, (0, 0, 0, 0)),
	("scheduled", "Scheduled", False, (0, 0, 0, 0)),
	("searchfolders", "Search Folders", False, (0, 0, 0, 0)),
	("syncissues", "Sync Issues", False, (0, 0, 0, 0)),
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


def read_mailboxes():
	with MAILBOX_CSV.open("r", newline="", encoding="utf-8-sig") as csv_file:
		reader = csv.DictReader(csv_file)
		if not reader.fieldnames or MAILBOX_COLUMN not in reader.fieldnames:
			raise ValueError(
				f"{MAILBOX_CSV.name} must contain a {MAILBOX_COLUMN} column."
			)
		return [
			row[MAILBOX_COLUMN].strip()
			for row in reader
			if row.get(MAILBOX_COLUMN, "").strip()
		]


def graph_request(session, method, url, params=None, json_body=None):
	for attempt in range(MAX_RETRIES):
		response = session.request(
			method,
			url,
			params=params,
			json=json_body,
			timeout=REQUEST_TIMEOUT,
		)
		if response.status_code not in (429, 503, 504):
			response.raise_for_status()
			return response.json() if response.content else {}

		if attempt + 1 == MAX_RETRIES:
			response.raise_for_status()
		retry_after = response.headers.get("Retry-After", "")
		delay = int(retry_after) if retry_after.isdigit() else 2**attempt
		time.sleep(delay)


def get_folders(session, url):
	folders = []
	params = {"$select": "id,displayName"}
	while url:
		response = graph_request(session, "GET", url, params=params)
		folders.extend(response.get("value", []))
		url = response.get("@odata.nextLink")
		params = None
	return folders


def collection_url(mailbox, folder_name):
	mailbox_path = quote(mailbox, safe="")
	if folder_name == "msgfolderroot":
		return f"{GRAPH_ROOT}/users/{mailbox_path}/mailFolders"
	root_path = quote(folder_name, safe="")
	return (
		f"{GRAPH_ROOT}/users/{mailbox_path}/mailFolders/"
		f"{root_path}/childFolders"
	)


def generated_folder_tree(parent_display_name, level_depths):
	prefix = parent_display_name[:2].upper()

	def build_children(parent_folder_name, level_index):
		if level_index >= len(level_depths):
			return []

		children = []
		for number in range(1, level_depths[level_index] + 1):
			if level_index == 0:
				folder_name = f"{prefix}-{number}"
			else:
				folder_name = f"{parent_folder_name}.{number}"
			children.append({
				"name": folder_name,
				"children": build_children(folder_name, level_index + 1),
			})
		return children

	return build_children(None, 0)


def ensure_folder_tree(session, collection, folders, mailbox, parent_name, actions):
	if not folders:
		return

	existing = {
		folder.get("displayName", "").casefold(): folder
		for folder in get_folders(session, collection)
	}
	for folder_spec in folders:
		folder_name = folder_spec["name"]
		folder = existing.get(folder_name.casefold())
		if folder:
			actions.append(f"Exists: {mailbox} / {parent_name} / {folder_name}")
		else:
			folder = graph_request(
				session,
				"POST",
				collection,
				json_body={"displayName": folder_name},
			)
			actions.append(f"Created: {mailbox} / {parent_name} / {folder_name}")
			existing[folder_name.casefold()] = folder

		children = folder_spec["children"]
		if not children:
			continue
		folder_id = folder.get("id")
		if not folder_id:
			raise RuntimeError(f"Graph did not return an ID for {folder_name!r}.")
		child_collection = (
			f"{GRAPH_ROOT}/users/{quote(mailbox, safe='')}/mailFolders/"
			f"{quote(folder_id, safe='')}/childFolders"
		)
		ensure_folder_tree(
			session,
			child_collection,
			children,
			mailbox,
			f"{parent_name}/{folder_name}",
			actions,
		)


def preview_folder_tree(mailbox, parent_name, folders, actions):
	for folder_spec in folders:
		folder_name = folder_spec["name"]
		actions.append(f"Would ensure: {mailbox} / {parent_name} / {folder_name}")
		preview_folder_tree(
			mailbox,
			f"{parent_name}/{folder_name}",
			folder_spec["children"],
			actions,
		)


def process_mailbox(mailbox, token):
	actions = []
	with requests.Session() as session:
		if not DRY_RUN:
			session.headers.update({"Authorization": f"Bearer {token}"})

		for folder_id, display_name, enabled, level_depths in DEFAULT_FOLDER_SETTINGS:
			if not enabled:
				continue
			folder_tree = generated_folder_tree(display_name, level_depths)
			if DRY_RUN:
				preview_folder_tree(mailbox, display_name, folder_tree, actions)
				continue
			ensure_folder_tree(
				session,
				collection_url(mailbox, folder_id),
				folder_tree,
				mailbox,
				display_name,
				actions,
			)
	return actions


def main():
	if MAX_WORKERS < 1:
		raise ValueError("MAX_WORKERS must be at least 1.")
	for _, folder_name, enabled, level_depths in DEFAULT_FOLDER_SETTINGS:
		if not isinstance(enabled, bool):
			raise ValueError(f"Create_subfolder setting for {folder_name} must be Boolean.")
		if len(level_depths) != 4:
			raise ValueError(f"{folder_name} must have exactly four level counts.")
		for level_index, depth in enumerate(level_depths):
			if not isinstance(depth, int) or depth < 0:
				raise ValueError(f"Level {level_index + 1} count for {folder_name} must be a non-negative integer.")
			if depth and level_index > 0 and not level_depths[level_index - 1]:
				raise ValueError(f"{folder_name} cannot configure level {level_index + 1} without the previous level.")

	mailboxes = read_mailboxes()
	if not mailboxes:
		raise ValueError(f"No mailbox addresses found in {MAILBOX_CSV.name}.")

	token = None if DRY_RUN else get_access_token()
	failures = []
	with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
		futures = {
			executor.submit(process_mailbox, mailbox, token): mailbox
			for mailbox in mailboxes
		}
		for future in as_completed(futures):
			mailbox = futures[future]
			try:
				for action in future.result():
					print(action)
			except Exception as error:
				failures.append(f"{mailbox}: {error}")

	for failure in failures:
		print(f"Error: {failure}", file=sys.stderr)
	print(
		f"Processed {len(mailboxes)} mailboxes; "
		f"mode={'dry-run' if DRY_RUN else 'create'}; failures={len(failures)}."
	)
	return 1 if failures else 0


if __name__ == "__main__":
	try:
		raise SystemExit(main())
	except Exception as error:
		print(f"Error: {error}", file=sys.stderr)
		raise SystemExit(1)
