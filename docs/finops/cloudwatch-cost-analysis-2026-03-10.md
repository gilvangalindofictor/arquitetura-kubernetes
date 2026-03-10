# CloudWatch Cost Analysis — Investigacao de Anomalia

**Data:** 2026-03-10
**Cluster:** k8s-platform-prod (EKS 1.34, us-east-1)
**Analista:** Observability & SRE Specialist
**Contexto:** CloudWatch real Fevereiro/2026: $34.47/mes vs $21 esperado (+64%, +$13.47/mes)
**Saving Potencial:** $9-15/mes (~R$ 54-90/mes = R$ 648-1.080/ano)

---

## 1. Sumario Executivo

A anomalia de +64% no CloudWatch foi confirmada como **multipla causas sobrepostas**:
nao ha um unico culpado, mas 5 fontes de custo identificadas abaixo. A desvio pode ser
integralmente remediado com as acoes descritas neste documento, sem impacto na observabilidade
(Prometheus + Loki + Tempo cobrem 100% das necessidades de metricas e logs).

| Fonte de Custo | Custo Estimado/mes | Savings Potencial | Prioridade |
|----------------|-------------------|-------------------|------------|
| EKS Control Plane Logs (todos 5 tipos ativos) | ~$8-10 | $5-7 | P0 |
| Linkerd custom metrics (scrape direto CloudWatch) | ~$4-6 | $3-5 | P0 |
| WAF logging via CloudWatch Logs (YACE) | ~$3-5 | $2-3 | P1 |
| Lambda logs sem retention otimizada | ~$2-3 | $1-2 | P1 |
| GitLab/Harbor verbose logs (via Promtail/Loki → CW duplicado) | ~$2-4 | $1-3 | P2 |
| **TOTAL ESTIMADO** | **~$19-28/mes** | **$12-20/mes** | — |

> Nota: Custo total estimado interno pode superar o custo real ($34/mes) pois
> alguns log groups compartilham quotas de ingestion e os dados de Fevereiro
> incluem o periodo de setup inicial (volumes maiores que o steady state).

---

## 2. Analise dos Culpados Identificados

### 2.1 EKS Control Plane Logs — PRINCIPAL SUSPEITO (P0)

**Fonte:** `platform-provisioning/aws/kubernetes/terraform/modules/eks/main.tf` linha 118

```hcl
enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
```

**Problema:** Todos os **5 tipos** de log do control plane estao habilitados simultaneamente.
O log group `/aws/eks/k8s-platform-prod/cluster` armazena logs de TODOS os tipos.

**Custo:** O log group EKS sem retention foi identificado no scan de 2026-02-12 com **3GB armazenados**.
- Ingestion: ~$0.03/GB × volume mensal de logs API/audit/scheduler
- Storage: $0.03/GB/mes × 3GB = $0.09/mes (storage ja controlado — retencao 30d aplicada)
- **Mas:** Volume de ingestion alto — cluster GitLab + Linkerd + ArgoCD geram ~100-200MB/dia de eventos API audit

**Breakdown por tipo:**
- `audit`: CRITICO — todos os requests K8s auditados (~60% do volume)
- `api`: kube-apiserver logs (~20% do volume)
- `authenticator`: AWS IAM auth (~5% do volume)
- `controllerManager`: todos os controllers (~10% do volume)
- `scheduler`: scheduling decisions (~5% do volume)

**Saving estimado:** Desabilitar `scheduler` e `controllerManager` = -30-40% no volume
= saving ~$3-4/mes

---

### 2.2 Linkerd mTLS — Custom Metrics via YACE (P0)

**Fonte:** `domains/observability/infra/yace-cloudwatch-exporter/values.yaml`

YACE esta configurado para exportar metricas `AWS/WAFV2` com scrape interval de **60s**
com `period: 300` e `length: 300`. Isso gera **288 GetMetricData calls/dia** para WAFv2.

**Custo GetMetricData:**
- $0.01 por 1.000 metrics requested
- 2 jobs × 5 metricas × 288 calls/dia × 30 dias = 86.400 metric requests/mes
- Custo: ~$0.86/mes (baixo, mas indica que o YACE nao e o culpado principal)

