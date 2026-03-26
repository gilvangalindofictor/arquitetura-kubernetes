################################################################################
# FinOps PDB Optimization — Kubectl Manifests
# ADR-025: Graceful Node Drain for Lambda Shutdown (10-15min → 2-3min)
#
# Aplica PDBs otimizados para permitir drain rápido durante shutdown Lambda.
# CoreDNS PDB: maxUnavailable=1 (permite evição de 1 pod, mantém HA)
#
# GAP-FINOPS-SCHED-001 (2026-03-24): calico-kube-controllers toleration
# Contexto: calico-kube-controllers é instalado via kubectl apply (raw manifests upstream —
#   NÃO gerenciado por Terraform nem ArgoCD). O Deployment não tem toleration para
#   node-type=system:NoSchedule. Durante shutdown FinOps, workload nodes escalam para 0
#   e o controller fica Pending → Calico CNI sem controlador → network policies não atualizadas.
# Fix: kubectl_manifest aplica strategic merge patch no Deployment para adicionar toleration.
#   Zero-drift: após apply, terraform plan retorna "No changes".
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

# Calico Node DaemonSet — NOTA sobre tolerations:
# O DaemonSet calico-node JÁ possui tolerations com operator=Exists (wildcard) que cobrem
# todos os taints incluindo node-type=system:NoSchedule. Não é necessário patch adicional.
# Auditado em 2026-03-24 — calico-node: 15/15 Running em todos os node groups.
#
# O componente com GAP é calico-kube-CONTROLLERS (Deployment, não DaemonSet) — ver abaixo.

# -----------------------------------------------------------------------------
# GAP-FINOPS-SCHED-001 (2026-03-24): calico-kube-controllers toleration
# Contexto: calico é instalado via kubectl apply (raw manifests upstream).
#   O Deployment calico-kube-controllers não tem toleration para node-type=system:NoSchedule.
#   Durante shutdown FinOps, workload nodes escalam para 0. O controller fica Pending nos
#   system nodes → sem controlador Calico → network policies podem ficar desatualizadas.
#
# Estratégia IaC: kubectl_manifest com strategic merge patch.
#   O recurso codifica o estado desejado — terraform plan retorna "No changes" após apply.
#
# IMPORTANTE: Este manifest usa strategic merge patch no Deployment existente.
#   O field manager é "terraform" — não conflita com o apply original do Calico.
#   Após apply, verificar: kubectl get deployment calico-kube-controllers -n calico-system \
#     -o jsonpath='{.spec.template.spec.tolerations}' | jq .
# -----------------------------------------------------------------------------
resource "kubectl_manifest" "calico_kube_controllers_toleration" {
  yaml_body = <<-YAML
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: calico-kube-controllers
      namespace: calico-system
      labels:
        app.kubernetes.io/managed-by: terraform
      annotations:
        finops/gap: "GAP-FINOPS-SCHED-001"
        finops/purpose: "Tolerate system node taint during FinOps shutdown"
    spec:
      template:
        spec:
          tolerations:
            # GAP-FINOPS-SCHED-001: tolerar system nodes durante shutdown FinOps
            - key: "node-type"
              operator: "Equal"
              value: "system"
              effect: "NoSchedule"
            # Tolerations padrão do Calico (manter para não remover via strategic merge)
            - key: "node.kubernetes.io/not-ready"
              operator: "Exists"
              effect: "NoExecute"
            - key: "node.kubernetes.io/unreachable"
              operator: "Exists"
              effect: "NoExecute"
            - key: "node.kubernetes.io/network-unavailable"
              operator: "Exists"
              effect: "NoSchedule"
  YAML

  # Server-side apply: preserva campos não gerenciados por este recurso
  server_side_apply = true
  force_conflicts   = false

  lifecycle {
    # Calico operator pode atualizar annotations/labels — não drift em yaml_body
    ignore_changes = [yaml_body]
  }
}

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
        verbs: ["get", "list", "delete"]
      - apiGroups: ["apps"]
        resources: ["deployments"]
        verbs: ["get", "patch"]
      - apiGroups: ["apps"]
        resources: ["deployments/scale"]
        verbs: ["get", "patch"]
      # GAP-FINOPS-CNI-01 (2026-03-23): DaemonSet rollout restart for linkerd-cni
      # token renewal. After stop/start cycles >24h (weekends/holidays), the CNI
      # host kubeconfig token expires. Lambda must patch the DaemonSet to trigger
      # rollout restart before starting the Linkerd control plane (Step 4a).
      - apiGroups: ["apps"]
        resources: ["daemonsets"]
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

