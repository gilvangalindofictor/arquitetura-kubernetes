# AWS Region
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

# VPC Configuration
variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
  default     = "kubernetes-platform-vpc"
}

# EKS Cluster Configuration
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "kubernetes-platform"
}

# S3 Buckets for Storage
variable "s3_buckets" {
  description = "List of S3 buckets to create for platform storage"
  type = list(object({
    name           = string
    purpose        = string
    lifecycle_days = number
  }))
  default = [
    {
      name           = "platform-metrics"
      purpose        = "Prometheus long-term metrics"
      lifecycle_days = 90
    },
    {
      name           = "platform-logs"
      purpose        = "Loki long-term logs"
      lifecycle_days = 30
    },
    {
      name           = "platform-traces"
      purpose        = "Tempo traces"
      lifecycle_days = 7
    },
    {
      name           = "platform-backups"
      purpose        = "Velero cluster backups"
      lifecycle_days = 30
    }
  ]
}

# Kubernetes Namespaces (for IAM roles)
variable "kubernetes_namespaces" {
  description = "Kubernetes namespaces that will need IAM roles (IRSA)"
  type        = list(string)
  default = [
    "observability-dev",
    "observability-hml",
    "observability-prd",
    "platform-core-dev",
    "platform-core-hml",
    "platform-core-prd",
    "cicd-platform",
    "data-services-dev",
    "data-services-hml",
    "data-services-prd",
    "secrets-management",
    "security"
  ]
}
