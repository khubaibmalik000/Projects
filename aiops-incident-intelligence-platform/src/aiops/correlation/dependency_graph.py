"""Directed service dependency graph used to relate anomalies across services.

Edges are ``(upstream, downstream)`` meaning downstream calls/depends on
upstream (e.g. ``("checkout-api", "payments-api")``). Failures typically
propagate upstream -> downstream, so this graph backs both alert
correlation (are two affected services actually connected?) and root-cause
ranking (which affected service sits furthest upstream?).
"""

from __future__ import annotations

from collections import defaultdict, deque


class ServiceDependencyGraph:
    def __init__(self, edges: list[tuple[str, str]] | None = None) -> None:
        self._downstream: dict[str, set[str]] = defaultdict(set)
        self._upstream: dict[str, set[str]] = defaultdict(set)
        for upstream, downstream in edges or []:
            self.add_edge(upstream, downstream)

    def add_edge(self, upstream: str, downstream: str) -> None:
        self._downstream[upstream].add(downstream)
        self._upstream[downstream].add(upstream)

    def is_upstream(self, candidate: str, of: str, max_hops: int = 3) -> bool:
        """True if ``candidate`` reaches ``of`` via downstream edges within max_hops."""
        if candidate == of:
            return True
        return self._bfs(candidate, self._downstream, of, max_hops)

    def related(self, a: str, b: str, max_hops: int = 2) -> bool:
        """True if ``a`` and ``b`` are within ``max_hops`` of each other, either direction."""
        if a == b:
            return True
        return self._bfs(a, self._downstream, b, max_hops) or self._bfs(
            a, self._upstream, b, max_hops
        )

    @staticmethod
    def _bfs(
        start: str, adjacency: dict[str, set[str]], target: str, max_hops: int
    ) -> bool:
        visited = {start}
        frontier = deque([(start, 0)])
        while frontier:
            node, depth = frontier.popleft()
            if depth >= max_hops:
                continue
            for neighbor in adjacency.get(node, ()):
                if neighbor == target:
                    return True
                if neighbor not in visited:
                    visited.add(neighbor)
                    frontier.append((neighbor, depth + 1))
        return False
