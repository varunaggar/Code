import os
import random
import threading
from pathlib import Path

from mailbox_permissions_common import (
	ADMIN_API_BASE,
	ADMIN_API_SCOPE,
	GRAPH_SCOPE,
	TokenProvider,
	admin_api_post,
	create_session,
	folder_permission_request,
	get_folder_permissions,
	list_mailbox_folders,
	load_addresses,
	logger,
	permission_exists,
	run_mailbox_workers,
	run_script,
	write_csv,
)


# Script configuration.
SCRIPT_DIR = Path(__file__).resolve().parent
MAILBOX_CSV = SCRIPT_DIR / "Mailboxes.csv"
USER_CSV = SCRIPT_DIR / "Userlist.csv"
OUTPUT_CSV = SCRIPT_DIR / "MailboxFolderPermissionResults.csv"
TENANT_ID = os.environ.get("TENANT_ID", "")
CLIENT_ID = os.environ.get("CLIENT_ID", "")
CLIENT_SECRET = os.environ.get("CLIENT_SECRET", "")
MAX_WORKERS = 4
MAX_RETRIES = 5
REQUEST_TIMEOUT = 30
INCLUDE_HIDDEN_FOLDERS = True
RANDOM_SEED = None
DEBUG_LOGGING = False
EXECUTE_CHANGES = False
CONFIRM_PERMISSION_CHANGES = False

ACCESS_RIGHTS = (
	"Owner",
	"PublishingEditor",
	"Editor",
	"PublishingAuthor",
	"Author",
	"NonEditingAuthor",
	"Reviewer",
	"Contributor",
)
RESULT_FIELDS = (
	"Mailbox",
	"FolderPath",
	"User",
	"AccessRights",
	"Action",
	"Status",
	"Error",
)


def make_plan(mailboxes, users, rng):
	user_positions = {}
	for index, user in enumerate(users):
		user_positions.setdefault(user.casefold(), index)

	assignments = []
	skipped = []
	for mailbox in mailboxes:
		mailbox_index = user_positions.get(mailbox.casefold())
		if mailbox_index is None:
			skipped.append({
				"Mailbox": mailbox,
				"FolderPath": "",
				"User": "",
				"AccessRights": "",
				"Action": "SelectUsers",
				"Status": "Skipped",
				"Error": "Mailbox was not found in Userlist.csv.",
			})
			continue

		selected_users = users[mailbox_index + 1:mailbox_index + 3]
		if len(selected_users) != 2 or len({user.casefold() for user in selected_users}) != 2:
			skipped.append({
				"Mailbox": mailbox,
				"FolderPath": "",
				"User": "",
				"AccessRights": "",
				"Action": "SelectUsers",
				"Status": "Skipped",
				"Error": "Two distinct users do not follow this mailbox in Userlist.csv.",
			})
			continue

		selected_rights = rng.sample(ACCESS_RIGHTS, 2)
		assignments.append({
			"Mailbox": mailbox,
			"Assignments": [
				{"User": user, "AccessRight": right}
				for user, right in zip(selected_users, selected_rights)
			],
		})
	return assignments, skipped


