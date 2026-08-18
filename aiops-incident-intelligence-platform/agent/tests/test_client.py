from __future__ import annotations

import json
import urllib.error

from aiops_agent.client import ApiClient


class _FakeResponse:
    def __enter__(self):
        return self

    def __exit__(self, *exc_info):
        return False

    def read(self):
        return b"{}"


def test_post_metric_sends_expected_body_and_path(monkeypatch):
    captured = {}

    def fake_urlopen(request, timeout):
        captured["url"] = request.full_url
        captured["body"] = json.loads(request.data)
        captured["content_type"] = request.get_header("Content-type")
        return _FakeResponse()

    monkeypatch.setattr("urllib.request.urlopen", fake_urlopen)

    client = ApiClient("http://localhost:8000")
    client.post_metric("svc", "cpu_percent", 42.5)

    assert captured["url"] == "http://localhost:8000/v1/metrics"
    assert captured["body"] == {"entity": "svc", "metric": "cpu_percent", "value": 42.5}
    assert captured["content_type"] == "application/json"


def test_post_topology_sends_edges(monkeypatch):
    captured = {}

    def fake_urlopen(request, timeout):
        captured["body"] = json.loads(request.data)
        return _FakeResponse()

    monkeypatch.setattr("urllib.request.urlopen", fake_urlopen)

    client = ApiClient("http://localhost:8000")
    client.post_topology([("db", "api"), ("api", "web")])

    assert captured["body"] == {
        "edges": [
            {"upstream": "db", "downstream": "api"},
            {"upstream": "api", "downstream": "web"},
        ]
    }


def test_retries_then_succeeds(monkeypatch):
    attempts = {"count": 0}

    def flaky_urlopen(request, timeout):
        attempts["count"] += 1
        if attempts["count"] < 3:
            raise urllib.error.URLError("connection refused")
        return _FakeResponse()

    sleeps = []
    monkeypatch.setattr("urllib.request.urlopen", flaky_urlopen)
    monkeypatch.setattr("time.sleep", lambda seconds: sleeps.append(seconds))

    client = ApiClient("http://localhost:8000", max_retries=3, backoff_seconds=1.0)
    client.post_log("svc", "hello")

    assert attempts["count"] == 3
    assert sleeps == [1.0, 2.0]  # linear backoff: attempt * backoff_seconds


def test_gives_up_after_max_retries_without_raising(monkeypatch):
    attempts = {"count": 0}

    def always_fails(request, timeout):
        attempts["count"] += 1
        raise urllib.error.URLError("connection refused")

    monkeypatch.setattr("urllib.request.urlopen", always_fails)
    monkeypatch.setattr("time.sleep", lambda seconds: None)

    client = ApiClient("http://localhost:8000", max_retries=2)
    client.post_metric("svc", "cpu_percent", 1.0)  # must not raise

    assert attempts["count"] == 2
