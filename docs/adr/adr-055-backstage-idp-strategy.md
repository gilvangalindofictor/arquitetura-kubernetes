# ADR-055 — Backstage como Internal Developer Platform (IDP)

> **Status:** Proposed
> **Data:** 2026-03-05
> **Autores:** Platform Architecture Team
> **ADR anterior:** ADR-054
> **Revisores:** Tech Lead, Engineering Manager
> **Relacionados:** ADR-046 (Keycloak SSO), ADR-054 (ultimo ADR aprovado)

---

## Status: Proposed

---

## Contexto

### Problema

A plataforma `k8s-platform-prod` atingiu o Marco 4 com sucesso: GitOps via ArgoCD, service mesh Linkerd, policy engine Kyverno, gestao de secrets HashiCorp Vault, e observabilidade completa (Prometheus + Grafana + Loki + Tempo + OTEL). O ambiente esta tecnicamente maduro.

Contudo, o **custo cognitivo para os desenvolvedores e proibitivo**. Para criar um novo servico, um desenvolvedor precisa atualmente:

1. Criar repositorio GitLab com estrutura correta
2. Configurar `.gitlab-ci.yml` com build, push Harbor e sync ArgoCD
3. Criar Dockerfile compativel com a stack (Node.js 22, node:24-trixie-slim para runtime)
4. Criar manifestos Kubernetes (Deployment, Service, Ingress, HPA, PDB)
5. Criar namespace no Vault KV v2 + AppRole + Policy
6. Criar ExternalSecret para o namespace correto
7. Criar ArgoCD Application no namespace `staging-platform-argocd`
8. Configurar `catalog-info.yaml` quando o catalogo existir

Estimativa atual: **2 a 4 dias de trabalho** por novo servico, com alta taxa de erro por falta de padronizacao.

### Marco 5: Self-Service Platform

O Marco 5 (Q1 2026) define como objetivo central que **a plataforma deve ser consumivel por desenvolvedores sem intervencao do time de plataforma**. O Backstage e o enabler tecnico desse objetivo.

### Estado Atual da Infraestrutura

O ambiente ja possui todos os pre-requisitos para o Backstage:

| Componente | Estado | Relevancia |
|---|---|---|
| Keycloak (ADR-046) | Ativo | SSO para Backstage (OIDC) |
| GitLab v18.9.1 (self-hosted) | Ativo | Source control + CI/CD + catalog discovery |
| ArgoCD v2.10.9 | Ativo | GitOps — plugin ArgoCD |
| HashiCorp Vault KV v2 | Ativo | Secrets — plugin Vault + Scaffolder |
| Harbor (com Linkerd sidecar) | Ativo | Registry — plugin Harbor |
| PostgreSQL RDS | Ativo | Database para Backstage (novo DB) |
| Redis HA (Spotahome) | Ativo | Cache para Backstage (keyspace /1) |
| Linkerd 2.x | Ativo | Service mesh — sidecar no Backstage pod |
| Kyverno | Ativo | Policies — requer PolicyException |
| SonarQube | Ativo | Code quality — plugin SonarQube |
| Prometheus + Grafana + Loki + Tempo | Ativo | Observabilidade — plugin Grafana (M3) |

---

## Decisao

**Adotamos o Backstage v1.48.0 como Internal Developer Platform (IDP) da plataforma.**

### Especificacoes Tecnicas

| Item | Decisao |
|---|---|
| Versao | Backstage **v1.48.0** |
| Runtime | Node.js **22 LTS** (OBRIGATORIO — 18/20 descontinuados desde v1.46) |
| Package manager | Yarn **4.4.1** |
| Helm chart | `backstage/backstage` **2.6.3** |
| Namespace | `staging-platform-backstage` |
| Database | PostgreSQL RDS existente (novo database `backstage`) |
| Cache | Redis HA existente (keyspace `/1`) |
| Auth | Keycloak OIDC (ADR-046 reaproveitado) + PKCE S256 |
| Image base | `node:24-trixie-slim` (runtime) |
| Image registry | Harbor `platform/backstage` |

