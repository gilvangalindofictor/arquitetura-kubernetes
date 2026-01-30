# FinOps Automation - Plano de Próximas Etapas

**Data de Criação**: 2026-01-30
**Última Atualização**: 2026-01-30
**Framework**: executor-terraform.md (Multi-Agent Decision Making)
**Status**: STAGING Deploy Completo | Manual Testing In Progress

---

## 🎯 Objetivo Geral

Completar validação e habilitar automação FinOps para reduzir custos de staging em 25.9% (R$ 12,787.92/ano).

---

## 📊 Status Atual

### ✅ Completo
- [x] Módulo Terraform desenvolvido (12 resources)
- [x] Deploy em staging environment
- [x] Correção de 6 bugs críticos
- [x] Teste manual Lambda START (100% sucesso)
- [x] Teste manual Lambda STOP (funcional, shutdown não-graceful)
- [x] Análise multi-agente para issue de PDBs

### 🔄 Em Progresso
- [ ] Testes manuais adicionais (3-5 testes esta semana)
- [ ] Monitoramento de logs CloudWatch
- [ ] Validação de circuit breaker DynamoDB

### 📋 Pendente
- [ ] Otimização de PDBs (próxima sprint)
- [ ] Habilitação de automação (após 1 semana)
- [ ] Deploy em produção (Marco 3)

---

## 📅 Roadmap Detalhado

### FASE 1: Validação Manual (Semana 1 - Em Progresso)
**Período**: 2026-01-30 a 2026-02-06
**Responsável**: DevOps Team
**Prioridade**: HIGH

#### Objetivos
- Executar 3-5 testes manuais adicionais de startup/shutdown
- Validar comportamento em diferentes condições
- Monitorar logs e métricas CloudWatch
- Verificar circuit breaker state no DynamoDB

#### Tarefas

**1.1 Testes de Startup** ⏳
```bash
# Executar em horários variados
export AWS_PROFILE=k8s-platform-prod

# Teste em horário comercial
aws lambda invoke --function-name finops-scheduler-start-staging response.json

# Validações:
# - Verificar logs: aws logs tail /aws/lambda/finops-scheduler-start-staging --follow
# - Verificar nodes: kubectl get nodes -o wide
# - Verificar RDS: aws rds describe-db-instances --db-instance-identifier k8s-platform-prod-postgresql
# - Tempo de startup: <5min esperado
```

**1.2 Testes de Shutdown** ⏳
```bash
# Executar após ambiente estabilizado (>30min uptime)
aws lambda invoke --function-name finops-scheduler-stop-staging response.json

# Validações:
# - Verificar desired=0: aws eks describe-nodegroup --cluster-name k8s-platform-prod --nodegroup-name system
# - Monitorar drain: kubectl get nodes (watch scheduling disabled)
# - Tempo de shutdown: 10-15min esperado (aceitável para staging)
# - RDS status: stopping → stopped
```

**1.3 Validação Circuit Breaker** ⏳
```bash
# Verificar estado no DynamoDB
aws dynamodb get-item \
  --table-name finops-scheduler-state-staging \
  --key '{"environment":{"S":"staging"}}'

# Validar campos:
# - circuit_breaker_state: "CLOSED" (esperado)
# - startup_failures: 0
# - shutdown_failures: 0
# - last_startup: timestamp ISO8601
# - last_shutdown: timestamp ISO8601
```

**1.4 Monitoramento CloudWatch** ⏳
- [ ] Verificar métricas Lambda (duration, errors, invocations)
- [ ] Revisar logs para warnings/errors
- [ ] Validar alarms configurados (não devem disparar)

#### Critérios de Sucesso
- ✅ 5 testes completos sem falhas críticas
- ✅ Circuit breaker permanece CLOSED
- ✅ Logs sem erros inesperados
- ✅ Métricas dentro do esperado (duration <2s, no errors)
- ✅ Documentação de qualquer anomalia

