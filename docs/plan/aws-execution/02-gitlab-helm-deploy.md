# 02 - GitLab Helm Deploy

**Épico B** | **Esforço: 48 person-hours** | **Sprint 1**

---

## Sumário

1. [Visão Geral](#1-visão-geral)
2. [Pré-requisitos](#2-pré-requisitos)
3. [Task B.1: Route53 + ALB (6h)](#3-task-b1-route53--alb-6h)
4. [Task B.2: Preparar values.yaml (8h)](#4-task-b2-preparar-valuesyaml-8h)
5. [Task B.3: Instalar GitLab Helm Chart (12h)](#5-task-b3-instalar-gitlab-helm-chart-12h)
6. [Task B.4: Configurar S3 Backups (6h)](#6-task-b4-configurar-s3-backups-6h)
7. [Task B.5: GitLab Runners (8h)](#7-task-b5-gitlab-runners-8h)
8. [Task B.6: Root Password e Documentação (4h)](#8-task-b6-root-password-e-documentação-4h)
9. [Validação e Definition of Done](#9-validação-e-definition-of-done)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Visão Geral

### Objetivo

Instalar o **GitLab CE** no cluster EKS usando o Helm chart oficial em modo **híbrido**:
- GitLab como pods Kubernetes
- PostgreSQL em RDS (gerenciado AWS)
- Redis via Helm (bitnami) no cluster
- Backups para S3

### Arquitetura do Deploy

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              FLUXO DE ACESSO                                │
│                                                                             │
│  Usuário ──▶ Route53 ──▶ ALB (WAF) ──▶ Ingress ──▶ GitLab Webservice       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                           NAMESPACE: gitlab                                 │
│                                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             │
│  │ webservice      │  │ sidekiq         │  │ gitlab-shell    │             │
│  │ (Rails app)     │  │ (Background)    │  │ (SSH access)    │             │
│  └────────┬────────┘  └────────┬────────┘  └─────────────────┘             │
│           │                    │                                            │
│           ▼                    ▼                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         CONEXÕES EXTERNAS                            │   │
│  │                                                                      │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │   │
│  │  │ RDS         │  │ Redis       │  │ S3          │  │ Registry    │ │   │
│  │  │ PostgreSQL  │  │ (bitnami)   │  │ Backups     │  │ S3 Backend  │ │   │
│  │  │ (AWS)       │  │ (K8s)       │  │ Artifacts   │  │             │ │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘ │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Helm Chart Utilizado

| Chart | Versão | Repository |
|-------|--------|------------|
| `gitlab/gitlab` | v7.7.x ou superior | https://charts.gitlab.io/ |
| `gitlab/gitlab-runner` | v0.60.x ou superior | https://charts.gitlab.io/ |

---

## 2. Pré-requisitos

### Checklist de Pré-requisitos

Antes de iniciar, confirme que todos os itens abaixo estão concluídos:

- [ ] **Doc 01 concluído**: VPC, EKS, Node Groups operacionais
- [ ] **Doc 03 concluído**: RDS PostgreSQL e Redis (bitnami) operacionais
- [ ] **kubectl configurado**: `kubectl get nodes` retorna nodes `Ready`
- [ ] **Helm 3.x instalado**: `helm version` retorna versão 3.x
- [ ] **Domínio disponível**: Você tem acesso a um domínio para configurar DNS
- [ ] **Certificado SSL**: ACM ou cert-manager configurado

### Verificar Ambiente

```bash
# Verificar conexão com cluster
kubectl cluster-info

# Verificar nodes disponíveis
kubectl get nodes -o wide

# Verificar namespaces existentes
kubectl get namespaces

# Verificar StorageClass
kubectl get storageclass

# Verificar RDS está acessível (do cluster)
kubectl run psql-test --image=postgres:15 --rm -it --restart=Never -- \
  psql -h <RDS_ENDPOINT> -U postgres_admin -d postgres -c "SELECT 1;"

# Verificar Redis está operacional
kubectl get pods -n redis
kubectl exec -it <redis-pod> -n redis -- redis-cli ping
```

### Informações Necessárias

Colete estas informações antes de prosseguir:

| Informação | Onde Obter | Exemplo |
|------------|------------|---------|
| **RDS Endpoint** | Console AWS > RDS > Instances | `k8s-platform-prod-postgresql.xxxxx.us-east-1.rds.amazonaws.com` |
| **RDS Password** | Secrets Manager | `senha_segura_32chars` |
| **Redis Endpoint** | `kubectl get svc -n redis` | `redis-master.redis.svc.cluster.local` |
| **Redis Password** | `kubectl get secret -n redis` | `redis_password` |
| **Domínio** | Seu registrador | `gitlab.empresa.com.br` |
| **S3 Bucket (backups)** | Console AWS > S3 | `k8s-platform-gitlab-backups-xxxxx` |
| **AWS Account ID** | Console AWS > Conta | `123456789012` |

---

## 3. Task B.1: Route53 + ALB (6h)

### 3.1 Criar Hosted Zone no Route53

**Passo a passo no Console AWS:**

1. Acesse o Console AWS: https://console.aws.amazon.com/
2. Na barra de busca, digite `Route53` e clique em **Route 53**
3. No menu lateral, clique em **Hosted zones**
4. Clique em **Create hosted zone**
5. Preencha os campos:

   | Campo | Valor |
   |-------|-------|
   | **Domain name** | `gitlab.empresa.com.br` (seu domínio) |
   | **Description** | `DNS zone para GitLab` |
   | **Type** | Public hosted zone |

6. Clique em **Create hosted zone**

7. **IMPORTANTE**: Copie os 4 nameservers (NS records) exibidos:
   ```
   ns-1234.awsdns-12.org
   ns-567.awsdns-34.com
   ns-890.awsdns-56.co.uk
   ns-1011.awsdns-78.net
   ```

8. Configure esses nameservers no seu registrador de domínio (GoDaddy, Registro.br, etc.)

**Contexto:** Route53 será o DNS autoritativo para o domínio do GitLab. Os nameservers precisam ser configurados no registrador para que o DNS funcione.

---

### 3.2 Solicitar Certificado SSL no ACM

**Passo a passo no Console AWS:**

1. Na barra de busca, digite `ACM` e clique em **Certificate Manager**
2. **IMPORTANTE**: Certifique-se de estar na região **us-east-1** (obrigatório para ALB)
3. Clique em **Request certificate**
4. Selecione **Request a public certificate** → **Next**
5. Preencha:

   **Domain names:**
   ```
   *.gitlab.empresa.com.br
   gitlab.empresa.com.br
   ```

   **Validation method:** DNS validation (recommended)

   **Key algorithm:** RSA 2048

6. Clique em **Request**
7. Na lista de certificados, clique no certificado pendente
8. Em **Domains**, clique em **Create records in Route 53**
9. Confirme clicando em **Create records**
10. Aguarde o status mudar para **Issued** (5-30 minutos)

**Contexto:** O certificado wildcard (`*.gitlab.empresa.com.br`) permite usar subdomínios como `registry.gitlab.empresa.com.br` sem certificados adicionais.

---

### 3.3 Instalar AWS Load Balancer Controller

O AWS Load Balancer Controller cria ALBs automaticamente para recursos Ingress.

**Passo a passo via terminal:**

```bash
# 1. Adicionar repositório Helm do EKS
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# 2. Criar namespace (se não existir)
kubectl create namespace kube-system 2>/dev/null || true

# 3. Baixar a policy IAM
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/docs/install/iam_policy.json

# 4. Criar a policy no IAM
aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy.json

# 5. Obter o OIDC provider do cluster
CLUSTER_NAME="k8s-platform-prod"
OIDC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5)
echo "OIDC ID: $OIDC_ID"

# 6. Verificar se o provider OIDC existe
aws iam list-open-id-connect-providers | grep $OIDC_ID

# 7. Se não existir, criar o provider OIDC
eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --approve

# 8. Criar a IAM Role para o ServiceAccount
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

cat > trust-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/${OIDC_ID}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "oidc.eks.us-east-1.amazonaws.com/id/${OIDC_ID}:aud": "sts.amazonaws.com",
                    "oidc.eks.us-east-1.amazonaws.com/id/${OIDC_ID}:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller"
                }
            }
        }
    ]
}
EOF

aws iam create-role \
    --role-name AmazonEKSLoadBalancerControllerRole \
    --assume-role-policy-document file://trust-policy.json

aws iam attach-role-policy \
    --role-name AmazonEKSLoadBalancerControllerRole \
    --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy

# 9. Criar o ServiceAccount
cat > aws-load-balancer-controller-service-account.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    app.kubernetes.io/component: controller
    app.kubernetes.io/name: aws-load-balancer-controller
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::${AWS_ACCOUNT_ID}:role/AmazonEKSLoadBalancerControllerRole
EOF

kubectl apply -f aws-load-balancer-controller-service-account.yaml

# 10. Instalar o controller via Helm
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# 11. Verificar instalação
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

**Validação:**

```bash
# O controller deve estar Running
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Saída esperada:
# NAME                                            READY   STATUS    RESTARTS   AGE
# aws-load-balancer-controller-xxxxxxxxx-xxxxx   1/1     Running   0          2m
```

---

### 3.4 Criar IngressClass

```bash
# Criar IngressClass para ALB
cat > alb-ingress-class.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: alb
  annotations:
    ingressclass.kubernetes.io/is-default-class: "true"
spec:
  controller: ingress.k8s.aws/alb
EOF

kubectl apply -f alb-ingress-class.yaml

# Verificar
kubectl get ingressclass
```

---

## 4. Task B.2: Preparar values.yaml (8h)

### 4.1 Criar Namespace para GitLab

```bash
# Criar namespace
kubectl create namespace gitlab

# Adicionar labels
kubectl label namespace gitlab \
  app=gitlab \
  environment=prod \
  domain=cicd

# Verificar
kubectl get namespace gitlab --show-labels
```

---

### 4.2 Criar Secrets para Credenciais

**Secret para PostgreSQL (RDS):**

```bash
# Substitua pelos valores reais
RDS_HOST="k8s-platform-prod-postgresql.xxxxx.us-east-1.rds.amazonaws.com"
RDS_PASSWORD="sua_senha_segura_aqui"
RDS_DATABASE="gitlab_production"
RDS_USERNAME="gitlab_user"

# Criar secret
kubectl create secret generic gitlab-postgresql-password \
  --namespace gitlab \
  --from-literal=postgresql-password="${RDS_PASSWORD}"

# Verificar
kubectl get secret gitlab-postgresql-password -n gitlab
```

**Secret para Redis:**

```bash
# Obter password do Redis (se configurado)
REDIS_PASSWORD=$(kubectl get secret redis -n redis -o jsonpath='{.data.redis-password}' | base64 -d)

# Criar secret para GitLab
kubectl create secret generic gitlab-redis-secret \
  --namespace gitlab \
  --from-literal=redis-password="${REDIS_PASSWORD}"

# Verificar
kubectl get secret gitlab-redis-secret -n gitlab
```

**Secret para S3 (Backups e Artifacts):**

```bash
# Criar credenciais IAM para S3 (ou usar IRSA)
# Opção 1: Access Keys (menos seguro, mais simples)
cat > s3-credentials.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-rails-storage
  namespace: gitlab
type: Opaque
stringData:
  connection: |
    provider: AWS
    region: us-east-1
    aws_access_key_id: AKIAXXXXXXXXXXXXXXXX
    aws_secret_access_key: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
EOF

kubectl apply -f s3-credentials.yaml

# Opção 2: IRSA (recomendado - mais seguro)
# Será configurado na seção 4.4
```

---

### 4.3 Adicionar Repositório Helm do GitLab

```bash
# Adicionar repositório
helm repo add gitlab https://charts.gitlab.io/
helm repo update

# Verificar charts disponíveis
helm search repo gitlab/gitlab

# Ver versões disponíveis
helm search repo gitlab/gitlab --versions | head -20
```

---

### 4.4 Criar values.yaml para GitLab

Crie o arquivo `gitlab-values.yaml` com as configurações híbridas:

```bash
cat > gitlab-values.yaml <<'EOF'
# =============================================================================
# GitLab Helm Chart - values.yaml (Modo Híbrido)
# =============================================================================
# Versão: 7.7.x
# Ambiente: Produção
# Configuração: Híbrido (GitLab no K8s, PostgreSQL no RDS, Redis via bitnami)
# =============================================================================

# -----------------------------------------------------------------------------
# CONFIGURAÇÕES GLOBAIS
# -----------------------------------------------------------------------------
global:
  # Edição do GitLab
  edition: ce  # Community Edition (gratuito)

  # Domínio base (ALTERAR para seu domínio)
  hosts:
    domain: gitlab.empresa.com.br
    https: true
    gitlab:
      name: gitlab.empresa.com.br
      https: true
    registry:
      name: registry.gitlab.empresa.com.br
      https: true
    minio:
      name: minio.gitlab.empresa.com.br
      https: true

  # Ingress configuration
  ingress:
    enabled: true
    configureCertmanager: false  # Usaremos ACM via ALB
    class: alb
    annotations:
      kubernetes.io/ingress.class: alb
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
      alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:ACCOUNT_ID:certificate/CERT_ID
      alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS13-1-2-2021-06
      alb.ingress.kubernetes.io/healthcheck-path: /-/health
      alb.ingress.kubernetes.io/healthcheck-interval-seconds: "30"
      alb.ingress.kubernetes.io/healthcheck-timeout-seconds: "5"
      alb.ingress.kubernetes.io/healthy-threshold-count: "2"
      alb.ingress.kubernetes.io/unhealthy-threshold-count: "3"
    tls:
      enabled: true

  # -------------------------------------------------------------------------
  # POSTGRESQL (RDS Externo)
  # -------------------------------------------------------------------------
  psql:
    host: k8s-platform-prod-postgresql.xxxxx.us-east-1.rds.amazonaws.com  # ALTERAR
    port: 5432
    database: gitlab_production
    username: gitlab_user
    password:
      secret: gitlab-postgresql-password
      key: postgresql-password

  # -------------------------------------------------------------------------
  # REDIS (bitnami/redis no cluster)
  # -------------------------------------------------------------------------
  redis:
    host: redis-master.redis.svc.cluster.local
    port: 6379
    password:
      enabled: true
      secret: gitlab-redis-secret
      key: redis-password

  # -------------------------------------------------------------------------
  # S3 STORAGE (AWS S3)
  # -------------------------------------------------------------------------
  minio:
    enabled: false  # Desabilitar Minio, usar S3

  appConfig:
    # Object Storage para LFS, Artifacts, Uploads, etc.
    object_store:
      enabled: true
      proxy_download: true
      connection:
        secret: gitlab-rails-storage
        key: connection

    # LFS (Large File Storage)
    lfs:
      enabled: true
      bucket: gitlab-lfs-ACCOUNT_ID
      connection:
        secret: gitlab-rails-storage
        key: connection

    # Artifacts (CI/CD)
    artifacts:
      enabled: true
      bucket: gitlab-artifacts-ACCOUNT_ID
      connection:
        secret: gitlab-rails-storage
        key: connection

    # Uploads
    uploads:
      enabled: true
      bucket: gitlab-uploads-ACCOUNT_ID
      connection:
        secret: gitlab-rails-storage
        key: connection

    # Packages
    packages:
      enabled: true
      bucket: gitlab-packages-ACCOUNT_ID
      connection:
        secret: gitlab-rails-storage
        key: connection

    # Backups
    backups:
      bucket: gitlab-backups-ACCOUNT_ID
      tmpBucket: gitlab-tmp-ACCOUNT_ID

  # -------------------------------------------------------------------------
  # TIMEZONE
  # -------------------------------------------------------------------------
  time_zone: America/Sao_Paulo

  # -------------------------------------------------------------------------
  # EMAIL (Configurar se necessário)
  # -------------------------------------------------------------------------
  smtp:
    enabled: false  # Habilitar quando tiver SMTP configurado
    # address: smtp.empresa.com.br
    # port: 587
    # user_name: gitlab@empresa.com.br
    # password:
    #   secret: gitlab-smtp-password
    #   key: password
    # authentication: login
    # starttls_auto: true

# -----------------------------------------------------------------------------
# COMPONENTES DO GITLAB
# -----------------------------------------------------------------------------

# Webservice (Rails application)
gitlab:
  webservice:
    enabled: true
    replicas: 2
    minReplicas: 2
    maxReplicas: 4
    resources:
      requests:
        cpu: 500m
        memory: 2Gi
      limits:
        cpu: 2000m
        memory: 4Gi
    nodeSelector:
      node-type: critical
    tolerations:
      - key: "workload"
        operator: "Equal"
        value: "critical"
        effect: "NoSchedule"
    ingress:
      enabled: true
      annotations:
        kubernetes.io/ingress.class: alb

  # Sidekiq (Background jobs)
  sidekiq:
    enabled: true
    replicas: 2
    minReplicas: 2
    maxReplicas: 4
    resources:
      requests:
        cpu: 250m
        memory: 1Gi
      limits:
        cpu: 1000m
        memory: 2Gi
    nodeSelector:
      node-type: critical

  # GitLab Shell (SSH access)
  gitlab-shell:
    enabled: true
    replicas: 2
    minReplicas: 2
    maxReplicas: 4
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 256Mi

  # Gitaly (Git storage - usar se não tiver PVC)
  gitaly:
    enabled: true
    replicas: 1
    persistence:
      enabled: true
      size: 50Gi
      storageClass: gp3
    resources:
      requests:
        cpu: 500m
        memory: 1Gi
      limits:
        cpu: 2000m
        memory: 4Gi
    nodeSelector:
      node-type: critical

  # Migrations (one-time jobs)
  migrations:
    enabled: true

  # Toolbox (backup/restore)
  toolbox:
    enabled: true
    replicas: 1
    persistence:
      enabled: true
      size: 10Gi
      storageClass: gp3

# -----------------------------------------------------------------------------
# COMPONENTES DESABILITADOS (usando externos)
# -----------------------------------------------------------------------------

# PostgreSQL interno (desabilitado - usando RDS)
postgresql:
  install: false

# Redis interno (desabilitado - usando bitnami/redis)
redis:
  install: false

# Minio (desabilitado - usando S3)
minio:
  install: false

# Prometheus (desabilitado - usando stack de observability separada)
prometheus:
  install: false

# Grafana (desabilitado - usando stack de observability separada)
grafana:
  install: false

# Certmanager (desabilitado - usando ACM)
certmanager:
  install: false

# NGINX Ingress (desabilitado - usando ALB)
nginx-ingress:
  enabled: false

# -----------------------------------------------------------------------------
# REGISTRY (Container Registry)
# -----------------------------------------------------------------------------
registry:
  enabled: true
  replicas: 2
  storage:
    secret: gitlab-rails-storage
    key: connection
    extraKey: registry-storage
  ingress:
    enabled: true

# -----------------------------------------------------------------------------
# GITLAB PAGES (opcional)
# -----------------------------------------------------------------------------
gitlab-pages:
  enabled: false  # Habilitar se precisar de GitLab Pages

# -----------------------------------------------------------------------------
# KAS (Kubernetes Agent Server)
# -----------------------------------------------------------------------------
gitlab-kas:
  enabled: true
  replicas: 2
  ingress:
    enabled: true

# -----------------------------------------------------------------------------
# SHARED SECRETS
# -----------------------------------------------------------------------------
shared-secrets:
  enabled: true
  rbac:
    create: true

# -----------------------------------------------------------------------------
# UPGRADE CHECK
# -----------------------------------------------------------------------------
upgradeCheck:
  enabled: false

EOF

echo "Arquivo gitlab-values.yaml criado!"
echo ""
echo "IMPORTANTE: Você precisa editar o arquivo e substituir:"
echo "  - ACCOUNT_ID pelo seu AWS Account ID"
echo "  - CERT_ID pelo ID do certificado ACM"
echo "  - O endpoint do RDS"
echo "  - Os nomes dos buckets S3"
```

---

### 4.5 Personalizar o values.yaml

**Passo a passo para personalização:**

1. **Obter AWS Account ID:**
   ```bash
   AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   echo "AWS Account ID: $AWS_ACCOUNT_ID"
   ```

2. **Obter ARN do Certificado ACM:**
   ```bash
   # Listar certificados
   aws acm list-certificates --region us-east-1

   # Copie o CertificateArn do certificado correto
   ```

3. **Editar o arquivo:**
   ```bash
   # Substituir placeholders
   sed -i "s/ACCOUNT_ID/${AWS_ACCOUNT_ID}/g" gitlab-values.yaml
   sed -i "s/CERT_ID/seu-cert-id-aqui/g" gitlab-values.yaml
   sed -i "s/xxxxx/seu-rds-endpoint/g" gitlab-values.yaml
   ```

4. **Verificar o arquivo:**
   ```bash
   # Verificar se não há placeholders restantes
   grep -E "(ACCOUNT_ID|CERT_ID|xxxxx)" gitlab-values.yaml
   # Não deve retornar nada se tudo foi substituído
   ```

---

## 5. Task B.3: Instalar GitLab Helm Chart (12h)

### 5.1 Criar Buckets S3

**Passo a passo no Console AWS:**

1. Na barra de busca, digite `S3` e clique em **S3**
2. Para cada bucket abaixo, repita:
   - Clique em **Create bucket**
   - **Bucket name:** (conforme tabela)
   - **Region:** us-east-1
   - **Block all public access:** ✅ Habilitado
   - **Bucket Versioning:** Enabled (para backups)
   - Clique em **Create bucket**

| Bucket Name | Propósito |
|-------------|-----------|
| `gitlab-lfs-{ACCOUNT_ID}` | Large File Storage |
| `gitlab-artifacts-{ACCOUNT_ID}` | CI/CD Artifacts |
| `gitlab-uploads-{ACCOUNT_ID}` | User Uploads |
| `gitlab-packages-{ACCOUNT_ID}` | Package Registry |
| `gitlab-backups-{ACCOUNT_ID}` | Backups |
| `gitlab-tmp-{ACCOUNT_ID}` | Temporary files |
| `gitlab-registry-{ACCOUNT_ID}` | Container Registry |

**Ou via CLI:**

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

for bucket in lfs artifacts uploads packages backups tmp registry; do
  aws s3 mb s3://gitlab-${bucket}-${AWS_ACCOUNT_ID} --region us-east-1
  aws s3api put-bucket-versioning \
    --bucket gitlab-${bucket}-${AWS_ACCOUNT_ID} \
    --versioning-configuration Status=Enabled
  aws s3api put-bucket-encryption \
    --bucket gitlab-${bucket}-${AWS_ACCOUNT_ID} \
    --server-side-encryption-configuration '{
      "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
    }'
  echo "Bucket gitlab-${bucket}-${AWS_ACCOUNT_ID} criado"
done
```

---

### 5.2 Criar IAM Policy para S3

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

cat > gitlab-s3-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "GitLabS3Access",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket",
                "s3:GetBucketLocation"
            ],
            "Resource": [
                "arn:aws:s3:::gitlab-*-${AWS_ACCOUNT_ID}",
                "arn:aws:s3:::gitlab-*-${AWS_ACCOUNT_ID}/*"
            ]
        }
    ]
}
EOF

aws iam create-policy \
    --policy-name GitLabS3AccessPolicy \
    --policy-document file://gitlab-s3-policy.json
```

---

### 5.3 Validar Configuração Antes do Deploy

```bash
# Dry-run do Helm (simula instalação)
helm install gitlab gitlab/gitlab \
  --namespace gitlab \
  --values gitlab-values.yaml \
  --dry-run \
  --debug 2>&1 | head -100

# Se não houver erros, prosseguir
```

---

### 5.4 Instalar GitLab

```bash
# Instalação do GitLab (pode demorar 10-15 minutos)
helm install gitlab gitlab/gitlab \
  --namespace gitlab \
  --values gitlab-values.yaml \
  --timeout 600s \
  --wait

# Acompanhar progresso
watch -n 5 kubectl get pods -n gitlab
```

**Saída esperada após alguns minutos:**

```
NAME                                      READY   STATUS    RESTARTS   AGE
gitlab-gitaly-0                           1/1     Running   0          5m
gitlab-gitlab-shell-xxxxxxxxx-xxxxx       1/1     Running   0          5m
gitlab-kas-xxxxxxxxx-xxxxx                1/1     Running   0          5m
gitlab-migrations-x-xxxxx                 0/1     Completed 0          5m
gitlab-registry-xxxxxxxxx-xxxxx           1/1     Running   0          5m
gitlab-sidekiq-all-in-1-v2-xxxxx-xxxxx    1/1     Running   0          5m
gitlab-toolbox-xxxxxxxxx-xxxxx            1/1     Running   0          5m
gitlab-webservice-default-xxxxx-xxxxx     2/2     Running   0          5m
gitlab-webservice-default-xxxxx-xxxxx     2/2     Running   0          5m
```

---

### 5.5 Verificar Ingress e ALB

```bash
# Verificar Ingress criado
kubectl get ingress -n gitlab

# Obter endereço do ALB
kubectl get ingress -n gitlab -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'

# Saída esperada: k8s-gitlab-xxxxx-xxxxx.us-east-1.elb.amazonaws.com
```

---

### 5.6 Configurar DNS no Route53

**Passo a passo no Console AWS:**

1. Vá para **Route53 > Hosted zones**
2. Clique na hosted zone `gitlab.empresa.com.br`
3. Clique em **Create record**
4. Preencha:

   **Record 1 (GitLab principal):**
   - **Record name:** (deixe em branco para root)
   - **Record type:** A
   - **Alias:** Yes
   - **Route traffic to:** Alias to Application Load Balancer
   - **Region:** US East (N. Virginia)
   - **ALB:** Selecione o ALB criado pelo ingress

5. Clique em **Create records**

6. Repita para os subdomínios:
   - `registry.gitlab.empresa.com.br` → Mesmo ALB
   - `kas.gitlab.empresa.com.br` → Mesmo ALB

**Ou via CLI:**

```bash
ALB_DNS=$(kubectl get ingress -n gitlab -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')
ALB_ZONE_ID=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?DNSName=='${ALB_DNS}'].CanonicalHostedZoneId" --output text)
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name gitlab.empresa.com.br --query "HostedZones[0].Id" --output text | cut -d'/' -f3)

cat > route53-records.json <<EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "gitlab.empresa.com.br",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "${ALB_ZONE_ID}",
          "DNSName": "${ALB_DNS}",
          "EvaluateTargetHealth": true
        }
      }
    },
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "registry.gitlab.empresa.com.br",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "${ALB_ZONE_ID}",
          "DNSName": "${ALB_DNS}",
          "EvaluateTargetHealth": true
        }
      }
    }
  ]
}
EOF

aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch file://route53-records.json
```

---

### 5.7 Testar Acesso ao GitLab

```bash
# Aguardar propagação DNS (pode levar alguns minutos)
dig gitlab.empresa.com.br

# Testar HTTPS
curl -I https://gitlab.empresa.com.br/-/health

# Saída esperada:
# HTTP/2 200
# ...
```

---

## 6. Task B.4: Configurar S3 Backups (6h)

### 6.1 Verificar Configuração de Backup

```bash
# Verificar se o toolbox está rodando
kubectl get pods -n gitlab -l app=toolbox

# Acessar o toolbox
kubectl exec -it -n gitlab $(kubectl get pods -n gitlab -l app=toolbox -o jsonpath='{.items[0].metadata.name}') -- /bin/bash

# Dentro do toolbox, verificar configuração de backup
cat /srv/gitlab/config/gitlab.yml | grep -A 20 backup
```

---

### 6.2 Executar Backup Manual (Teste)

```bash
# Executar backup do GitLab (via toolbox)
kubectl exec -it -n gitlab $(kubectl get pods -n gitlab -l app=toolbox -o jsonpath='{.items[0].metadata.name}') -- backup-utility

# Acompanhar logs
kubectl logs -n gitlab $(kubectl get pods -n gitlab -l app=toolbox -o jsonpath='{.items[0].metadata.name}') -f
```

---

### 6.3 Criar CronJob para Backup Automático

```bash
cat > gitlab-backup-cronjob.yaml <<EOF
apiVersion: batch/v1
kind: CronJob
metadata:
  name: gitlab-backup
  namespace: gitlab
