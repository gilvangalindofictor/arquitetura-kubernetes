#!/bin/bash
# =============================================================================
# create-namespace.sh — Cria Namespace com ResourceQuota + LimitRange + NetworkPolicy
# =============================================================================
# Descricao: Provisiona namespace Kubernetes com todas as governance policies
#            conforme P2 (ResourceQuotas) e ADR-048 (naming/labels).
# Uso:       ./create-namespace.sh --name <ns> --domain <d> --product <p> --env <e> --owner <o>
# Deps:      kubectl
# Idempotente: SIM — usa kubectl apply (check-before-create)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libs
LOG_PREFIX="NAMESPACE"
source "${SCRIPT_DIR}/../lib/common.sh"

# Cleanup
_cleanup() { :; }
register_cleanup _cleanup

# -----------------------------------------------------------------------------
# Parse argumentos
# -----------------------------------------------------------------------------
parse_args() {
    NAMESPACE="" DOMAIN="" PRODUCT="" ENV="" OWNER="" DRY_RUN=false
    SA_NAME="platform-provisioner"
    SA_NAMESPACE="platform-system"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --name)         NAMESPACE="$2"; shift 2 ;;
            --domain)       DOMAIN="$2"; shift 2 ;;
            --product)      PRODUCT="$2"; shift 2 ;;
            --env)          ENV="$2"; shift 2 ;;
            --owner)        OWNER="$2"; shift 2 ;;
            --dry-run)      DRY_RUN=true; shift ;;
            --sa-name)      SA_NAME="$2"; shift 2 ;;
            --sa-namespace) SA_NAMESPACE="$2"; shift 2 ;;
            *) log_error "Opcao desconhecida: $1"; exit 1 ;;
        esac
    done

    validate_required_args NAMESPACE DOMAIN PRODUCT ENV OWNER || exit 1
}

# -----------------------------------------------------------------------------
# Resolver ResourceQuota conforme P2 da mesa tecnica
# -----------------------------------------------------------------------------
resolve_quota() {
    local env="$1" domain="$2"

    # P2: ResourceQuotas por Namespace pattern
    if [[ "$env" == "staging" ]]; then
        if [[ "$domain" == "data" ]]; then
            echo "3 6Gi 6 12Gi 30"       # staging-data-*
        else
            echo "2 4Gi 4 8Gi 30"        # staging-* (padrao)
        fi
    elif [[ "$env" == "prod" ]]; then
        if [[ "$domain" == "data" ]]; then
            echo "8 16Gi 16 32Gi 50"     # prod-data-*
        elif [[ "$domain" == "integration" ]]; then
            echo "6 12Gi 12 24Gi 75"     # prod-integration-*
        else
            echo "4 8Gi 8 16Gi 50"       # prod-* (padrao)
        fi
    else
        echo "2 4Gi 4 8Gi 30"            # fallback
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    parse_args "$@"

    QUOTA_VALUES=$(resolve_quota "$ENV" "$DOMAIN")
    read -r QUOTA_CPU_REQ QUOTA_MEM_REQ QUOTA_CPU_LIM QUOTA_MEM_LIM QUOTA_PODS <<< "$QUOTA_VALUES"

    log_info "Namespace: $NAMESPACE"
    log_info "ResourceQuota P2: CPU req=$QUOTA_CPU_REQ lim=$QUOTA_CPU_LIM, Mem req=$QUOTA_MEM_REQ lim=$QUOTA_MEM_LIM, Pods=$QUOTA_PODS"

    # Check-before-create
    if resource_exists namespace "$NAMESPACE"; then
        log_warn "Namespace $NAMESPACE ja existe — atualizando labels e policies"
    else
        log_info "Criando namespace $NAMESPACE..."
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] kubectl apply namespace + quota + limitrange + networkpolicy"
        exit 0
    fi

    # Criar/Atualizar Namespace
    kubectl_apply_idempotent <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
  labels:
    # ADR-048: Labels obrigatorias
    domain: "${DOMAIN}"
    environment: "${ENV}"
    product: "${PRODUCT}"
    owner: "${OWNER}"
    managed-by: "platform-provisioner"
    onboarding-version: "v1"
