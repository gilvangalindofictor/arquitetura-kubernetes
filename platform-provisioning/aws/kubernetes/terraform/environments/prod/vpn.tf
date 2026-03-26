# =============================================================================
# VPN Site-to-Site — FortiGate (Fase 7)
# IPsec VPN connection between AWS VPC and on-premises FortiGate firewall
#
# Status: COMENTADO — Pronto para descomentar quando IP do FortiGate disponivel
#
# Pre-requisitos para ativar:
#   1. IP publico do FortiGate firewall (customer_gateway_ip)
#   2. BGP ASN do FortiGate (default 65000 se nao especificado)
#   3. CIDRs da rede do escritorio (destination_cidrs)
#   4. Descomentar o bloco abaixo
#   5. terraform plan + apply
#
# Pos-apply:
#   1. Baixar configuracao VPN do Console AWS (template FortiGate)
#   2. Configurar FortiGate com tunnel IPs e pre-shared keys dos outputs
#   3. Verificar status: aws ec2 describe-vpn-connections
#   4. Testar conectividade: ping de pod EKS para host on-premises
#
# Custo estimado: ~$36/month (VPN connection) + data transfer
#
# Seguranca:
#   - IKEv2 com AES-256 e SHA2-256
#   - DH Groups 14/20/21 (NIST recommended)
#   - Dual tunnel para HA (failover automatico AWS)
# =============================================================================

# --- Route Table data sources (necessarios para route propagation) ---
# Descomentados para disponibilizar os IDs quando o modulo VPN for ativado.
# Estes data sources NAO criam recursos, apenas consultam.

data "aws_route_table" "private_us_east_1a" {
  vpc_id = var.vpc_id
  filter {
    name   = "association.subnet-id"
    values = [data.aws_subnets.private.ids[0]]
  }
}

data "aws_route_table" "private_us_east_1b" {
  vpc_id = var.vpc_id
  filter {
    name   = "association.subnet-id"
    values = [data.aws_subnets.private.ids[1]]
  }
}

# --- VPN Module (COMENTADO — descomentar quando IP FortiGate disponivel) ---
#
# module "vpn_fortigate" {
#   source = "../../modules/vpn-site-to-site"
#
#   customer_gateway_ip  = "X.X.X.X"  # TODO: IP publico do FortiGate
#   customer_gateway_asn = 65000       # TODO: Confirmar ASN do FortiGate
#   vpc_id               = var.vpc_id
#
#   route_table_ids = [
#     data.aws_route_table.private_us_east_1a.id,
#     data.aws_route_table.private_us_east_1b.id,
#   ]
#
#   destination_cidrs = ["10.100.0.0/16"] # TODO: CIDR exato da rede do escritorio
#
#   # IPsec parameters (FortiGate-compatible defaults)
#   static_routes_only = true
#
#   tags = local.common_tags
# }

# --- Outputs (COMENTADOS — descomentar junto com o module) ---
#
# output "vpn_connection_id" {
#   description = "VPN Connection ID for FortiGate configuration"
#   value       = module.vpn_fortigate.vpn_connection_id
# }
#
# output "vpn_tunnel1_address" {
#   description = "AWS public IP for Tunnel 1 (configure on FortiGate)"
#   value       = module.vpn_fortigate.tunnel1_address
# }
#
# output "vpn_tunnel2_address" {
#   description = "AWS public IP for Tunnel 2 (configure on FortiGate)"
#   value       = module.vpn_fortigate.tunnel2_address
# }
#
# output "vpn_tunnel1_preshared_key" {
#   description = "Pre-shared key for Tunnel 1 (SENSITIVE)"
#   value       = module.vpn_fortigate.tunnel1_preshared_key
#   sensitive   = true
# }
#
# output "vpn_tunnel2_preshared_key" {
#   description = "Pre-shared key for Tunnel 2 (SENSITIVE)"
#   value       = module.vpn_fortigate.tunnel2_preshared_key
#   sensitive   = true
# }
