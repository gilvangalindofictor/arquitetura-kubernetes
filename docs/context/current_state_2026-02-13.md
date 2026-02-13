## Current State (2026-02-13)

Last Updated: 2026-02-13

Bloqueadores Conhecidos

1) Security Groups Dependencies (T5) — RESOLVIDO
   - Status: RESOLVIDO (2026-02-13)
   - Notes: 10/10 SGs cleaned up; see `docs/logbook/2026-02-13-security-groups-cleanup-completion.md` and related changes.

2) Keycloak 2a replica (CPU) — RESOLVIDO (staging behavior accepted)
   - Status: RESOLVIDO for now in staging (replicas kept at 1), startup race fixed via initContainer + startupProbe + health flag. See `docs/logbook/2026-02-13-keycloak-startup-fix.md` and `k8s/patches/keycloak-startup-fix.yaml`.

3) Prometheus Operator pending on system nodes — RESOLVIDO
   - Status: RESOLVIDO (2026-02-09) — ADR-042 applied; system node capacity increased; tolerations standardized.

Notes
- The Keycloak cluster now reports the health endpoint `/auth/health/ready` as `UP` and the immediate restart loop observed earlier has stopped.
- Pending: persist the `values.yaml.tpl` changes via Terraform (`modules/keycloak`) so future Terraform deploys don't revert the runtime patch.
