# -----------------------------------------------------------------------------
# VPN Site-to-Site Module - Variables
# Fase 7: FortiGate VPN connection to AWS VPC
# -----------------------------------------------------------------------------

variable "customer_gateway_ip" {
  description = "Public IP address of the FortiGate firewall (on-premises). NO default -- must be provided when IP is available."
  type        = string

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.customer_gateway_ip))
    error_message = "customer_gateway_ip must be a valid IPv4 address."
  }
}

variable "customer_gateway_asn" {
  description = "BGP ASN of the FortiGate firewall (default 65000 for private ASN)"
  type        = number
  default     = 65000

  validation {
    condition     = var.customer_gateway_asn >= 1 && var.customer_gateway_asn <= 4294967295
    error_message = "customer_gateway_asn must be a valid BGP ASN (1 to 4294967295)."
  }
}

variable "vpc_id" {
  description = "VPC ID to attach the VPN Gateway"
  type        = string
}

variable "route_table_ids" {
  description = "Route table IDs to enable VPN gateway route propagation"
  type        = list(string)
}

variable "destination_cidrs" {
  description = "On-premises CIDR blocks to route through the VPN tunnel"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]

  validation {
    condition     = length(var.destination_cidrs) > 0
    error_message = "At least one destination CIDR must be provided."
  }
}

variable "static_routes_only" {
  description = "Use static routes (true) or BGP dynamic routing (false). FortiGate default: static."
  type        = bool
  default     = true
}

variable "tunnel1_ike_versions" {
  description = "IKE versions for Tunnel 1 (ikev1, ikev2)"
  type        = list(string)
  default     = ["ikev2"]
}

variable "tunnel2_ike_versions" {
  description = "IKE versions for Tunnel 2 (ikev1, ikev2)"
  type        = list(string)
  default     = ["ikev2"]
}

variable "tunnel1_phase1_dh_group_numbers" {
  description = "Phase 1 DH group numbers for Tunnel 1"
  type        = list(number)
  default     = [14, 20, 21] # DH groups recommended for FortiGate
}

variable "tunnel2_phase1_dh_group_numbers" {
  description = "Phase 1 DH group numbers for Tunnel 2"
  type        = list(number)
  default     = [14, 20, 21]
}

variable "tunnel1_phase1_encryption_algorithms" {
  description = "Phase 1 encryption algorithms for Tunnel 1"
  type        = list(string)
  default     = ["AES256"]
}

variable "tunnel2_phase1_encryption_algorithms" {
  description = "Phase 1 encryption algorithms for Tunnel 2"
  type        = list(string)
  default     = ["AES256"]
}

variable "tunnel1_phase1_integrity_algorithms" {
  description = "Phase 1 integrity algorithms for Tunnel 1"
  type        = list(string)
  default     = ["SHA2-256"]
}

variable "tunnel2_phase1_integrity_algorithms" {
  description = "Phase 1 integrity algorithms for Tunnel 2"
  type        = list(string)
  default     = ["SHA2-256"]
}

variable "tunnel1_phase2_dh_group_numbers" {
  description = "Phase 2 DH group numbers for Tunnel 1"
  type        = list(number)
  default     = [14, 20, 21]
}

variable "tunnel2_phase2_dh_group_numbers" {
  description = "Phase 2 DH group numbers for Tunnel 2"
  type        = list(number)
  default     = [14, 20, 21]
}

variable "tunnel1_phase2_encryption_algorithms" {
  description = "Phase 2 encryption algorithms for Tunnel 1"
  type        = list(string)
  default     = ["AES256"]
}

variable "tunnel2_phase2_encryption_algorithms" {
  description = "Phase 2 encryption algorithms for Tunnel 2"
  type        = list(string)
  default     = ["AES256"]
}

variable "tunnel1_phase2_integrity_algorithms" {
  description = "Phase 2 integrity algorithms for Tunnel 1"
  type        = list(string)
  default     = ["SHA2-256"]
}

variable "tunnel2_phase2_integrity_algorithms" {
  description = "Phase 2 integrity algorithms for Tunnel 2"
  type        = list(string)
  default     = ["SHA2-256"]
}

variable "tags" {
  description = "Tags applied to all VPN resources"
  type        = map(string)
  default     = {}
}