### Roadmap de Implementacao

| Milestone | Periodo | Objetivo Principal |
|---|---|---|
| M1 | Semanas 1-4 | Core + SSO + GitLab + Kubernetes visibility |
| M2 | Semanas 5-8 | Scaffolder + ArgoCD + Harbor |
| M3 | Semanas 9-12 | Self-Service Platform completo |
| M4 | Semanas 13-16 | HA + Governance + Enforcement |

---

## Consequencias Positivas

### 1. Golden Path para Desenvolvedores
Desenvolvedores criam novos servicos via template em ~5 minutos, sem conhecimento de Kubernetes, Vault ou Harbor. Reducao estimada de 2-4 dias para < 1 hora por novo servico.

### 2. Catalogo Centralizado
Todos os servicos da plataforma (existentes e novos) catalogados em um unico lugar com metadados padronizados: owners, dependencias, documentacao, status de qualidade, status de deploy.

### 3. Self-Service Auditavel
Cada acao de scaffolding e auditavel: quem criou, quando, qual template, quais parametros. Conformidade e governanca por design.

### 4. Reducao de Tickets Manuais
Eliminacao de tickets recorrentes do tipo: "criar namespace no Vault", "configurar ArgoCD Application", "criar robot account no Harbor". Estimativa: reducao de 80% dos tickets operacionais do time de plataforma.

### 5. Developer Experience Unificada
Um unico portal para: ver status de deployments (ArgoCD), qualidade de codigo (SonarQube), imagens e CVEs (Harbor), pipelines (GitLab), pods e logs (Kubernetes), documentacao tecnica (TechDocs).

### 6. Zero Custo de Infraestrutura Nova
O Backstage utilizara exclusivamente infraestrutura existente: PostgreSQL RDS, Redis HA, cluster EKS. Custo incremental estimado: proximo de zero.

---

## Consequencias Negativas e Riscos

### 1. Manutencao do catalog-info.yaml
Cada repositorio existente precisara ter um arquivo `catalog-info.yaml` criado e mantido. Isso requer um trabalho inicial de retrospecao nos repositorios existentes e disciplina para incluir o arquivo em novos repos (mitigado pelo scaffolding automatico via templates).

### 2. Overhead Node.js 22
O processo Backstage requer Node.js 22 LTS, o que e um runtime adicional no cluster. Recursos estimados: 250m-1000m CPU, 512Mi-1.5Gi memoria. Aceitavel dado o valor entregue.

### 3. Manutencao de Plugins
O ecossistema de plugins Backstage evolui rapidamente. Plugins comunitarios (ex: `@backstage-community/*`) podem ser descontinuados ou mudar de maintainer. Requer monitoramento periodico de versoes e deprecacoes.

### 4. Curva de Aprendizado (Backstage Internals)
O time de plataforma precisara conhecer a arquitetura interna do Backstage para: criar plugins customizados, manter templates, debugar problemas. Estimativa: 2-3 sprints para o time atingir proficiencia.

### 5. Acoplamento ao GitLab
O Backstage dependera de Group Access Token do GitLab. Se o GitLab tiver downtime, o catalog discovery parara. Mitigado pelo cache do catalogo (dados ainda disponiveis, apenas discovery pausado).

---

## Alternativas Rejeitadas

| Alternativa | Motivo da Rejeicao |
|---|---|
| **Humanitec** | Custo elevado (SaaS enterprise). Vendor lock-in em plataforma proprietaria. Estimativa: $50k+/ano. |
| **Cortex** | Custo elevado (SaaS). Funcionalidades de catalogo apenas, sem scaffolding proprio. |
| **Backstage as SaaS (Roadie)** | Vendor lock-in. Custo crescente com numero de usuarios. Limite de customizacao de plugins. |
| **Portal customizado interno** | Custo de desenvolvimento proibitivo (estimativa: 6-12 meses de engenharia). Sem ecossistema de plugins. Sem comunidade. |
| **Nenhuma acao** | Nao atende ao Marco 5. Onboarding continuara custoso e lento. Resistencia cultural a plataforma aumenta. |

