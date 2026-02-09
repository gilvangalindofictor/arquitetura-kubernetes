# Documento de Governança - Domínios Corporativos

> **Versão**: 1.0
> **Data**: 2026-02-09
> **Status**: Ativo
> **Referências**: ADR-047, ADR-048, ADR-049

---

## 📋 Visão Geral

Este documento define as **regras determinísticas de governança** para domínios corporativos na Plataforma Kubernetes. Todas as regras são validáveis automaticamente via regex, scripts e admission controllers.

**Filosofia**: "Regras claras, não ambíguas, automaticamente validáveis"

**Escopo**:
- Naming conventions (GitLab, Kubernetes, Backstage)
- RBAC (GitLab Groups, Kubernetes RBAC, Backstage Teams)
- Processos (criação de domínios, produtos, aplicações, exceções)
- Enforcement (Kyverno, pre-push hooks, CI/CD validation)

---

## 🎯 Princípios de Governança

### 1. Determinístico
- Toda regra tem regex validável
- Sem ambiguidade (válido/inválido 100% claro)
- Exemplos de válido/inválido para cada regra

### 2. Automatizado
- Enforcement via tooling (Kyverno, pre-push hooks, CI/CD)
- Scripts de validação (`validate-*.sh`)
- Auditoria mensal automatizada

### 3. Escalável
- Suporta crescimento de 1 pessoa → 100+ pessoas
- Naming conventions suportam centenas de aplicações
- Processos documentados para delegação futura

### 4. Rastreável
- Git history como audit trail
- Labels para chargeback (FinOps)
- Exceções com prazo de expiração

---

## 🏢 5 Domínios Corporativos

**Organização**: Por produtos/linhas de negócio (Domain-Driven Design)

| Domínio | Descrição | Ownership (Futuro) |
|---------|-----------|-------------------|
| **PLATFORM** | Infraestrutura compartilhada (Observabilidade, CI/CD, Secrets, Security) | Platform Team |
| **INTEGRATION** | iPaaS - 9 microserviços para integrações SaaS | Integration Team |
| **DATA** | ETL Hatch (151 extractors), VemSoft, Data Platform | Data Team |
| **OPERATIONS** | Process Management, Fulfillment, Monitoring Operacional | Operations Team |
| **SHARED-SERVICES** | Files, Notification, Calendar, Automation (RPA) | Shared Services Team |

**Referência**: [ADR-047: Estrutura Corporativa de Domínios de Negócio](../adr/adr-047-estrutura-corporativa-dominios.md)

---

## 📛 Naming Conventions (Determinísticas)

**Referência**: [ADR-048: Naming Conventions Determinísticas](../adr/adr-048-naming-conventions-deterministicas.md)

### GitLab Groups/Repos

**Formato**: `^(corporate-domains)/(platform|integration|data|operations|shared-services)/[a-z0-9-]+$`

**Exemplos Válidos**:
```
✅ corporate-domains/integration/ipaas-bff-rest
✅ corporate-domains/data/hatch/hatch-etl
✅ corporate-domains/shared-services/files/bucketconnector
✅ corporate-domains/operations/process-management/process-api
```

**Exemplos Inválidos**:
```
❌ corporate-domains/Integration/iPaaS-BFF-REST   (uppercase não permitido)
❌ corporate-domains/gateway/ipaas-bff-rest       (domínio 'gateway' não existe)
❌ corporate-domains/integration/iPaaS_BFF_REST   (underscore não permitido)
❌ CorporateDomains/integration/ipaas-bff-rest    (camelCase não permitido)
```

**Validação**:
```bash
./scripts/governance/validate-naming.sh <repo-path>
```

---

### Kubernetes Namespaces

**Formato**: `^(dev|staging|prod|shared)-(platform|integration|data|operations|shared)(-[a-z0-9-]+)?$`

**Exemplos Válidos**:
```
✅ staging-integration-ipaas
✅ prod-data-hatch
✅ staging-shared-files
✅ shared-observability
✅ prod-operations-process
```

