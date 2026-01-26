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
}

variable "grafana_admin_password" {
  description = "Senha do admin do Grafana"
  type        = string
  sensitive   = true
  default     = "admin123"  # ALTERAR em produção
}
