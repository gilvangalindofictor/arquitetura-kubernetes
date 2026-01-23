// Módulo NAT Gateways - Engenharia Reversa
variable "nat_gateways" {
  type = list(object({
    subnet_id = string
    name      = string
  }))
}

resource "aws_eip" "nat_eip" {
  for_each = { for idx, ngw in var.nat_gateways : idx => ngw }
  domain   = "vpc"
}

resource "aws_nat_gateway" "nat" {
  for_each      = { for idx, ngw in var.nat_gateways : idx => ngw }
  allocation_id = aws_eip.nat_eip[each.key].id
  subnet_id     = each.value.subnet_id

  tags = {
    Name = each.value.name
  }
}

output "nat_gateway_ids" { value = { for k, v in aws_nat_gateway.nat : k => v.id } }
output "eip_public_ips" { value = { for k, v in aws_eip.nat_eip : k => v.public_ip } }
