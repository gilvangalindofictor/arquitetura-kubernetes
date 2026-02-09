# current_state.md

> **Responsabilidade**: AI (atualizado automaticamente após cada task)
> **Quando atualizar**: Após CADA task que modifica código/infra
> **Prioridade de leitura**: 4

---

## Status Geral

**Última Atualização**: 2026-02-06 (Marco 4 - GAP-002 e GAP-004 deployados)

**Estado do Projeto**: Desenvolvimento Ativo - Marco 4 em andamento

**Marco Atual**: Marco 4 - CI/CD Platform (75% completo)

**Progresso Geral**: 75% ██████████████████░░░░░░ (Marcos 0-3 + 75% Marco 4 / 0-6)

---

## Marcos

| Marco              | Status         | Progresso | Duração | Custo/Mês | Completado em |
| ------------------ | -------------- | --------- | ------- | --------- | ------------- |
| Marco 0            | ✅ Completo     | 100%      | 2 dias  | ~$0.01    | ✅             |
| Marco 1            | ✅ Completo     | 100%      | 1 dia   | $547      | ✅             |
| Marco 2            | ✅ Completo     | 100%      | 3 dias  | +$66      | ✅             |
| Marco 3 Fase 1a/1b | ✅ Completo     | 100%      | 5 dias  | +$58      | ✅             |
| Marco 3 Fase 1c    | ✅ Completo     | 100%      | < 1h    | $0        | ✅             |
| Marco 3 Fase 1d    | ✅ Completo     | 100%      | 3 dias  | +$0.50    | ✅             |
| Marco 3 Fase 1e    | ✅ Completo      | 100%      | 2h32min | +$28.90   | ✅ 2026-02-06 |
| Marco 4            | 🚧 Em andamento  | 75%       | ~10h    | +$100     | —             |
| Marco 5            | ⏸️ Pendente      | 0%        | TBD     | TBD       | —             |
| Marco 6            | ⏸️ Pendente      | 0%        | TBD     | TBD       | —             |

**Legenda**: ✅ Completo | 🚧 Em andamento | ⏸️ Pendente | ⚠️ Bloqueado

**Total até Marco 3**: ~14 dias de trabalho efetivo | ~$700/mês staging
**Marco 4 Atual**: 4/8 GAPs completos (75% core features) | +$100/mês | ~$800/mês total

---

## Tasks Recentes

**Marco 4 - CI/CD Platform (Em andamento - 75% completo)**:

- ✅ GAP-001: Keycloak SSO Platform Deploy (2026-02-06, ~6h)
- ✅ GAP-003: ArgoCD GitOps Deploy (2026-02-06, ~2h)
- 🟡 GAP-002: GitLab Components Fix (2026-02-06, ~2h, 90% completo)
- ✅ GAP-004: SonarQube Code Quality Deploy (2026-02-06, ~2h)

**Próximos Passos**:

- [ ] Resolver GitLab runner registration (aguardar migrations ~30min)
- [ ] Validar OIDC login (SonarQube + ArgoCD)
- [ ] GAP-005: GitLab CI/CD Integration (3h)
- [ ] GAP-006/007/008: Hardening (ApplicationSets, Network Policies, Dashboards)

---

## Componentes

### Infraestrutura Base

| Componente     | Status        | Versão  | Config      | Notas                                       |
| -------------- | ------------- | ------- | ----------- | ------------------------------------------- |
| AWS VPC        | ✅ Operacional | —       | 10.0.0.0/16 | 2 subnets públicas, 2 privadas              |
| VPC Endpoints  | ✅ Operacional | —       | STS + EC2   | ADR-046, custo +$28.90/mês                  |
| EKS Cluster    | ✅ Operacional | 1.28    | 7 nodes     | 3 node groups (critical, system, workloads) |
| EBS CSI Driver | ✅ Operacional | v1.26.1 | —           | Para persistent volumes                     |
| VPC CNI        | ✅ Operacional | v1.16.0 | —           | Networking                                  |
| CoreDNS        | ✅ Operacional | v1.10.1 | —           | DNS interno                                 |
| kube-proxy     | ✅ Operacional | v1.28.2 | —           | Network rules                               |

---

### Platform Services (Marco 2)

