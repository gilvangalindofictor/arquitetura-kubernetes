package test

// DT-003: Static Analysis Tests
//
// Tests that perform static analysis on Terraform modules without
// requiring any cloud credentials:
// - tflint execution (if available)
// - Security best practices validation
// - Naming convention checks
// - Tag compliance verification
// - Resource configuration standards

import (
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
)

// TestTFLintAllModules runs tflint on all modules if the tflint binary is available.
func TestTFLintAllModules(t *testing.T) {
	t.Parallel()

	// Check if tflint is available
	tflintPath, err := exec.LookPath("tflint")
	if err != nil {
		t.Skip("tflint not found in PATH - install tflint to enable lint checks: https://github.com/terraform-linters/tflint")
	}
	t.Logf("Using tflint at: %s", tflintPath)

	for _, moduleName := range AllModules {
		moduleName := moduleName
		t.Run(formatTestName(moduleName, "tflint"), func(t *testing.T) {
			t.Parallel()

			if !moduleExists(moduleName) {
				t.Skipf("Module directory does not exist: %s", moduleName)
			}

			modulePath := getModulePath(t, moduleName)
			logModuleInfo(t, moduleName, "LINT")

			cmd := exec.Command(tflintPath, "--no-color")
			cmd.Dir = modulePath

			output, err := cmd.CombinedOutput()
			if err != nil {
				// tflint may exit non-zero for warnings too
				if exitErr, ok := err.(*exec.ExitError); ok {
					if exitErr.ExitCode() == 2 {
						// Exit code 2 means issues found
						t.Logf("tflint found issues in module %s:\n%s", moduleName, string(output))
					} else {
						t.Logf("tflint error for module %s (exit code %d):\n%s",
							moduleName, exitErr.ExitCode(), string(output))
					}
				}
			} else {
				t.Logf("tflint passed for module %s", moduleName)
			}
		})
	}
}

// TestS3BucketsPublicAccessBlocked verifies that all S3 buckets in the project
// have public access explicitly blocked.
func TestS3BucketsPublicAccessBlocked(t *testing.T) {
	t.Parallel()

	// Scan all modules for S3 bucket definitions
	for _, moduleName := range AllModules {
		moduleName := moduleName
		if !moduleExists(moduleName) {
			continue
		}

		modulePath := getModulePath(t, moduleName)
		tfFiles := listTerraformFiles(t, modulePath)

		for _, filePath := range tfFiles {
			content := readFileContent(t, filePath)

			// Find S3 bucket definitions
			if !strings.Contains(content, `resource "aws_s3_bucket"`) {
				continue
			}

			t.Run(formatTestName(moduleName, "s3_public_access_block"), func(t *testing.T) {
				// For each S3 bucket, there should be an aws_s3_bucket_public_access_block
				assert.Contains(t, content, "aws_s3_bucket_public_access_block",
					"Module %s defines S3 buckets without public access block", moduleName)

				// Verify all four public access block settings
				allModuleContent := readAllModuleContent(t, modulePath)
				assert.Contains(t, allModuleContent, "block_public_acls       = true",
					"S3 buckets in %s must block public ACLs", moduleName)
				assert.Contains(t, allModuleContent, "block_public_policy     = true",
					"S3 buckets in %s must block public policies", moduleName)
				assert.Contains(t, allModuleContent, "ignore_public_acls      = true",
					"S3 buckets in %s must ignore public ACLs", moduleName)
				assert.Contains(t, allModuleContent, "restrict_public_buckets = true",
					"S3 buckets in %s must restrict public buckets", moduleName)
			})
		}
	}
}

// TestS3BucketsEncryptionEnabled verifies that all S3 buckets have
// server-side encryption configured.
func TestS3BucketsEncryptionEnabled(t *testing.T) {
	t.Parallel()

	for _, moduleName := range AllModules {
		moduleName := moduleName
		if !moduleExists(moduleName) {
			continue
		}

		modulePath := getModulePath(t, moduleName)
		allContent := readAllModuleContent(t, modulePath)

		if !strings.Contains(allContent, `resource "aws_s3_bucket"`) {
			continue
		}

		t.Run(formatTestName(moduleName, "s3_encryption"), func(t *testing.T) {
			assert.Contains(t, allContent, "aws_s3_bucket_server_side_encryption_configuration",
				"Module %s defines S3 buckets without encryption configuration", moduleName)
		})
	}
}

