# ArgoCD ApplicationSets - GitOps Patterns

Este diretório contém ApplicationSets que implementam patterns avançados de GitOps para automação de deploy e gerenciamento de aplicações na plataforma Kubernetes.

## Índice

- [Visão Geral](#visão-geral)
- [ApplicationSets Disponíveis](#applicationsets-disponíveis)
  - [1. Git Generator Pattern](#1-git-generator-pattern)
  - [2. List Generator Pattern](#2-list-generator-pattern)
  - [3. Cluster Generator Pattern](#3-cluster-generator-pattern)
- [Como Usar](#como-usar)
- [Exemplos Práticos](#exemplos-práticos)
- [Troubleshooting](#troubleshooting)
- [Referências](#referências)

---

## Visão Geral

ApplicationSets são um recurso do ArgoCD que permite gerar múltiplas Applications automaticamente usando generators (Git, List, Cluster, Matrix, etc.). Isso elimina a necessidade de criar Applications manualmente e garante consistência no deploy.

**Benefícios:**
- **Zero manual intervention:** Novos apps são criados automaticamente via Git commits
- **Consistência:** Mesmas políticas de sync, RBAC e configurações para todas as apps
- **Multi-environment/Multi-cluster:** Deploy automático em staging/production/clusters
- **Self-service:** Devs criam novos apps apenas commitando estrutura de diretórios

---

## ApplicationSets Disponíveis

### 1. Git Generator Pattern

**Arquivo:** `platform-services-multi-env.yaml`

**Descrição:** Auto-descobre aplicações baseado em estrutura de diretórios Git e gera Applications por ambiente.

**Pattern:**
```
domains/*/manifests/staging/   → Cria Application: {{domain}}-staging
domains/*/manifests/production/ → Cria Application: {{domain}}-production
```

**Exemplo de estrutura:**
```
domains/
├── observability/
│   └── manifests/
│       ├── staging/
│       │   ├── kustomization.yaml
│       │   └── values-staging.yaml
│       └── production/
│           ├── kustomization.yaml
│           └── values-production.yaml
└── data-services/
    └── manifests/
        ├── staging/
        │   └── values-staging.yaml
        └── production/
            └── values-production.yaml
```

**Applications geradas automaticamente:**
- `observability-staging` → namespace: `observability-staging`
- `observability-production` → namespace: `observability-production`
- `data-services-staging` → namespace: `data-services-staging`
- `data-services-production` → namespace: `data-services-production`

**Sync Policy:**
- Automated: `prune: true, selfHeal: true`
- Auto-cria namespaces
- Deleta resources órfãos (não mais em Git)

---

### 2. List Generator Pattern

**Arquivo:** `data-services-catalog.yaml`

**Descrição:** Define um catálogo explícito de serviços de dados (PostgreSQL, Redis, RabbitMQ) com deploy ordenado via sync waves.

**Use Case:** Deploy de serviços padrão com configurações específicas e ordenação de dependências.

**Serviços no catálogo:**

| Service | Application Name | Namespace | Sync Wave | Descrição |
|---------|------------------|-----------|-----------|-----------|
| PostgreSQL | `postgresql-connection` | `data-services` | 1 | RDS connection configs |
| Redis | `redis-cluster` | `data-services` | 2 | Redis cluster (OT-Container-Kit) |
| RabbitMQ | `rabbitmq-cluster` | `data-services` | 3 | RabbitMQ cluster (Operator) |

**Sync Waves:** Garante que PostgreSQL deploy antes de Redis, e Redis antes de RabbitMQ.

**Como adicionar novo serviço:**

```yaml
# Editar data-services-catalog.yaml
generators:
- list:
    elements:
    # Adicionar novo elemento
    - name: mongodb-cluster
      service: mongodb
      namespace: data-services
      path: domains/data-services/infra/helm/mongodb
      syncWave: "4"
      description: "MongoDB cluster"
```

**Commit e push:** ArgoCD detecta mudança e cria nova Application automaticamente.

---

### 3. Cluster Generator Pattern

**Arquivo:** `monitoring-multi-cluster.yaml`

**Descrição:** Prepara para deploy multi-cluster do monitoring stack (Prometheus, Grafana, Alertmanager) em clusters com label `monitoring: enabled`.

**Pattern:** Detecta clusters via ArgoCD cluster secrets e gera Application por cluster.

**Configuração por cluster:**

```yaml
# Cluster context injected into template
values:
  clusterName: staging-us-east-1
  environment: staging
  clusterServer: https://kubernetes.default.svc

# Application name: monitoring-stack-staging-us-east-1
# Namespace: monitoring
```

**Helm values override por cluster:**
- Usa `values-{{environment}}.yaml` (ex: `values-staging.yaml`)
- Injeta labels de cluster no Prometheus externalLabels
- Configura Grafana root URL por cluster
- Roteia alertas para Slack channel por environment

**Como habilitar monitoring em novo cluster:**

1. Registrar cluster no ArgoCD:
```bash
argocd cluster add CONTEXT_NAME --label monitoring=enabled --label environment=production
```

2. ArgoCD detecta novo cluster e cria Application automaticamente.

**Atualmente:** Apenas staging cluster existe. Pattern preparado para scale-out futuro.

---

## Como Usar

### Deploy dos ApplicationSets

```bash
# 1. Aplicar todos os ApplicationSets
kubectl apply -f domains/cicd-platform/infra/argocd/applicationsets/

# 2. Verificar ApplicationSets criados
kubectl get applicationsets -n argocd

# Saída esperada:
# NAME                          AGE
# platform-services-multi-env   1m
# data-services-catalog         1m
# monitoring-multi-cluster      1m

# 3. Verificar Applications geradas
kubectl get applications -n argocd

# 4. Ver detalhes de um ApplicationSet
kubectl describe applicationset platform-services-multi-env -n argocd
```

### Validação no ArgoCD UI

1. Acesse ArgoCD UI: `https://argocd.platform.internal`
2. Navegue para **Settings → ApplicationSets**
3. Visualize ApplicationSets e Applications geradas
4. Verifique status de sync (Synced/OutOfSync)

---

## Exemplos Práticos

### Exemplo 1: Adicionar Nova App via Git Commit (Git Generator)

**Objetivo:** Criar nova aplicação `security-platform` com deploy automático em staging/production.

**Passos:**

```bash
# 1. Criar estrutura de diretórios
mkdir -p domains/security-platform/manifests/{staging,production}

# 2. Criar manifests de staging
cat > domains/security-platform/manifests/staging/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
- service.yaml
namespace: security-platform-staging
EOF

# 3. Criar deployment
cat > domains/security-platform/manifests/staging/deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: security-platform
spec:
  replicas: 2
  selector:
    matchLabels:
      app: security-platform
  template:
    metadata:
      labels:
        app: security-platform
    spec:
      containers:
      - name: app
        image: security-platform:v1.0.0
        ports:
        - containerPort: 8080
EOF

# 4. Commit e push
git add domains/security-platform/
git commit -m "feat: add security-platform manifests for staging"
git push

# 5. ArgoCD detecta nova estrutura (polling: 3min)
# Application criada automaticamente: security-platform-staging
```

**Resultado:** Application `security-platform-staging` criada e sincronizada automaticamente.

---

### Exemplo 2: Override Values por Environment

**Cenário:** Configurar resources diferentes em staging vs production.

**Estrutura:**

```
domains/observability/manifests/
├── staging/
│   └── values-overrides.yaml
└── production/
    └── values-overrides.yaml
```

**staging/values-overrides.yaml:**
```yaml
prometheus:
  prometheusSpec:
    resources:
      requests:
        cpu: 500m
        memory: 2Gi
    retention: 7d
```

**production/values-overrides.yaml:**
```yaml
prometheus:
  prometheusSpec:
    resources:
      requests:
        cpu: 2000m
        memory: 8Gi
    retention: 30d
```

**Commit:** ArgoCD detecta e aplica overrides por ambiente automaticamente.

---

### Exemplo 3: Adicionar Serviço ao Data Services Catalog

**Objetivo:** Adicionar MongoDB ao catálogo de data services.

**Passos:**

```bash
# 1. Editar data-services-catalog.yaml
# Adicionar elemento MongoDB na lista:

- name: mongodb-cluster
  service: mongodb
  namespace: data-services
  path: domains/data-services/infra/helm/mongodb
  syncWave: "4"
  description: "MongoDB cluster for document storage"

# 2. Commit e push
git add domains/cicd-platform/infra/argocd/applicationsets/data-services-catalog.yaml
git commit -m "feat(data-services): add MongoDB to catalog"
git push

# 3. Verificar Application criada
kubectl get application mongodb-cluster -n argocd
```

**Resultado:** Application `mongodb-cluster` criada com sync wave 4 (após RabbitMQ).

---

## Troubleshooting

### ApplicationSet não gera Applications

**Sintomas:**
```bash
kubectl get applicationset platform-services-multi-env -n argocd
# Status: 0 Applications generated
```

**Diagnóstico:**

```bash
# 1. Ver eventos do ApplicationSet
kubectl describe applicationset platform-services-multi-env -n argocd

# 2. Verificar logs do ApplicationSet controller
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller

# 3. Verificar se path existe no Git
git ls-tree -r --name-only HEAD | grep domains/.*/manifests
```

**Soluções comuns:**
- **Path não existe:** Criar estrutura de diretórios esperada pelo generator
- **Selector não match:** Verificar labels/annotations no cluster/resources
- **Repo não acessível:** Verificar credentials do ArgoCD para o Git repo

---

### Applications geradas ficam OutOfSync

**Sintomas:**
```bash
kubectl get applications -n argocd
# Status: OutOfSync
```

**Diagnóstico:**

```bash
# Ver diff do sync
argocd app diff APPLICATION_NAME

# Ver detalhes do erro
kubectl describe application APPLICATION_NAME -n argocd
```

**Soluções:**
- **Namespace não existe:** Adicionar `CreateNamespace=true` em syncOptions
- **CRDs faltando:** Deploy CRDs antes (sync wave -1)
- **Permissões RBAC:** Verificar AppProject permite os resources

---

### Cluster Generator não detecta cluster

**Sintomas:**
```bash
kubectl get applicationset monitoring-multi-cluster -n argocd
# Status: 0 clusters matched
```

**Diagnóstico:**

```bash
# Listar clusters registrados no ArgoCD
argocd cluster list

# Ver labels do cluster
kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=cluster -o yaml
```

**Solução:**

```bash
# Adicionar label monitoring=enabled no cluster
argocd cluster set CONTEXT_NAME --label monitoring=enabled
```

---

### Application gera conflito com Application existente

**Sintomas:**
```bash
# Error: Application "monitoring-stack" already exists
```

**Solução:**

1. **PAUSE o ApplicationSet** para evitar conflitos:
```bash
kubectl patch applicationset monitoring-multi-cluster -n argocd \
  --type merge -p '{"spec":{"template":{"spec":{"syncPolicy":{"automated":null}}}}}'
```

2. Deletar Application conflitante OU renomear template:
```bash
# Opção 1: Deletar existente
kubectl delete application monitoring-stack -n argocd

# Opção 2: Renomear template no ApplicationSet
# name: 'monitoring-stack-v2-{{values.clusterName}}'
```

3. Re-habilitar automated sync.

---

## Referências

**ArgoCD ApplicationSets Docs:**
- [ApplicationSets Overview](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
- [Git Generator](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Git/)
- [List Generator](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-List/)
- [Cluster Generator](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Cluster/)
- [Template Fields](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Template/)

**Repo GitOps:**
- Repo: `https://github.com/gilvangalindofictor/arquitetura-kubernetes.git`
- Branch: `main`

**Support:**
- Issues: Ver logbook `docs/logbook/2026-02-24-gap006-applicationsets.md`
- Platform team: `#platform-team` Slack channel

---

**Última atualização:** 2026-02-24
**ArgoCD Version:** v2.10.0
**Kubernetes Version:** 1.34
