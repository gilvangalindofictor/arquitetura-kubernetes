# Backstage IDP — Plano de Implementacao

> **Atualizado:** 2026-03-05
> **Status:** Planejamento
> **ADR referencia:** ADR-055
> **Cluster:** k8s-platform-prod (EKS us-east-1, conta 891377105802)
> **Responsavel:** Platform Team

---

## Sumario Executivo

Este documento define o plano completo de implementacao do Backstage como Internal Developer Platform (IDP) para o cluster `k8s-platform-prod`. O Backstage centralizara o catalogo de servicos, provera templates de autoatendimento (scaffolding), e integrara toda a stack existente (GitLab, ArgoCD, Vault, Harbor, Keycloak, Kubernetes, SonarQube, Prometheus/Grafana) em uma unica interface para os desenvolvedores.

---

## 1. Decisao Estrategica

### Por que Backstage?

O principal problema hoje e o **custo cognitivo de onboarding**: um desenvolvedor que precisa criar um novo servico precisa conhecer e operar manualmente:

- GitLab (criar repositorio, configurar CI/CD, configurar `.gitlab-ci.yml`)
- Kubernetes (manifestos, namespaces, RBAC, requests/limits)
- HashiCorp Vault (criar namespace, secrets, AppRole, policy)
- Harbor (criar projeto, configurar robot account, push de imagem)
- ArgoCD (criar Application, configurar sync)
- External Secrets Operator (criar ExternalSecret)
- Kyverno (entender policies ativas)

Isso resulta em onboarding lento (estimativa: 2-4 dias por novo servico), erros frequentes por falta de padrao, e resistencia cultural ao uso da plataforma.

### Por que agora? Alinhamento com Marco 5

O Marco 5 da plataforma (Q1 2026) tem como objetivo central **Self-Service Platform**: a plataforma deve ser consumivel sem intervencao manual do time de plataforma. O Backstage e o enabler tecnico desse objetivo.

O ambiente esta maduro o suficiente:
- SSO unificado via Keycloak (ADR-046) — base para auth do Backstage
- GitOps via ArgoCD estabelecido — pipeline automatizado existe
- Vault KV v2 operacional — gestao de secrets padronizada
- Redis HA e PostgreSQL RDS disponiveis — zero nova infraestrutura necessaria
- Service mesh Linkerd ativo — seguranca de rede estabelecida

### Custo

O Backstage rodara na infraestrutura existente. Estimativa de custo incremental: **$0 em infraestrutura nova**. O pod Backstage consumira recursos do cluster EKS existente, utilizara o PostgreSQL RDS ja provisionado (novo database `backstage`) e o Redis HA existente (keyspace `/1`).

---

## 2. Principio: Developer Experience First

> "O desenvolvedor cria um repositorio via template no Backstage. Tudo mais e automatico. O desenvolvedor **nunca** precisa conhecer Kubernetes, Vault ou Harbor."

### Fluxo Golden Path (Estado Alvo)

```
+-------------------+
|   Desenvolvedor   |
|  (so conhece Git) |
+--------+----------+
         |
         | 1. Abre Backstage
         v
+-------------------+
|    Backstage UI    |
|  Software Catalog  |
|  + Scaffolder     |
+--------+----------+
         |
         | 2. Escolhe Template
         |    (ex: "ETL Service Python")
         v
+-------------------+
|  Template Form    |
|  - nome do servico|
|  - team owner     |
|  - tech stack     |
|  - integ. externas|
+--------+----------+
         |
         | 3. Submete
         v
+-----------------------------------------------------+
|                  Scaffolder Actions                  |
|                                                     |
|  [1] Cria repo GitLab com estrutura padrao          |
|  [2] Configura .gitlab-ci.yml + Dockerfile          |
|  [3] Cria manifestos K8s (Deployment/Service/etc)  |
|  [4] Cria namespace Vault + AppRole + Policy        |
|  [5] Cria ExternalSecret para o servico             |
|  [6] Cria ArgoCD Application (GitOps sync)          |
|  [7] Cria catalog-info.yaml no repo                 |
|  [8] Registra no Backstage Catalog                  |
+-----------------------------------------------------+
         |
         | 4. Em ~5 minutos:
         v
+-------------------+
|  Servico VIVO no  |
|  cluster, com CI, |
|  secrets, deploy  |
|  automatico ativo |
+-------------------+
         |
         | 5. Dev ve no Backstage:
         v
+-----------------------------------------------------+
|  Backstage Component Page                            |
|  - Status dos pods (Kubernetes plugin)              |
|  - Deploy history (ArgoCD plugin)                   |
|  - Imagens e CVEs (Harbor plugin)                   |
|  - Code quality (SonarQube plugin)                  |
|  - Logs/Traces/Metrics link (Grafana/Loki/Tempo)    |
|  - Secrets paths (Vault plugin - read only)         |
|  - Documentacao tecnica (TechDocs)                  |
+-----------------------------------------------------+
```

