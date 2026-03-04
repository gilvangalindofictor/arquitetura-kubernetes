# =============================================================================
# VPC DR Module — Outputs
# GAP-012: Disaster Recovery Multi-Region (Phase 2)
# =============================================================================

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the DR VPC in us-west-2. Required input for the rds-replica module."
  value       = aws_vpc.dr.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the DR VPC (10.1.0.0/16)."
  value       = aws_vpc.dr.cidr_block
}

output "vpc_arn" {
  description = "ARN of the DR VPC."
  value       = aws_vpc.dr.arn
}

# ---------------------------------------------------------------------------
# Subnets
# ---------------------------------------------------------------------------

output "private_subnet_ids" {
  description = "List of private subnet IDs in the DR region (AZ-a and AZ-b). Used by DB subnet group and future EKS DR node groups."
  value = [
    aws_subnet.rds_a.id,
    aws_subnet.rds_b.id,
  ]
}

output "rds_subnet_id_az_a" {
  description = "Private subnet ID in the first AZ of the DR region (us-west-2a)."
  value       = aws_subnet.rds_a.id
}

output "rds_subnet_id_az_b" {
  description = "Private subnet ID in the second AZ of the DR region (us-west-2b)."
  value       = aws_subnet.rds_b.id
}

# ---------------------------------------------------------------------------
# RDS
# ---------------------------------------------------------------------------

output "db_subnet_group_name" {
  description = "Name of the RDS DB subnet group in the DR region. Pass this to the rds-replica module as 'db_subnet_group_name'."
  value       = aws_db_subnet_group.dr.name
}

output "db_subnet_group_arn" {
  description = "ARN of the RDS DB subnet group in the DR region."
  value       = aws_db_subnet_group.dr.arn
}

output "rds_security_group_id" {
  description = "Security group ID for RDS DR replica. Allows PostgreSQL (5432) from within the DR VPC CIDR only."
  value       = aws_security_group.rds_dr.id
}

# ---------------------------------------------------------------------------
# Route Tables
# ---------------------------------------------------------------------------

output "private_route_table_id" {
  description = "Route table ID for the private (data) tier in the DR VPC."
  value       = aws_route_table.private_dr.id
}
