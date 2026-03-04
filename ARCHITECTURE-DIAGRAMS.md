# 🏗️ Arquitetura Visual - Plataforma Kubernetes

> **Última Atualização**: 2026-03-03
> **Status**: 5/6 domínios implementados
> **Conformidade SAD v1.2**: 89.6% média
> **Tipo**: Diagramas evolutivos (atualizar conforme implementação)
> **🎉 Novidade**: GitLab v18.9.1 (chart 9.9.1) + Linkerd Service Mesh DEPLOYED (2026-03-03)

---

## 📋 Índice de Diagramas

1. [Visão Geral da Plataforma](#1-visão-geral-da-plataforma)
2. [Ordem de Deploy e Dependências](#2-ordem-de-deploy-e-dependências)
3. [Platform-Core: Fundação](#3-platform-core-fundação)
4. [CI/CD Platform: Esteira DevOps](#4-cicd-platform-esteira-devops)
5. [Observability: Monitoramento](#5-observability-monitoramento)
6. [Data Services: Operators](#6-data-services-operators)
7. [Secrets Management: Cofre](#7-secrets-management-cofre)
8. [Security: Políticas](#8-security-políticas)
9. [Comunicação Entre Domínios](#9-comunicação-entre-domínios)
10. [Fluxo de Deploy Completo](#10-fluxo-de-deploy-completo)

---

## 1. Visão Geral da Plataforma

```mermaid
graph TB
    subgraph "CLOUD PROVIDER (Azure/AWS/GCP)"
        PROV[Platform Provisioning<br/>Clusters + VPC + Storage]
    end

    subgraph "KUBERNETES CLUSTER"
        subgraph "PLATFORM-CORE #1"
            KONG[Kong API Gateway<br/>Routing + Rate Limiting]
            KEYCLOAK[Keycloak<br/>Authentication OIDC]
            LINKERD[Linkerd Service Mesh<br/>mTLS + Observability]
            CERT[cert-manager<br/>TLS Certificates]
            NGINX[NGINX Ingress<br/>LoadBalancer]
        end

        subgraph "SECRETS-MANAGEMENT #2"
            VAULT[Vault HA Cluster<br/>Dynamic Secrets + PKI]
        end

        subgraph "OBSERVABILITY #3"
            OTEL[OpenTelemetry<br/>Traces + Metrics + Logs]
            PROM[Prometheus<br/>Time-Series DB]
            GRAFANA[Grafana<br/>Visualization]
            LOKI[Loki<br/>Log Aggregation]
            TEMPO[Tempo<br/>Distributed Tracing]
        end

        subgraph "CICD-PLATFORM #4"
            GITLAB[GitLab CE<br/>Git + CI/CD]
            SONAR[SonarQube<br/>Code Quality]
            HARBOR[Harbor<br/>Registry + Security]
            ARGOCD[ArgoCD<br/>GitOps]
            BACKSTAGE[Backstage<br/>Developer Portal]
        end

        subgraph "DATA-SERVICES #5"
            POSTGRES[Postgres Operator<br/>PostgreSQL HA]
            REDIS[Redis Operator<br/>Cache HA]
            RABBITMQ[RabbitMQ Operator<br/>Message Queue]
            VELERO[Velero<br/>Backup/Restore]
        end

        subgraph "SECURITY #6"
            KYVERNO[Kyverno<br/>Policy Engine]
            FALCO[Falco<br/>Runtime Security]
            TRIVY[Trivy Operator<br/>Vulnerability Scanning]
        end
    end

    subgraph "EXTERNAL USERS"
        DEVS[Developers]
        OPS[Platform Engineers]
        USERS[End Users]
    end

    %% Dependências Críticas
    PROV -->|Outputs: cluster_endpoint<br/>storage_class| KONG
    PROV -->|Outputs| KEYCLOAK

    KEYCLOAK -->|OIDC Provider| ARGOCD
    KEYCLOAK -->|OIDC Provider| GITLAB
    KONG -->|API Gateway| USERS

    CERT -->|TLS Certificates| NGINX
    NGINX -->|Ingress Routes| KONG
    NGINX -->|Ingress Routes| KEYCLOAK

    LINKERD -.->|mTLS Sidecar| GITLAB
    LINKERD -.->|mTLS Sidecar| HARBOR
    LINKERD -.->|mTLS Sidecar| ARGOCD

    VAULT -->|Secrets| GITLAB
    VAULT -->|Secrets| HARBOR
    VAULT -->|Secrets| ARGOCD

    OTEL -->|Metrics| PROM
    OTEL -->|Logs| LOKI
    OTEL -->|Traces| TEMPO
    PROM -->|Data Source| GRAFANA
    LOKI -->|Data Source| GRAFANA
    TEMPO -->|Data Source| GRAFANA

    GITLAB -->|Push Images| HARBOR
    GITLAB -->|Quality Gates| SONAR
    ARGOCD -->|Deploy Apps| POSTGRES
    ARGOCD -->|Deploy Apps| REDIS

    BACKSTAGE -->|Catalog| GITLAB
    BACKSTAGE -->|Software Templates| GITLAB

    DEVS -->|Code Push| GITLAB
    DEVS -->|Portal| BACKSTAGE
    OPS -->|Dashboards| GRAFANA
    OPS -->|GitOps| ARGOCD

    KYVERNO -.->|Policy Validation| GITLAB
    FALCO -.->|Runtime Alerts| GRAFANA
    TRIVY -.->|CVE Reports| HARBOR

    VELERO -->|Backup| POSTGRES
    VELERO -->|Backup| REDIS

    %% Estilos
    classDef implemented fill:#4CAF50,stroke:#2E7D32,color:#fff
    classDef pending fill:#FFC107,stroke:#F57C00,color:#000
    classDef external fill:#2196F3,stroke:#1565C0,color:#fff

    class KONG,KEYCLOAK,LINKERD,CERT,NGINX implemented
    class OTEL,PROM,GRAFANA,LOKI,TEMPO implemented
    class GITLAB,SONAR,HARBOR,ARGOCD,BACKSTAGE implemented
    class POSTGRES,REDIS,RABBITMQ,VELERO implemented
    class VAULT pending
    class KYVERNO,FALCO,TRIVY implemented
    class PROV,DEVS,OPS,USERS external
```

**Legenda**:
- 🟢 **Verde**: Implementado e aprovado (89.6% conformidade)
- 🟡 **Amarelo**: Pendente (ADR-002 para decisões arquiteturais)
- 🔵 **Azul**: Externo (cloud providers, usuários)
- **Linhas sólidas**: Dependências diretas
- **Linhas tracejadas**: Integrações opcionais/automáticas

---

## 2. Ordem de Deploy e Dependências

```mermaid
graph LR
    START([Platform Provisioning<br/>AKS/EKS/GKE]) --> PC[#1 Platform-Core<br/>Kong, Keycloak, Linkerd<br/>cert-manager, NGINX]

    PC --> SM[#2 Secrets-Management<br/>Vault HA + ESO<br/>✅ 16/16 SecretSynced]

    SM --> OBS[#3 Observability<br/>OTEL, Prometheus<br/>Grafana, Loki, Tempo]

    OBS --> CICD[#4 CI/CD Platform<br/>GitLab, SonarQube<br/>Harbor, ArgoCD, Backstage]

    OBS --> DATA[#5 Data Services<br/>Postgres, Redis<br/>RabbitMQ Operators]

    CICD --> SEC[#6 Security<br/>Kyverno ENFORCE, Falco, Trivy<br/>✅ 80/80 PASS]

    DATA --> SEC

    SEC --> READY([✅ Plataforma Completa<br/>6/6 Domínios Operacionais])

    %% Estilos
    classDef done fill:#4CAF50,stroke:#2E7D32,color:#fff
    classDef milestone fill:#9C27B0,stroke:#6A1B9A,color:#fff

    class PC,OBS,CICD,DATA,SM,SEC done
    class START,READY milestone
```

**Deploy Order Rationale**:
1. **Platform-Core**: Fundação (todos dependem de auth, gateway, mesh)
2. **Secrets-Management**: CI/CD precisa de injeção de secrets
3. **Observability**: Monitoramento de platform-core e CI/CD
4. **CI/CD Platform**: Automatiza deploys dos próximos domínios
5. **Data Services**: Operators para aplicações (pode ser paralelo com CI/CD)
6. **Security**: Políticas sobre toda a stack (último para validar tudo)

---

## 3. Platform-Core: Fundação

```mermaid
graph TB
    subgraph "PLATFORM-CORE NAMESPACE GROUP"
        subgraph "kong namespace"
            KONG_DEPLOY[Kong Deployment<br/>2 réplicas<br/>CPU: 1000m, Mem: 2Gi]
            KONG_DB[(PostgreSQL<br/>10Gi storage)]
            KONG_SVC[Kong Service<br/>8000, 8443, 8001]
        end

        subgraph "keycloak namespace"
            KC_DEPLOY[Keycloak Deployment<br/>2 réplicas<br/>CPU: 1000m, Mem: 2Gi]
            KC_DB[(PostgreSQL<br/>10Gi storage)]
            KC_SVC[Keycloak Service<br/>8080, 8443]
        end

        subgraph "linkerd namespace"
            LINKERD_CP[Linkerd Control Plane<br/>2 réplicas HA<br/>identity, proxy-injector]
            LINKERD_VIZ[Linkerd Viz<br/>Dashboard + Prometheus]
            LINKERD_PROXY[Linkerd Proxy<br/>Sidecar mTLS]
        end

        subgraph "cert-manager namespace"
            CERT_CONTROLLER[cert-manager Controller<br/>HTTP-01 challenge]
            CERT_WEBHOOK[cert-manager Webhook<br/>CRD validation]
            CERT_CA[cert-manager CA Injector<br/>Trust anchors]
        end

        subgraph "ingress-nginx namespace"
            NGINX_DEPLOY[NGINX Ingress Controller<br/>2 réplicas<br/>CPU: 200m, Mem: 256Mi]
            NGINX_SVC[LoadBalancer Service<br/>80, 443]
        end
    end

    subgraph "EXTERNAL ACCESS"
        INTERNET([Internet])
        DNS[DNS Records<br/>*.example.com]
    end

    subgraph "CONTRATOS PROVIDOS"
        CONTRACT_AUTH[Authentication<br/>SLA: 99.95%<br/>OIDC endpoints]
        CONTRACT_GATEWAY[API Gateway<br/>SLA: 99.9%<br/>Rate limiting, Routing]
        CONTRACT_MESH[Service Mesh<br/>SLA: 99.9%<br/>mTLS, Observability]
        CONTRACT_CERTS[Certificates<br/>SLA: 99.9%<br/>Auto-renewal]
        CONTRACT_INGRESS[Ingress<br/>SLA: 99.9%<br/>LoadBalancer]
    end

    %% Fluxo de Tráfego
    INTERNET --> DNS
    DNS --> NGINX_SVC
    NGINX_SVC --> NGINX_DEPLOY
    NGINX_DEPLOY --> KONG_SVC
    NGINX_DEPLOY --> KC_SVC

    KONG_DEPLOY --> KONG_DB
    KC_DEPLOY --> KC_DB

    %% Linkerd Injection
    LINKERD_CP -.->|Inject Sidecar| KONG_DEPLOY
    LINKERD_CP -.->|Inject Sidecar| KC_DEPLOY
    LINKERD_PROXY -.->|mTLS| LINKERD_PROXY

    %% cert-manager TLS
    CERT_CONTROLLER -->|Issue Certificates| NGINX_DEPLOY
    CERT_CONTROLLER -->|Issue Certificates| KONG_DEPLOY
    CERT_CONTROLLER -->|Issue Certificates| KC_DEPLOY

    %% Contratos
    KC_DEPLOY --> CONTRACT_AUTH
    KONG_DEPLOY --> CONTRACT_GATEWAY
    LINKERD_CP --> CONTRACT_MESH
    CERT_CONTROLLER --> CONTRACT_CERTS
    NGINX_DEPLOY --> CONTRACT_INGRESS

    %% Estilos
    classDef component fill:#4CAF50,stroke:#2E7D32,color:#fff
    classDef storage fill:#FF9800,stroke:#E65100,color:#fff
    classDef contract fill:#2196F3,stroke:#1565C0,color:#fff
    classDef external fill:#9E9E9E,stroke:#424242,color:#fff

    class KONG_DEPLOY,KC_DEPLOY,LINKERD_CP,CERT_CONTROLLER,NGINX_DEPLOY component
    class KONG_DB,KC_DB storage
    class CONTRACT_AUTH,CONTRACT_GATEWAY,CONTRACT_MESH,CONTRACT_CERTS,CONTRACT_INGRESS contract
    class INTERNET,DNS external
```

**Responsabilidades Platform-Core**:
- **Kong**: API Gateway (routing, rate limiting, autenticação)
- **Keycloak**: Identity Provider (OIDC, SAML, usuários/roles)
- **Linkerd**: Service Mesh (mTLS east-west, observability automática)
- **cert-manager**: Gerenciamento de certificados TLS (Let's Encrypt)
- **NGINX**: Ingress Controller (entrada norte-sul, LoadBalancer)

**Recursos**:
- CPU Total: ~4.2 cores (2x Kong + 2x Keycloak + Linkerd + NGINX)
- Memory Total: ~8Gi
- Storage: 20Gi (2x PostgreSQL 10Gi)

---

## 4. CI/CD Platform: Esteira DevOps

```mermaid
graph TB
    subgraph "CICD-PLATFORM NAMESPACE GROUP"
        subgraph "gitlab namespace"
            GITLAB_WEB[GitLab Webservice<br/>2 réplicas<br/>CPU: 1500m, Mem: 4Gi]
            GITLAB_SIDEKIQ[GitLab Sidekiq<br/>Background Jobs]
            GITLAB_RUNNER[GitLab Runner<br/>Kubernetes Executor<br/>10 concurrent pods]
            GITLAB_DB[(PostgreSQL<br/>10Gi)]
            GITLAB_REDIS[(Redis<br/>1Gi)]
            GITLAB_MINIO[(Minio S3<br/>50Gi artifacts)]
        end

        subgraph "sonarqube namespace"
            SONAR_APP[SonarQube<br/>1 réplica<br/>CPU: 2000m, Mem: 4Gi]
            SONAR_DB[(PostgreSQL<br/>20Gi)]
        end

        subgraph "harbor namespace"
            HARBOR_CORE[Harbor Core<br/>Registry API]
            HARBOR_REGISTRY[Harbor Registry<br/>100Gi images]
            HARBOR_CHART[Chartmuseum<br/>10Gi helm charts]
            HARBOR_TRIVY[Trivy Scanner<br/>CVE detection]
            HARBOR_DB[(PostgreSQL<br/>10Gi)]
        end

        subgraph "argocd namespace"
            ARGOCD_SERVER[ArgoCD Server v2.10.0<br/>2 réplicas<br/>Web UI + API + PKCE]
            ARGOCD_CONTROLLER[ArgoCD Controller v2.10.0<br/>2 réplicas<br/>App reconciliation]
            ARGOCD_REPO[ArgoCD Repo Server v2.10.0<br/>2 réplicas<br/>Git operations]
            ARGOCD_DEX[ArgoCD Dex<br/>Keycloak OIDC + PKCE]
        end

        subgraph "backstage namespace"
            BACKSTAGE_APP[Backstage<br/>2 réplicas<br/>Developer Portal]
            BACKSTAGE_DB[(PostgreSQL<br/>10Gi)]
        end
    end

    subgraph "DEVELOPER WORKFLOW"
        DEV[Developer]
        CODE[1. Code Push]
        CI[2. CI Pipeline]
        SCAN[3. Security Scan]
        BUILD[4. Build + Push]
        DEPLOY[5. GitOps Deploy]
        PORTAL[6. Catalog Update]
    end

    subgraph "CONTRATOS PROVIDOS"
        CONTRACT_GIT[Git Repository<br/>SLA: 99.5%<br/>50Gi storage]
        CONTRACT_CI[Continuous Integration<br/>10 concurrent runners<br/>P95 < 10min]
        CONTRACT_REGISTRY[Container Registry<br/>SLA: 99.5%<br/>100Gi + Trivy CVE]
        CONTRACT_GITOPS[GitOps<br/>SLA: 99.9%<br/>Auto-sync < 5min]
        CONTRACT_CATALOG[Developer Catalog<br/>Software Templates<br/>Sync < 15min]
    end

    %% Workflow
    DEV -->|git push| CODE
    CODE --> GITLAB_WEB
    GITLAB_WEB --> CI
    CI --> GITLAB_RUNNER
    GITLAB_RUNNER -->|.gitlab-ci.yml| SCAN
    SCAN --> SONAR_APP
    SONAR_APP -->|Quality Gate OK| BUILD
    BUILD --> GITLAB_RUNNER
    GITLAB_RUNNER -->|docker push| HARBOR_REGISTRY
    HARBOR_REGISTRY --> HARBOR_TRIVY
    HARBOR_TRIVY -->|CVE Scan OK| DEPLOY
    DEPLOY --> ARGOCD_CONTROLLER
    ARGOCD_CONTROLLER -->|kubectl apply| PORTAL
    PORTAL --> BACKSTAGE_APP
    BACKSTAGE_APP -->|API| GITLAB_WEB

    %% Dependencies
    GITLAB_WEB --> GITLAB_DB
    GITLAB_WEB --> GITLAB_REDIS
    GITLAB_WEB --> GITLAB_MINIO
    SONAR_APP --> SONAR_DB
    HARBOR_CORE --> HARBOR_DB
    HARBOR_CORE --> HARBOR_REGISTRY
    HARBOR_CORE --> HARBOR_CHART
    ARGOCD_SERVER --> ARGOCD_DEX
    ARGOCD_DEX -.->|OIDC| KC_EXT[Keycloak<br/>platform-core]
    BACKSTAGE_APP --> BACKSTAGE_DB

    %% Contratos
    GITLAB_WEB --> CONTRACT_GIT
    GITLAB_RUNNER --> CONTRACT_CI
    HARBOR_REGISTRY --> CONTRACT_REGISTRY
    ARGOCD_CONTROLLER --> CONTRACT_GITOPS
    BACKSTAGE_APP --> CONTRACT_CATALOG

    %% Estilos
    classDef component fill:#4CAF50,stroke:#2E7D32,color:#fff
    classDef storage fill:#FF9800,stroke:#E65100,color:#fff
    classDef workflow fill:#9C27B0,stroke:#6A1B9A,color:#fff
    classDef contract fill:#2196F3,stroke:#1565C0,color:#fff

    class GITLAB_WEB,SONAR_APP,HARBOR_CORE,ARGOCD_SERVER,BACKSTAGE_APP component
    class GITLAB_DB,GITLAB_REDIS,GITLAB_MINIO,SONAR_DB,HARBOR_DB,HARBOR_REGISTRY,BACKSTAGE_DB storage
    class DEV,CODE,CI,SCAN,BUILD,DEPLOY,PORTAL workflow
    class CONTRACT_GIT,CONTRACT_CI,CONTRACT_REGISTRY,CONTRACT_GITOPS,CONTRACT_CATALOG contract
```

**Responsabilidades CI/CD Platform**:
- **GitLab**: Git repos, CI pipelines, Docker registry integration
- **SonarQube**: Análise estática de código, quality gates
- **Harbor**: Container registry, Helm charts, Trivy CVE scanning
- **ArgoCD**: GitOps deployment, Keycloak OIDC authentication
- **Backstage**: Developer portal, software templates, catalog

**Recursos**:
- CPU Total: ~7.5 cores
- Memory Total: ~16Gi
- Storage: 211Gi (50Gi Minio + 100Gi registry + 20Gi SonarQube + 3x10Gi DBs + 10Gi charts)

---

## 5. Observability: Monitoramento

```mermaid
graph TB
    subgraph "OBSERVABILITY NAMESPACE"
        subgraph "Collection Layer"
            OTEL_COL[OpenTelemetry Collector<br/>Traces + Metrics + Logs<br/>2 réplicas]
            OTEL_AGENT[OTEL Agent<br/>DaemonSet<br/>1 pod per node]
        end

        subgraph "Storage Layer"
            PROM[Prometheus<br/>Time-Series DB<br/>100Gi storage<br/>Retention: 15 dias]
            LOKI[Loki<br/>Log Aggregation<br/>50Gi storage<br/>Retention: 7 dias]
            TEMPO[Tempo<br/>Distributed Tracing<br/>20Gi storage<br/>Retention: 7 dias]
        end

        subgraph "Visualization Layer"
            GRAFANA[Grafana<br/>Dashboards<br/>10Gi storage]
            KIALI[Kiali<br/>Service Mesh Viz<br/>Linkerd integration]
        end

        subgraph "Alerting Layer"
            ALERTMGR[Alertmanager<br/>Alert routing<br/>Slack, Email, PagerDuty]
        end
    end

    subgraph "DATA SOURCES (All Domains)"
        PCORE[Platform-Core<br/>ServiceMonitors]
        CICD[CI/CD Platform<br/>ServiceMonitors]
        DATA[Data Services<br/>ServiceMonitors]
        APPS[Applications<br/>Custom Metrics]
    end

    subgraph "CONTRATOS PROVIDOS"
        CONTRACT_METRICS[Metrics Storage<br/>SLA: 99.9%<br/>Prometheus Query]
        CONTRACT_LOGS[Log Aggregation<br/>LogQL queries<br/>7 dias retention]
        CONTRACT_TRACES[Trace Storage<br/>Jaeger compatible<br/>7 dias retention]
        CONTRACT_VIZ[Visualization<br/>Grafana dashboards<br/>Custom queries]
        CONTRACT_ALERTS[Alerting<br/>Multi-channel<br/>< 1min latency]
    end

    %% Data Flow
    PCORE -->|Scrape /metrics| OTEL_AGENT
    CICD -->|Scrape /metrics| OTEL_AGENT
    DATA -->|Scrape /metrics| OTEL_AGENT
    APPS -->|Scrape /metrics| OTEL_AGENT

    OTEL_AGENT -->|Forward| OTEL_COL
    OTEL_COL -->|Metrics| PROM
    OTEL_COL -->|Logs| LOKI
    OTEL_COL -->|Traces| TEMPO

    PROM -->|Data Source| GRAFANA
    LOKI -->|Data Source| GRAFANA
    TEMPO -->|Data Source| GRAFANA

    PROM -->|Evaluate Rules| ALERTMGR
    ALERTMGR -->|Notify| SLACK[Slack]
    ALERTMGR -->|Notify| EMAIL[Email]
    ALERTMGR -->|Notify| PD[PagerDuty]

    KIALI -.->|Query| PROM
    KIALI -.->|Linkerd API| LINKERD_EXT[Linkerd Control Plane]

    %% Contratos
    PROM --> CONTRACT_METRICS
    LOKI --> CONTRACT_LOGS
    TEMPO --> CONTRACT_TRACES
    GRAFANA --> CONTRACT_VIZ
    ALERTMGR --> CONTRACT_ALERTS

    %% Estilos
    classDef component fill:#4CAF50,stroke:#2E7D32,color:#fff
    classDef storage fill:#FF9800,stroke:#E65100,color:#fff
    classDef source fill:#9C27B0,stroke:#6A1B9A,color:#fff
    classDef contract fill:#2196F3,stroke:#1565C0,color:#fff
    classDef external fill:#9E9E9E,stroke:#424242,color:#fff

    class OTEL_COL,OTEL_AGENT,GRAFANA,KIALI,ALERTMGR component
    class PROM,LOKI,TEMPO storage
    class PCORE,CICD,DATA,APPS source
    class CONTRACT_METRICS,CONTRACT_LOGS,CONTRACT_TRACES,CONTRACT_VIZ,CONTRACT_ALERTS contract
    class SLACK,EMAIL,PD external
```

**Responsabilidades Observability**:
- **OpenTelemetry**: Coleta unificada de telemetria (traces, metrics, logs)
- **Prometheus**: Storage de métricas time-series, alerting rules
- **Grafana**: Visualização de dashboards, multi-datasource
- **Loki**: Agregação de logs, queries LogQL
- **Tempo**: Distributed tracing, Jaeger compatible
- **Kiali**: Visualização de service mesh (Linkerd integration)
- **Alertmanager**: Roteamento de alertas multi-canal

**Recursos**:
- CPU Total: ~3 cores
- Memory Total: ~8Gi
- Storage: 180Gi (100Gi Prometheus + 50Gi Loki + 20Gi Tempo + 10Gi Grafana)

---

## 6. Data Services: Operators

```mermaid
graph TB
    subgraph "DATA-SERVICES OPERATORS"
        subgraph "postgres-operator namespace"
            PG_OP[Zalando Postgres Operator<br/>Controller<br/>Patroni + Spilo]
        end

        subgraph "redis-operator namespace"
            REDIS_OP[Redis Cluster Operator<br/>Controller<br/>Master-Replica HA]
        end

        subgraph "rabbitmq-system namespace"
            RABBIT_OP[RabbitMQ Cluster Operator<br/>Controller<br/>Quorum Queues]
        end

        subgraph "velero namespace"
            VELERO[Velero<br/>Backup Controller<br/>S3-compatible storage]
        end
    end

    subgraph "INSTANCES CRIADAS (via CRDs)"
        subgraph "application namespace"
            PG_CLUSTER[PostgreSQL Cluster<br/>1 master + 2 replicas<br/>10Gi storage per pod]
            REDIS_CLUSTER[Redis Cluster<br/>3 masters<br/>5Gi storage per pod]
            RABBIT_CLUSTER[RabbitMQ Cluster<br/>3 nodes<br/>10Gi storage per node]
        end
    end

    subgraph "BACKUP STORAGE"
        S3[S3-compatible Storage<br/>Minio / AWS S3<br/>Azure Blob / GCP GCS]
    end

    subgraph "CONTRATOS PROVIDOS"
        CONTRACT_PG[PostgreSQL as a Service<br/>SLA: 99.9%<br/>HA via Patroni<br/>Auto-failover &lt; 30s]
        CONTRACT_REDIS[Redis as a Service<br/>SLA: 99.9%<br/>Cluster mode<br/>Persistence AOF/RDB]
        CONTRACT_RABBIT[RabbitMQ as a Service<br/>SLA: 99.9%<br/>Quorum queues<br/>Management UI]
        CONTRACT_BACKUP[Backup/Restore<br/>RPO: 24h daily<br/>RTO: &lt; 1h<br/>PVC + CRD backup]
    end

    %% Operator manages Instances
    PG_OP -->|Watch CRD: acid.zalan.do/v1/postgresql| PG_CLUSTER
    REDIS_OP -->|Watch CRD: redis.opstreelabs.in/v1beta1| REDIS_CLUSTER
    RABBIT_OP -->|Watch CRD: rabbitmq.com/v1beta1| RABBIT_CLUSTER

    %% Backup
    VELERO -.->|Schedule backup: Daily 2AM| PG_CLUSTER
    VELERO -.->|Schedule backup: Daily 2AM| REDIS_CLUSTER
    VELERO -.->|Schedule backup: Daily 2AM| RABBIT_CLUSTER
    VELERO -->|Store snapshots| S3

    %% Contratos
    PG_CLUSTER --> CONTRACT_PG
    REDIS_CLUSTER --> CONTRACT_REDIS
    RABBIT_CLUSTER --> CONTRACT_RABBIT
    VELERO --> CONTRACT_BACKUP

    %% Usage Example
    APP[Application Pod<br/>myapp-deployment] -->|my-postgres.app.svc:5432| PG_CLUSTER
    APP -->|my-redis.app.svc:6379| REDIS_CLUSTER
    APP -->|my-rabbitmq.app.svc:5672| RABBIT_CLUSTER

    %% Estilos
    classDef operator fill:#4CAF50,stroke:#2E7D32,color:#fff
    classDef instance fill:#FF9800,stroke:#E65100,color:#fff
    classDef contract fill:#2196F3,stroke:#1565C0,color:#fff
    classDef storage fill:#9E9E9E,stroke:#424242,color:#fff
    classDef app fill:#9C27B0,stroke:#6A1B9A,color:#fff

    class PG_OP,REDIS_OP,RABBIT_OP,VELERO operator
    class PG_CLUSTER,REDIS_CLUSTER,RABBIT_CLUSTER instance
    class CONTRACT_PG,CONTRACT_REDIS,CONTRACT_RABBIT,CONTRACT_BACKUP contract
    class S3 storage
    class APP app
```

**Responsabilidades Data Services**:
- **Zalando Postgres Operator**: PostgreSQL HA clusters com Patroni (auto-failover)
- **Redis Cluster Operator**: Redis HA com cluster mode e replicação
- **RabbitMQ Cluster Operator**: RabbitMQ HA com quorum queues
- **Velero**: Backup/restore de PVCs, CRDs, namespaces (disaster recovery)

**Recursos (por instance típica)**:
- PostgreSQL Cluster: 3 pods x 2Gi memory x 10Gi storage = 30Gi total
- Redis Cluster: 3 pods x 1Gi memory x 5Gi storage = 15Gi total
- RabbitMQ Cluster: 3 pods x 2Gi memory x 10Gi storage = 30Gi total

---

## 7. Secrets Management: Cofre

```mermaid
graph TB
    subgraph "SECRETS-MANAGEMENT ✅ OPERACIONAL (ADR-031 + ADR-032)"
        subgraph "vault namespace"
            VAULT_SERVER[Vault Server HA<br/>3 réplicas<br/>KMS Auto-unseal]
            VAULT_RAFT[(Raft Backend<br/>Integrated storage)]
            VAULT_INJECTOR[Vault Agent Injector<br/>Sidecar injection]
        end

        subgraph "external-secrets namespace"
            ESO_CONTROLLER[External Secrets Operator<br/>Controller<br/>16/16 SecretSynced]
            ESO_STORE[SecretStore<br/>vault-backend]
        end
    end

    subgraph "SECRET STORES"
        AWS_SM[AWS Secrets Manager<br/>staging/platform/*]
    end

    subgraph "CONTRATOS PROVIDOS"
        CONTRACT_STATIC[Static Secrets<br/>K8s Secret sync<br/>Auto-rotation]
        CONTRACT_DYNAMIC[Dynamic Secrets<br/>Database credentials<br/>TTL-based]
        CONTRACT_PKI[PKI/TLS<br/>Certificate generation<br/>Auto-renewal]
        CONTRACT_ENCRYPTION[Encryption as a Service<br/>Transit engine<br/>KMS key rotation]
    end

    subgraph "CONSUMERS (16 ExternalSecrets)"
        GITLAB_C[GitLab<br/>DB + SMTP + OIDC]
        HARBOR_C[Harbor<br/>DB + Admin + OIDC]
        ARGOCD_C[ArgoCD<br/>OIDC + Git keys]
        APP_C[Keycloak + Vault<br/>DB credentials]
    end

    %% Vault flows
    VAULT_SERVER --> VAULT_RAFT
    VAULT_SERVER --> CONTRACT_DYNAMIC
    VAULT_SERVER --> CONTRACT_PKI
    VAULT_SERVER --> CONTRACT_ENCRYPTION

    %% ESO flows
    ESO_CONTROLLER -->|Read secrets| AWS_SM
    ESO_CONTROLLER -->|ClusterSecretStore| ESO_STORE
    ESO_STORE -->|Create K8s Secret| GITLAB_C
    ESO_STORE -->|Create K8s Secret| HARBOR_C
    ESO_STORE -->|Create K8s Secret| ARGOCD_C
    ESO_STORE -->|Create K8s Secret| APP_C

    VAULT_INJECTOR -.->|Sidecar inject| GITLAB_C
    VAULT_SERVER --> CONTRACT_STATIC
    ESO_CONTROLLER -.-> CONTRACT_STATIC

    %% Estilos
    classDef vault fill:#4CAF50,stroke:#2E7D32,color:#fff
    classDef eso fill:#4CAF50,stroke:#2E7D32,color:#fff
    classDef cloud fill:#9E9E9E,stroke:#424242,color:#fff
    classDef contract fill:#2196F3,stroke:#1565C0,color:#fff
    classDef consumer fill:#9C27B0,stroke:#6A1B9A,color:#fff

    class VAULT_SERVER,VAULT_RAFT,VAULT_INJECTOR vault
    class ESO_CONTROLLER,ESO_STORE eso
    class AWS_SM cloud
    class CONTRACT_STATIC,CONTRACT_DYNAMIC,CONTRACT_PKI,CONTRACT_ENCRYPTION contract
    class GITLAB_C,HARBOR_C,ARGOCD_C,APP_C consumer
```

**✅ Decisão Implementada (ADR-031 + ADR-032)**:
- **Vault HA**: Secret engine primário — dynamic secrets (DB credentials), PKI, encryption as a service, KMS auto-unseal
- **ESO**: Synchronizer — lê de AWS Secrets Manager e cria K8s Secrets (16/16 SecretSynced)
- **Padrão híbrido**: Vault como storage authoritative + ESO como sync layer para cloud secrets

**Responsabilidades Secrets Management**:
- **Vault**: Storage seguro de secrets, dynamic secrets (DB credentials), PKI, encryption
- **ESO**: Sync de AWS Secrets Manager para Kubernetes Secrets (todos os componentes platform)

---

## 8. Security: Políticas

```mermaid
graph TB
    subgraph "SECURITY DOMAIN ✅ OPERACIONAL (ADR-043)"
        subgraph "kyverno namespace"
            KYVERNO[Kyverno Controller HA<br/>ENFORCE mode<br/>80/80 PASS]
        end

        subgraph "Runtime Security"
            FALCO[Falco<br/>DaemonSet<br/>Syscall monitoring<br/>Runtime alerts]
        end

        subgraph "Vulnerability Scanning"
            TRIVY_OP[Trivy Operator<br/>Controller<br/>Image scanning<br/>CVE reports]
        end

        subgraph "Network Security"
            NETPOL[Network Policies<br/>L3/L4 firewall<br/>Namespace isolation]
        end
    end

    subgraph "POLICY TYPES (3 Políticas ENFORCE)"
        POL_ADMISSION[Admission Policies<br/>- Require labels ADR-048<br/>- Disallow privileged<br/>- Enforce resource limits]
        POL_MUTATION[Mutation Policies<br/>- Add default labels<br/>- Inject Linkerd sidecar<br/>- Add NetworkPolicy]
        POL_GENERATION[Generation Policies<br/>- Auto-create RBAC<br/>- Auto-create NetworkPolicy]
    end

    subgraph "CONTRATOS PROVIDOS"
        CONTRACT_POLICY[Policy Enforcement<br/>Admission webhook<br/>ENFORCE mode ativo]
        CONTRACT_RUNTIME[Runtime Security<br/>Real-time alerts<br/>Threat detection]
        CONTRACT_VULN[Vulnerability Scanning<br/>CVE detection<br/>Harbor Trivy integration]
        CONTRACT_NETWORK[Network Segmentation<br/>mTLS via Linkerd<br/>Namespace isolation]
    end

    subgraph "MONITORED RESOURCES"
        PODS[Pods<br/>80/80 PASS]
        IMAGES[Images<br/>CVE scanning]
        SYSCALLS[System Calls<br/>Runtime behavior]
        TRAFFIC[Network Traffic<br/>L3/L4 policies]
    end

    KYVERNO -->|Validate| POL_ADMISSION
    KYVERNO -->|Mutate| POL_MUTATION
    KYVERNO -->|Generate| POL_GENERATION
    KYVERNO -->|Webhook| PODS

    FALCO -->|Monitor syscalls| SYSCALLS
    FALCO -->|Alert to| GRAFANA_EXT[Grafana<br/>observability]

    TRIVY_OP -->|Scan| IMAGES
    TRIVY_OP -->|Report to| HARBOR_EXT[Harbor<br/>cicd-platform]

    NETPOL -->|Apply rules| TRAFFIC
    NETPOL -.->|Complement| LINKERD_EXT[Linkerd mTLS<br/>platform-core]

    KYVERNO --> CONTRACT_POLICY
    FALCO --> CONTRACT_RUNTIME
    TRIVY_OP --> CONTRACT_VULN
    NETPOL --> CONTRACT_NETWORK

    %% Estilos
    classDef kyverno fill:#4CAF50,stroke:#2E7D32,color:#fff
    classDef runtime fill:#FF5722,stroke:#D84315,color:#fff
    classDef contract fill:#2196F3,stroke:#1565C0,color:#fff
    classDef resource fill:#9C27B0,stroke:#6A1B9A,color:#fff

    class KYVERNO kyverno
    class FALCO,TRIVY_OP,NETPOL runtime
    class CONTRACT_POLICY,CONTRACT_RUNTIME,CONTRACT_VULN,CONTRACT_NETWORK contract
    class PODS,IMAGES,SYSCALLS,TRAFFIC resource
```

**✅ Decisão Implementada (ADR-043)**:

- **Kyverno ENFORCE**: YAML policies, validation + mutation + generation — 80/80 PASS em todos os pods

**Responsabilidades Security**:

- **Kyverno**: Policy enforcement (admission webhooks) em modo ENFORCE — 3 políticas ativas (ADR-048 labels, privileged, resources)
- **Falco**: Runtime security monitoring, threat detection, syscall analysis
- **Trivy Operator**: Vulnerability scanning de imagens, CVE reports integrado ao Harbor
- **Network Policies**: L3/L4 firewall + Linkerd mTLS (zero-trust)

---

## 9. Comunicação Entre Domínios

```mermaid
sequenceDiagram
    actor Dev as Developer
    participant GL as GitLab
    participant SQ as SonarQube
    participant HB as Harbor
    participant AR as ArgoCD
    participant KC as Keycloak
    participant VAULT as Vault
    participant PG as PostgreSQL
    participant PROM as Prometheus
    participant GRAF as Grafana

    Note over Dev,GRAF: Fluxo Completo: Code → Production

    %% 1. Developer Push
    Dev->>GL: 1. git push main
    GL->>KC: 2. Authenticate (OIDC)
    KC-->>GL: Token OK

    %% 2. CI Pipeline
    GL->>GL: 3. Trigger .gitlab-ci.yml
    GL->>SQ: 4. Static Analysis
    SQ-->>GL: Quality Gate PASS

    %% 3. Build + Push
    GL->>VAULT: 5. Get Harbor credentials
    VAULT-->>GL: username + password
    GL->>GL: 6. docker build
    GL->>HB: 7. docker push
    HB->>HB: 8. Trivy CVE scan
    HB-->>GL: Image SAFE

    %% 4. GitOps Deploy
    GL->>GL: 9. Update manifests repo
    AR->>GL: 10. Poll repo (3min)
    AR->>KC: 11. Authenticate (OIDC)
    KC-->>AR: Token OK
    AR->>HB: 12. Pull image
    HB-->>AR: Image OK

    %% 5. Database Setup
    AR->>PG: 13. Create PostgreSQL CRD
    PG->>PG: 14. Provision HA cluster
    AR->>VAULT: 15. Get DB credentials
    VAULT-->>AR: Generated creds (TTL: 24h)
    AR->>AR: 16. Create Secret

    %% 6. Deploy Application
    AR->>AR: 17. kubectl apply
    AR->>PROM: 18. Expose metrics /metrics
    PROM->>PROM: 19. Scrape metrics (15s)

    %% 7. Monitoring
    Dev->>GRAF: 20. Check dashboard
    GRAF->>PROM: Query metrics
    PROM-->>GRAF: Time-series data
    GRAF-->>Dev: Dashboard OK

    Note over Dev,GRAF: Total Time: ~10-15 minutes
```

**Principais Integrações**:
1. **GitLab ↔ Keycloak**: OIDC authentication
2. **GitLab ↔ Vault**: Credentials injection (CI/CD secrets)
3. **GitLab ↔ Harbor**: Docker push/pull
4. **GitLab ↔ SonarQube**: Quality gates
5. **ArgoCD ↔ Keycloak**: OIDC authentication
6. **ArgoCD ↔ Harbor**: Image pull
7. **ArgoCD ↔ Vault**: Dynamic secrets (DB credentials)
8. **ArgoCD ↔ PostgreSQL Operator**: Database provisioning
9. **Todos ↔ Prometheus**: Metrics scraping (ServiceMonitors)
10. **Linkerd**: mTLS automático entre todos os pods

---

## 10. Fluxo de Deploy Completo

```mermaid
graph TB
    START([Developer: git push]) --> GITLAB_CI[GitLab CI Pipeline]

    GITLAB_CI --> LINT[Lint + Unit Tests]
    LINT --> SONAR[SonarQube Analysis]
    SONAR --> QG{Quality Gate?}
    QG -->|FAIL| NOTIFY_FAIL[Notify Slack: Failed]
    QG -->|PASS| BUILD[Docker Build]

    BUILD --> PUSH[Push to Harbor]
    PUSH --> TRIVY[Trivy CVE Scan]
    TRIVY --> CVE{CVE Critical?}
    CVE -->|YES| NOTIFY_CVE[Notify Security Team]
    CVE -->|NO| UPDATE_MANIFEST[Update GitOps Manifest]

    UPDATE_MANIFEST --> ARGOCD_POLL[ArgoCD Poll Repo]
    ARGOCD_POLL --> ARGOCD_SYNC[ArgoCD Sync]
    ARGOCD_SYNC --> CREATE_NS[Create Namespace]
    CREATE_NS --> CREATE_NETPOL[Generate Network Policy<br/>via Kyverno]

    CREATE_NETPOL --> NEED_DB{Need Database?}
    NEED_DB -->|YES| CREATE_PG[Create PostgreSQL CRD]
    CREATE_PG --> PG_HA[Postgres Operator<br/>Provision HA Cluster]
    PG_HA --> VAULT_DB[Vault: Generate DB Creds]
    VAULT_DB --> SECRET_DB[Create K8s Secret]

    NEED_DB -->|NO| DEPLOY_APP
    SECRET_DB --> DEPLOY_APP[Deploy Application]

    DEPLOY_APP --> INJECT_LINKERD[Linkerd: Inject Proxy]
    INJECT_LINKERD --> INJECT_VAULT[Vault: Inject Secrets<br/>via Sidecar]
    INJECT_VAULT --> POD_START[Pod Starting]

    POD_START --> KYVERNO_CHECK{Kyverno Validation}
    KYVERNO_CHECK -->|FAIL| REJECT[Reject Pod]
    KYVERNO_CHECK -->|PASS| POD_RUN[Pod Running]

    POD_RUN --> EXPOSE_METRICS[Expose /metrics]
    EXPOSE_METRICS --> PROM_SCRAPE[Prometheus Scrape]
    PROM_SCRAPE --> FALCO_MONITOR[Falco: Monitor Syscalls]

    FALCO_MONITOR --> HEALTHY{Health Check OK?}
    HEALTHY -->|FAIL| ROLLBACK[ArgoCD Rollback]
    HEALTHY -->|OK| UPDATE_BACKSTAGE[Backstage: Update Catalog]

    UPDATE_BACKSTAGE --> DONE([✅ Deployment Complete])

    %% Parallel Monitoring
    PROM_SCRAPE -.-> GRAFANA[Grafana Dashboards]
    FALCO_MONITOR -.-> GRAFANA
    POD_RUN -.-> LOKI[Loki: Aggregate Logs]
    POD_RUN -.-> TEMPO[Tempo: Trace Requests]

    %% Estilos
    classDef success fill:#4CAF50,stroke:#2E7D32,color:#fff
    classDef fail fill:#F44336,stroke:#C62828,color:#fff
    classDef process fill:#2196F3,stroke:#1565C0,color:#fff
    classDef decision fill:#FF9800,stroke:#E65100,color:#fff
    classDef milestone fill:#9C27B0,stroke:#6A1B9A,color:#fff

    class DEPLOY_APP,POD_RUN,DONE success
    class NOTIFY_FAIL,NOTIFY_CVE,REJECT,ROLLBACK fail
    class GITLAB_CI,BUILD,PUSH,ARGOCD_SYNC,CREATE_PG,VAULT_DB process
    class QG,CVE,NEED_DB,KYVERNO_CHECK,HEALTHY decision
    class START,UPDATE_BACKSTAGE milestone
```

**Tempo Estimado por Etapa**:
1. CI Pipeline: 5-8 minutos
2. ArgoCD Sync: 2-3 minutos
3. Database Provisioning: 3-5 minutos (se necessário)
4. Pod Startup: 1-2 minutos
5. **Total**: 10-18 minutos (sem DB) ou 13-23 minutos (com DB)

---

## 📊 Resumo de Recursos por Domínio

| Domínio                | CPU (cores) | Memory (Gi) | Storage (Gi)   | Status              | SLA           |
| ---------------------- | ----------- | ----------- | -------------- | ------------------- | ------------- |
| **Platform-Core**      | 4.2         | 8           | 20             | Implementado ✅      | 99.9%         |
| **Secrets-Management** | 2.0         | 4           | 15             | Vault HA + ESO ✅   | 99.9%         |
| **Observability**      | 3.0         | 8           | 180            | Implementado ✅      | 99.9%         |
| **CI/CD Platform**     | 7.5         | 16          | 211            | Implementado ✅      | 99.5%         |
| **Data Services**      | 0.5         | 2           | 10 (operators) | Implementado ✅      | 99.9%         |
| **Security**           | 1.5         | 3           | 5              | Kyverno ENFORCE ✅  | 99.9%         |
| **TOTAL**              | **18.7**    | **41**      | **441**        | **100% Completo**   | **99.7% Avg** |

**Nota**: Data Services storage é por operator. Instances criadas adicionam ~75Gi (30Gi PG + 15Gi Redis + 30Gi RabbitMQ) por aplicação.

---

## 🔄 Como Atualizar Este Documento

Este documento evolui com a implementação e está **protegido por hook de validação**.

### 📋 Quando Atualizar (Hook Automatizado)

O hook `validate-architecture-diagrams.sh` **bloqueia commits** se estes arquivos mudarem sem atualização de diagramas:

| Arquivo Modificado                                 | Diagrama(s) Obrigatórios                   |
| -------------------------------------------------- | ------------------------------------------ |
| `SAD/docs/sad.md`                                  | #1 Visão Geral, #2 Ordem de Deploy         |
| `SAD/docs/adrs/*.md`                               | #1 Visão Geral (se nova decisão sistêmica) |
| `domains/platform-core/infra/terraform/main.tf`    | #3 Platform-Core                           |
| `domains/cicd-platform/infra/terraform/main.tf`    | #4 CI/CD Platform                          |
| `domains/observability/infra/terraform/main.tf`    | #5 Observability                           |
| `domains/data-services/infra/terraform/main.tf`    | #6 Data Services                           |
| `domains/secrets-management/docs/adr/adr-002-*.md` | #7 Secrets Management (decisão)            |
| `domains/security/docs/adr/adr-002-*.md`           | #8 Security (decisão)                      |
| `PROJECT-CONTEXT.md` (contratos)                   | #9 Comunicação Entre Domínios              |
| Novos domínios criados                             | #1, #2, #10                                |

### 🛠️ Processo de Atualização

1. **Modificar arquivo estratégico** (ex: terraform, ADR, SAD)
2. **Atualizar diagrama(s) correspondente(s)** neste arquivo
3. **Atualizar data**: `> **Última Atualização**: 2026-01-22`
4. **Commit ambos**:
   ```bash
   git add ARCHITECTURE-DIAGRAMS.md domains/platform-core/infra/terraform/main.tf
   git commit -m "feat(platform-core): add component X + update diagrams"
   ```

### ⚙️ Instalação do Hook

```bash
# Instalar hook de validação
cp docs/hooks/validate-architecture-diagrams.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

Ver detalhes em: [docs/hooks/README.md](docs/hooks/README.md)

### 🎯 Checklist de Atualização

Ao modificar domínio, atualizar:
- [ ] Status (✅ implementado / ⚠️ pendente)
- [ ] Novos componentes no diagrama Mermaid
- [ ] Novas setas de comunicação/dependência
- [ ] Contratos providos (se mudaram)
- [ ] Recursos (CPU, Memory, Storage) na tabela
- [ ] Data de atualização no header
- [ ] Legenda de cores (se status mudou)

### 📝 Template de Atualização

```markdown
## X. Nome do Domínio

```mermaid
graph TB
    %% Adicionar componentes, comunicações, contratos
```

**Responsabilidades**:
- Componente 1: Descrição
- Componente 2: Descrição

**Recursos**:
- CPU: X cores
- Memory: X Gi
- Storage: X Gi
```

### 🚫 Bypass do Hook (Não Recomendado)

```bash
# Usar somente para typo fixes ou emergências
git commit --no-verify
```

---

**Autor**: System Architect
**Versão**: 1.1 (GitLab v18.9.1 + Linkerd DEPLOYED + Kyverno ENFORCE)
**Data**: 2026-03-03
**Próxima Revisão**: Após deploy de cada domínio
