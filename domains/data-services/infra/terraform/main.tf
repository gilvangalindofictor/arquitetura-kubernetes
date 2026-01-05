# =============================================================================
# DATA SERVICES DOMAIN - Cloud-Agnostic Terraform
# =============================================================================
# Domínio: data-services
# Responsabilidade: Operators para bancos de dados e message brokers gerenciados
# Deploy Priority: #5 (após observability)
#
# Components:
# - Zalando Postgres Operator (PostgreSQL HA clusters)
# - Redis Cluster Operator (Redis HA clusters)
# - RabbitMQ Cluster Operator (RabbitMQ HA clusters)
# - Velero (Kubernetes backup/restore)
#
# Nota: Este terraform instala OPERATORS, não instances.
#       Instances são criadas sob demanda via CRDs.
# =============================================================================

terraform {
  required_version = ">= 1.6"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

# =============================================================================
# PROVIDER CONFIGURATION
# =============================================================================

provider "kubernetes" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(var.cluster_ca_certificate)

  # Autenticação configurada via kubeconfig ou cloud-specific methods
  # (AWS: exec aws eks get-token, Azure: exec kubelogin, GCP: exec gcloud)
}

provider "helm" {
  kubernetes {
    host                   = var.cluster_endpoint
    cluster_ca_certificate = base64decode(var.cluster_ca_certificate)
  }
}

# =============================================================================
# NAMESPACE: data-services
# =============================================================================

resource "kubernetes_namespace" "data_services" {
  metadata {
    name = "data-services"

    labels = {
      "domain"      = "data-services"
      "managed-by"  = "terraform"
      "environment" = var.environment
    }

    annotations = {
      "linkerd.io/inject" = "enabled" # Service mesh mTLS
    }
  }
}

# =============================================================================
# NAMESPACE: postgres-operator (Zalando)
# =============================================================================

resource "kubernetes_namespace" "postgres_operator" {
  metadata {
    name = "postgres-operator"

    labels = {
      "domain"      = "data-services"
      "component"   = "postgres-operator"
      "managed-by"  = "terraform"
      "environment" = var.environment
    }

    annotations = {
      "linkerd.io/inject" = "disabled" # Operators geralmente não precisam mesh
    }
  }
}

# =============================================================================
# ZALANDO POSTGRES OPERATOR
# =============================================================================
# Operator para PostgreSQL HA clusters com Patroni + Spilo

resource "helm_release" "postgres_operator" {
  name       = "postgres-operator"
  repository = "https://opensource.zalando.com/postgres-operator/charts/postgres-operator"
  chart      = "postgres-operator"
  version    = var.postgres_operator_version # 1.10.1

  namespace        = kubernetes_namespace.postgres_operator.metadata[0].name
  create_namespace = false

  values = [
    yamlencode({
      configGeneral = {
        # Cloud-agnostic: Kubernetes CRDs only
        kubernetes_use_configmaps = true
        docker_image              = "ghcr.io/zalando/spilo-15:3.0-p1" # PostgreSQL 15

        # Storage parametrizado
        # Clusters criados via CRD herdam este storageClass
      }

      configKubernetes = {
        # RBAC
        enable_pod_disruption_budget = true
        pdb_name_format              = "postgres-{cluster}-pdb"

        # Observability
        enable_pod_antiaffinity = true # HA: pods em nodes diferentes
      }

      configConnectionPooler = {
        # PgBouncer para connection pooling
        connection_pooler_image = "registry.opensource.zalan.do/acid/pgbouncer:master-27"
      }

      # Monitoring
      serviceMonitor = {
        enabled   = var.enable_monitoring
        namespace = kubernetes_namespace.postgres_operator.metadata[0].name
      }
    })
  ]

  depends_on = [kubernetes_namespace.postgres_operator]
}

# =============================================================================
# NAMESPACE: redis-operator
# =============================================================================