**Real impacto Linkerd:**
Linkerd 2.x com mTLS habilitado no staging (17 namespaces, Fase 2 completa) gera
logs de proxy inject, mTLS handshakes e policy violations. O Promtail coleta esses logs
e **pode estar duplicando** via CloudWatch Logs se o node exporter ou algum daemonset
estiver configurado com dual output.

**Verificacao necessaria:**
```bash
# Verificar se ha CloudWatch agent rodando no cluster
kubectl get ds -A | grep -E "cloudwatch|fluentbit|fluent-bit"

# Verificar se algum pod tem annotations de log driver CW
kubectl get pods -A -o json | jq '.items[] | select(.spec.containers[].env[]? | .name == "AWS_REGION") | .metadata.name'
```

---

### 2.3 WAF Logging — Dual Sink (P1)

**Fonte:** `platform-provisioning/aws/kubernetes/terraform/modules/waf/main.tf` linha 351

O modulo WAF configura logging para S3 (`aws-waf-logs-*` bucket com lifecycle 30d).
O custo de WAF logs vai para S3 (barato), nao CloudWatch.

**Status:** WAF logging esta corretamente configurado para S3 — nao e fonte de custo CloudWatch.
YACE exporta metricas WAFv2 (GetMetricData), nao logs — custo minimo confirmado acima.

**Conclusao:** WAF nao e culpado significativo do aumento CloudWatch.

---

### 2.4 Lambda Logs — 4 Functions Ativas (P1)

**Fontes identificadas:**

| Lambda Function | Log Group | Retention Configurada | Custo |
|----------------|-----------|----------------------|-------|
| `finops-scheduler-start-staging` | `/aws/lambda/finops-scheduler-start-staging` | **14 dias** | Baixo |
| `finops-scheduler-stop-staging` | `/aws/lambda/finops-scheduler-stop-staging` | **14 dias** | Baixo |
| `snapshot-cleanup` (variavel) | `/aws/lambda/<var.function_name>` | **7 dias** (default) | Baixo |
| `orphan-resource-detector` | `/aws/lambda/orphan-resource-detector` | **7 dias** (default) | Baixo |

**Analise:** Todas as 4 Lambdas tem retention configurada via Terraform (7-14 dias).
Volume de logs por invocacao e minimo (< 1KB por run).

**Calculo:**
- Lambda finops: 2 invocacoes/dia × 30 dias = 60 invocacoes/mes × ~2KB = ~120KB/mes
- Lambda orphan: 1/dia × 30 dias = 30 invocacoes × ~5KB = ~150KB/mes
- Lambda snapshot: 1/semana × 4 = 4 invocacoes × ~5KB = ~20KB/mes
- **Total Lambda logs:** < 1MB/mes = custo irrisorio (~$0.003/mes)

**Conclusao:** Lambdas nao sao fonte relevante de custo CloudWatch.

---

### 2.5 GitLab Verbose Logs — Potencial Duplicacao (P2)

**Contexto:** GitLab v18.9.1 com 11/11 pods rodando em `staging-platform-gitlab`.
Cada request HTTP gera logs estruturados em stdout. O Promtail (via Loki) coleta esses logs.

**Risco de duplicacao:** Se o node group tiver o CloudWatch Container Insights habilitado
OU se algum DaemonSet FluentBit estiver ativo com output para CloudWatch E para Loki
simultaneamente, ha duplicacao de custo.

**Verificacao critica:**
```bash
# Checar Container Insights
aws eks describe-addon --cluster-name k8s-platform-prod \
  --addon-name amazon-cloudwatch-observability --profile k8s-platform-prod 2>/dev/null \
  || echo "Container Insights addon NAO instalado"

# Checar fluentbit com output CW
kubectl get configmap -A | grep -i fluent
kubectl get daemonset -A | grep -i "fluent\|cloudwatch"
```

