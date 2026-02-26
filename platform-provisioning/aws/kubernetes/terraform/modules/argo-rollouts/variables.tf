# -----------------------------------------------------------------------------
# Argo Rollouts Module — Variables
# Demand: CICD-005
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = "EKS cluster name (used for tagging and naming)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for Argo Rollouts (co-located with ArgoCD)"
  type        = string
  default     = "argocd"
}

variable "chart_version" {
  description = "Argo Rollouts Helm chart version"
  type        = string
  default     = "2.35.0"
}

variable "controller_replicas" {
  description = "Number of Argo Rollouts controller replicas (HA)"
  type        = number
  default     = 2
}

variable "metrics_enabled" {
  description = "Enable Prometheus metrics endpoint and ServiceMonitor"
  type        = bool
  default     = true
}

variable "prometheus_url" {
  description = "Prometheus URL for AnalysisRun metric queries"
  type        = string
  default     = "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"
}

variable "dashboard_enabled" {
  description = "Enable Argo Rollouts Dashboard (read-only UI)"
  type        = bool
  default     = true
}

variable "dashboard_port" {
  description = "Port for Argo Rollouts Dashboard service"
  type        = number
  default     = 3100
}

variable "metrics_port" {
  description = "Port for Argo Rollouts metrics endpoint"
  type        = number
  default     = 8090
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
