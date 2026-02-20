package test

// DT-003: S3 Buckets Module Tests
//
// Tests for the S3 Buckets module covering:
// - Bucket creation for all expected services (GitLab, Harbor, Keycloak)
// - Encryption enforcement (SSE)
// - Public access blocking
// - Versioning enabled
// - Lifecycle rules
// - IAM policy definitions (least privilege)
// - LGPD compliance for FCT Proposals bucket

import (
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
)

// TestS3BucketsModuleStructure validates the file structure of the S3 buckets module.
func TestS3BucketsModuleStructure(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "s3-buckets")
	logModuleInfo(t, "s3-buckets", "UNIT")

	t.Run("has_required_files", func(t *testing.T) {
		requiredFiles := []string{"main.tf", "variables.tf", "outputs.tf"}
		for _, f := range requiredFiles {
			assertFileExists(t, filepath.Join(modulePath, f))
		}
	})
}

// TestS3BucketsDefinitions validates that all expected buckets are defined.
func TestS3BucketsDefinitions(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "s3-buckets")
	content := readFileContent(t, filepath.Join(modulePath, "main.tf"))

	expectedBuckets := []struct {
		name    string
		purpose string
	}{
		{"gitlab_artifacts", "CI/CD build artifacts"},
		{"harbor_images", "Container registry images"},
		{"keycloak_backups", "Keycloak realm backups"},
	}

	for _, bucket := range expectedBuckets {
		bucket := bucket
		t.Run("defines_"+bucket.name+"_bucket", func(t *testing.T) {
			t.Parallel()
			assert.Contains(t, content, `aws_s3_bucket" "`+bucket.name,
				"Must define %s bucket for %s", bucket.name, bucket.purpose)
		})
	}

	t.Run("defines_fct_proposals_bucket_conditionally", func(t *testing.T) {
		assert.Contains(t, content, `aws_s3_bucket" "fct_proposals"`,
			"Must define fct_proposals bucket (conditional on enable_fct_proposals)")
		assert.Contains(t, content, "var.enable_fct_proposals",
			"fct_proposals bucket must be conditional")
	})
}

// TestS3BucketsSecurityConfiguration validates security settings for all buckets.
func TestS3BucketsSecurityConfiguration(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "s3-buckets")
	content := readFileContent(t, filepath.Join(modulePath, "main.tf"))

	buckets := []string{"gitlab_artifacts", "harbor_images", "keycloak_backups"}

	for _, bucket := range buckets {
		bucket := bucket

		t.Run(bucket+"/public_access_blocked", func(t *testing.T) {
			t.Parallel()
			assert.Contains(t, content, `aws_s3_bucket_public_access_block" "`+bucket,
				"Bucket %s must have public access block", bucket)
		})

		t.Run(bucket+"/encryption_configured", func(t *testing.T) {
			t.Parallel()
			assert.Contains(t, content, `aws_s3_bucket_server_side_encryption_configuration" "`+bucket,
				"Bucket %s must have server-side encryption", bucket)
		})

		t.Run(bucket+"/versioning_enabled", func(t *testing.T) {
			t.Parallel()
			assert.Contains(t, content, `aws_s3_bucket_versioning" "`+bucket,
				"Bucket %s must have versioning enabled", bucket)
		})
	}
}

// TestS3BucketsLifecycleRules validates that buckets have proper lifecycle management.
func TestS3BucketsLifecycleRules(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "s3-buckets")
	content := readFileContent(t, filepath.Join(modulePath, "main.tf"))

	t.Run("gitlab_artifacts_has_lifecycle", func(t *testing.T) {
		assert.Contains(t, content, `aws_s3_bucket_lifecycle_configuration" "gitlab_artifacts"`,
			"GitLab artifacts bucket must have lifecycle rules")
	})

	t.Run("harbor_images_has_lifecycle", func(t *testing.T) {
		assert.Contains(t, content, `aws_s3_bucket_lifecycle_configuration" "harbor_images"`,
			"Harbor images bucket must have lifecycle rules")
	})

	t.Run("keycloak_backups_has_lifecycle", func(t *testing.T) {
		assert.Contains(t, content, `aws_s3_bucket_lifecycle_configuration" "keycloak_backups"`,
			"Keycloak backups bucket must have lifecycle rules (30-day retention)")
	})

	t.Run("gitlab_has_intelligent_tiering", func(t *testing.T) {
		assert.Contains(t, content, `aws_s3_bucket_intelligent_tiering_configuration" "gitlab_artifacts"`,
			"GitLab artifacts should use Intelligent-Tiering for cost optimization")
	})
}

