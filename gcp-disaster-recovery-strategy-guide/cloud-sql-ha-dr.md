# Cloud SQL: High Availability vs. Disaster Recovery

A practical breakdown of how Cloud SQL's High Availability (HA) and Disaster Recovery (DR) mechanisms actually behave under failure — and why they solve different problems.

## Zonal HA (same region)

Cloud SQL HA runs a **primary and a standby instance in different zones within the same region**, connected by **synchronous disk replication** — every write is confirmed on both zones before it's acknowledged.

- **Failover is automatic** if the zone hosting the primary fails.
- Because replication is synchronous, the standby is always caught up — no data loss on zonal failover.

### Failover impact (RTO)

Recovery time isn't fixed — it depends on what has to be replayed during failover:

- **Uncommitted transactions** at the moment of failure need to be resolved.
- **Pending schema changes** (DDL) can extend recovery time.
- **High write throughput** at the time of failure means more in-flight work to reconcile — so recovery is slower under heavy write load than at idle.

## Regional DR (cross-region read replicas)

Cross-region replicas use **asynchronous replication** — writes are acknowledged on the primary before they're confirmed on the replica. This is what makes cross-region replication practical (synchronous replication across regions would add too much write latency), but it has a direct consequence:

- **Replicas always carry some replication lag.** This is not a failure state — it's inherent to asynchronous replication.
- **Higher TPS (transactions per second) → more lag.** If the primary is under heavy write load, the replica falls further behind before it catches up.

### Replication lag risk

Lag directly drives two DR metrics:

| Metric | What lag does to it |
|---|---|
| **RPO** (Recovery Point Objective — how much data you can afford to lose) | Higher lag = more recent writes missing from the replica if you fail over = higher potential data loss |
| **RTO** (Recovery Time Objective — how long recovery takes) | The replica may need to catch up or be reconciled before it's safe to promote, adding time |

### Regional failover is manual, and riskier

Unlike zonal HA, cross-region failover is **not automatic**:

1. An operator must **manually promote the replica** to become the new primary.
2. If the old primary comes back online after a promotion (e.g., a region "failure" that was actually a transient network partition), you can end up with **two primaries accepting writes — a split-brain scenario** — leading to data inconsistency that has to be manually reconciled.
3. **After promotion, every application/service must be manually redirected** (connection strings, DNS, config) to the new primary. There's no automatic traffic cutover.

## Key takeaway

| | HA (zonal) | DR (regional) |
|---|---|---|
| Replication | Synchronous | Asynchronous |
| Failover | Automatic | Manual promotion |
| Data loss on failover | None | Possible (depends on lag) |
| Scope | Survives a zone outage | Survives a full region outage |
| Speed | Fast | Slower, more operational overhead |

**HA** is fast, automatic, and scoped to a single region — it protects against a zone failure.
**DR** protects against losing an entire region, but is slower, requires a manual decision to promote, and carries real data-consistency risk if not executed carefully.

### For stronger consistency guarantees

If cross-region **synchronous** replication with automatic failover and no split-brain risk is a hard requirement, **Cloud Spanner** is the better fit — it's designed for globally consistent, horizontally scalable transactions with automatic multi-region failover, at the cost of a different (and pricier) operating model than Cloud SQL.
