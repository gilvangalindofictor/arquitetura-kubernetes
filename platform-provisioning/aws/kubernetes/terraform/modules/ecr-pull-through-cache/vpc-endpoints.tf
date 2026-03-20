#------------------------------------------------------------------------------
# VPC Endpoints — ECR API + ECR DKR
#
# Purpose: Route ECR traffic within VPC to avoid NAT Gateway latency/costs
# Type: Interface (private DNS enabled)
# Pattern: Follows existing VPC endpoints in staging/main.tf
#------------------------------------------------------------------------------

resource "aws_vpc_endpoint" "ecr_api" {
  count = var.enable_vpc_endpoints ? 1 : 0

  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type = "Interface"

  subnet_ids         = var.private_subnet_ids
  security_group_ids = var.security_group_ids

  private_dns_enabled = true

  tags = merge(var.common_tags, {
    Name        = "${var.cluster_name}-vpce-ecr-api"
    Purpose     = "ECR Pull-Through Cache API endpoint"
    ManagedBy   = "Terraform"
    Criticality = "High"
  })
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  count = var.enable_vpc_endpoints ? 1 : 0

  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type = "Interface"

  subnet_ids         = var.private_subnet_ids
  security_group_ids = var.security_group_ids

  private_dns_enabled = true

  tags = merge(var.common_tags, {
    Name        = "${var.cluster_name}-vpce-ecr-dkr"
    Purpose     = "ECR Pull-Through Cache Docker registry endpoint"
    ManagedBy   = "Terraform"
    Criticality = "High"
  })
}
