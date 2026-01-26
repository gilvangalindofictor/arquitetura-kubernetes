# -----------------------------------------------------------------------------
# Variables - AWS Load Balancer Controller Module
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
}

variable "region" {
  description = "Região AWS onde o cluster está provisionado"
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "ID da VPC onde o cluster está provisionado"
  type        = string
}

variable "namespace" {
  description = "Namespace Kubernetes para o controller"
  type        = string
  default     = "kube-system"
}

variable "service_account_name" {
  description = "Nome da Service Account Kubernetes"
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "chart_version" {
  description = "Versão do Helm chart do AWS Load Balancer Controller"
  type        = string
  default     = "1.11.0"
}

variable "enable_shield" {
  description = "Habilita suporte para AWS Shield"
  type        = bool
  default     = false
}

variable "enable_waf" {
  description = "Habilita suporte para AWS WAF"
  type        = bool
  default     = false
}

variable "enable_wafv2" {
  description = "Habilita suporte para AWS WAF v2"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags a serem aplicadas nos recursos AWS"
  type        = map(string)
  default     = {}
}
