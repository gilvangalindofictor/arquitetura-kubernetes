# Índice de Custos e FinOps

**Última Atualização:** 2026-02-19

Arquivo de referência central para todos os documentos, relatórios, scripts e dados relacionados a custos e FinOps da plataforma Kubernetes AWS.

---

## Documentação Principal

| Arquivo                                                  | Descrição                                                                                                            |
| -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| [docs/context/costs.md](costs.md)                        | Análise completa de custos — Resumo executivo, TCO, projeções por Marco, Cost Explorer real data, GAPs identificados |
| [docs/context/current_state.md](current_state.md#finops) | Estado atual da plataforma — Seção FinOps com custos MTD, automação e otimizações                                    |

---

## Relatórios Consolidados

| Arquivo                                                                                                    | Descrição                                                                           |
| ---------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| [reports/aws-costs-consolidated.md](../../reports/aws-costs-consolidated.md)                               | Relatório consolidado: dia a dia × serviço a serviço, tendências, forecast, alertas |
| [reports/aws-costs-daily.csv](../../reports/aws-costs-daily.csv)                                           | CSV diário por serviço (importável para planilhas/BI)                               |
| [reports/aws-costs.json](../../reports/aws-costs.json)                                                     | Raw JSON — MTD por serviço (Cost Explorer API)                                      |
| [docs/reports/aws-costs-consolidated-2026-02.md](../reports/aws-costs-consolidated-2026-02.md)             | Relatório consolidado Fev 2026 (snapshot mensal)                                    |
| [docs/reports/aws-costs-raw-consolidated-2026-02.json](../reports/aws-costs-raw-consolidated-2026-02.json) | Raw JSON consolidado Fev 2026                                                       |
| [docs/reports/aws-costs-raw-all-2026-02.json](../reports/aws-costs-raw-all-2026-02.json)                   | Raw JSON completo (sem filtro) Fev 2026                                             |

---

## Dados Detalhados (reports/aws-costs/)

### Custos por Dimensão

| Arquivo                                                                  | Dimensão                                            |
| ------------------------------------------------------------------------ | --------------------------------------------------- |
| [cost-by-service.json](../../reports/aws-costs/cost-by-service.json)     | Por serviço AWS (EKS, EC2, RDS, etc.)               |
| [cost-by-operation.json](../../reports/aws-costs/cost-by-operation.json) | Por operação API (RunInstances, CreateVolume, etc.) |
| [cost-by-usage.json](../../reports/aws-costs/cost-by-usage.json)         | Por tipo de uso (On-Demand, EBS, NAT, etc.)         |
| [cost-by-tag.json](../../reports/aws-costs/cost-by-tag.json)             | Por tag AWS (CostCenter, Environment, Owner)        |
| [cost-resources.json](../../reports/aws-costs/cost-resources.json)       | Por recurso individual                              |

### Snapshots MTD

| Arquivo                                                                          | Descrição                  |
| -------------------------------------------------------------------------------- | -------------------------- |
| [costs.json](../../reports/aws-costs/costs.json)                                 | Custos gerais consolidados |
| [costs-mtd.json](../../reports/aws-costs/costs-mtd.json)                         | Acumulado month-to-date    |
| [cost-mtd-by-service.json](../../reports/aws-costs/cost-mtd-by-service.json)     | MTD por serviço            |
| [cost-mtd-by-operation.json](../../reports/aws-costs/cost-mtd-by-operation.json) | MTD por operação           |

### Snapshots Históricos

| Arquivo                                                                                                | Data                          |
| ------------------------------------------------------------------------------------------------------ | ----------------------------- |
| [cost-2026-02-01-by-service.json](../../reports/aws-costs/cost-2026-02-01-by-service.json)             | 2026-02-01 por serviço        |
| [cost-2026-02-01-by-usage.json](../../reports/aws-costs/cost-2026-02-01-by-usage.json)                 | 2026-02-01 por uso            |
| [cost-2026-02-19-daily-by-service.json](../../reports/aws-costs/cost-2026-02-19-daily-by-service.json) | 2026-02-19 diário por serviço |

### Relatórios Semanais

| Arquivo                                                                              | Descrição                 |
| ------------------------------------------------------------------------------------ | ------------------------- |
| [weekly-2026-02-12-summary.md](../../reports/aws-costs/weekly-2026-02-12-summary.md) | Resumo semanal 2026-02-12 |
| [weekly-2026-02-12.json](../../reports/aws-costs/weekly-2026-02-12.json)             | Dados semanais JSON       |

### Relatórios de Cleanup

| Arquivo                                                                                                    | Operação                     |
| ---------------------------------------------------------------------------------------------------------- | ---------------------------- |
| [cleanup-all-2026-02-12.json](../../reports/aws-costs/cleanup-all-2026-02-12.json)                         | Execução completa de cleanup |
| [cleanup-2026-02-12.json](../../reports/aws-costs/cleanup-2026-02-12.json)                                 | Recursos órfãos              |
| [cleanup-elastic-ips-2026-02-12.json](../../reports/aws-costs/cleanup-elastic-ips-2026-02-12.json)         | Elastic IPs                  |
| [cleanup-nat-gateways-2026-02-12.json](../../reports/aws-costs/cleanup-nat-gateways-2026-02-12.json)       | NAT Gateways                 |
| [cleanup-cloudwatch-logs-2026-02-12.json](../../reports/aws-costs/cleanup-cloudwatch-logs-2026-02-12.json) | CloudWatch Logs              |
| [cleanup-ecr-images-2026-02-12.json](../../reports/aws-costs/cleanup-ecr-images-2026-02-12.json)           | ECR Images                   |
| [audit-security-groups-2026-02-12.json](../../reports/aws-costs/audit-security-groups-2026-02-12.json)     | Security Groups (audit-only) |

---

## Auditorias de Infraestrutura (reports/aws-checks/)

| Arquivo                                                         | Recurso        | Impacto FinOps                |
| --------------------------------------------------------------- | -------------- | ----------------------------- |
| [volumes.json](../../reports/aws-checks/volumes.json)           | EBS Volumes    | $0.10/GB/mês                  |
| [rds.json](../../reports/aws-checks/rds.json)                   | RDS Instances  | ~$28/mês                      |
| [albs.json](../../reports/aws-checks/albs.json)                 | Load Balancers | ~$16/ALB/mês                  |
| [eips.json](../../reports/aws-checks/eips.json)                 | Elastic IPs    | $3.60/EIP/mês (se unattached) |
| [nat-gateways.json](../../reports/aws-checks/nat-gateways.json) | NAT Gateways   | ~$32/mês + data               |

---

## ADRs (Decisões Arquiteturais)

### FinOps-Específicos

| ADR                                                             | Título                                               | Status   |
| --------------------------------------------------------------- | ---------------------------------------------------- | -------- |
| [ADR-022](../adr/adr-022-finops-automation-strategy.md)         | FinOps Automation Strategy                           | Approved |
| [ADR-024](../adr/adr-024-finops-scheduler-implementation.md)    | FinOps Scheduler Implementation (Lambda+EventBridge) | Approved |
| [ADR-055](../adr/adr-055-finops-security-groups-remediation.md) | Security Groups Remediation                          | Approved |

### Impacto em Custos

| ADR                                                            | Título                     | Impacto               |
| -------------------------------------------------------------- | -------------------------- | --------------------- |
| [ADR-007](../adr/adr-007-cluster-autoscaler-strategy.md)       | Cluster Autoscaler         | Otimização de nodes   |
| [ADR-050](../adr/adr-050-shared-data-services-prod-staging.md) | Shared Data Services       | Redução de instâncias |
| [ADR-051](../adr/adr-051-postgresql-rds-vs-operator.md)        | PostgreSQL RDS vs Operator | Decisão ~$28/mês      |
| [ADR-052](../adr/adr-052-velero-implementation-strategy.md)    | Velero Backup Strategy     | Custo S3 storage      |
| [ADR-054](../adr/adr-054-data-services-decisions.md)           | Data Services Decisions    | PostgreSQL + Redis    |
| [ADR-059](../adr/adr-059-multi-marco-infrastructure-split.md)  | Multi-Marco Infra Split    | Isolação de custos    |

---

## Scripts FinOps (scripts/finops/)

### Automação de Scheduler

| Script                                                              | Função                                                 |
| ------------------------------------------------------------------- | ------------------------------------------------------ |
| [lambda-start-nodes.py](../../scripts/finops/lambda-start-nodes.py) | Lambda: startup EKS nodes + RDS                        |
| [lambda-stop-nodes.py](../../scripts/finops/lambda-stop-nodes.py)   | Lambda: shutdown EKS nodes + RDS (com circuit breaker) |
| [startup-marco2.sh](../../scripts/finops/startup-marco2.sh)         | Startup manual ambiente staging                        |
| [shutdown-marco2.sh](../../scripts/finops/shutdown-marco2.sh)       | Shutdown manual ambiente staging                       |
| [health-check.sh](../../scripts/finops/health-check.sh)             | Validação de saúde da automação                        |
| [validate-shutdown.sh](../../scripts/finops/validate-shutdown.sh)   | Verificação de compliance shutdown                     |

### Cleanup e Auditoria

| Script                                                                          | Função                              | Economia Estimada |
| ------------------------------------------------------------------------------- | ----------------------------------- | ----------------- |
| [cleanup-all.sh](../../scripts/finops/cleanup-all.sh)                           | Executa todos os cleanups (dry-run) | -                 |
| [cleanup-orphan-resources.sh](../../scripts/finops/cleanup-orphan-resources.sh) | EBS, snapshots, ALBs órfãos         | R$0-2000/ano      |
| [cleanup-elastic-ips.sh](../../scripts/finops/cleanup-elastic-ips.sh)           | Elastic IPs não utilizados          | R$0-500/ano       |
| [cleanup-nat-gateways.sh](../../scripts/finops/cleanup-nat-gateways.sh)         | NAT Gateways órfãos                 | Mínimo            |
| [cleanup-cloudwatch-logs.sh](../../scripts/finops/cleanup-cloudwatch-logs.sh)   | Retention + log groups vazios       | R$0-1000/ano      |
| [cleanup-ecr-images.sh](../../scripts/finops/cleanup-ecr-images.sh)             | Imagens ECR antigas/untagged        | R$0-300/ano       |
| [audit-security-groups.sh](../../scripts/finops/audit-security-groups.sh)       | Security Groups (audit-only)        | -                 |
| [apply-tags.sh](../../scripts/finops/apply-tags.sh)                             | Tagueamento FinOps em recursos      | FREE              |

### Geração de Relatórios

| Script                                                              | Função                                     |
| ------------------------------------------------------------------- | ------------------------------------------ |
| [weekly-cost-report.sh](../../scripts/finops/weekly-cost-report.sh) | Gera relatório semanal (Cost Explorer API) |
| [README.md](../../scripts/finops/README.md)                         | Documentação completa da suite FinOps      |

---

## Logbook — Entradas FinOps

| Data       | Entrada                                                                                    | Resumo                                                         |
| ---------- | ------------------------------------------------------------------------------------------ | -------------------------------------------------------------- |
| 2026-02-18 | [p0-shutdown-script-bugfix](../logbook/2026-02-18-p0-shutdown-script-bugfix.md)            | Bugfix crítico no script de shutdown                           |
| 2026-02-18 | [p1-security-finops](../logbook/2026-02-18-p1-security-finops.md)                          | Integração Security + FinOps                                   |
| 2026-02-17 | [staging-shutdown-weekly](../logbook/2026-02-17-staging-shutdown-weekly.md)                | Execução semanal de shutdown                                   |
| 2026-02-16 | [staging-shutdown-weekend](../logbook/2026-02-16-staging-shutdown-weekend.md)              | Execução weekend shutdown                                      |
| 2026-02-13 | [weekly-finops-report](../logbook/2026-02-13-weekly-finops-report.md)                      | Relatório semanal FinOps + orphan detector                     |
| 2026-02-13 | [finops-p0-execution](../logbook/2026-02-13-finops-p0-execution.md)                        | Execução de prioridades P0                                     |
| 2026-02-13 | [ebs-gp2-gp3-pvc-migration](../logbook/2026-02-13-ebs-gp2-gp3-pvc-migration.md)            | Migração EBS gp2→gp3 (-20% custo/volume)                       |
| 2026-02-13 | [ecr-lifecycle-policies](../logbook/2026-02-13-ecr-lifecycle-policies.md)                  | Policies de retenção ECR                                       |
| 2026-02-13 | [orphan-detector-lambda](../logbook/2026-02-13-orphan-detector-lambda.md)                  | Lambda para detecção de recursos órfãos                        |
| 2026-02-13 | [security-groups-cleanup](../logbook/2026-02-13-security-groups-cleanup-completion.md)     | Conclusão limpeza Security Groups                              |
| 2026-02-12 | [finops-quick-wins](../logbook/2026-02-12-finops-quick-wins-execution.md)                  | 3 quick wins: CW Logs, S3 Endpoint, SGs. Economia: R$1.130/ano |
| 2026-02-05 | [finops-cleanup-legado](../logbook/2026-02-05-finops-cleanup-estrutura-legada.md)          | Limpeza de infra legada                                        |
| 2026-02-05 | [eventbridge-diagnostico](../logbook/2026-02-05-finops-eventbridge-diagnostico-staging.md) | Diagnóstico EventBridge scheduler                              |
| 2026-02-05 | [sns-notification-fix](../logbook/2026-02-05-finops-sns-notification-fix.md)               | Fix notificações SNS startup/shutdown                          |
| 2026-02-05 | [schedule-adjustment](../logbook/2026-02-05-finops-schedule-adjustment.md)                 | Ajuste horários: 08:00 startup, 18:00 shutdown BRT             |
| 2026-02-04 | [lambda-python-downgrade](../logbook/2026-02-04-finops-lambda-python-downgrade.md)         | Python 3.13→3.12 (compatibilidade Lambda)                      |

---

---

## 📊 Análise de Budget Fevereiro 2026 (NOVO)

> **Status:** 🟢 DENTRO DO BUDGET Marco 3 - Gap +$1 (+0,1%)
> **Última atualização:** 2026-02-19

### Documentos de Análise

| Documento | Audiência | Descrição |
|-----------|-----------|-----------|
| **[budget-feb2026-decisao-executiva.md](budget-feb2026-decisao-executiva.md)** 🆕 | **Decisores, C-Level** | **DOCUMENTO PRINCIPAL** - Unificado com budget quickstart vs realidade, decisão fim de mês, estratégia híbrida produção, estimativas staging+prod |
| [budget-summary-exec.md](budget-summary-exec.md) | C-Level, Stakeholders | Resumo executivo 1-2 páginas. Decisão: confirmar alinhamento com Marco 3 |
| [budget-consolidado-feb2026.md](budget-consolidado-feb2026.md) | Liderança Técnica, Financeiro | Análise completa 10-15 páginas. Comparativo quickstart vs realidade, estratégia híbrida |
| [budget-feb2026-forecast.md](budget-feb2026-forecast.md) | Time FinOps/DevOps | Projeções detalhadas, análise de tendência, custos por serviço |
| [../../reports/budget-feb2026-analysis.json](../../reports/budget-feb2026-analysis.json) | Automação, Dashboards | Dados estruturados JSON para integração programática |

### Situação Atual (Resumo)

| Métrica | Valor |
|---------|-------|
| Budget Marco 3 Aprovado | $807/mês (R$ 4.841) |
| Projeção Real Estabilizada | $808/mês (R$ 4.606) |
| Gap | +$1 (+0,1%) ✅ |
| Status | DENTRO DO BUDGET |

### Estratégia Implementada

**Ambiente Híbrido:**
- 1 ambiente staging robusto (ao invés de 2 separados)
- Serve para maioria dos casos (desenvolvimento, testes, validação)
- Prod individualizado apenas quando necessário
- Otimização de custos baseada em melhores práticas

### Documentos Base (Referência)

| Documento | Descrição |
|-----------|-----------|
| [../plan/quickstart/executive-summary-cto.md](../plan/quickstart/executive-summary-cto.md) | Budget quickstart original: $604/mês baseline, $807/mês Marco 3 |

### Timeline de Decisão

| Data | Ação | Status |
|------|------|--------|
| 19/02 | Análise custos estabilizados + projeção revisada | ✅ Concluída |
| 20/02 | **Decisão: Confirmar alinhamento com Marco 3** | ⏳ **Pendente** |

---

## Como Usar Este Índice

1. **Decisão Budget Fev/2026** 🔴 → [budget-feb2026-decisao-executiva.md](budget-feb2026-decisao-executiva.md) (PRINCIPAL - decisão executiva completa)
2. **Visão executiva geral** → [costs.md](costs.md) (Resumo Executivo + AWS Cost Explorer Real Data)
3. **Budget Fev/2026 resumido** → [budget-summary-exec.md](budget-summary-exec.md) (Análise budget atual 1-2 páginas)
4. **Relatório detalhado** → [aws-costs-consolidated.md](../../reports/aws-costs-consolidated.md) (dia a dia × serviço)
5. **Dados para planilha** → [aws-costs-daily.csv](../../reports/aws-costs-daily.csv) (importar no Google Sheets/Excel)
6. **Decisões tomadas** → ADRs 022, 024, 055
7. **Rodar cleanup** → `scripts/finops/cleanup-all.sh --dry-run`
8. **Gerar relatório** → `scripts/finops/weekly-cost-report.sh`
9. **Histórico de ações** → Logbook entries acima
