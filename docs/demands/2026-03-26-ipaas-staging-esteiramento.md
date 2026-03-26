# Demanda: Esteiramento iPaaS Staging — Sprint IaC

**Data**: 2026-03-26
**Status**: PLANEJAMENTO — Sprint IaC pendente
**Responsável**: DevOps Engineer / Platform Engineer
**GAP de referência**: GAP-IPAAS-STAGING-001
**Prioridade**: P1
**Escopo**: Staging APENAS — prod em segundo momento

---

## Objetivo

Realizar o esteiramento completo dos 10 componentes iPaaS no cluster EKS staging (`k8s-platform-prod`), criando todos os recursos IaC necessários:
namespaces, ArgoCD Applications, AppProject `integration`, Vault secrets, ExternalSecrets, GitLab CI/CD (`.gitlab-ci.yml`) para os 7 componentes que ainda não possuem, Helm charts (valores de staging) e manifests K8s de cada componente via Kustomize overlay.

---

## Contexto

### Estado Atual

| Item | Estado |
|------|--------|
| Namespace `staging-ipaas-*` | INEXISTENTE — apenas `prod-data-ipaas` existe (vazio, sem workloads) |
| ArgoCD Applications iPaaS | NENHUMA no staging-platform-argocd |
| AppProject `integration` | INEXISTENTE — domínio não cadastrado |
| Vault secrets iPaaS | AUSENTES — nenhum path `secret/staging/ipaas/*` criado |
| `.gitlab-ci.yml` por componente | 3/10 existem (AdminBFF, AdminUI, Partners) — 7/10 ausentes |
| Helm charts / K8s manifests | AUSENTES — apenas `.platform/manifest.yaml` existem por componente |
| Linkerd proxy injection | Comentado em staging main.tf (`staging-integration-ipaas`) |
| RDS database `ipaas` | AUSENTE — banco não criado no RDS compartilhado |

### Referência ao Estado Prod

O namespace `prod-data-ipaas` existe no cluster com label `environment=production` mas está **completamente vazio** (sem deployments, services, configmaps, externalsecrets ou ingresses). Foi criado antecipadamente via Terraform mas nunca recebeu workloads.

### Padrão de Onboarding de Referência (Hatch ETL / VemSoft ETL)

- **AppProject**: `data` (já existe) — para iPaaS será necessário criar AppProject `integration`
- **ArgoCD Application**: aponta para `k8s/overlays/staging` no repositório GitLab do componente
- **Namespace naming**: `staging-<domain>-<service>` — para iPaaS: `staging-ipaas-*`
- **Vault secrets**: `secret/staging/<service>/database`, `.../redis`, `.../rabbitmq`, `.../keycloak`
- **ExternalSecrets**: criados via Kustomize no overlay de staging
- **Repositórios GitLab**: `http://gitlab.staging.internal/corporate-domains/integration/<component>.git`

---

## Componentes iPaaS Identificados (10/10)

| Componente | Tipo (manifest) | Dockerfile | .gitlab-ci.yml | K8s manifests | Ingress |
|------------|-----------------|-----------|----------------|---------------|---------|
| iPaaS.Gateway | api-rest | EXISTE | AUSENTE | AUSENTE | SIM — `ipaas-gateway.staging.internal` |
| iPaaS.AdminBFF | api-rest | EXISTE | EXISTE | AUSENTE (deploy comentado) | SIM — `ipaas-adminbff.staging.internal` |
| iPaaS.AdminUI | frontend | EXISTE | EXISTE | AUSENTE (deploy comentado) | SIM — `ipaas-adminui.staging.internal` |
| iPaaS.Orchestrator.Bancarization | worker | EXISTE | AUSENTE | AUSENTE | NAO |
| iPaaS.Compliance | api-rest | EXISTE | AUSENTE | AUSENTE | NAO |
| iPaaS.HealthScoring | worker | EXISTE | AUSENTE | K8s draft existe (`k8s/`) | NAO |
| iPaaS.Partners | api-rest | EXISTE | EXISTE | AUSENTE (deploy comentado) | NAO |
| iPaaS.Peer.BPO | api-rest | EXISTE | AUSENTE | AUSENTE | NAO |
| iPaaS.Peer.HBI | api-rest | EXISTE | AUSENTE | AUSENTE | NAO |
| iPaaS.Peer.Worker | worker | EXISTE | AUSENTE | AUSENTE | NAO |

