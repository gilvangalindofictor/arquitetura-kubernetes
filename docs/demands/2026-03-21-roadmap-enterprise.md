# ROADMAP Enterprise — Plataforma k8s-platform-prod
**Data**: 2026-03-21
**Horizonte**: Q1 2026 → Q4 2026
**Cluster**: k8s-platform-prod | Conta: 891377105802 | Região: us-east-1
**Produzido por**: Orquestrador DevOps Sênior — análise baseada em dados reais do cluster e histórico documental

---

## Resumo Executivo

A plataforma k8s-platform-prod atingiu maturidade operacional básica em Q1 2026 após um ciclo intenso de construção: EKS 1.34 compartilhado staging/prod, 16 nós (t3.medium/large/xlarge), stack observabilidade Prometheus+Loki+Tempo+Grafana, Vault HA com KMS auto-unseal, ESO, Linkerd mTLS, WAF duplo (staging/prod), ArgoCD, Harbor, GitLab CE, Backstage 2.6.3, Velero com replicação cross-region (us-east-1→us-west-2) e pipeline CI/CD com conformidade 100%. O ambiente de produção possui ACM ISSUED para *.prod.alvocard.com.br e *.hml.alvocard.com.br, hosted zones Route53 públicas e fases 1-4 de infraestrutura concluídas. 337 pods Running, 0 CrashLoopBackOff.

Os gaps críticos que separam o estado atual do padrão enterprise são: ausência de Spot Instances e Savings Plans (100% On-Demand sem compromisso financeiro), RDS Single-AZ (Multi-AZ=false em produção — risco operacional grave), NAT Gateway Single-AZ (único ponto de falha de rede), EKS control-plane logging em apenas 1/5 tipos (apenas `authenticator`), VPN inexistente (acesso interno via port-forward), Network Policies incompletas em namespaces críticos (ArgoCD, GitLab, Keycloak, SonarQube sem isolamento lateral), External-DNS não instalado (DNS manual propenso a drift), Tempo não instanciado no staging TF (módulo existente mas não declarado), e ausência total de Savings Plans ou Reserved Instances para base-load.

A visão enterprise para Q4 2026 é uma plataforma com: resiliência Multi-AZ completa, observabilidade com tracing end-to-end e Dead Man's Switch, FinOps com 40-60% de economia via Spot+Savings Plans, Karpenter nativo substituindo Cluster Autoscaler legado, VPN operacional para acesso seguro, Backstage como hub de self-service com E2E funcional, compliance BACEN/LGPD auditável e RPO/RTO formalmente testados.

---

## Score Atual por Dimensão

| Dimensão | Score | Benchmark Enterprise | Evidência Principal |
|----------|-------|----------------------|---------------------|
| Resiliência | 5/10 | 9/10 | RDS Single-AZ (prod), NAT Single-AZ, sem PDB na maioria dos workloads, sem HPA/VPA em produção |
| Segurança | 6/10 | 9/10 | WAF ativo (2 WebACLs), Vault+ESO+KMS, Linkerd 3/3, mas Network Policies parciais, PSA não enforced, EKS logging 1/5, VPN inexistente |
| Observabilidade | 6/10 | 8/10 | Prometheus+Loki+Tempo+Grafana ativos, OTLP collector, mas Tempo não instanciado no TF, Dead Man's Switch ausente, SLO alerting inexistente |
| FinOps | 4/10 | 8/10 | Lambda FinOps ativa (shutdown staging), 100% On-Demand sem Savings Plans/Spot, 1 EBS orphan ($10/mês), sem budget alerts AWS |
| CI/CD & GitOps | 7/10 | 9/10 | ArgoCD + GitLab CI 100% conformidade, templates Backstage publicados, mas E2E scaffold não testado, drift detection manual |
| DR & Backup | 6/10 | 8/10 | Velero hourly backups + S3 cross-region (us-west-2), EBS snapshots diários, mas sem runbook testado de restore, RTO/RPO não formalmente validados, RDS backup_retention=7d apenas |
| Escalabilidade | 5/10 | 8/10 | Cluster Autoscaler com PDB e alertas, 3 node groups, mas CA legado (não Karpenter nativo), t3.medium com ENI limit 17 pods, prefix delegation não habilitado, 100% On-Demand |
| Developer Experience | 6/10 | 7/10 | Backstage 2.6.3 com OIDC, templates ETL/API/Service, catalog entities, mas E2E scaffold→deploy não testado, onboarding time não medido |
| Compliance | 5/10 | 8/10 | KMS encryption at rest para secrets EKS, Kyverno ECR redirect, audit log Vault, mas EKS control-plane audit logging desabilitado, CIS benchmark não executado, PSA não enforced |
| Automação | 6/10 | 8/10 | Lambda FinOps + CrashLoopBackOff cleanup + snapshot lifecycle + orphan detector, mas sem auto-remediation de alertas, runbooks não automatizados, sem ChatOps |
| **TOTAL** | **56/100** | **82/100** | |

> **Atualizacao 2026-03-27:** Score FinOps degradou de 4/10 para 3/10 (EventBridge shutdown rules DISABLED — 6 rules). Right-sizing melhorou de 5/10 para 6/10 (ArgoCD 11->7 pods, Observability 78->73 pods, SonarQube prod removido). Score geral permanece 56/100 (degradacao FinOps compensada por right-sizing). Custo mensal estimado atual: **$1,590.86/mes** ($19,090/ano). Ver `2026-03-27-finops-cost-summary.md` para detalhamento.

---

## ROADMAP por Quarter

### Q1 2026 (Janeiro–Março — em andamento)

