# ADR 049 — Governança e RBAC para Domínios Corporativos

## Data
2026-02-09

## Status
Proposto 📋

## Contexto

Com a definição de **5 domínios corporativos** (ADR-047) e **naming conventions determinísticas** (ADR-048), precisamos estabelecer:
1. **RBAC (Role-Based Access Control)** consistente entre GitLab e Kubernetes
2. **Processos de governança** para criação de domínios, produtos e aplicações
3. **Enforcement** automático via tooling (Kyverno, OPA, pre-push hooks)
4. **Auditoria** e compliance

**Problema Atual**:
- Marco 0: Sem times estruturados (1 pessoa operando)
- Futuro: Times organizados por domínios corporativos (Platform Team, Integration Team, Data Team, Operations Team, Shared Services Team)
- Necessidade: Estruturar RBAC e governança **desde o início**, mesmo sem times formados

**Filosofia**: "Se começar certo, quando grande já está certo"
- Definir RBAC como se times existissem (hoje você é Owner de todos os grupos)
- Preparar processos de aprovação e onboarding para futura delegação
- Enforcement desde Marco 0 para criar cultura de compliance

## Problema

Como garantir governança e controle de acesso em ambientes GitLab e Kubernetes para:
1. **RBAC consistente**: GitLab Groups ↔ Kubernetes RBAC ↔ Backstage Teams
2. **Ownership claro**: Cada domínio tem um time responsável
3. **Processos definidos**: Criação de domínios, produtos, aplicações, exceções
4. **Enforcement automático**: Validação de RBAC, labels, naming conventions
5. **Auditoria**: Rastreabilidade de mudanças por domínio
6. **Escalabilidade**: Suportar crescimento de 1 pessoa → 50+ pessoas sem refatoração

## Decisões

### 1. Estrutura de Times por Domínio Corporativo

#### 1.1 Definição de Times

**5 Times Corporativos** (mesmo sem membros hoje, estruturar GitLab Groups):

```yaml
platform-team:
  description: Time de Platform Engineering (SRE, DevOps, Infra)
  responsibilities:
    - Infraestrutura AWS EKS (Terraform)
    - Observabilidade (Prometheus, Grafana, Loki, Tempo)
    - CI/CD (GitLab, ArgoCD, SonarQube)
    - Secrets Management (Vault)
    - Security (Kyverno, Falco, Network Policies)
  domains_owned:
    - platform (Camada 1: Domínios Técnicos)
  members_marco_0:
    - você@company.com (Owner)       # Hoje: só você
  members_futuro:
    - +3-5 pessoas (SRE, Platform Engineers)

integration-team:
  description: Time de Integrações (Backend, Integration Specialists)
  responsibilities:
    - iPaaS (9 microserviços Go/.NET)
    - Integrações SaaS
    - APIs de integração (REST, gRPC, SOAP)
    - Orquestração de workflows
  domains_owned:
    - integration (iPaaS)
  members_marco_0:
    - você@company.com (Owner)       # Hoje: só você
  members_futuro:
    - +4-6 pessoas (Backend Engineers, Integration Specialists)

data-team:
  description: Time de Dados (Data Engineers, Analytics Engineers)
  responsibilities:
    - ETL Hatch (151 extractors, API Gateway, Web UI)
    - ETL VemSoft
    - Data Platform (catálogo, qualidade, governança)
    - Data Warehouse, Analytics
  domains_owned:
    - data (Hatch, VemSoft, Data Platform)
  members_marco_0:
    - você@company.com (Owner)       # Hoje: só você
  members_futuro:
    - +3-5 pessoas (Data Engineers, Analytics Engineers)

operations-team:
  description: Time de Operações (Product Managers, Ops Engineers, Business Analysts)
  responsibilities:
    - Process Management (orquestração de processos)
    - Fulfillment (execução de tarefas)
    - Monitoring Operacional (dashboards, alertas)
  domains_owned:
    - operations (Process, Fulfillment, Monitoring)
  members_marco_0:
    - você@company.com (Owner)       # Hoje: só você
  members_futuro:
    - +5-8 pessoas (Product Managers, Ops Engineers, Business Analysts)

shared-services-team:
  description: Time de Serviços Compartilhados (Fullstack, DevOps)
  responsibilities:
    - Files (BucketConnector, Generators Word/PDF/Excel/CSV)
    - Notification (Email/Slack/Teams)
    - Calendar (API, Feriados, Integrações)
    - Automation (RPA Platform)
  domains_owned:
    - shared-services (Files, Notification, Calendar, Automation)
  members_marco_0:
    - você@company.com (Owner)       # Hoje: só você
  members_futuro:
    - +2-4 pessoas (Fullstack Engineers, DevOps)
```

