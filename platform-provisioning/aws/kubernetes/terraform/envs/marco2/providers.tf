# -----------------------------------------------------------------------------
# Providers Configuration - Marco 2
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.14"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# AWS Provider
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "k8s-platform"
      Marco     = "marco2"
      ManagedBy = "terraform"
    }
  }
}

# Obter configuração do cluster EKS
data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

# Kubernetes Provider com exec para token dinâmico (não expira)
provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)

  # Usar exec para obter token dinamicamente via AWS CLI
  # Isso evita problemas com token expirado durante deploys longos
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      var.cluster_name,
      "--region",
      var.region
    ]
  }
}

# Helm Provider com exec para token dinâmico
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)

    # Usar exec para obter token dinamicamente via AWS CLI
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        var.cluster_name,
        "--region",
        var.region
      ]
    }
  }
}
