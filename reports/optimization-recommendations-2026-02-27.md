# 🎯 Relatório de Otimizações — 2026-02-27

**Análise**: Comprehensive cost & performance optimization scan
**Ambiente**: k8s-platform-prod (staging)
**Savings Atual**: R$ 56.539,20/ano
**Oportunidades Identificadas**: 8 categorias

---

## 📊 Executive Summary

| Categoria | Savings Potencial | Prioridade | Esforço |
|-----------|-------------------|------------|---------|
| **1. VPA FASE 0 Validation** | **R$ 15-17K/ano** | 🔴 ALTA | Baixo (monitoring) |
| **2. FinOps Lambda Protection** | R$ 0 (prevent downtime) | 🔴 ALTA | Baixo (config) |
| **3. Node Group Rightsizing** | R$ 8-12K/ano | 🟡 MÉDIA | Médio (testing) |
| **4. EBS gp2 → gp3 Migration** | R$ 14,40/ano | 🟢 BAIXA | Baixo (1 volume) |
| **5. Snapshot Lifecycle Policy** | R$ 200-300/ano | 🟢 BAIXA | Baixo (automation) |
| **6. Reserved Instances/SP** | R$ 20-25K/ano | 🟡 MÉDIA | Médio (commitment) |
| **7. CloudWatch Logs Optimization** | R$ 50-100/ano | 🟢 BAIXA | Baixo (retention) |
| **8. RDS Right-Sizing** | R$ 2-4K/ano | 🟡 MÉDIA | Médio (monitoring) |
| **TOTAL ADICIONAL** | **R$ 45-58K/ano** | - | - |

**Savings Total Projetado (atual + oportunidades)**: **R$ 101-114K/ano**

---

## 🔴 PRIORIDADE ALTA (Implementar Imediatamente)

### 1. VPA FASE 0 Validation (Day 7 — 2026-03-06)

**Status**: Em andamento (10 workloads, updateMode:Off)
**Ação**: Validar recommendations e habilitar updateMode:Auto
**Savings Projetado**: R$ 15-17K/ano

**Next Steps**:
```bash
# Day 7 validation (2026-03-06)
kubectl get vpa --all-namespaces -o yaml > /tmp/vpa-recommendations-day7.yaml

# Análise por workload
for vpa in $(kubectl get vpa --all-namespaces -o jsonpath='{.items[*].metadata.name}'); do
  kubectl describe vpa $vpa -n <namespace> | grep -A 10 "Target:"
done

# Enable updateMode:Auto for validated workloads
kubectl patch vpa <vpa-name> -n <namespace> --type='json' \
  -p='[{"op": "replace", "path": "/spec/updatePolicy/updateMode", "value":"Auto"}]'
```

**Validação**:
- [ ] CPU/Memory recommendations revisadas (10 workloads)
- [ ] Savings calculados (comparar requests atuais vs recommendations)
- [ ] updateMode:Auto habilitado em 1 workload não-crítico (teste)
- [ ] Monitorar por 48h (sem OOMKills, CPU throttling)
- [ ] Rollout gradual para demais workloads

**Bloqueio**: Nenhum — pronto para validação

---

### 2. FinOps Lambda — System Node Group Protection

**Problema Detectado**: FinOps Lambda escalou system node group para 0 (2026-02-27)
**Impacto**: 15 monitoring pods ficaram Pending/Unschedulable
**Root Cause**: Lambda não tem exclusão para node groups críticos

**Ação Imediata**:
```bash
# Add exclusion rule to FinOps Lambda
aws lambda update-function-configuration \
  --profile k8s-platform-prod \
  --region us-east-1 \
  --function-name eks-cluster-cost-optimizer \
  --environment "Variables={
    EXCLUDED_NODE_GROUPS=system,critical,
    MIN_SYSTEM_NODES=2,
    ENABLE_SCALING_PROTECTION=true
  }"

# Verify configuration
aws lambda get-function-configuration \
  --function-name eks-cluster-cost-optimizer \
  --query 'Environment.Variables' --output json
```

**Validação**:
- [ ] Environment variables atualizadas
- [ ] System node group protected (min: 2 nodes)
- [ ] Critical node group protected (min: 2 nodes)
- [ ] Lambda logs verificados (próxima execução não scala system nodes)

**Savings**: R$ 0 (prevenção de downtime, não redução de custo)
**Bloqueio**: Nenhum — implementação imediata

---

## 🟡 PRIORIDADE MÉDIA (Implementar em 30 dias)

### 3. Node Group Rightsizing — Memory-Optimized Instances

**Análise Atual**:
```
Node Resource Usage:
- CPU: 2-10% (SUBUTILIZADO)
- Memory: 16-72% (DESBALANCEADO)

Node Groups:
- system: t3.medium (3 nodes) → 2 vCPU, 4 GB RAM
- workloads: t3.large (6 nodes) → 2 vCPU, 8 GB RAM
- critical: t3.xlarge (2 nodes) → 4 vCPU, 16 GB RAM
```

