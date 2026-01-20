# 05 - Security Hardening

> **Épico G** | Estimativa: 30 person-hours | Sprint 3
> **Pré-requisitos**: Docs 01-04 concluídos

> ⚠️ **Abordagem CLI-First:** Este documento prioriza kubectl e AWS CLI.
> Seções de WAF e Security Groups agora incluem alternativas Terraform/CLI.

---

## Índice

1. [Visão Geral](#1-visão-geral)
2. [Network Policies](#2-network-policies)
3. [Pod Security Standards](#3-pod-security-standards)
4. [RBAC Least-Privilege](#4-rbac-least-privilege)
5. [cert-manager e TLS](#5-cert-manager-e-tls)
6. [AWS WAF](#6-aws-waf)
7. [Security Groups Review](#7-security-groups-review)
8. [Secrets Management](#8-secrets-management)
9. [Validação de Segurança](#9-validação-de-segurança)
10. [Checklist de Conclusão](#10-checklist-de-conclusão)

---

## 1. Visão Geral

### 1.1 Objetivos do Épico G

```
┌─────────────────────────────────────────────────────────────────┐
│                    SECURITY HARDENING                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │  Network    │  │    Pod      │  │    RBAC     │             │
│  │  Policies   │  │  Security   │  │  Policies   │             │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘             │
│         │                │                │                     │
│         ▼                ▼                ▼                     │
│  ┌─────────────────────────────────────────────────┐           │
│  │              KUBERNETES CLUSTER                  │           │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐         │           │
│  │  │ GitLab  │  │  Redis  │  │ RabbitMQ│         │           │
│  │  │ (TLS)   │  │ (TLS)   │  │  (TLS)  │         │           │
│  │  └─────────┘  └─────────┘  └─────────┘         │           │
│  └─────────────────────────────────────────────────┘           │
│         ▲                ▲                ▲                     │
│         │                │                │                     │
│  ┌──────┴──────┐  ┌──────┴──────┐  ┌──────┴──────┐             │
│  │ cert-manager│  │   AWS WAF   │  │   Secrets   │             │
│  │ (Let's Enc) │  │  (ALB)      │  │  (External) │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Componentes de Segurança

| Camada | Componente | Função |
|--------|------------|--------|
| **Network** | Network Policies | Microsegmentação L3/L4 |
| **Pod** | Pod Security Standards | Restrições de containers |
| **Access** | RBAC | Controle de acesso K8s |
| **Transport** | cert-manager | TLS automático |
| **Edge** | AWS WAF | Proteção L7 |
| **Infra** | Security Groups | Firewall AWS |
| **Data** | Secrets Management | Gestão de credenciais |

---

## 2. Network Policies

### 2.1 Instalar Calico (se não instalado)

O EKS usa Amazon VPC CNI por padrão. Para Network Policies, precisamos do Calico:

```bash
# Verificar se Calico já está instalado
kubectl get pods -n calico-system

# Se não estiver, instalar Calico para Network Policies
kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/config/master/calico-operator.yaml
kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/config/master/calico-crs.yaml

# Aguardar pods ficarem Ready
kubectl wait --for=condition=Ready pods -l k8s-app=calico-node -n calico-system --timeout=300s
```

### 2.2 Default Deny Policy (Por Namespace)

Criar arquivo `network-policies/default-deny.yaml`:

```yaml
# Default Deny - Aplicar em cada namespace
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: gitlab
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: data-services
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: observability
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

**Aplicar:**
```bash
kubectl apply -f network-policies/default-deny.yaml
```

### 2.3 GitLab Network Policies

Criar arquivo `network-policies/gitlab-policies.yaml`:

```yaml
# GitLab Webservice - Permite ingress do ALB e egress necessário
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: gitlab-webservice-policy
  namespace: gitlab
spec:
  podSelector:
    matchLabels:
      app: webservice
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Permite tráfego do ALB (via node)
    - from:
        - ipBlock:
            cidr: 10.0.0.0/16  # VPC CIDR
      ports:
        - protocol: TCP
          port: 8181
        - protocol: TCP
          port: 8080
  egress:
    # DNS
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
        - podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    # Redis
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: data-services
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: redis
      ports:
        - protocol: TCP
          port: 6379
    # RDS PostgreSQL (externa)
    - to:
        - ipBlock:
            cidr: 10.0.64.0/19  # Data Subnet CIDR
      ports:
        - protocol: TCP
          port: 5432
    # Gitaly
    - to:
        - podSelector:
            matchLabels:
              app: gitaly
      ports:
        - protocol: TCP
          port: 8075

---
# GitLab Sidekiq
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: gitlab-sidekiq-policy
  namespace: gitlab
spec:
  podSelector:
    matchLabels:
      app: sidekiq
  policyTypes:
    - Ingress
    - Egress
  ingress: []  # Sidekiq não recebe tráfego externo
  egress:
    # DNS
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    # Redis
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: data-services
      ports:
        - protocol: TCP
          port: 6379
    # RDS PostgreSQL
    - to:
        - ipBlock:
            cidr: 10.0.64.0/19
      ports:
        - protocol: TCP
          port: 5432
    # S3 (via NAT Gateway - internet)
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 10.0.0.0/8
              - 172.16.0.0/12
              - 192.168.0.0/16
      ports:
        - protocol: TCP
          port: 443

---
# GitLab Runner
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: gitlab-runner-policy
  namespace: gitlab
spec:
  podSelector:
    matchLabels:
      app: gitlab-runner
  policyTypes:
    - Ingress
    - Egress
  ingress: []
  egress:
    # DNS
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    # GitLab API (interno)
    - to:
        - podSelector:
            matchLabels:
              app: webservice
      ports:
        - protocol: TCP
          port: 8181
    # Internet (para pull de imagens e builds)
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 10.0.0.0/8
              - 172.16.0.0/12
              - 192.168.0.0/16
      ports:
        - protocol: TCP
          port: 443
        - protocol: TCP
          port: 80

---
# Gitaly
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: gitlab-gitaly-policy
  namespace: gitlab
spec:
  podSelector:
    matchLabels:
      app: gitaly
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: webservice
        - podSelector:
            matchLabels:
              app: sidekiq
        - podSelector:
            matchLabels:
              app: gitlab-shell
      ports:
        - protocol: TCP
          port: 8075
  egress:
    # DNS
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
```

### 2.4 Data Services Network Policies

Criar arquivo `network-policies/data-services-policies.yaml`:

```yaml
# Redis - Permite acesso do namespace gitlab
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: redis-policy
  namespace: data-services
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: redis
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # GitLab namespace
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: gitlab
      ports:
        - protocol: TCP
          port: 6379
    # Interno (replicação Sentinel)
    - from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: redis
      ports:
        - protocol: TCP
          port: 6379
        - protocol: TCP
          port: 26379
  egress:
    # DNS
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
    # Replicação entre pods Redis
    - to:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: redis
      ports:
        - protocol: TCP
          port: 6379
        - protocol: TCP
          port: 26379

---
# RabbitMQ - Permite acesso do namespace gitlab
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: rabbitmq-policy
  namespace: data-services
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: rabbitmq
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # GitLab namespace (AMQP)
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: gitlab
      ports:
        - protocol: TCP
          port: 5672
    # Management UI (interno)
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: observability
      ports:
        - protocol: TCP
          port: 15672
    # Cluster (entre nodes RabbitMQ)
    - from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: rabbitmq
      ports:
        - protocol: TCP
          port: 4369
        - protocol: TCP
          port: 25672
  egress:
    # DNS
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
    # Cluster interno
    - to:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: rabbitmq
      ports:
        - protocol: TCP
          port: 4369
        - protocol: TCP
          port: 25672
```

### 2.5 Observability Network Policies

Criar arquivo `network-policies/observability-policies.yaml`:

```yaml
# Prometheus - Permite scrape de todos namespaces
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: prometheus-policy
  namespace: observability
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: prometheus
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Grafana
    - from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: grafana
      ports:
        - protocol: TCP
          port: 9090
  egress:
    # DNS
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    # Scrape de métricas (todos os namespaces)
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 9090
        - protocol: TCP
          port: 9091
        - protocol: TCP
          port: 9100
        - protocol: TCP
          port: 8080
        - protocol: TCP
          port: 8081
        - protocol: TCP
          port: 10250  # kubelet

---
# Grafana - Acesso externo via ALB
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: grafana-policy
  namespace: observability
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: grafana
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # ALB
    - from:
        - ipBlock:
            cidr: 10.0.0.0/16
      ports:
        - protocol: TCP
          port: 3000
  egress:
    # DNS
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
    # Prometheus
    - to:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: prometheus
      ports:
        - protocol: TCP
          port: 9090
    # Loki
    - to:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: loki
      ports:
        - protocol: TCP
          port: 3100
    # Tempo
    - to:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: tempo
      ports:
        - protocol: TCP
          port: 3200

---
# Loki
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: loki-policy
  namespace: observability
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: loki
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Grafana
    - from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: grafana
      ports:
        - protocol: TCP
          port: 3100
    # OTEL Collector
    - from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: opentelemetry-collector
      ports:
        - protocol: TCP
          port: 3100
  egress:
    # DNS
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
    # S3
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 10.0.0.0/8
              - 172.16.0.0/12
              - 192.168.0.0/16
      ports:
        - protocol: TCP
          port: 443

---
# OpenTelemetry Collector
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: otel-collector-policy
  namespace: observability
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: opentelemetry-collector
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Recebe telemetria de todos os namespaces
    - from:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 4317   # OTLP gRPC
        - protocol: TCP
          port: 4318   # OTLP HTTP
        - protocol: TCP
          port: 14268  # Jaeger
  egress:
    # DNS
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
    # Prometheus
    - to:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: prometheus
      ports:
        - protocol: TCP
          port: 9090
    # Loki
    - to:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: loki
      ports:
        - protocol: TCP
          port: 3100
    # Tempo
    - to:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: tempo
      ports:
        - protocol: TCP
          port: 4317
```

### 2.6 Aplicar Todas as Policies

```bash
# Criar diretório
mkdir -p network-policies

# Aplicar todas as policies
kubectl apply -f network-policies/

# Verificar policies
kubectl get networkpolicies -A

# Testar conectividade (deve funcionar)
kubectl exec -it -n gitlab deploy/gitlab-webservice -- curl -s redis.data-services:6379

# Testar conectividade (deve falhar - namespace não autorizado)
kubectl run test-pod --image=busybox -n default -- sleep 3600
kubectl exec -it -n default test-pod -- nc -zv redis.data-services.svc.cluster.local 6379
# Esperado: timeout/blocked
kubectl delete pod test-pod -n default
```

---

## 3. Pod Security Standards

### 3.1 Habilitar Pod Security Admission

```bash
# Verificar se PSA está habilitado (EKS 1.23+)
kubectl get pods -n kube-system -l component=kube-apiserver -o yaml | grep enable-admission-plugins
```

### 3.2 Aplicar Labels nos Namespaces

```yaml
# pod-security-labels.yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: gitlab
  labels:
    kubernetes.io/metadata.name: gitlab
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
---
apiVersion: v1
kind: Namespace
metadata:
  name: data-services
  labels:
    kubernetes.io/metadata.name: data-services
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
---
apiVersion: v1
kind: Namespace
metadata:
  name: observability
  labels:
    kubernetes.io/metadata.name: observability
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

**Nota**: Observability usa `baseline` porque alguns collectors precisam de host network/hostPath.

```bash
kubectl apply -f pod-security-labels.yaml
```

### 3.3 SecurityContext Padrão para Deployments

Adicionar em todos os Deployments/StatefulSets:

```yaml
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: app
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
```

---

## 4. RBAC Least-Privilege

### 4.1 Service Accounts por Aplicação

```yaml
# rbac/service-accounts.yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: gitlab-webservice
  namespace: gitlab
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/gitlab-webservice-role
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: gitlab-sidekiq
  namespace: gitlab
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/gitlab-sidekiq-role
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: gitlab-runner
  namespace: gitlab
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: loki
  namespace: observability
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/loki-s3-role
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tempo
  namespace: observability
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/tempo-s3-role
```

### 4.2 Roles para GitLab Runner

```yaml
# rbac/gitlab-runner-rbac.yaml
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: gitlab-runner
  namespace: gitlab
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/exec", "pods/attach", "pods/log"]
    verbs: ["get", "list", "watch", "create", "delete"]
  - apiGroups: [""]
    resources: ["configmaps", "secrets"]
    verbs: ["get", "list", "create", "update", "delete"]
  - apiGroups: [""]
    resources: ["services"]
    verbs: ["get", "list", "create", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: gitlab-runner
  namespace: gitlab
subjects:
  - kind: ServiceAccount
    name: gitlab-runner
    namespace: gitlab
roleRef:
  kind: Role
  name: gitlab-runner
  apiGroup: rbac.authorization.k8s.io
```

### 4.3 ClusterRole para Prometheus

```yaml
# rbac/prometheus-rbac.yaml
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus-scraper
rules:
  - apiGroups: [""]
    resources: ["nodes", "nodes/metrics", "services", "endpoints", "pods"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses"]
    verbs: ["get", "list", "watch"]
  - nonResourceURLs: ["/metrics", "/metrics/cadvisor"]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus-scraper
subjects:
  - kind: ServiceAccount
    name: prometheus
    namespace: observability
roleRef:
  kind: ClusterRole
  name: prometheus-scraper
  apiGroup: rbac.authorization.k8s.io
```

### 4.4 Restringir Acesso Admin

```yaml
# rbac/admin-restriction.yaml
---
# Grupo de admins com acesso total
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: platform-admins
subjects:
  - kind: Group
    name: platform-admins
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
---
# Grupo de devs com acesso limitado
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: developer
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "services", "configmaps"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: developers
subjects:
  - kind: Group
    name: developers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: developer
  apiGroup: rbac.authorization.k8s.io
```

### 4.5 Aplicar RBAC

```bash
mkdir -p rbac
kubectl apply -f rbac/

# Verificar
kubectl get clusterroles | grep -E 'prometheus|developer|gitlab'
kubectl get rolebindings -n gitlab
kubectl auth can-i --as=system:serviceaccount:gitlab:gitlab-runner list pods -n gitlab
# Esperado: yes

kubectl auth can-i --as=system:serviceaccount:gitlab:gitlab-runner list pods -n kube-system
# Esperado: no
```

---

## 5. cert-manager e TLS

### 5.1 Instalar cert-manager

```bash
# Adicionar repositório
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Instalar cert-manager
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.14.0 \
  --set installCRDs=true \
  --set prometheus.enabled=true \
  --set webhook.timeoutSeconds=30

# Aguardar pods
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s
```

### 5.2 Criar ClusterIssuer para Let's Encrypt

```yaml
# cert-manager/cluster-issuers.yaml
---
# Staging (para testes - não tem rate limit)
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: admin@seudominio.com.br
    privateKeySecretRef:
      name: letsencrypt-staging-key
    solvers:
      - http01:
          ingress:
            class: alb
---
# Production
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@seudominio.com.br
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - http01:
          ingress:
            class: alb
      # Alternativa: DNS challenge para wildcard
      - dns01:
          route53:
            region: us-east-1
            hostedZoneID: Z0123456789ABCDEF
```

**Aplicar:**
```bash
kubectl apply -f cert-manager/cluster-issuers.yaml

# Verificar
kubectl get clusterissuers
kubectl describe clusterissuer letsencrypt-prod
```

### 5.3 Criar Certificados

```yaml
# cert-manager/certificates.yaml
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: gitlab-tls
  namespace: gitlab
spec:
  secretName: gitlab-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - gitlab.seudominio.com.br
    - registry.seudominio.com.br
  duration: 2160h    # 90 dias
  renewBefore: 360h  # Renovar 15 dias antes
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: grafana-tls
  namespace: observability
spec:
  secretName: grafana-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - grafana.seudominio.com.br
  duration: 2160h
  renewBefore: 360h
```

**Aplicar:**
```bash
kubectl apply -f cert-manager/certificates.yaml

# Verificar status
kubectl get certificates -A
kubectl describe certificate gitlab-tls -n gitlab

# Verificar secret gerado
kubectl get secret gitlab-tls -n gitlab -o yaml
```

### 5.4 Configurar ALB com TLS

Atualizar Ingress para usar certificados:

```yaml
# ingress/gitlab-ingress-tls.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: gitlab
  namespace: gitlab
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    # Usar ACM se preferir (recomendado para produção)
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:ACCOUNT_ID:certificate/CERT_ID
    # OU usar cert-manager
    # cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
    - hosts:
        - gitlab.seudominio.com.br
      secretName: gitlab-tls
  rules:
    - host: gitlab.seudominio.com.br
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: gitlab-webservice-default
                port:
                  number: 8181
```

### 5.5 TLS Interno (mTLS)

Para comunicação interna com TLS:

```yaml
# cert-manager/internal-ca.yaml
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: internal-ca
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: internal-ca-cert
  namespace: cert-manager
spec:
  isCA: true
  commonName: internal-ca
  secretName: internal-ca-secret
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: internal-ca
    kind: ClusterIssuer
    group: cert-manager.io
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: internal-issuer
spec:
  ca:
    secretName: internal-ca-secret
```

---

## 6. AWS WAF

### 6.1 Criar Web ACL

#### Opção A: Terraform (Recomendado - IaC)

```hcl
# terraform/05-waf/main.tf

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "project_name" {
  default = "k8s-platform"
}

variable "allowed_ips" {
  description = "IPs permitidos (escritório, VPN)"
  type        = list(string)
  default     = ["203.0.113.0/24", "198.51.100.0/24"]
}

# IP Set para allowlist
resource "aws_wafv2_ip_set" "office_ips" {
  name               = "${var.project_name}-office-ips"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = var.allowed_ips

  tags = {
    Project = var.project_name
  }
}

# Web ACL
resource "aws_wafv2_web_acl" "main" {
  name        = "${var.project_name}-waf"
  description = "WAF para proteção da plataforma Kubernetes"
  scope       = "REGIONAL"

  default_action {
    block {}
  }

  # Rule 1: Allow Office IPs
  rule {
    name     = "AllowOfficeIPs"
    priority = 0

    action {
      allow {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.office_ips.arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AllowOfficeIPs"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: Rate Limiting
  rule {
    name     = "RateLimit"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimit"
      sampled_requests_enabled   = true
    }
  }

  # Rule 3: AWS Managed Rules - Common
  rule {
    name     = "AWSManagedRulesCommon"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommon"
      sampled_requests_enabled   = true
    }
  }

  # Rule 4: AWS Managed Rules - Known Bad Inputs
  rule {
    name     = "AWSManagedRulesBadInputs"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesBadInputs"
      sampled_requests_enabled   = true
    }
  }

  # Rule 5: AWS Managed Rules - SQL Injection
  rule {
    name     = "AWSManagedRulesSQLi"
    priority = 4

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesSQLiRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesSQLi"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Project = var.project_name
  }
}

# Associar WAF ao ALB
resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}

# CloudWatch Log Group para WAF
resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-${var.project_name}"
  retention_in_days = 30

  tags = {
    Project = var.project_name
  }
}

# WAF Logging Configuration
resource "aws_wafv2_web_acl_logging_configuration" "main" {
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
  resource_arn            = aws_wafv2_web_acl.main.arn
}

output "web_acl_arn" {
  value = aws_wafv2_web_acl.main.arn
}
```

#### Opção B: AWS CLI (Completo)

```bash
#!/bin/bash
# scripts/create-waf.sh

set -euo pipefail

PROJECT_NAME="k8s-platform"
REGION="us-east-1"

echo "🔒 Criando AWS WAF Web ACL..."

# 1. Criar IP Set para allowlist
echo "📝 Criando IP Set..."
IP_SET_RESPONSE=$(aws wafv2 create-ip-set \
  --name "${PROJECT_NAME}-office-ips" \
  --scope REGIONAL \
  --ip-address-version IPV4 \
  --addresses "203.0.113.0/24" "198.51.100.0/24" \
  --region $REGION \
  --tags Key=Project,Value=$PROJECT_NAME)

IP_SET_ARN=$(echo $IP_SET_RESPONSE | jq -r '.Summary.ARN')
echo "✅ IP Set criado: $IP_SET_ARN"

# 2. Criar Web ACL
echo "🛡️ Criando Web ACL com regras..."

cat > /tmp/waf-rules.json << EOF
[
  {
    "Name": "AllowOfficeIPs",
    "Priority": 0,
    "Statement": {
      "IPSetReferenceStatement": {
        "ARN": "$IP_SET_ARN"
      }
    },
    "Action": {"Allow": {}},
    "VisibilityConfig": {
      "SampledRequestsEnabled": true,
      "CloudWatchMetricsEnabled": true,
      "MetricName": "AllowOfficeIPs"
    }
  },
  {
    "Name": "RateLimit",
    "Priority": 1,
    "Statement": {
      "RateBasedStatement": {
        "Limit": 2000,
        "AggregateKeyType": "IP"
      }
    },
    "Action": {"Block": {}},
    "VisibilityConfig": {
      "SampledRequestsEnabled": true,
      "CloudWatchMetricsEnabled": true,
      "MetricName": "RateLimit"
    }
  },
  {
    "Name": "AWSManagedRulesCommon",
    "Priority": 2,
    "OverrideAction": {"None": {}},
    "Statement": {
      "ManagedRuleGroupStatement": {
        "VendorName": "AWS",
        "Name": "AWSManagedRulesCommonRuleSet"
      }
    },
    "VisibilityConfig": {
      "SampledRequestsEnabled": true,
      "CloudWatchMetricsEnabled": true,
      "MetricName": "AWSManagedRulesCommon"
    }
  },
  {
    "Name": "AWSManagedRulesBadInputs",
    "Priority": 3,
    "OverrideAction": {"None": {}},
    "Statement": {
      "ManagedRuleGroupStatement": {
        "VendorName": "AWS",
        "Name": "AWSManagedRulesKnownBadInputsRuleSet"
      }
    },
    "VisibilityConfig": {
      "SampledRequestsEnabled": true,
      "CloudWatchMetricsEnabled": true,
      "MetricName": "AWSManagedRulesBadInputs"
    }
  },
  {
    "Name": "AWSManagedRulesSQLi",
    "Priority": 4,
    "OverrideAction": {"None": {}},
    "Statement": {
      "ManagedRuleGroupStatement": {
        "VendorName": "AWS",
        "Name": "AWSManagedRulesSQLiRuleSet"
      }
    },
    "VisibilityConfig": {
      "SampledRequestsEnabled": true,
      "CloudWatchMetricsEnabled": true,
      "MetricName": "AWSManagedRulesSQLi"
    }
  }
]
EOF

WAF_RESPONSE=$(aws wafv2 create-web-acl \
  --name "${PROJECT_NAME}-waf" \
  --scope REGIONAL \
  --default-action Block={} \
  --visibility-config SampledRequestsEnabled=true,CloudWatchMetricsEnabled=true,MetricName=${PROJECT_NAME}-waf \
  --rules file:///tmp/waf-rules.json \
  --region $REGION \
  --tags Key=Project,Value=$PROJECT_NAME)

WAF_ARN=$(echo $WAF_RESPONSE | jq -r '.Summary.ARN')
echo "✅ Web ACL criado: $WAF_ARN"

# 3. Criar CloudWatch Log Group para WAF
echo "📊 Criando Log Group..."
aws logs create-log-group \
  --log-group-name "aws-waf-logs-${PROJECT_NAME}" \
  --region $REGION \
  --tags Project=$PROJECT_NAME || true

aws logs put-retention-policy \
  --log-group-name "aws-waf-logs-${PROJECT_NAME}" \
  --retention-in-days 30 \
  --region $REGION

# 4. Configurar logging do WAF
echo "📝 Configurando WAF logging..."
LOG_GROUP_ARN=$(aws logs describe-log-groups \
  --log-group-name-prefix "aws-waf-logs-${PROJECT_NAME}" \
  --query 'logGroups[0].arn' --output text --region $REGION)

aws wafv2 put-logging-configuration \
  --logging-configuration ResourceArn=$WAF_ARN,LogDestinationConfigs=[$LOG_GROUP_ARN] \
  --region $REGION
echo "✅ Logging configurado"

# 5. Associar ao ALB (se existir)
echo "🔗 Associando WAF ao ALB..."
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(LoadBalancerName, 'k8s-gitlab')].LoadBalancerArn" \
  --output text --region $REGION 2>/dev/null || echo "")

if [[ -n "$ALB_ARN" && "$ALB_ARN" != "None" ]]; then
  aws wafv2 associate-web-acl \
    --web-acl-arn $WAF_ARN \
    --resource-arn $ALB_ARN \
    --region $REGION
  echo "✅ WAF associado ao ALB: $ALB_ARN"
else
  echo "⚠️ ALB não encontrado. Associe manualmente após criar o Ingress:"
  echo "   aws wafv2 associate-web-acl --web-acl-arn $WAF_ARN --resource-arn <ALB_ARN>"
fi

# 6. Verificar
echo ""
echo "📋 Resumo:"
echo "  Web ACL ARN: $WAF_ARN"
echo "  IP Set ARN: $IP_SET_ARN"
echo "  Log Group: aws-waf-logs-${PROJECT_NAME}"
echo ""
echo "🎉 WAF criado com sucesso!"

# Limpeza
rm -f /tmp/waf-rules.json
```

#### Opção C: Console AWS (Referência Visual)

> ⚠️ **Nota:** Prefira as opções A (Terraform) ou B (CLI) para ambientes de produção.

1. **AWS Console** → **WAF & Shield** → **Web ACLs**

2. **Create web ACL**:
   - Name: `k8s-platform-waf`
   - Resource type: `Regional resources`
   - Region: `us-east-1`
   - Associated resources: Selecionar o ALB do GitLab

3. **Add rules** (na ordem de prioridade):

#### Rule 1: IP Allowlist (Prioridade 0)
```
Rule type: IP set
Name: office-ips-allow
IP set: Criar novo com IPs permitidos
  - 203.0.113.0/24 (Exemplo - IP do escritório)
  - 198.51.100.0/24 (Exemplo - VPN)
Action: Allow
```

#### Rule 2: Rate Limiting (Prioridade 1)
```
Rule type: Rate-based rule
Name: rate-limit-rule
Rate limit: 2000 requests per 5 minutes
Scope: Source IP address
Action: Block
```

#### Rule 3: AWS Managed Rules - Common (Prioridade 2)
```
Rule type: Add managed rule groups
Vendor: AWS
Rule group: AWSManagedRulesCommonRuleSet
Action: Block (usar defaults)
```

#### Rule 4: AWS Managed Rules - Known Bad Inputs (Prioridade 3)
```
Rule type: Add managed rule groups
Vendor: AWS
Rule group: AWSManagedRulesKnownBadInputsRuleSet
Action: Block
```

#### Rule 5: AWS Managed Rules - SQL Injection (Prioridade 4)
```
Rule type: Add managed rule groups
Vendor: AWS
Rule group: AWSManagedRulesSQLiRuleSet
Action: Block
```

4. **Default action**: Block

5. **Logging**: Habilitar para CloudWatch Logs
   - Log group: `/aws/waf/k8s-platform`

### 6.2 Criar IP Set via CLI

```bash
# Criar IP Set
aws wafv2 create-ip-set \
  --name "office-allowed-ips" \
  --scope REGIONAL \
  --ip-address-version IPV4 \
  --addresses "203.0.113.0/24" "198.51.100.0/24" \
  --region us-east-1

# Listar IP Sets
aws wafv2 list-ip-sets --scope REGIONAL --region us-east-1
```

### 6.3 Associar WAF ao ALB

```bash
# Obter ARN do ALB
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --names "k8s-gitlab-alb" \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

# Obter ARN do Web ACL
WAF_ARN=$(aws wafv2 list-web-acls \
  --scope REGIONAL \
  --region us-east-1 \
  --query "WebACLs[?Name=='k8s-platform-waf'].ARN" \
  --output text)

# Associar
aws wafv2 associate-web-acl \
  --web-acl-arn $WAF_ARN \
  --resource-arn $ALB_ARN \
  --region us-east-1
```

### 6.4 Verificar WAF

```bash
# Ver métricas do WAF
aws wafv2 get-sampled-requests \
  --web-acl-arn $WAF_ARN \
  --rule-metric-name "rate-limit-rule" \
  --scope REGIONAL \
  --time-window StartTime=2024-01-01T00:00:00Z,EndTime=2024-12-31T23:59:59Z \
  --max-items 10 \
  --region us-east-1
```

---

## 7. Security Groups Review

### 7.1 Script de Auditoria e Hardening (CLI-First)

```bash
#!/bin/bash
# scripts/audit-and-harden-security-groups.sh

set -euo pipefail

PROJECT_NAME="k8s-platform"
REGION="us-east-1"

echo "🔍 Auditoria de Security Groups..."

# 1. Encontrar SGs com regras 0.0.0.0/0 (exceto ALB)
echo ""
echo "=== Security Groups com 0.0.0.0/0 (potencial risco) ==="
aws ec2 describe-security-groups \
  --filters "Name=ip-permission.cidr,Values=0.0.0.0/0" \
  --query 'SecurityGroups[*].[GroupId,GroupName,Description]' \
  --output table --region $REGION

# 2. Detalhar regras problemáticas
echo ""
echo "=== Regras de entrada com 0.0.0.0/0 ==="
aws ec2 describe-security-groups \
  --filters "Name=ip-permission.cidr,Values=0.0.0.0/0" \
  --query 'SecurityGroups[*].{ID:GroupId,Name:GroupName,Ingress:IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`]]}' \
  --output json --region $REGION | jq -r '.[] | "\(.Name) (\(.ID)):" + (.Ingress | map("  - Port: \(.FromPort // "All") Protocol: \(.IpProtocol)") | join("\n"))'

# 3. Verificar SG do RDS
echo ""
echo "=== Verificando Security Group do RDS ==="
RDS_SG=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=*rds*" "Name=tag:Project,Values=$PROJECT_NAME" \
  --query 'SecurityGroups[0].GroupId' --output text --region $REGION)

if [[ -n "$RDS_SG" && "$RDS_SG" != "None" ]]; then
  RDS_RULES=$(aws ec2 describe-security-groups \
    --group-ids $RDS_SG \
    --query 'SecurityGroups[0].IpPermissions' --output json --region $REGION)

  # Verificar se tem regra 0.0.0.0/0
  if echo "$RDS_RULES" | jq -e '.[] | select(.IpRanges[].CidrIp == "0.0.0.0/0")' > /dev/null 2>&1; then
    echo "❌ ALERTA: RDS Security Group tem regra 0.0.0.0/0!"
    echo "   Recomendação: Restringir para apenas o Security Group dos nodes EKS"
  else
    echo "✅ RDS Security Group não tem regras 0.0.0.0/0"
  fi
fi

# 4. Função para hardening
harden_rds_sg() {
  local RDS_SG=$1
  local EKS_NODE_SG=$2

  echo "🔧 Aplicando hardening no RDS Security Group..."

  # Remover regras 0.0.0.0/0 se existirem
  OPEN_RULES=$(aws ec2 describe-security-groups \
    --group-ids $RDS_SG \
    --query 'SecurityGroups[0].IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`]]' \
    --output json --region $REGION)

  if [[ $(echo "$OPEN_RULES" | jq length) -gt 0 ]]; then
    echo "  Removendo regras abertas..."
    aws ec2 revoke-security-group-ingress \
      --group-id $RDS_SG \
      --ip-permissions "$OPEN_RULES" \
      --region $REGION
    echo "  ✅ Regras abertas removidas"
  fi

  # Adicionar regra restrita para EKS nodes
  echo "  Adicionando regra restrita para EKS nodes..."
  aws ec2 authorize-security-group-ingress \
    --group-id $RDS_SG \
    --protocol tcp \
    --port 5432 \
    --source-group $EKS_NODE_SG \
    --region $REGION 2>/dev/null || echo "  (Regra já existe)"

  echo "✅ RDS Security Group hardened"
}

# 5. Verificar se deve aplicar hardening
echo ""
read -p "Deseja aplicar hardening nos Security Groups? (y/n): " APPLY_HARDENING

if [[ "$APPLY_HARDENING" == "y" ]]; then
  # Obter SG IDs
  RDS_SG=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=*rds*" "Name=tag:Project,Values=$PROJECT_NAME" \
    --query 'SecurityGroups[0].GroupId' --output text --region $REGION)

  EKS_NODE_SG=$(aws ec2 describe-security-groups \
    --filters "Name=tag:aws:eks:cluster-name,Values=${PROJECT_NAME}-prod" \
    --query 'SecurityGroups[?contains(GroupName, `node`)].GroupId' --output text --region $REGION | head -1)

  if [[ -n "$RDS_SG" && -n "$EKS_NODE_SG" && "$RDS_SG" != "None" && "$EKS_NODE_SG" != "None" ]]; then
    harden_rds_sg $RDS_SG $EKS_NODE_SG
  else
    echo "⚠️ Não foi possível encontrar os Security Groups necessários"
  fi
fi

echo ""
echo "🎉 Auditoria concluída!"
```

### 7.2 Revisão dos Security Groups

| Security Group | Inbound | Outbound |
|----------------|---------|----------|
| **EKS Cluster SG** | 443 from VPC CIDR | All |
| **EKS Node SG** | All from Cluster SG, 10250 kubelet | All |
| **RDS SG** | 5432 from Node SG only | None |
| **ALB SG** | 80, 443 from 0.0.0.0/0 (ou IP list) | All to Node SG |

### 7.2 Hardening RDS Security Group

**Console AWS** → **VPC** → **Security Groups** → Selecionar SG do RDS

Remover regras amplas e manter apenas:

```
Inbound Rules:
- Type: PostgreSQL (5432)
- Source: sg-xxxxx (EKS Node Security Group)
- Description: "Allow PostgreSQL from EKS nodes only"

Outbound Rules:
- (Remover regras não necessárias)
```

### 7.3 Restringir ALB Security Group

Se não usar WAF com IP allowlist, restringir no SG:

```
Inbound Rules:
- Type: HTTPS (443)
- Source: 203.0.113.0/24 (Office IP)
- Description: "Allow HTTPS from office"

- Type: HTTPS (443)
- Source: 198.51.100.0/24 (VPN)
- Description: "Allow HTTPS from VPN"
```

### 7.4 Script de Auditoria de Security Groups

```bash
#!/bin/bash
# audit-security-groups.sh

echo "=== Security Groups com 0.0.0.0/0 ==="
aws ec2 describe-security-groups \
  --filters "Name=ip-permission.cidr,Values=0.0.0.0/0" \
  --query 'SecurityGroups[*].[GroupId,GroupName,Description]' \
  --output table

echo ""
echo "=== Regras de entrada com 0.0.0.0/0 ==="
aws ec2 describe-security-groups \
  --filters "Name=ip-permission.cidr,Values=0.0.0.0/0" \
  --query 'SecurityGroups[*].{ID:GroupId,Name:GroupName,Rules:IpPermissions[?contains(IpRanges[].CidrIp,`0.0.0.0/0`)]}' \
  --output json | jq '.[] | {ID,Name,Ports: [.Rules[].FromPort]}'
```

---

## 8. Secrets Management

### 8.1 AWS Secrets Manager

#### Criar Secrets no Console

1. **AWS Console** → **Secrets Manager** → **Store a new secret**

2. **GitLab DB Password**:
   - Secret type: Other type of secret
   - Key/value:
     - `password`: `<senha-complexa-gerada>`
   - Secret name: `k8s-platform/gitlab/db-password`
   - Tags: `Environment=production`, `Application=gitlab`

3. **GitLab Root Password**:
   - Secret name: `k8s-platform/gitlab/root-password`

4. **Redis Password**:
   - Secret name: `k8s-platform/redis/password`

5. **RabbitMQ Password**:
   - Secret name: `k8s-platform/rabbitmq/password`

### 8.2 External Secrets Operator

```bash
# Instalar External Secrets
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true
```

### 8.3 Configurar SecretStore

```yaml
# external-secrets/secret-store.yaml
---
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
```

### 8.4 Criar ExternalSecrets

```yaml
# external-secrets/gitlab-secrets.yaml
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: gitlab-db-password
  namespace: gitlab
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: gitlab-postgresql-password
    creationPolicy: Owner
  data:
    - secretKey: postgresql-password
      remoteRef:
        key: k8s-platform/gitlab/db-password
        property: password
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: gitlab-root-password
  namespace: gitlab
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: gitlab-initial-root-password
    creationPolicy: Owner
  data:
    - secretKey: password
      remoteRef:
        key: k8s-platform/gitlab/root-password
        property: password
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: redis-password
  namespace: data-services
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: redis-password
    creationPolicy: Owner
  data:
    - secretKey: redis-password
      remoteRef:
        key: k8s-platform/redis/password
        property: password
```

**Aplicar:**
```bash
kubectl apply -f external-secrets/

# Verificar sync
kubectl get externalsecrets -A
kubectl describe externalsecret gitlab-db-password -n gitlab

# Verificar secret criado
kubectl get secret gitlab-postgresql-password -n gitlab
```

### 8.5 IRSA para External Secrets

```bash
# Criar IAM Policy
cat > external-secrets-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:us-east-1:ACCOUNT_ID:secret:k8s-platform/*"
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name ExternalSecretsPolicy \
  --policy-document file://external-secrets-policy.json

# Criar IRSA
eksctl create iamserviceaccount \
  --cluster=k8s-platform-cluster \
  --namespace=external-secrets \
  --name=external-secrets \
  --attach-policy-arn=arn:aws:iam::ACCOUNT_ID:policy/ExternalSecretsPolicy \
  --approve
```

---

## 9. Validação de Segurança

### 9.1 Checklist de Testes

```bash
#!/bin/bash
# security-validation.sh

echo "=== 1. Network Policies ==="
echo "Testando deny padrão..."
kubectl run test-pod --image=busybox -n default --restart=Never -- sleep 3600
sleep 10
kubectl exec -n default test-pod -- nc -zv -w5 redis.data-services.svc.cluster.local 6379 2>&1 || echo "PASS: Conexão bloqueada"
kubectl delete pod test-pod -n default

echo ""
echo "=== 2. Pod Security ==="
echo "Testando pod privilegiado (deve falhar)..."
kubectl run priv-pod --image=busybox -n gitlab --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"priv","image":"busybox","securityContext":{"privileged":true}}]}}' 2>&1 || echo "PASS: Pod privilegiado bloqueado"

echo ""
echo "=== 3. RBAC ==="
echo "Testando permissões do runner..."
kubectl auth can-i create pods -n gitlab --as=system:serviceaccount:gitlab:gitlab-runner
kubectl auth can-i create pods -n kube-system --as=system:serviceaccount:gitlab:gitlab-runner && echo "FAIL" || echo "PASS: Acesso cross-namespace bloqueado"

echo ""
echo "=== 4. TLS ==="
echo "Verificando certificados..."
kubectl get certificates -A
echo "Testando HTTPS..."
curl -sI https://gitlab.seudominio.com.br | head -5

echo ""
echo "=== 5. Secrets ==="
echo "Verificando External Secrets sync..."
kubectl get externalsecrets -A -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[0].reason

echo ""
echo "=== 6. Security Groups ==="
echo "SGs com 0.0.0.0/0..."
aws ec2 describe-security-groups \
  --filters "Name=ip-permission.cidr,Values=0.0.0.0/0" \
  --query 'SecurityGroups[*].GroupName' --output text
```

### 9.2 Ferramentas de Scanning

```bash
# Instalar kube-bench (CIS Benchmark)
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job-eks.yaml

# Ver resultados
kubectl logs -l app=kube-bench --tail=-1

# Instalar trivy para scan de imagens
helm repo add aqua https://aquasecurity.github.io/helm-charts/
helm install trivy-operator aqua/trivy-operator \
  --namespace trivy-system \
  --create-namespace \
  --set trivy.ignoreUnfixed=true

# Ver vulnerabilidades
kubectl get vulnerabilityreports -A
```

### 9.3 Alertas de Segurança no Prometheus

```yaml
# prometheus-rules/security-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: security-alerts
  namespace: observability
spec:
  groups:
    - name: security
      rules:
        - alert: PodSecurityViolation
          expr: |
            count(kube_pod_status_phase{phase="Pending"}
            and on(pod,namespace) kube_pod_labels{label_pod_security_kubernetes_io_enforce="restricted"}) > 0
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Pod pending devido a violação de segurança"

        - alert: NetworkPolicyMissing
          expr: |
            count by (namespace) (kube_pod_info)
            unless count by (namespace) (kube_networkpolicy_labels)
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Namespace {{ $labels.namespace }} sem Network Policy"

        - alert: TLSCertificateExpiringSoon
          expr: certmanager_certificate_expiration_timestamp_seconds - time() < 604800
          for: 1h
          labels:
            severity: warning
          annotations:
            summary: "Certificado {{ $labels.name }} expira em menos de 7 dias"

        - alert: ExternalSecretSyncFailed
          expr: externalsecret_status_condition{condition="Ready",status="False"} == 1
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "ExternalSecret {{ $labels.name }} falhou sync"
```

---

## 10. Checklist de Conclusão

### 10.1 Definition of Done - Épico G

| Item | Critério | Status |
|------|----------|--------|
| Network Policies | Default deny aplicado em todos namespaces | ☐ |
| Network Policies | Policies específicas para GitLab, Data, Observability | ☐ |
| Pod Security | PSA labels aplicados nos namespaces | ☐ |
| RBAC | Service Accounts específicos por aplicação | ☐ |
| RBAC | Least-privilege roles configurados | ☐ |
| cert-manager | Instalado e ClusterIssuers configurados | ☐ |
| TLS | Certificados emitidos para GitLab e Grafana | ☐ |
| WAF | Web ACL criado com regras básicas | ☐ |
| WAF | Rate limiting configurado | ☐ |
| Security Groups | Revisados e restringidos | ☐ |
| Secrets | External Secrets Operator configurado | ☐ |
| Secrets | Secrets migrados para AWS Secrets Manager | ☐ |
| Validação | Testes de segurança executados | ☐ |
| Alertas | PrometheusRules de segurança configurados | ☐ |

### 10.2 Comandos de Verificação Final

```bash
# Network Policies
kubectl get networkpolicies -A | wc -l
# Esperado: >= 10

# Pod Security
kubectl get ns --show-labels | grep pod-security

# RBAC
kubectl get serviceaccounts -A | grep -E 'gitlab|loki|tempo'

# Certificados
kubectl get certificates -A
kubectl get clusterissuers

# WAF
aws wafv2 list-web-acls --scope REGIONAL --region us-east-1

# External Secrets
kubectl get externalsecrets -A -o custom-columns=NAME:.metadata.name,READY:.status.conditions[0].status
```

### 10.3 Próximos Passos

- **Doc 06**: [Backup e Disaster Recovery](./06-backup-disaster-recovery.md) - Velero, AWS Backup, DR Drill

---

## Referências

- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [AWS WAF Documentation](https://docs.aws.amazon.com/waf/)
- [External Secrets Operator](https://external-secrets.io/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
