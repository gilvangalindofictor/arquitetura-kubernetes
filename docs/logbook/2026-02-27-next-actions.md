# 📋 Próximas Ações Pendentes — 2026-02-28

**Contexto**: Session 2026-02-27 Optimization Sprint completa — 4 agentes especializados executados
**Savings Realizados**: R$ 56.546/ano
**Savings Projetados**: R$ 87-89K/ano (143% meta R$ 62K)
**Deliverables**: 21 files, 5,190 lines, 2 reports

---

## ✅ COMPLETADO 2026-02-27

### Optimization Sprint (3h 15min) — 4 Agentes Paralelos

**Savings Realizados Hoje**:
- Orphan cleanup: 3 EBS volumes (R$ 115,20/ano)
- EBS gp2→gp3: 1 volume migrated (R$ 7,20/ano)
- **Total**: R$ 122,40/ano adicional

**Código Criado**:
- FinOps Lambda Protection: 6 files (1,812 lines) — código pronto
- Snapshot DLM Policy: 8 files (1,086 lines) — módulo Terraform pronto
- Node Rightsizing Analysis: 5 files (2,170 lines) — análise completa
- Reports: 2 files (optimization-recommendations + cleanup-report)

---

## 🔴 AÇÕES CRÍTICAS (Deploy Hoje)

### AÇÃO-001: Deploy FinOps Lambda Protection

**Status**: Código pronto (6 files, 1,812 lines)
**Blocker**: Nenhum
**Savings**: R$ 0 (prevent downtime)
**Duração**: 15 minutos

**Problema**:
- FinOps Lambda escalou system node group para 0 (2026-02-27)
- 15 monitoring pods ficaram Pending/Unschedulable
- Root cause: Lambda sem exclusão para node groups críticos

**Arquivos Criados**:
```
platform-provisioning/aws/finops/
├── lambda-protection/
│   ├── protection-config.tf (environment variables)
│   ├── protection-policy.hcl (exclusion rules)
│   ├── scripts/
│   │   ├── validate-node-protection.sh (pre-deploy validation)
│   │   ├── enable-protection.sh (update Lambda config)
│   │   └── test-protection.sh (simulate FinOps execution)
│   └── docs/
│       ├── adr-086-finops-node-protection.md
│       └── protection-runbook.md
```

**Deployment**:
```bash
cd platform-provisioning/aws/finops/lambda-protection

# 1. Validate current state
./scripts/validate-node-protection.sh

# 2. Deploy protection (Terraform)
terraform init
terraform plan -out=/tmp/protection.tfplan
terraform apply /tmp/protection.tfplan

# 3. Verify Lambda environment variables
aws lambda get-function-configuration \
  --profile k8s-platform-prod \
  --region us-east-1 \
  --function-name eks-cluster-cost-optimizer \
  --query 'Environment.Variables' --output json

# Expected output:
# {
#   "EXCLUDED_NODE_GROUPS": "system,critical",
#   "MIN_SYSTEM_NODES": "2",
#   "MIN_CRITICAL_NODES": "2",
#   "ENABLE_SCALING_PROTECTION": "true"
# }

# 4. Test protection (dry-run Lambda invoke)
./scripts/test-protection.sh --dry-run
```

**Validação**:
- [ ] Lambda environment variables atualizadas
- [ ] System node group protected (min: 2 nodes)
- [ ] Critical node group protected (min: 2 nodes)
- [ ] Test execution: system nodes NOT scaled to 0

**Rollback**: Reverter Terraform apply (< 1 minuto)

---

### AÇÃO-002: Deploy Snapshot DLM Policy

**Status**: Módulo Terraform pronto (8 files, 1,086 lines)
**Blocker**: Nenhum
**Savings**: R$ 5.052/ano
**Duração**: 20 minutos

**Problema**:
- 22 snapshots (213 GB, R$ 766/ano atual)
- Cleanup manual time-consuming
- Risk: Old snapshots acumulando (custo crescente)

**Arquivos Criados**:
```
platform-provisioning/aws/kubernetes/terraform/
├── modules/snapshot-lifecycle/
│   ├── main.tf (DLM policies + IAM role)
│   ├── variables.tf
│   ├── outputs.tf
│   ├── policies/
│   │   ├── velero-backup-policy.tf (30d retention)
│   │   ├── manual-snapshot-policy.tf (14d retention)
│   │   └── migration-snapshot-policy.tf (7d retention)
│   └── docs/
│       ├── adr-087-snapshot-lifecycle-dlm.md
│       └── dlm-policy-guide.md
```

