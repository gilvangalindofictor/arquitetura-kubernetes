// Módulo Route Tables - Engenharia Reversa
variable "vpc_id" { type = string }
variable "route_tables" {
  type = list(object({
    name = string
    routes = list(object({
      cidr_block     = string
      gateway_id     = optional(string)
      nat_gateway_id = optional(string)
    }))
    subnet_ids = list(string)
  }))
}

resource "aws_route_table" "rtb" {
  for_each = { for idx, rtb in var.route_tables : idx => rtb }
  vpc_id   = var.vpc_id

  dynamic "route" {
    for_each = each.value.routes
    content {
      cidr_block     = route.value.cidr_block
      gateway_id     = route.value.gateway_id
      nat_gateway_id = route.value.nat_gateway_id
    }
  }

  tags = {
    Name = each.value.name
  }
}

resource "aws_route_table_association" "assoc" {
  for_each = merge(
    { for idx, subnet_id in var.route_tables[0].subnet_ids : "${0}-${subnet_id}" => { rtb_idx = 0, subnet_id = subnet_id } },
    { for idx, subnet_id in var.route_tables[1].subnet_ids : "${1}-${subnet_id}" => { rtb_idx = 1, subnet_id = subnet_id } },
    { for idx, subnet_id in var.route_tables[2].subnet_ids : "${2}-${subnet_id}" => { rtb_idx = 2, subnet_id = subnet_id } }
  )

  subnet_id      = each.value.subnet_id
  route_table_id = aws_route_table.rtb[each.value.rtb_idx].id
}

output "route_table_ids" { value = { for k, v in aws_route_table.rtb : k => v.id } }
