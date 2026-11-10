# M365 Advanced Hunting to Fabric

This guide explains [`m365_hunting_to_fabric.py`](m365_hunting_to_fabric.py) in source order. Blank lines are only for readability; each code section below explains the statements that do the work.

## What It Does

The module obtains an app-only Microsoft Graph token, submits a Defender Advanced Hunting KQL query for Exchange Online mailbox-folder permission additions, normalizes the results, and appends them to a Delta table in the notebook's attached Fabric Lakehouse.

## Module Docstring

The opening triple-quoted text describes the module and its prerequisites. It says to run the code from a Fabric notebook with a Lakehouse attached, configure `M365_TENANT_ID`, `M365_CLIENT_ID`, and `M365_CLIENT_SECRET` through secret management, and call `load_hunting_events(spark)`. It also names the required Microsoft Graph application permission: `ThreatHunting.Read.All`, with admin consent.

## Imports

- `json` parses and serializes the dynamic `RawEventData` value.
- `logging` writes progress messages without printing token values or event contents.
- `os` reads settings from environment variables.
- `time` pauses between retry attempts.
- `datetime` and `timezone` parse timestamps and normalize them to UTC.
- `Any` allows helper parameters to accept the varying JSON values returned by the API.
- `msal` implements the Microsoft Entra confidential-client token flow.
- `requests` sends the HTTP request to Microsoft Graph.
- `SparkSession` describes the Fabric Spark session passed to the loader.
- The Spark SQL type classes define the explicit schema used to create the DataFrame.

## Endpoint, Scope, and KQL

`GRAPH_HUNTING_URL` is the Microsoft Graph v1.0 `security/runHuntingQuery` endpoint. `GRAPH_SCOPE` requests the Graph `.default` scope, which asks Entra ID to issue a token containing the application's already-consented Graph application permissions.

`KQL_QUERY` is a multiline KQL string:

1. `CloudAppEvents` selects the Defender activity table.
2. The `Application` filter keeps events attributed to `Microsoft Exchange Online`.
3. The `ActionType` filter keeps only `Add-MailboxFolderPermission` events.
4. `project` limits the result columns to timestamp, application, action, object, account, and raw event data.
5. `order by Timestamp desc` sorts newest events first.
6. `take 100000` caps the returned rows after sorting, preserving the newest rows if the cap is reached.

The API uses a default 30-day query window because this query does not specify a `Timespan` or a timestamp filter.

## `EVENT_SCHEMA`

`StructType([...])` describes the columns Spark should create and their order. Each `StructField` has a name, Spark type, and nullable flag:

- `timestamp` uses `TimestampType`.
- `application`, `action_type`, `object_name`, and `account_id` use `StringType`.
- `raw_event_data_json` stores the dynamic event payload as JSON text, also using `StringType`.
- The final `True` on each field permits null values, which can occur in API results.

Providing a schema makes the DataFrame's shape explicit instead of relying on Spark to infer it from the response data.

## `_required_setting`

The function takes an environment-variable name and retrieves its value with `os.getenv`. If the variable is missing or empty, it raises `ValueError` with the missing name. Otherwise it returns the value. This keeps configuration out of the source file and ensures missing settings fail early.

## `_acquire_graph_token`

1. The first three statements load the tenant ID, application/client ID, and client secret using `_required_setting`.
2. `ConfidentialClientApplication` configures MSAL for the tenant-specific Entra authority and supplies the client ID and secret.
3. `acquire_token_for_client` performs the non-interactive client-credentials flow using `GRAPH_SCOPE`.
4. `result.get("access_token")` retrieves the bearer token if the request succeeded.
5. If there is no token, the function chooses Entra's error description, error code, or a fallback message, then raises `RuntimeError`.
6. On success, the token string is returned to the caller.

The token is only used in memory and is not logged. Keep the secret in a Fabric secret-management integration; do not put it in this file or notebook source.

## `_run_hunting_query`

1. `headers` sets the bearer authorization header and JSON content type.
2. `payload` places the KQL under the Graph API's required `Query` property.
3. `for attempt in range(5)` allows up to five HTTP attempts.
4. `requests.post` sends the query with a 60-second timeout.
5. HTTP 429 responses (throttling) and 5xx responses (server errors) are treated as transient. On the fifth failed attempt, `raise_for_status()` raises the HTTP error.
6. Before retrying, the function reads `Retry-After`. If it is an integer, that value is used; otherwise it uses exponential delays of 1, 2, 4, then 8 seconds. `min(delay, 60)` caps the wait at 60 seconds.
7. For any non-retry response, `raise_for_status()` fails on unsuccessful HTTP status codes.
8. The response JSON is decoded, and its `results` property is checked to ensure it is a list. A malformed response raises `RuntimeError`.
9. Valid result rows are returned as a list of dictionaries. The final empty-list return is a defensive fallback after the retry loop.

