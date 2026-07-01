# CI/CD Kubernetes Deployment Pipeline

End-to-end CI/CD pipeline templates — implemented for both **Jenkins** and **GitLab CI** — that take a containerized application from commit to a running Kubernetes deployment, deployed via Helm.

## Pipeline stages

```
Checkout → Lint & Unit Tests → Build Image → Security Scan (Trivy) → Push to Registry → Deploy (Helm) → Smoke Test
```

1. **Lint & Unit Tests** — fails fast on code-quality or test regressions before anything is built.
2. **Build Docker Image** — tagged with the build number (Jenkins) or commit SHA (GitLab CI).
3. **Security Scan** — [Trivy](https://github.com/aquasecurity/trivy) scans the built image for HIGH/CRITICAL CVEs; the pipeline fails if any are found.
4. **Push to Registry** — only after the scan passes.
5. **Deploy to Kubernetes** — `helm upgrade --install` against the target namespace, using the chart in `helm/app/`.
6. **Smoke Test** — verifies the rollout actually completed (`kubectl rollout status`) before declaring success.

## Files

| File | Purpose |
|---|---|
| `Jenkinsfile` | Declarative Jenkins pipeline implementing the stages above, with a `DEPLOY_ENV` build parameter (dev/staging/prod). |
| `.gitlab-ci.yml` | Equivalent GitLab CI pipeline, with the deploy stage gated behind a manual approval (`when: manual`) for production. |
| `helm/app/` | A minimal, generic Helm chart (Deployment, Service, HorizontalPodAutoscaler) that either pipeline deploys. |

## Configuration

Both pipelines expect these to be set as CI credentials/variables (never hardcoded):

| Name | Where | Purpose |
|---|---|---|
| `registry-credentials` (Jenkins) / `REGISTRY_USER` + `REGISTRY_PASSWORD` (GitLab) | Credential store / CI/CD variables | Docker registry login |
| `kubeconfig-cred` (Jenkins) / cluster connected via GitLab Kubernetes integration | Credential store | Cluster access for `helm`/`kubectl` |

Update `REGISTRY` and `IMAGE_NAME` at the top of each pipeline file to point at your actual registry.

## Helm chart

`helm/app` is intentionally generic — swap in your own image, and adjust `values.yaml` (replica count, resource limits, probe paths, autoscaling thresholds) per environment via `--set` flags or a values override file per environment.

```bash
helm upgrade --install app helm/app \
  --namespace dev --create-namespace \
  --set image.repository=your-registry.example.com/app \
  --set image.tag=v1.2.3
```

## Requirements

- Jenkins with the Docker, Kubernetes CLI, and Credentials Binding plugins — or a GitLab Runner with Docker-in-Docker enabled
- `helm`, `kubectl`, `trivy` available on the runner/agent