resource "kubernetes_namespace" "redis_operator" {
  metadata {
    name = "redis-operator"

    labels = {
      "domain"      = "data-services"
      "component"   = "redis-operator"
      "managed-by"  = "terraform"
      "environment" = var.environment
    }

    annotations = {
      "linkerd.io/inject" = "disabled"
    }
  }
}

# =============================================================================
# REDIS CLUSTER OPERATOR
# =============================================================================
# Operator para Redis Cluster HA (master-replica topology)

resource "helm_release" "redis_operator" {
  name       = "redis-operator"
  repository = "https://ot-container-kit.github.io/helm-charts"
  chart      = "redis-operator"
  version    = var.redis_operator_version # 0.15.1

  namespace        = kubernetes_namespace.redis_operator.metadata[0].name
  create_namespace = false

  values = [
    yamlencode({
      # Operator configuration
      redisOperator = {
        replicaCount = 1 # Operator é stateless

        # RBAC
        rbac = {
          create = true
        }

        # Monitoring
        serviceMonitor = {
          enabled   = var.enable_monitoring
          namespace = kubernetes_namespace.redis_operator.metadata[0].name
        }
      }

      # Redis Cluster defaults (aplicado a todas as CRDs)
      redisCluster = {
        # Storage parametrizado (CRDs herdam)
        # Exemplo CRD:
        # storage:
        #   volumeClaimTemplate:
        #     spec:
        #       storageClassName: var.storage_class_name
        #       resources:
        #         requests:
        #           storage: 5Gi
      }
    })
  ]

  depends_on = [kubernetes_namespace.redis_operator]
}

# =============================================================================
# NAMESPACE: rabbitmq-system (RabbitMQ Operator)
# =============================================================================

resource "kubernetes_namespace" "rabbitmq_operator" {
  metadata {
    name = "rabbitmq-system"

    labels = {
      "domain"      = "data-services"
      "component"   = "rabbitmq-operator"
      "managed-by"  = "terraform"
      "environment" = var.environment
    }

    annotations = {
      "linkerd.io/inject" = "disabled"
    }
  }
}

# =============================================================================
# RABBITMQ CLUSTER OPERATOR
# =============================================================================
# Operator para RabbitMQ Cluster HA (quorum queues)

resource "helm_release" "rabbitmq_operator" {
  name       = "rabbitmq-cluster-operator"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "rabbitmq-cluster-operator"
  version    = var.rabbitmq_operator_version # 3.12.0

  namespace        = kubernetes_namespace.rabbitmq_operator.metadata[0].name
  create_namespace = false

  values = [
    yamlencode({
      # Operator configuration
      clusterOperator = {
        replicaCount = 1

        # RBAC
        rbac = {
          create = true
        }

        # Monitoring
        metrics = {
          enabled = var.enable_monitoring
          serviceMonitor = {
            enabled = var.enable_monitoring
          }
        }
      }

      # Webhook para validação de CRDs
      msgTopologyOperator = {
        enabled = true # Suporte a Exchanges, Queues via CRDs
      }
    })
  ]

  depends_on = [kubernetes_namespace.rabbitmq_operator]
}

# =============================================================================
# NAMESPACE: velero (Backup/Restore)
# =============================================================================

resource "kubernetes_namespace" "velero" {
  metadata {
    name = "velero"

    labels = {
      "domain"      = "data-services"
      "component"   = "velero"
      "managed-by"  = "terraform"
      "environment" = var.environment
    }

    annotations = {
      "linkerd.io/inject" = "disabled" # Backup controller
    }
  }
}

# =============================================================================
# VELERO - Kubernetes Backup/Restore
# =============================================================================
# Cloud-agnostic backup para PVCs, CRDs, namespaces