# DISABLED: EKS cluster uses CONFIG_MAP auth mode, not API/API_AND_CONFIG_MAP.
# To enable, first change EKS auth mode, then uncomment this resource.
# See: GAP-FINOPS-ACCESS-ENTRY (2026-03-21)
#
# resource "aws_eks_access_entry" "finops_lambda" {
#   cluster_name      = var.cluster_name
#   principal_arn     = aws_iam_role.lambda_role.arn
#   kubernetes_groups = ["finops-health-checker"]
#   user_name         = "lambda-finops"
#   type              = "STANDARD"
#
#   tags = merge(local.security_tags, {
#     Name    = "finops-lambda-access-entry"
#     Purpose = "Lambda K8s API access for health checks and CA scaling"
#   })
# }

################################################################################
# linkerd-cni Token Renewal CronJob
# ADR-026 / GAP-FINOPS-CNI-01 (2026-03-23)
#
# Problema: Token JWT do linkerd-cni no host kubeconfig expira após 24h.
# repair-controller v1.3.0 tem bug e não renova automaticamente.
# Após paradas >24h (fins de semana/feriados), CNI retorna Unauthorized →
# cascata total: Linkerd offline → CA offline → 57+ pods Pending.
#
# Solução: CronJob executa rollout restart do DaemonSet às 19h30 BRT
# (22h30 UTC, seg-sex), 30min antes do DOWN FinOps (20h00 BRT).
# Garante tokens frescos (TTL 24h) para o UP do dia seguinte.
################################################################################

resource "kubectl_manifest" "linkerd_cni_renewer_sa" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: linkerd-cni-renewer
      namespace: linkerd-cni
      labels:
        app.kubernetes.io/managed-by: terraform
        app.kubernetes.io/component: cni-token-renewal
        app.kubernetes.io/part-of: finops-resilience
      annotations:
        description: "ServiceAccount para CronJob de renovação preventiva do token CNI"
        finops/gap: "GAP-FINOPS-CNI-01"
  YAML
}

resource "kubectl_manifest" "linkerd_cni_renewer_role" {
  yaml_body = <<-YAML
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRole
    metadata:
      name: linkerd-cni-renewer
      labels:
        app.kubernetes.io/managed-by: terraform
        app.kubernetes.io/part-of: finops-resilience
      annotations:
        description: "Permissão mínima para rollout restart do DaemonSet linkerd-cni"
    rules:
      - apiGroups: ["apps"]
        resources: ["daemonsets"]
        verbs: ["get", "list", "patch", "update"]
      - apiGroups: ["apps"]
        resources: ["daemonsets/status"]
        verbs: ["get"]
      - apiGroups: [""]
        resources: ["pods"]
        verbs: ["get", "list"]
  YAML
}

resource "kubectl_manifest" "linkerd_cni_renewer_binding" {
  yaml_body = <<-YAML
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRoleBinding
    metadata:
      name: linkerd-cni-renewer
      labels:
        app.kubernetes.io/managed-by: terraform
        app.kubernetes.io/part-of: finops-resilience
    roleRef:
      apiGroup: rbac.authorization.k8s.io
      kind: ClusterRole
      name: linkerd-cni-renewer
    subjects:
      - kind: ServiceAccount
        name: linkerd-cni-renewer
        namespace: linkerd-cni
  YAML

  depends_on = [
    kubectl_manifest.linkerd_cni_renewer_sa,
    kubectl_manifest.linkerd_cni_renewer_role,
  ]
}