---

### 2. RBAC GitLab

#### 2.1 Níveis de Acesso GitLab

```yaml
Owner:
  description: Full control do grupo/repo
  permissions:
    - Manage members, settings, projects
    - Delete group/repo
    - Change visibility
  assigned_to:
    - Você (Marco 0)
    - CTO, Architect (futuro)

Maintainer:
  description: Gerenciamento de repositório e merge
  permissions:
    - Push to protected branches
    - Merge pull requests
    - Manage CI/CD pipelines
    - Deploy to environments
  assigned_to:
    - Tech Leads de cada domínio (futuro)

Developer:
  description: Desenvolvimento e criação de MRs
  permissions:
    - Push to non-protected branches
    - Create merge requests
    - Run CI/CD pipelines
    - View environments
  assigned_to:
    - Desenvolvedores de cada domínio (futuro)

Reporter:
  description: Read-only + create issues
  permissions:
    - View code, issues, merge requests
    - Create issues
    - Comment
  assigned_to:
    - QA, Support, outros times (read-only cross-domain)

Guest:
  description: View-only
  permissions:
    - View issues (if public)
  assigned_to:
    - Stakeholders, Management
```

#### 2.2 Matriz de RBAC GitLab por Domínio

**Princípio**: Cada time tem **Maintainer** no seu domínio, **Reporter** nos demais (troubleshooting cross-domain)

| GitLab Group | platform-team | integration-team | data-team | operations-team | shared-services-team |
|--------------|---------------|------------------|-----------|-----------------|----------------------|
| **corporate-domains/platform** | Maintainer | Reporter | Reporter | Reporter | Reporter |
| **corporate-domains/integration** | Reporter | Maintainer | Reporter | Reporter | Reporter |
| **corporate-domains/data** | Reporter | Reporter | Maintainer | Reporter | Reporter |
| **corporate-domains/operations** | Reporter | Reporter | Reporter | Maintainer | Reporter |
| **corporate-domains/shared-services** | Reporter | Reporter | Reporter | Reporter | Maintainer |

**Exceção: platform-team**:
- Tem **Reporter** (read-only) em todos os domínios corporativos para troubleshooting de plataforma
- **NÃO tem Maintainer** em domínios corporativos (respeita ownership)

**Justificativa**:
- **Ownership por domínio**: Cada time tem full control do seu domínio
- **Transparência**: Todos os times podem ver código de outros domínios (troubleshooting, learning)
- **Segregation of Duties**: Ninguém faz merge fora do seu domínio (compliance)

#### 2.3 Criação de Grupos GitLab

**Estrutura no Marco 0** (você como Owner de todos):

```bash
# Criar grupos raiz
gitlab group create --name "corporate-domains" --path "corporate-domains"

# Criar subgrupos por domínio
gitlab group create --parent-id <corporate-domains-id> --name "platform" --path "platform"
gitlab group create --parent-id <corporate-domains-id> --name "integration" --path "integration"
gitlab group create --parent-id <corporate-domains-id> --name "data" --path "data"
gitlab group create --parent-id <corporate-domains-id> --name "operations" --path "operations"
gitlab group create --parent-id <corporate-domains-id> --name "shared-services" --path "shared-services"

# Criar grupos de times (vazio no Marco 0, popular no futuro)
gitlab group create --name "platform-team" --path "platform-team"
gitlab group create --name "integration-team" --path "integration-team"
gitlab group create --name "data-team" --path "data-team"
gitlab group create --name "operations-team" --path "operations-team"
gitlab group create --name "shared-services-team" --path "shared-services-team"

# Adicionar você como Owner de todos (Marco 0)
gitlab group member add --user-id <your-user-id> --access-level owner --group-id <group-id>
```

