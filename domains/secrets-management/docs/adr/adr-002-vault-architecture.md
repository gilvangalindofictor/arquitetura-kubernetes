# ADR-002: HashiCorp Vault como Plataforma de Secrets Management

**Status**: ✅ Aprovado
**Data**: 2026-01-22
**Decisores**: System Architect, DevOps Lead
**Supersedes**: ADR-001 (decisão pendente)

---

## Contexto

O domínio `secrets-management` precisa de uma solução robusta para gerenciar credenciais, certificados e secrets de forma centralizada, com os seguintes requisitos:

### Requisitos Funcionais

1. **Centralização**: Único ponto de gerenciamento de secrets para todos os domínios
2. **Integração CI/CD**: Injeção automática de secrets em pipelines GitLab/ArgoCD
3. **Rotação Automática**: Secrets com ciclo de vida gerenciado (databases, API keys)
4. **Auditoria**: Log completo de acesso e modificações
5. **Dynamic Secrets**: Geração de credenciais sob demanda (PostgreSQL, RabbitMQ)
6. **PKI Interno**: Certificate Authority para mTLS entre serviços
7. **Encryption as a Service**: Criptografia/descriptografia centralizada

### Requisitos Não-Funcionais

1. **Cloud-Agnostic**: Conforme ADR-003 (sem dependência de cloud providers)
2. **Alta Disponibilidade**: Cluster HA Multi-AZ
3. **Segurança**: Auto-unsealing seguro, secrets criptografados at-rest e in-transit
4. **Performance**: Latência < 100ms para operações de leitura
5. **Kubernetes-Native**: Integração nativa com K8s via CSI driver ou sidecar injector

---

## Opções Consideradas

### Opção 1: HashiCorp Vault (Self-Hosted)

**Arquitetura:**
```
┌─────────────────────────────────────────────────────────┐
│                    VAULT HA CLUSTER                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ Vault Pod 1  │  │ Vault Pod 2  │  │ Vault Pod 3  │  │
│  │   (Active)   │  │  (Standby)   │  │  (Standby)   │  │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  │
│         │                  │                  │          │
│         └──────────────────┼──────────────────┘          │
│                            │                             │
│                   ┌────────▼─────────┐                   │
│                   │  Consul Backend  │                   │
│                   │  (Raft Storage)  │                   │
│                   └──────────────────┘                   │
└─────────────────────────────────────────────────────────┘
```

**Prós:**
- ✅ **Cloud-Agnostic Total**: Self-hosted, sem lock-in
- ✅ **Dynamic Secrets**: Suporte nativo para PostgreSQL, RabbitMQ, etc.
- ✅ **PKI Engine**: Certificate Authority interno para mTLS
- ✅ **Encryption as a Service**: Transit engine para criptografia
- ✅ **Auditoria Completa**: Logs detalhados de todas as operações
- ✅ **Kubernetes Integration**: CSI Driver e Sidecar Injector oficiais
- ✅ **Maturidade**: Solução enterprise-grade, amplamente adotada
- ✅ **Extensibilidade**: Plugins para integração custom

**Contras:**
- ❌ **Complexidade Operacional**: Unsealing, HA, backups complexos
- ❌ **Custo de Recursos**: 3+ pods (cluster HA) + Consul backend
- ❌ **Curva de Aprendizado**: Conceitos avançados (policies, auth methods, engines)
- ❌ **Gerenciamento de Estado**: Unsealing manual em disaster recovery

**Estimativa de Recursos:**
- **Vault Cluster**: 3 pods × 1 CPU + 1GB RAM = 3 CPUs, 3GB RAM
- **Consul Backend**: 3 pods × 0.5 CPU + 512MB RAM = 1.5 CPUs, 1.5GB RAM
- **Total**: ~4.5 CPUs, 4.5GB RAM

---

### Opção 2: External Secrets Operator (ESO) + Cloud KMS

