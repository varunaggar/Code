import os
import threading
import time
from pathlib import Path

from mailbox_permissions_common import (
	ADMIN_API_BASE,
	ADMIN_API_SCOPE,
	GRAPH_SCOPE,
	TokenProvider,
	create_session,
	csv_value,
	get_folder_permissions,
	list_mailbox_folders,
	load_addresses,
	logger,
	run_mailbox_workers,
	run_script,
	write_csv,
)


# Script configuration.
SCRIPT_DIR = Path(__file__).resolve().parent
MAILBOX_CSV = SCRIPT_DIR / "Mailboxes.csv"
OUTPUT_CSV = SCRIPT_DIR / "MailboxFolderPermissions.csv"
TENANT_ID = os.environ.get("TENANT_ID", "")
CLIENT_ID = os.environ.get("CLIENT_ID", "")
CLIENT_SECRET = os.environ.get("CLIENT_SECRET", "")
MAX_WORKERS = 4
MAX_RETRIES = 5
REQUEST_TIMEOUT = 30
INCLUDE_HIDDEN_FOLDERS = False
DEBUG_LOGGING = False

RESULT_FIELDS = (
	"Mailbox",
	"FolderPath",
	"FolderName",
	"User",
	"AccessRights",
	"SharingPermissionFlags",
	"IsValid",
	"Status",
	"Error",
)


def permission_row(mailbox, folder, permission):
	user = permission.get("User", "")
	if isinstance(user, dict):
		user = (
			user.get("PrimarySmtpAddress")
			or user.get("UserPrincipalName")
			or user.get("Name")
			or user
		)
	return {
		"Mailbox": mailbox,
		"FolderPath": folder["path"],
		"FolderName": permission.get("FolderName", folder["displayName"]),
		"User": csv_value(user),
		"AccessRights": csv_value(permission.get("AccessRights")),
		"SharingPermissionFlags": csv_value(permission.get("SharingPermissionFlags")),
		"IsValid": csv_value(permission.get("IsValid")),
		"Status": "Success",
		"Error": "",
	}


def process_mailbox(mailbox, mailbox_index, mailbox_count, token_provider):
	worker = threading.current_thread().name
	started_at = time.perf_counter()
	rows = []
	errors = 0
	logger.info(
		"Worker %s assigned mailbox %d/%d: %s.",
		worker,
		mailbox_index,
		mailbox_count,
		mailbox,
	)

	with create_session() as session:
		try:
			logger.info("Discovering folders for %s.", mailbox)
			folders = list_mailbox_folders(
				session,
				token_provider,
				mailbox,
				INCLUDE_HIDDEN_FOLDERS,
				MAX_RETRIES,
				REQUEST_TIMEOUT,
				logger,
			)
			logger.info("Found %d folder(s) recursively in %s.", len(folders), mailbox)
		except Exception as error:
			logger.exception("Folder discovery failed for %s.", mailbox)
			return worker, mailbox, [{
				"Mailbox": mailbox,
				"FolderPath": "",
				"FolderName": "",
				"User": "",
				"AccessRights": "",
				"SharingPermissionFlags": "",
				"IsValid": "",
				"Status": "Failed",
				"Error": str(error),
			}], 1

		if not folders:
			rows.append({
				"Mailbox": mailbox,
				"FolderPath": "",
				"FolderName": "",
				"User": "",
				"AccessRights": "",
				"SharingPermissionFlags": "",
				"IsValid": "",
				"Status": "NoFoldersFound",
				"Error": "Graph returned no mailbox folders.",
			})

		for folder_index, folder in enumerate(folders, start=1):
			logger.info(
				"Worker %s reading permissions for folder %d/%d: %s:%s",
				worker,
				folder_index,
				len(folders),
				mailbox,
				folder["path"],
			)
			try:
				permissions = get_folder_permissions(
					session,
					token_provider,
					TENANT_ID,
					mailbox,
					folder["path"],
					ADMIN_API_BASE,
					MAX_RETRIES,
					REQUEST_TIMEOUT,
					logger,
				)
				if permissions:
					rows.extend(permission_row(mailbox, folder, item) for item in permissions)
					logger.info(
						"Read %d permission entry(ies) from %s:%s.",
						len(permissions),
						mailbox,
						folder["path"],
					)
				else:
					rows.append({
						"Mailbox": mailbox,
						"FolderPath": folder["path"],
						"FolderName": folder["displayName"],
						"User": "",
						"AccessRights": "",
						"SharingPermissionFlags": "",
						"IsValid": "",
						"Status": "NoPermissionsReturned",
						"Error": "The Admin API returned no permission entries.",
					})
			except Exception as error:
				errors += 1
				logger.exception(
					"Failed to read permissions for %s:%s.", mailbox, folder["path"]
				)
				rows.append({
					"Mailbox": mailbox,
					"FolderPath": folder["path"],
					"FolderName": folder["displayName"],
					"User": "",
					"AccessRights": "",
					"SharingPermissionFlags": "",
					"IsValid": "",
					"Status": "Failed",
					"Error": str(error),
				})

	logger.info(
		"Worker %s completed %s: %d folder(s), %d row(s), %d error(s), %.2f seconds.",
		worker,
		mailbox,
		len(folders),
		len(rows),
		errors,
		time.perf_counter() - started_at,
	)
	return worker, mailbox, rows, errors


def main(logger_instance):
	if not all((TENANT_ID, CLIENT_ID, CLIENT_SECRET)):
		raise RuntimeError(
			"Set TENANT_ID, CLIENT_ID, and CLIENT_SECRET environment variables."
		)
	if MAX_WORKERS < 1:
		raise ValueError("MAX_WORKERS must be at least 1.")

	mailboxes = load_addresses(MAILBOX_CSV, logger_instance)
	if not mailboxes:
		raise ValueError(f"No mailboxes found in {MAILBOX_CSV}.")

	token_provider = TokenProvider(TENANT_ID, CLIENT_ID, CLIENT_SECRET)
	logger_instance.info("Acquiring Graph and Exchange Admin API tokens.")
	token_provider.get(GRAPH_SCOPE)
	token_provider.get(ADMIN_API_SCOPE)

	def worker(mailbox, index, total):
		return process_mailbox(mailbox, index, total, token_provider)

	outcomes, failures = run_mailbox_workers(
		mailboxes, worker, MAX_WORKERS, logger_instance
	)
	rows = []
	error_count = 0
	for _, mailbox_rows, mailbox_errors in outcomes:
		rows.extend(mailbox_rows)
		error_count += mailbox_errors
	for mailbox, error in failures:
		error_count += 1
		rows.append({
			"Mailbox": mailbox,
			"FolderPath": "",
			"FolderName": "",
			"User": "",
			"AccessRights": "",
			"SharingPermissionFlags": "",
			"IsValid": "",
			"Status": "Failed",
			"Error": str(error),
		})

	write_csv(OUTPUT_CSV, RESULT_FIELDS, rows, logger_instance)
	logger_instance.info(
		"Inventory complete: %d mailbox(es), %d permission row(s), %d error(s).",
		len(mailboxes),
		len(rows),
		error_count,
	)
	return 1 if error_count else 0


if __name__ == "__main__":
	run_script(main, DEBUG_LOGGING)