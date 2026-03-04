# -----------------------------------------------------------------------------
# Linkerd Module - Variables
# GAP-011: mTLS End-to-End | BACEN BCB 85/2021 Compliance
# -----------------------------------------------------------------------------

#------------------------------------------------------------------------------
# General
#------------------------------------------------------------------------------

variable "cluster_name" {
  description = "EKS cluster name (used for tagging and resource naming)"
  type        = string
}

variable "environment" {
  description = "Deployment environment (staging | production)"
  type        = string
  default     = "staging"

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be 'staging' or 'production'."
  }
}

variable "common_tags" {
  description = "Common tags applied to all Kubernetes resources (labels)"
  type        = map(string)
  default     = {}
}

#------------------------------------------------------------------------------
# Linkerd Core
#------------------------------------------------------------------------------

variable "linkerd_version" {
  description = "Linkerd Helm chart version (stable channel). See https://artifacthub.io/packages/helm/linkerd2/linkerd-control-plane"
  type        = string
  default     = "1.16.11" # Corresponds to Linkerd stable-2.16.x control-plane chart

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.linkerd_version))
    error_message = "linkerd_version must be a semver string (e.g. '1.16.11')."
  }
}

variable "linkerd_crds_chart_version" {
  description = "Linkerd CRDs Helm chart version. Must be aligned with linkerd_version."
  type        = string
  default     = "1.8.0" # linkerd-crds chart for stable-2.16.x
}

variable "trust_domain" {
  description = "Linkerd trust domain — must match the cluster domain. Used as SPIFFE trust anchor."
  type        = string
  default     = "cluster.local"
}

variable "certificate_validity_days" {
  description = "Validity period in days for the trust anchor (root CA) certificate."
  type        = number
  default     = 365

  validation {
    condition     = var.certificate_validity_days >= 1 && var.certificate_validity_days <= 3650
    error_message = "certificate_validity_days must be between 1 and 3650 days."
  }
}

variable "issuer_certificate_validity_hours" {
  description = "Validity period in hours for the intermediate issuer certificate."
  type        = number
  default     = 8760 # 365 days in hours
}

variable "proxy_cpu_request" {
  description = "CPU request for the Linkerd sidecar proxy container."
  type        = string
  default     = "100m"
}

variable "proxy_memory_request" {
  description = "Memory request for the Linkerd sidecar proxy container."
  type        = string
  default     = "64Mi"
}

variable "proxy_cpu_limit" {
  description = "CPU limit for the Linkerd sidecar proxy container."
  type        = string
  default     = "500m"
}

variable "proxy_memory_limit" {
  description = "Memory limit for the Linkerd sidecar proxy container."
  type        = string
  default     = "256Mi"
}

#------------------------------------------------------------------------------
# High Availability
#------------------------------------------------------------------------------

variable "ha_mode" {
  description = "Enable HA mode for the Linkerd control plane (recommended for production). Sets replicas=3 and PodDisruptionBudgets."
  type        = bool
  default     = false # staging: false | production: true
}

#------------------------------------------------------------------------------
# Viz Extension
#------------------------------------------------------------------------------

variable "enable_viz" {
  description = "Deploy the Linkerd Viz extension (dashboard, Prometheus scraping, Tap API)."
  type        = bool
  default     = true
}

variable "linkerd_viz_chart_version" {
  description = "Linkerd Viz Helm chart version. Must match the control-plane version channel."
  type        = string
  default     = "30.12.11" # linkerd-viz chart for stable-2.16.x
}

variable "viz_namespace" {
  description = "Kubernetes namespace for the Linkerd Viz extension."
  type        = string
  default     = "linkerd-viz"
}

variable "viz_prometheus_enabled" {
  description = "Deploy Viz's built-in Prometheus instance. Set to false when using an external Prometheus."
  type        = bool
  default     = false # Disabled: use existing kube-prometheus-stack
}

variable "external_prometheus_url" {
  description = "URL of the external Prometheus instance for Viz metrics (used when viz_prometheus_enabled=false)."
  type        = string
  default     = "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"
}

variable "viz_retention_period" {
  description = "Prometheus data retention period for Viz's built-in Prometheus (only used when viz_prometheus_enabled=true)."
  type        = string
  default     = "6h"
}

#------------------------------------------------------------------------------
# Jaeger (Distributed Tracing - Optional)
#------------------------------------------------------------------------------

variable "enable_jaeger" {
  description = "Deploy the Linkerd Jaeger extension for distributed tracing. Requires existing Jaeger or OpenTelemetry backend."
  type        = bool
  default     = false
}

variable "linkerd_jaeger_chart_version" {
  description = "Linkerd Jaeger Helm chart version. Must match the control-plane version channel."
  type        = string
  default     = "30.12.11" # linkerd-jaeger chart for stable-2.16.x
}

variable "jaeger_namespace" {
  description = "Kubernetes namespace for the Linkerd Jaeger extension."
  type        = string
  default     = "linkerd-jaeger"
}

variable "collector_backend_addr" {
  description = "OpenTelemetry / Jaeger collector address for span export (used when enable_jaeger=true)."
  type        = string
  default     = "otel-collector.monitoring.svc.cluster.local:4317"
}

#------------------------------------------------------------------------------
# Proxy Injection
#------------------------------------------------------------------------------

variable "proxy_inject_namespaces" {
  description = "List of namespaces to annotate for automatic Linkerd proxy injection (opt-in)."
  type        = list(string)
  default     = []
}

#------------------------------------------------------------------------------
# CNI Plugin
#------------------------------------------------------------------------------

variable "cni_enabled" {
  description = "Enable Linkerd CNI plugin (DaemonSet). Eliminates need for NET_ADMIN in init containers, allowing PSA restricted in all namespaces."
  type        = bool
  default     = false
}

variable "linkerd_cni_version" {
  description = "Helm chart version for linkerd2-cni"
  type        = string
  default     = "30.12.2" # Compatible with Linkerd stable-2.14.x
}

#------------------------------------------------------------------------------
# Grafana Dashboards
#------------------------------------------------------------------------------

variable "enable_grafana_dashboards" {
  description = <<-EOT
    Deploy Linkerd Grafana dashboards into the monitoring namespace as a
    ConfigMap (auto-discovered by kube-prometheus-stack sidecar).

    Requires dashboard JSON files to be present under modules/linkerd/dashboards/.
    Download them once from the official Linkerd repo before enabling:

      curl -sL https://raw.githubusercontent.com/linkerd/linkerd2/stable-2.16.0/grafana/dashboards/top-line.json \
        -o modules/linkerd/dashboards/linkerd-top-line.json

    Only takes effect when enable_viz=true.
  EOT
  type        = bool
  default     = false
}

variable "grafana_dashboard_namespace" {
  description = "Kubernetes namespace where Grafana dashboards ConfigMap is deployed (must match kube-prometheus-stack namespace)."
  type        = string
  default     = "monitoring"
}
