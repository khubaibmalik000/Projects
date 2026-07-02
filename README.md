# Projects

A collection of DevOps / infrastructure automation projects — backup pipelines, database maintenance tooling, monitoring/observability stacks, and CI/CD runbooks.

## Contents

| Project | Description |
|---|---|
| [db-slow-query-monitor](db-slow-query-monitor/) | Bash script that reports slow, stuck, and lock-blocked queries on MySQL/MariaDB. |
| [postgres-s3-backup-pipeline](postgres-s3-backup-pipeline/) | WAL archiving + scheduled full/incremental PostgreSQL backups shipped to S3. |
| [mariadb-date-based-cleanup](mariadb-date-based-cleanup/) | Interactive script for safely purging old rows from MariaDB with a preview-then-confirm flow. |
| [k3d-observability-stack](k3d-observability-stack/) | Prometheus + Grafana + Loki + Promtail + Node Exporter deployed on a local k3d cluster, with a synthetic log-generating workload and a custom dashboard. |
| [ansible-node-exporter-installer](ansible-node-exporter-installer/) | Ansible playbook that bulk-installs Node Exporter with Basic Auth across a fleet, using `raw` tasks (no Python required on targets). |
| [node-exporter-bulk-installer](node-exporter-bulk-installer/) | Bash/SSH-loop alternative for installing and securing Node Exporter across servers without a config management tool. |
| [cicd-gitlab-jenkins-sonarqube](cicd-gitlab-jenkins-sonarqube/) | Runbook for a CI/CD pipeline: GitLab triggers Jenkins via webhook, gated by SonarQube quality checks. |
| [mysql-uptime-watchdog](mysql-uptime-watchdog/) | Bash daemon that pings MySQL/MariaDB and sends Telegram alerts on outage/recovery. |
| [transcript-count-autoscaler](transcript-count-autoscaler/) | Custom Kubernetes autoscaler that scales a deployment based on a MySQL backlog count instead of CPU/memory. |
| [rustdesk-docker-server](rustdesk-docker-server/) | Self-hosted RustDesk remote-desktop server (ID/relay + web admin console) via Docker Compose. |
| [terraform-aws-eks-platform](terraform-aws-eks-platform/) | Modular Terraform IaC provisioning a production-grade AWS EKS platform (VPC/IAM/EKS modules, dev/prod environments, remote state), validated by CI on every push. |
| [cicd-k8s-deployment-pipeline](cicd-k8s-deployment-pipeline/) | Jenkins + GitLab CI pipelines that build, scan, and deploy a containerized app to Kubernetes via Helm. |
| [gcp-disaster-recovery-strategy-guide](gcp-disaster-recovery-strategy-guide/) | Reference docs on Cloud SQL HA vs. cross-region DR tradeoffs, and a hot-standby DR strategy for a Firebase application stack. |

Each project folder has its own README with setup and usage details.
