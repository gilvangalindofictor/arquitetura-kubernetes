# -----------------------------------------------------------------------------
# External Secrets Operator Module Variables
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for External Secrets Operator"
  type        = string
  default     = "external-secrets-system"
}

variable "eso_chart_version" {
  description = "External Secrets Operator Helm chart version"
  type        = string
  default     = "0.9.11"
}

variable "replicas" {
  description = "Number of ESO replicas"
  type        = number
  default     = 1
}

variable "vault_addr" {
  description = "Vault service address"
  type        = string
}

variable "enable_monitoring" {
  description = "Enable Prometheus ServiceMonitor"
  type        = bool
  default     = true
}

variable "environment" {
  description = "Environment name (staging, prod)"
  type        = string
  default     = "staging"
}

variable "monitoring_namespace" {
  description = "Namespace for monitoring/ServiceMonitor"
  type        = string
  default     = "staging-observability-monitoring"
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# GAP-SEC-ESO-001 (2026-03-23): CSS name parametrizado para isolar staging/prod.
# Default "vault-backend" mantém backward compatibility com staging existente.
# Para prod: passar cluster_secret_store_name = "vault-backend-prod"
variable "cluster_secret_store_name" {
  description = "Name for the ClusterSecretStore resource (Vault backend). Use 'vault-backend-{env}' per environment."
  type        = string
  default     = "vault-backend"
}

# ECR Pull-Through Cache
variable "ecr_registry" {
  description = "ECR registry prefix for pull-through cache (e.g. 891377105802.dkr.ecr.us-east-1.amazonaws.com). Empty string uses upstream registries."
  type        = string
  default     = ""
}

# GAP-ESO-MULTI-INSTANCE: ESO é cluster-wide — apenas uma instância por cluster.
# Para ambientes adicionais (ex: prod), usar deploy_operator=false para criar apenas
# o ClusterSecretStore sem tentar instalar o Helm chart novamente.
variable "deploy_operator" {
  description = "Whether to deploy the ESO Helm release. Set to false when ESO is already deployed in another namespace (e.g. staging) since ESO is cluster-scoped."
  type        = bool
  default     = true
}