**No Futuro** (quando contratar):

```bash
# Adicionar membros aos times
gitlab group member add --user-id <developer-id> --access-level developer --group-id <integration-team-id>
gitlab group member add --user-id <tech-lead-id> --access-level maintainer --group-id <integration-team-id>

# Adicionar time inteiro com permissões no domínio
gitlab group share --group-id <integration-id> --shared-group-id <integration-team-id> --access-level maintainer
```

---

### 3. RBAC Kubernetes

#### 3.1 Níveis de Acesso Kubernetes

**ClusterRoles** (definidos centralmente):

```yaml
cluster-admin:
  description: Full control do cluster
  permissions:
    - * (all verbs, all resources)
  assigned_to:
    - platform-team (você no Marco 0)

namespace-admin:
  description: Admin de namespace específico
  permissions:
    - get, list, watch, create, update, patch, delete (all resources no namespace)
  assigned_to:
    - Tech Leads de cada domínio (futuros)

developer:
  description: Deploy, debug, logs no namespace
  permissions:
    - get, list, watch (all resources)
    - create, update, patch, delete (Deployments, Services, ConfigMaps)
    - logs, exec (Pods)
  assigned_to:
    - Desenvolvedores de cada domínio (futuros)

viewer:
  description: Read-only no namespace
  permissions:
    - get, list, watch (all resources)
  assigned_to:
    - QA, Support, Management
```

#### 3.2 Matriz de RBAC Kubernetes por Namespace

**Princípio**: Cada time tem **namespace-admin** nos seus namespaces, **viewer** nos demais (troubleshooting)

| Namespace | platform-team | integration-team | data-team | operations-team | shared-services-team |
|-----------|---------------|------------------|-----------|-----------------|----------------------|
| **shared-observability** | namespace-admin | viewer | viewer | viewer | viewer |
| **staging-platform-cicd** | namespace-admin | viewer | viewer | viewer | viewer |
| **prod-platform-cicd** | namespace-admin | viewer | viewer | viewer | viewer |
| **staging-integration-ipaas** | viewer | namespace-admin | viewer | viewer | viewer |
| **prod-integration-ipaas** | viewer | namespace-admin | viewer | viewer | viewer |
| **staging-data-hatch** | viewer | viewer | namespace-admin | viewer | viewer |
| **prod-data-hatch** | viewer | viewer | namespace-admin | viewer | viewer |
| **staging-operations-process** | viewer | viewer | viewer | namespace-admin | viewer |
| **prod-operations-process** | viewer | viewer | viewer | namespace-admin | viewer |
| **staging-shared-files** | viewer | viewer | viewer | viewer | namespace-admin |
| **prod-shared-files** | viewer | viewer | viewer | viewer | namespace-admin |

**Exceção: platform-team**:
- **cluster-admin**: Full control do cluster (provisionamento, upgrades, troubleshooting crítico)
- **namespace-admin** nos namespaces de plataforma (`shared-observability`, `*-platform-*`)
- **viewer** nos namespaces corporativos (troubleshooting de infra, não de aplicação)

#### 3.3 Implementação RBAC Kubernetes

**Namespace com Labels** (facilita RBAC via label selectors):

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: staging-integration-ipaas
  labels:
    name: staging-integration-ipaas
    environment: staging
    domain: integration
    owner: integration-team
    cost-center: engineering
```

**RoleBinding** (namespace-admin para integration-team):

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: integration-team-admin
  namespace: staging-integration-ipaas
subjects:
- kind: Group
  name: integration-team                    # GitLab Group espelhado via OIDC
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: namespace-admin
  apiGroup: rbac.authorization.k8s.io
```

**RoleBinding** (viewer para outros times):

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: cross-team-viewer
  namespace: staging-integration-ipaas
subjects:
- kind: Group
  name: platform-team
  apiGroup: rbac.authorization.k8s.io
- kind: Group
  name: data-team
  apiGroup: rbac.authorization.k8s.io
- kind: Group
  name: operations-team
  apiGroup: rbac.authorization.k8s.io
