# -----------------------------------------------------------------------------
# Marco 2: Platform Services
# Descrição: Serviços fundamentais de plataforma (Ingress, Cert-Manager, etc.)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# OIDC Provider para EKS (Pré-requisito para IRSA)
# -----------------------------------------------------------------------------

# Nota: data.aws_eks_cluster.cluster já está definido em providers.tf

# Extrair informações do OIDC issuer
locals {
  oidc_issuer_url   = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
  oidc_provider_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(local.oidc_issuer_url, "https://", "")}"
}

data "aws_caller_identity" "current" {}

# Obter certificado TLS do OIDC endpoint
data "tls_certificate" "eks" {
  url = local.oidc_issuer_url
}

# Criar OIDC Provider (se não existir)
resource "aws_iam_openid_connect_provider" "eks" {
  url             = local.oidc_issuer_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]

  tags = {
    Name        = "eks-oidc-provider-${var.cluster_name}"
    Environment = "production"
    Project     = "k8s-platform"
    Marco       = "marco2"
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# AWS Load Balancer Controller
# -----------------------------------------------------------------------------

module "aws_load_balancer_controller" {
  source = "./modules/aws-load-balancer-controller"

  cluster_name         = var.cluster_name
  region               = var.region
  vpc_id               = var.vpc_id
  namespace            = "kube-system"
  service_account_name = "aws-load-balancer-controller"
  chart_version        = "1.11.0"

  # AWS features (desabilitadas por padrão para economia)
  enable_shield = false
  enable_waf    = false
  enable_wafv2  = false

  tags = {
    Environment = "production"
    Project     = "k8s-platform"
    Marco       = "marco2"
    ManagedBy   = "terraform"
  }

  depends_on = [aws_iam_openid_connect_provider.eks]
}

# -----------------------------------------------------------------------------
# Cert-Manager
# -----------------------------------------------------------------------------

module "cert_manager" {
  source = "./modules/cert-manager"

  namespace              = "cert-manager"
  chart_version          = "v1.16.3"
  create_cluster_issuers = false # Criados separadamente após CRDs instalados
  letsencrypt_email      = var.letsencrypt_email

  depends_on = [module.aws_load_balancer_controller]
}

# -----------------------------------------------------------------------------
# Kube-Prometheus-Stack (Monitoring)
# -----------------------------------------------------------------------------

module "kube_prometheus_stack" {
  source = "./modules/kube-prometheus-stack"

  namespace     = "monitoring"
  chart_version = "69.4.0"

  # Prometheus
  prometheus_storage_size = "20Gi"
  prometheus_retention    = "15d"

  # Grafana
  grafana_admin_password  = data.aws_secretsmanager_secret_version.grafana_admin_password.secret_string
  grafana_storage_size    = "5Gi"
  grafana_ingress_enabled = false # Acesso via port-forward por enquanto

  # Alertmanager
  alertmanager_storage_size = "2Gi"

  depends_on = [module.cert_manager]
}

# -----------------------------------------------------------------------------
# Loki (Logging)
# -----------------------------------------------------------------------------

module "loki" {
  source = "./modules/loki"

  cluster_name         = var.cluster_name
  region               = var.region
  namespace            = "monitoring"
  service_account_name = "loki"
  chart_version        = "5.42.0"

  # Storage configuration
  retention_days    = 30
  enable_versioning = false # Desabilitar para economia
  storage_class     = "gp2"
  write_pvc_size    = "10Gi"
  backend_pvc_size  = "10Gi"

  # Replication and scaling
  replication_factor = 2
  read_replicas      = 2
  write_replicas     = 2
  backend_replicas   = 2

  tags = {
    Environment = "production"
    Project     = "k8s-platform"
    Marco       = "marco2"
    ManagedBy   = "terraform"
  }

  depends_on = [module.kube_prometheus_stack]
}

# -----------------------------------------------------------------------------
# Fluent Bit (Log Collector)
# -----------------------------------------------------------------------------

module "fluent_bit" {
  source = "./modules/fluent-bit"

  cluster_name         = var.cluster_name
  namespace            = "monitoring"
  service_account_name = "fluent-bit"
  chart_version        = "0.43.0"
  image_tag            = "3.0.0"

  # Loki configuration
  loki_endpoint = module.loki.loki_push_endpoint
  loki_host     = "loki-gateway.monitoring"
  loki_port     = 80

  # Filtering (exclude noisy namespaces)
  exclude_namespaces = [
    "kube-system",
    "kube-node-lease",
    "kube-public"
  ]

  depends_on = [module.loki]
}

# -----------------------------------------------------------------------------
# Network Policies (Security - Marco 2 Fase 5)
# -----------------------------------------------------------------------------

module "network_policies" {
  source = "./modules/network-policies"

  # Namespaces com Network Policies
  namespaces = ["monitoring", "cert-manager", "kube-system"]

  # Fase 5.2.1: Aplicar políticas básicas PRIMEIRO
  enable_dns_policy        = true
  enable_api_server_policy = true

  # Fase 5.2.2: Aplicar políticas específicas de monitoring
  enable_prometheus_scraping   = true
  enable_loki_ingestion        = true
  enable_grafana_datasources   = true
  enable_cert_manager_egress   = true

  # Fase 5.2.3: Default Deny - DESABILITADO por padrão
  # ⚠️ IMPORTANTE: Habilitar APENAS após validar que allow policies funcionam
  # Para habilitar: mudar para true e executar terraform apply
  enable_default_deny = false

  # Namespace configuration
  prometheus_namespace   = "monitoring"
  loki_namespace         = "monitoring"
  grafana_namespace      = "monitoring"
  cert_manager_namespace = "cert-manager"
  kube_dns_namespace     = "kube-system"

  # Dependências: aplicar APÓS todos os serviços estarem rodando
  depends_on = [
    module.kube_prometheus_stack,
    module.loki,
    module.fluent_bit,
    module.cert_manager
  ]
}
