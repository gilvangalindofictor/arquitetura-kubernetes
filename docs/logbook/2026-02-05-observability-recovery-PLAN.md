# 📋 PLANO DE EXECUÇÃO — Observability Stack Recovery

| Campo | Valor |
|-------|-------|
| **Data Criação** | 2026-02-05 |
| **Status** | PRONTO PARA EXECUÇÃO |
| **Duração Estimada** | 15-20min |
| **Impacto** | Médio (Obs Stack down 5d+) |
| **Custo** | $0 (apenas scheduling) |

---

## 🎯 Objetivo

Aplicar tolerations `workload=critical:NoSchedule` em Prometheus, Alertmanager e Grafana para resolver pods Pending há 5+ dias.

---

## ✅ Trabalho Completado (Sessão Atual)

- [x] Análise root cause: taint `workload=critical` não tolerado
- [x] Edição módulo base `modules/kube-prometheus-stack/main.tf` ✅
- [x] Remoção pasta `envs/` deprecated (backup: 842MB)
- [x] Identificação arquitetura: Observability shared (staging+prod)
- [x] AWS re-auth + validação estrutura profissional

---

## 🚀 Opções de Execução

### Opção A: Helm Upgrade Direto (RECOMENDADO - 10min)

**Vantagem:** Aplica mudanças imediatamente sem refatorar environment

```bash
# 1. Backup values atuais
helm get values kube-prometheus-stack -n monitoring > /tmp/current-values.yaml

# 2. Upgrade com tolerations adicionais
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --reuse-values \
  --set prometheus.prometheusSpec.tolerations[1].key=workload \
  --set prometheus.prometheusSpec.tolerations[1].operator=Equal \
  --set prometheus.prometheusSpec.tolerations[1].value=critical \
  --set prometheus.prometheusSpec.tolerations[1].effect=NoSchedule \
  --set alertmanager.alertmanagerSpec.tolerations[1].key=workload \
  --set alertmanager.alertmanagerSpec.tolerations[1].operator=Equal \
  --set alertmanager.alertmanagerSpec.tolerations[1].value=critical \
  --set alertmanager.alertmanagerSpec.tolerations[1].effect=NoSchedule \
  --set grafana.tolerations[1].key=workload \
  --set grafana.tolerations[1].operator=Equal \
  --set grafana.tolerations[1].value=critical \
  --set grafana.tolerations[1].effect=NoSchedule

# 3. Monitorar pods recovery
watch -n 5 'kubectl get pods -n monitoring | grep -E "(prometheus|alertmanager|grafana)"'

# 4. Validar (após ~2min)
kubectl get pods -n monitoring | grep -E "(prometheus|alertmanager|grafana)"
# Esperado: 0/2 Pending → 2/2 Running
```

**Pós-Helm:**
- [ ] Documentar em `environments/common/observability.tf` (criar)
- [ ] Próximo terraform plan deve importar Helm release existente

---

### Opção B: Terraform via environments/common/ (PROFISSIONAL - 20min)

**Vantagem:** Gerencia observability via Terraform desde o início

#### B.1. Criar Environment Common

```bash
cd environments/common
cat > main.tf <<'EOF'
# Common/Shared Infrastructure Components
# Deployed once, used by both STAGING and PROD

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.20" }
    helm       = { source = "hashicorp/helm", version = "~> 2.12" }
  }
}

locals {
  cluster_name = "k8s-platform-prod"
}

provider "aws" {
  region  = "us-east-1"
  profile = "k8s-platform-prod"
}

data "aws_eks_cluster" "cluster" {
  name = local.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = local.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

# Import existing Helm release
import {
  to = module.kube_prometheus_stack.helm_release.kube_prometheus_stack
  id = "monitoring/kube-prometheus-stack"
}

module "kube_prometheus_stack" {
  source = "../../modules/kube-prometheus-stack"

  namespace                = "monitoring"
  chart_version            = "69.4.0"
  prometheus_storage_size  = "50Gi"
  prometheus_retention     = "30d"
  grafana_admin_password   = var.grafana_admin_password
  grafana_storage_size     = "10Gi"
  grafana_ingress_enabled  = false
  alertmanager_storage_size = "5Gi"
}
EOF

cat > backend.tf <<'EOF'
terraform {
  backend "s3" {
    bucket         = "terraform-state-marco0-891377105802"
    key            = "common/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks-marco0"
    encrypt        = true
  }
}
EOF

cat > variables.tf <<'EOF'
variable "grafana_admin_password" {
  type      = string
  sensitive = true
}
EOF

cat > terraform.tfvars <<'EOF'
# Get from Secrets Manager
grafana_admin_password = "REPLACE_WITH_SECRET"
EOF
```

#### B.2. Executar Terraform

```bash
cd environments/common

# Init
terraform init

# Import existing Helm release
terraform import module.kube_prometheus_stack.helm_release.kube_prometheus_stack monitoring/kube-prometheus-stack

# Plan (deve mostrar apenas tolerations changes)
terraform plan -out=observability-recovery.tfplan

# Apply
terraform apply observability-recovery.tfplan

# Validar
kubectl get pods -n monitoring | grep -E "(prometheus|alertmanager|grafana)"
terraform plan  # Deve retornar "No changes"
```