---

## Plugins Selecionados e Justificativas

| Plugin | Versao | Justificativa | Alternativas Rejeitadas |
|---|---|---|---|
| `@backstage/plugin-catalog-backend-module-gitlab` | 0.8.0 | Plugin oficial Backstage para GitLab self-hosted. Suporte nativo. | Plugin comunitario legado (nao mantido) |
| `@immobiliarelabs/backstage-plugin-gitlab` | 6.2.0 | UI rica com MRs, pipelines, issues, coverage. Muito mais informacao que o plugin oficial de UI. | Plugin oficial UI (muito basico) |
| `@backstage-community/plugin-sonarqube` | 0.23.0 | Plugin comunitario ativo. O `@backstage/plugin-sonarqube` esta DEPRECATED ha 2 anos. | `@backstage/plugin-sonarqube` (DEPRECATED) |
| `@backstage-community/plugin-vault` + backend | latest | Plugin comunitario ativo. O `@backstage/plugin-vault` esta DEPRECATED. | `@backstage/plugin-vault` (DEPRECATED) |
| `@roadiehq/backstage-plugin-argo-cd` | 2.12.2 | Plugin mais maduro e rico para ArgoCD. Roadie tem longa historia de manutencao deste plugin. | Plugin oficial (funcionalidade basica) |
| `@bestsellerit/backstage-plugin-harbor` | latest | Unico plugin ativo para Harbor. O `janus-idp` foi ARQUIVADO em agosto 2025. | `janus-idp/backstage-plugin-harbor` (ARQUIVADO) |
| `@backstage-community/plugin-catalog-backend-module-keycloak` | latest | Sync automatico de Users e Groups do Keycloak para o catalogo. Essencial para ownership. | Criacao manual de usuarios (inviavel em escala) |

---

## Breaking Change Critico: Legacy Backend System

> **AVISO CRITICO — LEITURA OBRIGATORIA ANTES DE QUALQUER IMPLEMENTACAO**

O **Legacy Backend System foi completamente removido no Backstage v1.31**.

**Impacto:** Qualquer plugin que use a API antiga (`createPlugin`, `router.use`, `createBackend` legado) **nao inicializara silenciosamente**. Nao ha mensagem de erro clara — o plugin simplesmente nao funciona.

**O que mudou:**
- **ANTIGO (removido):** `backend.add(createPlugin(...))` com `router.use()`
- **NOVO (obrigatorio):** `backend.add(import('@backstage/plugin-xxx-backend'))` com o novo sistema modular

**Validacao obrigatoria antes do deploy:**
```typescript
// packages/backend/src/index.ts — CORRETO (novo sistema)
import { createBackend } from '@backstage/backend-defaults';

const backend = createBackend();

// Todos os plugins devem ser adicionados assim:
backend.add(import('@backstage/plugin-catalog-backend'));
backend.add(import('@backstage/plugin-auth-backend'));
backend.add(import('@backstage/plugin-auth-backend-module-oidc-provider'));
backend.add(import('@backstage/plugin-techdocs-backend'));
backend.add(import('@backstage/plugin-kubernetes-backend'));
backend.add(import('@backstage/plugin-scaffolder-backend'));
// ... etc

backend.start();
```

**Verificacao:** Antes de adicionar qualquer plugin, verificar no NPM se a versao suporta o novo backend system. Plugins comunitarios antigos podem nao ter sido atualizados.

---

## Seguranca

### CVE-2025-55285 — Scaffolder Backend Secret Leak

**Severidade:** CRITICA
**Afeta:** `@backstage/plugin-scaffolder-backend` < 2.1.1
**Problema:** Secrets (tokens, senhas) sao vazados em texto claro nos logs do pod.
**Solucao:** Usar versao **3.1.3** (atual, corrigida). **NUNCA fazer downgrade abaixo de 2.1.1.**

### Vault — Kubernetes Auth Method (Nao Token Estatico)