**Arquitetura:**
```
┌─────────────────────────────────────────────────────┐
│             EXTERNAL SECRETS OPERATOR                │
│  ┌──────────────────────────────────────────────┐   │
│  │   ESO Controller                              │   │
│  │   (sync secrets K8s ← Cloud)                 │   │
│  └───────┬──────────────────────────────────────┘   │
│          │                                           │
│          ▼                                           │
│  ┌──────────────┐  ┌──────────────┐                 │
│  │  SecretStore │  │ ExternalSecret│                 │
│  │  (AWS/Azure) │  │   (CRDs)      │                 │
│  └──────────────┘  └──────────────┘                 │
└─────────────────────────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────────────────┐
│             CLOUD PROVIDER (AWS/Azure)               │
│  - AWS Secrets Manager / Parameter Store             │
│  - Azure Key Vault                                   │
│  - GCP Secret Manager                                │
└─────────────────────────────────────────────────────┘
```

**Prós:**
- ✅ **Simplicidade Operacional**: Controller leve (1 pod, baixo overhead)
- ✅ **Gerenciamento Delegado**: Cloud provider gerencia HA, backups, unsealing
- ✅ **Integração K8s Nativa**: CRDs (SecretStore, ExternalSecret)
- ✅ **Baixo Custo de Recursos**: ~0.5 CPU, 512MB RAM (controller apenas)
- ✅ **Rotação Automática**: Cloud provider gerencia rotação

**Contras:**
- ❌ **Cloud Lock-In**: **VIOLA ADR-003 (Cloud-Agnostic OBRIGATÓRIO)**
- ❌ **Sem Dynamic Secrets**: Apenas sync de secrets estáticos
- ❌ **Sem PKI**: Não oferece Certificate Authority
- ❌ **Sem Encryption Service**: Não oferece criptografia centralizada
- ❌ **Dependência Externa**: Falha no cloud provider afeta cluster K8s
- ❌ **Custo Variável**: Custos adicionais no cloud provider (AWS Secrets Manager: $0.40/secret/mês)

---

### Opção 3: Sealed Secrets (Bitnami)

**Arquitetura:**
```
┌─────────────────────────────────────────────────────┐
│             SEALED SECRETS CONTROLLER                │
│  ┌──────────────────────────────────────────────┐   │
│  │   Controller                                  │   │
│  │   (decrypt SealedSecrets → Secrets)          │   │
│  └──────────────────────────────────────────────┘   │
│                                                      │
│  Secrets criptografados no Git (safe to commit)     │
└─────────────────────────────────────────────────────┘
```

**Prós:**
- ✅ **GitOps-Friendly**: Secrets criptografados podem ser commitados
- ✅ **Simplicidade**: 1 controller, sem backend externo
- ✅ **Cloud-Agnostic**: Totalmente K8s-native

**Contras:**
- ❌ **Sem Dynamic Secrets**: Apenas secrets estáticos
- ❌ **Sem Rotação Automática**: Rotação manual
- ❌ **Sem PKI/Encryption Service**: Features limitadas
- ❌ **Sem Auditoria Avançada**: Logs básicos apenas
- ❌ **Gestão de Chaves**: Complexidade em backup/restore da chave privada

---

## Comparação Detalhada

| Critério | Vault | ESO + Cloud KMS | Sealed Secrets |
|----------|-------|-----------------|----------------|
| **Cloud-Agnostic (ADR-003)** | ✅ Total | ❌ **VIOLA** | ✅ Total |
| **Dynamic Secrets** | ✅ Sim | ❌ Não | ❌ Não |
| **PKI (mTLS interno)** | ✅ Sim | ❌ Não | ❌ Não |
| **Encryption Service** | ✅ Sim | ❌ Não | ❌ Não |
| **Rotação Automática** | ✅ Sim | ✅ Sim | ❌ Não |
| **Auditoria** | ✅ Completa | ⚠️ Básica | ⚠️ Básica |
| **Complexidade Operacional** | 🔴 Alta | 🟢 Baixa | 🟢 Baixa |
| **Custo de Recursos** | 🔴 Alto (4.5 CPUs) | 🟢 Baixo (0.5 CPU) | 🟢 Baixo (0.5 CPU) |
| **Maturidade** | ✅ Enterprise | ✅ Maduro | ⚠️ Limitado |
| **Kubernetes Integration** | ✅ CSI + Injector | ✅ CRDs | ✅ CRDs |

---

## Decisão

**ESCOLHIDO: Opção 1 - HashiCorp Vault (Self-Hosted HA Cluster)**

### Justificativa

1. **Alinhamento com SAD v1.2 (ADR-003):**
   - ✅ Cloud-agnostic é **requisito obrigatório**
   - ✅ ESO + Cloud KMS **VIOLA ADR-003** (lock-in)
   - ✅ Vault permite migração entre clouds sem mudança de stack