**Exemplos Inválidos**:
```
❌ staging-gateway-ipaas         (domínio 'gateway' não existe)
❌ Staging-Integration-iPaaS     (uppercase não permitido)
❌ staging_integration_ipaas     (underscore não permitido)
❌ integration-ipaas-staging     (ordem errada: ambiente deve vir primeiro)
```

**Validação**:
```bash
kubectl get ns -o json | jq -r '.items[].metadata.name' | grep -vE '^(dev|staging|prod|shared)-(platform|integration|data|operations|shared)(-[a-z0-9-]+)?$'
# Se retornar namespaces, estão violando naming convention
```

---

### Kubernetes Labels (Obrigatórias)

**CNCF Recommended Labels** (todas obrigatórias):

```yaml
app.kubernetes.io/name:
  regex: ^[a-z0-9-]+$
  max_length: 63
  description: Nome da aplicação (ex: ipaas-bff-rest)
  exemplo: ipaas-bff-rest

app.kubernetes.io/instance:
  regex: ^[a-z0-9-]+$
  max_length: 63
  description: Instância única (ex: staging-ipaas-bff-rest)
  exemplo: staging-ipaas-bff-rest

app.kubernetes.io/version:
  regex: ^\d+\.\d+\.\d+$
  description: Semantic versioning (major.minor.patch)
  exemplo: 1.2.0

app.kubernetes.io/component:
  regex: ^(api|worker|frontend|backend|database|cache|scheduler|gateway)$
  description: Componente arquitetural
  exemplo: api

app.kubernetes.io/part-of:
  regex: ^[a-z0-9-]+-[a-z0-9-]+$
  max_length: 63
  description: Sistema ao qual pertence (Backstage System)
  exemplo: integration-ipaas

app.kubernetes.io/managed-by:
  regex: ^(helm|argocd|terraform|kubectl)$
  description: Ferramenta de gestão
  exemplo: helm
```

**Governança Corporativa Labels** (todas obrigatórias):

```yaml
environment:
  regex: ^(dev|staging|prod)$
  description: Ambiente de execução
  exemplo: staging

domain:
  regex: ^(platform|integration|data|operations|shared-services)$
  description: Domínio corporativo
  exemplo: integration

owner:
  regex: ^[a-z0-9-]+-team$
  max_length: 63
  description: Time responsável (Backstage ownership)
  exemplo: integration-team

cost-center:
  regex: ^[a-z0-9-]+$
  max_length: 63
  description: Centro de custo (FinOps)
  exemplo: engineering

product:
  regex: ^[a-z0-9-]+$
  max_length: 63
  description: Produto dentro do domínio
  exemplo: ipaas
```

**Validação**:
```bash
./scripts/governance/validate-labels.sh <namespace>
```

**Exemplo Completo**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ipaas-bff-rest
  namespace: staging-integration-ipaas
  labels:
    # CNCF Recommended
    app.kubernetes.io/name: ipaas-bff-rest
    app.kubernetes.io/instance: staging-ipaas-bff-rest
    app.kubernetes.io/version: "1.2.0"
    app.kubernetes.io/component: api
    app.kubernetes.io/part-of: integration-ipaas
    app.kubernetes.io/managed-by: helm

    # Governança Corporativa
    environment: staging
    domain: integration
    owner: integration-team
    cost-center: engineering
    product: ipaas
```

---

### Backstage Entities

**Domain**:
```yaml
metadata.name:
  regex: ^(platform|integration|data|operations|shared-services)$
  exemplo: integration
```

**System**:
```yaml
metadata.name:
  regex: ^[a-z0-9-]+-[a-z0-9-]+$
  max_length: 63
  exemplo: integration-ipaas
```

**Component**:
```yaml
metadata.name:
  regex: ^[a-z0-9-]+$
  max_length: 63
  exemplo: ipaas-bff-rest