**Observação sobre `.gitlab-ci.yml` existentes**: AdminBFF, AdminUI e Partners possuem `.gitlab-ci.yml` completos com stages `build/scan/package` mas o **stage `deploy` está comentado**. O bloco de deploy precisa ser implementado (via ArgoCD image update ou kubectl set image).

---

## Namespaces a Criar

Seguindo o padrão ADR-048 (`staging-<domain>-<service>`), com domínio `ipaas`:

| Namespace | Componentes | Labels obrigatórios |
|-----------|-------------|---------------------|
| `staging-ipaas-gateway` | iPaaS.Gateway | `environment=staging`, `domain=integration`, `linkerd.io/inject=enabled` |
| `staging-ipaas-adminbff` | iPaaS.AdminBFF | `environment=staging`, `domain=integration`, `linkerd.io/inject=enabled` |
| `staging-ipaas-adminui` | iPaaS.AdminUI | `environment=staging`, `domain=integration`, `linkerd.io/inject=enabled` |
| `staging-ipaas-orchestrator` | iPaaS.Orchestrator.Bancarization | `environment=staging`, `domain=integration`, `linkerd.io/inject=enabled` |
| `staging-ipaas-compliance` | iPaaS.Compliance | `environment=staging`, `domain=integration`, `linkerd.io/inject=enabled` |
| `staging-ipaas-healthscoring` | iPaaS.HealthScoring | `environment=staging`, `domain=integration`, `linkerd.io/inject=enabled` |
| `staging-ipaas-partners` | iPaaS.Partners | `environment=staging`, `domain=integration`, `linkerd.io/inject=enabled` |
| `staging-ipaas-peerbpo` | iPaaS.Peer.BPO | `environment=staging`, `domain=integration`, `linkerd.io/inject=enabled` |
| `staging-ipaas-peerhbi` | iPaaS.Peer.HBI | `environment=staging`, `domain=integration`, `linkerd.io/inject=enabled` |
| `staging-ipaas-peerworker` | iPaaS.Peer.Worker | `environment=staging`, `domain=integration`, `linkerd.io/inject=enabled` |

**Decisão de Namespace Alternativa** (a discutir): por ser plataforma integrada com forte interdependência de service discovery, avaliar uso de namespace único `staging-ipaas` para todos os componentes (simplicidade de NetworkPolicy e Service DNS), versus namespaces separados por componente (isolamento maior, padrão Hatch/VemSoft). Recomendação: **namespace único** `staging-ipaas` + subconta por label `app.kubernetes.io/component`.

---

## ArgoCD Applications a Criar

### Pré-requisito: AppProject `integration`

O AppProject `data` (existente) cobre `staging-data-*` / `prod-data-*`. O domínio iPaaS usa o domínio `integration` (conforme `.platform/manifest.yaml` de todos os componentes: `domain: integration`). É necessário criar o AppProject `integration` no `staging-platform-argocd`.

**AppProject `integration` — especificação mínima**:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: integration
  namespace: staging-platform-argocd
spec:
  description: "AppProject para o domínio integration (iPaaS Consignado)"
  sourceRepos:
    - "https://gitlab.staging.internal/corporate-domains/integration/*"
    - "http://gitlab.staging.internal/corporate-domains/integration/*"
  destinations:
    - namespace: "staging-ipaas-*"
      server: https://kubernetes.default.svc
    - namespace: "prod-ipaas-*"
      server: https://kubernetes.default.svc
  # namespaceResourceWhitelist: equivalente ao AppProject data (Deployment, Service, ConfigMap,
  # Secret, Ingress, HPA, PDB, SA, Role, RoleBinding, NetworkPolicy, ExternalSecret, Namespace)
  clusterResourceWhitelist:
    - group: ""
      kind: Namespace
