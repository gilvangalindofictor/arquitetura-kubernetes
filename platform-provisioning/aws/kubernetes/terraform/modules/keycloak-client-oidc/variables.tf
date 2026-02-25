# =============================================================================
# Reusable OIDC Client Module — Variables
# =============================================================================

# -----------------------------------------------------------------------------
# Required inputs
# -----------------------------------------------------------------------------

variable "realm_id" {
  description = "Keycloak realm ID (UUID or realm name). Typically: keycloak_realm.platform.id"
  type        = string
}

variable "client_id" {
  description = "OIDC client ID string (e.g. 'myapp'). Must be unique within the realm."
  type        = string
}

variable "client_name" {
  description = "Human-readable display name for the client in the Keycloak admin console."
  type        = string
}

variable "redirect_uris" {
  description = "List of valid redirect URIs for the Authorization Code Flow callback. Must include the app's OAuth callback URL."
  type        = list(string)
}

variable "web_origins" {
  description = "List of allowed CORS origins. Typically the app's base URL without a trailing slash."
  type        = list(string)
}

# -----------------------------------------------------------------------------
# Optional inputs (sensible defaults)
# -----------------------------------------------------------------------------

variable "description" {
  description = "Optional description for the client in the Keycloak admin console."
  type        = string
  default     = ""
}

variable "enable_pkce" {
  description = "Enable PKCE (Proof Key for Code Exchange) with S256 method. Set true for all modern browser-based apps that support it. Set false only for legacy apps (e.g. ArgoCD < v2.12)."
  type        = bool
  default     = true
}

variable "root_url" {
  description = "Root URL for the application. Used by Keycloak admin console for relative URI resolution. Defaults to first web_origin if not set."
  type        = string
  default     = ""
}

variable "base_url" {
  description = "Default URL to use when the auth server needs to redirect or link back to the client. Defaults to root_url if not set."
  type        = string
  default     = ""
}

variable "backchannel_logout_url" {
  description = "Optional backchannel logout URL. Leave empty to disable backchannel logout."
  type        = string
  default     = ""
}

variable "backchannel_logout_session_required" {
  description = "Whether the client requires session ID in backchannel logout token. Only relevant when backchannel_logout_url is set."
  type        = bool
  default     = true
}

variable "standard_flow_enabled" {
  description = "Enable Authorization Code Flow (standard browser-based SSO). Should be true for all web applications."
  type        = bool
  default     = true
}

variable "direct_access_grants_enabled" {
  description = "Enable Resource Owner Password Credentials grant. Disabled by default (security risk). Only enable for legacy integrations."
  type        = bool
  default     = false
}

variable "service_accounts_enabled" {
  description = "Enable Service Accounts (Client Credentials grant). Disabled by default. Enable for machine-to-machine clients."
  type        = bool
  default     = false
}
