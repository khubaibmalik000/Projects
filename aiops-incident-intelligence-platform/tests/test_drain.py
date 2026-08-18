from __future__ import annotations

from datetime import datetime, timedelta

from aiops.logs.drain import LogTemplateMiner
from aiops.logs.parser import classify_severity, mask_variables


def _ts(i: int) -> datetime:
    return datetime(2026, 1, 1) + timedelta(seconds=i)


def test_mask_variables_replaces_numbers_ips_and_uuids():
    masked = mask_variables(
        "connect to 10.0.0.5 failed after 4321ms id=550e8400-e29b-41d4-a716-446655440000"
    )
    assert "10.0.0.5" not in masked
    assert "4321" not in masked
    assert "550e8400" not in masked
    assert "<*>" in masked


def test_classify_severity_keywords():
    assert classify_severity("everything is fine") == "info"
    assert classify_severity("connection retrying in 5s") == "warning"
    assert classify_severity("ERROR: request failed") == "error"
    assert classify_severity("FATAL: out of memory") == "critical"


def test_repeated_messages_collapse_to_one_template():
    miner = LogTemplateMiner()
    events = [
        miner.add_log_message(f"request completed status=200 duration_ms={n}", _ts(n))
        for n in range(50)
    ]
    assert events[0].is_new_template is True
    assert all(not e.is_new_template for e in events[1:])
    assert len({e.cluster_id for e in events}) == 1
    assert events[-1].occurrence_count == 50


def test_distinct_structures_get_distinct_templates():
    miner = LogTemplateMiner()
    e1 = miner.add_log_message("request completed status=200 duration_ms=12", _ts(0))
    e2 = miner.add_log_message("ERROR upstream payments-api timed out after 500ms", _ts(1))
    assert e1.cluster_id != e2.cluster_id
    assert miner.template_count == 2


def test_new_error_pattern_is_flagged_new_then_stops_being_new():
    miner = LogTemplateMiner()
    for i in range(20):
        miner.add_log_message(f"healthcheck ok uptime_s={i}", _ts(i))

    first_error = miner.add_log_message("ERROR connection to db-primary refused", _ts(20))
    second_error = miner.add_log_message("ERROR connection to db-primary refused", _ts(21))

    assert first_error.is_new_template is True
    assert second_error.is_new_template is False
    assert second_error.occurrence_count == 2


def test_template_masks_the_variable_position():
    miner = LogTemplateMiner()
    miner.add_log_message("cache hit key=session:111", _ts(0))
    event = miner.add_log_message("cache hit key=session:222", _ts(1))
    assert "<*>" in event.template
    assert event.is_new_template is False