```

### Applications por Componente (10 Applications)

| Application | Namespace destino | Repo GitLab | Path | Branch |
|-------------|-------------------|-------------|------|--------|
| `staging-ipaas-gateway` | `staging-ipaas-gateway` (ou `staging-ipaas`) | `/corporate-domains/integration/ipaas-gateway.git` | `k8s/overlays/staging` | `gitops/staging` |
| `staging-ipaas-adminbff` | `staging-ipaas-adminbff` | `/corporate-domains/integration/ipaas-adminbff.git` | `k8s/overlays/staging` | `gitops/staging` |
| `staging-ipaas-adminui` | `staging-ipaas-adminui` | `/corporate-domains/integration/ipaas-adminui.git` | `k8s/overlays/staging` | `gitops/staging` |
| `staging-ipaas-orchestrator` | `staging-ipaas-orchestrator` | `/corporate-domains/integration/ipaas-orchestrator.git` | `k8s/overlays/staging` | `gitops/staging` |
| `staging-ipaas-compliance` | `staging-ipaas-compliance` | `/corporate-domains/integration/ipaas-compliance.git` | `k8s/overlays/staging` | `gitops/staging` |
| `staging-ipaas-healthscoring` | `staging-ipaas-healthscoring` | `/corporate-domains/integration/ipaas-healthscoring.git` | `k8s/overlays/staging` | `gitops/staging` |
| `staging-ipaas-partners` | `staging-ipaas-partners` | `/corporate-domains/integration/ipaas-partners.git` | `k8s/overlays/staging` | `gitops/staging` |
| `staging-ipaas-peerbpo` | `staging-ipaas-peerbpo` | `/corporate-domains/integration/ipaas-peerbpo.git` | `k8s/overlays/staging` | `gitops/staging` |
| `staging-ipaas-peerhbi` | `staging-ipaas-peerhbi` | `/corporate-domains/integration/ipaas-peerhbi.git` | `k8s/overlays/staging` | `gitops/staging` |
| `staging-ipaas-peerworker` | `staging-ipaas-peerworker` | `/corporate-domains/integration/ipaas-peerworker.git` | `k8s/overlays/staging` | `gitops/staging` |

---

## Vault Secrets a Criar (por serviço)

### Padrão de paths (seguindo hatch-etl como referência)

Todos os paths ficam sob `secret/staging/ipaas/<componente>/`:

```
secret/staging/ipaas/database        → DATABASE_URL, DATABASE_HOST, DATABASE_NAME, DATABASE_USER, DATABASE_PASSWORD
secret/staging/ipaas/redis           → REDIS_URL, REDIS_PASSWORD
secret/staging/ipaas/rabbitmq        → RABBITMQ_HOST, RABBITMQ_USER, RABBITMQ_PASSWORD, RABBITMQ_VHOST
secret/staging/ipaas/keycloak        → KEYCLOAK_CLIENT_SECRET (realm "ipaas"), KEYCLOAK_REALM_URL
secret/staging/ipaas/compliance      → ENCRYPTION_KEY (AES-256-GCM), ENCRYPTION_KEY_ID
secret/staging/ipaas/hbi             → HBI_CLIENT_ID, HBI_CLIENT_SECRET, HBI_BASE_URL (por tenant — estrutura a definir)
secret/staging/ipaas/bpo             → BPO_WEBHOOK_SECRET (HMAC-SHA256)
secret/staging/ipaas/orchestrator    → ELSA_ENCRYPTION_KEY, WOLVERINEFX_TRANSPORT_URI
```

### Banco de dados iPaaS no RDS compartilhado

O RDS staging (`k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com`) é compartilhado entre staging e prod (GAP-SHARED-RDS pendente). Para iPaaS staging, criar:
- Database: `ipaas_staging`
- Usuário: `ipaas_staging_user`
- Schema: `ipaas` com Row-Level Security habilitado (multi-tenant)
- Tabelas criadas via EF Core migrations no startup do componente

### Configuração Vault TF (vault-config module)

Adicionar bloco no `modules/vault-config/main.tf` (similar ao padrão hatch_etl_*):
```hcl
# iPaaS Staging — Banco de dados (PostgreSQL RDS)
resource "vault_kv_secret_v2" "ipaas_database" {
  count = var.ipaas_enabled ? 1 : 0
  mount = vault_mount.kv.path
  name  = "${var.environment}/ipaas/database"
  data_json = jsonencode({
    host              = var.ipaas_db_host          # = module.postgresql_staging.rds_address
    port              = "5432"
    database          = var.ipaas_db_name          # = "ipaas_staging"
    username          = "ipaas_staging_user"
    password          = local.ipaas_db_password
    connection_string = "Host=${var.ipaas_db_host};Database=${var.ipaas_db_name};Username=ipaas_staging_user;Password=${local.ipaas_db_password}"
  })
}
```

---

## GitLab CI/CD — `.gitlab-ci.yml` por Componente

### Situação atual

| Componente | Status `.gitlab-ci.yml` | Ação necessária |
|------------|------------------------|-----------------|
| iPaaS.AdminBFF | EXISTE (deploy comentado) | Implementar stage deploy (ArgoCD image update) |
| iPaaS.AdminUI | EXISTE (deploy comentado) | Implementar stage deploy + variáveis VITE_* staging |
| iPaaS.Partners | EXISTE (deploy comentado) | Implementar stage deploy |
| iPaaS.Gateway | AUSENTE | CRIAR — .NET 10, stack idêntica ao AdminBFF |
| iPaaS.Orchestrator.Bancarization | AUSENTE | CRIAR — .NET 10, worker (sem Ingress) |
| iPaaS.Compliance | AUSENTE | CRIAR — .NET 10 |
| iPaaS.HealthScoring | AUSENTE | CRIAR — .NET 10, worker |
| iPaaS.Peer.BPO | AUSENTE | CRIAR — .NET 10 |
| iPaaS.Peer.HBI | AUSENTE | CRIAR — .NET 10 |
| iPaaS.Peer.Worker | AUSENTE | CRIAR — .NET 10, worker |

### Padrão CI adotado (referência: AdminBFF / Partners)

Stages: `build → scan → package → deploy`
- **build**: `dotnet build` com cache NuGet
- **scan**: SonarQube com dotnet-sonarscanner (allow_failure: true)
- **package**: Kaniko (rootless, privileged=false) → Harbor Registry
- **deploy**: ArgoCD app sync (OPÇÃO A — recomendada)

**Variáveis GitLab obrigatórias** (injetadas pelo runner):
- `HARBOR_REGISTRY`, `HARBOR_USER`, `HARBOR_PASSWORD`
- `SONAR_HOST_URL`, `SONAR_TOKEN`

**Variáveis por componente** (a configurar em Settings > CI/CD):
- `APP_NAME` — nome do Deployment K8s (ex: `ipaas-gateway`)
- `K8S_NAMESPACE` — namespace de destino (ex: `staging-ipaas-gateway`)
- `ARGOCD_APP_NAME` — nome da Application ArgoCD (ex: `staging-ipaas-gateway`)
- `ARGOCD_SERVER` — `argocd.staging.internal`
- `ARGOCD_TOKEN` — token de autenticação ArgoCD

### Variáveis específicas para iPaaS.AdminUI (build-time VITE_*)

```
VITE_KEYCLOAK_URL       = "http://keycloak.staging.internal/auth"
VITE_KEYCLOAK_REALM     = "ipaas"
VITE_KEYCLOAK_CLIENT_ID = "ipaas-admin-ui"
VITE_ADMIN_BFF_URL      = "http://ipaas-adminbff.staging.internal"
```

---

## Helm Charts / K8s Manifests por Componente

### Estrutura esperada (padrão Hatch ETL / VemSoft)

Cada repositório GitLab de componente deve conter:

```
k8s/
├── base/
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── externalsecret.yaml
│   ├── serviceaccount.yaml
│   ├── networkpolicy.yaml
│   └── (ingress.yaml — apenas para Gateway, AdminBFF, AdminUI)
└── overlays/
    └── staging/
        ├── kustomization.yaml          # patches de staging (replicas=1, resources mínimos)
        └── patches/
            ├── deployment-staging.yaml  # image tag, env vars staging-specific
            └── (hpa-staging.yaml)       # HPA se necessário