- kind: Group
  name: shared-services-team
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: viewer
  apiGroup: rbac.authorization.k8s.io
```

**ClusterRoleBinding** (cluster-admin para platform-team):

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: platform-team-cluster-admin
subjects:
- kind: Group
  name: platform-team
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
```

#### 3.4 Integração GitLab ↔ Kubernetes via OIDC

**Keycloak como Identity Provider** (Fase 2):

```yaml
Keycloak:
  realm: company-realm
  clients:
    - gitlab (OIDC client)
    - kubernetes (OIDC client)
  groups:
    - platform-team
    - integration-team
    - data-team
    - operations-team
    - shared-services-team

GitLab → Keycloak:
  - GitLab Groups espelhados em Keycloak Groups
  - SSO para GitLab via Keycloak

Kubernetes → Keycloak:
  - kube-apiserver configurado com OIDC
  - Groups mapeados para Kubernetes Groups
  - RoleBindings referenciam Keycloak Groups
```

**Configuração kube-apiserver** (EKS):

```yaml
apiServer:
  oidc:
    issuerURL: https://keycloak.company.com/realms/company-realm
    clientID: kubernetes
    usernameClaim: preferred_username
    groupsClaim: groups
    groupsPrefix: "keycloak:"
```

**RoleBinding com Keycloak Groups**:

```yaml
subjects:
- kind: Group
  name: keycloak:integration-team           # Prefixo "keycloak:"
  apiGroup: rbac.authorization.k8s.io
```

---

### 4. Backstage Teams (Fase 4)

**Estrutura Backstage**:

```yaml
apiVersion: backstage.io/v1alpha1
kind: Group
metadata:
  name: integration-team
  description: Time de Integrações (iPaaS)
spec:
  type: team
  profile:
    displayName: Integration Team
    email: integration-team@company.com
  parent: engineering                       # Parent group
  children: []

---
apiVersion: backstage.io/v1alpha1
kind: User
metadata:
  name: gilvan.galindo
spec:
  profile:
    displayName: Gilvan Galindo
    email: gilvan.galindo@company.com
  memberOf:
    - platform-team
    - integration-team
    - data-team
    - operations-team
    - shared-services-team                 # Marco 0: você em todos os times
```

**Ownership no Backstage**:

```yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: ipaas-bff-rest
spec:
  type: service
  owner: integration-team                   # Backstage team ownership
  system: integration-ipaas
```

---

### 5. Processos de Governança

#### 5.1 Processo de Criação de Novo Domínio Corporativo

**Quando?**
- Nova linha de negócio estratégica (ex: "Compliance", "Customer Success")
- Aplicação não se encaixa nos 5 domínios existentes
- Volume de aplicações justifica segregação (>10 apps)

**Processo**:

1. **RFC (Request for Comments)**:
   - Tech Lead cria Issue no GitLab: `[RFC] Novo Domínio: {nome}`
   - Template RFC:
     ```markdown
     ## Justificativa
     Por que criar novo domínio ao invés de usar existente?

     ## Escopo
     Quais aplicações/produtos farão parte?

     ## Ownership
     Quem será responsável? (time existente ou novo time?)

     ## Impacto
     Mudanças necessárias em infra, RBAC, naming conventions?

     ## Alternativas Consideradas
     Por que não usar domínios existentes?
     ```

2. **Mesa Técnica**:
   - Platform Team + Domain Leads avaliam RFC
   - Validam:
     - Necessidade real (não é possível encaixar em domínio existente?)
     - Impacto em infra (novos namespaces, RBAC, quotas)
     - Naming conventions (não conflita com existentes?)

3. **Aprovação**:
   - Platform Team + CTO aprovam RFC
   - Aprovação registrada como comentário no Issue

4. **Implementação**:
   - **GitLab**:
     - Criar subgrupo: `/corporate-domains/{novo-dominio}`
     - Criar grupo de time: `{novo-dominio}-team`
     - Configurar RBAC: Maintainer no subgrupo
   - **Kubernetes**:
     - Criar namespaces: `staging-{novo-dominio}-*`, `prod-{novo-dominio}-*`
     - Aplicar ResourceQuotas, NetworkPolicies
     - Criar RoleBindings (namespace-admin para novo time)
   - **Backstage**:
     - Criar `catalog-info.yaml` com `kind: Domain`
     - Criar `kind: Group` para novo time
     - Adicionar `owner: {novo-dominio}-team`

