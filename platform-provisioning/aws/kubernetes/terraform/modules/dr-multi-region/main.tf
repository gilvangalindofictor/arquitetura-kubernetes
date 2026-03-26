# =============================================================================
# DR Multi-Region Module — GAP-012 Phase 2
# =============================================================================
# Provisions disaster recovery infrastructure in us-west-2:
#   1. VPC with public + private subnets (mirrors primary CIDR structure)
#   2. Internet Gateway + NAT Gateway (optional) for network connectivity
#   3. Route tables for public/private traffic
#   4. VPC Peering between primary (us-east-1) and DR (us-west-2)
#   5. RDS cross-region read replica (PostgreSQL, using existing rds-replica
#      module pattern but integrated here for single-module deployment)
#   6. CloudWatch alarms for replication lag + storage monitoring
#
# Phase 1 (COMPLETE — velero-dr module):
#   - S3 Cross-Region Replication (Velero backups us-east-1 → us-west-2)
#   - Velero IRSA with cross-region S3 access
#   - CloudWatch alarms for replication failures
#
# Phase 2 (THIS MODULE):
#   - DR VPC in us-west-2 (10.1.0.0/16)
#   - RDS read replica for PostgreSQL (cross-region, async replication)
#   - VPC Peering for cross-region network connectivity
#   - Foundation for Phase 3 (EKS DR cluster)
#
# ADR Reference: ADR-090 — DR Multi-Region Strategy
# RTO target: 4h (full failover) | 10min (RDS promotion only)
# RPO target: ~0 (async replication lag < 60s)
# =============================================================================

# ---------------------------------------------------------------------------
# Data Sources
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_region" "primary" {}

# Lookup primary RDS for engine/version details (only when replica enabled)
data "aws_db_instance" "primary" {
  count                  = var.enable_rds_replica ? 1 : 0
  db_instance_identifier = var.source_db_identifier
}

# ---------------------------------------------------------------------------
# Local values
# ---------------------------------------------------------------------------

locals {
  account_id = data.aws_caller_identity.current.account_id

  common_tags = merge(var.common_tags, {
    Module    = "dr-multi-region"
    GAP       = "GAP-012"
    Phase     = "Phase-2"
    ManagedBy = "terraform"
  })

  # Private subnet CIDRs for security group rules
  dr_private_subnet_cidrs = [for s in var.dr_private_subnets : s.cidr_block]
}

# =============================================================================
# DR VPC (us-west-2)
# =============================================================================
# Mirrors the primary VPC structure but uses 10.1.0.0/16 to avoid overlap.
# Non-overlapping CIDRs are a prerequisite for VPC Peering.
# =============================================================================

resource "aws_vpc" "dr" {
  provider = aws.dr

  cidr_block           = var.dr_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name   = "${var.cluster_name}-dr-vpc"
    Region = var.dr_region
    Role   = "disaster-recovery"
  })
}

# ---------------------------------------------------------------------------
# Public Subnets — used for Internet Gateway + NAT Gateway
# ---------------------------------------------------------------------------

resource "aws_subnet" "dr_public" {
  provider = aws.dr

  for_each = { for idx, s in var.dr_public_subnets : s.name_suffix => s }

  vpc_id                  = aws_vpc.dr.id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-dr-${each.key}"
    Tier = "public"
  })
}

# ---------------------------------------------------------------------------
# Private Subnets — used for RDS replica + future EKS DR nodes
# ---------------------------------------------------------------------------

resource "aws_subnet" "dr_private" {
  provider = aws.dr

  for_each = { for idx, s in var.dr_private_subnets : s.name_suffix => s }

  vpc_id                  = aws_vpc.dr.id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-dr-${each.key}"
    Tier = "private"
  })
}

# =============================================================================
# INTERNET GATEWAY
# =============================================================================

resource "aws_internet_gateway" "dr" {
  provider = aws.dr

  vpc_id = aws_vpc.dr.id

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-dr-igw"
  })
}