**Concluído:**
- EKS 1.34 ativo, 16 nós, 337 pods Running
- Vault HA 3-replica com KMS auto-unseal, ESO integrado (15 ExternalSecrets SecretSynced)
- Secrets migrados para Vault (SEC-MIG-001 100%)
- IaC compliance 100% (Promtail, Velero, Loki, Node Groups importados)
- Linkerd 3/3 Running (mTLS control plane)
- Calico 16/16 Running (imagens ECR mirror)
- WAF: 2 WebACLs (staging+prod), 4/4 ALBs internet-facing protegidos, IP allowlist office
- ACM: 4 certificados ISSUED (*.prod.alvocard.com.br, *.hml.alvocard.com.br, harbor.staging.internal, keycloak.staging.internal)
- Route53: 3 hosted zones (staging.internal privada + prod/hml públicas), delegação NS propagando
- Backstage 2.6.3 Running 2/2, plugin S6-C montado, templates ETL/API/Service publicados no GitLab
- ArgoCD + GitLab CI: conformidade 100%, pipeline ETL/Hatch com Vault auth dinâmico
- Velero: backups hourly (S3 us-east-1 + replica us-west-2)
- FinOps Lambda: shutdown scheduling staging, CrashLoopBackOff cleanup, R$30.982/ano savings realizados — **ALERTA 2026-03-27: 6 shutdown rules DISABLED, savings efetivos ~R$9.944/ano**
- VPA: módulo instalado em recommendation mode
- OTEL Collector: gateway mode com OTLP
- Prod Fases 1-4: namespaces criados, Vault prod HA, Redis 3-replica, RabbitMQ 3-replica quorum
- D6 Fases 5-7 codificadas no TF: external-dns, linkerd-mtls, vpn-site-to-site (aguardando apply/FortiGate)

**Em andamento / pendente imediato:**
- External-DNS: módulo TF pronto, apply pendente
- VPN Site-to-Site: aguardando IP FortiGate (externo)
- GAP-WORKLOAD-01: etl-core Deployment→CronJob (P1)
- GAP-TEMPO-IMPORT: módulo Tempo não instanciado no staging TF
- ~~GAP-FINOPS-ACCESS-ENTRY~~: RESOLVIDO (2026-03-27) — EKS auth mode API_AND_CONFIG_MAP ativo
- VemSoft .gitlab-ci.yml: pendente push ao GitLab
- Backstage E2E: scaffold→deploy test não executado (TAREFA-022/023)
- Hatch ETL: em HOLD (replicas=0, ArgoCD auto-sync OFF) — aguarda estabilização

### Q2 2026 (Abril–Junho)

Foco: **Resiliência, Segurança completa e FinOps estrutural**

| Iniciativa | INIT-ID | Impacto | Esforço |
|-----------|---------|---------|---------|
| RDS Multi-AZ habilitado (prod) | INIT-001 | CRITICO | Baixo |
| NAT Gateway segundo AZ | INIT-002 | Alto | Baixo |
| Spot Instances para node group workloads | INIT-003 | Alto | Médio |
| Compute Savings Plans (1-year, no-upfront) | INIT-004 | Alto | Baixo |
| EKS control-plane logging completo (5/5 tipos) | INIT-005 | Alto | Baixo |
| Network Policies para namespaces críticos | INIT-006 | Alto | Médio |
| PSA enforced para namespaces de workload | INIT-007 | Alto | Médio |
| Dead Man's Switch + SLO alerting | INIT-008 | Alto | Médio |
| Tempo instanciado no TF staging + prod | INIT-009 | Médio | Baixo |
| Backstage E2E scaffold→deploy validado | INIT-010 | Médio | Médio |
| RDS backup retention 30d (prod) | INIT-011 | Médio | Baixo |
| AWS Budget Alerts configurados | INIT-012 | Médio | Baixo |

### Q3 2026 (Julho–Setembro)

Foco: **Escalabilidade avançada, Developer Experience e Compliance**

| Iniciativa | INIT-ID | Impacto | Esforço |
|-----------|---------|---------|---------|
| Karpenter nativo (substituir Cluster Autoscaler) | INIT-013 | Alto | Alto |
| VPC CNI Prefix Delegation (t3.medium: 17→110 pods) | INIT-014 | Alto | Médio |
| CIS EKS Benchmark automatizado (kube-bench) | INIT-015 | Alto | Médio |
| DR Restore Runbook testado (Velero full restore drill) | INIT-016 | Alto | Médio |
| Linkerd Phase 2 completa (mTLS em todos namespaces) | INIT-017 | Alto | Médio |
| Multi-region failover documentado e testado | INIT-018 | Alto | Alto |
| IRSA rightsizing — least-privilege por SA | INIT-019 | Médio | Médio |
| GitLab upgrade para versão LTS atual | INIT-020 | Médio | Médio |
| Backstage Plugin: Cost visibility por app | INIT-021 | Médio | Alto |

### Q4 2026 (Outubro–Dezembro)

Foco: **Excelência operacional, auto-remediação e preparação regulatória**

| Iniciativa | INIT-ID | Impacto | Esforço |
|-----------|---------|---------|---------|
| ChatOps via Slack/Teams para alertas críticos | INIT-022 | Alto | Médio |
| Auto-remediation runbooks (Ansible/Lambda) | INIT-023 | Alto | Alto |
| Multi-region active-passive (us-east-1 → sa-east-1 LGPD) | INIT-024 | Alto | Alto |
| Backstage TechDocs + ADR linking completo | INIT-025 | Médio | Médio |
| SOC2 Type I readiness (audit logs, access reviews) | INIT-026 | Alto | Alto |
| EKS upgrade para 1.31+ com blue-green node groups | INIT-027 | Alto | Médio |
| Service Mesh Observability com Grafana mTLS dashboards | INIT-028 | Médio | Médio |

