# =============================================================================
# VPC DR Module — us-west-2 Disaster Recovery Region
# =============================================================================
# Creates isolated VPC networking in us-west-2 to support:
#   - RDS read replica (GAP-012 Phase 2)
#   - Future DR workloads (EKS cluster failover)
#
# ADR Reference: ADR-078 — Velero Backup/DR Multi-Region (GAP-012)
# ADR-090 — DR Multi-Region Strategy
#
# VPC CIDR: 10.1.0.0/16  (primary: 10.0.0.0/16 in us-east-1)
# RDS Subnets: 10.1.128.0/20 (us-west-2a), 10.1.144.0/20 (us-west-2b)
# =============================================================================

# ---------------------------------------------------------------------------
# Local values
# ---------------------------------------------------------------------------

locals {
  common_tags = merge(var.tags, {
    Module    = "vpc-dr"
    GAP       = "GAP-012"
    ManagedBy = "terraform"
    Purpose   = "dr-region"
  })
}

# ---------------------------------------------------------------------------
# VPC — Disaster Recovery Region (us-west-2)
# ---------------------------------------------------------------------------

resource "aws_vpc" "dr" {
  provider = aws.dr

  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name        = "${var.name_prefix}-dr-vpc"
    Region      = var.dr_region
    Environment = var.environment
  })
}

# ---------------------------------------------------------------------------
# Private Subnets — RDS DB Subnet Group (multi-AZ required for RDS)
# ---------------------------------------------------------------------------

resource "aws_subnet" "rds_a" {
  provider = aws.dr

  vpc_id            = aws_vpc.dr.id
  cidr_block        = var.rds_subnet_cidr_az_a
  availability_zone = "${var.dr_region}a"

  tags = merge(local.common_tags, {
    Name        = "${var.name_prefix}-dr-rds-private-${var.dr_region}a"
    Tier        = "data"
    AZ          = "${var.dr_region}a"
    Environment = var.environment
  })
}

resource "aws_subnet" "rds_b" {
  provider = aws.dr

  vpc_id            = aws_vpc.dr.id
  cidr_block        = var.rds_subnet_cidr_az_b
  availability_zone = "${var.dr_region}b"

  tags = merge(local.common_tags, {
    Name        = "${var.name_prefix}-dr-rds-private-${var.dr_region}b"
    Tier        = "data"
    AZ          = "${var.dr_region}b"
    Environment = var.environment
  })
}

# ---------------------------------------------------------------------------
# DB Subnet Group — required for RDS multi-AZ in DR region
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "dr" {
  provider = aws.dr

  name        = var.db_subnet_group_name
  description = "DR subnet group for RDS replica (GAP-012 Phase 2) - ${var.environment}"

  subnet_ids = [
    aws_subnet.rds_a.id,
    aws_subnet.rds_b.id,
  ]

  tags = merge(local.common_tags, {
    Name        = var.db_subnet_group_name
    Environment = var.environment
  })
}

# ---------------------------------------------------------------------------
# Security Group — RDS access in DR region
# Allows inbound PostgreSQL from within the DR VPC CIDR only
# ---------------------------------------------------------------------------

resource "aws_security_group" "rds_dr" {
  provider = aws.dr

  name        = "${var.name_prefix}-dr-rds-sg"
  description = "Security group for RDS DR replica - ingress from DR VPC only (GAP-012)"
  vpc_id      = aws_vpc.dr.id

  ingress {
    description = "PostgreSQL from DR VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name        = "${var.name_prefix}-dr-rds-sg"
    Environment = var.environment
  })
}

# ---------------------------------------------------------------------------
# Route Table — private (no internet access for data tier)
# ---------------------------------------------------------------------------

resource "aws_route_table" "private_dr" {
  provider = aws.dr

  vpc_id = aws_vpc.dr.id

  tags = merge(local.common_tags, {
    Name        = "${var.name_prefix}-dr-private-rt"
    Environment = var.environment
    Tier        = "data"
  })
}

resource "aws_route_table_association" "rds_a" {
  provider = aws.dr

  subnet_id      = aws_subnet.rds_a.id
  route_table_id = aws_route_table.private_dr.id
}

resource "aws_route_table_association" "rds_b" {
  provider = aws.dr

  subnet_id      = aws_subnet.rds_b.id
  route_table_id = aws_route_table.private_dr.id
}