---

## 3. Versoes Pinadas (Marco 2026)

> **CRITICO:** Todas as versoes abaixo foram verificadas em marco de 2026. NAO atualizar sem validar compatibilidade, especialmente Node.js (18/20 nao suportados desde v1.46).

| Componente | Versao | Observacao |
|---|---|---|
| Backstage App | **v1.48.0** | LTS atual marco 2026 |
| Node.js | **22 LTS** | OBRIGATORIO — 18 e 20 descontinuados desde v1.46 |
| Yarn | **4.4.1** | Package manager oficial Backstage |
| Helm Chart | **backstage/backstage 2.6.3** | Chart oficial |
| Docker base image | **node:24-trixie-slim** | Runtime ~1.1-1.5GB |
| Kubernetes cluster | **v1.34** | EKS us-east-1 |
| ArgoCD | **v2.10.9** | Aviso: proximo de EOL — planejar upgrade para 3.x |
| GitLab | **v18.9.1** | Self-hosted |
| Keycloak | SSO (ADR-046) | OIDC provider |
| Linkerd | **2.x** | Service mesh (sidecar no Backstage pod) |
| Kyverno | Ativo | Policy engine — requer PolicyException |
| Vault | KV v2 | Kubernetes auth method |

---

## 4. Stack de Plugins

| Plugin | Versao | Funcionalidade | Prioridade |
|---|---|---|---|
| `@backstage/plugin-catalog` | 1.33.1 | Catalogo de componentes (frontend) | M1 |
| `@backstage/plugin-catalog-backend` | 3.3.0 | Catalogo backend + providers | M1 |
| `@backstage/plugin-auth-backend` | 0.26.0 | Auth backend + OIDC module | M1 |
| `@backstage/plugin-auth-backend-module-oidc-provider` | latest | Modulo OIDC para Keycloak | M1 |
| `@backstage/plugin-techdocs` | 1.17.0 | Documentacao tecnica (frontend) | M1 |
| `@backstage/plugin-techdocs-backend` | 2.1.5 | TechDocs backend (mkdocs) | M1 |
| `@backstage/plugin-kubernetes` | 0.12.16 | Visualizacao de workloads K8s | M1 |
| `@backstage/plugin-kubernetes-backend` | 0.20.4 | Kubernetes backend | M1 |
| `@backstage/plugin-catalog-backend-module-gitlab` | 0.8.0 | Discovery automatico repos GitLab | M1 |
| `@immobiliarelabs/backstage-plugin-gitlab` | 6.2.0 | UI rica: MRs, pipelines, issues, coverage | M1 |
| `@backstage-community/plugin-vault` | latest | Vault UI (read-only) | M1 |
| `@backstage-community/plugin-vault-backend` | latest | Vault backend | M1 |
| `@backstage-community/plugin-sonarqube` | 0.23.0 | Code quality por componente | M1 |
| `@backstage-community/plugin-sonarqube-backend` | 0.14.0 | SonarQube backend | M1 |
| `@backstage-community/plugin-catalog-backend-module-keycloak` | latest | Sync Users/Groups do Keycloak | M1 |
| `@backstage/plugin-scaffolder` | 1.35.4 | Software Templates (frontend) | M2 |
| `@backstage/plugin-scaffolder-backend` | **3.1.3** | Scaffolder backend (MINIMO 2.1.1 — CVE-2025-55285) | M2 |
| `@roadiehq/backstage-plugin-argo-cd` | 2.12.2 | ArgoCD status por componente | M2 |
| `@roadiehq/backstage-plugin-argo-cd-backend` | 4.5.1 | ArgoCD backend | M2 |
| `@bestsellerit/backstage-plugin-harbor` | latest | Harbor imagens e CVEs | M2 |

