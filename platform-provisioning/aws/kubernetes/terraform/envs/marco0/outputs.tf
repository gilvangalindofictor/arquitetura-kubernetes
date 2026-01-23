output "vpc_id" { value = module.vpc.vpc_id }
output "vpc_cidr" { value = module.vpc.vpc_cidr }
output "subnet_ids" { value = module.subnets.subnet_ids }
output "igw_id" { value = module.internet_gateway.igw_id }
output "nat_gateway_ids" { value = module.nat_gateways.nat_gateway_ids }
output "route_table_ids" { value = module.route_tables.route_table_ids }
