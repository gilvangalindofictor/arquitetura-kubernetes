# 04 - Observability Stack

**Épicos D, E, F** | **Esforço: 84 person-hours** | **Sprint 2** | **Status: 🟡 75% Completo**

**Última Atualização:** 2026-01-28

---

## 📊 Status Atual (2026-01-28)

| Fase | Componente | Status | Detalhes |
|------|------------|--------|----------|
| **Fase 1** | AWS Load Balancer Controller | ✅ COMPLETO | v1.11.0, IRSA configurado |
| **Fase 2** | Cert-Manager | ✅ COMPLETO | v1.16.3, CRDs provisionados |
| **Fase 3** | kube-prometheus-stack | ✅ COMPLETO | 13 pods Running, 3 PVCs (27Gi), Grafana acessível |
| **Fase 4** | Loki + Fluent Bit | 📝 CÓDIGO IMPLEMENTADO | Aguardando deploy (ADR-005, módulos Terraform criados) |
| **Fase 5** | Network Policies | ⏳ PENDENTE | Planejado |
| **Fase 6** | Cluster Autoscaler | ⏳ PENDENTE | Planejado |
| **Fase 7** | Aplicações de Teste | ⏳ PENDENTE | Planejado |

**Progresso Geral:** 🟡 75% (Fases 1-3 completas, Fase 4 código pronto)

---

## Sumário

