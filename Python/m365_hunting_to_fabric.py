"""Load Exchange mailbox-folder permission events into a Fabric Lakehouse.

Run from a Fabric notebook with a Lakehouse attached and a Spark session
available. Set M365_TENANT_ID, M365_CLIENT_ID, and M365_CLIENT_SECRET using
the notebook's secret-management integration before calling
load_hunting_events(spark). The app registration needs the Microsoft Graph
application permission ThreatHunting.Read.All with admin consent.
"""

import json
import logging
import os
import time
from datetime import datetime, timezone
from typing import Any

import msal
import requests
from pyspark.sql import SparkSession
from pyspark.sql.types import StringType, StructField, StructType, TimestampType


GRAPH_HUNTING_URL = "https://graph.microsoft.com/v1.0/security/runHuntingQuery"
GRAPH_SCOPE = ["https://graph.microsoft.com/.default"]
KQL_QUERY = """CloudAppEvents
| where Application == 'Microsoft Exchange Online'
| where ActionType == 'Add-MailboxFolderPermission'
| project Timestamp, Application, ActionType, ObjectName, AccountId, RawEventData
| order by Timestamp desc
| take 100000
"""

EVENT_SCHEMA = StructType(
    [
        StructField("timestamp", TimestampType(), True),
        StructField("application", StringType(), True),
        StructField("action_type", StringType(), True),
        StructField("object_name", StringType(), True),
        StructField("account_id", StringType(), True),
        StructField("raw_event_data_json", StringType(), True),
    ]
)


def _required_setting(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise ValueError(f"Required environment variable {name} is not set")
    return value


def _acquire_graph_token() -> str:
    tenant_id = _required_setting("M365_TENANT_ID")
    client_id = _required_setting("M365_CLIENT_ID")
    client_secret = _required_setting("M365_CLIENT_SECRET")

    app = msal.ConfidentialClientApplication(
        client_id=client_id,
        authority=f"https://login.microsoftonline.com/{tenant_id}",
        client_credential=client_secret,
    )
    result = app.acquire_token_for_client(scopes=GRAPH_SCOPE)
    access_token = result.get("access_token")
    if not access_token:
        error = result.get("error_description", result.get("error", "unknown error"))
        raise RuntimeError(f"Microsoft Entra token request failed: {error}")
    return access_token


def _run_hunting_query(access_token: str) -> list[dict[str, Any]]:
    headers = {"Authorization": f"Bearer {access_token}", "Content-Type": "application/json"}
    payload = {"Query": KQL_QUERY}

    for attempt in range(5):
        response = requests.post(
            GRAPH_HUNTING_URL,
            headers=headers,
            json=payload,
            timeout=60,
        )
        if response.status_code == 429 or response.status_code >= 500:
            if attempt == 4:
                response.raise_for_status()
            retry_after = response.headers.get("Retry-After")
            delay = int(retry_after) if retry_after and retry_after.isdigit() else 2**attempt
            time.sleep(min(delay, 60))
            continue

        response.raise_for_status()
        body = response.json()
        results = body.get("results")
        if not isinstance(results, list):
            raise RuntimeError("Advanced Hunting response did not contain a results array")
        return results

    return []


def _parse_timestamp(value: Any) -> datetime | None:
    if not value:
        return None
    parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).replace(tzinfo=None)


def _serialize_event_data(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except json.JSONDecodeError:
            return value
    return json.dumps(value, ensure_ascii=True, separators=(",", ":"), default=str)


def load_hunting_events(spark: SparkSession) -> int:
    """Query Defender and append normalized events to the attached Lakehouse."""
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)
    table_name = os.getenv("FABRIC_TABLE", "mailbox_folder_permission_events")

    access_token = _acquire_graph_token()
    results = _run_hunting_query(access_token)
    logger.info("Advanced Hunting returned %d event(s)", len(results))
    if not results:
        return 0

    records = [
        (
            _parse_timestamp(event.get("Timestamp")),
            event.get("Application"),
            event.get("ActionType"),
            event.get("ObjectName"),
            event.get("AccountId"),
            _serialize_event_data(event.get("RawEventData")),
        )
        for event in results
    ]

    dataframe = spark.createDataFrame(records, schema=EVENT_SCHEMA)
    dataframe.write.format("delta").mode("append").saveAsTable(table_name)
    logger.info("Appended %d event(s) to Fabric table %s", len(records), table_name)
    return len(records)