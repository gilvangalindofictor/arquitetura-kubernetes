package test

// DT-003: EKS Module Tests
//
// Tests for the EKS module covering:
// - Cluster configuration validation
// - IAM role structure
// - Security group configuration
// - Node group settings
// - OIDC provider for IRSA
// - Logging configuration

import (
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
)

// TestEKSModuleStructure validates the overall structure of the EKS module.
func TestEKSModuleStructure(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "eks")
	logModuleInfo(t, "eks", "UNIT")

	t.Run("has_main_tf", func(t *testing.T) {
		assertFileExists(t, filepath.Join(modulePath, "main.tf"))
	})

	t.Run("has_versions_tf", func(t *testing.T) {
		assertFileExists(t, filepath.Join(modulePath, "versions.tf"))
	})
}

// TestEKSClusterConfiguration validates the EKS cluster resource configuration.
func TestEKSClusterConfiguration(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "eks")
	content := readFileContent(t, filepath.Join(modulePath, "main.tf"))

	t.Run("defines_eks_cluster", func(t *testing.T) {
		assert.Contains(t, content, `resource "aws_eks_cluster"`,
			"Must define an EKS cluster resource")
	})

	t.Run("has_project_name_variable", func(t *testing.T) {
		assert.Contains(t, content, `variable "project_name"`,
			"Must accept project_name for resource tagging")
	})

	t.Run("has_cluster_version_variable", func(t *testing.T) {
		assert.Contains(t, content, `variable "cluster_version"`,
			"Must accept cluster_version for K8s version control")
	})

	t.Run("has_vpc_id_variable", func(t *testing.T) {
		assert.Contains(t, content, `variable "vpc_id"`,
			"Must accept vpc_id for network placement")
	})

	t.Run("has_subnet_variables", func(t *testing.T) {
		assert.Contains(t, content, `variable "private_subnet_ids"`,
			"Must accept private_subnet_ids")
		assert.Contains(t, content, `variable "public_subnet_ids"`,
			"Must accept public_subnet_ids")
	})

	t.Run("has_node_groups_variable", func(t *testing.T) {
		assert.Contains(t, content, `variable "node_groups"`,
			"Must accept node_groups configuration")
	})
}

// TestEKSIAMConfiguration validates IAM roles for EKS.
func TestEKSIAMConfiguration(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "eks")
	content := readFileContent(t, filepath.Join(modulePath, "main.tf"))

	t.Run("defines_cluster_iam_role", func(t *testing.T) {
		assert.Contains(t, content, `resource "aws_iam_role" "cluster"`,
			"Must define IAM role for EKS cluster")
	})

	t.Run("cluster_role_trusts_eks_service", func(t *testing.T) {
		assert.Contains(t, content, "eks.amazonaws.com",
			"Cluster IAM role must trust EKS service principal")
	})

	t.Run("attaches_eks_cluster_policy", func(t *testing.T) {
		assert.Contains(t, content, "AmazonEKSClusterPolicy",
			"Must attach AmazonEKSClusterPolicy to cluster role")
	})

	t.Run("attaches_vpc_resource_controller", func(t *testing.T) {
		assert.Contains(t, content, "AmazonEKSVPCResourceController",
			"Must attach AmazonEKSVPCResourceController to cluster role")
	})

	t.Run("defines_node_group_iam_role", func(t *testing.T) {
		assert.Contains(t, content, `resource "aws_iam_role" "node_group"`,
			"Must define IAM role for EKS node groups")
	})

	t.Run("node_role_trusts_ec2_service", func(t *testing.T) {
		assert.Contains(t, content, "ec2.amazonaws.com",
			"Node group IAM role must trust EC2 service principal")
	})

	t.Run("attaches_required_node_policies", func(t *testing.T) {
		requiredPolicies := []string{
			"AmazonEKSWorkerNodePolicy",
			"AmazonEKS_CNI_Policy",
			"AmazonEC2ContainerRegistryReadOnly",
		}
		for _, policy := range requiredPolicies {
			assert.Contains(t, content, policy,
				"Must attach %s to node group role", policy)
		}
	})

	t.Run("attaches_ssm_policy", func(t *testing.T) {
		assert.Contains(t, content, "AmazonSSMManagedInstanceCore",
			"Must attach SSM policy for node management access")
	})
}

// TestEKSSecurityGroupConfiguration validates SG for EKS.
func TestEKSSecurityGroupConfiguration(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "eks")
	content := readFileContent(t, filepath.Join(modulePath, "main.tf"))

	t.Run("defines_cluster_security_group", func(t *testing.T) {
		assert.Contains(t, content, `resource "aws_security_group" "cluster"`,
			"Must define security group for EKS cluster control plane")
	})

	t.Run("sg_associated_with_vpc", func(t *testing.T) {
		assert.Contains(t, content, "var.vpc_id",
			"Security group must be associated with the VPC")
	})

	t.Run("sg_has_description", func(t *testing.T) {
		assert.Contains(t, content, "Security group for EKS cluster",
			"Security group must have a meaningful description")
	})
}