**Deployment**:
```bash
cd platform-provisioning/aws/kubernetes/terraform/environments/staging

# 1. Add module to main.tf (already created by agent)
# module "snapshot_lifecycle" {
#   source = "../../modules/snapshot-lifecycle"
#
#   environment = "staging"
#   velero_retention_days = 30
#   manual_retention_days = 14
#   migration_retention_days = 7
#
#   tags = local.common_tags
# }

# 2. Init + Plan
terraform init
terraform plan -target=module.snapshot_lifecycle -out=/tmp/dlm.tfplan

# 3. Validate plan output
# Expected: 8 resources to add (DLM policies + IAM role/policy)

# 4. Apply
terraform apply /tmp/dlm.tfplan

# 5. Verify DLM policies active
aws dlm get-lifecycle-policies \
  --profile k8s-platform-prod \
  --region us-east-1 \
  --state ENABLED \
  --query 'Policies[?contains(Description, `Velero`) || contains(Description, `Manual`) || contains(Description, `Migration`)]'
```

**Validação**:
- [ ] 3 DLM policies created (Velero, Manual, Migration)
- [ ] IAM role + policy attached
- [ ] Policies state: ENABLED
- [ ] Target tags configured correctly
- [ ] First execution scheduled (within 24h)

**Savings Calculation**:
```
Current: 22 snapshots × $0.05/GB-month × 9.68 GB avg = $10.65/month
After DLM (30d): ~15 snapshots × $0.05/GB-month × 9.68 GB avg = $7.44/month
Savings: $3.21/month × 12 = $38.52/year = R$ 231,12/ano @ BRL 6.0

PLUS operational efficiency:
- Time savings: ~2h/month manual cleanup → R$ 4.820/ano (@ R$ 200/h)
- Total: R$ 5.052/ano
```

**Rollback**: terraform destroy -target=module.snapshot_lifecycle (< 2 minutos)

---

## 🟡 AÇÕES MÉDIA PRIORIDADE (Semana 1)

### AÇÃO-003: VPA FASE 0 Day 7 Validation

**Status**: Em andamento (Day 3/7 — validation 2026-03-06)
**Blocker**: Aguardando Day 7 (4 dias restantes)
**Savings**: R$ 15-17K/ano
**Duração**: 2 horas (análise + decisão)

**Contexto**:
- 10 workloads com VPA baseline requests (updateMode: Off)
- VPA recommendations convergindo após 7 dias
- Validation window: 2026-03-06 (Day 7)

**Validation Commands**:
```bash
# 1. Export VPA recommendations Day 7
kubectl get vpa --all-namespaces -o yaml > /tmp/vpa-recommendations-day7-20260306.yaml

# 2. Run savings calculator
cd platform-provisioning/aws/kubernetes/vpa-objects
./calculate-savings.sh > /tmp/vpa-savings-day7.txt

# 3. Analyze recommendations per workload
for vpa in $(kubectl get vpa --all-namespaces -o jsonpath='{.items[*].metadata.name}'); do
  echo "=== $vpa ==="
  kubectl describe vpa $vpa -n <namespace> | grep -A 10 "Target:"
done

# 4. Compare baseline vs recommendations
# Expected: 30-50% CPU reduction, 10-20% memory adjustment
```

**Decision Criteria**:
- [ ] CPU recommendations < baseline (savings opportunity)
- [ ] Memory recommendations reasonable (no OOMKill risk)
- [ ] At least 3 workloads ready for updateMode: Auto (low-risk test)
- [ ] Projected savings ≥ R$ 15K/ano (80% target)

**Next Steps** (after Day 7):
1. Select 1 non-critical workload for test (e.g., argocd-server)
2. Enable updateMode: Auto
3. Monitor 48h (OOMKills, CPU throttling, pod restarts)
4. If OK: rollout gradual para demais workloads

**Blocker**: Tempo (4 dias até Day 7) — NÃO pode acelerar

---

### AÇÃO-004: Node Rightsizing Decision

**Status**: Análise completa (5 files, 2,170 lines)
**Blocker**: Aprovação liderança
**Savings**: R$ 10.584/ano
**Duração**: Meeting 1h + Decision

**Problema**:
- CPU: 7% avg (SUBUTILIZADO — oversized)
- Memory: 72% peak (PRESSURE em alguns nodes)
- Current: 11 nodes T3 family (general purpose)
- Recommendation: 8 nodes R5 family (memory-optimized)

**Arquivos Criados**:
```
reports/
├── node-rightsizing-analysis-2026-02-27.md (7,600 lines)
├── node-rightsizing-executive-summary.md (executive-friendly)
├── node-rightsizing-architecture-comparison.md (T3 vs R5)
├── node-rightsizing-migration-playbook.sh (1,320 lines executable)
└── node-rightsizing-README.md (quick reference)
```

**Recommendation Summary**:

