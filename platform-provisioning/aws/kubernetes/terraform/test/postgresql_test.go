package test

// DT-003: PostgreSQL Module Tests
//
// Tests for the PostgreSQL RDS module covering:
// - HCL structure validation
// - Security group rules validation (port 5432, ingress restrictions)
// - Encryption enforcement (storage_encrypted = true)
// - Monitoring configuration
// - Backup configuration
// - Database provisioning structure
// - Secrets management

import (
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
)

// --- Unit Tests (no AWS credentials needed) ---

// TestPostgreSQLModuleStructure validates the overall structure of the
// PostgreSQL module (main.tf, variables.tf, outputs.tf, databases.tf).
func TestPostgreSQLModuleStructure(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "postgresql")
	logModuleInfo(t, "postgresql", "UNIT")

	t.Run("has_required_files", func(t *testing.T) {
		requiredFiles := []string{"main.tf", "variables.tf", "outputs.tf", "databases.tf", "versions.tf"}
		for _, f := range requiredFiles {
			assertFileExists(t, filepath.Join(modulePath, f))
		}
	})

	t.Run("has_bootstrap_script", func(t *testing.T) {
		assertFileExists(t, filepath.Join(modulePath, "scripts", "bootstrap-databases.sh"))
	})
}

// TestPostgreSQLSecurityGroupRules validates that the PostgreSQL security group
// follows the principle of least privilege.
func TestPostgreSQLSecurityGroupRules(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "postgresql")
	content := readFileContent(t, filepath.Join(modulePath, "main.tf"))

	t.Run("has_security_group", func(t *testing.T) {
		assert.Contains(t, content, `resource "aws_security_group" "postgresql"`,
			"PostgreSQL module must define a dedicated security group")
	})

	t.Run("restricts_ingress_to_port_5432", func(t *testing.T) {
		assert.Contains(t, content, "from_port   = 5432",
			"Ingress must be restricted to PostgreSQL port 5432")
		assert.Contains(t, content, "to_port     = 5432",
			"Ingress must be restricted to PostgreSQL port 5432")
	})

	t.Run("ingress_uses_private_subnets_only", func(t *testing.T) {
		assert.Contains(t, content, "var.private_subnet_cidrs",
			"Ingress should only allow traffic from private subnets (least privilege)")
	})

	t.Run("no_ingress_from_any_cidr", func(t *testing.T) {
		// Ensure ingress does not allow 0.0.0.0/0
		lines := strings.Split(content, "\n")
		inIngress := false
		for _, line := range lines {
			trimmed := strings.TrimSpace(line)
			if strings.HasPrefix(trimmed, "ingress {") || strings.HasPrefix(trimmed, "ingress{") {
				inIngress = true
			}
			if inIngress && trimmed == "}" {
				inIngress = false
			}
			if inIngress && strings.Contains(trimmed, `"0.0.0.0/0"`) {
				t.Error("PostgreSQL security group ingress should NOT allow 0.0.0.0/0")
			}
		}
	})

	t.Run("uses_create_before_destroy", func(t *testing.T) {
		assert.Contains(t, content, "create_before_destroy = true",
			"Security group should use create_before_destroy lifecycle")
	})
}

// TestPostgreSQLEncryption validates that storage encryption is enabled.
func TestPostgreSQLEncryption(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "postgresql")
	content := readFileContent(t, filepath.Join(modulePath, "main.tf"))

	t.Run("storage_encrypted", func(t *testing.T) {
		assert.Contains(t, content, "storage_encrypted     = true",
			"PostgreSQL RDS must have storage encryption enabled")
	})

	t.Run("uses_gp3_storage", func(t *testing.T) {
		assert.Contains(t, content, `storage_type          = "gp3"`,
			"PostgreSQL should use gp3 storage type for better performance/cost")
	})
}