#### Riscos
- **BAIXO**: Falha de Lambda por throttling (mitigado: baixa frequência de testes)
- **MÉDIO**: RDS 7-day stop limitation (mitigado: monitorar last_stop_time)

---

### FASE 2: Otimização de PDBs (Semana 2-3 - Próxima Sprint)
**Período**: 2026-02-06 a 2026-02-20
**Responsável**: Platform Team + DevOps
**Prioridade**: MEDIUM

#### Objetivos
- Implementar Cenário 3+4 da análise multi-agente
- Reduzir tempo de shutdown de 10-15min → 2-3min
- Manter HA dos serviços (N-1 sempre disponível)

#### Tarefas

**2.1 Criar ADR-025** 📋
```markdown
## ADR-025 - Adjust PDBs for Graceful Node Drain

**Date**: 2026-02-06
**Status**: Proposed → Accepted (após validação)
**Context**: FinOps Lambda STOP funcional mas shutdown não-graceful (10-15min) devido a PDBs restritivos
**Decision**: Ajustar PDBs para maxUnavailable=1 e DaemonSets com tolerations curtas
**Consequences**:
- Shutdown reduz 10-15min → 2-3min (saving: $22/ano)
- Melhora upgrades de cluster (~2h/upgrade saved)
- Mantém HA (N-1 sempre disponível)
**Alternatives Rejected**:
- Pre-drain hook (alto risco security - BLOQUEADO)
- Status quo (desperdiça recursos)
```

**2.2 Branch e Desenvolvimento** 📋
```bash
git checkout -b feat/improve-pdb-drain-behavior

# Estrutura:
# - platform-provisioning/aws/kubernetes/terraform/envs/marco2/modules/
#   - kube-prometheus-stack/values-overrides.yaml (PDBs)
#   - loki/values-overrides.yaml (PDBs)
#   - fluent-bit/values-overrides.yaml (Tolerations)
# - kubectl-manifests/
#   - coredns-pdb-override.yaml
#   - calico-pdb-override.yaml
```

**2.3 Helm Values - Loki** 📋
```yaml
# modules/loki/values-overrides.yaml
loki:
  gateway:
    podDisruptionBudget:
      maxUnavailable: 1  # Was: 0

  backend:
    podDisruptionBudget:
      maxUnavailable: 1

  read:
    podDisruptionBudget:
      maxUnavailable: 1

  write:
    podDisruptionBudget:
      maxUnavailable: 1
```

**2.4 Helm Values - Prometheus Stack** 📋
```yaml
# modules/kube-prometheus-stack/values-overrides.yaml
prometheus:
  prometheusSpec:
    podDisruptionBudget:
      maxUnavailable: 1

grafana:
  podDisruptionBudget:
    maxUnavailable: 1

alertmanager:
  alertmanagerSpec:
    podDisruptionBudget:
      maxUnavailable: 1
```

**2.5 DaemonSet Tolerations** 📋
```yaml
# modules/fluent-bit/values-overrides.yaml
tolerations:
  - key: "node.kubernetes.io/not-ready"
    operator: "Exists"
    effect: "NoExecute"
    tolerationSeconds: 10  # Permite drain rápido

  - key: "node.kubernetes.io/unreachable"
    operator: "Exists"
    effect: "NoExecute"
    tolerationSeconds: 10

# modules/kube-prometheus-stack/values-overrides.yaml (node-exporter)
prometheus-node-exporter:
  tolerations:
    - key: "node.kubernetes.io/not-ready"
      operator: "Exists"
      effect: "NoExecute"
      tolerationSeconds: 10
```

**2.6 CoreDNS e Calico PDB Overrides** 📋
```yaml
# kubectl-manifests/coredns-pdb-override.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: coredns
  namespace: kube-system
spec:
  maxUnavailable: 1  # Was implicitly 0
  selector:
    matchLabels:
      k8s-app: kube-dns
```