// TestS3BucketsIAMPolicies validates that IRSA policies are defined for each service.
func TestS3BucketsIAMPolicies(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "s3-buckets")
	content := readFileContent(t, filepath.Join(modulePath, "main.tf"))

	t.Run("gitlab_iam_policy_defined", func(t *testing.T) {
		assert.Contains(t, content, `aws_iam_policy" "gitlab_s3"`,
			"Must define IAM policy for GitLab S3 access")
	})

	t.Run("harbor_iam_policy_defined", func(t *testing.T) {
		assert.Contains(t, content, `aws_iam_policy" "harbor_s3"`,
			"Must define IAM policy for Harbor S3 access")
	})

	t.Run("keycloak_backup_iam_policy_defined", func(t *testing.T) {
		assert.Contains(t, content, `aws_iam_policy" "keycloak_backup_s3"`,
			"Must define IAM policy for Keycloak backup S3 access")
	})

	// Verify policies follow least privilege (not using s3:*)
	t.Run("policies_use_specific_actions", func(t *testing.T) {
		assert.NotContains(t, content, `"s3:*"`,
			"IAM policies must not use s3:* (follow least privilege)")
	})
}

// TestS3BucketsOutputs validates the module outputs.
func TestS3BucketsOutputs(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "s3-buckets")
	content := readFileContent(t, filepath.Join(modulePath, "outputs.tf"))

	requiredOutputs := []string{
		"gitlab_artifacts_bucket_name",
		"gitlab_artifacts_bucket_arn",
		"gitlab_s3_policy_arn",
		"harbor_images_bucket_name",
		"harbor_images_bucket_arn",
		"harbor_s3_policy_arn",
		"keycloak_backups_bucket_name",
		"keycloak_backups_bucket_arn",
		"keycloak_backup_s3_policy_arn",
		"buckets_summary",
	}

	for _, output := range requiredOutputs {
		output := output
		t.Run("has_output_"+output, func(t *testing.T) {
			t.Parallel()
			assert.Contains(t, content, `output "`+output+`"`,
				"S3 buckets module must export "+output)
		})
	}
}

// TestS3BucketsVariables validates the module input interface.
func TestS3BucketsVariables(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "s3-buckets")
	content := readFileContent(t, filepath.Join(modulePath, "variables.tf"))

	requiredVars := []string{
		"cluster_name",
		"aws_account_id",
		"common_tags",
		"enable_fct_proposals",
	}

	for _, v := range requiredVars {
		v := v
		t.Run("has_variable_"+v, func(t *testing.T) {
			t.Parallel()
			assert.Contains(t, content, `variable "`+v+`"`,
				"S3 buckets module must accept "+v+" variable")
		})
	}
}

// TestS3BucketsFCTProposalsLGPDCompliance validates LGPD compliance
// for the FCT Proposals bucket (cross-region, data retention).
func TestS3BucketsFCTProposalsLGPDCompliance(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "s3-buckets")
	content := readFileContent(t, filepath.Join(modulePath, "main.tf"))

	t.Run("deployed_in_sa_east_1", func(t *testing.T) {
		assert.Contains(t, content, "provider = aws.sa_east_1",
			"FCT Proposals bucket must be deployed in sa-east-1 for LGPD compliance")
	})

	t.Run("has_7_year_retention", func(t *testing.T) {
		assert.Contains(t, content, "2555",
			"FCT Proposals must have 7-year retention (2555 days) for LGPD compliance")
	})
}