2. **Capacidades Avançadas Necessárias:**
   - ✅ **Dynamic Secrets**: Essencial para PostgreSQL, RabbitMQ (ADR validado no TERRAFORM-IMPLEMENTATION-REPORT)
   - ✅ **PKI Engine**: Linkerd service mesh requer mTLS entre serviços
   - ✅ **Encryption Service**: Keycloak e GitLab precisam criptografar dados sensíveis

3. **Integração com Plataforma:**
   - ✅ **GitLab**: Injeção de secrets via Vault Agent Injector
   - ✅ **ArgoCD**: External Secrets CRD com Vault backend
   - ✅ **Keycloak**: OIDC authentication + secret storage
   - ✅ **Data Services**: Dynamic credentials para PostgreSQL Operator

4. **Segurança e Compliance:**
   - ✅ Auditoria completa (obrigatório para compliance)
   - ✅ Policies granulares (least-privilege)
   - ✅ Unsealing seguro (Kubernetes auto-unseal via transit key)

5. **Trade-off Aceitável:**
   - ⚠️ Complexidade operacional é aceitável dada a criticidade
   - ⚠️ Custo de recursos (4.5 CPUs) é justificado pelos benefícios
   - ⚠️ Curva de aprendizado será mitigada com treinamento

---

## Arquitetura de Implementação

### High-Level Design

```mermaid
graph TB
    subgraph "Kubernetes Cluster"
        subgraph "Namespace: vault"
            V1[Vault Pod 1<br/>Active]
            V2[Vault Pod 2<br/>Standby]
            V3[Vault Pod 3<br/>Standby]
            C1[Consul Pod 1]
            C2[Consul Pod 2]
            C3[Consul Pod 3]

            V1 -.-> C1
            V2 -.-> C2
            V3 -.-> C3
            C1 <--> C2
            C2 <--> C3
            C3 <--> C1
        end

        subgraph "App Namespaces"
            APP1[GitLab Pod<br/>+ Vault Agent]
            APP2[Keycloak Pod<br/>+ Vault Agent]
            APP3[ArgoCD Pod<br/>+ CSI Driver]
        end

        APP1 -->|1. Request Secret| V1
        APP2 -->|2. Authenticate| V1
        APP3 -->|3. Mount Secret| V1
    end

    V1 -->|4. Dynamic Creds| RDS[(RDS PostgreSQL)]
    V1 -->|5. PKI Cert| MESH[Linkerd mTLS]
```

### Componentes Principais

#### 1. Vault HA Cluster (3 réplicas)

**Deployment:**
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault
  namespace: vault

---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: vault
  namespace: vault
spec:
  serviceName: vault-internal
  replicas: 3
  selector:
    matchLabels:
      app: vault
  template:
    metadata:
      labels:
        app: vault
    spec:
      serviceAccountName: vault
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchLabels:
                  app: vault
              topologyKey: kubernetes.io/hostname
      containers:
        - name: vault
          image: hashicorp/vault:1.15.4
          resources:
            requests:
              cpu: 1000m
              memory: 1Gi
            limits:
              cpu: 2000m
              memory: 2Gi
          env:
            - name: VAULT_ADDR
              value: "http://127.0.0.1:8200"
            - name: VAULT_API_ADDR
              value: "http://$(POD_IP):8200"
            - name: SKIP_CHOWN
              value: "true"
            - name: SKIP_SETCAP
              value: "true"
          ports:
            - containerPort: 8200
              name: http
            - containerPort: 8201
              name: https-internal
            - containerPort: 8202
              name: http-rep
          volumeMounts:
            - name: data
              mountPath: /vault/data
            - name: config
              mountPath: /vault/config
          securityContext:
            capabilities:
              add: ["IPC_LOCK"]
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 10Gi
```

**Vault Config (vault-config.hcl):**
```hcl
ui = true

listener "tcp" {
  address = "[::]:8200"
  cluster_address = "[::]:8201"
  tls_disable = 1  # TLS via Linkerd service mesh
}

storage "consul" {
  address = "consul:8500"
  path    = "vault/"
}

# Auto-unseal via Kubernetes secret
seal "transit" {
  address         = "http://vault-unseal:8200"
  disable_renewal = "false"
  key_name        = "autounseal"
  mount_path      = "transit/"
}

