# =============================================================================
# CLUSTER OUTPUTS (Padronizados para consumo pelos domínios)
# =============================================================================

output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_ca_certificate" {
  description = "EKS cluster CA certificate (base64)"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "OIDC provider URL for IRSA"
  value       = module.eks.cluster_oidc_issuer_url
}

# =============================================================================
# STORAGE OUTPUTS (Padronizados)
# =============================================================================

output "storage_class_name" {
  description = "Default storage class name (EBS gp3)"
  value       = "gp3"
}

output "storage_class_fast" {
  description = "Fast storage class name (EBS io2)"
  value       = "io2"
}

# =============================================================================
# OBJECT STORAGE OUTPUTS (S3-Compatible)
# =============================================================================

output "object_storage_buckets" {
  description = "S3 buckets created for platform storage"
  value = {
    for bucket in var.s3_buckets :
    bucket.purpose => module.s3.bucket_names[bucket.name]
  }
}

output "object_storage_endpoint" {
  description = "S3 endpoint (AWS standard)"
  value       = "https://s3.${var.aws_region}.amazonaws.com"
}

output "object_storage_region" {
  description = "S3 bucket region"
  value       = var.aws_region
}

# =============================================================================
# IAM OUTPUTS (IRSA Roles)
# =============================================================================

output "iam_role_arns" {
  description = "IAM role ARNs for service accounts by namespace"
  value       = module.iam.namespace_role_arns
}

# =============================================================================
# NETWORK OUTPUTS
# =============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (where EKS nodes run)"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs (for load balancers)"
  value       = module.vpc.public_subnet_ids
}

# =============================================================================
# USAGE INSTRUCTIONS
# =============================================================================

output "usage_instructions" {
  description = "How domains should consume these outputs"
  value = <<-EOT
  
  # Domains should consume these outputs as variables:
  
  ## In /domains/<domain>/infra/terraform/variables.tf:
  
  variable "cluster_endpoint" {
    description = "Kubernetes API endpoint from platform-provisioning"
    type        = string
  }
  
  variable "storage_class_name" {
    description = "Default storage class from platform-provisioning"
    type        = string
    default     = "gp3"
  }
  
  variable "s3_bucket_metrics" {
    description = "S3 bucket for metrics from platform-provisioning"
    type        = string
  }
  
  ## Usage:
  
  resource "kubernetes_persistent_volume_claim" "example" {
    spec {
      storage_class_name = var.storage_class_name  # ← Parametrizado
      ...
    }
  }
  
  EOT
}