This retry logic does not retry authentication failures such as HTTP 401/403, nor other 4xx responses. Those fail immediately so permissions and query errors are visible.

## `_parse_timestamp`

1. An empty or missing timestamp returns `None`.
2. `str(value)` accepts the API's string value, while replacing a trailing `Z` with `+00:00` makes UTC explicit to Python's ISO parser.
3. `datetime.fromisoformat` parses the timestamp.
4. If the parsed value has no timezone, it is treated as UTC.
5. The result is converted to UTC and has its timezone metadata removed. Spark `TimestampType` stores the instant as a timestamp; the session's Spark timezone can affect how timestamps display, so keep the Fabric session timezone in mind when reading results.

## `_serialize_event_data`

1. A `None` payload stays `None`.
2. If the API returned a string, `json.loads` attempts to decode it. If that string is not valid JSON, the original text is retained.
3. `json.dumps` converts either the decoded value or a non-string value to compact JSON text. `ensure_ascii=True` escapes non-ASCII characters, and `default=str` converts otherwise unsupported values to strings.
4. The resulting text is stored in the `raw_event_data_json` column.

## `load_hunting_events`

This is the public entry point and accepts the active Fabric `SparkSession`.

1. Its docstring summarizes the query-and-append behavior.
2. `logging.basicConfig` enables informational logging; `getLogger(__name__)` creates this module's logger.
3. `FABRIC_TABLE` selects the target table. If it is unset, the default is `mailbox_folder_permission_events`.
4. `_acquire_graph_token()` obtains the Graph token, then `_run_hunting_query()` retrieves the event rows.
5. The count is logged. If the results are empty, the function returns `0` and does not create or write a table.
6. The list comprehension converts each API dictionary into a tuple matching `EVENT_SCHEMA`: parsed timestamp, application, action type, object name, account ID, and serialized raw event data. `dict.get` returns `None` when a field is absent.
7. `spark.createDataFrame(records, schema=EVENT_SCHEMA)` creates the Spark DataFrame with the declared types and column names.
8. `write.format("delta").mode("append").saveAsTable(table_name)` appends the rows to a Delta table registered in the attached Lakehouse.
9. The write count and table name are logged, and the function returns the number of rows appended.

## Running It in Fabric

Attach the target Lakehouse to a Fabric notebook, make sure the required Python packages are available (`msal` and `requests`), and configure the three `M365_*` variables using your approved secret-management approach. Then import and call the loader:

```python
from m365_hunting_to_fabric import load_hunting_events

written_count = load_hunting_events(spark)
print(f"Rows appended: {written_count}")
```

If the module is stored as a notebook-attached file, make sure it is on the notebook's Python import path. Fabric already supplies the Spark session as `spark`.

## Required Access

- The Entra app registration must have the Microsoft Graph **application** permission `ThreatHunting.Read.All`, and an administrator must grant consent.
- The app must be allowed to access the relevant Defender Advanced Hunting data.
- The notebook identity/user must have permission to write to the attached Lakehouse.

## Operational Notes

- The query uses Graph's default 30-day time window. Running it repeatedly appends the same historical rows again; this loader does not perform deduplication or an incremental watermark.
- The query keeps at most 100,000 rows, newest first. Narrow the time window or add a filter if you need predictable incremental batches.
- `saveAsTable` writes to the Lakehouse attached as the notebook's default Lakehouse. `FABRIC_TABLE` changes the table name, not the Lakehouse.
- For production use, keep credentials in a managed secret store, restrict the app to the required permission, and consider certificate-based or managed identity authentication where the hosting setup supports it.

## Microsoft References

- [Microsoft Graph: Run Advanced Hunting query](https://learn.microsoft.com/en-us/graph/api/security-security-runhuntingquery?view=graph-rest-1.0)
- [MSAL Python: Client credentials](https://learn.microsoft.com/en-us/entra/msal/python/advanced/client-credentials)
- [Microsoft Fabric: Load data into a Lakehouse with a notebook](https://learn.microsoft.com/en-us/fabric/data-engineering/lakehouse-notebook-load-data?tabs=pyspark)