---

## Detalhamento por Iniciativa

### INIT-001: RDS Multi-AZ — Produção
- **Dimensão**: Resiliência / DR
- **Problema atual**: `k8s-platform-prod-postgresql` — `MultiAZ: False` (confirmado via `aws rds describe-db-instances` em 2026-03-21). O TF declara `multi_az = true` mas o recurso real está Single-AZ. Qualquer falha na AZ us-east-1a causa downtime total de GitLab, Keycloak, Harbor e SonarQube (100% dependem deste RDS).
- **Solução**: `terraform apply` com `multi_az = true` na instância `k8s-platform-prod-postgresql`. AWS realiza conversão em-place com failover automático em <120s. Janela de manutenção: fora do horário de negócio.
- **Impacto**: CRITICO — elimina SPOF de dados para todos os serviços de plataforma
- **Esforço**: Baixo (1 variável TF, apply em janela)
- **Quarter**: Q2 2026
- **Dependências**: Janela de manutenção aprovada

### INIT-002: NAT Gateway Multi-AZ
- **Dimensão**: Resiliência / Rede
- **Problema atual**: ~~1 NAT Gateway em subnet unica~~ **RESOLVIDO 2026-03-27**: 2 NAT Gateways ativos (`nat-03512e5ee0642dcf2` us-east-1a + `nat-08f450d59d3c868f0` us-east-1b). Multi-AZ operacional.
- **Solucao**: ~~Criar segundo NAT Gateway~~ JA APLICADO. Custo adicional: ~$35/mes (confirmado).
- **Impacto**: Alto — elimina SPOF de conectividade de rede
- **Esforço**: Baixo (TF resource adicional no módulo nat-gateways)
- **Quarter**: Q2 2026
- **Dependências**: INIT-001 (alinhar com janela de manutenção)

### INIT-003: Spot Instances para Node Group Workloads
- **Dimensão**: FinOps / Escalabilidade
- **Problema atual**: 100% On-Demand em todos os 3 node groups (system: 6x t3.medium, workloads: 7x t3.large, critical: 2x t3.xlarge). Custo estimado: ~$720/mês somente em EC2. Sem nenhum uso de Spot. Documento `2026-03-17-revisao-capacidade-karpenter.md` identificou economia de 60-70% no node group workloads com Spot.
- **Solução**: Converter node group `workloads` para capacidade mista (70% Spot + 30% On-Demand). Usar diversificação de instâncias: t3.large, t3a.large, m5.large, m5a.large via `capacity_rebalance = true`. Node group `critical` permanece 100% On-Demand.
- **Impacto**: Alto — economia estimada R$8.000-12.000/ano
- **Esforço**: Médio (TF changes + validação de workload tolerations)
- **Quarter**: Q2 2026
- **Dependências**: INIT-013 (Karpenter é a solução definitiva; Spot em node groups é interim)

### INIT-004: Compute Savings Plans
- **Dimensão**: FinOps
- **Problema atual**: Nenhum Savings Plans ativo (`list-savings-plans` retornou vazio em 2026-03-21). Nenhum Reserved Instance ativo. Base-load de ~8 nodes sempre-ligados (critical + sistema) custa ~$350/mês 100% On-Demand.
- **Solução**: Contratar Compute Savings Plan 1-year No-Upfront para comprometer ~$150/mês de base-load (equivalente a 4 nodes t3.large 24/7). Desconto esperado: 20-30% sobre On-Demand.
- **Impacto**: Alto — economia R$3.600-5.400/ano com risco zero (Compute SP é flexível por instância/região)
- **Esforço**: Baixo (decisão financeira, não técnica)
- **Quarter**: Q2 2026
- **Dependências**: Budget approval

### INIT-005: EKS Control-Plane Logging Completo
- **Dimensão**: Compliance / Segurança
- **Problema atual**: EKS logging habilitado apenas para `authenticator` (1/5 tipos). `api`, `audit`, `controllerManager`, `scheduler` estão desabilitados (confirmado via `aws eks describe-cluster` em 2026-03-21). Sem audit log de API server, não é possível rastrear quem criou/deletou recursos — violação de BACEN BCB 85/2021 Art.27 (rastreabilidade de ações).
- **Solução**: Habilitar todos os 5 tipos de logging EKS via TF: `enabled_cluster_log_types = ["api","audit","authenticator","controllerManager","scheduler"]`. Logs vão para CloudWatch Logs; criar metric filter para chamadas privilegiadas (kubectl exec, port-forward, delete pods em kube-system).
- **Impacto**: Alto — compliance regulatório BACEN + segurança forense
- **Esforço**: Baixo (1 linha TF, custo ~$5-15/mês CloudWatch)
- **Quarter**: Q2 2026
- **Dependências**: CloudWatch Logs retention policy (30d recomendado)

### INIT-006: Network Policies — Namespaces Críticos
- **Dimensão**: Segurança
- **Problema atual**: Documentado em `2026-03-18-security-domain-vpn-prod.md`: namespaces `staging-platform-argocd`, `staging-platform-gitlab`, `staging-platform-keycloak`, `staging-platform-sonarqube` e `harbor-system` sem Network Policies. Qualquer pod comprometido pode alcançar lateralmente todos esses serviços sem restrição.
- **Solução**: Implementar NetworkPolicy deny-all por padrão + allow-list explícito por namespace. ArgoCD: permite apenas argocd-server→api-server, argocd-repo-server→git. GitLab: permite apenas gitlab-rails→postgresql/redis/s3. Modelo: copiar as 24 policies já existentes em staging-security-vault como template.
- **Impacto**: Alto — elimina risco de lateral movement (BACEN BCB 85/2021 Art.15)
- **Esforço**: Médio (5 namespaces × 3-5 policies cada = ~20 manifests)
- **Quarter**: Q2 2026
- **Dependências**: Linkerd mTLS (INIT-017) pode ser feito em paralelo

