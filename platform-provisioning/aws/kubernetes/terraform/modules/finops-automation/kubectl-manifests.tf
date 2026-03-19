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
# FinOps Lambda RBAC — K8s API Access for Health Checks + CA Scaling
#
# Fix 2026-03-18: Lambda health checks (Linkerd, workloads) and Cluster
# Autoscaler scaling require K8s API access. The Lambda IAM role must be
# mapped in aws-auth ConfigMap AND have a ClusterRole with pod read +
# deployment patch permissions.
#
# Without this, Lambda falls back to:
#   - ASSUMED_READY for Linkerd (blind sleep instead of real check)
#   - scale_error for CA (autoscaler not scaled, manual intervention needed)
################################################################################

# ClusterRole: read pods + patch deployments (least privilege for Lambda)
resource "kubectl_manifest" "finops_health_checker_role" {
  yaml_body = <<-YAML
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRole
    metadata:
      name: finops-health-checker
      labels:
        app.kubernetes.io/managed-by: terraform
        app.kubernetes.io/part-of: finops-automation
    rules:
      - apiGroups: [""]
        resources: ["pods"]
        verbs: ["get", "list"]
      - apiGroups: ["apps"]
        resources: ["deployments"]
        verbs: ["get", "patch"]
      - apiGroups: ["apps"]
        resources: ["deployments/scale"]
        verbs: ["get", "patch"]
  YAML
}

# ClusterRoleBinding: bind lambda-finops user to the ClusterRole
resource "kubectl_manifest" "finops_health_checker_binding" {
  yaml_body = <<-YAML
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRoleBinding
    metadata:
      name: finops-health-checker
      labels:
        app.kubernetes.io/managed-by: terraform
        app.kubernetes.io/part-of: finops-automation
    roleRef:
      apiGroup: rbac.authorization.k8s.io
      kind: ClusterRole
      name: finops-health-checker
    subjects:
      - kind: User
        name: lambda-finops
        apiGroup: rbac.authorization.k8s.io
  YAML

  depends_on = [kubectl_manifest.finops_health_checker_role]
}

################################################################################
# EKS Access Entry — Map Lambda IAM Role to K8s user
#
# Maps the Lambda IAM role to the K8s username 'lambda-finops' used in the
# ClusterRoleBinding above. Uses the EKS Access Entry API (preferred over
# manually patching the aws-auth ConfigMap).
#
# Requires: EKS cluster authenticationMode = API or API_AND_CONFIG_MAP
# If the cluster uses CONFIG_MAP only, uncomment the aws-auth patch below
# and remove this resource.
################################################################################

resource "aws_eks_access_entry" "finops_lambda" {
  cluster_name      = var.cluster_name
  principal_arn     = aws_iam_role.lambda_role.arn
  kubernetes_groups = ["finops-health-checker"]
  user_name         = "lambda-finops"
  type              = "STANDARD"

  tags = merge(local.security_tags, {
    Name    = "finops-lambda-access-entry"
    Purpose = "Lambda K8s API access for health checks and CA scaling"
  })
}

################################################################################
# Outputs para validação
################################################################################

output "coredns_pdb_applied" {
  description = "CoreDNS PDB manifest applied successfully"
  value       = kubectl_manifest.coredns_pdb.id
}

output "finops_rbac_applied" {
  description = "FinOps Lambda RBAC (ClusterRole + ClusterRoleBinding) applied"
  value       = kubectl_manifest.finops_health_checker_binding.id
}

output "finops_eks_access_entry" {
  description = "EKS Access Entry for Lambda IAM role"
  value       = aws_eks_access_entry.finops_lambda.access_entry_arn
}
