# -----------------------------------------------------------------------------
# Variables - Cert-Manager Module
# -----------------------------------------------------------------------------

variable "namespace" {
  description = "Namespace Kubernetes para o Cert-Manager"
  type        = string
  default     = "cert-manager"
}

variable "chart_version" {
  description = "Versão do Helm chart do Cert-Manager"
  type        = string
  default     = "v1.16.3"
}

variable "create_cluster_issuers" {
  description = "Criar ClusterIssuers para Let's Encrypt (staging e production)"
  type        = bool
  default     = true
}

variable "letsencrypt_email" {
  description = "Email para registro no Let's Encrypt"
  type        = string
}
