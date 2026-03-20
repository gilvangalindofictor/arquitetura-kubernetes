# ECR Pull-Through Cache — Arquitetura Completa para Docker Hub

**Data:** 2026-03-19
**Status:** PLANEJADO — Pendente PAT Docker Hub valido
**GAPs:** GAP-SEC-REGISTRY-02, GAP-SEC-REGISTRY-03
**Conta AWS:** 891377105802 | **Regiao:** us-east-1
**Cluster:** k8s-platform-prod (EKS 1.34)

---

## 1. Problema

Docker Hub rate limit (100 pulls/6h anonimo, 200 pulls/6h free account) afeta o cluster EKS que usa NAT Gateway com IP unico. Apos restart massivo (node drain, scale-up, FinOps UP/DOWN), 30 imagens Docker Hub atingem 429 Too Many Requests simultaneamente, causando ImagePullBackOff em 48 pods.

Harbor Proxy Cache NAO funciona como registry mirror para kubelet/containerd porque containerd roda no host (node EC2), fora do pod network do cluster — nao resolve DNS do CoreDNS (Licao 9).

---

## 2. Solucao: ECR Pull-Through Cache

ECR Pull-Through Cache e um recurso nativo AWS que:

1. Cria uma regra de cache apontando para upstream registry (Docker Hub)
2. Na primeira vez que uma imagem e solicitada via URI ECR, o ECR faz pull do upstream e armazena localmente
3. Pulls subsequentes vem do ECR (mesma regiao, sem rate limit Docker Hub)
4. ECR verifica atualizacoes no upstream a cada 24h automaticamente
5. containerd no node resolve `891377105802.dkr.ecr.us-east-1.amazonaws.com` via DNS publico/VPC — sem dependencia de DNS do cluster

**URI de pull:** `891377105802.dkr.ecr.us-east-1.amazonaws.com/docker-hub/<repository>:<tag>`

**Exemplos:**
```
# Docker Hub: library/nginx:1.25
# ECR:        891377105802.dkr.ecr.us-east-1.amazonaws.com/docker-hub/library/nginx:1.25

# Docker Hub: hashicorp/vault:1.15.4
# ECR:        891377105802.dkr.ecr.us-east-1.amazonaws.com/docker-hub/hashicorp/vault:1.15.4

# Docker Hub: grafana/grafana:10.x
# ECR:        891377105802.dkr.ecr.us-east-1.amazonaws.com/docker-hub/grafana/grafana:10.x
```

---

## 3. Arquitetura de Componentes

```
┌─────────────────────────────────────────────────────────────────┐
│  EKS Node (containerd)                                         │
│                                                                 │
│  kubelet pull image:                                            │
│  891377105802.dkr.ecr.us-east-1.amazonaws.com/docker-hub/X:tag │
│       │                                                         │
│       ▼                                                         │
│  ECR Auth (node role: AmazonEC2ContainerRegistryReadOnly        │
│           + ecr:BatchImportUpstreamImage + ecr:CreateRepository)│
└───────┬─────────────────────────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────────────────┐
│  Amazon ECR Private Registry (us-east-1)          │
│                                                   │
│  Pull-Through Cache Rule:                         │
│    prefix: docker-hub                             │
│    upstream: registry-1.docker.io                 │
│    credential_arn: secretsmanager:ecr-pullthr...  │
│                                                   │
│  Repository Creation Template:                    │
│    prefix: docker-hub                             │
│    applied_for: PULL_THROUGH_CACHE                │
│    lifecycle_policy: expire untagged > 30 days    │
│    image_tag_mutability: MUTABLE                  │
│    encryption: AES256                             │
│                                                   │
│  Auto-created repos:                              │
│    docker-hub/library/nginx                       │
│    docker-hub/library/busybox                     │
│    docker-hub/hashicorp/vault                     │
│    docker-hub/grafana/grafana                     │
│    docker-hub/grafana/loki                        │
│    docker-hub/grafana/tempo                       │
│    docker-hub/grafana/promtail                    │
│    ...                                            │
└───────┬───────────────────────────────────────────┘
        │ (first pull only, then cached)
        ▼
┌───────────────────────────────────────────────────┐
│  Docker Hub (registry-1.docker.io)                │
│                                                   │
│  Authenticated via Secrets Manager PAT            │
│  (200 pulls/6h per authenticated account)         │
│  Only accessed on cache miss / 24h refresh        │
└───────────────────────────────────────────────────┘
```

