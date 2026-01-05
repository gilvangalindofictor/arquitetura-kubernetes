# Mesa Técnica - Decisões de Arquitetura da Plataforma

> **Data**: 2025-12-30
> **Objetivo**: Definir decisões técnicas priorizando **custo baixo**, **cloud-agnostic**, **soluções consolidadas**
> **Participantes**: Time de Plataforma
> **Status**: 🔄 Em Discussão

---

## 🎯 Critérios de Decisão

### Prioridades (em ordem)
1. **💰 Custo Baixo**: Soluções open-source, self-hosted, sem lock-in de vendors
2. **☁️ Cloud-Agnostic**: Portável entre AWS/GCP/Azure/On-Premises
3. **✅ Consolidação**: Helm charts oficiais, imagens verificadas, comunidade ativa
4. **🔌 API-First**: Todas as ferramentas devem ter APIs REST robustas para automação
5. **🏢 Maturidade**: Projetos CNCF Graduated/Incubated preferencialmente

---

## 📦 DECISÃO 1: Container Registry (Onde armazenar imagens das aplicações)

### Contexto
Precisamos de um Container Registry **self-hosted**, **cloud-agnostic**, **com Helm chart oficial** para armazenar:
- Imagens de aplicações **polyglot** (Go, .NET, Python, Node.js) do GitLab CI
- Imagens base customizadas
- Caches de imagens de dependências
- Potencialmente: Helm charts (OCI registry)

### Opções Avaliadas

#### ✅ **RECOMENDADO: Harbor**

**Características**:
- ✅ **CNCF Graduated Project** (máxima maturidade)
- ✅ **100% Open-Source** (Apache 2.0)
- ✅ **Self-hosted** (Kubernetes native)
- ✅ **Helm Chart Oficial**: `harbor/harbor` (muito maduro)
- ✅ **Cloud-Agnostic**: Roda em qualquer Kubernetes
- ✅ **API REST Completa**: Swagger docs, automação total
- ✅ **Vulnerability Scanning**: Trivy integrado (scan automático de vulnerabilidades)
- ✅ **RBAC Robusto**: Integração com Keycloak via OIDC
- ✅ **Replicação**: Multi-região, multi-cluster
- ✅ **UI Web**: Interface amigável para gestão
- ✅ **OCI Compliant**: Suporta imagens Docker + Helm charts
- ✅ **Webhooks**: Notificações para CI/CD

**Custo**:
- 💰 **Baixíssimo**: Apenas recursos do Kubernetes (CPU, RAM, storage)
- Storage S3-compatible (MinIO self-hosted ou S3/GCS/Azure Blob)
- ~3-5GB RAM para ambiente médio
- Storage on-demand (pagar apenas pelo que usar)

**Integração com Stack**:
```yaml
GitLab CI → Build Image → Push para Harbor → Scan Trivy automático
ArgoCD → Pull de Harbor → Deploy no K8s
Backstage → Cataloga imagens do Harbor via API
```

**Helm Chart**:
```bash
helm repo add harbor https://helm.gke.io/chartrepo/harbor
helm install harbor harbor/harbor \
  --set expose.type=ingress \
  --set expose.ingress.hosts.core=harbor.seu-dominio.com \
  --set externalURL=https://harbor.seu-dominio.com \
  --set persistence.persistentVolumeClaim.registry.size=100Gi \
  --set trivy.enabled=true
```

**API REST**:
- Swagger UI: `https://harbor.seu-dominio.com/devcenter-api-2.0`
- Listagem de repos, tags, vulnerabilities
- Gestão de projetos, usuários, replicação
- Webhooks para eventos

**Decisão**: ✅ **Harbor como Container Registry oficial**

---

#### ❌ Alternativas Rejeitadas

**Docker Registry (oficial)**:
- ❌ Muito básico (sem UI, sem RBAC, sem scanning)
- ❌ Sem APIs avançadas
- ✅ Leve, mas insuficiente para corporativo