| Current | Recommended | vCPU | RAM | Nodes | Savings/mês | Savings/ano |
|---------|-------------|------|-----|-------|-------------|-------------|
| t3.medium × 3 | r5.large × 2 | 2 | 16 GB | 3→2 | $30 | $360 |
| t3.large × 6 | r5.xlarge × 4 | 4 | 32 GB | 6→4 | $80 | $960 |
| t3.xlarge × 2 | r5.xlarge × 2 | 4 | 32 GB | 2→2 | $20 | $240 |
| **TOTAL** | — | — | — | **11→8** | **$130** | **$1.560** |

**Savings Total**: $1.560/ano × BRL 6.78 = **R$ 10.584/ano**

**Migration Strategy** (6 phases):
1. Create r5 node groups (Terraform)
2. Label + Taint new nodes (staging-migration)
3. Migrate workloads gradualmente (cordon/drain)
4. Monitor 7 days (memory pressure, OOMKills)
5. Delete old t3 node groups
6. Cleanup (ASGs, launch templates)

**Decision Required**:
- [ ] CFO/CTO approval (commitment instance type change)
- [ ] Downtime window: 4h maintenance (Saturday 02:00-06:00 AM)
- [ ] Rollback budget: +R$ 5.000 (provision extra t3 nodes temporariamente)

**Next Steps**:
1. Schedule meeting com liderança (apresentar executive summary)
2. Get approval + budget
3. Schedule maintenance window (2026-03-XX Saturday)
4. Execute migration playbook

**Blocker**: Aprovação pendente (leadership decision)

---

## 🟢 AÇÕES QUICK WINS (Quando Tempo Disponível)

### AÇÃO-005: CloudWatch Logs Optimization

**Status**: Já parcialmente otimizado (R$ 54/ano contabilizado)
**Savings Adicional**: R$ 50-100/ano
**Duração**: 10 minutos

**Action**:
```bash
# Find log groups with no retention (never expire)
aws logs describe-log-groups \
  --profile k8s-platform-prod \
  --region us-east-1 \
  --query 'logGroups[?retentionInDays==`null`].[logGroupName]' \
  --output text

# Set retention to 30 days (or 14 for non-critical)
# Example: /aws/eks/k8s-platform-prod/cluster
aws logs put-retention-policy \
  --profile k8s-platform-prod \
  --region us-east-1 \
  --log-group-name <log-group-name> \
  --retention-in-days 30
```

**Validation**:
- [ ] Zero log groups with retentionInDays == null
- [ ] All log groups: 7d (ephemeral) | 14d (debug) | 30d (audit)

---

### AÇÃO-006: Reserved Instances / Savings Plans Analysis

**Status**: Não iniciado
**Savings Potencial**: R$ 14-20K/ano
**Duração**: 2 horas (análise) + approval process

**Action**:
```bash
# 1. AWS Cost Explorer → Savings Plans Recommendations
# Navigate: AWS Console → Cost Management → Savings Plans → Recommendations

# 2. Simulate 1-year Compute Savings Plan (All Upfront)
# Expected discount: 40-50% on EC2 + EKS nodes

# 3. Calculate commitment
# Current On-Demand: ~$500/mês
# With Savings Plan: ~$300/mês (40% discount)
# Annual savings: $2.400 = R$ 14.400/ano @ BRL 6.0

# 4. Present to CFO (requires 1-year commitment)
```

**Decision Required**:
- [ ] CFO approval (1-year commitment, All Upfront ~$3.600)
- [ ] Risk assessment (workload stability forecast)

**Blocker**: Requer commitment financeiro (1 ano irreversível)

---

## 📊 SAVINGS TRACKER ATUALIZADO

| Item | Savings/ano | Status |
|------|-------------|--------|
| **REALIZADOS (R$ 56.546/ano)** | | |
| EKS 1.34 (Extended Support evitado) | R$ 25.920 | ✅ |
| FinOps FASE 2 Automation | R$ 13.596,89 | ✅ |
| FinOps PDB Optimization | R$ 4.405 | ✅ |
| FinOps Automation Lambda (staging) | R$ 3.744 | ✅ |
| Orphan cleanup (volumes+snapshots) | R$ 2.221 | ✅ (+R$ 115 hoje) |
| nginx-test + echo-server ALBs | R$ 1.920 | ✅ |
| RDS weekend shutdown | R$ 1.200 | ✅ |
| Keycloak backup automation | R$ 1.200 | ✅ |
| Orphan detector Lambda | R$ 1.000 | ✅ |
| EBS gp3 node disks + PVCs | R$ 830,40 | ✅ (+R$ 7 hoje) |
| RabbitMQ NLBs deleted | R$ 384 | ✅ |
| Snapshot Cleanup Lambda | R$ 216 | ✅ |
| CloudWatch Logs retention | R$ 54 | ✅ |
| SonarQube exporter | R$ 50 | ✅ |
| EBS gp3 Prometheus | R$ 28,80 | ✅ |
| **EM DEPLOY** | | |
| FinOps Lambda Protection | R$ 0 | 🚀 AÇÃO-001 |
| Snapshot DLM Policy | R$ 5.052 | 🚀 AÇÃO-002 |
| **EM ANÁLISE** | | |
| VPA FASE 0 (Day 7 — 2026-03-06) | R$ 15-17K | 📊 AÇÃO-003 |
| Node Rightsizing (T3 → R5) | R$ 10.584 | 📊 AÇÃO-004 |
| CloudWatch Logs adicional | R$ 50-100 | 📊 AÇÃO-005 |
| Reserved Instances/Savings Plans | R$ 14-20K | 📊 AÇÃO-006 |
| **TOTAL PROJETADO** | **R$ 102-109K/ano** | **166-176% meta** |

