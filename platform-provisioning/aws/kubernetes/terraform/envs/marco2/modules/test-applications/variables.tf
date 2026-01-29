# Variables for Test Applications Module

variable "namespace" {
  description = "Namespace para test applications"
  type        = string
  default     = "test-apps"
}

variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
}

variable "tags" {
  description = "Tags para recursos AWS"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# TLS Configuration (Fase 7.1)
# -----------------------------------------------------------------------------

variable "domain_name" {
  description = "Base domain name for test applications (e.g., test-apps.k8s-platform.com.br). Certificates will be issued for nginx-test.DOMAIN and echo-server.DOMAIN"
  type        = string
  default     = ""
}

variable "create_route53_zone" {
  description = "Whether to create Route53 hosted zone for the domain. Set to false if using existing zone."
  type        = bool
  default     = false
}

variable "enable_tls" {
  description = "Enable TLS/HTTPS for ALB Ingresses. Requires domain_name to be set."
  type        = bool
  default     = false
}