EOF

    log_success "Namespace criado/atualizado"

    # ResourceQuota (P2)
    log_info "Aplicando ResourceQuota..."

    kubectl_apply_idempotent <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ${NAMESPACE}-quota
  namespace: ${NAMESPACE}
  labels:
    domain: "${DOMAIN}"
    environment: "${ENV}"
    managed-by: "platform-provisioner"
spec:
  hard:
    requests.cpu: "${QUOTA_CPU_REQ}"
    requests.memory: "${QUOTA_MEM_REQ}"
    limits.cpu: "${QUOTA_CPU_LIM}"
    limits.memory: "${QUOTA_MEM_LIM}"
    pods: "${QUOTA_PODS}"
    services: "20"
    secrets: "30"
    configmaps: "30"
    persistentvolumeclaims: "10"
EOF

    log_success "ResourceQuota aplicada"

    # LimitRange
    log_info "Aplicando LimitRange..."

    kubectl_apply_idempotent <<EOF
apiVersion: v1
kind: LimitRange
metadata:
  name: ${NAMESPACE}-limits
  namespace: ${NAMESPACE}
  labels:
    domain: "${DOMAIN}"
    environment: "${ENV}"
    managed-by: "platform-provisioner"
spec:
  limits:
  - type: Container
    default:
      cpu: "400m"
      memory: "512Mi"
    defaultRequest:
      cpu: "100m"
      memory: "128Mi"
    max:
      cpu: "4"
      memory: "4Gi"
    min:
      cpu: "10m"
      memory: "16Mi"
  - type: Pod
    max:
      cpu: "8"
      memory: "8Gi"
EOF

    log_success "LimitRange aplicada"

    # NetworkPolicy
    log_info "Aplicando NetworkPolicy default-deny..."

    kubectl_apply_idempotent <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: ${NAMESPACE}
  labels:
    domain: "${DOMAIN}"
    managed-by: "platform-provisioner"
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: ${NAMESPACE}
  labels:
    domain: "${DOMAIN}"
    managed-by: "platform-provisioner"
spec:
  podSelector: {}
  ingress:
  - from:
    - podSelector: {}
  policyTypes:
  - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-controller
  namespace: ${NAMESPACE}
  labels:
    domain: "${DOMAIN}"
    managed-by: "platform-provisioner"
spec:
  podSelector: {}
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
  policyTypes:
  - Ingress
EOF

    log_success "NetworkPolicies aplicadas"

    # RoleBinding: platform-provisioner no namespace (GAP-008)
    log_info "Configurando RoleBinding para ${SA_NAME}..."

    # Validar que o ServiceAccount existe antes de criar o binding
    if ! resource_exists serviceaccount "${SA_NAME}" "${SA_NAMESPACE}"; then
        log_error "ServiceAccount ${SA_NAME} NAO encontrado no namespace ${SA_NAMESPACE}"
        log_error "Execute bootstrap-provisioner.sh antes de criar namespaces"
        log_error "  ./bootstrap-provisioner.sh --sa-namespace ${SA_NAMESPACE}"
        exit 1
    fi

    kubectl_apply_idempotent <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${SA_NAME}-binding
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${SA_NAME}
    app.kubernetes.io/part-of: platform-core
    app.kubernetes.io/managed-by: ${SA_NAME}
    domain: "${DOMAIN}"
    environment: "${ENV}"
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: ${SA_NAME}
subjects:
  - kind: ServiceAccount
    name: ${SA_NAME}
    namespace: ${SA_NAMESPACE}
EOF

    log_success "RoleBinding ${SA_NAME}-binding criado em ${NAMESPACE}"
    log_success "Namespace $NAMESPACE totalmente provisionado"
}

main "$@"
