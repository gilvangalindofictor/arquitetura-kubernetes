# =============================================================================
# Linkerd mTLS Phase 2 — PROD (Fase 6a)
# ServerPolicy enforcement for mTLS across platform namespaces
# GAP-011 Phase 2: BACEN BCB 85/2021 Compliance
#
# Prerequisites (all must be TRUE before enabling):
#   1. Linkerd control plane running (modules/linkerd deployed in staging)
#   2. Linkerd proxy injection enabled on target namespaces
#   3. All workloads restarted to inject Linkerd sidecars
#   4. Verify meshed pods: linkerd viz stat deploy -n <namespace>
#
# Rollout order:
#   1. staging first (validate no breaking changes)
#   2. prod second (after 48h staging soak)
#
# CAUTION: Enabling mTLS enforcement on a namespace where workloads are NOT
#          meshed (no Linkerd sidecar) will BLOCK all traffic to those pods.
#          Always verify with `linkerd check --proxy` before applying.
# =============================================================================

module "linkerd_mtls_prod" {
  source = "../../modules/linkerd-mtls"

  environment = "prod"

  # Namespaces where mTLS ServerPolicy is enforced
  # Add namespaces here ONLY after verifying all pods are meshed
  mtls_namespaces = [
    "prod-platform-argocd",       # Fase 1 — mTLS ativado 2026-03-24 (100% MESHED verificado)
    "prod-platform-sonarqube",    # Fase 2 — mTLS ativado 2026-03-24 (100% MESHED verificado)
    "prod-platform-harbor",       # FIX-007 — 8 pods, credentials transit (2026-03-25)
    "prod-platform-keycloak",     # FIX-007 — 1 pod, SSO/OIDC tokens (2026-03-25)
    "prod-data-rabbitmq",         # FIX-007 — 3 pods, AMQP message bus (2026-03-25)
    # "prod-platform-gitlab",     # TODO: Enable after GitLab proxy injection verified
    # "prod-security-vault",      # HOLD: Vault + Linkerd chicken-and-egg — requer planejamento especial
    # "prod-observability-monitoring", # HOLD: 0/0 replicas — ativar scaling primeiro
    # "prod-platform-externaldns",    # TODO: Enable after proxy injection verified (1 pod)
    # "prod-data-infrastructure",     # TODO: Enable after proxy injection verified (1 pod)
  ]

  # Policy: all-authenticated = only mTLS-authenticated traffic allowed
  default_policy = "all-authenticated"

  # Allow kubelet probes and ALB health checks on admin ports
  allow_admin_server_access = true
  admin_ports               = [4191, 9990]

  common_tags = local.common_tags
}