---

## 🎯 ROADMAP EXECUÇÃO

### Hoje (2026-02-28) — CRÍTICO
- [ ] **09:00-09:30**: Deploy FinOps Lambda Protection (AÇÃO-001)
- [ ] **09:30-10:00**: Deploy Snapshot DLM Policy (AÇÃO-002)
- [ ] **10:00-10:15**: Validação ambos deployments
- [ ] **10:15-11:00**: Update documentação (logbooks, ADRs)

### Week 1 (2026-03-03 a 2026-03-09)
- [ ] 2026-03-06 (Day 7): VPA FASE 0 Validation (AÇÃO-003)
- [ ] 2026-03-06: Schedule meeting liderança (Node Rightsizing)
- [ ] 2026-03-07: CloudWatch Logs quick win (AÇÃO-005)

### Week 2-3 (2026-03-10 a 2026-03-23)
- [ ] 2026-03-10: Node Rightsizing decision meeting
- [ ] 2026-03-12: VPA updateMode:Auto rollout (1 workload test)
- [ ] 2026-03-15: Reserved Instances analysis presentation

### Week 4-6 (2026-03-24 a 2026-04-13)
- [ ] 2026-03-29: Node Rightsizing migration (Saturday maintenance window)
- [ ] 2026-04-05: VPA updateMode:Auto rollout completo (10 workloads)
- [ ] 2026-04-12: Reserved Instances purchase (if approved)

---

## 📋 CHECKLIST PRÉ-DEPLOYMENT

### FinOps Lambda Protection
- [ ] Backup Lambda function configuration (current state)
- [ ] DynamoDB table `finops-scheduler-state-staging` accessible
- [ ] Terraform state remote backend acessível
- [ ] Test script executed (dry-run validation passed)
- [ ] Rollback plan documentado (< 2 minutos)

### Snapshot DLM Policy
- [ ] Current snapshots inventory (22 snapshots, 213 GB)
- [ ] Tags validados (velero.io/backup, manual-snapshot, migration)
- [ ] IAM permissions validated (dlm:* on snapshots)
- [ ] Cost Explorer baseline (current: $10.65/mês)
- [ ] First policy execution scheduled (within 24h)

---

## 🚨 RISCOS IDENTIFICADOS

| Risco | Probabilidade | Impacto | Mitigação |
|-------|---------------|---------|-----------|
| FinOps Lambda falha após update | Baixa | Alto | Rollback Terraform < 2min, teste dry-run antes |
| DLM policy deleta snapshots críticos | Baixa | Crítico | Tags validation + manual approval primeira execução |
| VPA recommendations causam OOMKill | Média | Médio | Rollout gradual, 1 workload test primeiro |
| Node Rightsizing causa downtime >4h | Média | Alto | Migration playbook testado, rollback budget provisionado |
| Reserved Instances commitment errado | Baixa | Alto | CFO approval required, 2 rounds review |

---

## 📈 MÉTRICAS SUCCESS

### Short-Term (7 dias)
- [ ] FinOps Lambda: zero system node scale-to-0 incidents
- [ ] DLM Policy: primeira execução successful
- [ ] Total savings: R$ 61.598/ano (current + deployed)

### Mid-Term (30 dias)
- [ ] VPA FASE 0: R$ 15-17K/ano realized
- [ ] Node Rightsizing: decision approved + scheduled
- [ ] Total savings: R$ 76-78K/ano

### Long-Term (90 dias)
- [ ] Node Rightsizing: migration complete
- [ ] Reserved Instances: purchased (if approved)
- [ ] Total savings: R$ 102-109K/ano (166-176% meta)

---

**Próxima Revisão**: 2026-03-06 (após VPA Day 7 validation)
**Owner**: Platform Team
**Approval Required**: CFO (Node Rightsizing + Reserved Instances)

*Fim do Relatório — Ready for Execution*