```

### Artefatos K8s por componente (situação atual)

| Componente | k8s/base existente | k8s/overlays/staging | Ação |
|------------|--------------------|----------------------|------|
| iPaaS.HealthScoring | PARCIAL (`k8s/deployment.yaml` draft) | AUSENTE | Migrar draft → base + criar overlay |
| Todos os demais | AUSENTE | AUSENTE | CRIAR do zero |

### Observações sobre o `deployment.yaml` draft do HealthScoring

O arquivo `/components/iPaaS.HealthScoring/k8s/deployment.yaml` existe mas usa:
- `namespace: ipaas` (incorreto — usar `staging-ipaas-healthscoring`)
- `image: ipaas/ipaas-health-scoring:1.0.0` (incorreto — usar Harbor ECR do cluster)
- Secrets via `secretKeyRef` diretamente (correto — serão preenchidos pelo ExternalSecret)

---

## Dependências de Infraestrutura

### Dependências existentes no cluster staging (PRONTAS)

| Dependência | Namespace | Status |
|-------------|-----------|--------|
| PostgreSQL RDS | RDS externo | Running — `k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com` |
| Redis | `staging-data-infrastructure` | Running — `redis.staging-data-infrastructure.svc.cluster.local:6379` |
| RabbitMQ | `staging-data-infrastructure` | Running — `k8s-platform-prod-rabbitmq.staging-data-infrastructure.svc.cluster.local:5672` |
| Keycloak | `staging-platform-keycloak` | Running — realm `platform` existe; realm `ipaas` precisa ser criado |
| Harbor Registry | `staging-platform-harbor` | Running — push de imagens OK |
| External Secrets Operator | `staging-security-externalsecrets` | Running — ClusterSecretStore `vault-backend` operacional |
| Vault | `staging-security-vault` | Running — token `VAULT_TOKEN_STAGING_REDACTED` |
| ArgoCD | `staging-platform-argocd` | Running — AppProject `data` existe; `integration` precisa ser criado |
| Linkerd | Running | CNI 14/14; namespaces iPaaS precisam ser anotados para inject |

### Dependências AUSENTES a criar

| Dependência | Ação | Responsável |
|-------------|------|-------------|
| Database `ipaas_staging` no RDS | CREATE DATABASE + user + schema + RLS | DBA / Terraform |
| Realm `ipaas` no Keycloak | Criar realm, clients (Gateway, AdminUI, AdminBFF, OrchAPI), usuários de teste | DevOps |
| AppProject `integration` no ArgoCD | Criar via kubectl apply | Platform Engineer |
| Repositórios GitLab para 10 componentes | Criar grupos + repos no GitLab staging | GitLab Admin |
| Vault secrets `secret/staging/ipaas/*` | Criar via vault-config module TF | Terraform Specialist |

---

## Keycloak: Realm iPaaS

O iPaaS usa Keycloak para OAuth2/OIDC (ADR-008). O realm `ipaas` precisa ser criado no Keycloak staging:

### Clients necessários

| Client ID | Tipo | Componente consumidor | Observação |
|-----------|------|-----------------------|-----------|
| `ipaas-gateway` | confidential | iPaaS.Gateway (JWT validation) | Valida tokens dos originadores |
| `ipaas-admin-ui` | public | iPaaS.AdminUI (SPA Keycloak.js) | Redirect URI: `http://ipaas-adminui.staging.internal/*` |
| `ipaas-admin-bff` | confidential | iPaaS.AdminBFF (client_credentials) | Token introspection |
| `ipaas-service` | confidential | Todos os serviços internos (service-to-service) | Roles: `partners:view`, `partners:edit`, etc. |

### Módulo TF existente: `keycloak-clients`

Existe o módulo `keycloak-clients` no diretório de módulos. Verificar se suporta criação de realm completo ou apenas clients adicionais.

---

## Linkerd: Proxy Injection

No `staging/main.tf`, a seção Linkerd já tem comentário preparado:

```hcl
# Habilitado quando namespaces ipaas/integration forem criados:
#   proxy_inject_namespaces = ["staging-integration-ipaas", "staging-integration-workers"]
proxy_inject_namespaces = []
```

**Ação**: Após criar os namespaces `staging-ipaas-*`, descomentar e atualizar `proxy_inject_namespaces` para incluir todos os namespaces iPaaS. Fazer rolling restart dos pods após inject.

---

## Sequência de Execução

### Fase 1 — Infraestrutura Base (Prerequisitos)

1. **[TF]** Criar database `ipaas_staging` no RDS (adicionar em `additional_databases` no módulo postgresql)
2. **[TF]** Criar Vault secrets `secret/staging/ipaas/*` via módulo `vault-config`
3. **[GitLab Admin]** Criar grupo `corporate-domains/integration` e 10 repositórios
4. **[kubectl]** Criar AppProject `integration` no ArgoCD
5. **[Keycloak]** Criar realm `ipaas` com 4 clients

### Fase 2 — Manifests K8s por Componente

Para cada componente (prioridade: Gateway > AdminBFF > Partners > Orchestrator > demais):

1. Criar estrutura `k8s/base/` + `k8s/overlays/staging/`
2. Criar `namespace.yaml`, `deployment.yaml`, `service.yaml`, `externalsecret.yaml`
3. Criar `ingress.yaml` (apenas Gateway, AdminBFF, AdminUI)
4. Push para branch `gitops/staging` do repositório GitLab

### Fase 3 — CI/CD (`.gitlab-ci.yml`)

Para cada componente sem CI:
1. Criar `.gitlab-ci.yml` seguindo padrão AdminBFF/Partners
2. Implementar stage `deploy` (ArgoCD sync) nos 3 CIs existentes
3. Configurar variáveis GitLab no repositório de cada componente
4. Executar pipeline de validação (build + scan + package)

### Fase 4 — ArgoCD Applications

Para cada componente:
1. Criar ArgoCD Application apontando para `k8s/overlays/staging`
2. Primeiro sync manual + verificar health status
3. Verificar pods Running + ExternalSecrets Synced

### Fase 5 — Linkerd Injection

1. Atualizar `proxy_inject_namespaces` no `staging/main.tf`
2. `terraform apply` módulo linkerd
3. Rolling restart de todos os pods iPaaS

### Fase 6 — Validação E2E

1. Verificar 10/10 pods Running
2. Verificar 10/10 ExternalSecrets Synced
3. Testar endpoint Gateway: `curl -k https://ipaas-gateway.staging.internal/health`
4. Testar AdminUI: `curl -k https://ipaas-adminui.staging.internal`
5. Executar Collection Postman (71 requests em `/docs/postman/`)

---

## Itens IaC — Estimativa de Esforço

| Categoria | Qtd de itens | Estimativa |
|-----------|-------------|------------|
| Namespaces (via namespace.yaml + TF) | 10 namespaces | 2h |
| AppProject `integration` | 1 recurso | 1h |
| Vault secrets (TF vault-config module) | ~8 paths + TF variables | 3h |
| ArgoCD Applications | 10 Applications | 3h |
| Manifests K8s (base + overlay) por componente | 10 componentes × ~6 arquivos | 15h |
| `.gitlab-ci.yml` novos (7 componentes) | 7 arquivos | 5h |
| `.gitlab-ci.yml` deploy stage nos 3 existentes | 3 arquivos | 2h |
| Realm Keycloak `ipaas` + 4 clients | 1 realm, 4 clients | 3h |
| Database RDS + usuário | 1 database + 1 user | 1h |
| Repositórios GitLab (10 repos + grupo) | 10 repos | 2h |
| Linkerd proxy_inject_namespaces update | 1 TF change | 0.5h |
| Variáveis GitLab CI por componente | 10 × ~5 vars | 2h |
| **TOTAL ESTIMADO** | **~70+ artefatos IaC** | **~39.5h (~1 sprint)** |

---

## Definition of Done

- [ ] Todos os 10 namespaces `staging-ipaas-*` existem no cluster com labels corretos
- [ ] AppProject `integration` criado no `staging-platform-argocd`
- [ ] 10 ArgoCD Applications criadas e em estado `Synced/Healthy`
- [ ] 10 componentes com pods `Running` (mínimo 1 replica cada)
- [ ] Todos os ExternalSecrets em estado `Synced` (0 erros)
- [ ] 10 `.gitlab-ci.yml` existem e stages build/scan/package passam
- [ ] Stage `deploy` implementado e funcional (ArgoCD sync por pipeline)
- [ ] Vault secrets criados em todos os paths `secret/staging/ipaas/*`
- [ ] Database `ipaas_staging` criado no RDS + migrations aplicadas
- [ ] Realm `ipaas` criado no Keycloak com 4 clients
- [ ] Gateway acessível em `https://ipaas-gateway.staging.internal/health` → HTTP 200
- [ ] AdminUI acessível em `https://ipaas-adminui.staging.internal` → HTTP 200
- [ ] Linkerd proxies injetados em todos os pods iPaaS
- [ ] Collection Postman (71 requests) executada sem erros críticos
- [ ] Zero GAPs P0 em auditoria pós-esteiramento

---

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Multi-tenant RLS no PostgreSQL requer migrations complexas | MEDIA | Aplicar migrations via EF Core + verificar Row-Level Security policies pós-deploy |
| Realm `ipaas` no Keycloak — ausência de client secrets nos Vault paths | ALTA | Criar realm ANTES dos ExternalSecrets; gerar e registrar client_secrets no Vault manualmente |
| Repositórios GitLab para 10 componentes ainda não existem | ALTA | Criar repositórios como primeira ação da sprint (bloqueador de todas as outras fases) |
| `AppProject integration` com sourceRepos precisando cobrir URLs http e https | MEDIA | Incluir ambos os prefixos (http:// e https://) como feito no AppProject `data` |
| Elsa Workflows no Orchestrator requer configurações específicas (ELSA_ENCRYPTION_KEY) | MEDIA | Documentar variáveis Elsa no `.platform/manifest.yaml` antes do deploy |
| iPaaS.Peer.HBI precisa de credenciais HBI por tenant (multi-tenant) | ALTA | Definir estrutura de secrets multi-tenant antes do deploy (1 secret por originador ou tabela criptografada) |
| RabbitMQ VHost e usuário iPaaS ainda não existem | MEDIA | Criar via RabbitMQ management API ou ConfigMap definitions.json antes do deploy |

---

## Referências

- `.platform/manifest.yaml` de todos os componentes: `/home/gilvangalindo/projects/Arquitetura/iPaaS/components/*/`
- Padrão Hatch ETL: `Arquitetura/Kubernetes/docs/plan/backstage/argocd-hatch-etl-application.yaml`
- Padrão VemSoft: ArgoCD Application `staging-data-vemsoft-etl` (kubectl get application)
- AppProject `data` referência: `kubectl get appproject data -n staging-platform-argocd -o yaml`
- TF vault-config module: `Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/modules/vault-config/main.tf`
- Staging main.tf: `Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/environments/staging/main.tf`
- Linkerd proxy_inject placeholder: `staging/main.tf` linha ~2805 (comentário `staging-integration-ipaas`)
- iPaaS CLAUDE.md (arquitetura + regras): `/home/gilvangalindo/projects/Arquitetura/iPaaS/CLAUDE.md`
- ADR-048 (naming conventions): Arquitetura/Kubernetes docs
- ADR-047 (domínios): Arquitetura/Kubernetes docs
- ADR-104 (CI/CD Onboarding via Manifesto Base): Arquitetura/Kubernetes docs
