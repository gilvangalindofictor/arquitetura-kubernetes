# Changelog - AWS EKS Quickstart

---

## [4.0.0] - 2026-03-04

### 🎯 Estado: Marco 4 + CI/CD Enhancement + INFRA Upgrades — 100% Completo

Revisão completa do quickstart-REAL refletindo o estado auditado do ambiente staging após conclusão de todos os marcos até Marco 4, incluindo iPaaS Public Readiness, CI/CD Enhancement e upgrades de infraestrutura críticos.

### ✅ Mudanças Principais

#### Infraestrutura e Upgrades
- **INFRA-001**: GitLab v17.7 → **v18.9.1** (chart 9.9.1, Rev 36) — 9 breaking changes resolvidos
- **INFRA-002**: PostgreSQL RDS **14.8 → 16.4** — upgrade in-place sem downtime
- **kube-proxy** drift: v1.31.2 ≠ v1.34.x (registrado como dívida técnica T3)

#### Namespace Migration (DEC-074) — 100%
- **17 namespaces** migrados para o padrão `{env}-{domain}-{product}`
- Enforcement Kyverno ativo — rejeita namespaces sem padrão
- Segregação completa: `staging-platform-*` / `staging-security-*` / `staging-data-*` / `staging-observability-*` / `staging-governance-*`

#### iPaaS Public Readiness (GAP-010/011/012) — 3/3 ✅
- **GAP-010**: AWS WAF v2 deployado. WebACL com 5 managed rules (Rate Limit, Geo Block, OWASP, SQLi, Bad Inputs). S3 logging 90 dias.
- **GAP-011**: Linkerd Service Mesh (mTLS automático). 7/7 pods Running. Phase 2 completo: 18/18 proxies injetados (harbor 7/7 + gitlab 11/11).
- **GAP-012**: Velero DR Phase 1. S3 CRR us-east-1→us-west-2 com 15-min RTC SLA. Daily + Weekly schedules.

#### CI/CD Enhancement (CICD-001 a 005) — 5/5 ✅
- **CICD-001**: SAST/DAST pipeline enforcing — Harbor Trivy + SonarQube Quality Gate bloqueiam HIGH+CRITICAL
- **CICD-002**: Quality Gate "Production" default — Coverage ≥80%, Bugs=0, Vulnerabilities=0
- **CICD-003**: Secret rotation automática — CronJob quarterly (PostgreSQL + Keycloak + OIDC)
- **CICD-004**: Immutable image tags — 12 regras de imutabilidade em 3 projetos Harbor
- **CICD-005**: Argo Rollouts deployado — Canary + Blue-Green, 4 AnalysisTemplates

#### Governance & Security
- **Kyverno**: 100% compliance (80/80 PASS), 3 políticas em modo enforce
- **ESO**: 16/16 ExternalSecrets em `SecretSynced`
- **Vulnerabilidades**: V-001 a V-008 todos RESOLVIDOS (zero static credentials, IRSA completo)

#### Segregação Staging/Production (nova seção)
- **Staging**: documentado como estado operacional real
- **Production**: seção nova com gating criteria, arquitetura planejada, custo projetado e plano de execução por marcos

### 📊 Documentos Atualizados
- ✅ [aws-eks-gitlab-quickstart-REAL.md](aws-eks-gitlab-quickstart-REAL.md) — v4.0 completo (9 seções)
- ✅ [CHANGELOG.md](CHANGELOG.md) — este documento

### 📈 Métricas da Plataforma (2026-03-04)

| Métrica                 | Valor                    |
| ----------------------- | ------------------------ |
| Enterprise Maturity     | 4.0/5.0 (Advanced+)      |
| Production Readiness    | 85%                      |
| Kyverno Compliance      | 100% (80/80 PASS)        |
| FinOps Savings          | R$ 62.425/ano            |
| Custo staging (líquido) | ~$716/mês                |
| Custo staging (diário)  | ~$13/dia (vs $50 sem. 1) |
| ADR Coverage            | 99 ADRs documentados     |
| Componentes core        | 30+ operacionais         |