```

**Owner**:
```yaml
spec.owner:
  regex: ^[a-z0-9-]+-team$
  exemplo: integration-team
```

**Validação**:
```bash
./scripts/governance/validate-backstage.sh catalog-info.yaml
```

---

## 🔐 RBAC (Role-Based Access Control)

**Referência**: [ADR-049: Governança e RBAC](../adr/adr-049-governanca-rbac-dominios-corporativos.md)

### GitLab RBAC

**Princípio**: Cada time tem **Maintainer** no seu domínio, **Reporter** nos demais

**Níveis de Acesso GitLab**:
- **Owner**: Full control (você no Marco 0, CTO no futuro)
- **Maintainer**: Merge, deploy, manage repo (futuros tech leads)
- **Developer**: Push, create MR (futuros desenvolvedores)
- **Reporter**: Read-only, create issues (futuros QA, suporte)

**Matriz de RBAC GitLab**:

| GitLab Group | platform-team | integration-team | data-team | operations-team | shared-services-team |
|--------------|---------------|------------------|-----------|-----------------|----------------------|
| **corporate-domains/platform** | Maintainer | Reporter | Reporter | Reporter | Reporter |
| **corporate-domains/integration** | Reporter | Maintainer | Reporter | Reporter | Reporter |
| **corporate-domains/data** | Reporter | Reporter | Maintainer | Reporter | Reporter |
| **corporate-domains/operations** | Reporter | Reporter | Reporter | Maintainer | Reporter |
| **corporate-domains/shared-services** | Reporter | Reporter | Reporter | Reporter | Maintainer |

**Exceção**: platform-team tem Reporter em todos os domínios para troubleshooting de infraestrutura

**Referência Detalhada**: [rbac-matrix.md](./rbac-matrix.md)

---

### Kubernetes RBAC

**Princípio**: Cada time tem **namespace-admin** nos seus namespaces, **viewer** nos demais

**ClusterRoles**:
- `cluster-admin`: Full control do cluster (Platform Team apenas)
- `namespace-admin`: Admin de namespace específico (Tech Leads)
- `developer`: Deploy, debug, logs (Desenvolvedores)
- `viewer`: Read-only (QA, Support)

**Matriz de RBAC Kubernetes**:

| Namespace | platform-team | integration-team | data-team | operations-team | shared-services-team |
|-----------|---------------|------------------|-----------|-----------------|----------------------|
| **shared-observability** | namespace-admin | viewer | viewer | viewer | viewer |
| **staging-integration-ipaas** | viewer | namespace-admin | viewer | viewer | viewer |
| **prod-integration-ipaas** | viewer | namespace-admin | viewer | viewer | viewer |
| **staging-data-hatch** | viewer | viewer | namespace-admin | viewer | viewer |
| **prod-data-hatch** | viewer | viewer | namespace-admin | viewer | viewer |
| **staging-shared-files** | viewer | viewer | viewer | viewer | namespace-admin |
| **prod-shared-files** | viewer | viewer | viewer | viewer | namespace-admin |

**Referência Detalhada**: [rbac-matrix.md](./rbac-matrix.md)

---

## 📋 Processos de Governança

### Processo 1: Criação de Novo Domínio Corporativo

**Quando?**
- Nova linha de negócio estratégica (ex: "Compliance", "Customer Success")
- Aplicação não se encaixa nos 5 domínios existentes
- Volume de aplicações justifica segregação (>10 apps)

**Processo**:

#### Etapa 1: RFC (Request for Comments)
- **Responsável**: Tech Lead proposto para novo domínio
- **Ação**: Criar Issue no GitLab com template:

```markdown
## [RFC] Novo Domínio: {nome}

### Justificativa
Por que criar novo domínio ao invés de usar existente?

### Escopo
Quais aplicações/produtos farão parte?

### Ownership
Quem será responsável? (time existente ou novo time?)

### Impacto
Mudanças necessárias em infra, RBAC, naming conventions?