**Nexus Repository OSS**:
- ✅ Suporta múltiplos formatos (Maven, npm, PyPI, Docker)
- ❌ Pesado (alto consumo de RAM)
- ❌ UI menos amigável que Harbor
- ⚠️ Foco em Java/Maven (não é Kubernetes-native)

**GitLab Container Registry**:
- ✅ Integrado com GitLab
- ❌ Acoplado ao GitLab (não é standalone)
- ⚠️ Menos maduro que Harbor para multi-tenant

**Quay (Red Hat)**:
- ✅ Maduro, robusto
- ❌ Foco em Red Hat/OpenShift
- ⚠️ Menos comunidade open-source (Red Hat driven)

---

## 🔐 DECISÃO 2: Secrets Management (Cofre de Senhas)

### Contexto
Precisamos de um **cofre centralizado** com:
- **API REST robusta** para automações (criar secrets, rotação, auditoria)
- **Integração com CI/CD** (GitLab CI injeta secrets automaticamente)
- **Integração com Keycloak** (autenticação via OIDC)
- **Cloud-agnostic** (self-hosted)
- **Helm chart oficial**

### Opções Avaliadas

#### ✅ **RECOMENDADO: HashiCorp Vault**

**Características**:
- ✅ **Líder de Mercado**: Padrão de facto para secrets management
- ✅ **100% Open-Source** (Mozilla Public License 2.0)
- ✅ **Self-hosted** (Kubernetes native via Vault Agent Injector)
- ✅ **Helm Chart Oficial**: `hashicorp/vault` (muito maduro)
- ✅ **Cloud-Agnostic**: Roda em qualquer Kubernetes
- ✅ **API REST Completa**: Documentação excelente, automação total
- ✅ **Integração Keycloak**: Suporta OIDC/JWT auth method
- ✅ **Integração CI/CD**: Vault Agent + GitLab CI (injeção automática)
- ✅ **Rotação Automática**: Database credentials, API keys, certificates
- ✅ **Auditoria Total**: Logs detalhados de todos os acessos
- ✅ **PKI Integrado**: Geração de certificados TLS on-demand
- ✅ **Multi-Tenant**: Namespaces, policies granulares
- ✅ **HA Mode**: Raft storage (sem dependência de Consul)

**Custo**:
- 💰 **Baixíssimo**: Open-source, self-hosted
- ~1-2GB RAM para ambiente médio
- Storage mínimo (secrets são pequenos)
- Sem custos de licença (Enterprise é opcional)

**API REST**:
```bash
# Criar secret via API
curl -X POST https://vault.seu-dominio.com/v1/secret/data/myapp \
  -H "X-Vault-Token: $VAULT_TOKEN" \
  -d '{"data": {"db_password": "secret123"}}'

# Ler secret via API
curl -X GET https://vault.seu-dominio.com/v1/secret/data/myapp \
  -H "X-Vault-Token: $VAULT_TOKEN"

# Rotação automática via API
curl -X POST https://vault.seu-dominio.com/v1/database/rotate-role/myapp-db
```

**Integração com Keycloak (OIDC)**:
```bash
# Configurar Keycloak como auth method
vault write auth/oidc/config \
  oidc_discovery_url="https://keycloak.seu-dominio.com/realms/platform" \
  oidc_client_id="vault" \
  oidc_client_secret="..." \
  default_role="developer"

# Usuários fazem login via Keycloak
vault login -method=oidc role=developer
```

**Integração com GitLab CI**:
```yaml
# .gitlab-ci.yml
build:
  image: vault:latest
  before_script:
    # GitLab CI autentica no Vault via JWT
    - export VAULT_TOKEN=$(vault write -field=token auth/jwt/login role=gitlab-ci jwt=$CI_JOB_JWT)
    # Lê secrets do Vault
    - export DB_PASSWORD=$(vault kv get -field=password secret/myapp/db)
  script:
    - docker build --build-arg DB_PASSWORD=$DB_PASSWORD -t myapp:latest .
```

