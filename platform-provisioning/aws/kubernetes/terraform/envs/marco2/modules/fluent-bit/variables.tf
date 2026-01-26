# -----------------------------------------------------------------------------
# Variables - Fluent Bit Module
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = "Nome do cluster EKS (usado como label no Loki)"
  type        = string
}

variable "namespace" {
  description = "Namespace Kubernetes para o Fluent Bit"
  type        = string
  default     = "monitoring"
}

variable "service_account_name" {
  description = "Nome da Service Account Kubernetes"
  type        = string
  default     = "fluent-bit"
}

variable "chart_version" {
  description = "Versão do Helm chart do Fluent Bit"
  type        = string
  default     = "0.43.0"
}

variable "image_tag" {
  description = "Tag da imagem Docker do Fluent Bit"
  type        = string
  default     = "3.0.0"
}

# -----------------------------------------------------------------------------
# Loki Configuration
# -----------------------------------------------------------------------------

variable "loki_endpoint" {
  description = "Endpoint completo do Loki para push de logs (ex: http://loki-gateway.monitoring:3100/loki/api/v1/push)"
  type        = string
}

variable "loki_host" {
  description = "Host do Loki Gateway (sem http://, sem porta, sem path)"
  type        = string
  default     = "loki-gateway.monitoring"
}

variable "loki_port" {
  description = "Porta do Loki Gateway"
  type        = number
  default     = 3100
}

# -----------------------------------------------------------------------------
# Filtering Configuration
# -----------------------------------------------------------------------------

variable "exclude_namespaces" {
  description = "Lista de namespaces para excluir dos logs (reduzir noise)"
  type        = list(string)
  default = [
    "kube-system",
    "kube-node-lease",
    "kube-public"
  ]
}