### Alternativas Consideradas
Por que não usar domínios existentes (Platform, Integration, Data, Operations, Shared Services)?
```

#### Etapa 2: Mesa Técnica
- **Participantes**: Platform Team + Domain Leads
- **Validações**:
  - Necessidade real (não pode encaixar em domínio existente?)
  - Impacto em infra (novos namespaces, RBAC, quotas)
  - Naming conventions (não conflita com existentes?)
  - Custo projetado (infra + pessoas)

#### Etapa 3: Aprovação
- **Aprovadores**: Platform Team + CTO
- **Registro**: Aprovação como comentário no Issue

#### Etapa 4: Implementação

**GitLab**:
```bash
# Criar subgrupo
gitlab group create --parent-id <corporate-domains-id> --name "{novo-dominio}" --path "{novo-dominio}"

# Criar grupo de time
gitlab group create --name "{novo-dominio}-team" --path "{novo-dominio}-team"

# Adicionar Owner (você no Marco 0)
gitlab group member add --user-id <your-id> --access-level owner --group-id <group-id>

# Configurar RBAC: Maintainer no subgrupo
gitlab group share --group-id <novo-dominio-id> --shared-group-id <novo-dominio-team-id> --access-level maintainer
```

**Kubernetes**:
```bash
# Criar namespaces
kubectl create namespace staging-{novo-dominio}-{produto}
kubectl create namespace prod-{novo-dominio}-{produto}

# Aplicar ResourceQuotas
kubectl apply -f resourcequota-staging.yaml -n staging-{novo-dominio}-{produto}
kubectl apply -f resourcequota-prod.yaml -n prod-{novo-dominio}-{produto}

# Aplicar NetworkPolicies
kubectl apply -f networkpolicy-default-deny.yaml -n staging-{novo-dominio}-{produto}
kubectl apply -f networkpolicy-allow-ingress.yaml -n staging-{novo-dominio}-{produto}

# Criar RoleBindings
kubectl apply -f rolebinding-{novo-dominio}-team-admin.yaml -n staging-{novo-dominio}-{produto}
kubectl apply -f rolebinding-cross-team-viewer.yaml -n staging-{novo-dominio}-{produto}
```

**Backstage**:
```yaml
# Criar catalog-info.yaml
apiVersion: backstage.io/v1alpha1
kind: Domain
metadata:
  name: {novo-dominio}
  description: Descrição do novo domínio
spec:
  owner: {novo-dominio}-team

---
apiVersion: backstage.io/v1alpha1
kind: Group
metadata:
  name: {novo-dominio}-team
spec:
  type: team
  profile:
    displayName: {Novo Dominio} Team
  children: []
```

#### Etapa 5: Documentação
- Criar ADR em `/docs/adr/` (ex: ADR-050)
- Atualizar ADR-047 (adicionar novo domínio)
- Criar README.md em `/corporate-domains/{novo-dominio}/`
- Atualizar este documento (GOVERNANCE.md)

#### Etapa 6: Comunicação
- Anunciar criação (Slack, email)
- Treinamento para time sobre governança

**Aprovadores**: Platform Team (infra) + CTO (estratégia)

---

### Processo 2: Criação de Novo Produto

**Quando?**
- Nova aplicação dentro de domínio existente
- Novo microserviço dentro de sistema existente

**Processo**:

#### Etapa 1: Decisão do Tech Lead
- Tech Lead do domínio decide (sem RFC, decisão interna)

#### Etapa 2: Estrutura GitLab
```bash
# Criar repo
gitlab project create --name "{novo-produto}" --namespace-id <dominio-id> --path "{novo-produto}"

# Se necessário, criar repo GitOps
gitlab project create --name "{novo-produto}-gitops" --namespace-id <dominio-id> --path "{novo-produto}-gitops"
```

#### Etapa 3: Estrutura Kubernetes
- **Decidir**: Novo namespace ou compartilhado?
  - **Novo namespace**: Se produto tem infra própria (database, cache)
  - **Namespace compartilhado**: Se é microserviço de sistema existente

```bash
# Se novo namespace
kubectl create namespace staging-{dominio}-{novo-produto}
kubectl apply -f resourcequota.yaml -n staging-{dominio}-{novo-produto}
kubectl apply -f networkpolicy.yaml -n staging-{dominio}-{novo-produto}