resource "helm_release" "velero" {
  name       = "velero"
  repository = "https://vmware-tanzu.github.io/helm-charts"
  chart      = "velero"
  version    = var.velero_version # 5.2.0

  namespace        = kubernetes_namespace.velero.metadata[0].name
  create_namespace = false

  values = [
    yamlencode({
      # Credentials para S3-compatible storage
      # Velero suporta AWS S3, Azure Blob, GCS, Minio (cloud-agnostic)
      credentials = {
        # Secrets criados manualmente ou via secrets-management domain
        useSecret = true
        name      = "velero-backup-credentials"
        # Conteúdo:
        # [default]
        # aws_access_key_id=<KEY>
        # aws_secret_access_key=<SECRET>
      }

      configuration = {
        # Provider cloud-agnostic (S3 API)
        provider = "aws" # Compatible com Minio, Wasabi, DigitalOcean Spaces

        # Backup storage location
        backupStorageLocation = {
          name   = "default"
          bucket = var.velero_backup_bucket # Ex: k8s-backups-production
          config = {
            region           = var.velero_region # Ex: us-east-1 (Minio ignora)
            s3ForcePathStyle = "true"            # Minio compatibility
            s3Url            = var.velero_s3_url # Ex: https://minio.example.com
          }
        }

        # Volume snapshot location (para PVCs)
        volumeSnapshotLocation = {
          name = "default"
          config = {
            region = var.velero_region
          }
        }

        # Schedule de backups automáticos
        # Exemplo: backup diário de todos os namespaces
      }

      # Integração com CSI drivers (snapshots de PVCs)
      snapshotsEnabled = true

      # Monitoring
      metrics = {
        enabled = var.enable_monitoring
        serviceMonitor = {
          enabled = var.enable_monitoring
        }
      }

      # Init containers para plugins
      initContainers = [
        {
          name  = "velero-plugin-for-aws"
          image = "velero/velero-plugin-for-aws:v1.9.0"
          volumeMounts = [
            {
              mountPath = "/target"
              name      = "plugins"
            }
          ]
        }
      ]
    })
  ]

  depends_on = [kubernetes_namespace.velero]
}

# =============================================================================
# KUBERNETES SECRET: Velero S3 Credentials
# =============================================================================
# Temporário - migrar para secrets-management (Vault/ESO) em Sprint+1

resource "kubernetes_secret" "velero_credentials" {
  metadata {
    name      = "velero-backup-credentials"
    namespace = kubernetes_namespace.velero.metadata[0].name

    labels = {
      "managed-by" = "terraform"
      "component"  = "velero"
    }
  }

  data = {
    cloud = <<-EOT
      [default]
      aws_access_key_id=${var.velero_s3_access_key}
      aws_secret_access_key=${var.velero_s3_secret_key}
    EOT
  }

  type = "Opaque"
}

# =============================================================================
# OUTPUTS
# =============================================================================

output "namespaces" {
  description = "Namespaces criados pelo domínio data-services"
  value = {
    data_services    = kubernetes_namespace.data_services.metadata[0].name
    postgres         = kubernetes_namespace.postgres_operator.metadata[0].name
    redis            = kubernetes_namespace.redis_operator.metadata[0].name
    rabbitmq         = kubernetes_namespace.rabbitmq_operator.metadata[0].name
    velero           = kubernetes_namespace.velero.metadata[0].name
  }
}

output "operators_installed" {
  description = "Operators instalados e versões"
  value = {
    postgres_operator = {
      version   = var.postgres_operator_version
      namespace = kubernetes_namespace.postgres_operator.metadata[0].name
      chart     = "postgres-operator"
    }
    redis_operator = {
      version   = var.redis_operator_version
      namespace = kubernetes_namespace.redis_operator.metadata[0].name
      chart     = "redis-operator"
    }
    rabbitmq_operator = {
      version   = var.rabbitmq_operator_version
      namespace = kubernetes_namespace.rabbitmq_operator.metadata[0].name
      chart     = "rabbitmq-cluster-operator"
    }
    velero = {
      version   = var.velero_version
      namespace = kubernetes_namespace.velero.metadata[0].name
      chart     = "velero"
    }
  }
}

