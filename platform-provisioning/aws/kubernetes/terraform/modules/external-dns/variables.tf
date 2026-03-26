# -----------------------------------------------------------------------------
# External DNS Module - Variables
# Fase 5: DNS automation for EKS services via Route53
# -----------------------------------------------------------------------------

#------------------------------------------------------------------------------
# General
#------------------------------------------------------------------------------

variable "cluster_name" {
  description = "EKS cluster name (used for tagging, IRSA naming, and txtOwnerId)"
  type        = string
}

variable "environment" {
  description = "Deployment environment (staging | prod)"
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be 'staging' or 'prod'."
  }
}

variable "namespace" {
  description = "Kubernetes namespace for external-dns deployment"
  type        = string
  default     = "external-dns"
}

variable "create_namespace" {
  description = "Create the Kubernetes namespace if it does not exist"
  type        = bool
  default     = true
}

#------------------------------------------------------------------------------
# IRSA (IAM Roles for Service Accounts)
#------------------------------------------------------------------------------

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider for IRSA trust policy"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the EKS OIDC provider (used to build the trust policy condition)"
  type        = string
}

variable "service_account_name" {
  description = "Name of the Kubernetes ServiceAccount for external-dns"
  type        = string
  default     = "external-dns"
}

#------------------------------------------------------------------------------
# Route53 Configuration
#------------------------------------------------------------------------------

variable "hosted_zone_ids" {
  description = "List of Route53 Hosted Zone IDs that external-dns is allowed to manage"
  type        = list(string)
}

variable "domain_filters" {
  description = "List of domain names to filter (external-dns will only manage records matching these domains)"
  type        = list(string)
}

#------------------------------------------------------------------------------
# Helm Chart Configuration
#------------------------------------------------------------------------------

variable "chart_version" {
  description = "external-dns Helm chart version (kubernetes-sigs official — https://kubernetes-sigs.github.io/external-dns/)"
  type        = string
  default     = "1.15.0"
}

# GAP-EXTERNALDNS-IMAGE-01 (atualizado 2026-03-21):
# Substituido chart Bitnami por chart CNCF oficial kubernetes-sigs/external-dns.
# Imagem oficial: registry.k8s.io/external-dns/external-dns:v0.15.0
# Acessivel via ECR pull-through cache "k8s" -> registry.k8s.io (criado 2026-03-19).
# ECR path: 891377105802.dkr.ecr.us-east-1.amazonaws.com/k8s/external-dns/external-dns:v0.15.0
variable "image_registry" {
  description = "Container image registry for external-dns. Default: ECR pull-through cache (k8s -> registry.k8s.io)"
  type        = string
  default     = "891377105802.dkr.ecr.us-east-1.amazonaws.com"
}

variable "image_repository" {
  description = "Container image repository for external-dns (relative to registry). ECR pull-through path for registry.k8s.io/external-dns/external-dns"
  type        = string
  default     = "k8s/external-dns/external-dns"
}

variable "image_tag" {
  description = "Container image tag for external-dns (official kubernetes-sigs tag format: v0.15.0)"
  type        = string
  default     = "v0.15.0"
}

variable "policy" {
  description = "DNS record management policy: sync (create+update+delete) or upsert-only (create+update only)"
  type        = string
  default     = "sync"

  validation {
    condition     = contains(["sync", "upsert-only"], var.policy)
    error_message = "policy must be 'sync' or 'upsert-only'."
  }
}

variable "registry" {
  description = "Registry type for ownership tracking (txt or noop)"
  type        = string
  default     = "txt"
}

variable "txt_prefix" {
  description = "Prefix for TXT ownership records"
  type        = string
  default     = "extdns-"
}

variable "interval" {
  description = "Polling interval for DNS record synchronization"
  type        = string
  default     = "1m"
}

variable "log_level" {
  description = "Log level for external-dns (debug, info, warning, error)"
  type        = string
  default     = "info"
}

#------------------------------------------------------------------------------
# Tags
#------------------------------------------------------------------------------

variable "common_tags" {
  description = "Common tags applied to all AWS resources"
  type        = map(string)
  default     = {}
}