# Aplicar labels obrigatórias (validar via Kyverno)
```

#### Etapa 4: Backstage
```yaml
# Criar catalog-info.yaml
apiVersion: backstage.io/v1alpha1
kind: System  # ou Component, dependendo
metadata:
  name: {dominio}-{novo-produto}
spec:
  owner: {dominio}-team
  domain: {dominio}
```

#### Etapa 5: CI/CD
- Configurar `.gitlab-ci.yml`
- Criar ArgoCD Application (se GitOps)

**Aprovadores**: Tech Lead do domínio (decisão interna)

---

### Processo 3: Onboarding de Aplicação

**Referência Detalhada**: [application-onboarding.md](./application-onboarding.md)

**Processo Resumido**:

#### Etapa 1: Pré-Onboarding
```markdown
Checklist:
- [ ] Aplicação enquadrada em domínio (Integration, Data, Operations, Shared Services)
- [ ] Dockerfile criado e testado
- [ ] Helm chart criado (ou usar chart library)
- [ ] Secrets identificados (mover para Vault)
- [ ] Dependencies mapeadas (PostgreSQL, Redis, S3, etc)
- [ ] Naming conventions validadas (ADR-048)
```

#### Etapa 2: Staging Deployment
- Deploy em `staging-{dominio}-{produto}`
- Testes funcionais, integração, performance
- Validação de logs, métricas, traces

#### Etapa 3: Production Deployment
- Deploy em `prod-{dominio}-{produto}`
- Blue-Green ou Canary deployment
- Monitoramento pós-deploy (24h)

#### Etapa 4: Backstage Registration
- Criar `catalog-info.yaml`
- Registrar no Backstage catalog

#### Etapa 5: Documentação
- README.md no repo
- Runbook em `/docs/runbooks/`

**Aprovadores**:
- Tech Lead do domínio (staging)
- Platform Team + Tech Lead (produção)

---

### Processo 4: Exceções à Governança

**Quando?**
- Naming convention não se aplica (caso edge)
- RBAC precisa ser violado temporariamente (troubleshooting urgente)
- Label obrigatória não pode ser aplicada (limitação técnica)

**Processo**:

#### Etapa 1: Request
- Criar Issue no GitLab: `[Exception Request] {motivo}`

```markdown
## [Exception Request] {violação}

### Violação
Qual regra de governança será violada?

### Justificativa Técnica
Por que não é possível seguir a regra?

### Impacto
Qual o risco/impacto da exceção?

### Prazo
Por quanto tempo? (máx 90 dias)

### Plano de Correção
Como e quando a exceção será removida?
```

#### Etapa 2: Aprovação
- **Aprovadores**: Platform Team (infra) + CTO (se impacto alto)
- Aprovação registrada como comentário

#### Etapa 3: Implementação
```yaml
# Adicionar label governance-exception
labels:
  governance-exception: "true"
  governance-exception-issue: "https://gitlab.company.com/issues/123"
  governance-exception-expires: "2026-05-09"  # Data expiração
```

#### Etapa 4: Monitoramento
```bash
# Script semanal lista exceções
kubectl get all -A -l governance-exception=true -o yaml

# Notificar Platform Team de exceções próximas ao vencimento
```

#### Etapa 5: Expiração
- Após prazo: remover label `governance-exception`
- CI/CD validation bloqueia próximo deploy
- Tech Lead forçado a corrigir conformidade

**Aprovadores**: Platform Team + CTO (se impacto alto)

---

## 🚨 Enforcement (Validação Automática)

### GitLab: Pre-Push Hook

**Localização**: `.git/hooks/pre-push` ou CI/CD pipeline

```bash
#!/bin/bash
# Pre-push hook para validar naming conventions