spec:
  schedule: "0 2 * * *"  # Diariamente às 2h da manhã
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: registry.gitlab.com/gitlab-org/build/cng/gitlab-toolbox-ce:latest
            command:
            - /bin/sh
            - -c
            - |
              /usr/local/bin/backup-utility
            env:
            - name: GITLAB_BACKUP_EXTRA_ARGS
              value: "--skip builds,artifacts"
            volumeMounts:
            - name: etc-gitlab
              mountPath: /etc/gitlab
              readOnly: true
            - name: gitlab-data
              mountPath: /var/opt/gitlab
          restartPolicy: OnFailure
          volumes:
          - name: etc-gitlab
            configMap:
              name: gitlab-webservice-default
          - name: gitlab-data
            persistentVolumeClaim:
              claimName: gitlab-gitaly-data-gitlab-gitaly-0
          nodeSelector:
            node-type: critical
EOF

kubectl apply -f gitlab-backup-cronjob.yaml
```

---

### 6.4 Verificar Backups no S3

```bash
# Listar backups
aws s3 ls s3://gitlab-backups-${AWS_ACCOUNT_ID}/

# Saída esperada:
# 2026-01-19 02:15:00 1234567890 1705640100_2026_01_19_16.7.0_gitlab_backup.tar
```

---

## 7. Task B.5: GitLab Runners (8h)

### 7.1 Obter Token de Registro do Runner

**Via Interface Web:**

1. Acesse `https://gitlab.empresa.com.br/`
2. Faça login como root (ver seção 8 para obter senha)
3. Vá para **Admin Area** (ícone de chave inglesa)
4. Menu lateral: **CI/CD > Runners**
5. Clique em **New instance runner**
6. Configure:
   - **Tags:** `kubernetes`, `docker`
   - **Run untagged jobs:** ✅
