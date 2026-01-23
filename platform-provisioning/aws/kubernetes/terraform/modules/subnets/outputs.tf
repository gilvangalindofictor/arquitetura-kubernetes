output "public_subnet_ids" {
  value = [for k, v in aws_subnet.subnets : v.id if var.subnets[k].map_public_ip]
}

output "private_subnet_ids" {
  value = [for k, v in aws_subnet.subnets : v.id if !var.subnets[k].map_public_ip]
}