REPO_PATH=$(git remote get-url origin | sed 's/.*:\(.*\)\.git/\1/')
EXPECTED_REGEX="^(corporate-domains)/(platform|integration|data|operations|shared-services)/[a-z0-9-]+(/[a-z0-9-]+)*$"

if [[ ! "$REPO_PATH" =~ $EXPECTED_REGEX ]]; then
  echo "❌ PUSH BLOQUEADO: Naming convention violada (ADR-048)"
  echo "Esperado: corporate-domains/{domain}/{product}"
  echo "Recebido: $REPO_PATH"
  echo "Ver documentação: /docs/governance/naming-conventions.md"
  exit 1
fi

echo "✅ Naming convention OK"
```

**Ativar hook**:
```bash
cp scripts/governance/pre-push-hook.sh .git/hooks/pre-push
chmod +x .git/hooks/pre-push
```

---

### Kubernetes: Kyverno Policies

**Localização**: `/domains/security/infra/kyverno/policies/`

**Política 1: Validar Labels Obrigatórias**

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-corporate-labels
spec:
  validationFailureAction: enforce         # Bloqueia recursos não conformes
  background: true
  rules:
  - name: check-labels
    match:
      any:
      - resources:
          kinds:
          - Pod
          - Deployment
          - StatefulSet
          - DaemonSet
          namespaces:
          - "staging-*"
          - "prod-*"
    validate:
      message: "❌ Labels obrigatórias faltando: domain, owner, environment (ADR-048)"
      pattern:
        metadata:
          labels:
            domain: "platform | integration | data | operations | shared-services"
            owner: "*-team"
            environment: "dev | staging | prod"
            app.kubernetes.io/name: "?*"
            app.kubernetes.io/part-of: "?*"
```

**Política 2: Validar Namespace Naming**

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: validate-namespace-naming
spec:
  validationFailureAction: enforce
  rules:
  - name: check-namespace-name
    match:
      any:
      - resources:
          kinds:
          - Namespace
    validate:
      message: "❌ Namespace naming violado (ADR-048). Esperado: {env}-{domain}-{product}"
      pattern:
        metadata:
          name: "(dev|staging|prod|shared)-(platform|integration|data|operations|shared)-?*"
```

**Deploy Kyverno Policies**:
```bash
kubectl apply -f /domains/security/infra/kyverno/policies/require-corporate-labels.yaml
kubectl apply -f /domains/security/infra/kyverno/policies/validate-namespace-naming.yaml
```

**Referência Detalhada**: [validation-rules.yaml](./validation-rules.yaml)

---

### Backstage: CI/CD Validation

**Localização**: `.gitlab-ci.yml`

```yaml
stages:
  - validate
  - build
  - deploy

validate-catalog:
  stage: validate
  script:
    - echo "Validando catalog-info.yaml..."
    - /scripts/governance/validate-backstage.sh catalog-info.yaml
  rules:
    - if: '$CI_MERGE_REQUEST_TARGET_BRANCH_NAME == "main"'
      changes:
        - catalog-info.yaml

validate-naming:
  stage: validate
  script:
    - echo "Validando naming conventions..."
    - /scripts/governance/validate-naming.sh $CI_PROJECT_PATH
  rules:
    - if: '$CI_MERGE_REQUEST_TARGET_BRANCH_NAME == "main"'

validate-labels:
  stage: validate
  script:
    - echo "Validando labels Kubernetes..."
    - /scripts/governance/validate-labels.sh $CI_PROJECT_PATH
  rules:
    - if: '$CI_MERGE_REQUEST_TARGET_BRANCH_NAME == "main"'
      changes:
        - "infra/kubernetes/**/*"
        - "helm/**/*"
```

---

## 📊 Auditoria e Compliance

### Auditoria Mensal

**Executar todo dia 1º do mês**:

```bash
# 1. Auditoria de RBAC
./scripts/governance/audit-rbac.sh | tee /logs/audit-rbac-$(date +%Y-%m).txt