// TestPostgreSQLMonitoring validates that monitoring is properly configured.
func TestPostgreSQLMonitoring(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "postgresql")
	content := readFileContent(t, filepath.Join(modulePath, "main.tf"))

	t.Run("cloudwatch_logs_enabled", func(t *testing.T) {
		assert.Contains(t, content, "enabled_cloudwatch_logs_exports",
			"PostgreSQL must export logs to CloudWatch")
		assert.Contains(t, content, `"postgresql"`,
			"Must export postgresql logs")
	})

	t.Run("enhanced_monitoring_enabled", func(t *testing.T) {
		assert.Contains(t, content, "monitoring_interval",
			"Enhanced monitoring must be configured")
		assert.Contains(t, content, "monitoring_role_arn",
			"Monitoring IAM role must be specified")
	})

	t.Run("performance_insights_enabled", func(t *testing.T) {
		assert.Contains(t, content, "performance_insights_enabled          = true",
			"Performance Insights must be enabled for debugging")
	})

	t.Run("has_monitoring_iam_role", func(t *testing.T) {
		assert.Contains(t, content, `resource "aws_iam_role" "rds_monitoring"`,
			"Must define IAM role for RDS enhanced monitoring")
		assert.Contains(t, content, "AmazonRDSEnhancedMonitoringRole",
			"Monitoring role must attach AmazonRDSEnhancedMonitoringRole policy")
	})
}

// TestPostgreSQLBackupConfiguration validates backup settings.
func TestPostgreSQLBackupConfiguration(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "postgresql")
	content := readFileContent(t, filepath.Join(modulePath, "main.tf"))

	t.Run("backup_retention_configured", func(t *testing.T) {
		assert.Contains(t, content, "backup_retention_period",
			"Backup retention period must be configured")
	})

	t.Run("backup_window_configured", func(t *testing.T) {
		assert.Contains(t, content, "backup_window",
			"Backup window must be explicitly set")
	})

	t.Run("maintenance_window_configured", func(t *testing.T) {
		assert.Contains(t, content, "maintenance_window",
			"Maintenance window must be explicitly set")
	})

	t.Run("final_snapshot_not_skipped", func(t *testing.T) {
		assert.Contains(t, content, "skip_final_snapshot       = false",
			"Final snapshot should not be skipped (data protection)")
	})

	t.Run("final_snapshot_identifier_set", func(t *testing.T) {
		assert.Contains(t, content, "final_snapshot_identifier",
			"Final snapshot identifier must be configured")
	})
}

// TestPostgreSQLSecretsManagement validates password and secrets handling.
func TestPostgreSQLSecretsManagement(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "postgresql")
	content := readFileContent(t, filepath.Join(modulePath, "main.tf"))

	t.Run("uses_random_password", func(t *testing.T) {
		assert.Contains(t, content, `resource "random_password" "master"`,
			"Must use random_password for master password generation")
	})

	t.Run("password_stored_in_secrets_manager", func(t *testing.T) {
		assert.Contains(t, content, `resource "aws_secretsmanager_secret" "master_password"`,
			"Master password must be stored in AWS Secrets Manager")
	})

	t.Run("password_length_adequate", func(t *testing.T) {
		assert.Contains(t, content, "length  = 32",
			"Master password should be at least 32 characters")
	})
}

// TestPostgreSQLVariables validates the module's input interface.
func TestPostgreSQLVariables(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "postgresql")
	content := readFileContent(t, filepath.Join(modulePath, "variables.tf"))

	requiredVars := []struct {
		name        string
		description string
	}{
		{"cluster_name", "Must accept cluster name for resource naming"},
		{"vpc_id", "Must accept VPC ID for security group placement"},
		{"vpc_cidr", "Must accept VPC CIDR"},
		{"private_subnet_ids", "Must accept private subnet IDs for DB subnet group"},
		{"private_subnet_cidrs", "Must accept private subnet CIDRs for SG rules"},
		{"instance_class", "Must accept RDS instance class"},
		{"allocated_storage", "Must accept allocated storage size"},
		{"common_tags", "Must accept common tags for resource tagging"},
	}

	for _, v := range requiredVars {
		v := v
		t.Run("has_variable_"+v.name, func(t *testing.T) {
			t.Parallel()
			assert.Contains(t, content, `variable "`+v.name+`"`, v.description)
		})
	}

	t.Run("master_password_override_is_sensitive", func(t *testing.T) {
		assert.Contains(t, content, "sensitive   = true",
			"master_password_override must be marked as sensitive")
	})
}