7. Clique em **Create runner**
8. **Copie o token de registro** exibido

**Ou via API (após obter Personal Access Token):**

```bash
# Obter token via API
curl --request POST \
  --header "PRIVATE-TOKEN: <seu-access-token>" \
  "https://gitlab.empresa.com.br/api/v4/user/runners" \
  --form "runner_type=instance_type" \
  --form "tag_list=kubernetes,docker"
```

---

### 7.2 Criar values.yaml para Runner

```bash
cat > gitlab-runner-values.yaml <<'EOF'
# =============================================================================
# GitLab Runner Helm Chart - values.yaml
# =============================================================================

# GitLab instance URL
gitlabUrl: https://gitlab.empresa.com.br/

# Runner registration token (será substituído)
runnerToken: "RUNNER_TOKEN_AQUI"

# Número de runners concurrent
concurrent: 10

# Check interval
checkInterval: 3

# RBAC
rbac:
  create: true
  rules:
    - apiGroups: [""]
      resources: ["pods", "pods/exec", "pods/attach", "secrets", "configmaps"]
      verbs: ["get", "list", "watch", "create", "patch", "update", "delete"]
    - apiGroups: [""]
      resources: ["pods/log"]
      verbs: ["get", "list", "watch"]

# Runners configuration
runners:
  # Executor
  executor: kubernetes

  # Docker image padrão
  image: ubuntu:22.04

  # Privileged mode (necessário para Docker-in-Docker)
  privileged: false

  # Tags
  tags: "kubernetes,docker,aws"

  # Run untagged jobs
  runUntagged: true

  # Kubernetes executor config
  config: |
    [[runners]]
      [runners.kubernetes]
        namespace = "gitlab"
        image = "ubuntu:22.04"
        privileged = false
        poll_timeout = 600
        cpu_request = "100m"
        cpu_limit = "1"
        memory_request = "128Mi"
        memory_limit = "1Gi"
        service_cpu_request = "100m"
        service_cpu_limit = "1"
        service_memory_request = "128Mi"
        service_memory_limit = "1Gi"
        helper_cpu_request = "50m"
        helper_cpu_limit = "500m"
        helper_memory_request = "64Mi"
        helper_memory_limit = "256Mi"
        [runners.kubernetes.node_selector]
          "node-type" = "workloads"
        [runners.kubernetes.pod_labels]
          "gitlab-runner" = "true"

# Resources para o runner manager
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"

# Node selector para o runner manager
nodeSelector:
  node-type: workloads

# Tolerations
tolerations: []

# Pod annotations
podAnnotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "9252"

# Metrics
metrics:
  enabled: true
  portName: metrics
  port: 9252
  serviceMonitor:
    enabled: true

EOF

# Substituir o token
sed -i "s/RUNNER_TOKEN_AQUI/seu-token-aqui/" gitlab-runner-values.yaml
```