**Suporte a Stack Polyglot (Go, .NET, Python, Node.js)**:
```yaml
# .gitlab-ci.yml - Multi-linguagem
stages:
  - build

build-go:
  image: golang:1.21-alpine
  script: 
    - go build -o app
    - docker build -t $HARBOR_REGISTRY/myapp-go:$CI_COMMIT_SHA .

build-dotnet:
  image: mcr.microsoft.com/dotnet/sdk:8.0
  script:
    - dotnet publish -c Release -o out
    - docker build -t $HARBOR_REGISTRY/myapp-dotnet:$CI_COMMIT_SHA .

build-python:
  image: python:3.11-slim
  script:
    - pip install -r requirements.txt
    - docker build -t $HARBOR_REGISTRY/myapp-python:$CI_COMMIT_SHA .

build-nodejs:
  image: node:20-alpine
  script:
    - npm ci
    - docker build -t $HARBOR_REGISTRY/myapp-node:$CI_COMMIT_SHA .
```

**Vault Agent Injector (Pod Sidecar)**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "myapp"
        vault.hashicorp.com/agent-inject-secret-db-password: "secret/data/myapp/db"
    spec:
      containers:
      - name: myapp
        image: myapp:latest
        # Secret injetado automaticamente em /vault/secrets/db-password
```

**Helm Chart**:
```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault \
  --set server.ha.enabled=true \
  --set server.ha.replicas=3 \
  --set server.ha.raft.enabled=true \
  --set ui.enabled=true \
  --set injector.enabled=true
