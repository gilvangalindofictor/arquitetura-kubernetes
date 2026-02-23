# Guia de Onboarding de Aplicações - Corporate Domains

**Status**: ✅ Approved
**Data**: 2026-02-23
**Versão**: 2.0
**Responsável**: Platform Team

---

## 📋 Índice

1. [Visão Geral](#visão-geral)
2. [Pré-requisitos](#pré-requisitos)
3. [Processo de Onboarding](#processo-de-onboarding)
4. [Exemplo Completo: RPA Python](#exemplo-completo-rpa-python)
5. [Estrutura GitLab](#estrutura-gitlab)
6. [Naming Conventions](#naming-conventions)
7. [Provisionamento de Recursos](#provisionamento-de-recursos)
8. [CI/CD Pipeline](#cicd-pipeline)
9. [GitOps e ArgoCD](#gitops-e-argocd)
10. [Monitoramento](#monitoramento)
11. [Troubleshooting](#troubleshooting)

---

## Visão Geral

Este guia descreve o processo completo de **onboarding de uma nova aplicação** no ecossistema Kubernetes da empresa, desde a concepção até produção.

### Arquitetura de Governança

```
┌─────────────────────────────────────────────────────────────────┐
│                     CORPORATE DOMAINS                           │
│  ADR-047: Estrutura Corporativa de Domínios                    │
└─────────────────────────────────────────────────────────────────┘
         │
         ├─── Platform (Infra-as-Code, Observability, Security)
         ├─── Integration (iPaaS, APIs, Orchestrators)
         ├─── Data (ETL, Analytics, Data Lake)
         ├─── Operations (Process Management, Automation)
         └─── Shared-Services (Files, Notifications, Auth)

┌─────────────────────────────────────────────────────────────────┐
│                     NAMING CONVENTIONS                          │
│  ADR-048: Naming Conventions Determinísticas                   │
└─────────────────────────────────────────────────────────────────┘
  Namespace: {env}-{domain}-{produto}
  Exemplo:   staging-data-rpa-exemplo

┌─────────────────────────────────────────────────────────────────┐
│                     RBAC & GOVERNANCE                           │
│  ADR-049: Governança RBAC Domínios Corporativos               │
└─────────────────────────────────────────────────────────────────┘
  GitLab: Maintainer (domain-team), Reporter (platform-team)
  Kubernetes: edit (domain-team), view (platform-team)
```

### Fluxo Completo de Onboarding

```
┌───────────────┐
│ 1. Definição  │  → Domain, Produto, Stack, Dependências
└───────┬───────┘
        │
┌───────▼───────┐
│ 2. GitLab     │  → Criar repos: app + gitops
└───────┬───────┘
        │
┌───────▼───────┐
│ 3. Provisionar│  → PostgreSQL, Redis, RabbitMQ (se necessário)
└───────┬───────┘
        │
┌───────▼───────┐
│ 4. CI/CD      │  → Build, Test, Push Image, Update GitOps
└───────┬───────┘
        │
┌───────▼───────┐
│ 5. ArgoCD     │  → Deploy automático via GitOps
└───────┬───────┘
        │
┌───────▼───────┐
│ 6. Monitoring │  → Prometheus, Grafana, Loki
└───────────────┘
```

---

## Pré-requisitos

### Ferramentas de CLI

```bash
# Kubernetes
kubectl version --client  # >= 1.28

# Helm
helm version              # >= 3.12

# GitLab CLI
gitlab --version          # python-gitlab-cli

# ArgoCD CLI
argocd version --client   # >= 2.9

# Vault CLI
vault version             # >= 1.15

# Git
git --version             # >= 2.40
```

### Acessos Necessários

- [ ] **GitLab**: Membro do grupo `corporate-domains/{domain}` (Maintainer)
- [ ] **Kubernetes**: RBAC `edit` no namespace (via Keycloak)
- [ ] **Vault**: Política `secrets-{domain}-write`
- [ ] **ArgoCD**: Acesso ao project `{domain}`
- [ ] **Container Registry**: Push rights em `registry.empresa.com/{domain}/`

### Configuração Local

```bash
# 1. Configure GitLab token
export GITLAB_PRIVATE_TOKEN="<seu-token>"

# 2. Configure Kubeconfig
export KUBECONFIG=~/.kube/config-empresa

# 3. Login no ArgoCD
argocd login argocd.empresa.com --sso

# 4. Login no Vault
export VAULT_ADDR="https://vault.empresa.com"
vault login -method=oidc

# 5. Login no Container Registry
docker login registry.empresa.com
```

---

## Processo de Onboarding

### Passo 1: Definir Metadados da Aplicação

Preencha o formulário de definição:

```yaml
# app-definition.yaml
produto: rpa-exemplo
domain: data
stack:
  language: python
  version: "3.11"
  framework: fastapi
dependencies:
  postgresql: true
  redis: true
  rabbitmq: false
environments:
  - dev
  - staging
  - prod
owner: data-team
tech-lead: gilvan.galindo@empresa.com
```

### Passo 2: Executar Script de Onboarding

Usamos o script automatizado que criamos:

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/onboarding/

# Onboarding completo com PostgreSQL + Redis
./create-app.sh rpa-exemplo data staging \
  --needs-postgres \
  --needs-redis

# Output esperado:
# ✅ Namespace criado: staging-data-rpa-exemplo
# ✅ PostgreSQL provisionado
# ✅ Redis provisionado
# ✅ Repositórios GitLab criados
# ✅ ArgoCD Application criado
```

### Passo 3: Clonar Repositórios

```bash
# Clone repo da aplicação
git clone git@gitlab.empresa.com:corporate-domains/data/rpa-exemplo/rpa-exemplo.git
cd rpa-exemplo

# Clone repo gitops (em outro diretório)
git clone git@gitlab.empresa.com:corporate-domains/data/rpa-exemplo/rpa-exemplo-gitops.git
```

---

## Exemplo Completo: RPA Python

### Cenário

Vamos criar uma **aplicação RPA em Python** que:
- Extrai dados de uma API externa
- Processa e enriquece os dados
- Armazena em PostgreSQL
- Usa Redis para cache
- Expõe API REST para consulta

### Estrutura do Projeto

```
rpa-exemplo/
├── .gitlab-ci.yml           # CI/CD pipeline
├── Dockerfile               # Build da imagem
├── requirements.txt         # Dependências Python
├── src/
│   ├── __init__.py
│   ├── main.py             # FastAPI app
│   ├── database.py         # PostgreSQL connection
│   ├── cache.py            # Redis connection
│   └── rpa/
│       ├── extractor.py    # API extraction logic
│       └── processor.py    # Data processing
└── tests/
    ├── test_api.py
    └── test_rpa.py
```

### Código Python Completo

Ver exemplos completos em:
- [src/main.py](examples/rpa-python/src/main.py) - FastAPI app com health checks
- [src/database.py](examples/rpa-python/src/database.py) - PostgreSQL com SQLAlchemy
- [src/cache.py](examples/rpa-python/src/cache.py) - Redis connection
- [Dockerfile](examples/rpa-python/Dockerfile) - Multi-stage build
- [.gitlab-ci.yml](examples/rpa-python/.gitlab-ci.yml) - CI/CD pipeline completo

---

## Estrutura GitLab

### Hierarquia Completa

```
corporate-domains/                          (Group - ID: 1)
├── platform/                               (Group - ID: 10)
│   ├── observability/
│   │   ├── prometheus
│   │   └── prometheus-gitops
│   └── cicd/
│       ├── gitlab-runners
│       └── gitlab-runners-gitops
│
├── integration/                            (Group - ID: 20)
│   ├── ipaas-bff-rest/
│   │   ├── ipaas-bff-rest                 (App repo)
│   │   └── ipaas-bff-rest-gitops          (GitOps repo)
│   └── ipaas-orchestrator/
│
├── data/                                   (Group - ID: 30)
│   ├── rpa-exemplo/
│   │   ├── rpa-exemplo                    (App repo)
│   │   └── rpa-exemplo-gitops             (GitOps repo)
│   ├── hatch/
│   │   ├── hatch-api-gateway
│   │   ├── hatch-api-gateway-gitops
│   │   ├── hatch-etl
│   │   └── hatch-etl-gitops
│   └── vemsoft/
│
├── operations/                             (Group - ID: 40)
│   └── process-management/
│
└── shared-services/                        (Group - ID: 50)
    ├── files/
    │   ├── bucketconnector
    │   └── bucketconnector-gitops
    └── notification/
```

### RBAC por Domínio (ADR-049)

| Domain | Team | GitLab Role | Kubernetes Role |
|--------|------|-------------|-----------------|
| data | data-team | Maintainer | edit |
| data | platform-team | Reporter | view |
| data | security-team | Reporter | view |
| integration | integration-team | Maintainer | edit |
| integration | platform-team | Reporter | view |

---

## Naming Conventions

### Produtos (ADR-048)

```regex
^[a-z][a-z0-9-]{0,62}$
```

**Exemplos**:
- ✅ `rpa-exemplo`
- ✅ `hatch-api-gateway`
- ✅ `ipaas-bff-rest`
- ❌ `RPA_Exemplo` (uppercase, underscore)
- ❌ `123-app` (começa com número)

### Namespaces (ADR-048)

```
{env}-{domain}-{produto}
```

**Exemplos**:
- `staging-data-rpa-exemplo`
- `prod-integration-ipaas-bff-rest`
- `dev-shared-services-bucketconnector`

### Secrets (ADR-060, ADR-061, ADR-062)

```
{produto}-{tipo}-credentials
```

**Exemplos**:
- `rpa-exemplo-postgres-credentials`
- `rpa-exemplo-redis-credentials`
- `hatch-rabbitmq-credentials`

### Database Names (ADR-060)

```regex
^[a-z][a-z0-9_]{0,62}$
```

**Exemplos**:
- ✅ `rpa_exemplo` (snake_case)
- ✅ `hatch_api_gateway`
- ❌ `rpa-exemplo` (kebab-case não permitido no PostgreSQL)

### Redis Keys (ADR-061)

```
{domain}:{produto}:{resource}:{id}
```

**Exemplos**:
- `data:rpa-exemplo:session:user-123`
- `data:rpa-exemplo:cache:users-list`
- `integration:ipaas:queue:task-456`

### RabbitMQ (ADR-062)

**Exchanges**: `{domain}.{produto}.{type}`
- `data.rpa-exemplo.events`
- `data.rpa-exemplo.tasks`

**Queues**: `{domain}.{produto}.{queue-name}`
- `data.rpa-exemplo.extract-users`
- `data.rpa-exemplo.dlq`

**Routing Keys**: `{resource}.{action}[.{detail}]`
- `user.created`
- `user.updated.email`
- `task.completed`

---

## Provisionamento de Recursos

### PostgreSQL (ADR-060)

```bash
# Executado automaticamente por create-app.sh --needs-postgres
./scripts/onboarding/provision-database.sh rpa-exemplo staging-data-rpa-exemplo
```

**O que é criado**:
1. Database: `rpa_exemplo`
2. Users:
   - `rpa_exemplo_user` (read/write)
   - `rpa_exemplo_readonly` (read-only)
   - `rpa_exemplo_admin` (migrations)
3. Secret K8s: `rpa-exemplo-postgres-credentials`
4. Vault path: `secret/database/rpa-exemplo/postgres`
5. ExternalSecret para sync Vault ↔ K8s

**Connection String**:
```bash
postgresql://rpa_exemplo_user:{password}@rds-shared-cluster.prod-platform-databases.svc.cluster.local:5432/rpa_exemplo?sslmode=require
```

### Redis (ADR-061)

```bash
./scripts/onboarding/provision-redis.sh rpa-exemplo staging-data-rpa-exemplo staging
```

**O que é criado**:
1. Redis CR: `rpa-exemplo-redis` (via Redis Operator)
2. Configuração: Memory 512Mi, Replicas 2 (staging)
3. Secret K8s: `rpa-exemplo-redis-credentials`
4. Vault path: `secret/database/rpa-exemplo/redis`
5. ServiceMonitor (Prometheus)

**Connection String**:
```bash
redis://:{ password}@rpa-exemplo-redis.staging-data-rpa-exemplo.svc.cluster.local:6379/0
```

### RabbitMQ (ADR-062)

```bash
./scripts/onboarding/provision-rabbitmq.sh rpa-exemplo staging-data-rpa-exemplo data staging
```

**O que é criado**:
1. Virtual Host: `data.rpa-exemplo`
2. User: `rpa-exemplo-user`
3. Exchanges:
   - `data.rpa-exemplo.events` (topic)
   - `data.rpa-exemplo.tasks` (direct)
   - `data.rpa-exemplo.dlx` (dead letter)
4. Queue DLQ: `data.rpa-exemplo.dlq`
5. Secret K8s: `rpa-exemplo-rabbitmq-credentials`
6. Vault path: `secret/messaging/rpa-exemplo/rabbitmq`

**Connection String**:
```bash
amqp://rpa-exemplo-user:{password}@rabbitmq-shared-cluster.prod-platform-messaging.svc.cluster.local:5672/data.rpa-exemplo
```

---

## CI/CD Pipeline

### Stages

```
┌─────────────┐
│  Validate   │  → Linting, Governance checks
└──────┬──────┘
       │
┌──────▼──────┐
│    Build    │  → Docker build, push to registry
└──────┬──────┘
       │
┌──────▼──────┐
│    Test     │  → Unit, integration tests
└──────┬──────┘
       │
┌──────▼──────┐
│   Deploy    │  → Update GitOps repo (ArgoCD sync auto)
└─────────────┘
```

### Variáveis de Ambiente (GitLab CI/CD Settings)

```bash
# Registry
CI_REGISTRY_USER=gitlab-ci-token
CI_REGISTRY_PASSWORD=<token>

# GitOps deploy key
GITOPS_DEPLOY_KEY=<ssh-private-key>

# Opcional: Notifications
SLACK_WEBHOOK_URL=<webhook>
```

### Quality Gates

- **Linting**: flake8, black, mypy (Python)
- **Test Coverage**: Mínimo 80%
- **Security**: Trivy scan na imagem Docker
- **Governance**: Validação de naming conventions

---

## GitOps e ArgoCD

### ArgoCD Application

Criado automaticamente por `create-argocd-app.sh`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: staging-rpa-exemplo
  namespace: argocd
spec:
  project: data
  source:
    repoURL: https://gitlab.empresa.com/corporate-domains/data/rpa-exemplo/rpa-exemplo-gitops.git
    targetRevision: main
    path: overlays/staging
  destination:
    server: https://kubernetes.default.svc
    namespace: staging-data-rpa-exemplo
  syncPolicy:
    automated:
      prune: false
      selfHeal: true
```

### Sync Policy por Ambiente

| Env | Auto-Sync | Auto-Prune | Self-Heal | Approval |
|-----|-----------|------------|-----------|----------|
| dev | ✅ Yes | ✅ Yes | ✅ Yes | ❌ No |
| staging | ✅ Yes | ❌ No | ✅ Yes | ❌ No |
| prod | ❌ No | ❌ No | ❌ No | ✅ Manual |

### Comandos ArgoCD

```bash
# Ver status
argocd app get staging-rpa-exemplo

# Fazer sync manual (produção)
argocd app sync prod-rpa-exemplo

# Ver logs do sync
argocd app logs staging-rpa-exemplo --follow

# Rollback
argocd app rollback staging-rpa-exemplo

# Ver diff antes do sync
argocd app diff staging-rpa-exemplo
```

---

## Monitoramento

### Prometheus Metrics

A aplicação deve expor métricas no endpoint `/metrics`. Ver [ADR-067: Logging Standards](/docs/adr/adr-067-logging-standards-patterns.md) (futuro).

### ServiceMonitor (Prometheus Operator)

```yaml
# rpa-exemplo-gitops/base/servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: rpa-exemplo
  labels:
    app.kubernetes.io/name: rpa-exemplo
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: rpa-exemplo
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
```

### Grafana Dashboard

Dashboard automático disponível em:
```
https://grafana.empresa.com/d/rpa-exemplo
```

**Painéis**:
- Request rate (requests/sec)
- Latency (p50, p95, p99)
- Error rate (5xx responses)
- Database connections pool
- Redis hit/miss ratio
- RabbitMQ queue depth

---

## Troubleshooting

### Problema: Pod não inicia (CrashLoopBackOff)

```bash
# Ver logs
kubectl logs -n staging-data-rpa-exemplo -l app.kubernetes.io/name=rpa-exemplo

# Descrever pod
kubectl describe pod -n staging-data-rpa-exemplo -l app.kubernetes.io/name=rpa-exemplo

# Ver eventos
kubectl get events -n staging-data-rpa-exemplo --sort-by='.lastTimestamp'
```

**Causas comuns**:
1. ❌ Secret não encontrado → Verificar: `kubectl get secrets -n staging-data-rpa-exemplo`
2. ❌ Conexão com database falhou → Testar: `kubectl exec -it <pod> -- psql $DATABASE_URL`
3. ❌ Imagem Docker não existe → Verificar registry: `docker pull registry.empresa.com/data/rpa-exemplo:latest`

### Problema: ArgoCD não faz sync

```bash
# Ver status detalhado
argocd app get staging-rpa-exemplo

# Ver diff
argocd app diff staging-rpa-exemplo

# Forçar refresh
argocd app get staging-rpa-exemplo --refresh
```

**Causas comuns**:
1. ❌ GitOps repo sem mudanças → CI não atualizou image tag
2. ❌ Sync policy desabilitado → Sync manual necessário
3. ❌ Conflito no manifest → Ver diff e corrigir

### Problema: Database connection pool exhausted

```bash
# Ver pool stats
kubectl exec -it <pod> -n staging-data-rpa-exemplo -- python -c "
from src.database import engine
print(engine.pool.status())
"
```

**Solução**: Aumentar `pool_size` no `database.py` (ADR-060: padrão 10)

---

## Checklist de Onboarding

### Fase 1: Preparação
- [ ] Definir domain, produto, stack
- [ ] Verificar acessos (GitLab, K8s, Vault, ArgoCD)
- [ ] Instalar CLIs localmente

### Fase 2: Provisionamento
- [ ] Executar `create-app.sh` com flags corretas
- [ ] Verificar namespace criado: `kubectl get ns`
- [ ] Verificar secrets criados: `kubectl get secrets -n <namespace>`
- [ ] Verificar Vault paths: `vault kv list secret/database/`

### Fase 3: Desenvolvimento
- [ ] Clonar repositórios (app + gitops)
- [ ] Implementar aplicação com health checks
- [ ] Configurar Dockerfile
- [ ] Criar `.gitlab-ci.yml`
- [ ] Testar build local: `docker build -t test .`

### Fase 4: CI/CD
- [ ] Configurar variáveis no GitLab CI/CD Settings
- [ ] Commit e push para `main`
- [ ] Verificar pipeline execução
- [ ] Verificar imagem no registry

### Fase 5: Deploy
- [ ] GitOps repo atualizado automaticamente pelo CI
- [ ] ArgoCD detecta mudança e faz sync
- [ ] Verificar pods: `kubectl get pods -n <namespace>`
- [ ] Testar aplicação

### Fase 6: Monitoramento
- [ ] Verificar métricas no Prometheus
- [ ] Verificar dashboard no Grafana
- [ ] Configurar alertas críticos
- [ ] Testar notificações

### Fase 7: Documentação
- [ ] Atualizar README do repo app
- [ ] Documentar APIs (OpenAPI/Swagger)
- [ ] Criar runbook de operação
- [ ] Adicionar contato de tech lead

---

## Contatos e Suporte

| Área | Time | Contato |
|------|------|---------|
| Platform Engineering | platform-team | platform@empresa.com |
| Data Domain | data-team | data@empresa.com |
| Integration Domain | integration-team | integration@empresa.com |
| Security | security-team | security@empresa.com |
| Onboarding Support | Platform Team | Slack: #platform-support |

---

## Referências

- [ADR-047: Estrutura Corporativa de Domínios](/docs/adr/adr-047-estrutura-corporativa-dominios.md)
- [ADR-048: Naming Conventions Determinísticas](/docs/adr/adr-048-naming-conventions-deterministicas.md)
- [ADR-049: Governança RBAC Domínios Corporativos](/docs/adr/adr-049-governanca-rbac-dominios-corporativos.md)
- [ADR-060: PostgreSQL Governance Standards](/docs/adr/adr-060-postgresql-governance-standards.md)
- [ADR-061: Redis Governance Standards](/docs/adr/adr-061-redis-governance-standards.md)
- [ADR-062: RabbitMQ Governance Standards](/docs/adr/adr-062-rabbitmq-governance-standards.md)
- [GOVERNANCE.md](/docs/governance/GOVERNANCE.md)
- [RBAC Matrix](/docs/governance/rbac-matrix.md)
- [Onboarding Scripts](/scripts/onboarding/)

---

**Última Atualização**: 2026-02-23
**Versão**: 2.0
**Aprovado por**: Platform Team
