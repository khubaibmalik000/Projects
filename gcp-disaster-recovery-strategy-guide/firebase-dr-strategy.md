# Firebase Disaster Recovery Strategy (Hot Standby)

A disaster recovery pattern for a Firebase/GCP application stack (Auth, Firestore, Web/Mobile apps, Cloud Functions), built around a **hot-standby project** rather than relying on a single project surviving everything.

## Strategy overview

- The DR environment is a **separate GCP/Firebase project**, built with the same standard infrastructure process used for production — not a manual, one-off setup that would drift over time.
- It's kept as a **hot standby**: ready to receive traffic quickly, not spun up from scratch during an incident.

## Components covered

| Component | Recovery approach |
|---|---|
| Firebase Auth (Users) | Daily backups, restored via automated GitHub workflow |
| Web Apps | Redeployed directly from GitHub on every commit |
| Mobile Apps | Redeployed directly from GitHub on every commit |
| Firestore | Multi-region deployment (`nam5`) + daily backups restorable from GCS |
| Cloud Functions | Redeployed directly from GitHub on every commit |

## Why source-controlled redeploy, not image/snapshot restore

Web apps, mobile apps, and Cloud Functions are **redeployed straight from the GitHub repository** rather than restored from a stored artifact. Since every commit already triggers a build/deploy in the normal pipeline, the DR project can be brought up to the latest known-good state using the exact same process used for day-to-day deploys — no separate DR-specific deployment tooling to maintain or let go stale.

## Firestore

Firestore already runs in a **multi-region configuration (`nam5`)**, which gives it built-in resilience to a single-region outage at the database layer. On top of that:

- **Daily backups** are taken and stored in GCS.
- Restore procedures exist to rebuild Firestore state from those backups if needed (e.g., recovering from data corruption or accidental deletion, not just a regional outage).

## Firebase Auth (Users)

User accounts are **backed up daily** and can be restored through the same automated GitHub workflows used elsewhere in the pipeline — keeping the recovery path consistent with how the team already operates, rather than a separate manual runbook.

## Backup frequency

| Component | Frequency |
|---|---|
| Web Apps / Mobile Apps / Cloud Functions | On every commit |
| Firestore | Daily |
| Firebase Users (Auth) | Daily |

## Manual step: custom domains

Custom domains are the one piece that **can't be fully automated** in this strategy — DNS validation and SSL certificate reconfiguration for custom domains must be done manually during a real recovery, since domain ownership verification is inherently tied to DNS control and can't be pre-provisioned on the standby project without pointing production traffic at it prematurely.

## Recommendations for DR readiness

A DR plan that's never tested isn't a DR plan — it's a hope. To keep this actually usable in an incident:

- **Recovery testing** — periodically exercise the actual restore/redeploy process, not just review the plan on paper.
- **Monitoring** on both the primary and standby projects, so a failure is detected quickly enough for the DR window to matter.
- **IAM-based access control** on the standby project, scoped the same way as production — a DR environment with looser permissions is a security gap, not a shortcut.
- **Credential rotation** for any service accounts/API keys used by the standby, on the same cadence as production.
- **DR runbooks** — written, step-by-step recovery procedures, not tribal knowledge.
- **Regular DR drills** — scheduled fire-drills that actually fail over to the standby, so the team (and the automation) is proven to work before it's needed for real.