api_addr = "http://vault.vault.svc.cluster.local:8200"
cluster_addr = "https://vault.vault.svc.cluster.local:8201"
```

#### 2. Consul Backend (Raft Storage)

**Deployment:**
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: consul
  namespace: vault
spec:
  serviceName: consul
  replicas: 3
  selector:
    matchLabels:
      app: consul
  template:
    metadata:
      labels:
        app: consul
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchLabels:
                  app: consul
              topologyKey: kubernetes.io/hostname
      containers:
        - name: consul
          image: hashicorp/consul:1.17.0
          resources:
            requests:
              cpu: 500m
              memory: 512Mi
            limits:
              cpu: 1000m
              memory: 1Gi
          env:
            - name: POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
          args:
            - "agent"
            - "-server"
            - "-bootstrap-expect=3"
            - "-ui"
            - "-data-dir=/consul/data"
            - "-bind=0.0.0.0"
            - "-client=0.0.0.0"
            - "-advertise=$(POD_IP)"
            - "-retry-join=consul-0.consul.vault.svc.cluster.local"
            - "-retry-join=consul-1.consul.vault.svc.cluster.local"
            - "-retry-join=consul-2.consul.vault.svc.cluster.local"
          ports:
            - containerPort: 8500
              name: http
            - containerPort: 8300
              name: server
            - containerPort: 8301
              name: serf-lan
          volumeMounts:
            - name: data
              mountPath: /consul/data
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 5Gi
```

#### 3. Vault Agent Injector (Sidecar Automático)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vault-agent-injector
  namespace: vault
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vault-agent-injector
  template:
    metadata:
      labels:
        app: vault-agent-injector
    spec:
      serviceAccountName: vault-agent-injector
      containers:
        - name: sidecar-injector
          image: hashicorp/vault-k8s:1.3.1
          resources:
            requests:
              cpu: 250m
              memory: 256Mi
          env:
            - name: AGENT_INJECT_LISTEN
              value: ":8080"
            - name: AGENT_INJECT_VAULT_ADDR
              value: "http://vault.vault.svc.cluster.local:8200"
```

---

## Configuração de Secrets Engines

### 1. Database Dynamic Secrets (PostgreSQL)

```bash
# Habilitar database engine
vault secrets enable database

# Configurar conexão PostgreSQL
vault write database/config/postgresql \
    plugin_name=postgresql-database-plugin \
    allowed_roles="gitlab,keycloak,sonarqube" \
    connection_url="postgresql://{{username}}:{{password}}@rds-endpoint:5432/postgres" \
    username="vault_admin" \
    password="vault_password"

# Criar role para GitLab
vault write database/roles/gitlab \
    db_name=postgresql \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
        GRANT ALL PRIVILEGES ON DATABASE gitlab_production TO \"{{name}}\";" \
    default_ttl="1h" \
    max_ttl="24h"

# Gerar credenciais dinâmicas
vault read database/creds/gitlab
# Key                Value
# ---                -----
# lease_id           database/creds/gitlab/abc123
# lease_duration     1h
# username           v-gitlab-xyz
# password           A1b2C3d4...
```

### 2. PKI Engine (Certificate Authority)

```bash
# Habilitar PKI engine
vault secrets enable pki

# Configurar CA raiz
vault secrets tune -max-lease-ttl=87600h pki

vault write pki/root/generate/internal \
    common_name="Platform Internal CA" \
    ttl=87600h

# Configurar CRL
vault write pki/config/urls \
    issuing_certificates="http://vault.vault.svc.cluster.local:8200/v1/pki/ca" \
    crl_distribution_points="http://vault.vault.svc.cluster.local:8200/v1/pki/crl"

# Criar role para Linkerd mTLS
vault write pki/roles/linkerd-identity \
    allowed_domains="*.linkerd.cluster.local" \
    allow_subdomains=true \
    max_ttl="720h"

# Emitir certificado
vault write pki/issue/linkerd-identity \
    common_name="pod.linkerd.cluster.local" \
    ttl="24h"
```

### 3. Transit Engine (Encryption as a Service)

```bash
# Habilitar transit engine
vault secrets enable transit

# Criar chave de criptografia
vault write -f transit/keys/keycloak