1. [Visão Geral](#1-visão-geral)
2. [Task D.1: OpenTelemetry Collector (12h)](#2-task-d1-opentelemetry-collector-12h)
3. [Task D.2: kube-prometheus-stack (16h)](#3-task-d2-kube-prometheus-stack-16h)
4. [Task D.3: Prometheus Scraping e Retention (6h)](#4-task-d3-prometheus-scraping-e-retention-6h)
5. [Task E.1: Loki para Logs (12h)](#5-task-e1-loki-para-logs-12h)
6. [Task E.2: Tempo para Traces (8h)](#6-task-e2-tempo-para-traces-8h)
7. [Task E.3: Pipelines OTEL (8h)](#7-task-e3-pipelines-otel-8h)
8. [Task F.1: Grafana e Datasources (6h)](#8-task-f1-grafana-e-datasources-6h)
9. [Task F.2: Dashboards Baseline (10h)](#9-task-f2-dashboards-baseline-10h)
10. [Task F.3: Alertmanager (6h)](#10-task-f3-alertmanager-6h)
11. [Validação e Definition of Done](#11-validação-e-definition-of-done)

---

## 1. Visão Geral

### Objetivo

Implementar stack de observabilidade completa seguindo o modelo de três pilares:

| Pilar | Ferramenta | Storage |
|-------|------------|---------|
| **Métricas** | Prometheus | PVC (EBS) |
| **Logs** | Loki | S3 |
| **Traces** | Tempo | S3 |

### Arquitetura

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         OBSERVABILITY ARCHITECTURE                          │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    COLLECTION LAYER                                  │   │
│  │                                                                      │   │
│  │  ┌───────────────────────────────────────────────────────────────┐  │   │
│  │  │            OpenTelemetry Collector (DaemonSet)                 │  │   │
│  │  │                                                                │  │   │
│  │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐           │  │   │
│  │  │  │ Metrics     │  │ Logs        │  │ Traces      │           │  │   │
│  │  │  │ Receiver    │  │ Receiver    │  │ Receiver    │           │  │   │
│  │  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘           │  │   │
│  │  │         │                │                │                   │  │   │
│  │  │         ▼                ▼                ▼                   │  │   │
│  │  │  ┌─────────────────────────────────────────────────────────┐ │  │   │
│  │  │  │                    OTEL Pipeline                         │ │  │   │
│  │  │  │  processors: batch, memory_limiter, resourcedetection   │ │  │   │
│  │  │  └─────────────────────────────────────────────────────────┘ │  │   │
│  │  │         │                │                │                   │  │   │
│  │  └─────────┼────────────────┼────────────────┼───────────────────┘  │   │
│  │            │                │                │                       │   │
│  └────────────┼────────────────┼────────────────┼───────────────────────┘   │
│               │                │                │                           │
│               ▼                ▼                ▼                           │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    STORAGE LAYER                                     │   │
│  │                                                                      │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐     │   │
│  │  │ Prometheus      │  │ Loki            │  │ Tempo           │     │   │
│  │  │ (Metrics)       │  │ (Logs)          │  │ (Traces)        │     │   │
│  │  │ PVC: 100Gi      │  │ S3 Backend      │  │ S3 Backend      │     │   │
│  │  │ Retention: 15d  │  │ Retention: 30d  │  │ Retention: 7d   │     │   │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘     │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    VISUALIZATION LAYER                               │   │
│  │                                                                      │   │
│  │  ┌─────────────────────────────────────────────────────────────┐   │   │
│  │  │                        GRAFANA                               │   │   │
│  │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │   │   │
│  │  │  │ Metrics     │  │ Logs        │  │ Traces      │         │   │   │
│  │  │  │ Explore     │  │ Explore     │  │ Explore     │         │   │   │
│  │  │  └─────────────┘  └─────────────┘  └─────────────┘         │   │   │
│  │  │                                                              │   │   │
│  │  │  ┌─────────────────────────────────────────────────────┐   │   │   │
│  │  │  │              Dashboards (10+)                        │   │   │   │
│  │  │  │  • K8s Cluster • Nodes • GitLab CI • SLIs • Alerts  │   │   │   │
│  │  │  └─────────────────────────────────────────────────────┘   │   │   │
│  │  └─────────────────────────────────────────────────────────────┘   │   │
│  │                                                                      │   │
│  │  ┌─────────────────────────────────────────────────────────────┐   │   │
│  │  │                     ALERTMANAGER                             │   │   │
│  │  │  Routes: critical → PagerDuty, warning → Slack, Email       │   │   │
│  │  └─────────────────────────────────────────────────────────────┘   │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Helm Charts Utilizados

| Chart | Versão | Repository |
|-------|--------|------------|
| `open-telemetry/opentelemetry-collector` | v0.76.x | https://open-telemetry.github.io/opentelemetry-helm-charts |
| `prometheus-community/kube-prometheus-stack` | v55.x | https://prometheus-community.github.io/helm-charts |
| `grafana/loki` | v5.x | https://grafana.github.io/helm-charts |
| `grafana/tempo` | v1.7.x | https://grafana.github.io/helm-charts |

---

## 2. Task D.1: OpenTelemetry Collector (12h)

### 2.1 Criar Namespace

```bash
kubectl create namespace observability

kubectl label namespace observability \
  project=k8s-platform \
  environment=prod \
  domain=observability
```

### 2.2 Adicionar Repositório Helm

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update
```

### 2.3 Criar values.yaml para OTEL Collector

```bash
cat > otel-collector-values.yaml <<'EOF'
# =============================================================================
# OpenTelemetry Collector - values.yaml
# =============================================================================
# Mode: DaemonSet (node collector) + Deployment (gateway)
# =============================================================================

# Modo de deploy
mode: daemonset

# Imagem
image:
  repository: otel/opentelemetry-collector-contrib
  tag: "0.91.0"

# Resources
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi

# Presets (habilita receivers comuns automaticamente)
presets:
  logsCollection:
    enabled: true
    includeCollectorLogs: false
  kubernetesAttributes:
    enabled: true
  kubeletMetrics:
    enabled: true
  hostMetrics:
    enabled: true

# Configuração do collector
config:
  receivers:
    # OTLP para aplicações instrumentadas
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318

    # Prometheus scraping
    prometheus:
      config:
        scrape_configs:
          - job_name: 'otel-collector'
            scrape_interval: 30s
            static_configs:
              - targets: ['localhost:8888']

    # Jaeger (para compatibilidade)
    jaeger:
      protocols:
        grpc:
          endpoint: 0.0.0.0:14250
        thrift_http:
          endpoint: 0.0.0.0:14268

  processors:
    # Batch para eficiência
    batch:
      send_batch_size: 10000
      timeout: 10s
      send_batch_max_size: 11000

    # Limite de memória
    memory_limiter:
      check_interval: 5s
      limit_mib: 400
      spike_limit_mib: 100

    # Adicionar atributos do K8s
    k8sattributes:
      auth_type: "serviceAccount"
      passthrough: false
      extract:
        metadata:
          - k8s.pod.name
          - k8s.pod.uid
          - k8s.deployment.name
          - k8s.namespace.name
          - k8s.node.name
          - k8s.pod.start_time
        labels:
          - tag_name: app
            key: app
            from: pod
          - tag_name: environment
            key: environment
            from: namespace
      pod_association:
        - sources:
            - from: resource_attribute
              name: k8s.pod.ip
        - sources:
            - from: resource_attribute
              name: k8s.pod.uid

    # Resource detection
    resourcedetection:
      detectors: [env, eks, ec2]
      timeout: 5s
      override: false

  exporters:
    # Para Prometheus
    prometheusremotewrite:
      endpoint: "http://prometheus-kube-prometheus-prometheus.observability:9090/api/v1/write"
      tls:
        insecure: true

    # Para Loki
    loki:
      endpoint: "http://loki-gateway.observability:3100/loki/api/v1/push"
      tls:
        insecure: true
      labels:
        attributes:
          k8s.namespace.name: "namespace"
          k8s.pod.name: "pod"
          k8s.container.name: "container"

    # Para Tempo
    otlp/tempo:
      endpoint: "http://tempo.observability:4317"
      tls:
        insecure: true

    # Debug (para troubleshooting)
    debug:
      verbosity: basic

  service:
    pipelines:
      metrics:
        receivers: [otlp, prometheus]
        processors: [memory_limiter, k8sattributes, resourcedetection, batch]
        exporters: [prometheusremotewrite]

      logs:
        receivers: [otlp]
        processors: [memory_limiter, k8sattributes, resourcedetection, batch]
        exporters: [loki]

      traces:
        receivers: [otlp, jaeger]
        processors: [memory_limiter, k8sattributes, resourcedetection, batch]
        exporters: [otlp/tempo]

    telemetry:
      logs:
        level: info
      metrics:
        address: 0.0.0.0:8888

# Service
service:
  type: ClusterIP

# Node selector
nodeSelector:
  node-type: workloads

# Tolerations para rodar em todos os nodes
tolerations:
  - operator: Exists

# Pod annotations
podAnnotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8888"

# RBAC
serviceAccount:
  create: true
  name: otel-collector

clusterRole:
  create: true
  rules:
    - apiGroups: [""]
      resources: ["pods", "namespaces", "nodes", "nodes/stats"]
      verbs: ["get", "list", "watch"]
    - apiGroups: ["apps"]
      resources: ["replicasets", "deployments"]
      verbs: ["get", "list", "watch"]

EOF
```

### 2.4 Instalar OTEL Collector

```bash
helm install otel-collector open-telemetry/opentelemetry-collector \
  --namespace observability \
  --values otel-collector-values.yaml \
  --version 0.76.0 \
  --wait

# Verificar
kubectl get pods -n observability -l app.kubernetes.io/name=opentelemetry-collector
kubectl get daemonset -n observability
```

---

## 3. Task D.2: kube-prometheus-stack (16h)

### 3.1 Adicionar Repositório

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

### 3.2 Criar S3 Bucket para Thanos (Opcional)

Se quiser armazenamento de longo prazo com Thanos:

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws s3 mb s3://k8s-platform-thanos-${AWS_ACCOUNT_ID} --region us-east-1

aws s3api put-bucket-encryption \
  --bucket k8s-platform-thanos-${AWS_ACCOUNT_ID} \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'
```

### 3.3 Criar values.yaml para kube-prometheus-stack

```bash
cat > prometheus-stack-values.yaml <<'EOF'
# =============================================================================
# kube-prometheus-stack - values.yaml
# =============================================================================

# -----------------------------------------------------------------------------
# ALERTMANAGER
# -----------------------------------------------------------------------------
alertmanager:
  enabled: true

  config:
    global:
      resolve_timeout: 5m

    route:
      group_by: ['alertname', 'namespace', 'severity']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      receiver: 'default'
      routes:
        - match:
            severity: critical
          receiver: 'critical'
          continue: true
        - match:
            severity: warning
          receiver: 'warning'

    receivers:
      - name: 'default'
        # Configurar webhook, email, slack, etc.

      - name: 'critical'
        # Configurar PagerDuty ou similar

      - name: 'warning'
        # Configurar Slack ou similar

  alertmanagerSpec:
    replicas: 2
    retention: 120h

    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: gp3
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi

    resources:
      requests:
        cpu: 50m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi

    nodeSelector:
      node-type: workloads

# -----------------------------------------------------------------------------
# GRAFANA
# -----------------------------------------------------------------------------
grafana:
  enabled: true

  replicas: 2

  adminPassword: ""  # Será gerado automaticamente

  ingress:
    enabled: true
    ingressClassName: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
      alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:ACCOUNT_ID:certificate/CERT_ID
      alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS13-1-2-2021-06
    hosts:
      - grafana.gitlab.empresa.com.br
    tls:
      - hosts:
          - grafana.gitlab.empresa.com.br

  persistence:
    enabled: true
    type: pvc
    storageClassName: gp3
    size: 10Gi

  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

  nodeSelector:
    node-type: workloads

  # Datasources (serão configurados automaticamente)
  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
        - name: Prometheus
          type: prometheus
          url: http://prometheus-kube-prometheus-prometheus:9090
          access: proxy
          isDefault: true

        - name: Loki
          type: loki
          url: http://loki-gateway:3100
          access: proxy
          jsonData:
            derivedFields:
              - datasourceUid: tempo
                matcherRegex: "traceID=(\\w+)"
                name: TraceID
                url: "$${__value.raw}"

        - name: Tempo
          type: tempo
          url: http://tempo:3100
          access: proxy
          uid: tempo
          jsonData:
            tracesToLogs:
              datasourceUid: loki
              tags: ['namespace', 'pod']

  # Dashboards providers
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: 'default'
          orgId: 1
          folder: ''
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards/default

  # Dashboards from ConfigMaps
  dashboardsConfigMaps:
    default: grafana-dashboards

  # Grafana.ini
  grafana.ini:
    server:
      root_url: https://grafana.gitlab.empresa.com.br
    analytics:
      check_for_updates: false
    log:
      mode: console
      level: info
    auth:
      disable_login_form: false
    auth.anonymous:
      enabled: false

# -----------------------------------------------------------------------------
# PROMETHEUS
# -----------------------------------------------------------------------------
prometheus:
  enabled: true

  prometheusSpec:
    replicas: 2

    retention: 15d
    retentionSize: "80GB"

    # Remote write para OTEL (se configurado)
    remoteWrite: []

    # Scrape interval
    scrapeInterval: 30s
    evaluationInterval: 30s

    # Storage
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: gp3
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 100Gi

    # Resources
    resources:
      requests:
        cpu: 500m
        memory: 2Gi
      limits:
        cpu: 2000m
        memory: 4Gi

    # Node placement
    nodeSelector:
      node-type: critical

    # Tolerations para nodes críticos
    tolerations:
      - key: "workload"
        operator: "Equal"
        value: "critical"
        effect: "NoSchedule"

    # Service Monitors seletor
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false

    # Habilitar admin API
    enableAdminAPI: true

# -----------------------------------------------------------------------------
# NODE EXPORTER
# -----------------------------------------------------------------------------
nodeExporter:
  enabled: true

  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 128Mi

# -----------------------------------------------------------------------------
# KUBE STATE METRICS
# -----------------------------------------------------------------------------
kubeStateMetrics:
  enabled: true

  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi

# -----------------------------------------------------------------------------
# PROMETHEUS OPERATOR
# -----------------------------------------------------------------------------
prometheusOperator:
  enabled: true

  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

  nodeSelector:
    node-type: workloads

# -----------------------------------------------------------------------------
# COMMON LABELS
# -----------------------------------------------------------------------------
commonLabels:
  project: k8s-platform
  environment: prod

# -----------------------------------------------------------------------------
# DEFAULT RULES
# -----------------------------------------------------------------------------
defaultRules:
  create: true
  rules:
    alertmanager: true
    etcd: true
    configReloaders: true
    general: true
    k8s: true
    kubeApiserverAvailability: true
    kubeApiserverBurnrate: true
    kubeApiserverHistogram: true
    kubeApiserverSlos: true
    kubelet: true
    kubeProxy: true
    kubePrometheusGeneral: true
    kubePrometheusNodeRecording: true
    kubernetesApps: true
    kubernetesResources: true
    kubernetesStorage: true
    kubernetesSystem: true
    kubeScheduler: true
    kubeStateMetrics: true
    network: true
    node: true
    nodeExporterAlerting: true
    nodeExporterRecording: true
    prometheus: true
    prometheusOperator: true

EOF
```

### 3.4 Instalar kube-prometheus-stack

```bash
# Substituir placeholders
sed -i "s/ACCOUNT_ID/$(aws sts get-caller-identity --query Account --output text)/g" prometheus-stack-values.yaml
sed -i "s/CERT_ID/seu-cert-id/g" prometheus-stack-values.yaml

# Instalar
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace observability \
  --values prometheus-stack-values.yaml \
  --version 55.5.0 \
  --timeout 600s \
  --wait

# Verificar
kubectl get pods -n observability -l "release=prometheus"
```

---

## 4. Task D.3: Prometheus Scraping e Retention (6h)

### 4.1 Criar ServiceMonitor para GitLab

```bash
cat > gitlab-servicemonitor.yaml <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: gitlab-webservice
  namespace: observability
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app: webservice
  namespaceSelector:
    matchNames:
      - gitlab
  endpoints:
    - port: http-metrics
      interval: 30s
      path: /metrics
EOF

kubectl apply -f gitlab-servicemonitor.yaml
```

### 4.2 Criar ServiceMonitor para Redis

```bash
cat > redis-servicemonitor.yaml <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: redis
  namespace: observability
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: redis
  namespaceSelector:
    matchNames:
      - redis
  endpoints:
    - port: metrics
      interval: 30s
EOF

kubectl apply -f redis-servicemonitor.yaml
```

### 4.3 Criar ServiceMonitor para RabbitMQ

```bash
cat > rabbitmq-servicemonitor.yaml <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: rabbitmq
  namespace: observability
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: rabbitmq
  namespaceSelector:
    matchNames:
      - rabbitmq
  endpoints:
    - port: metrics
      interval: 30s
EOF

kubectl apply -f rabbitmq-servicemonitor.yaml
```

### 4.4 Verificar Targets

```bash
# Port-forward para acessar Prometheus UI
kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n observability 9090:9090

# Acesse http://localhost:9090/targets
# Verifique se todos os targets estão UP
```

---

## 5. Task E.1: Loki para Logs (12h)

**Status Atual (2026-01-28):** ✅ **IMPLEMENTADO NO TERRAFORM - AGUARDANDO DEPLOY**

> **Nota Importante:** Esta task foi implementada via **Terraform modules** no Marco 2 em vez de comandos manuais Helm.
>
> **Arquivos Implementados:**
> - `modules/loki/main.tf` (330 linhas) - S3 bucket, IAM Role/Policy (IRSA), Helm release
> - `modules/fluent-bit/main.tf` (270 linhas) - DaemonSet, parsers, Loki output
> - `marco2/main.tf` - Integration dos módulos
> - ADR-005: Logging Strategy (Loki escolhido, CloudWatch em hold)
>
> **Deploy Instructions:** Ver [FASE4-IMPLEMENTATION.md](../../../platform-provisioning/aws/kubernetes/terraform/envs/marco2/FASE4-IMPLEMENTATION.md)
>
> **Economia:** $423/ano vs CloudWatch (~64% economia)

---

### Implementação Manual (Referência - Não Executar)

> **ATENÇÃO:** As seções abaixo são mantidas como referência técnica. A implementação real está no Terraform.

### 5.1 Adicionar Repositório

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

### 5.2 Criar Bucket S3 para Loki

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws s3 mb s3://k8s-platform-loki-${AWS_ACCOUNT_ID} --region us-east-1

aws s3api put-bucket-lifecycle-configuration \
  --bucket k8s-platform-loki-${AWS_ACCOUNT_ID} \
  --lifecycle-configuration '{
    "Rules": [
      {
        "ID": "expire-old-logs",
        "Status": "Enabled",
        "Expiration": {"Days": 30},
        "Filter": {"Prefix": ""}
      }
    ]
  }'
```

### 5.3 Criar values.yaml para Loki

```bash
cat > loki-values.yaml <<'EOF'
# =============================================================================
# Loki - values.yaml
# =============================================================================
# Mode: Simple Scalable
# =============================================================================

# Deployment mode
deploymentMode: SimpleScalable

# Loki config
loki:
  auth_enabled: false

  commonConfig:
    replication_factor: 2
    path_prefix: /var/loki

  storage:
    type: s3
    bucketNames:
      chunks: k8s-platform-loki-ACCOUNT_ID
      ruler: k8s-platform-loki-ACCOUNT_ID
      admin: k8s-platform-loki-ACCOUNT_ID
    s3:
      region: us-east-1
      # Usar IRSA para autenticação
      # insecure: false
      # s3ForcePathStyle: false

  schemaConfig:
    configs:
      - from: "2024-01-01"
        store: tsdb
        object_store: s3
        schema: v12
        index:
          prefix: loki_index_
          period: 24h

  limits_config:
    retention_period: 720h  # 30 dias
    max_query_length: 721h
    max_query_parallelism: 32
    max_query_series: 500
    split_queries_by_interval: 15m
    ingestion_rate_mb: 10
    ingestion_burst_size_mb: 20
    per_stream_rate_limit: 5MB
    per_stream_rate_limit_burst: 15MB

  compactor:
    working_directory: /var/loki/compactor
    shared_store: s3
    compaction_interval: 10m
    retention_enabled: true
    retention_delete_delay: 2h

# -----------------------------------------------------------------------------
# READ PATH
# -----------------------------------------------------------------------------
read:
  replicas: 2

  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

  nodeSelector:
    node-type: workloads

# -----------------------------------------------------------------------------
# WRITE PATH
# -----------------------------------------------------------------------------
write:
  replicas: 2

  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

  persistence:
    enabled: true
    storageClass: gp3
    size: 10Gi

  nodeSelector:
    node-type: workloads

# -----------------------------------------------------------------------------
# BACKEND
# -----------------------------------------------------------------------------
backend:
  replicas: 2

  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

  persistence:
    enabled: true
    storageClass: gp3
    size: 10Gi

  nodeSelector:
    node-type: workloads

# -----------------------------------------------------------------------------
# GATEWAY
# -----------------------------------------------------------------------------
gateway:
  enabled: true
  replicas: 2

  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 128Mi

  nodeSelector:
    node-type: workloads

# -----------------------------------------------------------------------------
# MINIO (Desabilitado - usando S3)
# -----------------------------------------------------------------------------
minio:
  enabled: false

# -----------------------------------------------------------------------------
# SERVICE ACCOUNT
# -----------------------------------------------------------------------------
serviceAccount:
  create: true
  name: loki
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/LokiS3Role

# -----------------------------------------------------------------------------
# MONITORING
# -----------------------------------------------------------------------------
monitoring:
  selfMonitoring:
    enabled: true
    grafanaAgent:
      installOperator: false
  serviceMonitor:
    enabled: true
    namespace: observability

EOF
```

### 5.4 Criar IAM Role para Loki (IRSA)

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
OIDC_ID=$(aws eks describe-cluster --name k8s-platform-prod --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5)

# Criar policy
cat > loki-s3-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket",
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3:::k8s-platform-loki-${AWS_ACCOUNT_ID}",
                "arn:aws:s3:::k8s-platform-loki-${AWS_ACCOUNT_ID}/*"
            ]
        }
    ]
}
EOF

aws iam create-policy --policy-name LokiS3Policy --policy-document file://loki-s3-policy.json

# Criar trust policy
cat > loki-trust-policy.json <<EOF
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
                    "oidc.eks.us-east-1.amazonaws.com/id/${OIDC_ID}:sub": "system:serviceaccount:observability:loki"
                }
            }
        }
    ]
}
EOF

aws iam create-role --role-name LokiS3Role --assume-role-policy-document file://loki-trust-policy.json
aws iam attach-role-policy --role-name LokiS3Role --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/LokiS3Policy
```

### 5.5 Instalar Loki

```bash
# Substituir placeholders
sed -i "s/ACCOUNT_ID/${AWS_ACCOUNT_ID}/g" loki-values.yaml

# Instalar
helm install loki grafana/loki \
  --namespace observability \
  --values loki-values.yaml \
  --version 5.42.0 \
  --timeout 600s \
  --wait

# Verificar
kubectl get pods -n observability -l app.kubernetes.io/name=loki
```

---

## 6. Task E.2: Tempo para Traces (8h)

### 6.1 Criar Bucket S3 para Tempo

```bash
aws s3 mb s3://k8s-platform-tempo-${AWS_ACCOUNT_ID} --region us-east-1
```

### 6.2 Criar values.yaml para Tempo

```bash
cat > tempo-values.yaml <<'EOF'
# =============================================================================
# Tempo - values.yaml
# =============================================================================
# Mode: Distributed
# =============================================================================

# Tempo config
tempo:
  storage:
    trace:
      backend: s3
      s3:
        bucket: k8s-platform-tempo-ACCOUNT_ID
        endpoint: s3.us-east-1.amazonaws.com
        region: us-east-1

  retention: 168h  # 7 dias

  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318
    jaeger:
      protocols:
        thrift_http:
          endpoint: 0.0.0.0:14268
        grpc:
          endpoint: 0.0.0.0:14250

# -----------------------------------------------------------------------------
# COMPONENTS
# -----------------------------------------------------------------------------
distributor:
  replicas: 2
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

ingester:
  replicas: 2
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi
  persistence:
    enabled: true
    storageClass: gp3
    size: 10Gi

querier:
  replicas: 2
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

queryFrontend:
  replicas: 2
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 256Mi

compactor:
  replicas: 1
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

# -----------------------------------------------------------------------------
# SERVICE ACCOUNT
# -----------------------------------------------------------------------------
serviceAccount:
  create: true
  name: tempo
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/TempoS3Role

# -----------------------------------------------------------------------------
# MONITORING
# -----------------------------------------------------------------------------
metaMonitoring:
  serviceMonitor:
    enabled: true
    namespace: observability

EOF
```

### 6.3 Criar IAM Role para Tempo

```bash
# Criar policy (similar ao Loki)
cat > tempo-s3-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket",
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3:::k8s-platform-tempo-${AWS_ACCOUNT_ID}",
                "arn:aws:s3:::k8s-platform-tempo-${AWS_ACCOUNT_ID}/*"
            ]
        }
    ]
}
EOF

aws iam create-policy --policy-name TempoS3Policy --policy-document file://tempo-s3-policy.json

# Criar role
cat > tempo-trust-policy.json <<EOF
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
                    "oidc.eks.us-east-1.amazonaws.com/id/${OIDC_ID}:sub": "system:serviceaccount:observability:tempo"
                }
            }
        }
    ]
}
EOF

aws iam create-role --role-name TempoS3Role --assume-role-policy-document file://tempo-trust-policy.json
aws iam attach-role-policy --role-name TempoS3Role --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/TempoS3Policy
```

### 6.4 Instalar Tempo

```bash
sed -i "s/ACCOUNT_ID/${AWS_ACCOUNT_ID}/g" tempo-values.yaml

helm install tempo grafana/tempo-distributed \
  --namespace observability \
  --values tempo-values.yaml \
  --version 1.7.2 \
  --timeout 600s \
  --wait

kubectl get pods -n observability -l app.kubernetes.io/name=tempo
```

---

## 7. Task E.3: Pipelines OTEL (8h)

Os pipelines já foram configurados no OTEL Collector. Vamos validar:

### 7.1 Testar Pipeline de Traces

```bash
# Criar pod de teste que envia trace
kubectl run trace-test --rm -it --restart=Never \
  --image=curlimages/curl \
  -- curl -X POST http://otel-collector.observability:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{
    "resourceSpans": [{
      "resource": {"attributes": [{"key": "service.name", "value": {"stringValue": "test-service"}}]},
      "scopeSpans": [{
        "spans": [{
          "traceId": "5B8EFFF798038103D269B633813FC60C",
          "spanId": "EEE19B7EC3C1B174",
          "name": "test-span",
          "kind": 1,
          "startTimeUnixNano": 1544712660000000000,
          "endTimeUnixNano": 1544712661000000000
        }]
      }]
    }]
  }'
```

### 7.2 Testar Pipeline de Logs

```bash
# Verificar que logs estão sendo enviados para Loki
kubectl logs -n observability -l app.kubernetes.io/name=loki-gateway --tail=20

# Consultar via Loki API
kubectl port-forward svc/loki-gateway -n observability 3100:3100
curl -G "http://localhost:3100/loki/api/v1/labels"
```

### 7.3 Testar Pipeline de Métricas

```bash
# Verificar targets no Prometheus
kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n observability 9090:9090

# Acessar http://localhost:9090/targets
# Verificar que otel-collector está listado
```

---

## 8. Task F.1: Grafana e Datasources (6h)

Os datasources já foram configurados via Helm. Vamos verificar:

### 8.1 Obter Senha do Admin

```bash
kubectl get secret prometheus-grafana -n observability -o jsonpath='{.data.admin-password}' | base64 -d && echo
```

### 8.2 Acessar Grafana

```bash
# Se não tiver Ingress configurado ainda, use port-forward
kubectl port-forward svc/prometheus-grafana -n observability 3000:80

# Acesse http://localhost:3000
# Username: admin
# Password: (obtida acima)
```

### 8.3 Verificar Datasources

1. Acesse **Configuration > Data sources**
2. Verifique que existem:
   - Prometheus (default)
   - Loki
   - Tempo

3. Teste cada um clicando em **Test**

---

## 9. Task F.2: Dashboards Baseline (10h)

### 9.1 Importar Dashboards da Comunidade

**Via UI do Grafana:**

1. Acesse **Dashboards > Import**
2. Importe os seguintes dashboards (por ID):

| ID | Dashboard |
|----|-----------|
| 315 | Kubernetes cluster monitoring |
| 1860 | Node Exporter Full |
| 13770 | K8s / Compute Resources / Cluster |
| 14584 | K8s / CoreDNS |
| 13032 | K8s / Networking / Cluster |

### 9.2 Criar ConfigMap com Dashboards

```bash
cat > grafana-dashboards-cm.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards
  namespace: observability
  labels:
    grafana_dashboard: "1"
data:
  kubernetes-overview.json: |
    {
      "annotations": {
        "list": []
      },
      "title": "Kubernetes Overview",
      "uid": "k8s-overview",
      "version": 1,
      "panels": [
        {
          "title": "Cluster CPU Usage",
          "type": "timeseries",
          "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
          "targets": [
            {
              "expr": "sum(rate(container_cpu_usage_seconds_total{container!=\"\"}[5m]))",
              "legendFormat": "CPU Usage"
            }
          ]
        },
        {
          "title": "Cluster Memory Usage",
          "type": "timeseries",
          "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
          "targets": [
            {
              "expr": "sum(container_memory_working_set_bytes{container!=\"\"})",
              "legendFormat": "Memory Usage"
            }
          ]
        }
      ]
    }
EOF

kubectl apply -f grafana-dashboards-cm.yaml
```

---

## 10. Task F.3: Alertmanager (6h)

### 10.1 Criar PrometheusRule para Alertas Críticos

```bash
cat > critical-alerts.yaml <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: critical-alerts
  namespace: observability
  labels:
    release: prometheus
spec:
  groups:
    - name: critical
      rules:
        # Node down
        - alert: NodeDown
          expr: up{job="node-exporter"} == 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Node {{ $labels.instance }} is down"
            description: "Node has been down for more than 5 minutes."

        # Pod CrashLooping
        - alert: PodCrashLooping
          expr: rate(kube_pod_container_status_restarts_total[15m]) * 60 * 15 > 3
          for: 15m
          labels:
            severity: warning
          annotations:
            summary: "Pod {{ $labels.namespace }}/{{ $labels.pod }} is crash looping"
            description: "Pod has restarted more than 3 times in the last 15 minutes."

        # PVC Usage > 80%
        - alert: PVCUsageHigh
          expr: |
            (kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes) * 100 > 80
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "PVC {{ $labels.persistentvolumeclaim }} usage is above 80%"
            description: "PVC usage is {{ $value | humanize }}%"

        # RDS CPU > 80%
        - alert: RDSCPUHigh
          expr: aws_rds_cpuutilization_average > 80
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "RDS instance CPU is high"
            description: "RDS CPU usage is {{ $value }}%"

        # GitLab Sidekiq Queue High
        - alert: GitLabSidekiqQueueHigh
          expr: gitlab_sidekiq_queue_size > 1000
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "GitLab Sidekiq queue is high"
            description: "Sidekiq queue size is {{ $value }}"

EOF

kubectl apply -f critical-alerts.yaml
```

### 10.2 Verificar Alertas

```bash
# Verificar rules carregadas
kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n observability 9090:9090
# Acesse http://localhost:9090/rules

# Verificar alertas ativos
# Acesse http://localhost:9090/alerts
```

---

## 11. Validação e Definition of Done

### Checklist de Validação

```bash
echo "=== OTEL Collector ==="
kubectl get pods -n observability -l app.kubernetes.io/name=opentelemetry-collector

echo "=== Prometheus ==="
kubectl get pods -n observability -l app.kubernetes.io/name=prometheus

echo "=== Alertmanager ==="
kubectl get pods -n observability -l app.kubernetes.io/name=alertmanager

echo "=== Grafana ==="
kubectl get pods -n observability -l app.kubernetes.io/name=grafana

echo "=== Loki ==="
kubectl get pods -n observability -l app.kubernetes.io/name=loki

echo "=== Tempo ==="
kubectl get pods -n observability -l app.kubernetes.io/name=tempo

echo "=== PVCs ==="
kubectl get pvc -n observability

echo "=== Services ==="
kubectl get svc -n observability
```

### Definition of Done - Épicos D, E, F

- [ ] **OpenTelemetry Collector**
  - [ ] DaemonSet rodando em todos os nodes
  - [ ] Recebendo métricas, logs e traces
  - [ ] Pipelines configurados para Prometheus, Loki, Tempo

- [ ] **Prometheus**
  - [ ] 2 réplicas Running
  - [ ] PVC de 100Gi provisionado
  - [ ] Retenção de 15 dias configurada
  - [ ] ServiceMonitors para: node-exporter, GitLab, Redis, RabbitMQ
  - [ ] Targets todos UP

- [ ] **Alertmanager**
  - [ ] 2 réplicas Running
  - [ ] Alertas críticos configurados
  - [ ] Routes configurados

- [ ] **Loki**
  - [ ] Read/Write/Backend pods Running
  - [ ] S3 backend configurado
  - [ ] Logs sendo ingeridos
  - [ ] Query funcionando

- [ ] **Tempo**
  - [ ] Componentes distribuídos Running
  - [ ] S3 backend configurado
  - [ ] Traces sendo ingeridos
  - [ ] Query funcionando

- [ ] **Grafana**
  - [ ] 2 réplicas Running
  - [ ] Datasources: Prometheus, Loki, Tempo
  - [ ] Dashboards baseline instalados
  - [ ] Acesso via HTTPS (se Ingress configurado)

- [ ] **Validação End-to-End**
  - [ ] Métricas de pods visíveis no Grafana
  - [ ] Logs de pods consultáveis no Loki
  - [ ] Trace de teste visível no Tempo
  - [ ] Correlação traces → logs funcionando

---

**Documento:** 04-observability-stack.md
**Versão:** 1.0
**Última atualização:** 2026-01-19
**Épicos:** D, E, F
**Esforço:** 84 person-hours