# =============================================================================
# NAT GATEWAY (optional — disabled by default to save ~$32/month)
# =============================================================================
# Enable when:
#   - EKS DR cluster needs outbound internet from private subnets
#   - RDS replica needs to download extensions from internet
# For Phase 2 (RDS-only), NAT is NOT required.
# =============================================================================

resource "aws_eip" "dr_nat" {
  provider = aws.dr
  count    = var.enable_nat_gateway ? 1 : 0

  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-dr-nat-eip"
  })
}

resource "aws_nat_gateway" "dr" {
  provider = aws.dr
  count    = var.enable_nat_gateway ? 1 : 0

  allocation_id = aws_eip.dr_nat[0].id
  subnet_id     = values(aws_subnet.dr_public)[0].id

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-dr-nat"
  })

  depends_on = [aws_internet_gateway.dr]
}

# =============================================================================
# ROUTE TABLES
# =============================================================================

# Public route table — routes to Internet Gateway
resource "aws_route_table" "dr_public" {
  provider = aws.dr

  vpc_id = aws_vpc.dr.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.dr.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-dr-public-rt"
  })
}

resource "aws_route_table_association" "dr_public" {
  provider = aws.dr

  for_each = aws_subnet.dr_public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.dr_public.id
}

# Private route table — routes to NAT Gateway (if enabled) or is isolated
resource "aws_route_table" "dr_private" {
  provider = aws.dr

  vpc_id = aws_vpc.dr.id

  # NAT Gateway route (only when NAT is enabled)
  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.dr[0].id
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-dr-private-rt"
  })
}

resource "aws_route_table_association" "dr_private" {
  provider = aws.dr

  for_each = aws_subnet.dr_private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.dr_private.id
}

# =============================================================================
# VPC PEERING — primary (us-east-1) <-> DR (us-west-2)
# =============================================================================
# Cross-region VPC peering enables:
#   - Direct network path for RDS replication (lower latency)
#   - Future EKS DR cluster to communicate with primary services
#   - Operational tools in primary to reach DR resources
# =============================================================================

resource "aws_vpc_peering_connection" "primary_to_dr" {
  count = var.enable_vpc_peering ? 1 : 0

  vpc_id      = var.primary_vpc_id
  peer_vpc_id = aws_vpc.dr.id
  peer_region = var.dr_region
  auto_accept = false

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-vpc-peer-primary-to-dr"
    Side = "requester"
  })
}

# Auto-accept the peering connection from the DR side
resource "aws_vpc_peering_connection_accepter" "dr_accept" {
  provider = aws.dr
  count    = var.enable_vpc_peering ? 1 : 0

  vpc_peering_connection_id = aws_vpc_peering_connection.primary_to_dr[0].id
  auto_accept               = true

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-vpc-peer-dr-accepter"
    Side = "accepter"
  })
}

# Route from DR private subnets to primary VPC via peering
resource "aws_route" "dr_to_primary" {
  provider = aws.dr
  count    = var.enable_vpc_peering ? 1 : 0

  route_table_id            = aws_route_table.dr_private.id
  destination_cidr_block    = var.primary_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.primary_to_dr[0].id
}

# =============================================================================
# RDS READ REPLICA — cross-region PostgreSQL (us-east-1 → us-west-2)
# =============================================================================
# Creates a read replica in the DR VPC. Key characteristics:
#   - Async replication (typically < 60s lag for PostgreSQL)
#   - Promotable to standalone primary in ~10 minutes
#   - Uses gp3 storage, Performance Insights enabled
#   - Enhanced Monitoring for replication lag visibility
# =============================================================================

# DB Subnet Group — private subnets in us-west-2
resource "aws_db_subnet_group" "dr_replica" {
  provider = aws.dr
  count    = var.enable_rds_replica ? 1 : 0

  name        = "${var.cluster_name}-postgresql-dr-replica"
  description = "Subnet group for PostgreSQL DR read replica (GAP-012 Phase 2, ${var.dr_region})"
  subnet_ids  = [for s in aws_subnet.dr_private : s.id]

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-postgresql-dr-replica-subnet-group"
  })
}