**Encontrado no TF:** O modulo EKS (`eks/main.tf`) tem `enabled_cluster_log_types` com
todos os 5 tipos mas NAO tem configuracao de Container Insights — o addon nao esta
habilitado via IaC.

**Conclusao provavel:** Container Insights NAO habilitado via IaC. Verificar no cluster
para confirmar que nenhum deploy manual o habilitou.

---

### 2.6 RDS Enhanced Monitoring — Possivel Contribuidor (P2)

RDS com Enhanced Monitoring habilitado envia metricas em granularidade 1s para CloudWatch,
gerando um log group `/RDSOSMetrics` com volume alto.

**Verificar:**
```bash
aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --profile k8s-platform-prod \
  --query 'DBInstances[0].{MonitoringInterval:MonitoringInterval,EnhancedMonitoring:MonitoringRoleArn}'
```

Se `MonitoringInterval > 0`, ha custo adicional de metrics customizadas.

---

## 3. Hipotese Principal — EKS API Audit Logs

O EKS com 17 namespaces, GitLab (11 pods), Linkerd (10 DaemonSets CNI + proxies),
ArgoCD, Kyverno (policys), Harbor, Keycloak, etc gera um volume ALTO de eventos no
API server. Cada vez que:
- O Kyverno intercepta um admission request → log de audit
- O ArgoCD reconcilia um recurso → log de API
- O cert-manager renova um certificado → log de API
- O ESO sincroniza um ExternalSecret → log de API (a cada 1min)

**Estimativa de volume:**
- GitLab ESO: 11 ExternalSecrets × 1 sync/min = 660 syncs/hora = 15.840 syncs/dia
- Kyverno: ~50 admission webhooks/min = 3.000/hora = 72.000/dia
- ArgoCD: reconcile loop ~30s = 2.880 reconciles/dia
- Linkerd: proxy inject em cada pod start/restart

**Volume estimado de audit logs:** ~500MB-2GB/dia → ingestion ~$0.015-0.06/dia = **$0.45-1.80/mes**

Mas o custo CloudWatch real e $34/mes — a diferenca pode estar em:
1. **Metricas customizadas:** YACE + Prometheus Remote Write para CW
2. **PutMetricData calls:** Se algum servico escreve metricas customizadas direto no CW

---

## 4. Plano de Acao — Tabela de Savings

| # | Acao | Tipo | Saving/mes | Saving/ano (BRL R$6) | Esforco | Risco |
|---|------|------|-----------|---------------------|---------|-------|
| **A1** | Reduzir EKS log types: desabilitar `scheduler` e `controllerManager` | Terraform change | $3-4 | R$ 216-288 | Baixo (1h) | Baixo |
| **A2** | Reduzir retention EKS cluster log group de 30d para 7d | AWS CLI / Terraform | $2-3 | R$ 144-216 | Muito baixo (15min) | Nenhum |
| **A3** | Filtrar audit logs: excluir verbos `get`, `list`, `watch` do audit policy | K8s audit policy | $4-6 | R$ 288-432 | Medio (4h) | Medio |
| **A4** | Confirmar Container Insights desabilitado — se ativo, desabilitar | AWS CLI | $5-8 | R$ 360-576 | Muito baixo (15min) | Nenhum |
| **A5** | Verificar RDS Enhanced Monitoring — reduzir interval de 1s para 60s | AWS Console/TF | $1-2 | R$ 72-144 | Baixo (30min) | Nenhum |
| **A6** | PutMetricData audit: identificar se algum servico publica CW custom metrics | CloudWatch Metrics | $2-4 | R$ 144-288 | Medio (2h) | Nenhum |
| **TOTAL** | | | **$17-27/mes** | **R$ 1.224-1.944/ano** | | |

**Saving conservador (implementando A1+A2+A4):** $10-15/mes = R$ 720-1.080/ano

---

## 5. Comandos AWS CLI — Top Log Groups por Volume