---

## 4. Componentes AWS Necessarios

### 4.1 Secrets Manager — Docker Hub PAT

```
Secret Name:  ecr-pullthroughcache/docker-hub
Encryption:   aws/secretsmanager (KMS default — obrigatorio, CMK nao suportado)
Format:       {"username":"<dockerhub-user>","accessToken":"<PAT-read-only>"}
```

**IMPORTANTE:** Usar Personal Access Token (PAT) do Docker Hub, NAO senha da conta. Gerar em: hub.docker.com > Account Settings > Security > New Access Token (scope: Read-only).

### 4.2 Pull-Through Cache Rule

```
ECR Repository Prefix:  docker-hub
Upstream Registry URL:  registry-1.docker.io
Credential ARN:         arn:aws:secretsmanager:us-east-1:891377105802:secret:ecr-pullthroughcache/docker-hub-XXXXXX
```

### 4.3 Repository Creation Template

Template automatiza a configuracao de repositorios criados pelo pull-through cache:

```
Prefix:               docker-hub
Applied For:          PULL_THROUGH_CACHE
Image Tag Mutability: MUTABLE (obrigatorio — ECR atualiza tags a cada 24h)
Encryption:           AES256
Lifecycle Policy:     Expire untagged images > 30 days
Resource Tags:        ManagedBy=ecr-pull-through-cache, Source=docker-hub
```

**AVISO:** Tag immutability MUTABLE e obrigatorio. Se IMMUTABLE, ECR nao consegue atualizar imagens com a mesma tag (ex: `latest`, `1.15.4`).

### 4.4 IAM — Node Role (adicional)