---

## 📊 Validação Pós-Apply

```bash
# 1. Verificar pods Running
kubectl get pods -n monitoring -o wide | grep -E "(prometheus|alertmanager|grafana)"

# Esperado:
# prometheus-kube-prometheus-stack-prometheus-0       2/2  Running  0  <2m  10.0.X.X  ip-10-0-134-10 (critical node)
# alertmanager-kube-prometheus-stack-alertmanager-0   2/2  Running  0  <2m  10.0.X.X  ip-10-0-151-94 (critical node)
# kube-prometheus-stack-grafana-XXXXX                 3/3  Running  0  <2m  10.0.X.X  ip-10-0-134-10 (critical node)

# 2. Verificar tolerations aplicadas
kubectl get pod prometheus-kube-prometheus-stack-prometheus-0 -n monitoring -o yaml | grep -A 10 tolerations

# Esperado incluir:
# - key: workload
#   operator: Equal
#   value: critical
#   effect: NoSchedule

# 3. Verificar métricas funcionando
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
curl -s http://localhost:9090/api/v1/query?query=up | jq '.status'
# Esperado: "success"

# 4. Idempotência check
terraform plan  # ou helm list (se Opção A)
# Esperado: "No changes" ou release unchanged
```

---

## 📝 Documentação Pós-Execução

### Atualizar Logbook

```bash
# Adicionar ao logbook:
[HH:MM:SS] Helm Upgrade | Orq | kube-prometheus-stack com tolerations críticos | ✅
[HH:MM:SS] Validação | K8s | 3 pods Pending → Running em 2m18s | ✅
[HH:MM:SS] Idempotência | TF/Helm | Verificado: no changes | ✅
[HH:MM:SS] DocSync | Orq | architecture.md, decisions.md | ✅
```

### Atualizar architecture.md

```markdown
## Observability Stack

### Scheduling Strategy

- **Node Affinity:** `node-type=system` (preferred)
- **Tolerations:**
  - `node-type=system:NoSchedule` (system nodes)
  - `workload=critical:NoSchedule` (critical nodes) ← **ADR-041 pattern**
- **Rationale:** Allow observability on critical nodes for database monitoring
- **Applied:** 2026-02-05 (recovery from 5d+ Pending)
```

### Criar ADR se necessário

```markdown
## ADR-042: Observability Stack on Critical Nodes

**Date:** 2026-02-05
**Status:** Accepted

**Context:**
- Prometheus, Alertmanager, Grafana Pending 5+ dias
- Critical nodes tainted `workload=critical:NoSchedule`
- Database monitoring requires proximity to critical workloads

**Decision:**
Add toleration `workload=critical:NoSchedule` to observability components.

**Consequences:**
- ✅ Monitoring operational 24/7
- ✅ Low latency metrics from critical nodes
- ⚠️ Resource contention with databases (mitigated by resource limits)
```

---

## 🔄 Rollback Plan

Se algo falhar:

```bash
# Opção A (Helm):
helm rollback kube-prometheus-stack -n monitoring

# Opção B (Terraform):
cd environments/common
terraform destroy -target=module.kube_prometheus_stack
# Depois re-deploy via Helm manual se necessário
```

---

## ⚠️ Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|---------------|-----------|
| Pods não schedulam | Baixa | Nodes críticos têm capacidade suficiente |
| Resource contention | Média | Limits já configurados (CPU 500m, Mem 2Gi) |
| Helm drift no TF | Média | Import explícito do release antes do plan |
| PVC recreation | Baixa | Mudança não afeta PVCs (apenas spec do pod) |

---

## 🎯 Recomendação Final

**Execute Opção A (Helm Upgrade)** primeiro:
- Mais rápido (10min)
- Menos risco (não mexe em structure)
- Resolve problema imediato

**Depois, migre para Opção B (Terraform)**:
- Próxima sessão
- Refatorar observability para `environments/common/`
- Import Helm release existente
- Documentar em `decisions.md` (ADR-029: Observability in Common Environment)

---

## 📞 Checklist Execução

- [ ] AWS SSO login (`aws sso login --profile=k8s-platform-prod`)
- [ ] Verificar pods Pending (`kubectl get pods -n monitoring`)
- [ ] Backup Helm values (`helm get values kube-prometheus-stack -n monitoring`)
- [ ] Executar Helm upgrade (Opção A) OU Terraform (Opção B)
- [ ] Aguardar 2-3min (pods recreation)
- [ ] Validar todos Running (`kubectl get pods -n monitoring`)
- [ ] Verificar tolerations (`kubectl describe pod ...`)
- [ ] Idempotência check
- [ ] Atualizar logbook
- [ ] Atualizar architecture.md
- [ ] Commit mudanças (`git add` + `git commit`)

---

**Status:** ✅ PRONTO PARA EXECUÇÃO
**Próxima sessão:** Executar Opção A, validar, documentar