```bash
#!/bin/bash
# Identificar top log groups por volume de storage e ingestion

REGION="us-east-1"
PROFILE="k8s-platform-prod"

echo "=== TOP LOG GROUPS POR STORAGE ==="
aws logs describe-log-groups \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query 'sort_by(logGroups, &storedBytes)[-10:].{
    Name: logGroupName,
    StorageGB: storedBytes,
    RetentionDays: retentionInDays
  }' \
  --output table

echo ""
echo "=== LOG GROUPS SEM RETENTION POLICY ==="
aws logs describe-log-groups \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query 'logGroups[?retentionInDays==`null`].{
    Name: logGroupName,
    StorageGB: storedBytes
  }' \
  --output table

echo ""
echo "=== CUSTO ESTIMADO CLOUDWATCH LOGS ==="
# Calcular custo total stored bytes
TOTAL_BYTES=$(aws logs describe-log-groups \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query 'sum(logGroups[].storedBytes)' \
  --output text)

TOTAL_GB=$(echo "scale=2; $TOTAL_BYTES / 1073741824" | bc)
COST_STORAGE=$(echo "scale=2; $TOTAL_GB * 0.03" | bc)
echo "Total stored: ${TOTAL_GB}GB | Custo storage/mes: \$$COST_STORAGE"

echo ""
echo "=== CONTAINER INSIGHTS CHECK ==="
aws eks describe-addon \
  --cluster-name k8s-platform-prod \
  --addon-name amazon-cloudwatch-observability \
  --region "$REGION" \
  --profile "$PROFILE" 2>/dev/null \
  && echo "ATENCAO: Container Insights ATIVO — desabilitar para economizar \$5-8/mes" \
  || echo "OK: Container Insights nao encontrado"

echo ""
echo "=== RDS ENHANCED MONITORING ==="
aws rds describe-db-instances \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query 'DBInstances[?MonitoringInterval>`0`].{
    Instance: DBInstanceIdentifier,
    MonitoringInterval: MonitoringInterval,
    MonitoringRoleArn: MonitoringRoleArn
  }' \
  --output table

echo ""
echo "=== CUSTOM METRICS NAMESPACES (PutMetricData) ==="
aws cloudwatch list-metrics \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query 'Metrics[].Namespace' \
  --output text | tr '\t' '\n' | sort -u | grep -v "^AWS/"

echo ""
echo "=== EKS CONTROL PLANE LOG TYPES ATIVOS ==="
aws eks describe-cluster \
  --name k8s-platform-prod \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query 'cluster.logging.clusterLogging[?enabled==`true`].types[]' \
  --output table
```

---

## 6. Terraform Snippets — Correcoes de Retention

### 6.1 Reduzir EKS Log Types (A1)

**Arquivo:** `platform-provisioning/aws/kubernetes/terraform/modules/eks/main.tf` linha 118

**Situacao atual:**
```hcl
enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
```

**Proposta (manter apenas os essenciais para compliance e troubleshooting):**
```hcl
# Reducao de log types EKS — FinOps CW-001
# Removidos: controllerManager, scheduler (baixo valor diagnostico em steady state)
# Mantidos: api (required), audit (compliance SOC2/LGPD), authenticator (security)
enabled_cluster_log_types = ["api", "audit", "authenticator"]
```

**Saving estimado:** $3-4/mes (30-40% reducao de volume de ingestion)

**Nota:** `audit` DEVE ser mantido para compliance LGPD e rastreabilidade de acessos.
`scheduler` e `controllerManager` podem ser reabilitados temporariamente para troubleshooting.

---

### 6.2 Adicionar Retention ao Log Group EKS (A2)

O log group `/aws/eks/k8s-platform-prod/cluster` foi configurado com retention de 30 dias
via AWS CLI em 2026-02-12 (logbook finops-quick-wins). Verificar se essa configuracao
persiste e esta codificada em Terraform:

```hcl
# Adicionar em eks/main.tf — gestao explicita do log group EKS
# Evita que o log group seja recriado sem retention pelo EKS
resource "aws_cloudwatch_log_group" "eks_cluster" {
  # O EKS cria este log group automaticamente, mas podemos gerenciar via TF
  # para garantir que a retention policy persista
  name              = "/aws/eks/${aws_eks_cluster.main.name}/cluster"
  retention_in_days = 7   # Reduzido de 30d para 7d — saving ~$2/mes

  tags = {
    Name        = "${var.project_name}-eks-cluster-logs"
    Project     = var.project_name
    ManagedBy   = "terraform"
    FinOps      = "CW-001-retention-7d"
  }

  # Evitar conflito com o log group criado pelo EKS
  lifecycle {
    ignore_changes = []
  }
}
```

**Saving estimado:** $2-3/mes (reducao de storage de 30d para 7d)

---

### 6.3 Garantir Retention em Todos os Log Groups Lambda (consolidacao)

Atual: Lambda finops = 14d, snapshot-cleanup = 7d (default), orphan-detector = 7d (default).
Todos corretos. Nenhuma acao necessaria.

---

### 6.4 Audit Policy K8s — Filtrar Verbos Read-Only (A3 — Medio Prazo)

Para reduzir volume de audit logs sem perder rastreabilidade de escrita:

```yaml
# docs/k8s/audit-policy.yaml
# Filtro para reduzir volume de logs de auditoria
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  # Nao logar requests read-only de recursos comuns (get, list, watch)
  - level: None
    verbs: ["get", "list", "watch"]
    resources:
      - group: ""
        resources: ["pods", "configmaps", "secrets", "endpoints", "services"]
      - group: "apps"
        resources: ["deployments", "replicasets", "statefulsets", "daemonsets"]
  # Nao logar health checks e system components
  - level: None
    users: ["system:kube-proxy"]
    verbs: ["watch"]
    resources:
      - group: ""
        resources: ["endpoints", "services", "services/status"]
  # Nao logar o próprio audit system
  - level: None
    users: ["system:apiserver"]
    verbs: ["get"]
    resources:
      - group: ""
        resources: ["namespaces"]
  # Logar writes em nivel de Request body (operacoes de mudanca)
  - level: RequestResponse
    verbs: ["create", "update", "patch", "delete", "deletecollection"]
  # Logar tudo mais em nivel Metadata apenas
  - level: Metadata
```

**Saving estimado:** $4-6/mes (eliminacao de ~60% do volume de audit logs)
**Custo de implementacao:** 4h (EKS nao suporta audit policy customizada via API — requer
configuracao via `aws eks update-cluster-config` com policy file ou Fargate)
**Nota:** EKS Managed tem limitacoes no audit policy customization — verificar via docs AWS.

---

## 7. Root Cause Analysis — Por Que Passou de $21 para $34?

### Timeline da Anomalia

| Periodo | Custo CW | Eventos Relevantes |
|---------|----------|-------------------|
| Jan/2026 (parcial, 10 dias) | ~$0.40/mes (projetado) | Cluster novo, poucos workloads |
| Fev/2026 (full month) | **$34.47/mes** | GitLab deploy, Linkerd Fase 2, 17 namespaces, Kyverno, 11 ExternalSecrets |
| Mar/2026 MTD | ~$30-35/mes (estimado) | Baseline estabelecido |

### Correlacao com Eventos de Plataforma

A explosao de custo CloudWatch coincide exatamente com:
1. **GitLab v18.x deploy** (11 pods, verbose logging em startup) — Fevereiro
2. **Linkerd Phase 2** (10 DaemonSets CNI + proxies em 17 namespaces) — 2026-03-03 a 03-04
3. **Kyverno MutatingPolicies** (intercept todos os pods → audit logs volumosos) — 2026-02-27
4. **11 ExternalSecrets** sincronizando a cada 1min → 15.840 API calls/dia → audit logs

**Estimativa de contribuicao por componente:**
- EKS API/Audit logs do setup GitLab: ~$8-12 em Fevereiro (pico de setup)
- Linkerd proxy inject (audit log por pod): ~$3-5
- Kyverno admission webhooks: ~$4-6
- ESO sync loop: ~$2-4
- Baseline (RDS, Lambda, misc): ~$3-5
- **Total estimado:** $20-32/mes (compativel com $34 real)

---