O node role `k8s-platform-eks-node-role` ja possui `AmazonEC2ContainerRegistryReadOnly` (pull standard). Para pull-through cache, precisa adicionalmente:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECRPullThroughCache",
      "Effect": "Allow",
      "Action": [
        "ecr:BatchImportUpstreamImage",
        "ecr:CreateRepository"
      ],
      "Resource": "arn:aws:ecr:us-east-1:891377105802:repository/docker-hub/*"
    }
  ]
}
```

**NOTA:** `ecr:CreateRepository` e necessario apenas na primeira pull de cada imagem (ECR cria o repositorio automaticamente). `ecr:BatchImportUpstreamImage` e necessario em toda pull que trigger cache refresh.

### 4.5 Service-Linked Role (automatico)

AWS cria automaticamente a service-linked role `AWSServiceRoleForECRPullThroughCache` na primeira criacao de uma pull-through cache rule. Esta role permite ao ECR:

- Criar repositorios
- Ler secrets do Secrets Manager
- Push de imagens cacheadas

---

## 5. Registries Upstream e Regras Necessarias

O cluster usa imagens de MULTIPLAS registries. ECR Pull-Through Cache suporta regras separadas por upstream:

### 5.1 Docker Hub (PRIORITARIO — causa do rate limit)

| Prefixo ECR | Upstream URL | Credenciais | Status |
|-------------|-------------|-------------|--------|
| `docker-hub` | `registry-1.docker.io` | Secrets Manager PAT | PENDENTE PAT |

### 5.2 Quay.io (sem autenticacao necessaria)

| Prefixo ECR | Upstream URL | Credenciais | Status |
|-------------|-------------|-------------|--------|
| `quay` | `quay.io` | Nenhuma (publico) | PLANEJADO |

### 5.3 GitHub Container Registry (autenticacao necessaria)

| Prefixo ECR | Upstream URL | Credenciais | Status |
|-------------|-------------|-------------|--------|
| `ghcr` | `ghcr.io` | Secrets Manager PAT GitHub | PLANEJADO |

### 5.4 Registries que NAO precisam de pull-through cache

| Registry | Motivo |
|----------|--------|
| `registry.k8s.io` | ECR Pull-Through suporta como "Kubernetes container image registry" (sem auth) |
| `cr.l5d.io` (Linkerd) | Acesso via Linkerd Helm chart (baixo volume de pulls) |
| `gcr.io` (Kaniko) | Usado apenas em CI/CD runners (nao afeta pods do cluster) |
| `registry.gitlab.com` | GitLab chart usa propria registry (nao Docker Hub) |

---

## 6. Inventario Completo de Imagens Docker Hub Afetadas

### 6.1 Imagens Docker Hub (docker.io) — 30 imagens estimadas

As imagens abaixo sao referenciadas direta ou indiretamente (via chart defaults) pelos Helm charts do cluster:

#### Categoria: Observabilidade (Grafana Charts)

| # | Imagem Docker Hub | Helm Chart | Namespace |
|---|-------------------|------------|-----------|
| 1 | `grafana/grafana:11.x` | kube-prometheus-stack (subchart) | monitoring |
| 2 | `grafana/loki:3.x` | loki | monitoring |
| 3 | `grafana/tempo:2.x` | tempo-distributed | monitoring |
| 4 | `grafana/promtail:3.x` | promtail | monitoring |

#### Categoria: Prometheus Ecosystem (kube-prometheus-stack)

| # | Imagem Docker Hub | Helm Chart | Namespace |
|---|-------------------|------------|-----------|
| 5 | `prom/prometheus:v2.x` | kube-prometheus-stack | monitoring |
| 6 | `prom/alertmanager:v0.x` | kube-prometheus-stack | monitoring |
| 7 | `jimmidyson/configmap-reload:v0.x` | kube-prometheus-stack | monitoring |
| 8 | `prom/pushgateway:v1.x` | prometheus-pushgateway | monitoring |

**NOTA:** kube-prometheus-stack chart v69.4.0 usa `quay.io/prometheus/alertmanager` e `quay.io/prometheus-operator/admission-webhook` por padrao. Verificar se a versao deployada usa docker.io ou quay.io via `kubectl get pods -n monitoring -o jsonpath='{..image}'`.

#### Categoria: HashiCorp

| # | Imagem Docker Hub | Helm Chart | Namespace |
|---|-------------------|------------|-----------|
| 9 | `hashicorp/vault:1.15.4` | vault | staging-security-vault / prod-security-vault |
| 10 | `hashicorp/vault-k8s:1.x` | vault (injector) | staging-security-vault |

#### Categoria: SonarQube

| # | Imagem Docker Hub | Helm Chart | Namespace |
|---|-------------------|------------|-----------|
| 11 | `sonarqube:10.3.0-community` | sonarqube | staging-platform-sonarqube |

#### Categoria: OpenTelemetry

| # | Imagem Docker Hub | Helm Chart | Namespace |
|---|-------------------|------------|-----------|
| 12 | `otel/opentelemetry-collector-contrib:0.108.0` | opentelemetry-collector | monitoring |

#### Categoria: Velero

| # | Imagem Docker Hub | Helm Chart | Namespace |
|---|-------------------|------------|-----------|
| 13 | `velero/velero:v1.15.0` | velero | staging-platform-velero |
| 14 | `velero/velero-plugin-for-aws:v1.x` | velero (init container) | staging-platform-velero |
| 15 | `bitnami/kubectl:latest` | velero (upgrade job) | staging-platform-velero |

#### Categoria: Init Containers / Utilities

| # | Imagem Docker Hub | Helm Chart | Namespace |
|---|-------------------|------------|-----------|
| 16 | `busybox:1.36` | keycloak (wait-for-db) | staging-platform-keycloak |
| 17 | `busybox:latest` | kube-prometheus-stack (init) | monitoring |
| 18 | `node:22-bookworm-slim` | backstage (install-oidc init) | staging-platform-backstage |

#### Categoria: GitLab CI

| # | Imagem Docker Hub | Helm Chart | Namespace |
|---|-------------------|------------|-----------|
| 19 | `ubuntu:22.04` | gitlab (runner default image) | staging-platform-gitlab |

#### Categoria: Harbor (goharbor)

| # | Imagem Docker Hub | Helm Chart | Namespace |
|---|-------------------|------------|-----------|
| 20 | `goharbor/harbor-core:v2.x` | harbor | harbor-system |
| 21 | `goharbor/harbor-jobservice:v2.x` | harbor | harbor-system |
| 22 | `goharbor/harbor-portal:v2.x` | harbor | harbor-system |
| 23 | `goharbor/harbor-registry:v2.x` | harbor | harbor-system |
| 24 | `goharbor/harbor-registryctl:v2.x` | harbor | harbor-system |
| 25 | `goharbor/harbor-db:v2.x` | harbor | harbor-system |
| 26 | `goharbor/harbor-trivy-adapter:v2.x` | harbor | harbor-system |
| 27 | `goharbor/harbor-exporter:v2.x` | harbor | harbor-system |
| 28 | `goharbor/nginx-photon:v2.x` | harbor | harbor-system |

#### Categoria: Backstage

| # | Imagem Docker Hub | Helm Chart | Namespace |
|---|-------------------|------------|-----------|
| 29 | `backstage custom image` | backstage | staging-platform-backstage |

#### Categoria: Argo

| # | Imagem Docker Hub | Helm Chart | Namespace |
|---|-------------------|------------|-----------|
| 30 | `argoproj/argo-rollouts:v1.x` | argo-rollouts | staging-platform-argocd |

### 6.2 Imagens Quay.io (nao Docker Hub, mas tambem vulneraveis)

| # | Imagem Quay.io | Helm Chart | Namespace |
|---|----------------|------------|-----------|
| 1 | `quay.io/keycloak/keycloak:26.5.1` | keycloakx | staging-platform-keycloak |
| 2 | `quay.io/argoproj/argocd:v2.10.0` | argo-cd | staging-platform-argocd |
| 3 | `quay.io/argoproj/argocd-applicationset:v2.x` | argo-cd | staging-platform-argocd |
| 4 | `quay.io/opstree/redis-operator:v0.23.0` | redis-operator | staging-data-redis |
| 5 | `quay.io/opstree/redis:v8.4.0` | redis (CRD) | staging-data-redis |
| 6 | `quay.io/opstree/redis-exporter:latest` | redis (CRD) | staging-data-redis |
| 7 | `quay.io/prometheus-operator/prometheus-operator:v0.x` | kube-prometheus-stack | monitoring |
| 8 | `quay.io/prometheus/alertmanager:v0.31.1` | kube-prometheus-stack | monitoring |
| 9 | `quay.io/kiwigrid/k8s-sidecar:1.x` | kube-prometheus-stack (Grafana) | monitoring |
| 10 | `quay.io/prometheus/node-exporter:v1.x` | kube-prometheus-stack | monitoring |
| 11 | `quay.io/prometheus-community/postgres-exporter:v0.x` | kube-prometheus-stack | monitoring |
| 12 | `quay.io/brancz/kube-rbac-proxy:v0.x` | kube-prometheus-stack | monitoring |

### 6.3 Imagens GHCR (GitHub Container Registry)

| # | Imagem GHCR | Helm Chart | Namespace |
|---|-------------|------------|-----------|
| 1 | `ghcr.io/external-secrets/external-secrets:v0.9.11` | external-secrets | staging-security-eso |
| 2 | `ghcr.io/jkroepke/kube-webhook-certgen:1.7.8` | kube-prometheus-stack | monitoring |

---

## 7. Transparencia do Pull-Through Cache (NAO e transparente)

**RESPOSTA CRITICA: ECR Pull-Through Cache NAO e transparente para os pods.**

Os pods devem referenciar as imagens usando a URI completa do ECR:

```
# ANTES (Docker Hub direto):
image: hashicorp/vault:1.15.4