### INIT-007: Pod Security Admission (PSA) Enforced
- **Dimensão**: Segurança / Compliance
- **Problema atual**: Nenhum namespace tem labels `pod-security.kubernetes.io/*` (verificado: PSA audit retornou vazio). Pods de workload podem declarar `privileged: true`, `hostNetwork: true`, `runAsRoot: true` sem restrição. CIS EKS Benchmark requer PSA ou equivalente.
- **Solução**: Aplicar PSA em modo `audit` primeiro (2 semanas), depois `warn`, depois `enforce`. Namespaces de workload: `baseline`. Namespaces de sistema (kube-system, linkerd): `privileged` (necessário). Usar Kyverno policies como complemento para regras customizadas (ex: proibir `latest` tag em imagens de prod).
- **Impacto**: Alto — hardening de segurança, prerequisito para CIS benchmark
- **Esforço**: Médio (análise de impacto + rollout gradual)
- **Quarter**: Q2 2026
- **Dependências**: INIT-015 (CIS benchmark guia as policies)

### INIT-008: Dead Man's Switch + SLO Alerting
- **Dimensão**: Observabilidade
- **Problema atual**: Incidente de 26h sem detecção em 2026-03-17 (Prometheus ficou Pending, sem alerta). Documentado em `2026-03-17-observabilidade-capacity-alertas.md`. Sem Dead Man's Switch, Prometheus offline = silêncio = "tudo bem". Sem alertas SLO/SLA por serviço.
- **Solução**:
  1. Dead Man's Switch: PrometheusRule `Watchdog` com `expr: vector(1)` e alerta `DeadMansSwitch` — deve SEMPRE disparar. Integrar no Alertmanager com rota para receiver específico. Se parar de disparar, o AlertManager notifica.
  2. SLO alerting: PrometheusRules para ClusterAutoscalerDown, NodeCPUCritical (>90%), NodeMemoryCritical (>85%), PodPendingCritical (>5 pods >5min), ObservabilityStackDegraded.
  3. Alertmanager routing: canal Teams/Slack dedicado para `severity=critical`.
- **Impacto**: Alto — reduz MTTD de 26h para <5min
- **Esforço**: Médio (PrometheusRules + Alertmanager config + webhook receiver)
- **Quarter**: Q2 2026
- **Dependências**: INIT-009 (Tempo completo para tracing de alertas)

### INIT-009: Tempo Instanciado no Terraform
- **Dimensão**: Observabilidade
- **Problema atual**: GAP-TEMPO-IMPORT registrado no MEMORY.md. Módulo `tempo` existe em `modules/tempo/` e S3 buckets para Tempo já foram criados (`k8s-platform-tempo-891377105802`, `k8s-platform-tempo-prod-891377105802`), mas o módulo não está instanciado no `main.tf` staging. Sem Tempo, não há distributed tracing end-to-end para ETL, VemSoft, e futuros serviços.
- **Solução**: Instanciar `module "tempo_staging"` no staging main.tf apontando para S3 bucket existente. Aplicar `terraform apply` na próxima janela. Configurar OTLP collector para exportar traces para Tempo.
- **Impacto**: Médio — completa o pilar de tracing na stack observabilidade
- **Esforço**: Baixo (módulo existe, bucket existe, 1 instanciação TF)
- **Quarter**: Q2 2026 (Quick Win — pode ser feito na sprint atual)
- **Dependências**: OTEL Collector já running

### INIT-010: Backstage E2E Scaffold→Deploy Validado
- **Dimensão**: Developer Experience
- **Problema atual**: TAREFA-022/023 pendentes (MEMORY.md). Templates ETL/API/Service publicados no GitLab (MR !3 merged), mas nunca foram executados em um teste E2E completo: formulário Backstage → skeleton gerado → MR aberto no GitLab → pipeline CI → deploy via ArgoCD → pod Running.
- **Solução**: Executar teste E2E completo com serviço de exemplo (ex: `hello-world-etl`). Medir tempo total (meta: <3 minutos formulário→MR conforme ADR-102). Documentar resultado. Corrigir quaisquer bugs encontrados no fluxo.
- **Impacto**: Médio — valida o ROI de todos os investimentos em IDP
- **Esforço**: Médio (execução + debug de bugs esperados no primeiro run)
- **Quarter**: Q2 2026
- **Dependências**: External-DNS instalado (INIT-009), Backstage 2/2 Running

### INIT-011: RDS Backup Retention 30 dias (Prod)
- **Dimensão**: DR & Backup
- **Problema atual**: `backup_retention_period = 7` (confirmado via `describe-db-instances`). Para BACEN BCB 85/2021 e PCI-DSS (se aplicável), retenção mínima de 30 dias é recomendada para dados de produção. Janela atual: 03:00-04:00 UTC.
- **Solução**: Alterar TF `backup_retention_period = 30`. Custo adicional: ~$15-25/mês em storage RDS automated backups. Adicionar também `deletion_protection = true` (verificar se já está ativo no prod TF).
- **Impacto**: Médio — compliance e RPO mais amplo
- **Esforço**: Baixo (1 variável TF)
- **Quarter**: Q2 2026
- **Dependências**: Nenhuma

