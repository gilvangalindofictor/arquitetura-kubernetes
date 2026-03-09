# ADR-102 — Backstage IDP: Estratégia de Adoção e Arquitetura

| Campo | Valor |
|---|---|
| **Status** | Accepted |
| **Data** | 2026-03-05 |
| **Autores** | Mesa Técnica (DevOps, Security, SRE, FinOps) |
| **Revisores** | Arquitetura |
| **Relacionados** | ADR-101 (Vault+ESO), ADR-096 (Keycloak), ADR-092 (GitLab), ADR-098 (DNS) |

---

## Contexto

O ecossistema Kubernetes da empresa possui múltiplos times de desenvolvimento, cada um responsável por criar e manter seus próprios repositórios, pipelines CI/CD e integrações com serviços de plataforma (PostgreSQL, Redis, S3, Vault, Keycloak, Harbor). O processo atual é manual, inconsistente e depende de conhecimento tácito concentrado no time de plataforma.

Necessidades identificadas:
- Self-service para criação de repositórios e configuração inicial de aplicações
- Catálogo centralizado de serviços, APIs e equipes proprietárias
- Instrumentação de credenciais externas (APIs de terceiros) via Vault, sem exposição nos pipelines
- Padronização de templates para novos projetos (Helm chart, CI/CD, ExternalSecrets, ArgoCD Application)
- Visibilidade de saúde, dependências e owners dos serviços

## Decisão

Adotar **Backstage v1.48.0** (LTS track) como Internal Developer Portal (IDP), implantado via Helm chart `backstage/backstage 2.6.3` no namespace `staging-platform-backstage`, integrado com:

- **Keycloak** (OIDC): provider de identidade único, grupos → permissões RBAC no Backstage
- **GitLab 18.x**: SCM backend, catalog discovery, scaffolder target
- **Vault**: secrets das integrações externas consumidos em runtime; Scaffolder escreve paths iniciais via token scoped
- **Harbor**: catálogo de imagens via plugin `@bestsellerit/backstage-plugin-harbor`
- **ArgoCD**: visibilidade de deploys via `@backstage-community/plugin-argocd`
- **SonarQube**: qualidade de código via `@backstage-community/plugin-sonarqube`
- **Kubernetes**: visibilidade de pods/deployments dos serviços no catálogo

### Fluxo Dev Self-Service

```
Dev abre Backstage
  └─> Escolhe template (app Python ETL / app Node.js API / lib shared)
        └─> Preenche: nome, team, dependências (postgres, redis, s3), integrações externas
              └─> Scaffolder executa:
                    ├─> Cria repositório GitLab com estrutura padrão
                    ├─> Registra componente no catálogo (catalog-info.yaml)
                    ├─> Cria namespace K8s + ExternalSecrets skeleton
                    ├─> Escreve path Vault skeleton (secret/<env>/<app>/*)
                    ├─> Cria ArgoCD Application apontando para helm/platform-bootstrap
                    └─> Notifica Slack com link do repo + ArgoCD app
```

### Credenciais de APIs Externas — Fluxo Vault-First

```
Credenciais externas (API Keys, usuário/senha) → NUNCA em CI/CD vars
  └─> Escritas no Vault por: humano (1ª vez) ou Backstage Scaffolder (skeleton)
        └─> ExternalSecrets sincroniza Vault → K8s Secret (refreshInterval: 1h)
              └─> Pod consome via envFrom secretRef
                    └─> Backstage exibe status de sync no catálogo do componente
```

## Alternativas Consideradas

| Alternativa | Motivo da Rejeição |
|---|---|
| Port CNCF (Kratix, Crossplane Composition) | Complexidade alta, curva longa, sem UI self-service |
| Internal tooling customizado | Custo de manutenção alto, sem ecossistema de plugins |
| Backstage SaaS (Roadie) | Dados do catálogo fora do perímetro, custo por seat |
| Backstage com backend legado | Removido em v1.31; todos os plugins devem usar `backend.add()` |

## Consequências

### Positivas

- Self-service reduz handoff plataforma→dev de dias para minutos
- Catálogo centralizado elimina "quem é dono disso?" em incidentes
- Templates enforce padrões: OTEL, ExternalSecrets, NetworkPolicy, HPA
- Vault-first elimina segredos em CI/CD vars (alinha com ADR-101)

### Riscos e Mitigações

| Risco | Mitigação |
|---|---|
| **CVE-2025-55285**: scaffolder-backend < 2.1.1 vaza secrets em logs | Fixar `@backstage/plugin-scaffolder-backend >= 2.1.1` no package.json |
| Linkerd mTLS bloqueia conexão com Harbor (sem sidecar) | Annotation `config.linkerd.io/skip-outbound-ports: "443"` no pod Backstage |
| Vault Scaffolder — sem action oficial para KV v2 write (RFC #32600 aberto) | Usar `@roadiehq/backstage-plugin-scaffolder-backend-module-http-request` ou custom action |
| Node.js 18/20 removidos desde Backstage v1.46 | Imagem base: `node:22-alpine` obrigatório |
| janus-idp arquivado (agosto 2025) | Substituído por `@bestsellerit/backstage-plugin-harbor` para Harbor |
| Plugins oficiais vault/sonarqube deprecated | Usar `@backstage-community/*` (community transfer completo) |
| Keycloak grupos → roles Backstage não é automático | Configurar `signIn.resolvers` com `emailMatchingUserEntityAnnotation` + GroupTransformer |

## Versões Fixadas (verificadas 2026-03-05)

| Componente | Versão |
|---|---|
| Backstage core | 1.48.0 |
| Node.js (imagem base) | 22 LTS (22-alpine) |
| Helm chart `backstage/backstage` | 2.6.3 |
| `@backstage/plugin-scaffolder-backend` | >= 2.1.1 (CVE-2025-55285) |
| `@backstage-community/plugin-vault` | latest (community fork) |
| `@backstage-community/plugin-sonarqube` | latest (community fork) |
| `@backstage-community/plugin-argocd` | latest |
| `@backstage/plugin-kubernetes` | latest |
| `@bestsellerit/backstage-plugin-harbor` | latest (substitui janus-idp) |
| `@roadiehq/backstage-plugin-scaffolder-backend-module-http-request` | latest (Vault KV write workaround) |
| PostgreSQL (backend) | RDS 16 (existente na plataforma) |
| Helm repo | `https://backstage.github.io/charts` |

## Recursos de Infraestrutura

| Recurso | Request | Limit | Justificativa |
|---|---|---|---|
| CPU (backstage pod) | 500m | 2000m | Scaffolder runs são CPU-intensivos |
| Memória (backstage pod) | 1Gi | 2Gi | Catálogo em memória + plugins |
| Réplicas (staging) | 2 | — | HA mínimo, PDB minAvailable=1 |
| Réplicas (prod) | 3 | — | HA com spread por AZ |
| PostgreSQL | Instância existente | — | Schema `backstage` isolado no RDS |

## Notas de Implementação

- Backend utiliza **new backend system** (`createBackend()` + `backend.add()`) — obrigatório desde v1.31
- Catálogo configurado com `catalog.providers.gitlab` para auto-discovery de `catalog-info.yaml`
- RBAC Backstage baseado em grupos Keycloak: `platform-admin` → owner, `developer` → member
- Deployment com `topologySpreadConstraints` por zona de disponibilidade
- Linkerd injection: `linkerd.io/inject: enabled`, com skip-outbound para Harbor (`443`)
- Kyverno PolicyException necessária para init container do Linkerd (NET_ADMIN)
