# ADR-107: ECR Public Gallery como Upstream (Eliminacao de Docker Hub)

| Campo | Valor |
|-------|-------|
| ID | ADR-107 |
| Data | 2026-03-19 |
| Status | Accepted |
| Contexto | k8s-platform-prod, EKS 1.34, conta 891377105802, us-east-1 |
| Autor | Documentation Specialist |
| Revisores | Platform Team, Mesa Tecnica |
| Tags | ecr, docker-hub, ecr-public, registry, upstream, rate-limit |

---

## Contexto e Problema

O ECR Pull-Through Cache (ADR-106) requer definicao de **upstreams** — os registries publicos de onde as imagens serao cacheadas. Para imagens Docker Hub, existem duas opcoes de upstream:

1. **Docker Hub direto** (`registry-1.docker.io`) — requer Docker Hub Personal Access Token (PAT), armazenado no AWS Secrets Manager; sujeito a rate limit por token; PAT expira e precisa de rotacao.

2. **ECR Public Gallery** (`public.ecr.aws`) — AWS mantém mirror completo de todas as **Docker Official Library images** em `public.ecr.aws/docker/library/`. Sem credenciais, sem rate limit AWS-to-AWS, sem custo de Secrets Manager.

### Docker Official Library no ECR Public

AWS publica e mantem todas as imagens Docker Official Library em:
```
public.ecr.aws/docker/library/<image>:<tag>
```

Exemplos:
- `public.ecr.aws/docker/library/nginx:1.25`
- `public.ecr.aws/docker/library/postgres:16`
- `public.ecr.aws/docker/library/redis:7`
- `public.ecr.aws/docker/library/vault:1.15`

Alem das Docker Official images, o ECR Public Gallery hospeda imagens de vendors (Bitnami, HashiCorp, etc.) em namespaces dedicados:
- `public.ecr.aws/bitnami/*`
- `public.ecr.aws/hashicorp/*`

---

## Opcoes Avaliadas

### Opcao A: Docker Hub como upstream do Pull-Through Cache

**REJEITADO**

- Requer criacao de Docker Hub PAT (token pessoal ou de organizacao)
- PAT deve ser armazenado no AWS Secrets Manager (~$0.40/mes + rotacao)
- PAT expira — se expirar sem rotacao, pull-through para de funcionar silenciosamente
- Rate limit do Docker Hub ainda se aplica (200 pulls/6h para authenticated users)
- Risco operacional: single point of failure na credencial

### Opcao B: ECR Public Gallery como upstream principal

**ACEITO**

- Zero credenciais — nao precisa de PAT, nem Secrets Manager
- Zero rate limit para trafego AWS-to-AWS (ECR Public -> ECR Private na mesma regiao)
- Zero custo de Secrets Manager
- Zero risco de expiracao de credenciais
- AWS mantem as imagens sincronizadas com Docker Hub automaticamente
- Cobertura: todas Docker Official Library images + vendors populares

---

## Decisao

Usar **ECR Public Gallery** (`public.ecr.aws`) como upstream principal para o ECR Pull-Through Cache. **Docker Hub NAO sera usado como upstream.**

### Upstreams Configurados

| Rule Prefix | Upstream Registry | Uso | Credenciais |
|-------------|-------------------|-----|-------------|
| `ecr-public` | `public.ecr.aws` | Docker Official Library + vendors AWS/Bitnami/HashiCorp | Nenhuma |
| `quay` | `quay.io` | Imagens Red Hat, CoreOS, Prometheus, etc. | Nenhuma |
| `ghcr` | `ghcr.io` | Imagens GitHub (Actions runners, tools) | Nenhuma |
| `k8s` | `registry.k8s.io` | Imagens Kubernetes (kube-proxy, coredns, pause, metrics-server) | Nenhuma |

**Total de credenciais gerenciadas: 0**

### Mapeamento de Imagens Docker Hub -> ECR Pull-Through

O prefixo final no ECR Private sera:
```
891377105802.dkr.ecr.us-east-1.amazonaws.com/<rule-prefix>/<upstream-path>:<tag>
```