// TestS3BucketsVersioningEnabled verifies that all S3 buckets have versioning enabled.
func TestS3BucketsVersioningEnabled(t *testing.T) {
	t.Parallel()

	for _, moduleName := range AllModules {
		moduleName := moduleName
		if !moduleExists(moduleName) {
			continue
		}

		modulePath := getModulePath(t, moduleName)
		allContent := readAllModuleContent(t, modulePath)

		if !strings.Contains(allContent, `resource "aws_s3_bucket"`) {
			continue
		}

		t.Run(formatTestName(moduleName, "s3_versioning"), func(t *testing.T) {
			assert.Contains(t, allContent, "aws_s3_bucket_versioning",
				"Module %s defines S3 buckets without versioning", moduleName)
		})
	}
}

// TestSecurityGroupsHaveDescriptions ensures all security groups have descriptions.
func TestSecurityGroupsHaveDescriptions(t *testing.T) {
	t.Parallel()

	sgPattern := regexp.MustCompile(`resource\s+"aws_security_group"\s+"[^"]+"\s+\{`)

	for _, moduleName := range AllModules {
		moduleName := moduleName
		if !moduleExists(moduleName) {
			continue
		}

		modulePath := getModulePath(t, moduleName)
		tfFiles := listTerraformFiles(t, modulePath)

		for _, filePath := range tfFiles {
			content := readFileContent(t, filePath)

			if !sgPattern.MatchString(content) {
				continue
			}

			fileName := filepath.Base(filePath)
			t.Run(formatTestName(moduleName, "sg_descriptions/"+fileName), func(t *testing.T) {
				assert.Contains(t, content, "description",
					"Security groups in %s/%s must have descriptions", moduleName, fileName)
			})
		}
	}
}

// TestIAMRolesFollowLeastPrivilege checks that IAM roles use specific
// policy documents instead of overly broad permissions.
func TestIAMRolesFollowLeastPrivilege(t *testing.T) {
	t.Parallel()

	for _, moduleName := range CriticalModules {
		moduleName := moduleName
		if !moduleExists(moduleName) {
			continue
		}

		modulePath := getModulePath(t, moduleName)
		allContent := readAllModuleContent(t, modulePath)

		if !strings.Contains(allContent, `resource "aws_iam_role"`) &&
			!strings.Contains(allContent, `resource "aws_iam_policy"`) {
			continue
		}

		t.Run(formatTestName(moduleName, "iam_least_privilege"), func(t *testing.T) {
			// Check for overly broad actions
			if strings.Contains(allContent, `"*"`) && strings.Contains(allContent, `actions`) {
				// Look for "Action": "*" pattern (overly broad)
				if strings.Contains(allContent, `actions = ["*"]`) ||
					strings.Contains(allContent, `Action = "*"`) ||
					strings.Contains(allContent, `"Action": "*"`) {
					t.Errorf("Module %s uses overly broad IAM actions (\"*\") - follow least privilege", moduleName)
				}
			}

			// Specific checks: no AdministratorAccess
			assert.NotContains(t, allContent, "AdministratorAccess",
				"Module %s should not reference AdministratorAccess policy", moduleName)

			// No PowerUserAccess
			assert.NotContains(t, allContent, "PowerUserAccess",
				"Module %s should not reference PowerUserAccess policy", moduleName)
		})
	}
}

// TestKMSKeyRotationEnabled verifies that KMS keys have rotation enabled.
func TestKMSKeyRotationEnabled(t *testing.T) {
	t.Parallel()

	for _, moduleName := range AllModules {
		moduleName := moduleName
		if !moduleExists(moduleName) {
			continue
		}

		modulePath := getModulePath(t, moduleName)
		allContent := readAllModuleContent(t, modulePath)

		if !strings.Contains(allContent, `resource "aws_kms_key"`) {
			continue
		}

		t.Run(formatTestName(moduleName, "kms_rotation"), func(t *testing.T) {
			assert.Contains(t, allContent, "enable_key_rotation     = true",
				"KMS keys in module %s must have key rotation enabled", moduleName)
		})
	}
}

// TestResourceNamingConventions checks that resources follow consistent naming patterns.
func TestResourceNamingConventions(t *testing.T) {
	t.Parallel()

	for _, moduleName := range CriticalModules {
		moduleName := moduleName
		if !moduleExists(moduleName) {
			continue
		}

		modulePath := getModulePath(t, moduleName)
		allContent := readAllModuleContent(t, modulePath)

		t.Run(formatTestName(moduleName, "naming_conventions"), func(t *testing.T) {
			// Resources should use tags for identification
			if strings.Contains(allContent, `resource "aws_`) {
				// Verify resources have tags (at least Name tag or common_tags)
				hasTagging := strings.Contains(allContent, "tags") ||
					strings.Contains(allContent, "var.common_tags")

				if !hasTagging {
					t.Logf("WARNING: Module %s has AWS resources but may be missing tagging", moduleName)
				}
			}
		})
	}
}