def process_mailbox(mailbox_plan, mailbox_index, mailbox_count, token_provider):
	mailbox = mailbox_plan["Mailbox"]
	assignments = mailbox_plan["Assignments"]
	worker = threading.current_thread().name
	results = []
	error_count = 0
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
			for assignment in assignments:
				results.append({
					"Mailbox": mailbox,
					"FolderPath": "",
					"User": assignment["User"],
					"AccessRights": assignment["AccessRight"],
					"Action": "ListFolders",
					"Status": "Failed",
					"Error": str(error),
				})
			return worker, mailbox, results, len(assignments)

		if not folders:
			for assignment in assignments:
				results.append({
					"Mailbox": mailbox,
					"FolderPath": "",
					"User": assignment["User"],
					"AccessRights": assignment["AccessRight"],
					"Action": "ListFolders",
					"Status": "NoFoldersFound",
					"Error": "Graph returned no mailbox folders.",
				})
			return worker, mailbox, results, 0

		for folder_index, folder in enumerate(folders, start=1):
			identity = f"{mailbox}:{folder['path']}"
			logger.info(
				"Worker %s checking folder %d/%d: %s",
				worker,
				folder_index,
				len(folders),
				identity,
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
			except Exception as error:
				error_count += len(assignments)
				logger.exception("Could not read permissions for %s.", identity)
				for assignment in assignments:
					results.append({
						"Mailbox": mailbox,
						"FolderPath": folder["path"],
						"User": assignment["User"],
						"AccessRights": assignment["AccessRight"],
						"Action": "Get-MailboxFolderPermission",
						"Status": "Failed",
						"Error": str(error),
					})
				continue

			for assignment in assignments:
				user = assignment["User"]
				access_right = assignment["AccessRight"]
				exists = permission_exists(permissions, user)
				cmdlet = (
					"Set-MailboxFolderPermission"
					if exists
					else "Add-MailboxFolderPermission"
				)
				status = "WouldUpdate" if exists else "WouldAdd"
				error_message = ""

				if EXECUTE_CHANGES:
					body = folder_permission_request(cmdlet, identity, user, access_right)
					try:
						admin_api_post(
							session,
							token_provider,
							mailbox,
							TENANT_ID,
							f"{ADMIN_API_BASE}/adminapi/v2.0/{TENANT_ID}/MailboxFolderPermission",
							body,
							MAX_RETRIES,
							REQUEST_TIMEOUT,
							logger,
						)
						status = "Success"
					except Exception as error:
						status = "Failed"
						error_count += 1
						error_message = str(error)
						logger.exception("%s failed for %s -> %s.", cmdlet, identity, user)
				else:
					logger.info(
						"Preview: %s %s -> %s (%s).",
						cmdlet,
						identity,
						user,
						access_right,
					)

				results.append({
					"Mailbox": mailbox,
					"FolderPath": folder["path"],
					"User": user,
					"AccessRights": access_right,
					"Action": cmdlet,
					"Status": status,
					"Error": error_message,
				})

	logger.info(
		"Worker %s completed %s: %d result row(s), %d error(s).",
		worker,
		mailbox,
		len(results),
		error_count,
	)
	return worker, mailbox, results, error_count


def main(logger_instance):
	if not all((TENANT_ID, CLIENT_ID, CLIENT_SECRET)):
		raise RuntimeError(
			"Set TENANT_ID, CLIENT_ID, and CLIENT_SECRET environment variables."
		)
	if MAX_WORKERS < 1:
		raise ValueError("MAX_WORKERS must be at least 1.")
	if EXECUTE_CHANGES and not CONFIRM_PERMISSION_CHANGES:
		raise RuntimeError(
			"Set CONFIRM_PERMISSION_CHANGES = True before enabling EXECUTE_CHANGES."
		)

	mailboxes = load_addresses(MAILBOX_CSV, logger_instance)
	users = load_addresses(USER_CSV, logger_instance)
	if not mailboxes:
		raise ValueError(f"No mailboxes found in {MAILBOX_CSV}.")
	if not users:
		raise ValueError(f"No users found in {USER_CSV}.")

	rng = random.Random(RANDOM_SEED) if RANDOM_SEED is not None else random.SystemRandom()
	assignments, results = make_plan(mailboxes, users, rng)
	for mailbox_plan in assignments:
		chosen = ", ".join(
			f"{item['User']}={item['AccessRight']}"
			for item in mailbox_plan["Assignments"]
		)
		logger_instance.info("Planned %s: %s", mailbox_plan["Mailbox"], chosen)
	for skipped in results:
		logger_instance.warning("Skipping %s: %s", skipped["Mailbox"], skipped["Error"])

	if not assignments:
		write_csv(OUTPUT_CSV, RESULT_FIELDS, results, logger_instance)
		logger_instance.warning("No mailbox assignments are eligible for processing.")
		return 1

	token_provider = TokenProvider(TENANT_ID, CLIENT_ID, CLIENT_SECRET)
	logger_instance.info("Acquiring Graph and Exchange Admin API tokens.")
	token_provider.get(GRAPH_SCOPE)
	token_provider.get(ADMIN_API_SCOPE)

	def worker(mailbox_plan, index, total):
		return process_mailbox(
			mailbox_plan,
			index,
			total,
			token_provider,
		)

	outcomes, failures = run_mailbox_workers(
		assignments, worker, MAX_WORKERS, logger_instance
	)
	error_count = 0
	for _, mailbox_rows, mailbox_errors in outcomes:
		results.extend(mailbox_rows)
		error_count += mailbox_errors
	for mailbox_plan, error in failures:
		error_count += len(mailbox_plan["Assignments"])
		for assignment in mailbox_plan["Assignments"]:
			results.append({
				"Mailbox": mailbox_plan["Mailbox"],
				"FolderPath": "",
				"User": assignment["User"],
				"AccessRights": assignment["AccessRight"],
				"Action": "Worker",
				"Status": "Failed",
				"Error": str(error),
			})

	write_csv(OUTPUT_CSV, RESULT_FIELDS, results, logger_instance)
	failure_count = sum(result.get("Status") == "Failed" for result in results)
	logger_instance.info(
		"Completed in %s mode: %d row(s), %d failure(s), %d skipped mailbox(es).",
		"execute" if EXECUTE_CHANGES else "preview",
		len(results),
		failure_count,
		sum(result.get("Status") == "Skipped" for result in results),
	)
	return 1 if failure_count else 0


if __name__ == "__main__":
	run_script(main, DEBUG_LOGGING)