---

### 7.3 Instalar GitLab Runner

```bash
# Instalar runner
helm install gitlab-runner gitlab/gitlab-runner \
  --namespace gitlab \
  --values gitlab-runner-values.yaml \
  --timeout 300s

# Verificar instalação
kubectl get pods -n gitlab -l app=gitlab-runner

# Verificar logs
kubectl logs -n gitlab -l app=gitlab-runner -f
```

---

### 7.4 Verificar Runner Registrado

1. Acesse `https://gitlab.empresa.com.br/admin/runners`
2. O runner deve aparecer com status **Online** (ícone verde)

**Via kubectl:**

```bash
# Verificar ConfigMap do runner
kubectl get configmap -n gitlab -l app=gitlab-runner

# Ver configuração
kubectl get configmap gitlab-runner -n gitlab -o yaml
```

---

### 7.5 Testar Pipeline

1. Crie um novo projeto no GitLab
2. Adicione um arquivo `.gitlab-ci.yml`:

```yaml
# .gitlab-ci.yml
stages:
  - test

test-job:
  stage: test
  tags:
    - kubernetes
  script:
    - echo "Hello from Kubernetes Runner!"
    - cat /etc/os-release
    - whoami
    - pwd
```

3. Faça commit e verifique a execução do pipeline em **CI/CD > Pipelines**