---

## [3.0.0] - 2026-02-12

### 🎯 Reconciliação Pós-Upgrade EKS 1.34

Primeiro documento com dados reais do AWS CLI (reconciliação pós-upgrade v1.34). Verificação auditada de todos os recursos AWS vs estado Terraform.

### ✅ Mudanças Principais
- **EKS Version**: Real = 1.34 Standard (vs planejado 1.28). Custo EKS: $73/mês Standard (vs $378 Extended).
- **Node Groups**: 3 grupos reais (system + workloads + critical) vs 1 grupo no TF.
- **8 Load Balancers** inventariados (6 ALBs + 2 NLBs).
- **14 volumes EBS / 555 GB** mapeados.
- **FinOps Automation**: Lambda start/stop + EventBridge ativo. Economia: $177/mês.
- **Marco 4 em andamento**: ~80% (GitLab OIDC Keycloak operacional, ArgoCD OIDC operacional).
- **10 Terraform gaps** identificados (T1–T8 + orphan SGs + endpoints ausentes).
- Custo staging efetivo: **~$716/mês** (vs $1.397/mês v2.0 = -49%).

### 🔗 Referências
- [QUICKSTART-RECONCILIATION-2026-02-12.md](../../infrastructure/QUICKSTART-RECONCILIATION-2026-02-12.md)
- [AWS-TERRAFORM-DOC-RECONCILIATION-2026-02-12.md](../../infrastructure/AWS-TERRAFORM-DOC-RECONCILIATION-2026-02-12.md)

---

## [2.0.0] - 2026-01-07

### 🎯 Decisão Estratégica: Arquitetura de 2 Ambientes

Após análise técnica e financeira documentada em [technical-roundtable.md](technical-roundtable.md), decidimos por uma **arquitetura de 2 ambientes (Staging + Prod)**, removendo o ambiente Dev dedicado.

### ✅ Mudanças Principais

#### Arquitetura
- **REMOVIDO**: Ambiente Dev dedicado
- **ADICIONADO**: Staging assume papel dual (testes + homologação)
- **MANTIDO**: Prod dedicado com alta disponibilidade

#### Namespaces
```diff
- namespace: dev         (REMOVIDO)
- namespace: app-default (REMOVIDO)
+ namespace: staging     (NOVO - testes + homologação)
+ namespace: prod        (NOVO - produção)
  namespace: observability (compartilhado entre staging e prod)
  namespace: kube-system (sistema)
```

#### Infraestrutura
- **RDS PostgreSQL**: 2 instâncias (1 staging db.t3.small, 1 prod db.t3.medium)
- **Redis**: 2 deployments (staging básico, prod HA com Sentinel)
- **RabbitMQ**: 2 deployments (staging single-node, prod cluster)
- **GitLab**: 2 instalações (staging compartilhada, prod dedicada)

#### Custos Atualizados

| Componente | Antes (3 ambientes) | Depois (2 ambientes) | Economia              |
| ---------- | ------------------- | -------------------- | --------------------- |
| **Mensal** | R$ 5.100            | R$ 4.074             | **-R$ 1.026 (-20%)**  |
| **Anual**  | R$ 61.200           | R$ 48.888            | **-R$ 12.312 (-20%)** |

**Com otimizações de start/stop em Staging**:
- Custo otimizado: **R$ 3.624/mês** (R$ 43.488/ano)
- Economia adicional: **R$ 450/mês** (R$ 5.400/ano)
- **Economia total vs 3 ambientes**: **R$ 1.476/mês** (R$ 17.712/ano) = **-29%**

### 📊 Documentos Atualizados

#### 1. [aws-eks-gitlab-quickstart.md](aws-eks-gitlab-quickstart.md)
- ✅ Seção "Decisões chave" atualizada
- ✅ "Componentes Principais" reflete 2 ambientes
- ✅ Custos recalculados com breakdown detalhado
- ✅ Tabela comparativa 2 vs 3 ambientes
- ✅ Seção "Observações" atualizada com uso de Staging
- ✅ Link para mesa técnica de decisão

