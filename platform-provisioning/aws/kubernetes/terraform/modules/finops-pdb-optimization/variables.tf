# -----------------------------------------------------------------------------
# FinOps PDB Optimization Module — Variables
# -----------------------------------------------------------------------------
# Objetivo: PodDisruptionBudgets otimizados para reduzir tempo de drain de
#           nodes de 30min para <5min, habilitando Cluster Autoscaler scale-down
#
# Savings estimados:
#   Direto:   ~R$ 25/ano (reduced drain downtime)
#   Indireto: ~R$ 4.380/ano (potential -1 node t3.large via autoscaler)
#
# ADR: DEC-076-finops-pdb-optimization
# -----------------------------------------------------------------------------

variable "workloads" {
  type = map(object({
    namespace     = string
    min_available = number
    selector      = map(string)
  }))
  description = "Map of workloads to create PodDisruptionBudgets for. Each workload requires namespace, minAvailable value, and label selector matching the pods."
}
