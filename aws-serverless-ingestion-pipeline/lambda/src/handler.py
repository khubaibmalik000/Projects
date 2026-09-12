"""S3-triggered Lambda that ingests CSV/JSON event files into DynamoDB.

Flow: S3 ObjectCreated (raw/*) -> download -> parse -> validate each record
-> batch-write valid records to DynamoDB -> write invalid records to a
quarantine/ prefix in the same bucket for later inspection.

Idempotency: DynamoDB writes are keyed on the record's own `id` field, so a
Lambda retry (or S3 redelivering the same event) overwrites the same item
rather than creating a duplicate.
"""

import csv
import io
import json
import logging
import os
from datetime import datetime, timezone
from urllib.parse import unquote_plus

import boto3

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")

REQUIRED_FIELDS = ("id", "event_type", "timestamp")


class RecordValidationError(Exception):
    """Raised when a source file can't be parsed at all (unsupported type, bad encoding, etc.)."""


def _parse_records(body: bytes, key: str) -> list:
    if key.endswith(".json"):
        data = json.loads(body.decode("utf-8"))
        return data if isinstance(data, list) else [data]
    if key.endswith(".csv"):
        text = body.decode("utf-8")
        return list(csv.DictReader(io.StringIO(text)))
    raise RecordValidationError(f"Unsupported file extension for key: {key}")


def _missing_fields(record: dict) -> list:
    return [field for field in REQUIRED_FIELDS if not record.get(field)]


def _to_item(record: dict, source_key: str) -> dict:
    item = dict(record)
    item["source_key"] = source_key
    item["ingested_at"] = datetime.now(timezone.utc).isoformat()
    return item


def _quarantine(bucket: str, key: str, invalid: list) -> str:
    quarantine_key = f"quarantine/{key.rsplit('/', 1)[-1]}.invalid.json"
    s3.put_object(
        Bucket=bucket,
        Key=quarantine_key,
        Body=json.dumps(invalid, default=str).encode("utf-8"),
        ContentType="application/json",
    )
    logger.warning("Wrote %d invalid record(s) from %s to %s", len(invalid), key, quarantine_key)
    return quarantine_key


def process_object(bucket: str, key: str, table_name: str) -> dict:
    response = s3.get_object(Bucket=bucket, Key=key)
    body = response["Body"].read()
    records = _parse_records(body, key)

    table = dynamodb.Table(table_name)
    written = 0
    invalid = []

    with table.batch_writer(overwrite_by_pkeys=["id"]) as batch:
        for record in records:
            missing = _missing_fields(record)
            if missing:
                invalid.append({"record": record, "missing": missing})
                continue
            batch.put_item(Item=_to_item(record, key))
            written += 1

    if invalid:
        _quarantine(bucket, key, invalid)

    summary = {
        "bucket": bucket,
        "key": key,
        "total": len(records),
        "written": written,
        "invalid": len(invalid),
    }
    logger.info("Processed %s", summary)
    return summary


def handler(event, context):  # noqa: ARG001 - context required by the Lambda runtime contract
    table_name = os.environ["TABLE_NAME"]
    results = []

    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = unquote_plus(record["s3"]["object"]["key"])
        if key.startswith("quarantine/"):
            continue  # never re-process our own output
        results.append(process_object(bucket, key, table_name))

    return {"processed": results}