5. **Documentação**:
   - Criar ADR em `/docs/adr/` (ex: ADR-050)
   - Atualizar ADR-047 (adicionar novo domínio à lista)
   - Criar README.md em `/corporate-domains/{novo-dominio}/`
   - Atualizar `/docs/governance/GOVERNANCE.md`

6. **Comunicação**:
   - Anunciar criação de novo domínio (Slack, email)
   - Treinamento para time sobre governança

**Aprovadores**:
- Platform Team (infraestrutura)
- CTO (estratégia de negócio)

---

#### 5.2 Processo de Criação de Novo Produto

**Quando?**
- Nova aplicação dentro de domínio existente
- Novo microserviço dentro de sistema existente (ex: novo BFF no iPaaS)

**Processo**:

1. **Decisão do Tech Lead do Domínio**:
   - Tech Lead do domínio decide criar novo produto (sem RFC, decisão interna do time)

2. **Estrutura GitLab**:
   - Criar repo: `{dominio}/{novo-produto}`
   - Seguir naming conventions (ADR-048)
   - Criar repo GitOps: `{novo-produto}-gitops` (se necessário)

3. **Estrutura Kubernetes**:
   - Decidir se precisa novo namespace:
     - **Novo namespace**: Se produto tem infra própria (database, cache, etc)
     - **Namespace compartilhado**: Se é microserviço dentro de sistema existente
   - Aplicar labels obrigatórias (ADR-048)

4. **Backstage**:
   - Criar `catalog-info.yaml`:
     - `kind: System` (se novo sistema independente)
     - `kind: Component` (se microserviço de sistema existente)
   - Referenciar `domain: {dominio}`
   - Adicionar `owner: {dominio}-team`

5. **CI/CD**:
   - Configurar pipeline GitLab CI (`.gitlab-ci.yml`)
   - Criar ArgoCD Application (se GitOps)

**Aprovadores**:
- Tech Lead do domínio (decisão interna)

---

#### 5.3 Processo de Onboarding de Aplicação

**Quando?**
- Migração de aplicação legada (VMs, docker-compose) para Kubernetes
- Nova aplicação sendo criada

**Processo** (ver `/docs/governance/application-onboarding.md` detalhado):

1. **Checklist Pré-Onboarding**:
   ```markdown
   - [ ] Aplicação enquadrada em domínio corporativo (Integration, Data, Operations, Shared Services)
   - [ ] Dockerfile criado e testado
   - [ ] Helm chart criado (ou usar chart library)
   - [ ] Secrets identificados (mover para Vault)
   - [ ] Dependencies mapeadas (PostgreSQL, Redis, S3, etc)
   - [ ] Naming conventions validadas (ADR-048)
   ```

2. **Staging Deployment**:
   - Deploy em `staging-{dominio}-{produto}`
   - Testes funcionais, integração, performance
   - Validação de logs, métricas, traces (observabilidade)

3. **Production Deployment**:
   - Deploy em `prod-{dominio}-{produto}`
   - Blue-Green ou Canary deployment
   - Monitoramento pós-deploy (24h)

4. **Backstage Registration**:
   - Criar `catalog-info.yaml`
   - Registrar no Backstage catalog

5. **Documentação**:
   - README.md no repo
   - Runbook em `/docs/runbooks/`

**Aprovadores**:
- Tech Lead do domínio (staging)
- Platform Team + Tech Lead (produção)

---

#### 5.4 Processo de Exceções à Governança

**Quando?**
- Naming convention não se aplica (caso edge)
- RBAC precisa ser violado temporariamente (troubleshooting urgente)
- Label obrigatória não pode ser aplicada (limitação técnica)

**Processo**:

1. **Request**:
   - Criar Issue no GitLab: `[Exception Request] {motivo}`
   - Template:
     ```markdown
     ## Violação
     Qual regra de governança será violada?

     ## Justificativa Técnica
     Por que não é possível seguir a regra?

     ## Impacto
     Qual o risco/impacto da exceção?

     ## Prazo
     Por quanto tempo a exceção é necessária? (máx 90 dias)

     ## Plano de Correção
     Como e quando a exceção será removida?
     ```