# Criptografar dado
vault write transit/encrypt/keycloak \
    plaintext=$(echo "sensitive-data" | base64)
# Key           Value
# ciphertext    vault:v1:abc123...

# Descriptografar
vault write transit/decrypt/keycloak \
    ciphertext="vault:v1:abc123..."
```

### 4. KV v2 (Secrets Estáticos)

```bash
# Habilitar KV v2
vault secrets enable -path=secret kv-v2

# Armazenar secret
vault kv put secret/gitlab/oauth \
    client_id="gitlab-oauth" \
    client_secret="super-secret-123"

# Ler secret
vault kv get secret/gitlab/oauth
```

---

## Integração com Aplicações

### GitLab (Vault Agent Injector)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gitlab
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "gitlab"
    vault.hashicorp.com/agent-inject-secret-database: "database/creds/gitlab"
    vault.hashicorp.com/agent-inject-template-database: |
      {{- with secret "database/creds/gitlab" -}}
      export DB_USERNAME={{ .Data.username }}
      export DB_PASSWORD={{ .Data.password }}
      {{- end }}
spec:
  serviceAccountName: gitlab
  containers:
    - name: gitlab
      image: gitlab/gitlab-ce:latest
      command: ["/bin/sh"]
      args: ["-c", "source /vault/secrets/database && /assets/wrapper"]
```

### ArgoCD (External Secrets Operator + Vault Backend)

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: argocd
spec:
  provider:
    vault:
      server: "http://vault.vault.svc.cluster.local:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "argocd"

---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: argocd-secret
  namespace: argocd
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: argocd-secret
    creationPolicy: Owner
  data:
    - secretKey: admin.password
      remoteRef:
        key: secret/argocd/admin
        property: password
```

---

## Políticas de Acesso (RBAC)

### GitLab Policy

```hcl
# gitlab-policy.hcl
path "database/creds/gitlab" {
  capabilities = ["read"]
}

path "secret/data/gitlab/*" {
  capabilities = ["read"]
}

path "transit/encrypt/gitlab" {
  capabilities = ["update"]
}

path "transit/decrypt/gitlab" {
  capabilities = ["update"]
}
```

### Keycloak Policy

```hcl
# keycloak-policy.hcl
path "database/creds/keycloak" {
  capabilities = ["read"]
}

path "secret/data/keycloak/*" {
  capabilities = ["read"]
}

path "pki/issue/keycloak-mtls" {
  capabilities = ["create", "update"]
}
```

---

## Auto-Unsealing Strategy

### Kubernetes Secret-Based Auto-Unseal

**Setup:**

1. Criar cluster Vault secundário para unsealing (bootstrap)
2. Usar transit engine do Vault secundário para auto-unseal do cluster principal
3. Vault secundário é manualmente unsealed (1x após disaster recovery)

**Alternativa (Produção):**
- Usar AWS KMS/Azure Key Vault **APENAS** para auto-unseal (exceção ao ADR-003)
- Justificativa: Unsealing é operação crítica, cloud KMS oferece maior segurança

```hcl
# vault-config.hcl (com cloud auto-unseal)
seal "awskms" {
  region     = "us-east-1"
  kms_key_id = "alias/vault-unseal"
}
```

**Decisão**: Usar Kubernetes auto-unseal em dev/staging, AWS KMS em produção.

---

## Backup e Disaster Recovery

### Estratégia de Backup

1. **Consul Snapshots**: Backup automático a cada 6h
```bash
consul snapshot save backup-$(date +%Y%m%d-%H%M%S).snap
# Upload para S3
aws s3 cp backup-*.snap s3://k8s-platform-backups-prod/vault/
```

2. **Vault Snapshots**: Backup via API
```bash
vault operator raft snapshot save vault-snapshot.snap
aws s3 cp vault-snapshot.snap s3://k8s-platform-backups-prod/vault/
```

3. **Retenção**: 7 dias local, 90 dias S3, 365 dias Glacier

### Disaster Recovery

**Cenário 1: Perda de 1 pod Vault**
- Auto-recovery via StatefulSet (standby promovido a active)
- RTO: 30 segundos

**Cenário 2: Perda total do cluster**
1. Restaurar Consul snapshot
2. Restaurar Vault snapshot
3. Unseal manualmente (ou via cloud KMS)
4. Validar integridade
- RTO: 15 minutos, RPO: 6 horas

---

## Métricas e Monitoramento

### Prometheus Metrics

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: vault-exporter
  namespace: vault
data:
  config.yaml: |
    vault:
      addr: http://vault.vault.svc.cluster.local:8200
      token_path: /var/run/secrets/vault-token
    metrics:
      - seal_status
      - ha_status
      - leader
      - secrets_engines
      - auth_methods
```