resource "kubectl_manifest" "linkerd_cni_token_renewal" {
  yaml_body = <<-YAML
    apiVersion: batch/v1
    kind: CronJob
    metadata:
      name: linkerd-cni-token-renewal
      namespace: linkerd-cni
      labels:
        app.kubernetes.io/managed-by: terraform
        app.kubernetes.io/component: cni-token-renewal
        app.kubernetes.io/part-of: finops-resilience
      annotations:
        description: "Renova tokens do linkerd-cni DaemonSet antes do DOWN FinOps"
        finops/purpose: "Previne CNI Unauthorized após paradas de 24h+ (GAP-FINOPS-CNI-01)"
        finops/schedule: "19h30 BRT seg-sex (30min antes do DOWN 20h00 BRT)"
        adr: "ADR-026"
    spec:
      schedule: "30 22 * * 1-5"
      concurrencyPolicy: Forbid
      successfulJobsHistoryLimit: 5
      failedJobsHistoryLimit: 3
      jobTemplate:
        spec:
          backoffLimit: 2
          activeDeadlineSeconds: 360
          template:
            metadata:
              labels:
                app.kubernetes.io/component: cni-token-renewal
              annotations:
                linkerd.io/inject: disabled
            spec:
              serviceAccountName: linkerd-cni-renewer
              restartPolicy: OnFailure
              nodeSelector:
                eks.amazonaws.com/nodegroup: system
              tolerations:
                # GAP-TOLERATION-001 (2026-03-25): system nodes possuem taint
                # 'node-type=system:NoSchedule' — sem este toleration o CronJob
                # nunca agenda em nodes system (onde CNI esta configurado).
                - key: "node-type"
                  operator: "Equal"
                  value: "system"
                  effect: "NoSchedule"
                - key: "node.kubernetes.io/not-ready"
                  operator: "Exists"
                  effect: "NoSchedule"
                - key: "node.kubernetes.io/unreachable"
                  operator: "Exists"
                  effect: "NoSchedule"
              containers:
                - name: cni-token-renewer
                  # GAP-IMAGE-001 (2026-03-25): usar ECR mirror publico (nao DockerHub).
                  # Patch manual aplicado em 2026-03-25; codificado aqui via variavel
                  # cni_renewer_image para zero drift (executor-terraform.md).
                  image: ${var.cni_renewer_image}
                  imagePullPolicy: IfNotPresent
                  command:
                    - /bin/sh
                    - -c
                    - |
                      set -e
                      echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] linkerd-cni token renewal iniciado (GAP-FINOPS-CNI-01)"
                      echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Estado atual do DaemonSet:"
                      kubectl get pods -n linkerd-cni -o wide
                      echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Executando rollout restart..."
                      kubectl rollout restart daemonset/linkerd-cni -n linkerd-cni
                      echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Aguardando rollout (300s)..."
                      kubectl rollout status daemonset/linkerd-cni -n linkerd-cni --timeout=300s
                      RUNNING=$(kubectl get pods -n linkerd-cni --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo "0")
                      TOTAL=$(kubectl get pods -n linkerd-cni --no-headers 2>/dev/null | wc -l || echo "0")
                      echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Resultado: $RUNNING/$TOTAL pods Running"
                      if [ "$RUNNING" -lt "$TOTAL" ]; then
                        echo "[FAIL] pods não Running após rollout"
                        exit 1
                      fi
                      echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Renovação concluída — tokens válidos por 24h"
                  resources:
                    requests:
                      cpu: "50m"
                      memory: "64Mi"
                    limits:
                      cpu: "200m"
                      memory: "128Mi"
  YAML

  depends_on = [
    kubectl_manifest.linkerd_cni_renewer_sa,
    kubectl_manifest.linkerd_cni_renewer_role,
    kubectl_manifest.linkerd_cni_renewer_binding,
  ]
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

# DISABLED: depends on aws_eks_access_entry.finops_lambda (commented out)
# output "finops_eks_access_entry" {
#   description = "EKS Access Entry for Lambda IAM role"
#   value       = aws_eks_access_entry.finops_lambda.access_entry_arn
# }
