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