#### 2. [diagrams/gitlab_eks_platform.mmd](diagrams/gitlab_eks_platform.mmd)
- ✅ Diagrama completamente redesenhado
- ✅ Namespace `staging` em verde (testes)
- ✅ Namespace `prod` em vermelho (produção)
- ✅ Namespace `observability` em azul (compartilhado)
- ✅ 2 instâncias RDS separadas visíveis
- ✅ Redis/RabbitMQ segregados por namespace
- ✅ Labels de telemetria multi-tenant (env=staging/prod)

#### 3. [technical-roundtable.md](technical-roundtable.md) - NOVO
- ✅ Simulação completa de mesa técnica
- ✅ Debate: EC2 vs Kubernetes (Decisão: K8s)
- ✅ Debate: Precisa de Dev? (Decisão: Não, otimizar custo)
- ✅ Debate: Investir sem devs? (Decisão: Sim, com capacitação)
- ✅ Análise de ROI detalhada
- ✅ Budget aprovado: R$ 113k (ano 1) + R$ 35k (ano 2)
- ✅ ROI esperado: +89% (R$ 132k ganho em 2 anos)

#### 4. [evolution-strategy.md](evolution-strategy.md) - NOVO
- ✅ Roadmap de evolução completo (5 fases)
- ✅ Custos evolutivos por fase
- ✅ Gatekeepers de transição
- ✅ Checklists de validação
- ✅ Exemplos práticos de código

### 🎯 Justificativa da Decisão

#### Por que remover Dev?

**Análise de Custo-Benefício**:
- Time atual: 2 analistas infra, 1 DBA, 0 desenvolvedores dedicados
- Uso previsto de Dev: <20% do tempo (baixa utilização)
- Staging pode servir como ambiente de testes
- Economia: R$ 12.312/ano

**Quando Staging NÃO é suficiente**:
- Se time crescer para 5+ desenvolvedores
- Se houver 10+ deploys/dia
- Se experimentação causar >3 quebras/mês em staging
- **Neste caso**: Adicionar Dev novamente (custo incremental ~R$ 1.000/mês)

#### Por que manter 2 ambientes (não apenas 1)?

**Isolamento é crítico**:
- Testes em staging não afetam prod
- Validação de upgrades sem risco
- POCs e experimentações seguras
- DR drill sem impacto em prod
- Custo marginal: Apenas R$ 1.122/mês para staging

### 📋 Próximos Passos

1. **Aprovação Executiva**
   - [ ] Apresentar [technical-roundtable.md](technical-roundtable.md) para C-Level
   - [ ] Obter budget approval: R$ 113k (ano 1)

2. **Revisão de Documentação**
   - [x] Quickstart atualizado com 2 ambientes
   - [x] Diagramas atualizados
   - [x] Custos recalculados
   - [ ] Executar validação técnica com time terceirizado

3. **Implementação** (seguir [aws-eks-gitlab-quickstart.md](aws-eks-gitlab-quickstart.md))
   - Sprint 1: Cluster + GitLab staging
   - Sprint 2: Observability + GitLab prod
   - Sprint 3: Hardening + DR Drill

### 🔗 Referências

- [AWS EKS Quickstart](aws-eks-gitlab-quickstart.md) - Plano de implementação
- [Mesa Técnica](technical-roundtable.md) - Análise de decisões
- [Estratégia de Evolução](evolution-strategy.md) - Roadmap futuro
- [Diagrama Arquitetural](diagrams/gitlab_eks_platform.mmd) - Arquitetura visual

---

## [1.0.0] - 2026-01-06

### Versão Inicial
- Quickstart com 3 ambientes (Dev + Staging + Prod)
- Custos estimados: R$ 5.100/mês
- Diagramas conceituais
- Épicos e sprints definidos