### INIT-012: AWS Budget Alerts
- **Dimensão**: FinOps
- **Problema atual**: Nenhum AWS Budget configurado na conta. Sem alertas de orçamento, picos de custo (ex: Karpenter provisionar 20 nodes acidentalmente) passam despercebidos até a fatura chegar.
- **Solução**: Criar 3 AWS Budgets via TF: (1) Alerta 80% do orçamento mensal estimado ($2.500), (2) Alerta 100%, (3) Budget por serviço EC2 com alerta se exceder $900/mês. Notificação via SNS→email (já existe SNS no módulo finops-automation).
- **Impacto**: Médio — FinOps governance básico
- **Esforço**: Baixo (TF resource `aws_budgets_budget`)
- **Quarter**: Q2 2026
- **Dependências**: Nenhuma

### INIT-013: Karpenter Nativo (Substituir Cluster Autoscaler)
- **Dimensão**: Escalabilidade / FinOps
- **Problema atual**: Cluster Autoscaler legado com limitações documentadas: lag 2-10min para scale-out, sem diversificação nativa de instâncias, sem Spot nativo, scale-in conservador. Karpenter já está listado como ADR-059 mas o módulo não foi implementado — os 3 node groups estão usando CA legado (confirmado: nodegroups `system`, `workloads`, `critical` com scalingConfig).
- **Solução**: Instalar Karpenter via Helm + criar NodePools e EC2NodeClasses para cada perfil de workload. Migrar gradualmente: primeiro workloads stateless, depois sistema. Remover Cluster Autoscaler após validação. Karpenter habilita: Spot nativo, bin-packing otimizado, scale-out em segundos, diversificação automática de família de instâncias.
- **Impacto**: Alto — reduz latência de scale-out de minutos para segundos + base para Spot economy
- **Esforço**: Alto (migração complexa, requer planejamento de node drain, testes extensivos)
- **Quarter**: Q3 2026
- **Dependências**: INIT-003 (Spot interim), INIT-014 (Prefix Delegation)

### INIT-014: VPC CNI Prefix Delegation
- **Dimensão**: Escalabilidade
- **Problema atual**: t3.medium tem limite de 17 pods/node (ENI padrão). Com 6 nodes t3.medium no grupo `system`, capacidade máxima de 102 pods para workloads de sistema — já atingida em março/2026 (incidente 26h). Prefix Delegation aumenta para 110 pods/node sem custo adicional de instância.
- **Solução**: Habilitar `ENABLE_PREFIX_DELEGATION=true` e `WARM_PREFIX_TARGET=1` no addon VPC CNI via EKS managed addon. Requer rollout de nodes (drain+replace). Janela de manutenção de ~2h.
- **Impacto**: Alto — elimina ENI pod limit como gargalo de capacidade
- **Esforço**: Médio (addon config + node rollout planejado)
- **Quarter**: Q3 2026
- **Dependências**: INIT-013 (Karpenter facilita o node rollout)

### INIT-015: CIS EKS Benchmark Automatizado
- **Dimensão**: Compliance
- **Problema atual**: Nenhuma execução de CIS benchmark documentada. Vulnerabilidades de configuração (PSA, RBAC excessivo, service account tokens auto-mount, etc.) não são auditadas sistematicamente.
- **Solução**: Integrar `kube-bench` como CronJob no cluster (execução semanal). Report exportado para S3 e alerta no Grafana se score < threshold. Também integrar `trivy operator` para scan contínuo de imagens em produção.
- **Impacto**: Alto — compliance auditável, prerequisito para SOC2 e BACEN auditorias
- **Esforço**: Médio (CronJob + dashboard Grafana)
- **Quarter**: Q3 2026
- **Dependências**: INIT-007 (PSA), INIT-005 (audit logs)

### INIT-016: DR Restore Drill — Velero Full Restore
- **Dimensão**: DR & Backup
- **Problema atual**: Velero com backups hourly confirmados (S3 us-east-1 + replica us-west-2 via `velero-backups-staging-891377105802-us-west-2`). EBS snapshots diários confirmados. Porém RTO/RPO nunca foram testados formalmente. Não existe runbook de restore validado. A capacidade de DR existe no papel mas não foi provada.
- **Solução**: Executar DR drill semestral: restaurar namespace não-crítico (ex: staging-data-infrastructure) em ambiente isolado a partir do backup Velero. Medir RTO real. Documentar runbook passo-a-passo. Adicionar DR drill como item obrigatório no calendário de compliance.
- **Impacto**: Alto — valida capacidade de DR antes que seja necessária em produção
- **Esforço**: Médio (2-4h de execução + documentação)
- **Quarter**: Q3 2026
- **Dependências**: INIT-011 (RDS 30d retention)

### INIT-017: Linkerd Phase 2 — mTLS em Todos os Namespaces
- **Dimensão**: Segurança
- **Problema atual**: Linkerd control plane 3/3 Running mas Phase 2 incompleta. Documentado em `2026-03-18-security-domain-vpn-prod.md`: namespaces `argocd`, `gitlab`, `sonarqube`, `harbor` sem injeção de sidecar Linkerd. Comunicação entre esses serviços não tem mTLS — violação de conformidade para ambiente com dados PII (LGPD Art.46).
- **Solução**: Anotar namespaces pendentes com `linkerd.io/inject: enabled`. Validar que serviços funcionam com proxy (alguns podem ter issues com protocolos não-HTTP — ex: PostgreSQL wire protocol). Usar `linkerd.io/inject: disabled` por pod onde necessário. Estratégia Recreate já aplicada em linkerd control-plane.
- **Impacto**: Alto — mTLS compliance completo para todos os serviços de plataforma
- **Esforço**: Médio (namespace annotation + validação por serviço)
- **Quarter**: Q3 2026
- **Dependências**: INIT-006 (Network Policies complement mTLS)

