# =============================================================================
# DR Multi-Region Module — Outputs
# GAP-012 Phase 2: VPC + RDS Read Replica in us-west-2
# =============================================================================

# ---------------------------------------------------------------------------
# DR VPC
# ---------------------------------------------------------------------------

output "dr_vpc_id" {
  description = "ID of the DR VPC in us-west-2"
  value       = aws_vpc.dr.id
}

output "dr_vpc_cidr" {
  description = "CIDR block of the DR VPC"
  value       = aws_vpc.dr.cidr_block
}

output "dr_public_subnet_ids" {
  description = "List of public subnet IDs in the DR VPC"
  value       = [for s in aws_subnet.dr_public : s.id]
}

output "dr_private_subnet_ids" {
  description = "List of private subnet IDs in the DR VPC (used for RDS replica and future EKS)"
  value       = [for s in aws_subnet.dr_private : s.id]
}

output "dr_public_subnet_cidrs" {
  description = "List of public subnet CIDR blocks in the DR VPC"
  value       = [for s in aws_subnet.dr_public : s.cidr_block]
}

output "dr_private_subnet_cidrs" {
  description = "List of private subnet CIDR blocks in the DR VPC"
  value       = [for s in aws_subnet.dr_private : s.cidr_block]
}

# ---------------------------------------------------------------------------
# Internet Gateway
# ---------------------------------------------------------------------------

output "dr_internet_gateway_id" {
  description = "ID of the Internet Gateway in the DR VPC"
  value       = aws_internet_gateway.dr.id
}

# ---------------------------------------------------------------------------
# NAT Gateway (when enabled)
# ---------------------------------------------------------------------------

output "dr_nat_gateway_id" {
  description = "ID of the NAT Gateway in the DR VPC. Empty when enable_nat_gateway = false."
  value       = var.enable_nat_gateway ? aws_nat_gateway.dr[0].id : ""
}

output "dr_nat_eip_public_ip" {
  description = "Public IP of the NAT Gateway EIP. Empty when enable_nat_gateway = false."
  value       = var.enable_nat_gateway ? aws_eip.dr_nat[0].public_ip : ""
}

# ---------------------------------------------------------------------------
# VPC Peering
# ---------------------------------------------------------------------------

output "vpc_peering_connection_id" {
  description = "ID of the VPC peering connection between primary and DR VPCs. Empty when peering disabled."
  value       = var.enable_vpc_peering ? aws_vpc_peering_connection.primary_to_dr[0].id : ""
}

output "vpc_peering_status" {
  description = "Status of the VPC peering connection. Empty when peering disabled."
  value       = var.enable_vpc_peering ? aws_vpc_peering_connection_accepter.dr_accept[0].status : ""
}

# ---------------------------------------------------------------------------
# RDS Read Replica
# ---------------------------------------------------------------------------

output "replica_instance_id" {
  description = "RDS instance identifier of the DR read replica. Use in 'aws rds promote-read-replica --db-instance-identifier' during failover."
  value       = var.enable_rds_replica ? aws_db_instance.dr_replica[0].identifier : ""
}

output "replica_endpoint" {
  description = "Connection endpoint of the DR read replica (host:port). Available for read-only queries or after promotion."
  value       = var.enable_rds_replica ? aws_db_instance.dr_replica[0].endpoint : ""
}

output "replica_address" {
  description = "Hostname of the DR read replica (without port)"
  value       = var.enable_rds_replica ? aws_db_instance.dr_replica[0].address : ""
}

output "replica_port" {
  description = "Port of the DR read replica (5432 for PostgreSQL)"
  value       = var.enable_rds_replica ? aws_db_instance.dr_replica[0].port : 0
}

output "replica_arn" {
  description = "ARN of the DR read replica RDS instance. Required as source ARN when promoting."
  value       = var.enable_rds_replica ? aws_db_instance.dr_replica[0].arn : ""
}

output "replica_security_group_id" {
  description = "Security group ID attached to the DR read replica"
  value       = var.enable_rds_replica ? aws_security_group.dr_replica_rds[0].id : ""
}

output "replica_subnet_group_name" {
  description = "DB subnet group name used by the DR read replica"
  value       = var.enable_rds_replica ? aws_db_subnet_group.dr_replica[0].name : ""
}

# ---------------------------------------------------------------------------
# Monitoring
# ---------------------------------------------------------------------------

output "sns_topic_arn" {
  description = "ARN of the SNS topic for DR alerts. Empty when create_sns_topic = false or RDS replica disabled."
  value       = local.sns_topic_arn
}

output "cloudwatch_alarm_arns" {
  description = "Map of CloudWatch alarm ARNs. Empty when alarms disabled."
  value = var.enable_cloudwatch_alarms && var.enable_rds_replica ? {
    replication_lag     = aws_cloudwatch_metric_alarm.dr_replication_lag[0].arn
    storage_space_low   = aws_cloudwatch_metric_alarm.dr_storage_low[0].arn
    replica_unavailable = aws_cloudwatch_metric_alarm.dr_replica_unavailable[0].arn
  } : {}
}

# ---------------------------------------------------------------------------
# Summary (for operational dashboards)
# ---------------------------------------------------------------------------

output "dr_summary" {
  description = "Summary of all DR resources created by this module"
  value = {
    dr_region              = var.dr_region
    dr_vpc_id              = aws_vpc.dr.id
    dr_vpc_cidr            = aws_vpc.dr.cidr_block
    public_subnets         = length(aws_subnet.dr_public)
    private_subnets        = length(aws_subnet.dr_private)
    nat_gateway_enabled    = var.enable_nat_gateway
    vpc_peering_enabled    = var.enable_vpc_peering
    rds_replica_enabled    = var.enable_rds_replica
    rds_replica_identifier = var.enable_rds_replica ? aws_db_instance.dr_replica[0].identifier : "disabled"
    cloudwatch_alarms      = var.enable_cloudwatch_alarms ? 3 : 0
  }
}