**2.7 Terraform Integration** 📋
```hcl
# modules/kubectl-manifests/main.tf
resource "kubectl_manifest" "coredns_pdb" {
  yaml_body = file("${path.module}/manifests/coredns-pdb-override.yaml")
}

resource "kubectl_manifest" "calico_pdb" {
  yaml_body = file("${path.module}/manifests/calico-pdb-override.yaml")
}
```

**2.8 Testes em Staging** 📋
```bash
# Após terraform apply
terraform apply

# Validar PDBs atualizados
kubectl get pdb -A -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace,MAX-UNAVAILABLE:.spec.maxUnavailable,ALLOWED:.status.disruptionsAllowed

# Teste de shutdown
aws lambda invoke --function-name finops-scheduler-stop-staging response.json

# Medir tempo com timer
time kubectl get nodes --watch
# Expectativa: 2-3min até todos nodes terminarem

# Validar logs não perdidos
# - Query Loki últimos 5min
# - Verificar fluent-bit graceful termination
```

**2.9 Validação de Failover** 📋
```bash
# Simular node failure durante drain
kubectl delete pod loki-gateway-xxxxx --grace-period=0 --force

# Validar:
# - Novo pod criado em <30s
# - Serviço não teve downtime (check ALB health)
# - PDB permitiu eviction (ALLOWED=1)
```

#### Critérios de Sucesso
- ✅ Shutdown reduz para 2-3min
- ✅ PDBs mantêm HA (ALLOWED=1, mínimo N-1 pods)
- ✅ Logs não perdidos durante drain
- ✅ Failover funciona normalmente (N-1 replica handling)
- ✅ Upgrades de cluster mais rápidos (validar com dry-run)

#### Riscos
- **MÉDIO**: PDB mal configurado pode causar downtime (mitigado: testar em staging primeiro)
- **BAIXO**: Resistência de stakeholders (mitigado: documentar em ADR com aprovação)

---

### FASE 3: Habilitar Automação (Semana 4 - Após Validação)
**Período**: 2026-02-20 a 2026-02-27
**Responsável**: DevOps Team
**Prioridade**: HIGH

#### Objetivos
- Habilitar EventBridge rules para execução automática
- Monitorar primeiras execuções em produção
- Validar economia real vs projetada

#### Tarefas

**3.1 Update Terraform Config** 📋
```hcl
# envs/finops-staging/main.tf
module "finops_automation" {
  source = "../../modules/finops-automation"

  # Mudar de false → true
  enable_automation = true  # ✅ HABILITAR APÓS 1 SEMANA

  # Schedules (já configurados)
  startup_schedule  = "cron(0 11 ? * MON-FRI *)"  # 08:00 BRT
  shutdown_schedule = "cron(0 21 ? * MON-FRI *)"  # 18:00 BRT
}
```

**3.2 Deploy** 📋
```bash
export AWS_PROFILE=k8s-platform-prod
cd platform-provisioning/aws/kubernetes/terraform/envs/finops-staging

terraform plan -out=tfplan
# Validar: 2 resources to change (EventBridge rules state: DISABLED → ENABLED)

terraform apply tfplan

# Validar rules ativas
aws events list-rules --name-prefix finops-
```

**3.3 Monitoramento Primeira Semana** 📋
```bash
# Verificar execuções diárias
aws lambda get-function --function-name finops-scheduler-start-staging
aws lambda get-function --function-name finops-scheduler-stop-staging

# Monitorar logs
aws logs tail /aws/lambda/finops-scheduler-start-staging --follow --since 1h
aws logs tail /aws/lambda/finops-scheduler-stop-staging --follow --since 1h

# Verificar métricas CloudWatch
# - Invocations: 10/semana esperado (5 startups + 5 shutdowns)
# - Errors: 0 esperado
# - Duration: ~1.5s avg
# - Throttles: 0

# Validar alarms não disparados
aws cloudwatch describe-alarms --alarm-names \
  finops-staging-startup-failures \
  finops-staging-shutdown-failures \
  finops-staging-startup-duration-high
```