2. **Aprovação**:
   - Platform Team aprova ou nega
   - Aprovação registrada como comentário no Issue

3. **Implementação**:
   - Adicionar label `governance-exception` no recurso:
     ```yaml
     labels:
       governance-exception: "true"
       governance-exception-issue: "https://gitlab.company.com/issues/123"
       governance-exception-expires: "2026-05-09"  # Data de expiração
     ```

4. **Monitoramento**:
   - Script semanal lista recursos com `governance-exception` label:
     ```bash
     kubectl get all -A -l governance-exception=true -o yaml
     ```
   - Notificar Platform Team de exceções próximas ao vencimento

5. **Expiração**:
   - Após prazo expirado:
     - Automaticamente remover label `governance-exception`
     - CI/CD validation bloqueia próximo deploy
     - Tech Lead forçado a corrigir conformidade

**Aprovadores**:
- Platform Team (infraestrutura)
- CTO (estratégia, se impacto alto)

---

### 6. Enforcement Automático

#### 6.1 GitLab: Pre-Push Hook

**Localização**: `.git/hooks/pre-push` (ou CI/CD pipeline)

```bash
#!/bin/bash
# Valida naming conventions antes de push

REPO_PATH=$(git remote get-url origin | sed 's/.*:\(.*\)\.git/\1/')
EXPECTED_REGEX="^(domains|corporate-domains)/[a-z0-9-]+(/[a-z0-9-]+)*$"

if [[ ! "$REPO_PATH" =~ $EXPECTED_REGEX ]]; then
  echo "❌ PUSH BLOQUEADO: Naming convention violada (ADR-048)"
  echo "Esperado: (domains|corporate-domains)/{domain}/{product}"
  echo "Recebido: $REPO_PATH"
  echo "Ver documentação: /docs/governance/naming-conventions.md"
  exit 1
fi

echo "✅ Naming convention OK"
```

#### 6.2 Kubernetes: Kyverno Policies

**Validar Labels Obrigatórias**:

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

**Validar Namespace Naming**:

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

**Validar RBAC (RoleBinding owner deve existir)**:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: validate-rolebinding-owner
spec:
  validationFailureAction: audit           # Apenas alerta, não bloqueia
  rules:
  - name: check-owner-label
    match:
      any:
      - resources:
          kinds:
          - RoleBinding
    validate:
      message: "⚠️ RoleBinding deve ter label 'owner' (ADR-049)"
      pattern:
        metadata:
          labels:
            owner: "*-team"
```

#### 6.3 Backstage: CI/CD Validation

**Pipeline GitLab CI** (`.gitlab-ci.yml`):

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

### 7. Auditoria e Compliance

#### 7.1 Auditoria de RBAC

**Script**: `/scripts/governance/audit-rbac.sh`

```bash
#!/bin/bash
# Auditoria de RBAC Kubernetes

echo "=== Auditoria de RBAC Kubernetes ==="

# 1. Listar ClusterRoleBindings com cluster-admin
echo "## ClusterRoleBindings com cluster-admin:"
kubectl get clusterrolebinding -o json | jq -r '
  .items[] |
  select(.roleRef.name == "cluster-admin") |
  "\(.metadata.name): \(.subjects[].name)"
'

# 2. Listar RoleBindings por namespace
echo "## RoleBindings por namespace (staging-integration-ipaas):"
kubectl get rolebinding -n staging-integration-ipaas -o json | jq -r '
  .items[] |
  "\(.metadata.name): \(.subjects[].name) -> \(.roleRef.name)"
'

# 3. Validar que cada namespace tem owner label
echo "## Namespaces sem owner label:"
kubectl get ns -o json | jq -r '
  .items[] |
  select(.metadata.labels.owner == null) |
  .metadata.name
'

# 4. Validar que RoleBindings referenciam grupos válidos
echo "## RoleBindings com grupos inválidos:"
kubectl get rolebinding -A -o json | jq -r '
  .items[] |
  select(.subjects[].name | test("^(platform|integration|data|operations|shared-services)-team$") | not) |
  "\(.metadata.namespace)/\(.metadata.name): \(.subjects[].name)"
