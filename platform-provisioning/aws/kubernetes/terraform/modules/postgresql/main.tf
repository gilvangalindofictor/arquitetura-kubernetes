# -----------------------------------------------------------------------------
# DT-001: PostgreSQL Private Subnet Migration
# -----------------------------------------------------------------------------
# CURRENT STATE: RDS may be deployed in public subnets (db subnet group created
# with public subnet IDs during initial provisioning or manual recreation).
# TARGET STATE: RDS in private subnets only (no internet-routable IPs).
#
# MIGRATION NOTES:
# - Changing db_subnet_group_name on an existing RDS instance FORCES REPLACEMENT
#   (AWS limitation: subnet group change = destroy + recreate).
# - If the current RDS subnet group already uses private subnets (verify via AWS
#   Console or CLI), then no recreation is needed - only `publicly_accessible = false`
#   will be applied as an in-place update.
# - If recreation IS required:
#   1. Create manual snapshot BEFORE terraform apply
#   2. terraform apply (will recreate RDS with private subnet group)
#   3. Verify connectivity from all consumers (GitLab, Harbor, Keycloak, ArgoCD, SonarQube)
#   4. Update CoreDNS/ExternalName service if RDS endpoint changes
#
# VERIFICATION COMMAND:
#   aws rds describe-db-instances \
#     --db-instance-identifier k8s-platform-prod-postgresql \
#     --query 'DBInstances[0].{SubnetGroup:DBSubnetGroup.DBSubnetGroupName,PubliclyAccessible:PubliclyAccessible,Subnets:DBSubnetGroup.Subnets[*].SubnetIdentifier}'
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# BACEN BCB 85/2021 Art.6º §1º + LGPD Art.46 — Auditoria e Rastreabilidade
# Parameter group com pgaudit habilitado para registro de DDL, roles e conexões.
# IMPORTANTE: shared_preload_libraries usa apply_method="pending-reboot" — a
# extensão só é carregada após reinicialização planejada na janela de manutenção.
# Os demais parâmetros (log_connections, log_disconnections, pgaudit.log) são
# apply_method="immediate" e entram em vigor assim que o parameter group é aplicado.
# -----------------------------------------------------------------------------
resource "aws_db_parameter_group" "pgaudit" {
  name        = "${var.cluster_name}-postgresql-pgaudit"
  family      = "postgres16"
  description = "PostgreSQL 16 parameter group with pgaudit - BACEN BCB 85/2021 Art.6 Par.1 + LGPD Art.46"

  # shared_preload_libraries: REQUER REBOOT para ativar pgaudit.
  # apply_method="pending-reboot" garante que NÃO haverá reboot imediato durante apply.
  # O reboot ocorrerá apenas na próxima janela de manutenção (sun:04:00-sun:05:00 UTC)
  # ou manualmente via "aws rds reboot-db-instance".
  parameter {
    name         = "shared_preload_libraries"
    value        = "pgaudit"
    apply_method = "pending-reboot"
  }

  # Registra todas as conexões estabelecidas — rastreabilidade BACEN/LGPD
  parameter {
    name         = "log_connections"
    value        = "1"
    apply_method = "immediate"
  }

  # Registra todas as desconexões — rastreabilidade BACEN/LGPD
  parameter {
    name         = "log_disconnections"
    value        = "1"
    apply_method = "immediate"
  }

  # Audita DDL (CREATE/DROP/ALTER) e alterações de roles — BACEN BCB 85/2021 rastreabilidade.
  # Conexões são auditadas via log_connections/log_disconnections (parametros acima).
  # "connection" nao e valor valido para pgaudit.log (use log_connections para isso).
  # Ampliar para "ddl,role,read,write" apenas se exigido por auditoria BACEN.
  parameter {
    name         = "pgaudit.log"
    value        = "ddl,role"
    apply_method = "immediate"
  }

  tags = merge(var.common_tags, {
    Name       = "${var.cluster_name}-postgresql-pgaudit"
    Compliance = "BACEN-BCB85-2021 LGPD-Art46"
    ManagedBy  = "terraform"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Subnet Group for RDS (DT-001: Must use private subnets only)
resource "aws_db_subnet_group" "postgresql" {
  name       = "${var.cluster_name}-postgresql"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-postgresql-subnet-group"
  })
}

# Security Group for PostgreSQL (DT-001: Restrict to private subnets + VPC CIDR)
resource "aws_security_group" "postgresql" {
  name_prefix = "${var.cluster_name}-postgresql-"
  description = "Security group for PostgreSQL RDS - private subnet access only (DT-001)"
  vpc_id      = var.vpc_id

  # Allow PostgreSQL from private subnets (where EKS pods run)
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
    description = "PostgreSQL from private subnets (EKS pods: GitLab, Harbor, Keycloak, ArgoCD, SonarQube)"
  }

  # Allow PostgreSQL from VPC CIDR (for pod-to-RDS via VPC CNI secondary CIDR)
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "PostgreSQL from VPC CIDR (VPC CNI pod networking, DT-001 connectivity guarantee)"
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

  # Multi-AZ configurable per environment (DT-004)
  # Staging: false (accept downtime, FinOps cost-optimized)
  # Production: true (99.95% SLA, automatic failover)
  multi_az = var.multi_az

  db_name  = "platform"
  username = "postgres_admin"
  password = random_password.master.result

  db_subnet_group_name   = aws_db_subnet_group.postgresql.name
  vpc_security_group_ids = [aws_security_group.postgresql.id]
  publicly_accessible    = false # DT-001: Explicit deny public access (defense in depth)

  # BACEN BCB 85/2021 Art.6º §1º: pgaudit parameter group — in-place update, sem replacement.
  # shared_preload_libraries=pending-reboot: NÃO causa reboot imediato durante apply.
  parameter_group_name = aws_db_parameter_group.pgaudit.name

  # Backups
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  # Monitoring
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn

  # Major version upgrade (INFRA-002: PostgreSQL 14→16)
  allow_major_version_upgrade = var.allow_major_version_upgrade
  apply_immediately           = var.apply_immediately

  # Deletion protection (DT-004: parametrized per environment)
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.cluster_name}-postgresql-final-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  deletion_protection       = var.deletion_protection

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
# TODO: Commented temporarily due to provider cache issue
# resource "kubernetes_service" "postgresql_external" {
#   metadata {
#     name      = "postgresql-external"
#     namespace = "default"
#
#     labels = {
#       app     = "postgresql"
#       service = "rds"
#     }
#   }
#
#   spec {
#     type          = "ExternalName"
#     external_name = split(":", aws_db_instance.postgresql.endpoint)[0] # Extract hostname without port
#
#     port {
#       name     = "postgresql"
#       port     = 5432
#       protocol = "TCP"
#     }
#   }
#
#   depends_on = [aws_db_instance.postgresql]
# }

