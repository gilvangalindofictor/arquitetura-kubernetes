variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for SonarQube"
  type        = string
  default     = "sonarqube"
}

variable "sonarqube_chart_version" {
  description = "SonarQube Helm chart version"
  type        = string
  default     = "10.7.0"
}

variable "replicas" {
  description = "Number of SonarQube replicas (Community Edition: 1 only)"
  type        = number
  default     = 1
}

variable "postgresql_host" {
  description = "PostgreSQL host (RDS endpoint)"
  type        = string
}

variable "postgresql_port" {
  description = "PostgreSQL port"
  type        = number
  default     = 5432
}

variable "postgresql_database" {
  description = "PostgreSQL database name"
  type        = string
  default     = "sonarqube"
}

variable "storage_class" {
  description = "Storage class for PVC"
  type        = string
  default     = "gp2"
}

variable "pvc_size" {
  description = "PVC size for SonarQube data"
  type        = string
  default     = "20Gi"
}

variable "ingress_enabled" {
  description = "Enable ALB ingress"
  type        = bool
  default     = false
}

variable "domain" {
  description = "Domain for SonarQube (e.g., sonarqube.example.com)"
  type        = string
  default     = ""
}

variable "ingress_group_name" {
  description = "ALB Ingress group name para compartilhar ALB entre serviços"
  type        = string
  default     = ""
}

variable "enable_monitoring" {
  description = "Enable Prometheus ServiceMonitor"
  type        = bool
  default     = true
}

variable "enable_prometheus_exporter" {
  description = "Enable JMX Prometheus exporter init container (downloads JAR from Maven Central). Disable if egress/TLS issues."
  type        = bool
  default     = false # Disabled: sonarqube:10.3.0-community curl SSL timeout (exit code 28)
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

# SAML Authentication Variables
variable "saml_enabled" {
  description = "Enable SAML 2.0 authentication with Keycloak"
  type        = bool
  default     = false
}

variable "saml_application_id" {
  description = "SAML Service Provider application ID (must match Keycloak client_id)"
  type        = string
  default     = "sonarqube"
}

variable "saml_provider_id" {
  description = "SAML Identity Provider entity ID (Keycloak realm URL)"
  type        = string
  default     = ""
}

variable "saml_login_url" {
  description = "SAML SingleSignOnService Location (Keycloak SAML endpoint)"
  type        = string
  default     = ""
}

variable "saml_certificate" {
  description = "SAML Identity Provider X.509 certificate (PEM format, no headers)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "saml_user_login_attribute" {
  description = "SAML attribute name for user login mapping"
  type        = string
  default     = "login"
}

variable "saml_user_email_attribute" {
  description = "SAML attribute name for user email mapping"
  type        = string
  default     = "email"
}

variable "saml_user_name_attribute" {
  description = "SAML attribute name for user display name mapping"
  type        = string
  default     = "name"
}

variable "saml_group_attribute" {
  description = "SAML attribute name for group membership mapping"
  type        = string
  default     = "groups"
}
