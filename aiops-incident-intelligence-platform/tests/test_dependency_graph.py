from __future__ import annotations

from aiops.correlation.dependency_graph import ServiceDependencyGraph


def test_direct_edge_is_upstream():
    graph = ServiceDependencyGraph([("db", "api")])
    assert graph.is_upstream("db", "api")
    assert not graph.is_upstream("api", "db")


def test_transitive_upstream_within_hop_limit():
    graph = ServiceDependencyGraph([("db", "api"), ("api", "web")])
    assert graph.is_upstream("db", "web", max_hops=2)
    assert not graph.is_upstream("db", "web", max_hops=1)


def test_related_is_symmetric():
    graph = ServiceDependencyGraph([("db", "api")])
    assert graph.related("db", "api")
    assert graph.related("api", "db")


def test_unrelated_services_are_not_related():
    graph = ServiceDependencyGraph([("db", "api"), ("queue", "worker")])
    assert not graph.related("api", "worker")


def test_self_is_always_related_and_upstream():
    graph = ServiceDependencyGraph()
    assert graph.related("solo", "solo")
    assert graph.is_upstream("solo", "solo")