> **ATENCAO — Plugins DEPRECATED (NAO USAR):**
> - `@backstage/plugin-sonarqube` — DEPRECATED ha 2 anos. Usar `@backstage-community/plugin-sonarqube`
> - `@backstage/plugin-vault` — DEPRECATED. Usar `@backstage-community/plugin-vault`
> - `janus-idp/backstage-plugin-harbor` — ARQUIVADO em agosto 2025. Usar `@bestsellerit/backstage-plugin-harbor`

---

## 5. Alertas de Seguranca e Compatibilidade

| ID | Severidade | Problema | Solucao | Owner |
|---|---|---|---|---|
| CRITICO-1 | CRITICO | Legacy backend system REMOVIDO em v1.31. Plugins com `createPlugin` / `router.use` NAO inicializam. | Todos os plugins DEVEM usar `backend.add()` (novo sistema). Validar cada plugin antes do deploy. | Platform Eng |
| CRITICO-2 | CRITICO | CVE-2025-55285 — `@backstage/plugin-scaffolder-backend` < 2.1.1 vaza secrets em logs. | Usar versao **3.1.3** (ja corrigido). NUNCA usar versao < 2.1.1. | Platform Eng |
| ALTO-1 | ALTO | Harbor + Linkerd mTLS — Backstage esta no mesh, Harbor pode nao ter sidecar. Conexao falha. | Annotation no pod: `config.linkerd.io/skip-outbound-ports: "443"` OU adicionar Linkerd ao namespace Harbor. | Platform Eng |
| ALTO-2 | ALTO | GitLab 18.x: integration com OAuth token falha (issue #30650). | USAR **Group Access Token** (nao OAuth token). Escopos: `api`, `read_repository`, `read_user`. | Platform Eng |
| ALTO-3 | ALTO | Keycloak "iss missing" — misconfiguracao do `metadataUrl` causa falha silenciosa no auth. | Validar endpoint `/.well-known/openid-configuration` ANTES do deploy. Habilitar PKCE (S256) no client Keycloak. | Platform Eng |
| MEDIO-1 | MEDIO | Vault Scaffolder — nao existe action oficial para escrever no Vault KV v2 (RFC #32600 aberto). | Implementar action customizada `catalog:vault:write-namespace` ou usar HTTP request action. | Platform Eng |
| MEDIO-2 | MEDIO | Kyverno + Linkerd init container — `NET_ADMIN`/`NET_RAW` bloqueado por `disallow-privilege-escalation`. | Criar `PolicyException` para pods `backstage-*` no namespace `staging-platform-backstage`. Alternativa: Linkerd native sidecars 2.15+. | Platform Eng |
| MEDIO-3 | MEDIO | ArgoCD 2.10.9 e versao nao-LTS, proxima de EOL. | Planejar upgrade para ArgoCD 3.x (plugin `@roadiehq/backstage-plugin-argo-cd` 2.12.2 e compativel). | Platform Eng |
| BAIXO-1 | BAIXO | GitLab 18.6+ rate limits na File API. | Manter schedule discovery >= 30 minutos (`frequency.minutes: 30`). | Platform Eng |

---

## 6. Arquitetura de Deploy

### Namespace e Posicionamento

```
Namespace: staging-platform-backstage
Cluster:   k8s-platform-prod (EKS, us-east-1)
Pattern:   staging-platform-* (consistente com demais servicos platform)
```

### Recursos Computacionais

```yaml
resources:
  requests:
    cpu: 250m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1536Mi
```

### Banco de Dados e Cache

| Componente | Solucao | Detalhe |
|---|---|---|
| PostgreSQL | RDS existente (AWS) | Novo database `backstage`, usuario `backstage_user` |
| Redis | Redis HA existente (Spotahome operator) | Keyspace `/1` (sem conflito com apps existentes) |

**Zero infraestrutura nova necessaria.**

### Service Mesh

O pod Backstage tera o sidecar Linkerd injetado (`linkerd.io/inject: "enabled"`). A annotation `config.linkerd.io/skip-outbound-ports: "443"` e necessaria para comunicacao com Harbor (workaround ALTO-1).

### Ingress

ALB interno (schema `internal`), target-type `ip`, host `backstage.staging.internal`.

---

## 7. Integracao Keycloak (SSO)

### Pre-requisitos no Keycloak

1. Realm `platform` criado (ja existente por ADR-046)
2. Client `backstage` criado com:
   - Access Type: `confidential`
   - **PKCE habilitado** (Code Challenge Method: S256) — Backstage usa S256 por padrao
   - Valid Redirect URIs: `https://backstage.staging.internal/api/auth/keycloak/handler/frame`
   - Web Origins: `https://backstage.staging.internal`
3. Client Secret copiado para Vault: `secret/data/platform/integrations/keycloak`

### Validacao do Endpoint (ANTES DO DEPLOY)

```bash
# Validar metadataUrl — OBRIGATORIO antes do deploy
curl -s https://<KEYCLOAK_HOST>/realms/platform/.well-known/openid-configuration | jq '.issuer'
# Deve retornar: "https://<KEYCLOAK_HOST>/realms/platform"
```

### Configuracao app-config.yaml

```yaml
auth:
  session:
    secret: ${AUTH_SESSION_SECRET}
  providers:
    keycloak:
      production:
        metadataUrl: https://<KEYCLOAK_HOST>/realms/platform/.well-known/openid-configuration
        clientId: ${KEYCLOAK_CLIENT_ID}
        clientSecret: ${KEYCLOAK_CLIENT_SECRET}
        prompt: auto
```

---

## 8. Integracao Vault (Kubernetes Auth Method)

O Backstage usara Kubernetes Auth Method (nao token estatico). O Service Account `backstage` no namespace `staging-platform-backstage` sera vinculado a uma role no Vault.

### Configuracao do Vault

```bash
# Habilitar Kubernetes auth (se nao habilitado)
vault auth enable kubernetes

# Configurar o auth method
vault write auth/kubernetes/config \
  kubernetes_host="https://${EKS_CLUSTER_URL}" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

# Criar role para o Backstage
vault write auth/kubernetes/role/backstage \
  bound_service_account_names=backstage \
  bound_service_account_namespaces=staging-platform-backstage \
  policies=backstage-policy \
  ttl=1h
```

### IRSA (Recomendado para EKS)

O Service Account `backstage` deve ter annotation IRSA:

```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::891377105802:role/backstage-irsa-role
```

---

## 9. Integracao GitLab

### Group Access Token (OBRIGATORIO)

Conforme ALTO-2, usar **Group Access Token** (nao OAuth token). Issue #30650 confirma falha com OAuth tokens no GitLab 18.x.

```
Tipo:    Group Access Token
Grupo:   / (root, ou grupo principal dos projetos)
Escopos: api, read_repository, read_user
Salvar:  secret/data/platform/integrations/gitlab
```

### Discovery Automatico

O plugin `@backstage/plugin-catalog-backend-module-gitlab` 0.8.0 fara discovery automatico de todos os repos GitLab que contenham `catalog-info.yaml`. Schedule minimo: 30 minutos (BAIXO-1).

---

## 10. Milestones de Implementacao

### M1 (Semanas 1-4): Core + SSO + GitLab + Observabilidade

**Objetivo:** Backstage funcionando com autenticacao, catalogo populado e visibilidade dos workloads.

**Entregaveis:**
- [ ] Backstage v1.48.0 deployado no cluster `k8s-platform-prod`
- [x] Namespace `staging-platform-backstage` criado com Linkerd injetado — CONCLUIDO 2026-03-06
- [x] Keycloak OIDC configurado — client `backstage` existente, secret extraido — CONCLUIDO 2026-03-06
- [ ] GitLab integration ativa — discovery automatico de todos os repos (schedule: 30min)
- [ ] Plugin `@immobiliarelabs/backstage-plugin-gitlab` 6.2.0 — MRs, pipelines, issues, coverage
- [ ] Kubernetes plugin — visualizacao de todos os workloads nos namespaces `staging-platform-*`
- [ ] Vault plugin read-only — listar e visualizar paths de secrets
- [ ] SonarQube integration — code quality por componente
- [ ] Keycloak sync — Users e Groups sincronizados automaticamente
- [ ] TechDocs configurado — documentacao gerada a partir de `mkdocs.yml` nos repos
- [ ] `catalog-info.yaml` criado nos primeiros 5 repos criticos da plataforma

**Criterio de sucesso M1:** Um desenvolvedor consegue logar no Backstage com suas credenciais Keycloak, ver todos os servicos da plataforma no catalogo, e visualizar o status dos pods K8s e pipelines GitLab de cada servico.

---

### M2 (Semanas 5-8): Scaffolder + ArgoCD + Harbor

**Objetivo:** Scaffolding automatizado — dev cria novo servico sem intervencao manual.

**Entregaveis:**

**Software Templates:**
- [ ] Template **"ETL Service"** (Python + K8s + ESO + Vault)
  - Input: nome, team, schedule (cron), fonte de dados
  - Actions: cria repo GitLab + `.gitlab-ci.yml` + `Dockerfile` + manifestos K8s + ExternalSecret + AppRole Vault + ArgoCD Application
- [ ] Template **"API Service"** (FastAPI + K8s)
  - Input: nome, team, port, autenticacao (sim/nao)
  - Actions: idem ETL + ingress + HPA
- [ ] Template **"Frontend"** (React + nginx + K8s)
  - Input: nome, team, API backend (referencia catalog)
  - Actions: idem API + ConfigMap nginx

**Outros entregaveis M2:**
- [ ] ArgoCD plugin — deployment history + sync status por componente
- [ ] Harbor plugin — imagens e vulnerabilidades por servico
- [ ] **Vault Scaffolder action customizada** (`catalog:vault:write-namespace`) — cria namespace da app no Vault (MEDIO-1)
- [ ] TechDocs — primeiro servico com documentacao completa publicada

**Criterio de sucesso M2:** Um desenvolvedor preenche um formulario no Backstage e em 5 minutos tem um servico rodando no cluster, com CI ativo, secrets configurados no Vault, e deploy automatico via ArgoCD.

---

### M3 (Semanas 9-12): Self-Service Platform

**Objetivo:** Plataforma completamente self-service, Backstage como unico ponto de entrada.

**Entregaveis:**
- [ ] Template completo com selecao de integracoes externas (Vault reference pattern)
- [ ] Backstage como UI de gestao de secrets `platform/integrations/*` (com aprovacao)
- [ ] Grafana plugin — dashboards por servico diretamente no Backstage
- [ ] Cost Insights plugin — FinOps por servico/team
- [ ] Todos os servicos da plataforma com `catalog-info.yaml`
- [ ] Runbooks e ADRs publicados via TechDocs

**Criterio de sucesso M3:** 100% dos novos servicos criados via Backstage. Zero tickets manuais de "criar namespace no Vault" ou "configurar ArgoCD".

---

### M4 (Semanas 13-16): Producao + Governance

**Objetivo:** Alta disponibilidade, governanca e enforcement.

**Entregaveis:**
- [ ] HA: 2 replicas, `PodDisruptionBudget` com `minAvailable: 1`
- [ ] Karpenter NodePool dedicado para Backstage (On-Demand base + Spot para burst)
- [ ] Backstage como porta de entrada obrigatoria para novos projetos (enforcement via ADR-055)
- [ ] ADR-055 aprovado, publicado e em enforcement
- [ ] Metricas de adocao: % servicos no catalogo, % criados via template
- [ ] Plano de upgrade ArgoCD para 3.x (MEDIO-3)

---

## 11. Helm Values (Staging)

Ver arquivo separado: `helm-values-staging.yaml`

O chart utilizado e `backstage/backstage 2.6.3`. Principais configuracoes:

- `postgresql.enabled: false` — usa RDS externo
- `serviceAccount.create: true` com annotation IRSA
- `podAnnotations` com Linkerd inject e skip-outbound-ports (ALTO-1)
- `ingress` ALB interno

---

## 12. Pipeline CI/CD

### Job `build-backstage` no GitLab CI

```yaml
# .gitlab-ci.yml do repositorio backstage-app
stages:
  - build
  - push
  - deploy

variables:
  HARBOR_REGISTRY: harbor.staging.internal
  IMAGE_NAME: platform/backstage

build-backstage:
  stage: build
  image: node:22-slim
  script:
    - yarn install --frozen-lockfile
    - yarn tsc
    - yarn build:all
  cache:
    paths:
      - node_modules/
  artifacts:
    paths:
      - packages/backend/dist/
      - packages/app/dist/

build-image:
  stage: push
  image: docker:24
  services:
    - docker:24-dind
  script:
    - docker build -t ${HARBOR_REGISTRY}/${IMAGE_NAME}:${CI_COMMIT_SHA} .
    - docker build -t ${HARBOR_REGISTRY}/${IMAGE_NAME}:latest .
    - echo ${HARBOR_ROBOT_SECRET} | docker login ${HARBOR_REGISTRY} -u ${HARBOR_ROBOT_USER} --password-stdin
    - docker push ${HARBOR_REGISTRY}/${IMAGE_NAME}:${CI_COMMIT_SHA}
    - docker push ${HARBOR_REGISTRY}/${IMAGE_NAME}:latest
  only:
    - main

deploy-staging:
  stage: deploy
  image: argoproj/argocd:v2.10.9
  script:
    - argocd app set backstage --helm-set backstage.image.tag=${CI_COMMIT_SHA}
    - argocd app sync backstage --timeout 120
    - argocd app wait backstage --health --timeout 180
  environment:
    name: staging
  only:
    - main
```

### Dockerfile para Build

```dockerfile
FROM node:22-slim AS build
WORKDIR /app
COPY package.json yarn.lock ./
COPY packages/backend/package.json ./packages/backend/
COPY packages/app/package.json ./packages/app/
RUN yarn install --frozen-lockfile
COPY . .
RUN yarn build:all

FROM node:24-trixie-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/packages/backend/dist ./packages/backend/dist
COPY --from=build /app/node_modules ./node_modules
EXPOSE 7007
CMD ["node", "packages/backend/dist/index.cjs"]
```

---

## 13. RBAC Kubernetes Necessario

Ver arquivo separado: `rbac.yaml`

O `ClusterRole` `backstage-kubernetes-reader` concede acesso read-only a:
- Pods, ConfigMaps, Services, ResourceQuotas, LimitRanges, Events, ServiceAccounts
- Deployments, ReplicaSets, StatefulSets, DaemonSets
- HPAs, Ingresses, NetworkPolicies
- Jobs, CronJobs
- Metricas (metrics.k8s.io)
- ArgoCD Applications e AppProjects (argoproj.io)
- ExternalSecrets e ClusterSecretStores

---

## 14. Vault Policies Necessarias

Ver arquivo separado: `vault-policy.hcl`

### Resumo das Permissoes

| Path | Capabilities | Uso |
|---|---|---|
| `secret/metadata/*` | list | Plugin Vault UI — listar paths disponiveis |
| `secret/data/platform/integrations/*` | read | Ler secrets das integracoes da plataforma |
| `secret/metadata/staging/+/*` | list | Listar secrets por app |
| `secret/data/staging/+/*` | create, update | Scaffolder — criar namespace de nova app |
| `sys/policies/acl/+*` | create, update, read | Scaffolder — criar policy de nova app |
| `auth/approle/role/+*` | create, update, read | Scaffolder — criar AppRole de nova app |

---

## 15. Kyverno PolicyException

Ver arquivo separado: `kyverno-exception.yaml`

### Justificativa

O Linkerd proxy-init container precisa de `NET_ADMIN` e `NET_RAW` para configurar regras iptables. As policies Kyverno `disallow-privilege-escalation` e `disallow-capabilities` bloqueiam isso.

A `PolicyException` e aplicada somente no namespace `staging-platform-backstage`, minimizando o escopo da excecao.

**Alternativa para o futuro:** Migrar para Linkerd native sidecars (2.15+) que nao precisam de `NET_ADMIN`.

---

## 16. Checklist de Pre-Deploy

### Keycloak
- [ ] Client `backstage` criado no realm `platform` — **PENDENTE: acao manual no Keycloak admin console**
- [ ] Realm `platform` existe e esta ativo
- [ ] Client `backstage` criado com `clientId` e `clientSecret`
- [ ] **PKCE habilitado** no client (Code Challenge Method: S256)
- [ ] Redirect URIs configuradas: `https://backstage.staging.internal/api/auth/keycloak/handler/frame`
- [ ] Endpoint `metadataUrl` validado via curl (retorna `issuer` correto)
- [ ] Client Secret armazenado no Vault: `secret/data/platform/integrations/keycloak`

### GitLab
- [ ] Group Access Token criado — **PENDENTE: acao manual no GitLab (gitlab.staging.internal)**
- [ ] **Group Access Token** criado (NAO OAuth token — issue #30650)
- [ ] Escopos: `api`, `read_repository`, `read_user`
- [ ] Token armazenado no Vault: `secret/data/platform/integrations/gitlab`
- [ ] Token testado: `curl -H "PRIVATE-TOKEN: <token>" https://<GITLAB_HOST>/api/v4/groups`

### Banco de Dados (RDS PostgreSQL)
- [ ] Schema backstage criado no RDS — **PENDENTE: executar apos bootstrap-vault-setup.sh**
- [ ] Conectar ao RDS existente
- [ ] `CREATE DATABASE backstage;`
- [ ] `CREATE USER backstage_user WITH PASSWORD '<senha_forte>';`
- [ ] `GRANT ALL PRIVILEGES ON DATABASE backstage TO backstage_user;`
- [ ] Credenciais armazenadas no Vault: `secret/data/platform/integrations/postgres-backstage`

### Vault
- [ ] VAULT_TOKEN admin obtido e exportado — **PENDENTE: executar `bootstrap-vault-setup.sh`**
- [ ] Auth method Kubernetes habilitado: `vault auth enable kubernetes`
- [ ] Kubernetes auth configurado com URL e CA do cluster EKS
- [ ] Policy `backstage-policy` criada: `vault policy write backstage-policy vault-policy.hcl`
- [ ] Role `backstage` criada: `vault write auth/kubernetes/role/backstage ...`

> **Instrucao:** Com VAULT_TOKEN admin disponivel, executar:
> `cd docs/plan/backstage && chmod +x bootstrap-vault-setup.sh && ./bootstrap-vault-setup.sh`

### Harbor
- [ ] Robot account `backstage-puller` criado — **PENDENTE: acao manual no Harbor (harbor.staging.internal)**
- [ ] Projeto `platform` existe no Harbor
- [ ] Robot account `backstage-puller` criado com permissao pull
- [ ] Credentials armazenadas no Kubernetes Secret `harbor-pull-secret`

### Kubernetes
- [x] Namespace `staging-platform-backstage` criado com annotation Linkerd — **CONCLUIDO 2026-03-05**
- [x] `ClusterRole` e `ClusterRoleBinding` backstage-kubernetes-reader aplicados (inclui argoproj.io, external-secrets.io) — **CONCLUIDO 2026-03-05**
- [x] `PodDisruptionBudget` backstage-pdb criado (minAvailable=1) — **CONCLUIDO 2026-03-05**
- [x] `PolicyException` backstage-linkerd-exception (v2beta1) aplicada — **CONCLUIDO 2026-03-05**
- [ ] Secret `backstage-secrets` criado no namespace com todas as credenciais

### ArgoCD
- [ ] Token ArgoCD gerado — **PENDENTE: executar `argocd account generate-token --account backstage-reader`**
- [ ] Service account `backstage-reader` criado no namespace `staging-platform-argocd`
- [ ] Role + RoleBinding com permissao `get`, `list` em Applications
- [ ] Token gerado e armazenado no Vault: `secret/data/platform/integrations/argocd`

### SonarQube
- [ ] Token SonarQube gerado — **PENDENTE: acao manual no SonarQube (sonarqube.staging.internal)**
- [ ] Service account criado no SonarQube
- [ ] Token de API gerado
- [ ] Token armazenado no Vault: `secret/data/platform/integrations/sonarqube`

### Helm e ArgoCD Application
- [x] Repositorio Helm `backstage` adicionado (v2.6.3 disponivel) — **CONCLUIDO 2026-03-05**
- [x] ExternalSecret manifest preparado (`externalsecret-backstage.yaml`) — **CONCLUIDO 2026-03-05**
- [ ] `helm-values-staging.yaml` revisado e com todos os placeholders substituidos
- [ ] ArgoCD Application `backstage` criada apontando para o chart + values
- [ ] Primeiro deploy realizado: `argocd app sync backstage`

---

## 17. Proximos Passos Imediatos

### Acao 1: Validar pre-requisitos de auth (Hoje)
```bash
# 1. Validar Keycloak metadataUrl
curl -s https://<KEYCLOAK_HOST>/realms/platform/.well-known/openid-configuration | jq '{issuer, authorization_endpoint, token_endpoint}'

# 2. Criar Group Access Token no GitLab e testar
curl -H "PRIVATE-TOKEN: <token>" https://<GITLAB_HOST>/api/v4/groups | jq '.[0].name'

# 3. Verificar conectividade RDS
psql -h <RDS_HOST> -U admin -c '\l'
```

### Acao 2: Aplicar recursos Kubernetes (Semana 1)
```bash
# Criar namespace e RBAC
kubectl apply -f rbac.yaml
kubectl apply -f kyverno-exception.yaml

# Verificar PolicyException
kubectl get policyexception -n staging-platform-backstage

# Criar secret com credenciais (usar ESO em producao)
kubectl create secret generic backstage-secrets \
  --namespace staging-platform-backstage \
  --from-literal=postgres-host=<RDS_HOST> \
  --from-literal=postgres-user=backstage_user \
  --from-literal=postgres-password=<SENHA> \
  --from-literal=keycloak-client-id=backstage \
  --from-literal=keycloak-client-secret=<SECRET> \
  --from-literal=gitlab-token=<GROUP_ACCESS_TOKEN>
```

### Acao 3: Primeiro deploy Helm (Semana 1)
```bash
# Adicionar repo
helm repo add backstage https://backstage.github.io/charts
helm repo update

# Deploy inicial (dry-run primeiro)
helm upgrade --install backstage backstage/backstage \
  --version 2.6.3 \
  --namespace staging-platform-backstage \
  --values helm-values-staging.yaml \
  --dry-run

# Deploy real
helm upgrade --install backstage backstage/backstage \
  --version 2.6.3 \
  --namespace staging-platform-backstage \
  --values helm-values-staging.yaml

# Acompanhar
kubectl -n staging-platform-backstage get pods -w
kubectl -n staging-platform-backstage logs -f deployment/backstage
```

---

## 18. Definicao de Pronto (DoD)

Um milestone e considerado **Pronto** quando:

1. Todos os entregaveis do milestone estao marcados como concluidos no checklist
2. O criterio de sucesso do milestone foi validado por pelo menos um desenvolvedor nao pertencente ao time de plataforma
3. O ADR-055 foi atualizado com o status do milestone
4. Nenhum alerta CRITICO ou ALTO pendente de resolucao

---

## 19. Referencias

| Recurso | URL |
|---|---|
| Backstage docs oficiais | https://backstage.io/docs |
| Helm chart backstage/backstage | https://github.com/backstage/charts |
| CVE-2025-55285 | https://github.com/backstage/backstage/security/advisories |
| GitLab issue #30650 (OAuth tokens) | https://gitlab.com/gitlab-org/gitlab/-/issues/30650 |
| Vault RFC #32600 (Scaffolder KV v2) | https://github.com/backstage/backstage/issues/32600 |
| Linkerd native sidecars | https://linkerd.io/2.15/tasks/installing-cni/ |
| @immobiliarelabs/backstage-plugin-gitlab | https://www.npmjs.com/package/@immobiliarelabs/backstage-plugin-gitlab |
| @bestsellerit/backstage-plugin-harbor | https://www.npmjs.com/package/@bestsellerit/backstage-plugin-harbor |
| ADR-046 (Keycloak SSO) | `docs/adr/adr-046-keycloak-sso.md` |
| ADR-055 (Backstage IDP) | `docs/adr/adr-055-backstage-idp-strategy.md` |

---

*Documento gerado em 2026-03-05 pelo Platform Architecture Team.*
*Proxima revisao programada: 2026-04-01 (apos conclusao M1).*