---

## 8. Task B.6: Root Password e Documentação (4h)

### 8.1 Obter Senha Inicial do Root

```bash
# Obter senha do root
kubectl get secret gitlab-gitlab-initial-root-password \
  -n gitlab \
  -o jsonpath='{.data.password}' | base64 -d && echo

# Saída: uma senha aleatória como "xY7k9mN2pQ4r"
```

**IMPORTANTE:** Anote esta senha em local seguro. Altere-a após o primeiro login.

---

### 8.2 Primeiro Acesso

1. Acesse `https://gitlab.empresa.com.br/`
2. Login:
   - **Username:** `root`
   - **Password:** (senha obtida acima)
3. Altere a senha imediatamente:
   - Vá para **User Settings > Password**
   - Defina uma nova senha forte

---

### 8.3 Configurações Iniciais Recomendadas

**Via Interface Admin:**

1. **Admin Area > Settings > General**
   - **Sign-up restrictions:** Desabilitar sign-up público
   - **Sign-in restrictions:** Habilitar 2FA obrigatório

2. **Admin Area > Settings > CI/CD**
   - **Default artifacts expiration:** 30 days
   - **Maximum artifacts size:** 1 GB

3. **Admin Area > Settings > Repository**
   - **Repository size limit:** 5 GB

---

