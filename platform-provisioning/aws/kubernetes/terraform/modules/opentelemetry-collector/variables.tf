variable "release_name" {
  description = "Helm release name"
  type        = string
  default     = "opentelemetry-collector"
}

variable "chart_version" {
  description = "OTel Collector Helm chart version"
  type        = string
  default     = "0.108.0"
}

variable "namespace" {
  description = "Kubernetes namespace for OTel Collector deployment"
  type        = string
  default     = "monitoring"
}

variable "observability_namespace" {
  description = "Kubernetes namespace where Tempo/Prometheus/Loki are deployed"
  type        = string
  default     = "monitoring"
}

variable "replicas" {
  description = "Number of OTel Collector replicas (HA)"
  type        = number
  default     = 2
}

variable "resources" {
  description = "Pod resource requests/limits"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "100m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "500m"
      memory = "512Mi"
    }
  }
}

variable "memory_limiter_limit_mib" {
  description = "Memory limiter limit in MiB (80% of memory.limits recommended)"
  type        = number
  default     = 400
}

variable "enable_servicemonitor" {
  description = "Enable Prometheus ServiceMonitor"
  type        = bool
  default     = true
}

variable "servicemonitor_interval" {
  description = "Prometheus scrape interval"
  type        = string
  default     = "30s"
}

variable "enable_hpa" {
  description = "Enable HPA (Performance Specialist requirement)"
  type        = bool
  default     = true
}

variable "hpa_min_replicas" {
  description = "HPA minimum replicas"
  type        = number
  default     = 2
}

variable "hpa_max_replicas" {
  description = "HPA maximum replicas"
  type        = number
  default     = 5
}

variable "hpa_target_cpu_percent" {
  description = "HPA target CPU utilization percentage"
  type        = number
  default     = 70
}

variable "enable_pdb" {
  description = "Enable PDB (Performance Specialist requirement)"
  type        = bool
  default     = true
}

variable "enable_network_policies" {
  description = "Enable Network Policies (Security Specialist requirement)"
  type        = bool
  default     = true
}