### Alertas Críticos

| Alerta | Condição | Severidade |
|--------|----------|------------|
| `VaultSealed` | Vault cluster sealed | Critical |
| `VaultNotLeader` | Nenhum pod active | Critical |
| `VaultHighLatency` | p95 > 200ms | Warning |
| `ConsulNoLeader` | Consul sem leader | Critical |
| `VaultBackupFailed` | Snapshot failed | Warning |

---

## Segurança

### Least-Privilege Policies

- ✅ Cada aplicação tem policy dedicada (gitlab-policy, keycloak-policy)
- ✅ Secrets engines isolados por domínio
- ✅ TTL curto para dynamic secrets (1h padrão, 24h max)

### Network Policies

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: vault-ingress
  namespace: vault
spec:
  podSelector:
    matchLabels:
      app: vault
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              vault-access: "true"
      ports:
        - protocol: TCP
          port: 8200
```

### Audit Logging

```hcl
# vault-audit.hcl
audit "file" {
  path = "/vault/logs/audit.log"
  log_raw = true
  format = "json"
}

# Forward para Loki
```

---

## Consequências

### Positivas

1. ✅ **Cloud-Agnostic Compliance**: Alinhado com ADR-003
2. ✅ **Capacidades Avançadas**: Dynamic secrets, PKI, encryption service
3. ✅ **Segurança Enterprise**: Auditoria completa, policies granulares
4. ✅ **Integração Total**: GitLab, ArgoCD, Keycloak, data-services
5. ✅ **Escalabilidade**: HA cluster, performance adequada
6. ✅ **Maturidade**: Solução battle-tested, comunidade ativa

### Negativas

1. ❌ **Complexidade Operacional**: Unsealing, backup, DR complexos
2. ❌ **Custo de Recursos**: 4.5 CPUs, 4.5GB RAM (aceitável dado benefícios)
3. ❌ **Curva de Aprendizado**: Treinamento necessário para equipe
4. ❌ **Gerenciamento de Estado**: Snapshots manuais (automação necessária)

### Neutras

1. ⚪ **Auto-Unseal Trade-off**: Cloud KMS em produção (exceção justificada)
2. ⚪ **Alternatives Available**: ESO como fallback se requisitos mudarem

---

## Plano de Implementação

### Sprint Atual

- [ ] Criar namespace `vault`
- [ ] Deploy Consul cluster (3 pods)
- [ ] Deploy Vault cluster (3 pods)
- [ ] Configurar auto-unsealing
- [ ] Habilitar secrets engines (database, PKI, transit, KV)
- [ ] Criar policies (gitlab, keycloak, argocd)
- [ ] Deploy Vault Agent Injector
- [ ] Criar VALIDATION-REPORT.md

### Sprint+1

- [ ] Integrar com GitLab (sidecar injection)
- [ ] Integrar com Keycloak (OIDC + secrets)
- [ ] Integrar com ArgoCD (External Secrets Operator)
- [ ] Configurar dynamic secrets PostgreSQL
- [ ] Configurar PKI para Linkerd mTLS
- [ ] Implementar backup automático
- [ ] Configurar métricas Prometheus
- [ ] Testes de DR

---

## Referências

- [SAD v1.2](../../../../SAD/docs/sad.md)
- [ADR-003: Cloud-Agnostic](../../../../SAD/docs/adrs/adr-003-cloud-agnostic-obrigatorio.md)
- [ADR-005: Segurança Sistêmica](../../../../SAD/docs/adrs/adr-005-seguranca-sistemica.md)
- [HashiCorp Vault Documentation](https://developer.hashicorp.com/vault/docs)
- [Vault Kubernetes Integration](https://developer.hashicorp.com/vault/docs/platform/k8s)
- [Terraform Implementation Report](../../../../docs/plan/tools/TERRAFORM-IMPLEMENTATION-REPORT.md)

---

**Autor**: System Architect
**Versão**: 1.0
**Última Atualização**: 2026-01-22
