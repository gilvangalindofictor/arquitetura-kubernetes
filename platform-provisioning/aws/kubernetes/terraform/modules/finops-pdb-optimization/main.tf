# -----------------------------------------------------------------------------
# FinOps PDB Optimization Module
# -----------------------------------------------------------------------------
# Cria PodDisruptionBudgets com minAvailable=0 para workloads críticos,
# permitindo drains rápidos de nodes sem bloquear o Cluster Autoscaler.
#
# Problema resolvido: Node drains >30min devido a pods únicos sem PDB
# Solução: PDBs com minAvailable=0 (disruption permitida) para workloads
#          que toleram indisponibilidade momentânea durante manutenção
#
# Contexto: Cluster EKS staging, nodes t3.large (R$ 365/mês cada)
# Savings: Habilita CA scale-down eficiente → potencial -1 node = R$ 4.380/ano
#
# ADR: DEC-076 | Logbook: 2026-02-24-finops-pdb-optimization.md
# -----------------------------------------------------------------------------

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
  }
}

# -----------------------------------------------------------------------------
# PodDisruptionBudgets para workloads críticos
# minAvailable=0: permite eviction completa durante drain (disruption OK)
# Usar apenas para workloads sem SLA de 100% de uptime contínuo
# -----------------------------------------------------------------------------

resource "kubernetes_pod_disruption_budget_v1" "workload_pdb" {
  for_each = var.workloads

  metadata {
    name      = "${each.key}-pdb"
    namespace = each.value.namespace

    labels = {
      app                   = each.key
      "managed-by"          = "terraform"
      "finops.k8s.io/pdb"   = "optimized"
      "finops.k8s.io/phase" = "drain-optimization"
    }

    annotations = {
      "finops.k8s.io/purpose"   = "Enables fast node drain for Cluster Autoscaler scale-down"
      "finops.k8s.io/savings"   = "Indirect: ~R$ 4380/ano via -1 node t3.large"
      "finops.k8s.io/adr"       = "DEC-076"
      "finops.k8s.io/created"   = "2026-02-24"
      "finops.k8s.io/namespace" = each.value.namespace
    }
  }

  spec {
    min_available = each.value.min_available

    selector {
      match_labels = each.value.selector
    }
  }
}