### INIT-018: Multi-Region Failover Documentado e Testado
- **Dimensão**: DR & Backup / Resiliência
- **Problema atual**: Módulo `dr-multi-region` e `vpc-dr` existem no TF mas não foram aplicados. Bucket velero us-west-2 existe mas sem procedimento de failover documentado. RTO alvo de 4h declarado no módulo velero-dr mas não testado.
- **Solução**: Aplicar módulos VPC-DR e DR-multi-region em us-west-2. Criar runbook de failover: (1) promote velero backup us-west-2, (2) restore workloads críticos, (3) DNS failover via Route53 health checks + failover routing policy. Meta: RTO <4h, RPO <1h para workloads ipaas.
- **Impacto**: Alto — garante continuidade de negócio em disaster scenario
- **Esforço**: Alto (infra us-west-2 + teste de failover)
- **Quarter**: Q3 2026
- **Dependências**: INIT-001, INIT-016

### INIT-019: IRSA Rightsizing — Least-Privilege
- **Dimensão**: Segurança / Compliance
- **Problema atual**: 19 IAM roles para EKS (auditado via `list-roles`). Algumas roles têm escopos amplos por conveniência histórica (ex: múltiplos `rds-monitoring` roles). Service accounts com `automountServiceAccountToken` padrão habilitado. Sem auditoria de permissões efetivas por SA.
- **Solução**: Executar `IAM Access Analyzer` por role, identificar permissões não usadas nos últimos 90 dias, aplicar least-privilege. Desabilitar `automountServiceAccountToken: false` em SAs que não precisam acessar a API do cluster (a maioria das aplicações). Consolidar roles redundantes de `rds-monitoring`.
- **Impacto**: Médio — reduz blast radius em caso de comprometimento de SA
- **Esforço**: Médio (análise + mudanças incrementais)
- **Quarter**: Q3 2026
- **Dependências**: INIT-005 (audit logs necessários para análise de uso)

### INIT-020: GitLab Upgrade para LTS Atual
- **Dimensão**: Compliance / Segurança
- **Problema atual**: GitLab CE chart versão 8.7.0 instalado. GitLab mantem versões com CVEs críticos corrigidos apenas nas últimas 3 versões. Versão muito antiga pode ter vulnerabilidades sem patch disponível. CI/CD depende de GitLab ser seguro.
- **Solução**: Upgrade incremental do GitLab CE para versão LTS atual (verificar no momento do upgrade). Usar estratégia de blue-green via ArgoCD (criar nova instância Helm, migrar dados, switchover). Pré-requisito: backup completo validado.
- **Impacto**: Médio — segurança da cadeia de suprimento de software
- **Esforço**: Médio (upgrade complexo com dados)
- **Quarter**: Q3 2026
- **Dependências**: INIT-016 (DR drill valida processo de backup antes do upgrade)

### INIT-021: Backstage Plugin — Cost Visibility por App
- **Dimensão**: Developer Experience / FinOps
- **Problema atual**: Desenvolvedores não têm visibilidade do custo de seus serviços. Backstage mostra catálogo e métricas técnicas mas não custo. FinOps é responsabilidade centralizada sem feedback loop para engenharia.
- **Solução**: Integrar plugin Backstage `@backstage/plugin-cost-insights` (ou equivalente) com dados do AWS Cost Explorer por tag `app` e `team`. Cada componente no catálogo mostra custo atual, tendência e anomalias. Alinhado com tagging strategy já implementada (`CostCenter`, `Team`, `Environment`).
- **Impacto**: Médio — FinOps democratizado, reduz custos via accountability
- **Esforço**: Alto (integração AWS Cost Explorer API + plugin customização)
- **Quarter**: Q3 2026
- **Dependências**: INIT-010 (Backstage E2E validado)

