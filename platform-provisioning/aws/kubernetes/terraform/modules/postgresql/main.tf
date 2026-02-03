# Subnet Group for RDS
resource "aws_db_subnet_group" "postgresql" {
  name       = "${var.cluster_name}-postgresql"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-postgresql-subnet-group"
  })
}

# Security Group for PostgreSQL
resource "aws_security_group" "postgresql" {
  name_prefix = "${var.cluster_name}-postgresql-"
  description = "Security group for PostgreSQL RDS"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "PostgreSQL from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-postgresql-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Master Password (Secrets Manager)
resource "random_password" "master" {
  length  = 32
  special = true
  # Exclude characters that might cause issues in connection strings
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "master_password" {
  name_prefix = "${var.cluster_name}/postgresql-master-"
  description = "PostgreSQL master password for Marco 3"

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-postgresql-password"
  })
}

resource "aws_secretsmanager_secret_version" "master_password" {
  secret_id     = aws_secretsmanager_secret.master_password.id
  secret_string = random_password.master.result
}

# PostgreSQL RDS Instance
resource "aws_db_instance" "postgresql" {
  identifier = "${var.cluster_name}-postgresql"

  engine         = "postgres"
  engine_version = "16.4"
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  # Single-AZ for cost savings (Marco 3 Fase 1)
  multi_az = false

  db_name  = "platform"
  username = "postgres_admin"
  password = random_password.master.result

  db_subnet_group_name   = aws_db_subnet_group.postgresql.name
  vpc_security_group_ids = [aws_security_group.postgresql.id]

  # Backups
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  # Monitoring
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn

  # Deletion protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.cluster_name}-postgresql-final-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  deletion_protection       = false # Set to true for production

  # Performance Insights
  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-postgresql"
  })

  lifecycle {
    ignore_changes = [
      # Ignore final_snapshot_identifier as it uses timestamp
      final_snapshot_identifier
    ]
  }
}

# IAM Role for RDS Enhanced Monitoring
resource "aws_iam_role" "rds_monitoring" {
  name_prefix = "${var.cluster_name}-rds-monitoring-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-rds-monitoring-role"
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Kubernetes Service (ExternalName) for internal DNS routing to RDS
# This creates a DNS CNAME within the cluster pointing to the RDS endpoint
# Internal apps can connect using: postgresql-external.default.svc.cluster.local:5432
# External access: Use RDS endpoint directly (no NLB needed, saves $16.20/month)
resource "kubernetes_service" "postgresql_external" {
  metadata {
    name      = "postgresql-external"
    namespace = "default"

    labels = {
      app     = "postgresql"
      service = "rds"
    }
  }

  spec {
    type = "ExternalName"
    external_name = split(":", aws_db_instance.postgresql.endpoint)[0]  # Extract hostname without port

    port {
      name     = "postgresql"
      port     = 5432
      protocol = "TCP"
    }
  }

  depends_on = [aws_db_instance.postgresql]
}
