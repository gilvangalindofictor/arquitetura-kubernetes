# -----------------------------------------------------------------------------
# VPN Site-to-Site Module
# Fase 7: FortiGate IPsec VPN connection to AWS VPC
#
# Architecture:
#   1. Customer Gateway: represents the FortiGate on-premises firewall
#   2. VPN Gateway (VGW): AWS-side termination point attached to VPC
#   3. VPN Connection: IPsec tunnel(s) between Customer GW and VPN GW
#   4. Static Routes: on-premises CIDRs routed through the VPN tunnel
#   5. Route Propagation: VPN routes propagated to specified route tables
#
# Security:
#   - IKEv2 with AES-256 encryption and SHA2-256 integrity (default)
#   - DH Groups 14/20/21 for key exchange (NIST recommended)
#   - Static routes (no BGP) for simpler FortiGate configuration
#   - Dual tunnel for HA (AWS manages failover automatically)
#
# Post-apply steps:
#   1. Download VPN configuration from AWS Console (FortiGate template)
#   2. Configure FortiGate with tunnel IPs and pre-shared keys from outputs
#   3. Verify tunnel status: aws ec2 describe-vpn-connections --filters Name=vpn-connection-id,Values=<id>
#   4. Test connectivity: ping from EKS pod to on-premises host
# -----------------------------------------------------------------------------

# --- Customer Gateway: FortiGate firewall ---
resource "aws_customer_gateway" "fortigate" {
  bgp_asn    = var.customer_gateway_asn
  ip_address = var.customer_gateway_ip
  type       = "ipsec.1"

  tags = merge(var.tags, {
    Name = "fortigate-customer-gateway"
  })
}

# --- VPN Gateway: AWS-side VPN termination ---
resource "aws_vpn_gateway" "main" {
  vpc_id = var.vpc_id

  tags = merge(var.tags, {
    Name = "k8s-platform-vpn-gateway"
  })
}

# --- VPN Connection: IPsec tunnel between FortiGate and AWS ---
resource "aws_vpn_connection" "fortigate" {
  customer_gateway_id = aws_customer_gateway.fortigate.id
  vpn_gateway_id      = aws_vpn_gateway.main.id
  type                = "ipsec.1"
  static_routes_only  = var.static_routes_only

  # Tunnel 1 — Phase 1 (IKE)
  tunnel1_ike_versions                 = var.tunnel1_ike_versions
  tunnel1_phase1_dh_group_numbers      = var.tunnel1_phase1_dh_group_numbers
  tunnel1_phase1_encryption_algorithms = var.tunnel1_phase1_encryption_algorithms
  tunnel1_phase1_integrity_algorithms  = var.tunnel1_phase1_integrity_algorithms

  # Tunnel 1 — Phase 2 (IPsec)
  tunnel1_phase2_dh_group_numbers      = var.tunnel1_phase2_dh_group_numbers
  tunnel1_phase2_encryption_algorithms = var.tunnel1_phase2_encryption_algorithms
  tunnel1_phase2_integrity_algorithms  = var.tunnel1_phase2_integrity_algorithms

  # Tunnel 2 — Phase 1 (IKE)
  tunnel2_ike_versions                 = var.tunnel2_ike_versions
  tunnel2_phase1_dh_group_numbers      = var.tunnel2_phase1_dh_group_numbers
  tunnel2_phase1_encryption_algorithms = var.tunnel2_phase1_encryption_algorithms
  tunnel2_phase1_integrity_algorithms  = var.tunnel2_phase1_integrity_algorithms

  # Tunnel 2 — Phase 2 (IPsec)
  tunnel2_phase2_dh_group_numbers      = var.tunnel2_phase2_dh_group_numbers
  tunnel2_phase2_encryption_algorithms = var.tunnel2_phase2_encryption_algorithms
  tunnel2_phase2_integrity_algorithms  = var.tunnel2_phase2_integrity_algorithms

  tags = merge(var.tags, {
    Name = "fortigate-vpn-connection"
  })
}

# --- Static VPN Routes: on-premises CIDRs ---
resource "aws_vpn_connection_route" "routes" {
  for_each = toset(var.destination_cidrs)

  destination_cidr_block = each.value
  vpn_connection_id      = aws_vpn_connection.fortigate.id
}

# --- Route Propagation: propagate VPN routes to private route tables ---
resource "aws_vpn_gateway_route_propagation" "main" {
  for_each = toset(var.route_table_ids)

  vpn_gateway_id = aws_vpn_gateway.main.id
  route_table_id = each.value
}