```

**Decisão**: ✅ **HashiCorp Vault como Secrets Management oficial**

---

#### ❌ Alternativas Rejeitadas

**External Secrets Operator (ESO)**:
- ✅ CNCF Sandbox, cloud-agnostic
- ❌ **Não é um cofre**, é apenas um operator que sincroniza secrets externos
- ❌ Ainda precisa de um backend (Vault, AWS Secrets Manager, etc.)
- ⚠️ Útil se você já tem Vault em outra cloud, mas não substitui Vault

**Sealed Secrets (Bitnami)**:
- ✅ Leve, simples
- ❌ Secrets ficam no Git (encrypted), não em cofre centralizado
- ❌ Sem rotação automática
- ❌ Sem auditoria centralizada
- ❌ Sem API REST para automações complexas

**Kubernetes Secrets (nativo)**:
- ✅ Nativo do K8s
- ❌ Base64 (não é encriptação real)
- ❌ Sem rotação automática
- ❌ Sem auditoria granular
- ❌ Totalmente inseguro para produção

---

## 🏗️ DECISÃO 3: Service Mesh (Istio vs Linkerd)

### Contexto
Precisamos de **service mesh** para:
- Sidecar isolation entre namespaces
- mTLS automático
- Traffic management
- Observabilidade avançada

### Opções Avaliadas

#### ✅ **RECOMENDADO: Linkerd**

**Por quê Linkerd?**:
- ✅ **CNCF Graduated** (máxima maturidade)
- ✅ **Leve**: Proxy em Rust (baixíssimo overhead de CPU/RAM)
- ✅ **Simples**: Instalação e operação muito mais fáceis que Istio
- ✅ **Custo Baixo**: Menor consumo de recursos = menor custo
- ✅ **mTLS Automático**: Zero-config
- ✅ **Helm Chart Oficial**: `linkerd/linkerd2`
- ✅ **API REST**: CLI + API para automações
- ✅ **Observabilidade**: Dashboards Grafana + Kiali-like (Linkerd Viz)

**Custo**:
- 💰 **Baixíssimo**: ~10-20MB RAM por sidecar (vs 50-100MB no Istio)
- Control plane leve (~200MB RAM vs ~1GB no Istio)

**Helm Chart**:
```bash
helm repo add linkerd https://helm.linkerd.io/stable
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -
linkerd viz install | kubectl apply -f -  # Observabilidade
```

**Decisão**: ✅ **Linkerd como Service Mesh oficial (foco em custo baixo e simplicidade)**

---

#### ⚠️ Alternativa: Istio

**Quando considerar Istio**:
- ✅ Funcionalidades avançadas (rate limiting, circuit breaker complexo, etc.)
- ✅ Ecossistema maior (mais integrações)
- ❌ **Muito mais complexo** (curva de aprendizado alta)
- ❌ **Muito mais pesado** (3-5x mais recursos que Linkerd)
- ❌ **Custo maior**

**Decisão**: ❌ Rejeitar Istio no momento (over-engineering + custo alto)
**Reavaliação**: Se precisarmos de funcionalidades avançadas no futuro

---

## 📊 DECISÃO 4: Database Operators (PostgreSQL, Redis, RabbitMQ)

### PostgreSQL

#### ✅ **RECOMENDADO: CloudNativePG**

**Por quê CloudNativePG?**:
- ✅ **CNCF Sandbox** (em crescimento)
- ✅ **Leve e Moderno**: Operator em Go, arquitetura cloud-native
- ✅ **HA Nativo**: Replicação streaming, failover automático
- ✅ **Backup Integrado**: Barman (WAL archiving, PITR)
- ✅ **Custo Baixo**: Menor overhead que outros operators
- ✅ **Helm Chart Oficial**: `cloudnative-pg/cloudnative-pg`
- ✅ **API REST**: CRDs Kubernetes (kubectl + APIs K8s)

**Helm Chart**:
```bash
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm install cloudnative-pg cnpg/cloudnative-pg
```

**Alternativas**:
- ⚠️ **Zalando Postgres Operator**: Maduro, mas mais complexo
- ⚠️ **CrunchyData PGO**: Robusto, mas pesado (foco enterprise)

**Decisão**: ✅ **CloudNativePG (foco em custo baixo e simplicidade)**

---

### Redis

#### ✅ **RECOMENDADO: Redis Operator (Spotahome)**

**Por quê Spotahome Redis Operator?**:
- ✅ **Open-Source** (Apache 2.0)
- ✅ **Cluster Mode**: Redis Sentinel (HA)
- ✅ **Leve**: Operator simples em Go
- ✅ **Helm Chart Oficial**: `spotahome/redis-operator`
- ✅ **Custo Baixo**: Redis é leve por natureza

**Helm Chart**:
```bash
helm repo add spotahome https://spotahome.github.io/redis-operator
helm install redis-operator spotahome/redis-operator
```

**Decisão**: ✅ **Spotahome Redis Operator**

---

### RabbitMQ

#### ✅ **RECOMENDADO: RabbitMQ Cluster Operator (VMware/Tanzu)**

**Por quê RabbitMQ Cluster Operator?**:
- ✅ **Oficial**: Mantido pelo time do RabbitMQ (VMware)
- ✅ **HA Nativo**: Quorum queues, clustering automático
- ✅ **Helm Chart Oficial**: `bitnami/rabbitmq-cluster-operator`
- ✅ **API REST**: RabbitMQ Management API + CRDs K8s

**Helm Chart**:
```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install rabbitmq-operator bitnami/rabbitmq-cluster-operator
```

**Decisão**: ✅ **RabbitMQ Cluster Operator (Bitnami/VMware)**

---

## 💾 DECISÃO 5: Backup (Velero)

### ✅ **CONFIRMADO: Velero**

**Por quê Velero?**:
- ✅ **VMware (Broadcom)** - Líder de mercado
- ✅ **CNCF Project** (não graduated ainda, mas amplamente usado)
- ✅ **Cloud-Agnostic**: Backup para S3-compatible (MinIO, S3, GCS, Azure)
- ✅ **Helm Chart Oficial**: `vmware-tanzu/velero`
- ✅ **API REST**: CRDs Kubernetes
- ✅ **Backup/Restore**: PVs, namespaces, cluster completo
- ✅ **Custo Baixo**: Storage S3-compatible (pagar pelo uso)

**Helm Chart**:
```bash
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm install velero vmware-tanzu/velero \
  --set configuration.provider=aws \
  --set configuration.backupStorageLocation.bucket=velero-backups \
  --set configuration.backupStorageLocation.config.region=us-east-1 \
  --set initContainers[0].name=velero-plugin-for-aws \
  --set initContainers[0].image=velero/velero-plugin-for-aws:v1.8.0
