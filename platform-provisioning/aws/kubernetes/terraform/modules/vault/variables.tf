# -----------------------------------------------------------------------------
# Vault Module Variables
# -----------------------------------------------------------------------------

variable "environment" {
  description = "Environment name (staging, prod)"
  type        = string
  default     = "staging"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "namespace" {
  description = "Kubernetes namespace for Vault"
  type        = string
  default     = "vault-system"
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider"
  type        = string
}

variable "vault_chart_version" {
  description = "Vault Helm chart version"
  type        = string
  default     = "0.27.0"
}

variable "replicas" {
  description = "Number of Vault replicas (1 for staging, 3 for prod)"
  type        = number
  default     = 1
}

variable "storage_class" {
  description = "Storage class for Vault PVCs"
  type        = string
  # GAP-ARCH-006: default migrado gp2→gp3 (2026-03-23) — gp3 é 20% mais barato e sem burst IOPS
  default = "gp3"
}

variable "pvc_size" {
  description = "Size of Vault PVC"
  type        = string
  default     = "10Gi"
}

variable "enable_monitoring" {
  description = "Enable Prometheus ServiceMonitor"
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations for Vault server pods"
  type = list(object({
    key      = string
    operator = string
    value    = optional(string)
    effect   = string
  }))
  default = []
}

# -----------------------------------------------------------------------------
# Ingress
# -----------------------------------------------------------------------------

variable "helm_release_name" {
  description = "Name for the Helm release (use unique name per env to avoid cluster-scoped resource conflicts)"
  type        = string
  default     = "vault"
}

variable "injector_enabled" {
  description = "Enable Vault Agent Injector (disable for prod if staging already has it — cluster-scoped resources conflict)"
  type        = bool
  default     = true
}

variable "ingress_enabled" {
  description = "Habilitar ALB Ingress para o Vault UI"
  type        = bool
  default     = false
}

variable "ingress_host" {
  description = "Hostname para o Ingress do Vault (e.g., vault.staging.internal)"
  type        = string
  default     = ""
}

variable "ingress_group_name" {
  description = "ALB Ingress group name para compartilhar ALB entre serviços"
  type        = string
  default     = ""
}

variable "ingress_extra_hosts" {
  description = "Lista de hostnames adicionais para dual-host Ingress (DNS Fase 7 migration)"
  type        = list(string)
  default     = []
}

variable "ingress_certificate_arns" {
  description = "Lista de ARNs de certificados ACM para o Ingress (comma-separated no annotation). Se vazio, usa certificate-arn padrão do ALB."
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# IAM naming override (for brownfield imports where name was created without env prefix)
# -----------------------------------------------------------------------------

variable "iam_name_override" {
  description = "Override IAM role/policy name. If empty, uses VaultIRSA-<environment>-<cluster_name>. Use for clusters where the role was created manually without the env prefix (avoid destroy+recreate)."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Node Placement
# -----------------------------------------------------------------------------

variable "node_selector" {
  description = "nodeSelector labels for Vault server pods (e.g. { \"eks.amazonaws.com/nodegroup\" = \"workloads\" }). Empty map = no nodeSelector."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# ECR Pull-Through Cache
# -----------------------------------------------------------------------------

variable "ecr_registry" {
  description = "ECR registry prefix for pull-through cache (e.g. 891377105802.dkr.ecr.us-east-1.amazonaws.com). Empty string uses upstream registries."
  type        = string
  default     = ""
}