'
```

**Executar mensalmente**:
```bash
./scripts/governance/audit-rbac.sh | tee /logs/audit-rbac-$(date +%Y-%m).txt
```

#### 7.2 Auditoria de Labels

**Script**: `/scripts/governance/audit-labels.sh`

```bash
#!/bin/bash
# Auditoria de labels obrigatórias

NAMESPACE="$1"

echo "=== Auditoria de Labels: $NAMESPACE ==="

# Listar Pods sem labels obrigatórias
kubectl get pods -n "$NAMESPACE" -o json | jq -r '
  .items[] |
  select(
    .metadata.labels.domain == null or
    .metadata.labels.owner == null or
    .metadata.labels.environment == null or
    .metadata.labels["app.kubernetes.io/name"] == null
  ) |
  .metadata.name
' | while read pod; do
  if [ -n "$pod" ]; then
    echo "❌ Pod sem labels obrigatórias: $pod"
  fi
done

echo "✅ Auditoria concluída"
```

#### 7.3 Auditoria de Naming Conventions

**Script**: `/scripts/governance/audit-naming.sh`

```bash
#!/bin/bash
# Auditoria de naming conventions

echo "=== Auditoria de Naming Conventions ==="

# 1. Namespaces com naming inválido
echo "## Namespaces com naming inválido:"
kubectl get ns -o json | jq -r '
  .items[] |
  select(.metadata.name | test("^(dev|staging|prod|shared)-(platform|integration|data|operations|shared)(-[a-z0-9-]+)?$") | not) |
  .metadata.name
'

# 2. Services com naming inválido (deve ser lowercase-kebab-case)
echo "## Services com naming inválido:"
kubectl get svc -A -o json | jq -r '
  .items[] |
  select(.metadata.name | test("^[a-z0-9-]+$") | not) |
  "\(.metadata.namespace)/\(.metadata.name)"
'

echo "✅ Auditoria concluída"
```

#### 7.4 Auditoria de Exceções

**Script**: `/scripts/governance/audit-exceptions.sh`

```bash
#!/bin/bash
# Auditoria de exceções à governança

echo "=== Auditoria de Exceções à Governança ==="

# 1. Listar recursos com label governance-exception
echo "## Recursos com governance-exception:"
kubectl get all -A -l governance-exception=true -o json | jq -r '
  .items[] |
  "\(.kind)/\(.metadata.name) (namespace: \(.metadata.namespace))"
  "\(.metadata.labels."governance-exception-issue")"
  "\(.metadata.labels."governance-exception-expires")"
  "---"
'

# 2. Verificar exceções expiradas
echo "## Exceções expiradas (ação necessária):"
kubectl get all -A -l governance-exception=true -o json | jq -r '
  .items[] |
  select(.metadata.labels."governance-exception-expires" < now | strftime("%Y-%m-%d")) |
  "\(.kind)/\(.metadata.name) (namespace: \(.metadata.namespace)) - EXPIRADO"
'

echo "✅ Auditoria concluída"
```

---

### 8. Métricas de Governança (FinOps)

#### 8.1 Resource Quotas por Namespace

**Staging** (conservador):
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: staging-quota
  namespace: staging-integration-ipaas
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
  namespace: prod-integration-ipaas
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

#### 8.2 Cost Allocation Labels

**Labels para FinOps**:
```yaml
labels:
  cost-center: engineering                 # Centro de custo
  domain: integration                      # Domínio corporativo (chargeback)
  owner: integration-team                  # Time responsável (chargeback)
  environment: prod                        # Ambiente (prod > staging em custo)
  product: ipaas                           # Produto (chargeback por produto)
```

**Kubecost Query**:
```bash
# Custo por domínio corporativo
kubecost cost --label domain --window 30d

# Custo por time (owner)
kubecost cost --label owner --window 30d

