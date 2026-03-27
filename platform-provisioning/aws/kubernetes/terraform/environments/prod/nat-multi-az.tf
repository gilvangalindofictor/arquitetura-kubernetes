# =============================================================================
# GAP-CONF-022 (P2): NAT Gateway Multi-AZ — Producao
# =============================================================================
# Problema: NAT Gateway Single-AZ. Se a AZ do NAT cair, todos os pods perdem
#   acesso a internet (ECR pulls, DNS externo, webhooks, API calls).
#
# Solucao: Segundo NAT Gateway em AZ diferente (us-east-1b).
#   - Cada AZ route table aponta para seu NAT Gateway local
#   - Elimina cross-AZ dependency e single point of failure
#   - Staging permanece com 1 NAT (custo aceitavel para non-prod)
#
# Custo: ~$32/mes (NAT Gateway) + ~$0.045/GB data processing
#   Total estimado: ~$40-50/mes adicional (baseado no trafego atual)
#
# IMPORTANTE:
#   - O NAT Gateway existente NÃO e gerenciado por este TF state (criado em Marco0)
#   - Este arquivo cria APENAS o segundo NAT Gateway
#   - Apos apply, atualizar route table da subnet us-east-1b para usar o novo NAT
#
# Pre-requisitos:
#   1. Identificar public subnet em us-east-1b para o NAT Gateway
#   2. Confirmar route table association da private subnet us-east-1b
#
# Ref: https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html
# =============================================================================

# --- Data: Public Subnets (para hospedar o NAT Gateway) ---
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  filter {
    name   = "tag:Name"
    values = ["*public*"]
  }
}

# --- Data: Obter detalhes das subnets publicas para mapear AZs ---
data "aws_subnet" "public_details" {
  for_each = toset(data.aws_subnets.public.ids)
  id       = each.value
}

# --- Locals: Mapear subnets por AZ ---
locals {
  # Identificar subnet publica em us-east-1b para o segundo NAT
  public_subnet_az_map = {
    for id, subnet in data.aws_subnet.public_details :
    subnet.availability_zone => subnet.id
  }

  # AZ do segundo NAT (us-east-1b — complementar ao existente em us-east-1a)
  nat_secondary_az        = "us-east-1b"
  nat_secondary_subnet_id = lookup(local.public_subnet_az_map, local.nat_secondary_az, "")
}

# --- EIP para o segundo NAT Gateway ---
resource "aws_eip" "nat_secondary" {
  count  = local.nat_secondary_subnet_id != "" ? 1 : 0
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "k8s-platform-prod-nat-eip-${local.nat_secondary_az}"
    Gap  = "GAP-CONF-022"
  })
}

# --- Segundo NAT Gateway (us-east-1b) ---
resource "aws_nat_gateway" "secondary" {
  count         = local.nat_secondary_subnet_id != "" ? 1 : 0
  allocation_id = aws_eip.nat_secondary[0].id
  subnet_id     = local.nat_secondary_subnet_id

  tags = merge(local.common_tags, {
    Name = "k8s-platform-prod-nat-${local.nat_secondary_az}"
    Gap  = "GAP-CONF-022"
  })

  depends_on = [aws_eip.nat_secondary]
}

# =============================================================================
# POS-APPLY — Acao manual necessaria:
#
# 1. Identificar route table da private subnet us-east-1b:
#    aws ec2 describe-route-tables \
#      --filters "Name=association.subnet-id,Values=subnet-0472ab28726cdf745" \
#      --query 'RouteTables[].RouteTableId' --output text
#
# 2. Atualizar rota default (0.0.0.0/0) para apontar ao novo NAT:
#    aws ec2 replace-route \
#      --route-table-id <ROUTE_TABLE_ID> \
#      --destination-cidr-block 0.0.0.0/0 \
#      --nat-gateway-id <NEW_NAT_GW_ID>
#
# 3. Verificar conectividade:
#    kubectl run test-nat --rm -it --image=busybox -- wget -qO- ifconfig.me
#
# TODO: Codificar route table update no TF (requer import da route table existente)
# =============================================================================

output "nat_secondary_id" {
  description = "ID do segundo NAT Gateway (us-east-1b)"
  value       = length(aws_nat_gateway.secondary) > 0 ? aws_nat_gateway.secondary[0].id : "not-created"
}

output "nat_secondary_eip" {
  description = "IP publico do segundo NAT Gateway"
  value       = length(aws_eip.nat_secondary) > 0 ? aws_eip.nat_secondary[0].public_ip : "not-created"
}
