# GCP Disaster Recovery Strategy Guide

Reference documentation on high-availability and disaster-recovery design for two common GCP-based stacks: a **Cloud SQL** relational database, and a full **Firebase** application stack (Auth, Firestore, Web/Mobile apps, Cloud Functions).

## Contents

- **[cloud-sql-ha-dr.md](cloud-sql-ha-dr.md)** — How Cloud SQL's zonal HA (synchronous, automatic failover) differs from cross-region DR (asynchronous, manual promotion), what drives RTO/RPO in each case, the split-brain risk of manual regional failover, and when to reach for Cloud Spanner instead.
- **[firebase-dr-strategy.md](firebase-dr-strategy.md)** — A hot-standby DR pattern for Firebase: a separate GCP project built via the standard infra process, source-controlled redeploy for app code/functions, Firestore multi-region + backup strategy, Auth backup/restore, and the operational practices (testing, monitoring, IAM, credential rotation, runbooks, drills) needed to keep a DR plan actually usable.

## Why this matters

HA and DR are often conflated, but they answer different questions:

- **HA** — "can we survive losing a zone, automatically, in seconds?"
- **DR** — "can we survive losing an entire region, and how much data/time do we lose doing it?"

Designing for one doesn't automatically give you the other — these docs lay out the tradeoffs (consistency vs. latency, automatic vs. manual failover, cost vs. recovery speed) so the right mechanism gets chosen deliberately, not by default.