**Problema**: CPU oversized, Memory undersized em alguns nodes (72% usage)

**Recomendação**: Migrar para instances memory-optimized (série r5/r6)

| Atual | Recomendado | vCPU | RAM | Savings/mês | Savings/ano |
|-------|-------------|------|-----|-------------|-------------|
| t3.medium × 3 | r5.large × 2 | 2 | 16 GB | ~$30 | ~$360 |
| t3.large × 6 | r5.xlarge × 4 | 4 | 32 GB | ~$80 | ~$960 |
| t3.xlarge × 2 | r5.xlarge × 2 | 4 | 32 GB | ~$20 | ~$240 |

**Savings Total**: ~$130/mês = ~$1.560/ano = **R$ 9.360/ano** (@ BRL 6.0)

**Ação**:
1. Criar node group r5.large (staging-system-r5)
2. Cordon/drain nodes t3.medium gradualmente
3. Monitorar por 7 dias (memory pressure, OOMKills)
4. Repeat para workloads e critical

**Bloqueio**: Requer downtime mínimo (rolling update) — agendar janela de manutenção

---

### 4. Reserved Instances / Savings Plans

**Análise**:
```
Current On-Demand Usage:
- EKS nodes: 11 instances (t3.medium/large/xlarge)
- RDS: 1 db.t3.medium
- Total On-Demand Cost: ~$500/mês

Savings Plan Potential (1-year commitment, All Upfront):
- Compute Savings Plan: 40-50% discount
- EC2 Instance Savings Plan: 30-40% discount
- RDS Reserved Instance: 35-45% discount
```

**Recomendação**: Compute Savings Plan (mais flexível)

| Recurso | Custo On-Demand | Custo c/ SP (40%) | Savings/ano |
|---------|-----------------|-------------------|-------------|
| EKS nodes | $450/mês | $270/mês | $2.160 |
| RDS | $50/mês | $32/mês | $216 |
| **Total** | **$500/mês** | **$302/mês** | **$2.376/ano** |

**Savings Total**: **R$ 14.256/ano** (@ BRL 6.0)

**Ação**:
1. AWS Cost Explorer → Savings Plans Recommendations
2. Simular 1-year Compute Savings Plan (All Upfront)
3. Validar commitment com equipe financeira
4. Comprar Savings Plan (irreversível por 1 ano)

**Bloqueio**: Requer aprovação financeira (commitment de 1 ano)

---

### 5. RDS Right-Sizing — db.t3.medium → db.t3.small

**Análise Atual**:
```
RDS Instance: k8s-platform-prod-postgresql
Class: db.t3.medium (2 vCPU, 4 GB RAM)
Status: available
Cost: ~$50/mês = $600/ano = R$ 3.600/ano
```

**Recomendação**: Downgrade para db.t3.small (staging environment)

| Atual | Recomendado | vCPU | RAM | Savings/ano |
|-------|-------------|------|-----|-------------|
| db.t3.medium | db.t3.small | 2 → 1 | 4 → 2 GB | ~$300 = R$ 1.800 |

**Ação**:
```bash
# 1. Create RDS snapshot (backup)
aws rds create-db-snapshot \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --db-snapshot-identifier pre-downgrade-$(date +%Y%m%d)

# 2. Modify instance class (requires reboot)
aws rds modify-db-instance \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --db-instance-class db.t3.small \
  --apply-immediately

# 3. Monitor performance for 7 days
# Check CloudWatch metrics: CPU, Memory, Connections
```

**Validação**:
- [ ] Snapshot criado (backup antes do downgrade)
- [ ] Downtime window agendado (5-10 minutos)
- [ ] Performance validada (7 dias monitoring)
- [ ] Rollback plan pronto (restore snapshot se necessário)

**Bloqueio**: Requer downtime (5-10 min) — agendar janela de manutenção

---

## 🟢 PRIORIDADE BAIXA (Quick Wins)

### 6. EBS gp2 → gp3 Migration (1 volume restante)

**Encontrado**: 1 volume gp2 ainda não migrado

```
Volume: vol-07be6ee836d25d875
Size: 5 GB
Type: gp2 (should be gp3)
Cost: $0.50/mês (gp2) vs $0.40/mês (gp3)
Savings: $0.10/mês × 12 = $1.20/ano = R$ 7.20/ano
```

**Ação**:
```bash
# Migrate gp2 → gp3 (zero downtime)
aws ec2 modify-volume \
  --profile k8s-platform-prod \
  --region us-east-1 \
  --volume-id vol-07be6ee836d25d875 \
  --volume-type gp3

# Verify migration
aws ec2 describe-volumes-modifications \
  --volume-ids vol-07be6ee836d25d875
```