# -----------------------------------------------------------------------------
# CloudWatch Log Groups — RDS (Mesa Técnica CloudWatch 2026-03-24)
# Gerencia retenção dos log groups RDS criados automaticamente pelo AWS.
# Sem este resource, AWS cria com Never Expire → drift de custo crescente.
# Import staging: terraform import 'module.postgresql_staging.aws_cloudwatch_log_group.rds_postgresql' '/aws/rds/instance/k8s-platform-prod-postgresql/postgresql'
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "rds_postgresql" {
  name              = "/aws/rds/instance/${aws_db_instance.postgresql.identifier}/postgresql"
  retention_in_days = var.log_retention_days

  tags = merge(var.common_tags, {
    Name      = "/aws/rds/instance/${aws_db_instance.postgresql.identifier}/postgresql"
    Component = "rds-logs"
    ManagedBy = "terraform"
  })
}

resource "aws_cloudwatch_log_group" "rds_upgrade" {
  name              = "/aws/rds/instance/${aws_db_instance.postgresql.identifier}/upgrade"
  retention_in_days = var.log_retention_days

  tags = merge(var.common_tags, {
    Name      = "/aws/rds/instance/${aws_db_instance.postgresql.identifier}/upgrade"
    Component = "rds-logs"
    ManagedBy = "terraform"
  })
}

# -----------------------------------------------------------------------------
# Bootstrap Additional Databases (DISABLED - network connectivity issue)
# TODO: Fix security group to allow pod→RDS connectivity, then re-enable
# For now: use manual script modules/postgresql/scripts/bootstrap-databases.sh
# -----------------------------------------------------------------------------

# resource "null_resource" "bootstrap_databases" {
#   count = length(var.additional_databases)
#   ... (commented out due to pod→RDS network issue)
# }