| Componente                   | Status        | Versão | Réplicas | Namespace               | Notas                    |
| ---------------------------- | ------------- | ------ | -------- | ----------------------- | ------------------------ |
| Prometheus                   | ✅ Operacional | 2.48.0 | 1        | monitoring              | Metrics collection ok    |
| Grafana                      | ✅ Operacional | 10.2.0 | 1        | monitoring              | Dashboards principais ok |
| Loki                         | ✅ Operacional | 2.9.3  | 1        | monitoring              | Logs agregados           |
| Tempo                        | ✅ Operacional | 2.3.1  | 1        | monitoring              | Traces distribuídos      |
| Cluster Autoscaler           | ✅ Operacional | 1.28.x | 1        | kube-system             | Auto-scaling nodes       |
| Metrics Server               | ✅ Operacional | 0.6.4  | 1        | kube-system             | HPA support              |
| AWS Load Balancer Controller | ✅ Operacional | 2.7.0  | 2        | kube-system             | Ingress ALB              |
| External Secrets Operator    | ✅ Operacional | 0.9.11 | 1        | external-secrets-system | Vault integration        |

---

### Workloads (Marco 3)

| Aplicação      | Status        | Versão      | Réplicas               | Namespace     | Database               | Notas                                          |
| -------------- | ------------- | ----------- | ---------------------- | ------------- | ---------------------- | ---------------------------------------------- |
| PostgreSQL RDS | ✅ Operacional | 15.4        | —                      | —             | db.t3.medium Single-AZ | Temporariamente em subnet pública (ADR-046)    |
| Redis Sentinel | ✅ Operacional | Chart 3.2.9 | 3 sentinels + 1 master | data-services | —                      | Operator-based, toleration critical nodes      |
| RabbitMQ       | ✅ Operacional | Operator    | 1                      | data-services | —                      | Official operator                              |
| GitLab         | ✅ Operacional | 16.7.0      | 1                      | gitlab        | PostgreSQL RDS         | Webservice + Sidekiq + Gitaly ok               |
| Harbor         | ✅ Operacional | 2.9.1       | 1                      | harbor        | PostgreSQL RDS         | Registry funcional, robot accounts ok          |
| Vault          | ✅ Operacional | 1.15.0      | 3 (HA)                 | vault         | PostgreSQL RDS         | HA injector + unsealing automatizado (ADR-041) |

---

### CI/CD Platform (Marco 4) - 🚧 75% Completo

| Aplicação | Status         | Versão            | Réplicas | Namespace      | Database       | Notas                                              |
| --------- | -------------- | ----------------- | -------- | -------------- | -------------- | -------------------------------------------------- |
| Keycloak  | ✅ Operacional | 23.0.0            | 1        | keycloak       | PostgreSQL RDS | SSO centralizado, OIDC clients: argocd, sonarqube  |
| ArgoCD    | ✅ Operacional | 2.9.3             | 2/2      | argocd         | PostgreSQL RDS | GitOps platform, OIDC Keycloak, 8/8 pods running   |
| SonarQube | ✅ Operacional | 10.3.0-community  | 1        | sonarqube      | PostgreSQL RDS | Code quality, OIDC Keycloak, PVC 20Gi              |
| GitLab    | 🟡 90% OK      | 16.7.0 (v17.7.0)  | Vários   | gitlab-staging | PostgreSQL RDS | Core OK, runner pending (migrations ~30min)        |

**GAPs Marco 4**:

- ✅ GAP-001: Keycloak SSO (100% - deployed 2026-02-06)
- 🟡 GAP-002: GitLab Fix (90% - core operacional, runner pendente)
- ✅ GAP-003: ArgoCD GitOps (100% - deployed 2026-02-06)
- ✅ GAP-004: SonarQube (100% - deployed 2026-02-06)
- ⏸️ GAP-005: GitLab CI/CD Integration (0% - aguarda runner)
- ⏸️ GAP-006: ApplicationSets GitOps Patterns (0%)
- ⏸️ GAP-007: Network Policies Marco 4 (0%)
- ⏸️ GAP-008: Monitoring & Dashboards Marco 4 (0%)

**Known Issues Marco 4**:

- 🟡 GitLab runner: Registration failing (GitLab API 500 - migrations pending)
- ⚠️ SonarQube Prometheus exporter: Disabled (Maven Central timeout)
- 🟡 OIDC testing: Pending manual validation (SonarQube + ArgoCD)

---

## Observabilidade

**Stack de Monitoring**:
- ✅ Prometheus: metrics coleta operacional
- ✅ Grafana: dashboards principais disponíveis
- ✅ Loki: logs centralizados funcionando
- ✅ Tempo: traces distribuídos habilitados
- ⏸️ Alertmanager: configuração básica, alertas críticos pendentes