### 8.4 Documentar Credenciais

Crie um registro seguro (no AWS Secrets Manager ou Vault) com:

| Item | Valor |
|------|-------|
| GitLab URL | https://gitlab.empresa.com.br |
| Root Username | root |
| Root Password | (nova senha definida) |
| Registry URL | https://registry.gitlab.empresa.com.br |
| Runner Token | (token de registro) |
| RDS Endpoint | (endpoint do RDS) |
| RDS Database | gitlab_production |
| RDS Username | gitlab_user |
| RDS Password | (senha do RDS) |

---

## 9. Validação e Definition of Done

### Checklist de Validação

Execute cada verificação e marque como concluída:

```bash
# 1. Verificar todos os pods Running
kubectl get pods -n gitlab
# Todos os pods devem estar Running ou Completed

# 2. Verificar Ingress
kubectl get ingress -n gitlab
# Deve mostrar ADDRESS do ALB

# 3. Verificar serviços
kubectl get svc -n gitlab
# Deve listar todos os services

# 4. Testar healthcheck
curl -I https://gitlab.empresa.com.br/-/health
# Deve retornar HTTP 200

# 5. Testar login
# Acessar via browser e fazer login com root

# 6. Testar pipeline
# Criar projeto e rodar .gitlab-ci.yml

# 7. Verificar runner
kubectl get pods -n gitlab -l app=gitlab-runner
# Runner deve estar Running

# 8. Verificar métricas
kubectl port-forward svc/gitlab-webservice-default -n gitlab 9168:9168
curl http://localhost:9168/metrics
# Deve retornar métricas Prometheus
```

