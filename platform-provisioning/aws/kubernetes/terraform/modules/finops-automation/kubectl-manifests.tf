################################################################################
# FinOps PDB Optimization — Kubectl Manifests
# ADR-025: Graceful Node Drain for Lambda Shutdown (10-15min → 2-3min)
#
# Aplica PDBs otimizados para permitir drain rápido durante shutdown Lambda.
# CoreDNS PDB: maxUnavailable=1 (permite evição de 1 pod, mantém HA)
################################################################################


# CoreDNS PDB Override
# Permite drain rápido enquanto mantém 1 pod CoreDNS ativo (HA)
resource "kubectl_manifest" "coredns_pdb" {
  yaml_body = <<-YAML
    apiVersion: policy/v1
    kind: PodDisruptionBudget
    metadata:
      name: coredns
      namespace: kube-system
      labels:
        k8s-app: kube-dns
        app.kubernetes.io/managed-by: terraform
        app.kubernetes.io/component: pdb
        app.kubernetes.io/part-of: finops-optimization
      annotations:
        description: "Allow 1 CoreDNS pod to be evicted during node drain"
        finops/optimization: "shutdown-lambda-drain-speed"
        adr: "ADR-025"
    spec:
      maxUnavailable: 1
      selector:
        matchLabels:
          k8s-app: kube-dns
  YAML

  depends_on = [
    # Aguardar cluster estar pronto antes de aplicar manifests
    # Ajustar dependência conforme módulo EKS
  ]
}

# Calico Node DaemonSet Tolerations
# NOTA: Commented out pois Calico pode ser gerenciado por EKS add-on ou Helm
# Descomentar APENAS se Calico não tiver configuração própria de tolerations
#
# Para aplicar manualmente:
# kubectl patch daemonset calico-node -n kube-system --type='json' \
#   -p='[
#     {"op":"add","path":"/spec/template/spec/tolerations/-","value":{"key":"node.kubernetes.io/not-ready","operator":"Exists","effect":"NoExecute","tolerationSeconds":10}},
#     {"op":"add","path":"/spec/template/spec/tolerations/-","value":{"key":"node.kubernetes.io/unreachable","operator":"Exists","effect":"NoExecute","tolerationSeconds":10}}
#   ]'

# resource "null_resource" "calico_node_tolerations_patch" {
#   provisioner "local-exec" {
#     command = <<-EOT
#       kubectl patch daemonset calico-node -n kube-system --type='json' \
#         -p='[
#           {"op":"add","path":"/spec/template/spec/tolerations/-","value":{"key":"node.kubernetes.io/not-ready","operator":"Exists","effect":"NoExecute","tolerationSeconds":10}},
#           {"op":"add","path":"/spec/template/spec/tolerations/-","value":{"key":"node.kubernetes.io/unreachable","operator":"Exists","effect":"NoExecute","tolerationSeconds":10}}
#         ]'
#     EOT
#   }
#
#   triggers = {
#     always_run = timestamp()
#   }
# }

################################################################################
# Outputs para validação
################################################################################

output "coredns_pdb_applied" {
  description = "CoreDNS PDB manifest applied successfully"
  value       = kubectl_manifest.coredns_pdb.id
}