**Dashboards Disponíveis**:
- Cluster Overview (nodes, pods, resources)
- Application Metrics (GitLab, Harbor, Keycloak)
- PostgreSQL Metrics
- Cost Analysis (via logs de FinOps Lambda)

**Logs**:
- Centralizados no Loki
- Retenção: 7 dias (configuração atual)
- Query via Grafana Explore

**Metrics**:
- Scrape interval: 15s
- Retention: 15 dias (Prometheus)
- Exporters: node-exporter, kube-state-metrics

**Alertas Configurados**: Básicos (pod restarts, node not ready)

**Alertas Pendentes**:
- [ ] Disk space critical
- [ ] Memory pressure
- [ ] Certificate expiration
- [ ] Database connection pool exhaustion

---

## Secrets Management

**Estratégia**: Vault + External Secrets Operator

**Status Migração para Vault**:
| Aplicação | Status     | External Secret | Detalhes                                  |
| --------- | ---------- | --------------- | ----------------------------------------- |
| Keycloak  | ✅ Migrado  | ✅ Configurado   | Admin password, DB credentials via Vault  |
| Harbor    | 🚧 Parcial  | ⏸️ Pendente      | Usando secrets manuais, migração pendente |
| GitLab    | ⏸️ Pendente | ⏸️ Pendente      | Usando secrets manuais                    |

**Temporary Secrets (AWS Secrets Manager)**:
- FinOps Lambda unseal token (transitório, migrar para Vault)

**Security Groups**:
- PostgreSQL: Least privilege (apenas Lambda e EKS nodes) - ADR-040

---

## FinOps

**Última Análise**: 2026-02-05

**Custo Atual Staging (mensal)**:

| Categoria                   | Custo      | Percentual |
| --------------------------- | ---------- | ---------- |
| EKS Cluster (control plane) | $73        | 9.1%       |
| EC2 Nodes (7 nodes)         | $474       | 59.3%      |
| PostgreSQL RDS              | $58        | 7.3%       |
| VPC Endpoints               | $28.90     | 3.6%       |
| EBS Volumes                 | $50        | 6.3%       |
| Load Balancers              | $16        | 2.0%       |
| **Marco 4 (Keycloak+Argo+Sonar)** | **+$100** | **12.5%** |
| **Total Marco 0-4**         | **~$800**  | **100%**   |

**Automação FinOps (ADR-024)**:
- ✅ Lambda start/stop para RDS + ASGs
- ✅ EventBridge schedules:
  - Start: Segunda-Sexta 07:00 UTC
  - Stop: Segunda-Sexta 19:00 UTC
- ✅ Economia projetada: R$ 360/mês (~$70/mês)

**Otimizações Implementadas**:
- ✅ Auto-shutdown ambiente staging (ADR-024)
- ✅ Single-AZ RDS (staging only)
- ✅ Tolerations para node groups (evitar over-provisioning)

**Próximas Otimizações**:
- [ ] Spot instances para workloads node group
- [ ] Karpenter para auto-scaling mais eficiente
- [ ] Revisão de tamanhos de volumes EBS

---

## Testes

**Última Execução**: Não aplicável (infra não tem tests

 automatizados ainda)

| Tipo                    | Total | Passed | Failed | Cobertura |
| ----------------------- | ----- | ------ | ------ | --------- |
| Unit                    | 0     | 0      | 0      | —         |
| Integration (Terratest) | 0     | 0      | 0      | —         |
| E2E                     | 0     | 0      | 0      | —         |
| Performance             | 0     | 0      | 0      | —         |

**Status**: ⚠️ Sem testes automatizados

**Ação**: Implementar Terratest para módulos Terraform (Marco 4+)

---

## Segurança

**Última Audit**: Não realizado formalmente ainda

**Security Posture**:
- ✅ Secrets via Vault + ESO (parcial, migração em andamento)
- ✅ Network Policies: básicas implementadas (Marco 2)
- ✅ RBAC: configurado por namespace
- ✅ Security Groups: least privilege (ADR-040)
- ⏸️ Service Mesh (Linkerd): planejado para Marco 5
- ⏸️ API Gateway (Kong): planejado para Marco 5
- ⏸️ Policy Engine (Kyverno): planejado para Marco 5
- ⏸️ Runtime Security (Falco): planejado para Marco 5

**Vulnerabilities Scan**: Não executado ainda

**Pendências Críticas**:
- [ ] PostgreSQL em subnet pública temporário - migrar após estabilização (ADR-046)
- [ ] Completar migração de secrets para Vault (Harbor, GitLab)
- [ ] Implementar security audit completo (checklist OWASP Top 10)
- [ ] Configurar TLS para todos os endpoints

