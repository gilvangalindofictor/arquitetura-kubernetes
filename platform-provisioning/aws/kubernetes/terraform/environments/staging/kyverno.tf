################################################################################
# Kyverno — Policy Engine (Staging)
# GAP-FINOPS-SCHED-001 (2026-03-24): Onboarding Kyverno para Terraform para adicionar
#   toleration node-type=system:NoSchedule em todos os subcomponentes.
#
# Contexto: Kyverno era instalado fora do Terraform (helm install manual) e fora do
#   ArgoCD GitOps ativo (apps/staging/governance/kyverno/app.yaml é apenas metadata).
#   Durante o shutdown FinOps, os subcomponentes ficavam Pending nos system nodes por
#   ausência de toleration → webhooks de validação offline → pods novos rejeitados.
#
# Subcomponentes afetados (todos Deployments):
#   - admissionController  (webhook validação/mutação — CRÍTICO)
#   - backgroundController (scan de compliance em background)
#   - cleanupController    (cleanup policies)
#   - reportsController    (policy reports)
#
# Versão: 3.7.1 (helm release name: kyverno-new, chart version real no cluster)
# NOTA: O helm release foi instalado manualmente como "kyverno-new" (não "kyverno")
#       e a versão real do chart é 3.7.1 (appVersion v1.17.1), não 3.2.7.
#       Corrigido em 2026-03-25 durante FASE 2 do import (GAP-FINOPS-SCHED-001).
# Namespace: staging-governance-kyverno (ADR-048 naming convention)
#
# Import antes do primeiro apply:
#   terraform import helm_release.kyverno staging-governance-kyverno/kyverno-new
#
# ATENÇÃO: Kyverno valida os próprios pods. Durante o apply, webhooks podem bloquear
#   o rollout se o Kyverno estiver em estado degradado. Aplicar durante janela de manutenção
#   ou com: kubectl delete validatingwebhookconfiguration kyverno-resource-validating-webhook-cfg
#   (será recriado automaticamente pelo admissionController após o rollout).
#
# Ref: apps/staging/governance/kyverno/app.yaml (metadata)
#      environments/staging/kyverno-ecr-redirect.tf (políticas — depends_on removido,
#        agora pode referenciar helm_release.kyverno explicitamente)
################################################################################

resource "helm_release" "kyverno" {
  name       = "kyverno-new"
  repository = "https://kyverno.github.io/kyverno"
  chart      = "kyverno"
  version    = "3.7.1"
  namespace  = "staging-governance-kyverno"

  create_namespace = true

  # Estratégia de atualização: Recreate para evitar conflito de webhooks durante upgrade
  # (dois admissionController com versões diferentes rejeitando cada um os pods do outro)
  set {
    name  = "admissionController.updateStrategy.type"
    value = "Recreate"
  }

  # -----------------------------------------------------------------------------
  # GAP-FINOPS-SCHED-001: tolerations node-type=system:NoSchedule
  # Aplicar em TODOS os subcomponentes para garantir disponibilidade durante shutdown FinOps
  # -----------------------------------------------------------------------------

  # admissionController — CRÍTICO: webhooks de validação/mutação (ECR redirect policy)
  set {
    name  = "admissionController.tolerations[0].key"
    value = "node-type"
  }
  set {
    name  = "admissionController.tolerations[0].operator"
    value = "Equal"
  }
  set {
    name  = "admissionController.tolerations[0].value"
    value = "system"
  }
  set {
    name  = "admissionController.tolerations[0].effect"
    value = "NoSchedule"
  }

  # backgroundController — policy scan em background
  set {
    name  = "backgroundController.tolerations[0].key"
    value = "node-type"
  }
  set {
    name  = "backgroundController.tolerations[0].operator"
    value = "Equal"
  }
  set {
    name  = "backgroundController.tolerations[0].value"
    value = "system"
  }
  set {
    name  = "backgroundController.tolerations[0].effect"
    value = "NoSchedule"
  }

  # cleanupController — cleanup policies
  set {
    name  = "cleanupController.tolerations[0].key"
    value = "node-type"
  }
  set {
    name  = "cleanupController.tolerations[0].operator"
    value = "Equal"
  }
  set {
    name  = "cleanupController.tolerations[0].value"
    value = "system"
  }
  set {
    name  = "cleanupController.tolerations[0].effect"
    value = "NoSchedule"
  }

  # reportsController — policy reports
  set {
    name  = "reportsController.tolerations[0].key"
    value = "node-type"
  }
  set {
    name  = "reportsController.tolerations[0].operator"
    value = "Equal"
  }
  set {
    name  = "reportsController.tolerations[0].value"
    value = "system"
  }
  set {
    name  = "reportsController.tolerations[0].effect"
    value = "NoSchedule"
  }

  # ECR mirror: imagens do Kyverno vêm do ECR pull-through cache
  # Necessário para compatibilidade com a ClusterPolicy redirect-public-registries-to-ecr
  # NOTA: A própria policy exclui kube-system/kube-public/kube-node-lease — staging-governance-kyverno
  #   NÃO está excluído, portanto o Kyverno precisa de imagens já no ECR ou ter exceção.
  # Verificar: o chart kyverno/kyverno usa ghcr.io/kyverno/kyverno como imagem base.
  # Se enable_ghcr=false (atual), as imagens serão redirecionadas para ECR ghcr/ prefix
  # que NÃO tem pull-through rule. Considerar adicionar PolicyException para staging-governance-kyverno
  # ou habilitar enable_ghcr=true. Referência: GAP-KYVERNO-GHCR-001 em kyverno-ecr-redirect.tf.

  lifecycle {
    # Permite upgrade de versão via CI sem recriar o release
    ignore_changes = [version]
  }
}
