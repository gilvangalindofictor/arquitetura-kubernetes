# -----------------------------------------------------------------------------
# Variables - Marco 2 Environment
# -----------------------------------------------------------------------------

variable "region" {
  description = "Região AWS"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC"
  type        = string
}

variable "letsencrypt_email" {
  description = "Email para registro no Let's Encrypt (usado para notificações de expiração)"
  type        = string
  sensitive   = true
}

variable "grafana_admin_password" {
  description = "Senha do admin do Grafana"
  type        = string
  sensitive   = true
  default     = "admin123" # ALTERAR em produção
}

# -----------------------------------------------------------------------------
# Test Applications TLS Configuration (Fase 7.1)
# -----------------------------------------------------------------------------

variable "test_apps_domain_name" {
  description = "Base domain name for test applications (e.g., k8s-platform-test.com.br). Leave empty to disable TLS."
  type        = string
  default     = ""
}

variable "test_apps_create_route53_zone" {
  description = "Whether to create Route53 hosted zone for test applications domain. Set to false if zone already exists."
  type        = bool
  default     = false
}

variable "test_apps_enable_tls" {
  description = "Enable TLS/HTTPS for test applications ALB Ingresses. Requires test_apps_domain_name to be set."
  type        = bool
  default     = false
}
