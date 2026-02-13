## Current State (2026-02-13)

Last Updated: 2026-02-13

### SSO Smoke Test Results (Final)

**Score: 39 PASSED / 0 FAILED / 5 SKIPPED**

Script: `scripts/sso-smoke-test.sh`

### Bloqueadores Conhecidos

1) Security Groups Dependencies (T5) — RESOLVIDO
   - Status: RESOLVIDO (2026-02-13)
   - Notes: 10/10 SGs cleaned up; see `docs/logbook/2026-02-13-security-groups-cleanup-completion.md` and related changes.

2) Keycloak 2a replica (CPU) — RESOLVIDO (staging behavior accepted)
   - Status: RESOLVIDO for now in staging (replicas kept at 1), startup race fixed via initContainer + startupProbe + health flag. See `docs/logbook/2026-02-13-keycloak-startup-fix.md` and `k8s/patches/keycloak-startup-fix.yaml`.

3) Prometheus Operator pending on system nodes — RESOLVIDO
   - Status: RESOLVIDO (2026-02-09) — ADR-042 applied; system node capacity increased; tolerations standardized.

4) CoreDNS DNS Mismatch — RESOLVIDO
   - Status: RESOLVIDO (2026-02-13)
   - Fix: CoreDNS ConfigMap patched — `keycloak.staging.internal` → `keycloak-keycloakx-http.keycloak.svc.cluster.local`

5) Redis AUTH Mismatch — RESOLVIDO
   - Status: RESOLVIDO (2026-02-13)
   - Root cause: SpotaHome→OT-Container-Kit migration drift (7-step fix chain)
   - Fix: Redis CR patched (redisSecret, image, UID, PSS), Operator RBAC patched, TF module rewritten

6) Vault/ExternalSecret (EBS Volume Loss) — RESOLVIDO
   - Status: RESOLVIDO (2026-02-13)
   - Root cause: 3/3 EBS volumes deleted outside K8s lifecycle
   - Fix: Vault reinitialized (KMS auto-unseal), KV v2 + K8s auth configured, secrets seeded

### Known Issues (nao bloqueadores)

- Cluster capacity insuficiente: GitLab webservice 1/3 Running (2 Pending), Vault 1/3
- GitLab Runner: CrashLoopBackOff
- CoreDNS ConfigMap: nao codificado em Terraform (drift risk)
- Terraform state: `terraform state mv` necessario para Redis resources

### Notes
- The Keycloak cluster now reports the health endpoint `/auth/health/ready` as `UP` and the immediate restart loop observed earlier has stopped.
- Pending: persist the `values.yaml.tpl` changes via Terraform (`modules/keycloak`) so future Terraform deploys don't revert the runtime patch.
- Redis operator: OT-Container-Kit v0.23.0, image `quay.io/opstree/redis:v8.4.0`, AUTH enabled, PSS restricted compliant
- Vault: KV v2 at `secret/`, K8s auth for ESO, ClusterSecretStore Ready, ExternalSecret synced
