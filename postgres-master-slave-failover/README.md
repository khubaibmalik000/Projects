# PostgreSQL Master-Slave Failover & Recovery

Scripted PostgreSQL 16 failover: a streaming standby is promoted when the primary goes down, and the old primary is safely rejoined afterward as a standby of the new one — using `pg_rewind` instead of a full re-sync, without risking split-brain.

Two environments, same underlying mechanics (`pg_promote`, `pg_rewind`, `standby.signal`):

| Variant | Use it for | Path |
|---|---|---|
| [**docker-lab**](docker-lab/) | Original, actually-tested lab on two Docker containers (`pg-master` / `pg-slave`) — fast to spin up, good for learning or CI. | `docker-lab/` |
| [**two-node**](two-node/) | Adaptation for two real/virtual Ubuntu hosts over SSH — same steps, real networking, firewalls, and `systemctl`. | `two-node/` |

## Why `pg_rewind` instead of a fresh re-sync

After a failover, the old primary's data directory has diverged from the new primary — it kept accepting local WAL for whatever wasn't yet replicated at crash time. `pg_rewind` finds the last common checkpoint and copies over only the changed data pages, instead of re-copying the entire cluster. It requires the target to have been **cleanly shut down** first, and either `wal_log_hints = on` or data checksums enabled on the source — both variants set `wal_log_hints = on` from the start for exactly this reason.

## The core risk this is designed around

Once a standby is promoted, the old primary cannot simply be restarted and left running — on disk it still believes it's the primary. If anything routes writes to it before it's rejoined as a standby (a stale connection string, an un-failed-over load balancer, a human on the wrong host), both nodes end up accepting writes with no way to reconcile them afterward. Every script in both variants that touches the old primary exists to close that window.

## Production hardening

- Automate with **repmgr** or **Patroni** instead of manual/scripted runbooks for real incident response time — this repo is a reference implementation of the mechanics, not a substitute for a cluster manager.
- Use WAL archiving (pgBackRest/WAL-G) or a generous WAL retention window so WAL isn't recycled before a delayed rejoin can use it.
- Use TLS (`sslmode=verify-full` + real certs) for replication traffic on any real network — the Docker lab's plaintext `md5` auth is lab-only.
- Least-privilege replication role: grant only the specific `pg_rewind` functions, never superuser.
- Restrict `pg_hba.conf` / firewall rules to exact peer IPs — never `0.0.0.0/0` outside an isolated lab.
- Monitor `pg_stat_replication` and lag; alert on WAL receiver disconnects.
- Run the failover drill regularly against staging as a game-day exercise, not just once.
