from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from aiops.api.deps import get_db, get_pipeline
from aiops.api.main import app
from aiops.correlation.dependency_graph import ServiceDependencyGraph
from aiops.pipeline import AiopsPipeline
from aiops.remediation.rules import RemediationRule, RemediationRuleBook


@pytest.fixture
def client(session_factory):
    test_pipeline = AiopsPipeline(
        dependency_graph=ServiceDependencyGraph(),
        remediation_rulebook=RemediationRuleBook(
            [RemediationRule(name="page", action="notify_only", match_severity={"critical"})]
        ),
        session_factory=session_factory,
    )

    def _override_pipeline():
        return test_pipeline

    def _override_db():
        session = session_factory()
        try:
            yield session
        finally:
            session.close()

    app.dependency_overrides[get_pipeline] = _override_pipeline
    app.dependency_overrides[get_db] = _override_db
    try:
        yield TestClient(app)
    finally:
        app.dependency_overrides.clear()


def test_health(client):
    resp = client.get("/v1/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_metric_ingest_below_threshold_returns_no_incidents(client):
    resp = client.post("/v1/metrics", json={"entity": "svc", "metric": "cpu", "value": 50.0})
    assert resp.status_code == 200
    assert resp.json() == []


def test_metric_spike_creates_incident_visible_in_list_and_detail(client):
    base_ts = datetime(2026, 1, 1, tzinfo=UTC)
    last_resp = None
    for i in range(25):
        value = 50.0 if i < 20 else 500.0
        last_resp = client.post(
            "/v1/metrics",
            json={
                "entity": "svc",
                "metric": "cpu",
                "value": value,
                "timestamp": (base_ts + timedelta(seconds=i)).isoformat(),
            },
        )
    assert last_resp.status_code == 200
    incidents = last_resp.json()
    assert len(incidents) == 1
    incident_id = incidents[0]["id"]
    assert incidents[0]["severity"] == "critical"

    listed = client.get("/v1/incidents").json()
    assert any(i["id"] == incident_id for i in listed)

    detail = client.get(f"/v1/incidents/{incident_id}")
    assert detail.status_code == 200
    body = detail.json()
    assert body["signals"][0]["entity"] == "svc"
    assert len(body["remediations"]) == 1
    assert body["remediations"][0]["dry_run"] is True


def test_get_unknown_incident_is_404(client):
    resp = client.get("/v1/incidents/INC-does-not-exist")
    assert resp.status_code == 404


def test_log_ingest_with_normal_message_returns_null(client):
    resp = client.post("/v1/logs", json={"entity": "svc", "message": "healthcheck ok"})
    assert resp.status_code == 200
    assert resp.json() is None


def test_topology_endpoint_accepts_edges(client):
    resp = client.post(
        "/v1/topology", json={"edges": [{"upstream": "db", "downstream": "api"}]}
    )
    assert resp.status_code == 204