# 2. Auditoria de Labels
./scripts/governance/audit-labels.sh | tee /logs/audit-labels-$(date +%Y-%m).txt

# 3. Auditoria de Naming Conventions
./scripts/governance/audit-naming.sh | tee /logs/audit-naming-$(date +%Y-%m).txt

# 4. Auditoria de Exceções
./scripts/governance/audit-exceptions.sh | tee /logs/audit-exceptions-$(date +%Y-%m).txt
```

**Métricas de Conformidade**:
- % de namespaces com naming correto
- % de recursos com labels obrigatórias
- Número de exceções ativas
- Número de exceções expiradas (ação necessária)

**Target**: 100% de conformidade (0 violações)

---

## 💰 FinOps (Cost Allocation)

### Resource Quotas por Namespace

**Staging** (conservador):
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: staging-quota
spec:
  hard:
    requests.cpu: "8"
    requests.memory: 16Gi
    limits.cpu: "16"
    limits.memory: 32Gi
    persistentvolumeclaims: "10"
    services.loadbalancers: "2"
    pods: "100"
```

**Production** (generoso):
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: prod-quota
spec:
  hard:
    requests.cpu: "32"
    requests.memory: 64Gi
    limits.cpu: "64"
    limits.memory: 128Gi
    persistentvolumeclaims: "20"
    services.loadbalancers: "5"
    pods: "200"
```

### Cost Allocation Labels

**Labels para Chargeback**:
```yaml
labels:
  cost-center: engineering                 # Centro de custo
  domain: integration                      # Domínio corporativo (chargeback)
  owner: integration-team                  # Time responsável (chargeback)
  environment: prod                        # Ambiente (prod > staging)
  product: ipaas                           # Produto (chargeback por produto)
```

**Kubecost Queries**:
```bash
# Custo por domínio corporativo
kubecost cost --label domain --window 30d

# Custo por time (owner)
kubecost cost --label owner --window 30d

# Custo por produto
kubecost cost --label product --window 30d

# Custo por ambiente
kubecost cost --label environment --window 30d
```

---

## 📚 Referências

### ADRs
- [ADR-047: Estrutura Corporativa de Domínios de Negócio](../adr/adr-047-estrutura-corporativa-dominios.md)
- [ADR-048: Naming Conventions Determinísticas](../adr/adr-048-naming-conventions-deterministicas.md)
- [ADR-049: Governança e RBAC para Domínios Corporativos](../adr/adr-049-governanca-rbac-dominios-corporativos.md)

### Documentos de Governança
- [Naming Conventions (Detalhado)](./naming-conventions.md)
- [RBAC Matrix](./rbac-matrix.md)
- [Validation Rules (Kyverno/OPA)](./validation-rules.yaml)
- [Backstage Standards](./backstage-standards.md)
- [Application Onboarding Guide](./application-onboarding.md)

### Scripts de Validação
- `/scripts/governance/validate-naming.sh`
- `/scripts/governance/validate-labels.sh`
- `/scripts/governance/validate-rbac.sh`
- `/scripts/governance/validate-backstage.sh`

### Scripts de Auditoria
- `/scripts/governance/audit-rbac.sh`
- `/scripts/governance/audit-labels.sh`
- `/scripts/governance/audit-naming.sh`
- `/scripts/governance/audit-exceptions.sh`

---

## ✅ Aprovações

- [x] Usuário (gilvangalindo) - 2026-02-09
- [ ] Platform Team (quando formado)
- [ ] CTO (estratégia)

---

## 📝 Changelog

### v1.0 (2026-02-09)
- Criação inicial do documento de governança
- Definição de 5 domínios corporativos
- Naming conventions determinísticas com regex
- Processos de criação de domínios, produtos, aplicações
- Enforcement via Kyverno, pre-push hooks, CI/CD
- Auditoria mensal automatizada