O Backstage se autenticara no Vault usando **Kubernetes Auth Method** com o Service Account `backstage` no namespace `staging-platform-backstage`. Isso elimina a necessidade de tokens estaticos rotativos.

```bash
vault write auth/kubernetes/role/backstage \
  bound_service_account_names=backstage \
  bound_service_account_namespaces=staging-platform-backstage \
  policies=backstage-policy \
  ttl=1h
```

### Keycloak — PKCE Obrigatorio

O Backstage usa **PKCE S256** por padrao. O client `backstage` no Keycloak **deve ter PKCE habilitado**. Sem isso, o fluxo de autenticacao falha.

Validacao pre-deploy:
```bash
curl -s https://<KEYCLOAK_HOST>/realms/platform/.well-known/openid-configuration \
  | jq '.code_challenge_methods_supported'
# Deve incluir "S256"
```

### GitLab — Group Access Token (Nao OAuth)

Conforme issue #30650 do GitLab, a integracao Backstage + GitLab 18.x **falha silenciosamente com OAuth tokens**. O token DEVE ser um **Group Access Token** com escopos `api`, `read_repository`, `read_user`.

### Harbor + Linkerd mTLS Workaround

O pod Backstage estara no service mesh Linkerd. Se o Harbor nao tiver sidecar Linkerd, a comunicacao mTLS falha. Solucao implementada:

```yaml
podAnnotations:
  config.linkerd.io/skip-outbound-ports: "443"
```

Isso exclui a porta 443 (Harbor HTTPS) do intercepte mTLS do Linkerd, permitindo a comunicacao direta.

---

## Implementacao de Referencia

Os seguintes artefatos de implementacao foram criados junto com este ADR:

| Arquivo | Descricao |
|---|---|
| `docs/plan/backstage/BACKSTAGE-IMPLEMENTATION-PLAN.md` | Plano completo de implementacao com todos os milestones |
| `docs/plan/backstage/helm-values-staging.yaml` | Helm values para o chart backstage/backstage 2.6.3 |
| `docs/plan/backstage/rbac.yaml` | ClusterRole, ClusterRoleBinding, Namespace, PDB |
| `docs/plan/backstage/kyverno-exception.yaml` | PolicyException para Linkerd init container |
| `docs/plan/backstage/vault-policy.hcl` | Vault policy para o Backstage |

---

## Referencias

| Recurso | URL/Localizacao |
|---|---|
| Backstage documentacao oficial | https://backstage.io/docs |
| Backstage v1.48.0 changelog | https://backstage.io/docs/releases/v1.48.0 |
| Helm chart backstage/backstage 2.6.3 | https://github.com/backstage/charts |
| CVE-2025-55285 (Scaffolder secret leak) | https://github.com/backstage/backstage/security/advisories |
| Legacy Backend System removal (v1.31) | https://backstage.io/docs/backend-system/building-backends/migrating |
| GitLab issue #30650 (OAuth token) | https://gitlab.com/gitlab-org/gitlab/-/issues/30650 |
| Vault RFC #32600 (Scaffolder KV v2 action) | https://github.com/backstage/backstage/issues/32600 |
| Kyverno PolicyException docs | https://kyverno.io/docs/writing-policies/exceptions/ |
| Linkerd native sidecars | https://linkerd.io/2.15/tasks/installing-cni/ |
| ADR-046 (Keycloak SSO) | `docs/adr/adr-046-keycloak-sso.md` |
| NPM: @immobiliarelabs/backstage-plugin-gitlab | https://www.npmjs.com/package/@immobiliarelabs/backstage-plugin-gitlab |
| NPM: @bestsellerit/backstage-plugin-harbor | https://www.npmjs.com/package/@bestsellerit/backstage-plugin-harbor |
| NPM: @roadiehq/backstage-plugin-argo-cd | https://www.npmjs.com/package/@roadiehq/backstage-plugin-argo-cd |

---

*ADR-055 criado em 2026-03-05.*
*Status inicial: Proposed. Aguardando aprovacao do Tech Lead e Engineering Manager.*
*Apos aprovacao, status mudara para: Accepted.*