**3.4 Validação de Economia** 📋
```bash
# Após 1 mês de operação, verificar Cost Explorer
# Filtros:
# - Service: Amazon Elastic Compute Cloud
# - Tag: Environment=staging
# - Período: Compare mês atual vs mês anterior

# Savings esperados:
# - EC2: ~$140/mês reduction (7 nodes × 10h/dia saved)
# - EBS: ~$2/mês reduction (volumes attached only when running)
# - Data Transfer: ~$5/mês reduction
# Total: ~$147/mês = ~R$ 882/mês (vs R$ 1,065 projetado = 83% accuracy)
```

**3.5 Ajustes Finos** 📋
- [ ] Ajustar schedules se necessário (ex: 08:30 vs 08:00)
- [ ] Configurar SNS notifications (opcional)
- [ ] Habilitar RDS snapshots antes de stop (se necessário)

#### Critérios de Sucesso
- ✅ EventBridge invocando Lambdas automaticamente
- ✅ 100% success rate nas primeiras 20 execuções (2 semanas)
- ✅ Economia real ≥80% da projetada
- ✅ Zero downtime inesperado
- ✅ Circuit breaker permanece CLOSED

#### Riscos
- **MÉDIO**: Primeira execução automática falhar (mitigado: testes manuais prévios)
- **BAIXO**: RDS 7-day stop issue (mitigado: circuit breaker detect + alert)
- **BAIXO**: Holiday não detectado (mitigado: Brasil API + manual override)

---

### FASE 4: Deploy Produção (Marco 3 - Futuro)
**Período**: 2026-03+ (Após GitLab deployment)
**Responsável**: Platform Team + DevOps
**Prioridade**: MEDIUM

#### Objetivos
- Replicar automação FinOps para ambiente de produção
- Savings estimados: R$ 3,500/mês+ (cluster maior)

#### Pré-requisitos
- [ ] Marco 3 completo (GitLab, Keycloak, ArgoCD, Harbor)
- [ ] Staging automation validada (3+ meses sem incidentes)
- [ ] PDB optimization implantada
- [ ] Runbook documentado
- [ ] Aprovação stakeholders (impacto em SLA)

#### Considerações Especiais para Produção
- **Schedules Diferentes**: Produção pode precisar 24/7 ou schedules diferentes
- **RDS Snapshots Obrigatórios**: `CREATE_RDS_SNAPSHOT=true` para prod
- **Monitoring Mais Rígido**: SLA-based alarms
- **Circuit Breaker Mais Sensível**: Threshold = 1 (vs 3 em staging)
- **Manual Override**: Implementar API/Slack bot para override manual

#### Tarefas (High-Level)
1. Criar `envs/finops-prod/`
2. Ajustar configurações para prod (schedules, thresholds, snapshots)
3. Validar em prod-like environment primeiro
4. Deploy gradual (1 nodegroup por vez)
5. Monitorar 1 semana antes de habilitar automação completa

---

## 🎯 Métricas de Sucesso (KPIs)

### Fase 1 (Manual Testing)
- **Testes Executados**: Target 5+, Current 2
- **Success Rate**: Target 100%, Current 100%
- **Circuit Breaker State**: Target CLOSED, Current CLOSED
- **Anomalias Documentadas**: Target 0 critical, Current 1 minor (PDB)

### Fase 2 (PDB Optimization)
- **Shutdown Time**: Target <3min, Current 10-15min
- **HA Maintained**: Target N-1 always, Current N-1 (mas com delay)
- **Logs Lost**: Target 0%, Current 0%

