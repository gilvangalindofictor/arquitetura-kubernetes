# -----------------------------------------------------------------------------
# Linkerd mTLS Phase 2 Module - Variables
# Fase 6a: ServerPolicy enforcement for mTLS across namespaces
# GAP-011 Phase 2: BACEN BCB 85/2021 Compliance
# -----------------------------------------------------------------------------

variable "environment" {
  description = "Deployment environment (staging | prod)"
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be 'staging' or 'prod'."
  }
}

variable "mtls_namespaces" {
  description = <<-EOT
    List of namespaces where Linkerd mTLS ServerPolicy should be enforced.
    Each namespace MUST already have Linkerd proxy injection enabled
    (annotation: linkerd.io/inject=enabled) before applying this module.

    Example: ["prod-platform-argocd", "prod-platform-gitlab", "prod-platform-sonarqube", "prod-platform-harbor"]
  EOT
  type        = list(string)
  default     = []
}

variable "default_policy" {
  description = <<-EOT
    Default inbound policy for the Server resources.
    - "all-authenticated": Only allow mTLS-authenticated traffic (meshed pods)
    - "all-unauthenticated": Allow all traffic (no mTLS enforcement)
    - "cluster-authenticated": Allow mTLS from any identity in the cluster
    - "deny": Deny all traffic by default (most restrictive)

    Recommended: "all-authenticated" for production, "cluster-authenticated" for staging.
  EOT
  type        = string
  default     = "all-authenticated"

  validation {
    condition     = contains(["all-authenticated", "all-unauthenticated", "cluster-authenticated", "deny"], var.default_policy)
    error_message = "default_policy must be one of: all-authenticated, all-unauthenticated, cluster-authenticated, deny."
  }
}

variable "allow_admin_server_access" {
  description = <<-EOT
    Create an AuthorizationPolicy that allows access to admin/health ports
    from non-meshed traffic (e.g., kubelet health probes, ALB health checks).
    This prevents breaking liveness/readiness probes when enforcing mTLS.
  EOT
  type        = bool
  default     = true
}

variable "admin_ports" {
  description = "List of ports to exclude from mTLS enforcement (health checks, metrics)"
  type        = list(number)
  default     = [4191, 9990] # 4191=linkerd-admin, 9990=common admin port
}

variable "common_tags" {
  description = "Common tags applied to Kubernetes labels"
  type        = map(string)
  default     = {}
}