// TestPostgreSQLOutputs validates the module's output interface.
func TestPostgreSQLOutputs(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "postgresql")
	content := readFileContent(t, filepath.Join(modulePath, "outputs.tf"))

	requiredOutputs := []string{
		"rds_endpoint",
		"rds_address",
		"rds_port",
		"rds_database_name",
		"rds_username",
		"master_password_secret_arn",
		"security_group_id",
		"db_instance_id",
	}

	for _, output := range requiredOutputs {
		output := output
		t.Run("has_output_"+output, func(t *testing.T) {
			t.Parallel()
			assert.Contains(t, content, `output "`+output+`"`,
				"PostgreSQL module must export "+output)
		})
	}

	t.Run("username_output_is_sensitive", func(t *testing.T) {
		// Check that sensitive outputs are properly marked
		assert.Contains(t, content, "sensitive   = true",
			"Sensitive outputs (username, passwords) must be marked as sensitive")
	})
}

// TestPostgreSQLDatabaseProvisioning validates the database creation logic.
func TestPostgreSQLDatabaseProvisioning(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "postgresql")
	content := readFileContent(t, filepath.Join(modulePath, "databases.tf"))

	expectedDatabases := []string{"gitlab", "keycloak", "sonarqube"}

	for _, dbName := range expectedDatabases {
		dbName := dbName
		t.Run("provisions_"+dbName+"_database", func(t *testing.T) {
			t.Parallel()
			assert.Contains(t, content, `postgresql_database" "`+dbName,
				"Must provision "+dbName+" database")
		})

		t.Run("creates_"+dbName+"_user", func(t *testing.T) {
			t.Parallel()
			assert.Contains(t, content, dbName+"_user",
				"Must create dedicated user for "+dbName)
		})

		t.Run("uses_random_password_for_"+dbName, func(t *testing.T) {
			t.Parallel()
			assert.Contains(t, content, `random_password" "`+dbName+"_user",
				"Must use random_password for "+dbName+" user")
		})
	}

	t.Run("grants_are_scoped", func(t *testing.T) {
		assert.Contains(t, content, `postgresql_grant"`,
			"Must use postgresql_grant for fine-grained access control")
	})

	t.Run("uses_utf8_encoding", func(t *testing.T) {
		assert.Contains(t, content, `encoding          = "UTF8"`,
			"Databases must use UTF8 encoding")
	})
}

// TestPostgreSQLSecretsManagerIntegration validates that application passwords
// are properly stored in AWS Secrets Manager.
func TestPostgreSQLSecretsManagerIntegration(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "postgresql")
	content := readFileContent(t, filepath.Join(modulePath, "databases.tf"))

	t.Run("keycloak_password_in_secrets_manager", func(t *testing.T) {
		assert.Contains(t, content, `aws_secretsmanager_secret" "keycloak_user_password"`,
			"Keycloak user password must be stored in Secrets Manager")
	})

	t.Run("sonarqube_password_in_secrets_manager", func(t *testing.T) {
		assert.Contains(t, content, `aws_secretsmanager_secret" "sonarqube_user_password"`,
			"SonarQube user password must be stored in Secrets Manager")
	})
}

// TestPostgreSQLProviderConfiguration validates that the PostgreSQL provider
// is configured with security best practices.
func TestPostgreSQLProviderConfiguration(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "postgresql")
	content := readFileContent(t, filepath.Join(modulePath, "databases.tf"))

	t.Run("uses_ssl_require", func(t *testing.T) {
		assert.Contains(t, content, `sslmode         = "require"`,
			"PostgreSQL provider must use sslmode=require for encrypted connections")
	})

	t.Run("has_connect_timeout", func(t *testing.T) {
		assert.Contains(t, content, "connect_timeout",
			"Must configure connect_timeout to prevent hanging connections")
	})
}

// TestPostgreSQLVersionConstraints validates provider version requirements.
func TestPostgreSQLVersionConstraints(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "postgresql")
	content := readFileContent(t, filepath.Join(modulePath, "versions.tf"))

	t.Run("requires_aws_provider", func(t *testing.T) {
		assert.Contains(t, content, "hashicorp/aws", "Must require AWS provider")
	})

	t.Run("requires_random_provider", func(t *testing.T) {
		assert.Contains(t, content, "hashicorp/random", "Must require random provider")
	})

	t.Run("requires_postgresql_provider", func(t *testing.T) {
		assert.Contains(t, content, "cyrilgdn/postgresql", "Must require PostgreSQL provider")
	})

	t.Run("has_terraform_version_constraint", func(t *testing.T) {
		assert.Contains(t, content, "required_version", "Must specify required Terraform version")
	})
}