output "usage_instructions" {
  description = "Instruções para criar database/broker instances"
  value = <<-EOT
    ============================================================
    DATA SERVICES DOMAIN - OPERATORS INSTALADOS
    ============================================================

    Os operators estão prontos. Para criar instances:

    1️⃣ POSTGRESQL HA CLUSTER (via Zalando Operator):
    ---------------------------------------------------
    kubectl apply -f - <<EOF
    apiVersion: "acid.zalan.do/v1"
    kind: postgresql
    metadata:
      name: my-postgres-cluster
      namespace: data-services
    spec:
      teamId: "myapp"
      volume:
        size: 10Gi
        storageClass: ${var.storage_class_name}
      numberOfInstances: 3  # HA: 1 master + 2 replicas
      users:
        myapp: []
      databases:
        myappdb: myapp
      postgresql:
        version: "15"
      patroni:
        ttl: 30
        loop_wait: 10
    EOF

    Conexão:
    Host: my-postgres-cluster.data-services.svc.cluster.local
    Port: 5432
    User: myapp
    Password: kubectl get secret myapp.my-postgres-cluster.credentials.postgresql.acid.zalan.do -o jsonpath='{.data.password}' | base64 -d

    2️⃣ REDIS CLUSTER (via Redis Operator):
    ---------------------------------------------------
    kubectl apply -f - <<EOF
    apiVersion: redis.redis.opstreelabs.in/v1beta1
    kind: RedisCluster
    metadata:
      name: my-redis-cluster
      namespace: data-services
    spec:
      clusterSize: 3  # HA: 3 masters
      kubernetesConfig:
        image: redis:7.0
      storage:
        volumeClaimTemplate:
          spec:
            storageClassName: ${var.storage_class_name}
            resources:
              requests:
                storage: 5Gi
    EOF

    Conexão:
    Host: my-redis-cluster.data-services.svc.cluster.local
    Port: 6379

    3️⃣ RABBITMQ CLUSTER (via RabbitMQ Operator):
    ---------------------------------------------------
    kubectl apply -f - <<EOF
    apiVersion: rabbitmq.com/v1beta1
    kind: RabbitmqCluster
    metadata:
      name: my-rabbitmq-cluster
      namespace: data-services
    spec:
      replicas: 3  # HA: 3 nodes
      persistence:
        storageClassName: ${var.storage_class_name}
        storage: 10Gi
      rabbitmq:
        additionalPlugins:
          - rabbitmq_management
          - rabbitmq_prometheus
    EOF

    Conexão:
    Host: my-rabbitmq-cluster.data-services.svc.cluster.local
    Port: 5672 (AMQP), 15672 (Management UI)
    User: kubectl get secret my-rabbitmq-cluster-default-user -o jsonpath='{.data.username}' | base64 -d
    Password: kubectl get secret my-rabbitmq-cluster-default-user -o jsonpath='{.data.password}' | base64 -d

    4️⃣ VELERO BACKUPS:
    ---------------------------------------------------
    # Backup manual de um namespace
    velero backup create my-backup --include-namespaces data-services

    # Backup agendado (diário às 2AM)
    velero schedule create daily-backup --schedule="0 2 * * *" --ttl 720h

    # Restore de backup
    velero restore create --from-backup my-backup

    # Listar backups
    velero backup get

    ============================================================
    OBSERVABILITY
    ============================================================

    ServiceMonitors ativos:
    - postgres-operator (namespace: postgres-operator)
    - redis-operator (namespace: redis-operator)
    - rabbitmq-operator (namespace: rabbitmq-system)
    - velero (namespace: velero)

    Dashboards Grafana (via observability domain):
    - PostgreSQL: Conexões, Queries/sec, Replication lag
    - Redis: Memory usage, Commands/sec, Keyspace
    - RabbitMQ: Queue depth, Publish/Consume rates
    - Velero: Backup success rate, Duration

    ============================================================
  EOT
}