### INIT-022: ChatOps via Teams/Slack para Alertas Críticos
- **Dimensão**: Automação / Observabilidade
- **Problema atual**: Alertmanager configurado com webhooks mas sem canal de comunicação dedicado e estruturado para on-call. Incidente de 26h detectado manualmente. Sem runbook links nos alertas.
- **Solução**: Configurar Alertmanager receiver para Microsoft Teams (webhook) com routing por severity. Mensagens formatadas com: descrição, runbook link, dashboard link, comandos de diagnóstico rápido. Integrar com `monitoring.alertmanager-teams-webhook` já existente no Vault.
- **Impacto**: Alto — reduz MTTD de horas para minutos
- **Esforço**: Médio (Alertmanager config + Teams webhook + template messages)
- **Quarter**: Q4 2026
- **Dependências**: INIT-008 (Dead Man's Switch + SLO alerting)

### INIT-023: Auto-Remediation Runbooks
- **Dimensão**: Automação
- **Problema atual**: Lambda FinOps já faz auto-remediation de CrashLoopBackOff pods. Mas a maioria dos incidentes de plataforma requer intervenção manual. MTTR elevado porque operadores precisam diagnosticar antes de agir.
- **Solução**: Expandir Lambda finops para: (1) auto-restart de deployments críticos com 0 replicas (Cluster Autoscaler, ESO controller), (2) auto-scale up de node groups quando pods Pending > threshold, (3) alertas com actions pré-aprovadas via ChatOps (botão "restart pod" direto no Teams). Usar EventBridge para triggers baseados em CloudWatch alarms.
- **Impacto**: Alto — MTTR de minutos para segundos em incidentes recorrentes
- **Esforço**: Alto (Lambda expansion + EventBridge + validação extensiva)
- **Quarter**: Q4 2026
- **Dependências**: INIT-022 (ChatOps), INIT-008 (alertas estruturados)

### INIT-024: Multi-Region Active-Passive (sa-east-1 LGPD)
- **Dimensão**: DR / Compliance
- **Problema atual**: Toda a plataforma está em us-east-1. LGPD Art.33 impõe restrições sobre transferência internacional de dados pessoais. Dados de produção com PII (marcados como `LGPD: PII` nas tags) armazenados apenas em us-east-1 (Virginia, EUA) pode gerar questionamento regulatório.
- **Solução**: Provisionar região passiva em sa-east-1 (São Paulo) para dados PII de produção. Usar S3 CRR exclusivamente para buckets marcados com LGPD=PII. RDS read replica em sa-east-1 para compliance data residency. Failover via Route53 latency-based routing.
- **Impacto**: Alto — compliance LGPD + DR para região brasileira
- **Esforço**: Alto (nova região AWS, módulos TF duplicados, validação regulatória)
- **Quarter**: Q4 2026
- **Dependências**: INIT-018 (multi-region base em us-west-2 primeiro)

### INIT-025: Backstage TechDocs + ADR Linking
- **Dimensão**: Developer Experience
- **Problema atual**: S3 bucket `backstage-techdocs-891377105802` existe mas TechDocs não estão sendo gerados automaticamente para os componentes. ADRs existem em markdown mas não estão linkados no Backstage. Developer onboarding depende de documentação manual dispersa.
- **Solução**: Configurar `techdocs-backend` para build automático via CI/CD (GitLab pipeline) ao push em repos com `docs/`. Publicar para S3 existente. Linkar ADRs no catálogo Backstage como entidades do tipo `Document`. Objetivo: todo componente tem documentação acessível via Backstage em <2 cliques.
- **Impacto**: Médio — reduz tempo de onboarding e dependência de conhecimento tribal
- **Esforço**: Médio (pipeline + catalog entities)
- **Quarter**: Q4 2026
- **Dependências**: INIT-010 (Backstage E2E)

### INIT-026: SOC2 Type I Readiness
- **Dimensão**: Compliance
- **Problema atual**: Sem assessment formal de controles SOC2. Infraestrutura tem muitos controles técnicos (WAF, encryption, RBAC, audit logs parciais) mas sem documentação de controles operacionais (access reviews, change management, incident response).
- **Solução**: Executar gap assessment SOC2 Type I contra os 5 Trust Service Criteria (Security, Availability, Processing Integrity, Confidentiality, Privacy). Priorizar evidências coletáveis automaticamente (CloudTrail, EKS audit logs, Vault audit log). Criar policy documents para controles operacionais. Meta: readiness report aprovado por management.
- **Impacto**: Alto — habilita auditorias externas e vendas enterprise
- **Esforço**: Alto (processo multi-mês com stakeholders não-técnicos)
- **Quarter**: Q4 2026
- **Dependências**: INIT-005, INIT-015, INIT-019

### INIT-027: EKS Upgrade para 1.31+
- **Dimensão**: Compliance / Segurança
- **Problema atual**: EKS 1.34 (versão atual ao momento da criação do cluster). AWS depreca versões EKS e exige upgrade. Kubernetes 1.31+ traz melhorias em PSA, structured logging, e novos features de escalabilidade.
- **Solução**: Upgrade blue-green: criar novo node group com AMI da nova versão, drain/migrate workloads, remover node group antigo. EKS managed upgrade para control plane. Validar todos os manifests contra nova API (ex: deprecações de APIs beta).
- **Impacto**: Alto — security patches + features enterprise
- **Esforço**: Médio (processo gerenciado pela AWS para control plane + node rolling)
- **Quarter**: Q4 2026
- **Dependências**: INIT-013 (Karpenter facilita node rollout)

### INIT-028: Service Mesh Observability — Grafana mTLS Dashboards
- **Dimensão**: Observabilidade / Segurança
- **Problema atual**: Linkerd control plane Running com Viz ativo, mas sem dashboards Grafana dedicados para visualizar: tráfego mTLS por serviço, taxa de sucesso de mTLS handshakes, latência p99 por rota de serviço mesh, identificação de serviços ainda sem sidecar injetado.
- **Solução**: Importar dashboards oficiais Linkerd para Grafana (disponíveis em grafana.com/dashboards). Criar ServiceMonitors para exportar métricas do Linkerd proxy. Alertas para serviços com TLS failure rate > 1%.
- **Impacto**: Médio — visibilidade operacional do service mesh
- **Esforço**: Médio (dashboards + ServiceMonitors + alertas)
- **Quarter**: Q4 2026
- **Dependências**: INIT-017 (Linkerd Phase 2 completa)

---

## Quick Wins (< 1 sprint — podem ser executados imediatamente)

| # | Ação | Dimensão | Impacto | Esforço Real |
|---|------|----------|---------|--------------|
| QW-01 | **Instanciar módulo Tempo no staging TF** (GAP-TEMPO-IMPORT) — bucket S3 existe, módulo TF existe, apenas adicionar instanciação em main.tf + apply | Observabilidade | Médio | 30min |
| QW-02 | **Habilitar EKS control-plane logging completo** (5/5 tipos) — 1 linha TF | Compliance | Alto | 30min |
| QW-03 | **Deletar EBS orphan** `vol-0055d1a7bc8e4e292` (10GB gp3, created 2026-02-25, not attached) — economia $10/mês | FinOps | Baixo | 5min |
| QW-04 | **RDS backup_retention_period = 30** para prod — 1 variável TF | DR | Médio | 20min |
| QW-05 | **AWS Budget Alerts** — TF resource `aws_budgets_budget` com limites $2.500/mês e alerta 80% | FinOps | Médio | 1h |
| QW-06 | **EKS auth mode CONFIG_MAP → API_AND_CONFIG_MAP** (GAP-FINOPS-ACCESS-ENTRY) | Compliance | Médio | 30min |
| QW-07 | **External-DNS apply** — módulo TF pronto, hosted zones existem, IRSA role existe (`ExternalDNS-k8s-platform-prod-staging`) | Operacional | Alto | 1h |
| QW-08 | **Dead Man's Switch PrometheusRule** — 10 linhas YAML em TF | Observabilidade | Alto | 1h |
| QW-09 | **GAP-WORKLOAD-01: etl-core Deployment→CronJob** — patch no manifests Kustomize | CI/CD | Médio | 1h |
| QW-10 | **VemSoft .gitlab-ci.yml push ao GitLab** — arquivo criado localmente, pendente push | CI/CD | Médio | 15min |

---

## FinOps Roadmap — Estimativas de Economia

| Iniciativa | Timeline | Economia Estimada/Ano | Investimento | ROI 1-ano |
|-----------|----------|----------------------|-------------|----------|
| QW-03: EBS orphan cleanup | Imediato | R$600 | R$0 | Infinito |
| INIT-004: Compute Savings Plans (1yr no-upfront) | Q2 | R$3.600-5.400 | R$0 (commitment) | Imediato |
| INIT-003: Spot Instances workloads (70%) | Q2 | R$8.000-12.000 | R$0 | 1 mês |
| INIT-013: Karpenter (bin-packing + Spot avançado) | Q3 | R$6.000-9.000 adicionais | R$4.000 eng | 4 meses |
| INIT-012: Budget Alerts (previne over-provisioning) | Q2 | R$2.000-5.000 | R$0 | Imediato |
| INIT-014: Prefix Delegation (evita upgrade prematuro) | Q3 | R$3.000-6.000 | R$0 | 2 meses |
| **Total Potencial** | **Q2-Q3** | **R$23.200-37.400/ano** | **<R$5.000** | **<3 meses** |

*Valores em BRL estimados com USD/BRL=5.5 e preços EC2 us-east-1 On-Demand vs Spot/SP.*

**Savings acumulados ja realizados em Q1 2026**: R$30.982/ano (auditoria 2026-02-11)

**Savings totais com roadmap Q2-Q3**: R$30.982 + R$23.200-37.400 = **R$54.182-68.382/ano**

> **Atualizacao 2026-03-27:**
> - Savings adicionais realizados nesta sessao: ~$28/mes ($336/ano / R$1.848/ano) via right-sizing staging
> - **ALERTA:** EventBridge 6 shutdown rules DISABLED — custo extra **+$346.75/mes (+$4.161/ano / R$22.886/ano)**
> - Saldo liquido: **-$319/mes** (custo AUMENTOU vs sessao anterior)
> - Savings totais realizados ajustados: R$30.982 - R$22.886 + R$1.848 = **R$9.944/ano** (enquanto EventBridge estiver DISABLED)
> - **Acao urgente:** Reabilitar shutdown rules para restaurar R$22.886/ano de savings
> - Custo mensal atual: **$1,590.86/mes** (18 nodes, 2 NATs, 7 ALBs, 1 RDS Single-AZ)
> - Ver detalhamento completo: `2026-03-27-finops-cost-summary.md`

---

## Matriz de Risco — Top 5 Riscos não Endereçados

| Risco | Probabilidade | Impacto | Mitigação |
|-------|--------------|---------|-----------|
| RDS Single-AZ falha (INIT-001 pendente) | Médio | CRITICO — downtime total da plataforma | INIT-001 Q2, prioridade máxima |
| NAT Gateway falha AZ única (INIT-002 pendente) | Baixo | Alto — cluster sem conectividade externa | INIT-002 Q2 |
| EKS control-plane audit log ausente — incidente não rastreável | Alto | Alto — compliance e forense impossível | QW-02 imediato |
| Velero restore nunca testado — RPO/RTO teórico apenas | Médio | Alto — DR ineficaz na prática | INIT-016 Q3 |
| Spot interruption sem tolerations adequados (pos INIT-003) | Medio | Medio — disruption de workloads | Deve ser planejado junto com INIT-003 |
| **EventBridge 6 shutdown rules DISABLED (2026-03-27)** | **Alto** | **Alto — +$347/mes custo extra, anula 74% dos savings FinOps** | **Reabilitar rules imediatamente** |

---

## Referências

- Plano Produção: `docs/demands/2026-03-18-plano-ambiente-producao.md`
- Onboarding ETL: `docs/demands/2026-03-13-hatch-etl-onboarding-eks.md`
- Catálogo Componentes: `docs/demands/2026-03-18-catalogo-componentes-plataforma.md`
- FinOps Roadmap Pós-Auditoria: `docs/demands/2026-02-12-finops-roadmap-pos-audit.md`
- Cluster Autoscaler Resiliência: `docs/demands/2026-03-17-cluster-autoscaler-resiliencia.md`
- Revisão Capacidade Karpenter: `docs/demands/2026-03-17-revisao-capacidade-karpenter.md`
- Segurança e VPN Prod: `docs/demands/2026-03-18-security-domain-vpn-prod.md`
- Observabilidade Alertas: `docs/demands/2026-03-17-observabilidade-capacity-alertas.md`
- IaC Compliance: `docs/demands/2026-03-05-iac-compliance-migration.md`
- Backstage IDP: `docs/demands/2026-03-11-s6-backstage-idp-integration.md`
- Sessão 2026-03-21: `memory/session-2026-03-21-monitoring.md`
- MEMORY.md: `memory/MEMORY.md`