# DEPOIS (ECR Pull-Through):
image: 891377105802.dkr.ecr.us-east-1.amazonaws.com/docker-hub/hashicorp/vault:1.15.4
```

**Impacto:** TODA referencia de imagem Docker Hub nos Helm values DEVE ser atualizada.

### 7.1 Estrategia de Migracao de Image References

**Opcao A — Rewrite nos Helm Values (RECOMENDADA)**

Atualizar os `values.yaml.tpl` de cada modulo Terraform para usar a URI ECR:

```yaml
# Vault values.yaml.tpl — ANTES:
server:
  image:
    repository: "hashicorp/vault"
    tag: "1.15.4"

# Vault values.yaml.tpl — DEPOIS:
server:
  image:
    repository: "891377105802.dkr.ecr.us-east-1.amazonaws.com/docker-hub/hashicorp/vault"
    tag: "1.15.4"
```

**Opcao B — Kyverno MutatingPolicy (ALTERNATIVA para chart defaults)**

Para imagens que vem dos chart defaults (nao configuradas nos values), criar uma Kyverno MutatingPolicy que reescreve `docker.io/*` para a URI ECR automaticamente:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: redirect-dockerhub-to-ecr
spec:
  rules:
    - name: redirect-dockerhub
      match:
        any:
          - resources:
              kinds: ["Pod"]
      mutate:
        foreach:
          - list: "request.object.spec.containers"
            patchStrategicMerge:
              spec:
                containers:
                  - name: "{{ element.name }}"
                    image: "{{ regex_replace_all('^docker\\.io/(.+)$', element.image, '891377105802.dkr.ecr.us-east-1.amazonaws.com/docker-hub/$1') }}"
          - list: "request.object.spec.initContainers"
            patchStrategicMerge:
              spec:
                initContainers:
                  - name: "{{ element.name }}"
                    image: "{{ regex_replace_all('^docker\\.io/(.+)$', element.image, '891377105802.dkr.ecr.us-east-1.amazonaws.com/docker-hub/$1') }}"
```

**RECOMENDACAO:** Usar Opcao A para imagens explicitamente configuradas nos values + Opcao B como safety net para imagens de chart defaults que escapam dos values.

### 7.2 Modulos TF que Precisam de Atualizacao

| Modulo | Arquivo | Imagem(ns) a Atualizar |
|--------|---------|----------------------|
| vault | values.yaml.tpl | `hashicorp/vault:1.15.4` |
| sonarqube | values.yaml.tpl | `sonarqube:10.3.0-community` |
| keycloak | values.yaml.tpl | `busybox:1.36` (init container) |
| opentelemetry-collector | values.yaml.tpl | `otel/opentelemetry-collector-contrib:0.108.0` |
| velero-helm | main.tf | `velero/velero-plugin-for-aws:v1.x` |
| backstage | values.yaml.tpl | Registry ja parametrizado via `${image_registry}` |
| gitlab | values.yaml.tpl | `ubuntu:22.04` (runner image) |
| kube-prometheus-stack | main.tf | Chart defaults (usar Kyverno mutating) |

---

## 8. Estimativa de Custos

### 8.1 ECR Storage

| Item | Estimativa |
|------|-----------|
| Imagens Docker Hub cacheadas (~30 imagens) | ~15-25 GB |
| Imagens Quay.io cacheadas (~12 imagens) | ~8-15 GB |
| Imagens GHCR cacheadas (~2 imagens) | ~1-2 GB |
| **Total storage estimado** | **~25-40 GB** |
| **Custo mensal** ($0.10/GB) | **$2.50 - $4.00/mes** |

### 8.2 Data Transfer

| Item | Custo |
|------|-------|
| ECR → EKS nodes (mesma regiao us-east-1) | **$0.00** (gratuito intra-regiao) |
| Docker Hub → ECR (first pull + 24h refresh) | Insignificante (AWS paga upstream pull) |

### 8.3 Custo Total Estimado

```
ECR Storage:     ~$3.00/mes = ~$36/ano
Data Transfer:   $0.00 (intra-regiao)
Secrets Manager: $0.40/mes per secret × 1-3 secrets = ~$0.40-$1.20/mes

TOTAL ESTIMADO: ~$4.00/mes = ~$48/ano
```

**ROI:** Custo do rate limit = downtime (48 pods, servicos degradados, intervenção manual). $48/ano e insignificante comparado ao custo de indisponibilidade.

---

## 9. Recursos Terraform Necessarios

### 9.1 Novo Modulo: `modules/ecr-pull-through-cache/`

```
modules/ecr-pull-through-cache/
  ├── main.tf          # Pull-through cache rules + repo creation templates
  ├── variables.tf     # Configurable upstream registries
  ├── outputs.tf       # ECR URI prefixes for use in other modules
  ├── versions.tf      # Provider constraints
  └── iam.tf           # Additional IAM policy for node role
```

### 9.2 Recursos Terraform

```hcl
# --- main.tf ---

# 1. Secrets Manager Secret (Docker Hub PAT)
resource "aws_secretsmanager_secret" "docker_hub" {
  name        = "ecr-pullthroughcache/docker-hub"
  description = "Docker Hub PAT for ECR Pull-Through Cache"
  # MUST use default aws/secretsmanager key (CMK not supported)
}

resource "aws_secretsmanager_secret_version" "docker_hub" {
  secret_id = aws_secretsmanager_secret.docker_hub.id
  secret_string = jsonencode({
    username    = var.docker_hub_username
    accessToken = var.docker_hub_pat
  })
}

# 2. Pull-Through Cache Rule — Docker Hub
resource "aws_ecr_pull_through_cache_rule" "docker_hub" {
  ecr_repository_prefix = "docker-hub"
  upstream_registry_url = "registry-1.docker.io"
  credential_arn        = aws_secretsmanager_secret.docker_hub.arn
}

# 3. Pull-Through Cache Rule — Quay.io (no auth needed)
resource "aws_ecr_pull_through_cache_rule" "quay" {
  ecr_repository_prefix = "quay"
  upstream_registry_url = "quay.io"
}

# 4. Pull-Through Cache Rule — GHCR (auth needed)
resource "aws_ecr_pull_through_cache_rule" "ghcr" {
  ecr_repository_prefix = "ghcr"
  upstream_registry_url = "ghcr.io"
  credential_arn        = aws_secretsmanager_secret.ghcr.arn
}

# 5. Repository Creation Template — Docker Hub
resource "aws_ecr_repository_creation_template" "docker_hub" {
  prefix      = "docker-hub"
  applied_for = ["PULL_THROUGH_CACHE"]

  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images older than 30 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 30
        }
        action = {
          type = "expire"
        }
      }
    ]
  })

  resource_tags = {
    ManagedBy = "ecr-pull-through-cache"
    Source    = "docker-hub"
    Module   = "ecr-pull-through-cache"
  }
}

# 6. Repository Creation Template — Quay
resource "aws_ecr_repository_creation_template" "quay" {
  prefix      = "quay"
  applied_for = ["PULL_THROUGH_CACHE"]

  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images older than 30 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 30
        }
        action = {
          type = "expire"
        }
      }
    ]
  })

  resource_tags = {
    ManagedBy = "ecr-pull-through-cache"
    Source    = "quay"
    Module   = "ecr-pull-through-cache"
  }
}
```

### 9.3 IAM Policy (iam.tf)

```hcl
# Additional IAM policy for EKS node role — pull-through cache permissions
resource "aws_iam_policy" "ecr_pull_through_cache" {
  name        = "ecr-pull-through-cache-node-policy"
  description = "Allows EKS nodes to trigger ECR pull-through cache (create repos + import images)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRPullThroughCacheDockerHub"
        Effect = "Allow"
        Action = [
          "ecr:BatchImportUpstreamImage",
          "ecr:CreateRepository"
        ]
        Resource = [
          "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/docker-hub/*",
          "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/quay/*",
          "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/ghcr/*"
        ]
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "ecr_pull_through_cache" {
  role       = var.node_role_name  # "k8s-platform-eks-node-role"
  policy_arn = aws_iam_policy.ecr_pull_through_cache.arn
}
```

### 9.4 Variables (variables.tf)

```hcl
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws_account_id" {
  type    = string
  default = "891377105802"
}

variable "docker_hub_username" {
  type        = string
  description = "Docker Hub username for authenticated pulls"
  sensitive   = true
}

variable "docker_hub_pat" {
  type        = string
  description = "Docker Hub Personal Access Token (Read-only scope)"
  sensitive   = true
}

variable "node_role_name" {
  type        = string
  description = "Name of the EKS node IAM role"
  default     = "k8s-platform-eks-node-role"
}

variable "enable_ghcr" {
  type        = bool
  description = "Enable GHCR pull-through cache rule"
  default     = false
}

variable "ghcr_username" {
  type        = string
  description = "GitHub username for GHCR authenticated pulls"
  sensitive   = true
  default     = ""
}

variable "ghcr_pat" {
  type        = string
  description = "GitHub PAT with read:packages scope"
  sensitive   = true
  default     = ""
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
```

### 9.5 Outputs (outputs.tf)

```hcl
output "ecr_docker_hub_prefix" {
  description = "ECR URI prefix for Docker Hub images"
  value       = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/docker-hub"
}

output "ecr_quay_prefix" {
  description = "ECR URI prefix for Quay.io images"
  value       = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/quay"
}

output "ecr_ghcr_prefix" {
  description = "ECR URI prefix for GHCR images"
  value       = var.enable_ghcr ? "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/ghcr" : ""
}

output "pull_through_cache_rules" {
  description = "Map of pull-through cache rules created"
  value = {
    docker_hub = aws_ecr_pull_through_cache_rule.docker_hub.ecr_repository_prefix
    quay       = aws_ecr_pull_through_cache_rule.quay.ecr_repository_prefix
  }
}

output "node_policy_arn" {
  description = "ARN of the IAM policy attached to node role for pull-through cache"
  value       = aws_iam_policy.ecr_pull_through_cache.arn
}
```

---

## 10. Plano de Migracao (Faseado)

### Fase 1 — Infraestrutura Base (Pre-requisito)

1. Gerar PAT no Docker Hub (scope: Read-only)
2. `terraform apply` do modulo `ecr-pull-through-cache` (secret + rule + template + IAM)
3. Validar: `aws ecr describe-pull-through-cache-rules`
4. Teste manual: `docker pull 891377105802.dkr.ecr.us-east-1.amazonaws.com/docker-hub/library/nginx:latest`
5. Verificar repositorio auto-criado: `aws ecr describe-repositories --repository-names docker-hub/library/nginx`

### Fase 2 — Migracao de Imagens Explicitas nos Values

Atualizar os `values.yaml.tpl` de cada modulo para usar URI ECR. Ordem de prioridade:

1. **vault** — `hashicorp/vault:1.15.4`
2. **sonarqube** — `sonarqube:10.3.0-community` (ja foi feito manual)
3. **keycloak** — `busybox:1.36` (init container)
4. **opentelemetry-collector** — `otel/opentelemetry-collector-contrib:0.108.0`
5. **velero** — `velero/velero-plugin-for-aws:v1.x`
6. **backstage** — `node:22-bookworm-slim` (init container)
7. **gitlab** — `ubuntu:22.04` (runner default image)

### Fase 3 — Kyverno MutatingPolicy (Safety Net)

Deploy da ClusterPolicy `redirect-dockerhub-to-ecr` para interceptar imagens que fogem dos values (chart defaults, sidecars, etc.).

### Fase 4 — Quay.io + GHCR

1. Pull-through cache rule para `quay.io` (sem auth)
2. Pull-through cache rule para `ghcr.io` (com auth — GitHub PAT)
3. Atualizar imagens Quay (keycloak, argocd, redis, prometheus)
4. Atualizar imagens GHCR (external-secrets)

### Fase 5 — Validacao e Monitoramento

1. Restart controlado de todos os pods (`kubectl rollout restart`)
2. Monitorar ImagePullBackOff: `kubectl get events --field-selector reason=Failed -A`
3. Verificar repos ECR criados: `aws ecr describe-repositories | grep docker-hub`
4. Dashboard Grafana: latencia de pulls, cache hit rate

---

## 11. Impacto no containerd/Nodes

**NAO e necessaria configuracao adicional nos nodes (containerd).**

- Os nodes EKS ja possuem autenticacao automatica para ECR via instance profile
- O EKS AMI (AL2023) inclui ECR credential helper no containerd config
- kubelet autentica no ECR usando a role `k8s-platform-eks-node-role`
- A unica mudanca necessaria e adicionar as permissoes `ecr:BatchImportUpstreamImage` e `ecr:CreateRepository` ao node role (feito via IAM policy na Fase 1)

---

## 12. Riscos e Mitigacoes

| Risco | Mitigacao |
|-------|----------|
| PAT Docker Hub expira | Alertar via Secrets Manager rotation schedule + CloudWatch |
| ECR Pull-Through Cache indisponivel | Imagens ja cacheadas continuam disponiveis; fallback manual para Docker Hub |
| Storage ECR cresce indefinidamente | Lifecycle policy (untagged > 30 dias) + Repository Creation Template |
| Kyverno MutatingPolicy conflito | Testar em namespace de staging isolado antes de cluster-wide |
| Pull-through cache nao suporta imagens multi-arch | Comportamento documentado: puxa manifest list completo (storage maior) |

---

## 13. Comandos de Validacao

```bash
# Verificar cache rules existentes
aws ecr describe-pull-through-cache-rules --region us-east-1

# Listar repos criados pelo pull-through cache
aws ecr describe-repositories --region us-east-1 | jq -r '.repositories[].repositoryName' | grep '^docker-hub/'

# Testar pull manual via ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 891377105802.dkr.ecr.us-east-1.amazonaws.com
docker pull 891377105802.dkr.ecr.us-east-1.amazonaws.com/docker-hub/library/nginx:latest

# Verificar node role permissions
aws iam list-attached-role-policies --role-name k8s-platform-eks-node-role
aws iam get-policy-version --policy-arn <ecr-pull-through-cache-policy-arn> --version-id v1

# Verificar pods com ImagePullBackOff apos migracao
kubectl get pods -A --field-selector status.phase!=Running | grep -v Completed

# Listar todas as imagens em uso no cluster (para auditoria)
kubectl get pods -A -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{range .spec.initContainers[*]}{.image}{"\n"}{end}{end}' | sort -u
```

---

*Documento produzido pelo AWS Specialist — Sessao 2026-03-19*
*Referencias: Licao 9, Licao 10, Licao 17 (strategies-consolidado.md)*