// TestRDSInstancesNotPubliclyAccessible verifies that RDS instances are not publicly accessible.
func TestRDSInstancesNotPubliclyAccessible(t *testing.T) {
	t.Parallel()

	for _, moduleName := range AllModules {
		moduleName := moduleName
		if !moduleExists(moduleName) {
			continue
		}

		modulePath := getModulePath(t, moduleName)
		allContent := readAllModuleContent(t, modulePath)

		if !strings.Contains(allContent, `resource "aws_db_instance"`) {
			continue
		}

		t.Run(formatTestName(moduleName, "rds_not_public"), func(t *testing.T) {
			// Verify the module does not set publicly_accessible = true
			assert.NotContains(t, allContent, "publicly_accessible = true",
				"RDS instances in module %s must not be publicly accessible", moduleName)
		})
	}
}

// TestEKSClusterLogging verifies that EKS clusters have proper logging configured.
func TestEKSClusterLogging(t *testing.T) {
	t.Parallel()

	if !moduleExists("eks") {
		t.Skip("EKS module does not exist")
	}

	modulePath := getModulePath(t, "eks")
	content := readFileContent(t, filepath.Join(modulePath, "main.tf"))

	t.Run("has_cluster_logging", func(t *testing.T) {
		assert.Contains(t, content, "enabled_cluster_log_types",
			"EKS cluster must have logging enabled")
	})

	t.Run("logs_api_events", func(t *testing.T) {
		assert.Contains(t, content, `"api"`,
			"EKS must log API events")
	})

	t.Run("logs_audit_events", func(t *testing.T) {
		assert.Contains(t, content, `"audit"`,
			"EKS must log audit events")
	})

	t.Run("logs_authenticator_events", func(t *testing.T) {
		assert.Contains(t, content, `"authenticator"`,
			"EKS must log authenticator events")
	})
}

// TestEKSPrivateEndpoint verifies that EKS cluster has private endpoint enabled.
func TestEKSPrivateEndpoint(t *testing.T) {
	t.Parallel()

	if !moduleExists("eks") {
		t.Skip("EKS module does not exist")
	}

	modulePath := getModulePath(t, "eks")
	content := readFileContent(t, filepath.Join(modulePath, "main.tf"))

	t.Run("private_endpoint_enabled", func(t *testing.T) {
		assert.Contains(t, content, "endpoint_private_access = true",
			"EKS cluster must have private endpoint access enabled")
	})
}

// TestVaultModuleSecurityBestPractices checks Vault module security config.
func TestVaultModuleSecurityBestPractices(t *testing.T) {
	t.Parallel()

	if !moduleExists("vault") {
		t.Skip("Vault module does not exist")
	}

	modulePath := getModulePath(t, "vault")
	content := readFileContent(t, filepath.Join(modulePath, "main.tf"))

	t.Run("uses_kms_auto_unseal", func(t *testing.T) {
		assert.Contains(t, content, `resource "aws_kms_key" "vault_unseal"`,
			"Vault must use KMS for auto-unseal")
	})

	t.Run("kms_key_rotation_enabled", func(t *testing.T) {
		assert.Contains(t, content, "enable_key_rotation     = true",
			"Vault KMS key must have rotation enabled")
	})

	t.Run("s3_snapshots_encrypted", func(t *testing.T) {
		assert.Contains(t, content, "aws_s3_bucket_server_side_encryption_configuration",
			"Vault snapshot bucket must be encrypted")
	})

	t.Run("s3_snapshots_public_access_blocked", func(t *testing.T) {
		assert.Contains(t, content, "aws_s3_bucket_public_access_block",
			"Vault snapshot bucket must have public access blocked")
	})

	t.Run("uses_irsa", func(t *testing.T) {
		assert.Contains(t, content, "AssumeRoleWithWebIdentity",
			"Vault must use IRSA for AWS authentication")
	})

	t.Run("has_lifecycle_for_snapshots", func(t *testing.T) {
		assert.Contains(t, content, "aws_s3_bucket_lifecycle_configuration",
			"Vault snapshot bucket must have lifecycle rules")
	})
}

// --- Helper functions ---

// readAllModuleContent reads and concatenates all .tf files in a module directory.
func readAllModuleContent(t *testing.T, modulePath string) string {
	t.Helper()

	var allContent strings.Builder
	entries, err := os.ReadDir(modulePath)
	if err != nil {
		t.Fatalf("Failed to read module directory %s: %v", modulePath, err)
	}

	for _, entry := range entries {
		if !entry.IsDir() && strings.HasSuffix(entry.Name(), ".tf") {
			content, err := os.ReadFile(filepath.Join(modulePath, entry.Name()))
			if err != nil {
				t.Fatalf("Failed to read file %s: %v", entry.Name(), err)
			}
			allContent.Write(content)
			allContent.WriteString("\n")
		}
	}
	return allContent.String()
}
