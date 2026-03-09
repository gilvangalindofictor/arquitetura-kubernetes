variable "cluster_name" {
  description = "EKS cluster name (used for resource naming)"
  type        = string
}

variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "sa-east-1"
}

variable "environment" {
  description = "Environment name (staging, production)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace where the CronJob and ServiceAccount will be created"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider (used for IRSA trust policy)"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the EKS OIDC provider, e.g. https://oidc.eks.sa-east-1.amazonaws.com/id/XXXX"
  type        = string
}

variable "pushgateway_url" {
  description = "Prometheus Pushgateway URL (cluster-internal DNS, e.g. http://kube-prometheus-stack-prometheus-pushgateway.<namespace>.svc.cluster.local:9091)"
  type        = string
}

variable "budget_limit_usd" {
  description = "Monthly budget limit in USD"
  type        = number
  default     = 807
}

variable "budget_name" {
  description = "AWS Budget name for budget vs actual tracking"
  type        = string
  default     = "staging-monthly"
}

variable "common_tags" {
  description = "Common tags to apply to all AWS resources"
  type        = map(string)
  default     = {}
}