# Security Group — restricts access to DR VPC private subnets + peered primary VPC
resource "aws_security_group" "dr_replica_rds" {
  provider = aws.dr
  count    = var.enable_rds_replica ? 1 : 0

  name_prefix = "${var.cluster_name}-postgresql-dr-replica-"
  description = "Security group for PostgreSQL DR read replica — private VPC access only (GAP-012 Phase 2)"
  vpc_id      = aws_vpc.dr.id

  # Allow PostgreSQL from DR VPC private subnets
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = local.dr_private_subnet_cidrs
    description = "PostgreSQL from DR VPC private subnets"
  }

  # Allow PostgreSQL from primary VPC (via peering, for operational access)
  dynamic "ingress" {
    for_each = var.enable_vpc_peering ? [1] : []
    content {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = [var.primary_vpc_cidr]
      description = "PostgreSQL from primary VPC via VPC peering (operational access)"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-postgresql-dr-replica-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# IAM Role for RDS Enhanced Monitoring on the DR replica
resource "aws_iam_role" "dr_rds_monitoring" {
  count = var.enable_rds_replica ? 1 : 0

  name_prefix = "${var.cluster_name}-dr-rds-mon-"
  description = "IAM role for RDS Enhanced Monitoring on DR replica (GAP-012 Phase 2)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-dr-rds-monitoring-role"
  })
}

resource "aws_iam_role_policy_attachment" "dr_rds_monitoring" {
  count = var.enable_rds_replica ? 1 : 0

  role       = aws_iam_role.dr_rds_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# The RDS read replica instance
resource "aws_db_instance" "dr_replica" {
  provider = aws.dr
  count    = var.enable_rds_replica ? 1 : 0

  # Cross-region replica: reference the primary instance by ARN
  identifier          = "${var.source_db_identifier}-dr-replica-${var.dr_region}"
  replicate_source_db = data.aws_db_instance.primary[0].db_instance_arn

  # Instance sizing — start small, scale up after promotion if needed
  instance_class = var.replica_instance_class

  # Storage — inherits size from primary; gp3 for cost/performance
  storage_type          = "gp3"
  storage_encrypted     = true
  max_allocated_storage = var.replica_max_allocated_storage

  # Network — DR VPC private subnets
  db_subnet_group_name   = aws_db_subnet_group.dr_replica[0].name
  vpc_security_group_ids = [aws_security_group.dr_replica_rds[0].id]
  publicly_accessible    = false
  multi_az               = false # Single-AZ replica; promote to Multi-AZ after failover if needed

  # Maintenance
  auto_minor_version_upgrade = false
  maintenance_window         = "sun:05:00-sun:06:00"

  # Backups — enable to allow point-in-time restore after promotion
  backup_retention_period = var.replica_backup_retention_period
  backup_window           = "04:00-05:00"

  # Monitoring — Enhanced Monitoring for replication lag visibility
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.dr_rds_monitoring[0].arn

  # Performance Insights
  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  # CloudWatch logs
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Deletion protection — false on replica (can be destroyed and re-created)
  deletion_protection = false
  skip_final_snapshot = true
  apply_immediately   = false

  tags = merge(local.common_tags, {
    Name               = "${var.source_db_identifier}-dr-replica-${var.dr_region}"
    PromotionReadiness = "ready"
    ReplicationSource  = var.source_db_identifier
  })

  lifecycle {
    # Allow instance class changes in-place without forced replacement
    ignore_changes = [replicate_source_db]
  }
}

# =============================================================================
# CloudWatch Log Groups — DR Replica (Mesa Técnica CloudWatch 2026-03-24)
# Gerencia retenção dos log groups criados automaticamente pelo AWS para a réplica DR.
# count condicionado ao mesmo flag enable_rds_replica do aws_db_instance.dr_replica.
# =============================================================================

resource "aws_cloudwatch_log_group" "rds_postgresql" {
  provider = aws.dr
  count    = var.enable_rds_replica ? 1 : 0

  name              = "/aws/rds/instance/${aws_db_instance.dr_replica[0].identifier}/postgresql"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name      = "/aws/rds/instance/${aws_db_instance.dr_replica[0].identifier}/postgresql"
    Component = "rds-logs"
    ManagedBy = "terraform"
  })
}