Exemplos de remapeamento:
```
# Antes (Docker Hub direto — sujeito a rate limit)
nginx:1.25
postgres:16
redis:7
hashicorp/vault:1.15

# Depois (ECR Pull-Through via ECR Public)
891377105802.dkr.ecr.us-east-1.amazonaws.com/ecr-public/docker/library/nginx:1.25
891377105802.dkr.ecr.us-east-1.amazonaws.com/ecr-public/docker/library/postgres:16
891377105802.dkr.ecr.us-east-1.amazonaws.com/ecr-public/docker/library/redis:7
891377105802.dkr.ecr.us-east-1.amazonaws.com/ecr-public/hashicorp/vault:1.15

# Imagens de outros registries
quay.io/prometheus/node-exporter:v1.7
→ 891377105802.dkr.ecr.us-east-1.amazonaws.com/quay/prometheus/node-exporter:v1.7

ghcr.io/external-secrets/external-secrets:v0.9
→ 891377105802.dkr.ecr.us-east-1.amazonaws.com/ghcr/external-secrets/external-secrets:v0.9

registry.k8s.io/kube-proxy:v1.34
→ 891377105802.dkr.ecr.us-east-1.amazonaws.com/k8s/kube-proxy:v1.34
```

---

## Kyverno MutatingPolicy (Safety Net)

Para garantir que nenhum pod faca pull direto do Docker Hub (mesmo que um desenvolvedor esqueca de atualizar o manifesto), sera implementada uma **Kyverno MutatingPolicy** que reescreve automaticamente as image references:

```yaml
# Regra conceitual (implementacao detalhada no Terraform)
match:
  resources:
    kinds: [Pod]
mutate:
  patchStrategicMerge:
    spec:
      containers:
        - (image): "!891377105802.dkr.ecr.*"  # se NAO for ECR
          image: "891377105802.dkr.ecr.us-east-1.amazonaws.com/ecr-public/docker/library/{{image}}"
```

Excecoes da policy:
- Imagens ja com prefixo ECR (`891377105802.dkr.ecr.*`)
- Imagens Harbor internas (`harbor.alvocard.com/*`)
- Namespaces de sistema (`kube-system`, `kube-node-lease`)

---

## Consequencias

### Positivas

- **Zero credenciais para registries publicos**: nenhum PAT, nenhum Secrets Manager, nenhum risco de expiracao
- **Zero rate limit**: trafego AWS-to-AWS entre ECR Public e ECR Private nao tem throttling
- **Zero custo de gestao de credenciais**: sem rotacao, sem alertas de expiracao, sem Secrets Manager
- **Resiliencia**: ECR Public e servico gerenciado AWS com SLA; nao depende de disponibilidade do Docker Hub
- **Simplicidade operacional**: 4 pull-through rules, 0 secrets, 1 Kyverno policy
- **Compativel com CI/CD**: pipelines GitLab podem fazer pull de imagens base via ECR Pull-Through (mesma conta AWS)

### Negativas / Riscos

- **Imagens nao-oficiais do Docker Hub**: imagens de terceiros que nao estao no ECR Public Gallery precisarao de tratamento individual (push manual para Harbor ou ECR)
- **Latencia no primeiro pull**: primeira vez que uma imagem e puxada via pull-through, ha latencia adicional (download do ECR Public); pulls subsequentes sao do cache local
- **Dependencia de ECR Public Gallery**: se AWS descontinuar o mirror de Docker Official Library (improvavel), seria necessario reconfigurar upstream

### Mitigacoes

- Para imagens nao-oficiais: fazer pull manual e push para Harbor (registry privado) — ja e pratica atual
- Latencia de primeiro pull: pipeline de pre-warming pode popular o cache durante deploy de infra
- ECR Public e servico GA da AWS; Docker Official Library mirror existe desde 2021

---

## Referencias

- ADR-106: ECR Pull-Through Cache como Registry Cache (Modelo Hibrido com Harbor)
- Licao 9: Harbor Proxy Cache != registry mirror para containerd/kubelet
- Licao 10: Docker Hub rate limit -> ECR Pull-Through Cache
- GAP-SEC-REGISTRY-01 a 04
- [ECR Public Gallery — Docker Library](https://gallery.ecr.aws/docker/library)
- [AWS ECR Pull-Through Cache — Upstream registries](https://docs.aws.amazon.com/AmazonECR/latest/userguide/pull-through-cache.html#pull-through-cache-upstream)
- [AWS Blog — ECR Pull Through Cache for Public Registries](https://aws.amazon.com/blogs/containers/announcing-pull-through-cache-for-public-registries/)
