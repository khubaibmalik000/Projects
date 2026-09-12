import json
import os
import sys

import boto3
import pytest
from moto import mock_aws

os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-1")
os.environ.setdefault("AWS_ACCESS_KEY_ID", "testing")
os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "testing")
os.environ.setdefault("AWS_SECURITY_TOKEN", "testing")
os.environ.setdefault("AWS_SESSION_TOKEN", "testing")
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

import handler  # noqa: E402


@pytest.fixture
def aws(monkeypatch):
    monkeypatch.setenv("TABLE_NAME", "test-table")
    with mock_aws():
        s3 = boto3.client("s3", region_name="us-east-1")
        s3.create_bucket(Bucket="test-bucket")

        dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
        table = dynamodb.create_table(
            TableName="test-table",
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
        table.wait_until_exists()
        yield s3, table


def test_valid_json_records_are_written(aws):
    s3, table = aws
    payload = [
        {"id": "1", "event_type": "login", "timestamp": "2026-01-01T00:00:00Z"},
        {"id": "2", "event_type": "logout", "timestamp": "2026-01-01T00:05:00Z"},
    ]
    s3.put_object(Bucket="test-bucket", Key="raw/events.json", Body=json.dumps(payload).encode())

    summary = handler.process_object("test-bucket", "raw/events.json", "test-table")

    assert summary == {"bucket": "test-bucket", "key": "raw/events.json", "total": 2, "written": 2, "invalid": 0}
    items = table.scan()["Items"]
    assert {item["id"] for item in items} == {"1", "2"}
    assert all("ingested_at" in item and item["source_key"] == "raw/events.json" for item in items)


def test_single_json_object_is_wrapped_in_a_list(aws):
    s3, table = aws
    payload = {"id": "5", "event_type": "click", "timestamp": "2026-01-01T00:00:00Z"}
    s3.put_object(Bucket="test-bucket", Key="raw/single.json", Body=json.dumps(payload).encode())

    summary = handler.process_object("test-bucket", "raw/single.json", "test-table")

    assert summary["written"] == 1


def test_csv_records_are_parsed_and_written(aws):
    s3, table = aws
    csv_body = "id,event_type,timestamp\n3,click,2026-01-01T00:10:00Z\n"
    s3.put_object(Bucket="test-bucket", Key="raw/events.csv", Body=csv_body.encode())

    summary = handler.process_object("test-bucket", "raw/events.csv", "test-table")

    assert summary["written"] == 1
    items = table.scan()["Items"]
    assert items[0]["id"] == "3"


def test_invalid_records_are_quarantined_not_written(aws):
    s3, table = aws
    payload = [{"id": "1", "event_type": "login"}]  # missing timestamp
    s3.put_object(Bucket="test-bucket", Key="raw/bad.json", Body=json.dumps(payload).encode())

    summary = handler.process_object("test-bucket", "raw/bad.json", "test-table")

    assert summary == {"bucket": "test-bucket", "key": "raw/bad.json", "total": 1, "written": 0, "invalid": 1}
    assert table.scan()["Items"] == []

    quarantined = s3.list_objects_v2(Bucket="test-bucket", Prefix="quarantine/")
    assert quarantined["KeyCount"] == 1
    body = json.loads(s3.get_object(Bucket="test-bucket", Key=quarantined["Contents"][0]["Key"])["Body"].read())
    assert body[0]["missing"] == ["timestamp"]


def test_unsupported_extension_raises(aws):
    s3, table = aws
    s3.put_object(Bucket="test-bucket", Key="raw/events.txt", Body=b"whatever")

    with pytest.raises(handler.RecordValidationError):
        handler.process_object("test-bucket", "raw/events.txt", "test-table")


def test_reprocessing_the_same_record_overwrites_not_duplicates(aws):
    s3, table = aws
    payload = [{"id": "1", "event_type": "login", "timestamp": "2026-01-01T00:00:00Z"}]
    s3.put_object(Bucket="test-bucket", Key="raw/events.json", Body=json.dumps(payload).encode())

    handler.process_object("test-bucket", "raw/events.json", "test-table")
    handler.process_object("test-bucket", "raw/events.json", "test-table")  # simulate a retry

    assert len(table.scan()["Items"]) == 1


def test_handler_reads_s3_event_records_and_skips_quarantine_prefix(aws):
    s3, table = aws
    payload = [{"id": "9", "event_type": "signup", "timestamp": "2026-01-01T00:00:00Z"}]
    s3.put_object(Bucket="test-bucket", Key="raw/e.json", Body=json.dumps(payload).encode())

    event = {
        "Records": [
            {"s3": {"bucket": {"name": "test-bucket"}, "object": {"key": "raw/e.json"}}},
            {"s3": {"bucket": {"name": "test-bucket"}, "object": {"key": "quarantine/skip.json"}}},
        ]
    }

    result = handler.handler(event, None)

    assert len(result["processed"]) == 1
    assert result["processed"][0]["key"] == "raw/e.json"