// TestEKSNodeGroupConfiguration validates node group settings.
func TestEKSNodeGroupConfiguration(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "eks")
	content := readFileContent(t, filepath.Join(modulePath, "main.tf"))

	t.Run("uses_for_each_for_node_groups", func(t *testing.T) {
		assert.Contains(t, content, "for_each = var.node_groups",
			"Must use for_each for flexible node group creation")
	})

	t.Run("node_groups_in_private_subnets", func(t *testing.T) {
		assert.Contains(t, content, "subnet_ids      = var.private_subnet_ids",
			"Node groups must be deployed in private subnets")
	})

	t.Run("has_scaling_config", func(t *testing.T) {
		assert.Contains(t, content, "scaling_config",
			"Node groups must have scaling configuration")
	})

	t.Run("has_update_config", func(t *testing.T) {
		assert.Contains(t, content, "update_config",
			"Node groups must have update configuration")
	})

	t.Run("has_max_unavailable_set", func(t *testing.T) {
		assert.Contains(t, content, "max_unavailable = 1",
			"Node groups should limit max_unavailable for controlled rolling updates")
	})
}

// TestEKSClusterEndpointConfiguration validates endpoint access settings.
func TestEKSClusterEndpointConfiguration(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "eks")
	content := readFileContent(t, filepath.Join(modulePath, "main.tf"))

	t.Run("private_endpoint_enabled", func(t *testing.T) {
		assert.Contains(t, content, "endpoint_private_access = true",
			"EKS must have private endpoint enabled for internal access")
	})

	t.Run("uses_both_subnet_types", func(t *testing.T) {
		assert.Contains(t, content, "concat(var.private_subnet_ids, var.public_subnet_ids)",
			"EKS cluster should use both private and public subnets")
	})
}

// TestEKSOutputs validates the module outputs.
func TestEKSOutputs(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "eks")
	content := readFileContent(t, filepath.Join(modulePath, "main.tf"))

	requiredOutputs := []string{
		"cluster_id",
		"cluster_endpoint",
		"cluster_security_group_id",
		"cluster_iam_role_arn",
		"cluster_certificate_authority_data",
		"cluster_oidc_issuer_url",
		"node_group_role_arn",
	}

	for _, output := range requiredOutputs {
		output := output
		t.Run("has_output_"+output, func(t *testing.T) {
			t.Parallel()
			assert.Contains(t, content, `output "`+output+`"`,
				"EKS module must export "+output)
		})
	}

	t.Run("certificate_authority_data_is_sensitive", func(t *testing.T) {
		assert.Contains(t, content, "sensitive   = true",
			"Certificate authority data must be marked as sensitive")
	})
}

// TestEKSOIDCProvider validates the OIDC provider configuration for IRSA.
func TestEKSOIDCProvider(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "eks")
	content := readFileContent(t, filepath.Join(modulePath, "main.tf"))

	t.Run("defines_oidc_provider", func(t *testing.T) {
		assert.Contains(t, content, `aws_iam_openid_connect_provider`,
			"Must define OIDC provider for IRSA")
	})

	t.Run("uses_tls_certificate", func(t *testing.T) {
		assert.Contains(t, content, `data "tls_certificate"`,
			"Must use tls_certificate data source for OIDC thumbprint")
	})

	t.Run("includes_sts_audience", func(t *testing.T) {
		assert.Contains(t, content, "sts.amazonaws.com",
			"OIDC provider must include sts.amazonaws.com as client ID")
	})

	t.Run("has_oidc_provider_arn_output", func(t *testing.T) {
		assert.Contains(t, content, `output "oidc_provider_arn"`,
			"Must export OIDC provider ARN for use in IRSA modules")
	})
}

// TestEKSTaggingCompliance validates that all EKS resources have proper tags.
func TestEKSTaggingCompliance(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "eks")
	content := readFileContent(t, filepath.Join(modulePath, "main.tf"))

	t.Run("resources_use_project_tag", func(t *testing.T) {
		assert.Contains(t, content, "Project   = var.project_name",
			"EKS resources must include Project tag")
	})

	t.Run("resources_use_managed_by_tag", func(t *testing.T) {
		assert.Contains(t, content, `ManagedBy = "terraform"`,
			"EKS resources must include ManagedBy = terraform tag")
	})
}

// TestEKSNodeGroupDefaults validates the default node group configuration.
func TestEKSNodeGroupDefaults(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "eks")
	content := readFileContent(t, filepath.Join(modulePath, "main.tf"))

	t.Run("default_uses_on_demand", func(t *testing.T) {
		assert.Contains(t, content, `capacity_type  = "ON_DEMAND"`,
			"Default node group should use ON_DEMAND instances for reliability")
	})

	t.Run("default_has_minimum_two_nodes", func(t *testing.T) {
		assert.Contains(t, content, "min_size       = 2",
			"Default node group should have at least 2 min nodes for HA")
	})
}