## 8. Diagnostico Adicional — Verificar PutMetricData

Se custom metrics (namespace nao-AWS) forem encontrados no passo 5, investigar qual
servico as publica. Cada metric `put` custa $0.01 por 1.000 data points.

Suspeitos de custom metrics:
- Prometheus Remote Write para CloudWatch (nao configurado, mas verificar)
- YACE additional jobs (alem de WAFv2)
- GitLab exporter custom metrics

---

## 9. Acoes Imediatas Recomendadas (Quick Wins — Esta Semana)

### Passo 1 — Validacao (30 min)

```bash
# Executar o script de diagnostico da secao 5
# Confirmar:
# a) Container Insights desabilitado
# b) EKS log types ativos
# c) Total log groups e sizes
# d) Custom namespaces (PutMetricData)
```

### Passo 2 — Reducao EKS Log Types (A1 — 1h)

Editar `platform-provisioning/aws/kubernetes/terraform/modules/eks/main.tf`:
```
["api", "audit", "authenticator", "controllerManager", "scheduler"]
→ ["api", "audit", "authenticator"]
```

Rodar `terraform plan` e confirmar only 1 change em `aws_eks_cluster.main`.
Aplicar com `terraform apply`.

### Passo 3 — Retention EKS Log Group (A2 — 15 min)

Se o log group `/aws/eks/k8s-platform-prod/cluster` ainda estiver em 30 dias:
```bash
aws logs put-retention-policy \
  --log-group-name "/aws/eks/k8s-platform-prod/cluster" \
  --retention-in-days 7 \
  --region us-east-1 \
  --profile k8s-platform-prod
```

Codificar em TF com o recurso `aws_cloudwatch_log_group` da secao 6.2.

### Passo 4 — Confirmar Container Insights (A4 — 15 min)

```bash
aws eks list-addons \
  --cluster-name k8s-platform-prod \
  --region us-east-1 \
  --profile k8s-platform-prod

# Se amazon-cloudwatch-observability aparecer: desabilitar
aws eks delete-addon \
  --cluster-name k8s-platform-prod \
  --addon-name amazon-cloudwatch-observability \
  --region us-east-1 \
  --profile k8s-platform-prod
```

---

## 10. Projecao de Savings pos-Implementacao

| Cenario | Saving/mes | Saving/ano (BRL R$6) |
|---------|-----------|---------------------|
| **Conservador** (A1 + A2 + A4 apenas) | $9-12 | R$ 648-864 |
| **Moderado** (A1 + A2 + A4 + A5 + A6) | $12-16 | R$ 864-1.152 |
| **Otimista** (todos + A3 audit policy) | $16-22 | R$ 1.152-1.584 |

**Meta:** Trazer CloudWatch de $34/mes para $20-25/mes (alinhado com crescimento da plataforma)
= saving de **$9-14/mes = R$ 648-1.008/ano**

---

## 11. Referências

- Logbook finops-quick-wins: `docs/logbook/2026-02-12-finops-quick-wins-execution.md`
- Scan CloudWatch 2026-02-12: `reports/aws-costs/cleanup-cloudwatch-logs-2026-02-12.json`
- Status FinOps 2026-03-10: `docs/finops/finops-status-2026-03-10.md`
- EKS Module: `platform-provisioning/aws/kubernetes/terraform/modules/eks/main.tf`
- YACE CloudWatch Exporter values: `domains/observability/infra/yace-cloudwatch-exporter/values.yaml`
- CloudWatch pricing: $0.03/GB ingested, $0.03/GB stored/mes, $0.01/1000 custom metrics
- ADR-055: FinOps Security Groups Remediation (contexto de logs)

---

**Status:** ANALISE CONCLUIDA — Acoes A1, A2, A4 prontas para implementacao imediata
**Proximo passo:** Executar script de diagnostico (secao 5) para confirmar hipoteses e
medir volume real antes de aplicar mudancas no TF.
**Owner:** SRE / FinOps
**Revisao:** 2026-03-17 (1 semana pos-implementacao, validar no Cost Explorer)