### Definition of Done - Épico B

- [ ] **Infraestrutura de Rede**
  - [ ] Route53 hosted zone criada
  - [ ] Certificado ACM emitido e válido
  - [ ] ALB criado e funcionando
  - [ ] DNS resolvendo corretamente

- [ ] **GitLab Operacional**
  - [ ] GitLab UI acessível via HTTPS
  - [ ] Login com root funcional
  - [ ] Conexão com RDS PostgreSQL funcionando
  - [ ] Conexão com Redis funcionando
  - [ ] Registry acessível

- [ ] **CI/CD Funcional**
  - [ ] Pelo menos 1 runner registrado e online
  - [ ] Pipeline de teste executado com sucesso
  - [ ] Artifacts sendo salvos no S3

- [ ] **Backup Configurado**
  - [ ] Backup manual executado com sucesso
  - [ ] CronJob de backup configurado
  - [ ] Backups aparecendo no S3

- [ ] **Documentação**
  - [ ] Credenciais documentadas em local seguro
  - [ ] Procedimentos de acesso documentados

---

## 10. Troubleshooting

### Problema: Pods em CrashLoopBackOff

```bash
# Verificar logs do pod
kubectl logs -n gitlab <pod-name> --previous

# Verificar eventos
kubectl describe pod -n gitlab <pod-name>

# Causas comuns:
# - Conexão com RDS falhou (verificar Security Group)
# - Conexão com Redis falhou (verificar endpoint)
# - Recursos insuficientes (aumentar limits)
```

### Problema: ALB não é criado

```bash
# Verificar logs do controller
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Causas comuns:
# - IRSA não configurado corretamente
# - Subnets sem tags corretas
# - Security Group muito restritivo
```

### Problema: Certificado inválido

```bash
# Verificar status do certificado ACM
aws acm describe-certificate --certificate-arn <arn>

# Causas comuns:
# - Validação DNS não completada
# - Certificado na região errada (deve ser us-east-1)
# - ARN incorreto no values.yaml
```

### Problema: Runner não registra

```bash
# Verificar logs do runner
kubectl logs -n gitlab -l app=gitlab-runner

# Causas comuns:
# - Token de registro expirado ou inválido
# - URL do GitLab incorreta
# - Problemas de rede (Network Policy bloqueando)
```

### Problema: Backup falha

```bash
# Verificar logs do toolbox
kubectl logs -n gitlab $(kubectl get pods -n gitlab -l app=toolbox -o jsonpath='{.items[0].metadata.name}')

# Causas comuns:
# - Permissões S3 insuficientes
# - Bucket não existe
# - Credenciais S3 incorretas
```

---

## Próximos Passos

Após concluir este documento:

1. **Validar Definition of Done** completamente
2. Prosseguir para **[03-data-services-helm.md](03-data-services-helm.md)** se ainda não concluído
3. Ou iniciar **[04-observability-stack.md](04-observability-stack.md)**

---

**Documento:** 02-gitlab-helm-deploy.md
**Versão:** 1.0
**Última atualização:** 2026-01-19
**Épico:** B
**Esforço:** 48 person-hours
