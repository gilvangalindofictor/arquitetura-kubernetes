# -----------------------------------------------------------------------------
# VPN Site-to-Site Module - Outputs
# Fase 7: FortiGate VPN connection to AWS VPC
# -----------------------------------------------------------------------------

output "customer_gateway_id" {
  description = "Customer Gateway ID (FortiGate)"
  value       = aws_customer_gateway.fortigate.id
}

output "vpn_gateway_id" {
  description = "VPN Gateway ID (AWS-side)"
  value       = aws_vpn_gateway.main.id
}

output "vpn_connection_id" {
  description = "VPN Connection ID"
  value       = aws_vpn_connection.fortigate.id
}

# --- Tunnel 1 ---
output "tunnel1_address" {
  description = "AWS-side public IP for Tunnel 1 (configure on FortiGate as remote gateway)"
  value       = aws_vpn_connection.fortigate.tunnel1_address
}

output "tunnel1_cgw_inside_address" {
  description = "Customer-side (FortiGate) inside IP for Tunnel 1"
  value       = aws_vpn_connection.fortigate.tunnel1_cgw_inside_address
}

output "tunnel1_vgw_inside_address" {
  description = "AWS-side inside IP for Tunnel 1"
  value       = aws_vpn_connection.fortigate.tunnel1_vgw_inside_address
}

output "tunnel1_preshared_key" {
  description = "Pre-shared key for Tunnel 1 (SENSITIVE -- configure on FortiGate)"
  value       = aws_vpn_connection.fortigate.tunnel1_preshared_key
  sensitive   = true
}

# --- Tunnel 2 ---
output "tunnel2_address" {
  description = "AWS-side public IP for Tunnel 2 (configure on FortiGate as remote gateway)"
  value       = aws_vpn_connection.fortigate.tunnel2_address
}

output "tunnel2_cgw_inside_address" {
  description = "Customer-side (FortiGate) inside IP for Tunnel 2"
  value       = aws_vpn_connection.fortigate.tunnel2_cgw_inside_address
}

output "tunnel2_vgw_inside_address" {
  description = "AWS-side inside IP for Tunnel 2"
  value       = aws_vpn_connection.fortigate.tunnel2_vgw_inside_address
}

output "tunnel2_preshared_key" {
  description = "Pre-shared key for Tunnel 2 (SENSITIVE -- configure on FortiGate)"
  value       = aws_vpn_connection.fortigate.tunnel2_preshared_key
  sensitive   = true
}

# --- General ---
output "vpn_connection_type" {
  description = "VPN connection type"
  value       = aws_vpn_connection.fortigate.type
}

output "static_routes" {
  description = "List of on-premises CIDRs routed through the VPN"
  value       = var.destination_cidrs
}
