# -----------------------------------------------------------------------------
# FinOps PDB Optimization Module — Outputs
# -----------------------------------------------------------------------------

output "pdb_names" {
  description = "Map of workload key → PDB name created"
  value = {
    for k, v in kubernetes_pod_disruption_budget_v1.workload_pdb :
    k => v.metadata[0].name
  }
}

output "pdb_namespaces" {
  description = "Map of workload key → namespace where PDB was created"
  value = {
    for k, v in kubernetes_pod_disruption_budget_v1.workload_pdb :
    k => v.metadata[0].namespace
  }
}

output "pdb_count" {
  description = "Total number of PDBs created"
  value       = length(kubernetes_pod_disruption_budget_v1.workload_pdb)
}