resource "aws_cloudwatch_log_group" "rds_upgrade" {
  provider = aws.dr
  count    = var.enable_rds_replica ? 1 : 0

  name              = "/aws/rds/instance/${aws_db_instance.dr_replica[0].identifier}/upgrade"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name      = "/aws/rds/instance/${aws_db_instance.dr_replica[0].identifier}/upgrade"
    Component = "rds-logs"
    ManagedBy = "terraform"
  })
}

# =============================================================================
# CLOUDWATCH MONITORING — replication lag + storage + availability
# =============================================================================

# SNS Topic for DR alerts
resource "aws_sns_topic" "dr_alerts" {
  provider = aws.dr
  count    = var.create_sns_topic && var.enable_rds_replica ? 1 : 0

  name = "${var.cluster_name}-dr-multi-region-alerts-${var.dr_region}"

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-dr-multi-region-alerts"
  })
}

# Optional email subscription
resource "aws_sns_topic_subscription" "dr_email" {
  provider = aws.dr
  count    = var.alert_email != "" && var.create_sns_topic && var.enable_rds_replica ? 1 : 0

  topic_arn = aws_sns_topic.dr_alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

locals {
  sns_topic_arn = (
    var.enable_rds_replica
    ? (var.create_sns_topic ? aws_sns_topic.dr_alerts[0].arn : var.existing_sns_topic_arn)
    : ""
  )
}

# Alarm 1: Replication lag > threshold (default 60s)
resource "aws_cloudwatch_metric_alarm" "dr_replication_lag" {
  provider = aws.dr
  count    = var.enable_cloudwatch_alarms && var.enable_rds_replica ? 1 : 0

  alarm_name          = "${var.source_db_identifier}-dr-replica-replication-lag-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ReplicaLag"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = var.replication_lag_threshold_seconds
  alarm_description   = "GAP-012 Phase 2: RDS DR replica replication lag exceeds ${var.replication_lag_threshold_seconds}s. RPO SLA at risk."
  treat_missing_data  = "breaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.dr_replica[0].identifier
  }

  alarm_actions = [local.sns_topic_arn]
  ok_actions    = [local.sns_topic_arn]

  tags = local.common_tags
}

# Alarm 2: Free storage space low (< 4 GB default)
resource "aws_cloudwatch_metric_alarm" "dr_storage_low" {
  provider = aws.dr
  count    = var.enable_cloudwatch_alarms && var.enable_rds_replica ? 1 : 0

  alarm_name          = "${var.source_db_identifier}-dr-replica-storage-space-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Minimum"
  threshold           = 4294967296 # 4 GB in bytes
  alarm_description   = "GAP-012 Phase 2: DR replica free storage below 4 GB. Replication may stop if storage fills."
  treat_missing_data  = "breaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.dr_replica[0].identifier
  }

  alarm_actions = [local.sns_topic_arn]
  ok_actions    = [local.sns_topic_arn]

  tags = local.common_tags
}

# Alarm 3: Replica unavailable
resource "aws_cloudwatch_metric_alarm" "dr_replica_unavailable" {
  provider = aws.dr
  count    = var.enable_cloudwatch_alarms && var.enable_rds_replica ? 1 : 0

  alarm_name          = "${var.source_db_identifier}-dr-replica-unavailable"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "SampleCount"
  threshold           = 1
  alarm_description   = "GAP-012 Phase 2: DR replica appears unavailable (no connection metrics). Investigate immediately."
  treat_missing_data  = "breaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.dr_replica[0].identifier
  }

  alarm_actions = [local.sns_topic_arn]

  tags = local.common_tags
}