# Custo por produto
kubecost cost --label product --window 30d
```

---

## Alternativas Consideradas

### Alternativa 1: RBAC Flat (sem domínios, todos têm acesso a tudo)
**Rejeita**: Sem segregation of duties, alto risco de compliance, não escala

### Alternativa 2: RBAC por Namespace Apenas (sem GitLab Groups)
**Rejeita**: GitLab e Kubernetes não espelhados, confusão de ownership

### Alternativa 3: RBAC Manual (sem Keycloak/OIDC)
**Rejeita**: Não escala, difícil manter GitLab ↔ Kubernetes sincronizados

### Alternativa 4: RBAC por Domínio + OIDC + Enforcement (ESCOLHIDA)
**Aceita**:
- GitLab Groups ↔ Keycloak Groups ↔ Kubernetes RBAC (SSO)
- Enforcement via Kyverno, pre-push hooks, CI/CD
- Auditoria automatizada

---

## Consequências

### Positivas
✅ **RBAC consistente**: GitLab ↔ Kubernetes ↔ Backstage espelhados
✅ **Ownership claro**: Cada domínio tem time responsável
✅ **Enforcement automático**: Kyverno, pre-push hooks, CI/CD validation
✅ **Auditoria**: Scripts mensais de compliance
✅ **Escalabilidade**: Estrutura suporta 1 pessoa → 50+ pessoas
✅ **FinOps**: Labels para chargeback por domínio/time/produto
✅ **Compliance**: Segregation of duties, rastreabilidade de mudanças

### Negativas
⚠️ **Complexidade inicial**: Estrutura parece pesada para 1 pessoa no Marco 0
⚠️ **Overhead de processos**: RFC, aprovações, auditorias

### Riscos
🔴 **Risco**: RBAC muito restritivo impede troubleshooting urgente
🟢 **Mitigação**: Processo de exceção (governance-exception label, 90 dias)

🔴 **Risco**: Enforcement quebra workflows existentes
🟢 **Mitigação**: Implementação gradual (audit mode primeiro, enforce depois)

🔴 **Risco**: GitLab Groups ↔ Kubernetes RBAC dessincronizados
🟢 **Mitigação**: Keycloak OIDC como single source of truth, script de auditoria

---

## Métricas de Sucesso

✅ **RBAC GitLab configurado**: 5 grupos (`*-team`), matriz de permissões aplicada
✅ **RBAC Kubernetes configurado**: RoleBindings em todos os namespaces
✅ **Keycloak OIDC funcional**: SSO entre GitLab ↔ Kubernetes (Fase 2)
✅ **Kyverno policies deployed**: 100% de recursos validados (labels, naming)
✅ **Auditoria mensal**: 0 violações de governança
✅ **Exceções monitoradas**: 100% de exceções com prazo de expiração
✅ **FinOps labels**: 100% dos recursos com labels de cost allocation
✅ **Processo de onboarding**: Documentado e testado (1ª aplicação piloto)

---

## Referências

- **ADR-047**: Estrutura Corporativa de Domínios de Negócio
- **ADR-048**: Naming Conventions Determinísticas
- **Kubernetes RBAC**: https://kubernetes.io/docs/reference/access-authn-authz/rbac/
- **Kyverno Policies**: https://kyverno.io/policies/
- **Keycloak OIDC**: https://www.keycloak.org/docs/latest/securing_apps/
- **FinOps Foundation**: https://www.finops.org/

---

## Aprovações

- [ ] Usuário (gilvangalindo)
- [ ] Architect Guardian
- [ ] Platform Team (quando formado)

---

## Próximos Passos

1. ✅ Aprovar ADR-049
2. 📋 Criar scripts de auditoria (`/scripts/governance/audit-*.sh`)
3. 📋 Criar scripts de validação (`/scripts/governance/validate-*.sh`)
4. 📋 Implementar pre-push hooks no GitLab
5. 📋 Deploy Kyverno policies no Kubernetes (audit mode primeiro)
6. 📋 Criar GitLab Groups (`*-team`) e configurar RBAC
7. 📋 Criar Kubernetes RoleBindings por namespace
8. 📋 Documentar processos em `/docs/governance/GOVERNANCE.md`
9. 📋 Criar guia de onboarding em `/docs/governance/application-onboarding.md`
10. 📋 Executar 1ª auditoria (baseline)
