// Módulo Subnets - Engenharia Reversa
variable "vpc_id" { type = string }
variable "subnets" {
  type = list(object({
    cidr_block        = string
    availability_zone = string
    map_public_ip     = bool
    name              = string
  }))
}

resource "aws_subnet" "subnets" {
  for_each = { for idx, subnet in var.subnets : idx => subnet }

  vpc_id                  = var.vpc_id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = each.value.map_public_ip

  tags = {
    Name = each.value.name
  }
}

output "subnet_ids" { value = { for k, v in aws_subnet.subnets : k => v.id } }