```

**Decisão**: ✅ **Velero confirmado**

---

## 🗄️ DECISÃO 6: Object Storage (S3-Compatible)

### Contexto
Precisamos de object storage para:
- Harbor (registry storage)
- Velero (backups)
- Loki (logs storage)
- Tempo (traces storage)

### ✅ **RECOMENDADO: MinIO (Self-Hosted) + Cloud Native (S3/GCS/Azure Blob)**

**Estratégia Híbrida**:

#### Ambientes Dev/HML: MinIO Self-Hosted
- ✅ **100% Open-Source** (AGPL v3)
- ✅ **S3-Compatible**: API 100% compatível
- ✅ **Self-hosted**: Kubernetes native
- ✅ **Helm Chart Oficial**: `minio/minio`
- ✅ **Custo Zero**: Apenas storage local do K8s
- ✅ **UI Web**: Console de gerenciamento

**Helm Chart**:
```bash
helm repo add minio https://charts.min.io/
helm install minio minio/minio \
  --set mode=distributed \
  --set replicas=4 \
  --set persistence.size=100Gi
```

#### Ambientes Produção: Cloud Native (S3/GCS/Azure Blob)
- ✅ **Durabilidade**: 11 noves (99.999999999%)
- ✅ **Custo**: Pay-as-you-go (pagar apenas pelo uso)
- ✅ **Sem Operação**: Gerenciado pela cloud
- ✅ **Multi-Região**: Replicação automática

**Decisão**: ✅ **MinIO para dev/hml + S3/GCS/Azure para produção**

---

## 🔑 DECISÃO 7: PKI e Certificados (cert-manager)

### ✅ **CONFIRMADO: cert-manager**

**Por quê cert-manager?**:
- ✅ **CNCF Graduated** (máxima maturidade)
- ✅ **Padrão de Mercado**: Líder absoluto para TLS no K8s
- ✅ **Let's Encrypt**: Certificados gratuitos automáticos
- ✅ **Vault Integration**: Pode usar Vault como CA
- ✅ **Helm Chart Oficial**: `jetstack/cert-manager`
- ✅ **Custo Zero**: Open-source + Let's Encrypt gratuito

**Helm Chart**:
```bash
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  --set installCRDs=true
```

**Decisão**: ✅ **cert-manager confirmado**

---

## 📈 Resumo de Custos Estimados

### Ambientes Dev/HML (Cluster 3 nodes, 4 vCPU, 16GB RAM cada)

| Componente | RAM Estimado | Storage | Custo Mensal (AWS EKS) |
|------------|--------------|---------|------------------------|
| **Kubernetes Nodes** | 48GB total | 300GB SSD | ~$250 (t3.xlarge × 3) |
| Harbor | 3GB | 100GB | Incluído |
| Vault (HA) | 2GB | 5GB | Incluído |
| Linkerd | 1GB | - | Incluído |
| PostgreSQL (HA) | 4GB | 50GB | Incluído |
| Redis | 2GB | 10GB | Incluído |
| RabbitMQ | 2GB | 20GB | Incluído |
| GitLab | 8GB | 100GB | Incluído |
| Observability | 10GB | 200GB | Incluído |
| MinIO | 2GB | 50GB | Incluído |
| **TOTAL** | ~34GB usado de 48GB | ~535GB | **~$250/mês** |

### Ambientes Produção (Cluster 5 nodes, 8 vCPU, 32GB RAM cada)

| Componente | Custo Mensal (AWS EKS) |
|------------|------------------------|
| **Kubernetes Nodes** | ~$850 (t3.2xlarge × 5) |
| **S3 (backups + storage)** | ~$50 (1TB) |
| **Load Balancers** | ~$50 (2 NLBs) |
| **TOTAL** | **~$950/mês** |

💡 **Comparação com Managed Services**:
- AWS RDS PostgreSQL: ~$200/mês (db.t3.medium)
- AWS ElastiCache Redis: ~$150/mês (cache.t3.medium)
- AWS MQ RabbitMQ: ~$200/mês (mq.t3.micro)
- **Total Managed**: ~$550/mês **APENAS para databases**
- **Nossa Stack**: $0 adicional (tudo no K8s)
- **Economia**: ~$550/mês = **$6.600/ano** 💰

---

## ✅ Decisões Finais Recomendadas

### Stack Aprovado (aguardando validação)

| Categoria | Solução | Motivo |
|-----------|---------|--------|
| **Container Registry** | ✅ Harbor | CNCF Graduated, Trivy integrado, API REST, RBAC |
| **Secrets Management** | ✅ HashiCorp Vault | Líder de mercado, API REST excelente, integração Keycloak |
| **Service Mesh** | ✅ Linkerd | Leve, custo baixo, CNCF Graduated |
| **PostgreSQL** | ✅ CloudNativePG | Leve, moderno, CNCF Sandbox |
| **Redis** | ✅ Spotahome Redis Operator | Open-source, cluster mode, leve |
| **RabbitMQ** | ✅ RabbitMQ Cluster Operator | Oficial VMware, HA nativo |
| **Backup** | ✅ Velero | Padrão de mercado, cloud-agnostic |
| **Object Storage** | ✅ MinIO (dev/hml) + S3/GCS (prod) | Híbrido: custo zero em dev, durabilidade em prod |
| **PKI/Certificados** | ✅ cert-manager | CNCF Graduated, Let's Encrypt gratuito |

---

## 🚀 Próximos Passos

### Imediatos
1. ✅ Validar decisões em reunião de time
2. ✅ Criar ADRs sistêmicos (ADR-003 a ADR-012) documentando cada decisão
3. ✅ Atualizar context-generator.md com ferramentas específicas
4. ✅ Iniciar FASE 1 (Concepção do SAD)

### FASE 2 (Criação de Domínios)
1. Criar domínio **platform-core**: Harbor, Vault, Linkerd, cert-manager
2. Criar domínio **cicd-platform**: GitLab + integração com Harbor/Vault
3. Validar domínio **observability** existente
4. Criar domínio **data-services**: PostgreSQL, Redis, RabbitMQ operators

---

## 📚 Referências

### Helm Charts Oficiais
- Harbor: https://github.com/goharbor/harbor-helm
- Vault: https://github.com/hashicorp/vault-helm
- Linkerd: https://github.com/linkerd/linkerd2
- CloudNativePG: https://github.com/cloudnative-pg/charts
- Velero: https://github.com/vmware-tanzu/helm-charts
- cert-manager: https://github.com/cert-manager/cert-manager

### APIs REST
- Harbor API: https://goharbor.io/docs/2.10.0/build-customize-contribute/configure-swagger/
- Vault API: https://developer.hashicorp.com/vault/api-docs
- Linkerd CLI/API: https://linkerd.io/2.14/reference/cli/
- Keycloak Admin API: https://www.keycloak.org/docs-api/latest/rest-api/

---

**Status**: 🔄 Aguardando aprovação para prosseguir com ADRs sistêmicos