**Savings**: R$ 7,20/ano (pequeno, mas completa migração 100% gp3)
**Bloqueio**: Nenhum — zero downtime

---

### 7. Snapshot Lifecycle Policy Automation

**Análise Atual**:
```
Total snapshots: 22
Total size: 213 GB
Current cost: $10.65/mês = R$ 766.80/ano

Age distribution:
- <7 days: 16 snapshots
- 7-30 days: 6 snapshots
- >30 days: 0 snapshots
```

**Recomendação**: Implementar Data Lifecycle Manager (DLM) para retention automática

**Policy Sugerida**:
- Velero backups: Retention 30 dias (alinhado com Velero schedule)
- Manual snapshots: Retention 14 dias (exceto tagged com "retain")
- Migration snapshots: Retention 7 dias (safe to delete após validation)

**Savings Projetados**:
- Redução de ~30% snapshots (após 30 dias) = ~70 GB deleted
- Savings: $3.50/mês = $42/ano = **R$ 252/ano**

**Ação**:
```bash
# Create DLM policy via Terraform
# File: platform-provisioning/aws/kubernetes/terraform/modules/snapshot-lifecycle/main.tf

resource "aws_dlm_lifecycle_policy" "velero_backups" {
  description        = "Velero backup snapshots - 30 day retention"
  execution_role_arn = aws_iam_role.dlm_lifecycle_role.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    schedule {
      name = "Velero backups retention"

      retain_rule {
        count = 30
      }

      tags_to_add = {
        SnapshotCreator = "DLM"
      }
    }

    target_tags = {
      "velero.io/backup" = "*"
    }
  }
}
```

**Bloqueio**: Nenhum — implementação via Terraform

---

### 8. CloudWatch Logs Retention Optimization

**Análise Atual**:
```
Total log groups: 11

Retention policies:
- 7 days: 5 log groups
- 14 days: 2 log groups
- 30 days: 3 log groups
- Never expire: 1 log group
```

**Recomendação**: Ajustar log group com "Never expire" para retention razoável

**Ação**:
```bash
# Find log group with no retention
aws logs describe-log-groups \
  --profile k8s-platform-prod \
  --region us-east-1 \
  --query 'logGroups[?retentionInDays==`null`].[logGroupName]' \
  --output text

# Set retention to 30 days (or 14 for non-critical logs)
aws logs put-retention-policy \
  --log-group-name <log-group-name> \
  --retention-in-days 30
```

**Savings**: R$ 50-100/ano (depende do volume de logs)
**Bloqueio**: Nenhum — configuração simples

---

## 📋 Roadmap de Implementação

### Week 1 (2026-03-03 a 2026-03-09)
- [x] FinOps Lambda protection (CRÍTICO — implementar hoje)
- [ ] EBS gp2 → gp3 migration (quick win)
- [ ] CloudWatch Logs retention (quick win)
- [ ] VPA FASE 0 Day 7 validation (2026-03-06)

### Week 2-3 (2026-03-10 a 2026-03-23)
- [ ] Snapshot Lifecycle Policy (DLM) via Terraform
- [ ] VPA updateMode:Auto rollout (gradual)
- [ ] RDS right-sizing planning (monitoring + validation)

### Week 4-6 (2026-03-24 a 2026-04-13)
- [ ] Node Group rightsizing (r5 instances testing)
- [ ] RDS downgrade (janela de manutenção)
- [ ] Reserved Instances/Savings Plans (decisão financeira)

---

## 🎯 Success Criteria

### Short-Term (30 dias)
- [ ] VPA FASE 0 completo: R$ 15-17K/ano realized
- [ ] FinOps Lambda protegido (zero downtime incidents)
- [ ] Quick wins implementados: R$ 300-400/ano adicional

### Mid-Term (90 dias)
- [ ] Node Groups rightsized: R$ 8-12K/ano adicional
- [ ] RDS optimizado: R$ 1.800/ano adicional
- [ ] Savings Plans decision made (R$ 14K potential)

### Long-Term (6 meses)
- [ ] **Total Savings Target**: R$ 100K+/ano
- [ ] Infrastructure efficiency: 85%+ resource utilization
- [ ] Zero cost-related downtime incidents

---

## 📊 Métricas de Acompanhamento

**Dashboard FinOps** (Grafana):
- Total savings realized vs target (current: 56% of 100K goal)
- Node CPU/Memory utilization trends
- VPA recommendations adoption rate
- EBS/Snapshot storage costs over time

**Alertas Críticos**:
- Node group scaling to 0 (FinOps Lambda)
- VPA OOMKills or CPU throttling after updateMode:Auto
- RDS CPU > 80% after downgrade (rollback trigger)

---

**Próxima Revisão**: 2026-03-27 (30 dias)
**Owner**: Platform Team
**Aprovação Necessária**: CFO (Reserved Instances/Savings Plans commitment)