### Fase 3 (Automation Enabled)
- **Automatic Executions**: Target 10/week, Current 0
- **Success Rate**: Target 100%, Current N/A
- **Savings Realized**: Target ≥80% of projected, Current N/A
- **Downtime**: Target 0min, Current 0min

### Fase 4 (Production)
- **Prod Deploy**: Target Q2 2026, Current Not Started
- **Prod Savings**: Target R$ 3,500+/mês, Current N/A

---

## 📋 Backlog de Issues

### Abertos
1. **PDB Optimization** (MEDIUM priority)
   - Shutdown não-graceful: 10-15min vs 2-3min esperado
   - Causa: PDBs com maxUnavailable=0
   - Solução: Implementar Cenário 3+4
   - ETA: Sprint 2026-02

2. **Monitoring Enhancements** (LOW priority)
   - SNS notifications não configuradas
   - Solução: Adicionar SNS topic ARN após validação
   - ETA: Fase 3

3. **RDS 7-Day Stop Limitation** (LOW priority - monitoring)
   - AWS para RDS automaticamente após 7 dias stopped
   - Solução: Circuit breaker detecta + alerta
   - Mitigação: Monitorar last_stop_time no DynamoDB

### Fechados
- [x] DynamoDB TTL type mismatch
- [x] CloudWatch Logs KMS permission
- [x] Lambda IAM missing EKS permissions
- [x] Lambda IAM missing RDS permissions
- [x] Lambda credential cache not refreshing
- [x] RDS instance name hardcoded

---

## 📚 Documentação Relacionada

### ADRs
- ADR-024: FinOps Automation Architecture (já existente?)
- **ADR-025**: Adjust PDBs for Graceful Node Drain (a criar - Fase 2)

### Runbooks
- `docs/runbooks/finops-manual-override.md` (a criar)
- `docs/runbooks/finops-troubleshooting.md` (a criar)

### Dashboards
- CloudWatch Dashboard: FinOps/Scheduler (já criado pelo Terraform)
- Grafana Dashboard: Cost Optimization Metrics (a criar - opcional)

### Scripts
- `scripts/finops-manual-start.sh` (usar output do Terraform)
- `scripts/finops-manual-stop.sh` (usar output do Terraform)

---

## 👥 Stakeholders

| Papel | Nome/Team | Responsabilidade |
|-------|-----------|------------------|
| **Executor** | DevOps Team | Deploy, monitoring, troubleshooting |
| **Reviewer** | Platform Team | PDB changes approval |
| **Approver** | Tech Lead | Enable automation decision |
| **Informed** | Finance Team | Cost savings tracking |

---

## 🔗 Links Úteis

- Terraform Module: `platform-provisioning/aws/kubernetes/terraform/modules/finops-automation/`
- CloudWatch Logs Start: `/aws/lambda/finops-scheduler-start-staging`
- CloudWatch Logs Stop: `/aws/lambda/finops-scheduler-stop-staging`
- DynamoDB Table: `finops-scheduler-state-staging`
- S3 Terraform State: `s3://terraform-state-marco0-891377105802/finops-staging/`

---

## ⚠️ Riscos e Mitigações

| Risco | Severidade | Probabilidade | Mitigação |
|-------|------------|---------------|-----------|
| Lambda failure durante startup automático | HIGH | LOW | Circuit breaker após 3 falhas + alertas |
| RDS 7-day stop limiter | MEDIUM | MEDIUM | Monitorar last_stop_time + alert antes de 7d |
| PDB mudanças causam downtime | MEDIUM | LOW | Testar em staging primeiro, validar failover |
| Holiday não detectado | LOW | LOW | Brasil API + manual override capability |
| Cost Explorer dados atrasados | LOW | HIGH | Aceitar: dados têm 24-48h delay (esperado) |

---

**Última Revisão**: 2026-01-30
**Próxima Revisão**: 2026-02-06 (após Fase 1 completa)
**Owner**: DevOps Team
**Status**: 🟢 On Track