---

## Dívida Técnica

**Top 5 Items**:

1. **PostgreSQL em Subnet Pública (Temporário)** - Severidade: HIGH
   - **Impacto**: Exposição de banco (mitigado por SG restritivo)
   - **Esforço**: M (depende de VPC endpoints funcionais)
   - **Plano**: Migrar para subnet privada quando Vault estável (Marco 4)
   - **Relacionado**: ADR-046

2. **Secrets Hardcoded (Harbor, GitLab)** - Severidade: HIGH
   - **Impacto**: Secrets em Kubernetes Secrets não criptografados em rest
   - **Esforço**: S (migração via ESO)
   - **Plano**: Marco 4, após Vault 100% estável

3. **Sem Testes Automatizados (IaC)** - Severidade: MEDIUM
   - **Impacto**: Risco de regressão em mudanças Terraform
   - **Esforço**: M (setup Terratest + CI)
   - **Plano**: Marco 4

4. **RDS Single-AZ (Staging)** - Severidade: LOW (staging only)
   - **Impacto**: Sem HA em staging (aceitável)
   - **Esforço**: S (flag Multi-AZ)
   - **Plano**: Production será Multi-AZ desde o início

5. **Alertas Básicos (Observability)** - Severidade: MEDIUM
   - **Impacto**: Possível falha sem notificação rápida
   - **Esforço**: M (definir alertas + routing)
   - **Plano**: Marco 5 (observability completa)

---

## Próximos Passos

**Marco 4 - CI/CD Completa** (Planejado):
- [ ] GitLab Runners configurados
- [ ] SonarQube para análise de código
- [ ] ArgoCD para GitOps
- [ ] Backstage para catálogo de serviços
- [ ] Templates Backstage para novos projetos

**Dependências Críticas**:
- Vault 100% estável (unseal confiável)
- PostgreSQL migrado para subnet privada (ou aceitar temporário)

**Riscos Identificados**:
- ⚠️ Vault unsealing após restarts (mitigado com HA + VPC endpoints)
- ⚠️ Custo crescente com adição de serviços (monitorar via FinOps)
- ⚠️ Complexidade aumentando (documentar bem, manter ADRs atualizados)

---

## Mudanças Recentes

### [2026-02-06]
- ✅ VPC Endpoints STS + EC2 criados (ADR-046)
- ✅ Vault recovery após issue de unsealing
- ✅ PostgreSQL SG atualizado para permitir Lambda
- ✅ Keycloak + GitLab + Harbor reconectados
- 🐛 Identificado: Vault precisa de PostgreSQL acessível antes de seal

### [2026-02-05]
- ✅ Vault HA migration de 1→3 replicas (ADR-041)
- ✅ FinOps Lambda completamente funcional (ADR-024)
- ✅ Harbor robot accounts configurados
- ✅ Observability stack recovery pós-taint

### [2026-02-04]
- ✅ PostgreSQL RDS security group fix (ADR-040)
- ✅ Harbor deployment completo
- ✅ FinOps Lambda Python downgrade (3.13→3.12)

### [2026-02-03]
- ✅ GitLab migration (envs→environments) fix
- ✅ Terraform drift cleanup (GitLab, RabbitMQ)
- ✅ Redis Sentinel user:1000 filesystem fix

---

## Metrics de Qualidade

**Commits com Co-Authorship AI**: ~80% (estimado)

**ADRs Criados**: 46 (ADR-001 a ADR-046)

**Logbooks Escritos**: 48 arquivos

**Documentation Coverage**: Alta (PROJECT-CONTEXT.md, README.md, ADRs, logbooks extensos)

**Code Review**: Manual (não automatizado ainda)

---

## Notas

### Hierarquia de Ambientes

- **Atual**: staging only (`k8s-platform-prod` - naming histórico)
- **Futuro**: Multi-environment (ADR-026)
  - staging: `k8s-platform-staging`
  - production: `k8s-platform-production`

### Estratégia Cloud

- **MVP (Atual)**: AWS-First, 75-80% cloud-agnostic by design
- **Futuro**: 100% cloud-agnostic via operators (RDS → CloudNativePG, etc.)

### AI-First Development

- Sistema de aprendizagem ativo (scaffold kit bootstrap em 2026-02-06)
- Hooks Git obrigatórios
- Rastreabilidade total via logbooks

---

_Auto-atualizado pelo sistema de scaffold | Última task: Bootstrap Scaffold Kit em 2026-02-06_
