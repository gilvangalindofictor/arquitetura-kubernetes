package test

// DT-003: VPC Module Tests
//
// Tests for the VPC module covering:
// - HCL structure validation (variables, resources, outputs)
// - CIDR block validation
// - DNS configuration enforcement
// - Tag compliance
// - Integration test with terraform plan (requires AWS credentials)

import (
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// --- Unit Tests (no AWS credentials needed) ---

// TestVPCModuleStructure validates the HCL structure of the VPC module.
func TestVPCModuleStructure(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "vpc")
	logModuleInfo(t, "vpc", "UNIT")

	// Verify main.tf exists
	mainTf := filepath.Join(modulePath, "main.tf")
	assertFileExists(t, mainTf)

	content := readFileContent(t, mainTf)

	t.Run("has_vpc_resource", func(t *testing.T) {
		assert.Contains(t, content, `resource "aws_vpc"`, "VPC module must define an aws_vpc resource")
	})

	t.Run("has_vpc_cidr_variable", func(t *testing.T) {
		assert.Contains(t, content, `variable "vpc_cidr"`, "VPC module must define vpc_cidr variable")
	})

	t.Run("has_vpc_name_variable", func(t *testing.T) {
		assert.Contains(t, content, `variable "vpc_name"`, "VPC module must define vpc_name variable")
	})

	t.Run("has_vpc_id_output", func(t *testing.T) {
		assert.Contains(t, content, `output "vpc_id"`, "VPC module must export vpc_id output")
	})

	t.Run("has_vpc_cidr_output", func(t *testing.T) {
		assert.Contains(t, content, `output "vpc_cidr"`, "VPC module must export vpc_cidr output")
	})
}

// TestVPCDNSConfiguration verifies that the VPC module enables DNS support
// (required for EKS and other AWS services).
func TestVPCDNSConfiguration(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "vpc")
	content := readFileContent(t, filepath.Join(modulePath, "main.tf"))

	t.Run("enables_dns_hostnames", func(t *testing.T) {
		assert.Contains(t, content, "enable_dns_hostnames = true",
			"VPC must enable DNS hostnames (required for EKS, RDS endpoints)")
	})

	t.Run("enables_dns_support", func(t *testing.T) {
		assert.Contains(t, content, "enable_dns_support = true",
			"VPC must enable DNS support (required for service discovery)")
	})
}

// TestVPCTagCompliance verifies that the VPC resource has proper tagging.
func TestVPCTagCompliance(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "vpc")
	content := readFileContent(t, filepath.Join(modulePath, "main.tf"))

	t.Run("has_name_tag", func(t *testing.T) {
		assert.Contains(t, content, "Name = var.vpc_name",
			"VPC resource must have a Name tag using the vpc_name variable")
	})
}

// TestVPCCIDRValidation tests that various CIDR inputs are valid RFC 1918 ranges.
func TestVPCCIDRValidation(t *testing.T) {
	t.Parallel()

	validCIDRs := []struct {
		name     string
		cidr     string
		expected bool
	}{
		{"standard_10_network", "10.0.0.0/16", true},
		{"standard_172_network", "172.16.0.0/16", true},
		{"standard_192_network", "192.168.0.0/16", true},
		{"small_subnet", "10.0.0.0/24", true},
		{"project_cidr", "10.0.0.0/16", true},
		{"invalid_public_ip", "8.8.8.0/24", false},
		{"invalid_multicast", "224.0.0.0/8", false},
	}

	for _, tc := range validCIDRs {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			result := isRFC1918CIDR(tc.cidr)
			assert.Equal(t, tc.expected, result,
				"CIDR %s: expected RFC1918=%v, got %v", tc.cidr, tc.expected, result)
		})
	}
}

// TestVPCVersionConstraints verifies that the VPC module has proper
// Terraform and provider version constraints.
func TestVPCVersionConstraints(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "vpc")
	versionsFile := filepath.Join(modulePath, "versions.tf")
	assertFileExists(t, versionsFile)

	content := readFileContent(t, versionsFile)

	t.Run("has_terraform_version", func(t *testing.T) {
		assert.Contains(t, content, "required_version",
			"VPC module must specify required Terraform version")
	})

	t.Run("has_aws_provider_version", func(t *testing.T) {
		assert.Contains(t, content, "hashicorp/aws",
			"VPC module must specify AWS provider source")
	})
}

// TestVPCSubnetsModuleStructure validates the subnets module that pairs with VPC.
func TestVPCSubnetsModuleStructure(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "subnets")
	logModuleInfo(t, "subnets", "UNIT")

	content := readFileContent(t, filepath.Join(modulePath, "main.tf"))

	t.Run("has_subnet_resource", func(t *testing.T) {
		assert.Contains(t, content, `resource "aws_subnet"`,
			"Subnets module must define aws_subnet resource")
	})

	t.Run("uses_for_each", func(t *testing.T) {
		assert.Contains(t, content, "for_each",
			"Subnets module should use for_each for scalable subnet creation")
	})

	t.Run("has_vpc_id_variable", func(t *testing.T) {
		assert.Contains(t, content, `variable "vpc_id"`,
			"Subnets module must accept vpc_id as input")
	})

	t.Run("has_subnet_ids_output", func(t *testing.T) {
		assert.Contains(t, content, `output "subnet_ids"`,
			"Subnets module must export subnet_ids")
	})

	t.Run("configures_availability_zone", func(t *testing.T) {
		assert.Contains(t, content, "availability_zone",
			"Subnets must configure availability_zone for HA")
	})
}

// TestVPCSecurityGroupsModuleStructure validates the security-groups module.
func TestVPCSecurityGroupsModuleStructure(t *testing.T) {
	t.Parallel()

	modulePath := getModulePath(t, "security-groups")
	logModuleInfo(t, "security-groups", "UNIT")

	content := readFileContent(t, filepath.Join(modulePath, "main.tf"))

	t.Run("has_security_group_resources", func(t *testing.T) {
		assert.Contains(t, content, `resource "aws_security_group"`,
			"Security groups module must define aws_security_group resources")
	})

	t.Run("has_eks_cluster_sg", func(t *testing.T) {
		assert.Contains(t, content, "eks_cluster",
			"Must define security group for EKS cluster")
	})

	t.Run("has_eks_nodes_sg", func(t *testing.T) {
		assert.Contains(t, content, "eks_nodes",
			"Must define security group for EKS worker nodes")
	})

	t.Run("uses_vpc_id_variable", func(t *testing.T) {
		assert.Contains(t, content, `var.vpc_id`,
			"Security groups must reference VPC ID")
	})
}

// --- Integration Tests (requires AWS credentials) ---

// TestVPCTerraformPlan runs terraform plan with the VPC module fixture.
// This test requires AWS credentials and is skipped by default.
func TestVPCTerraformPlan(t *testing.T) {
	skipUnlessIntegration(t)
	t.Parallel()

	fixturePath := filepath.Join("fixtures", "vpc")
	absFixturePath, err := filepath.Abs(fixturePath)
	require.NoError(t, err)

	// Ensure fixture exists
	if _, err := os.Stat(absFixturePath); os.IsNotExist(err) {
		t.Skip("VPC fixture directory does not exist - create test/fixtures/vpc/main.tf")
	}

	tfBinary := getTerraformBinary()

	// Init
	cmdInit := exec.Command(tfBinary, "init", "-backend=false", "-no-color")
	cmdInit.Dir = absFixturePath
	initOutput, initErr := cmdInit.CombinedOutput()
	require.NoError(t, initErr, "terraform init failed: %s", string(initOutput))

	// Plan (expect no errors)
	cmdPlan := exec.Command(tfBinary, "plan", "-no-color", "-input=false")
	cmdPlan.Dir = absFixturePath
	planOutput, planErr := cmdPlan.CombinedOutput()
	if planErr != nil {
		t.Logf("terraform plan output:\n%s", string(planOutput))
	}
	assert.NoError(t, planErr, "terraform plan should succeed for VPC fixture")
}

// --- Helper functions ---

// isRFC1918CIDR checks if a CIDR block falls within RFC 1918 private address ranges.
func isRFC1918CIDR(cidr string) bool {
	_, ipNet, err := net.ParseCIDR(cidr)
	if err != nil {
		return false
	}

	rfc1918Ranges := []string{
		"10.0.0.0/8",
		"172.16.0.0/12",
		"192.168.0.0/16",
	}

	for _, rfc1918 := range rfc1918Ranges {
		_, privateNet, _ := net.ParseCIDR(rfc1918)
		if privateNet.Contains(ipNet.IP) {
			// Also verify the network is within the private range
			lastIP := make(net.IP, len(ipNet.IP))
			for i := range ipNet.IP {
				lastIP[i] = ipNet.IP[i] | ^ipNet.Mask[i]
			}
			if privateNet.Contains(lastIP) {
				return true
			}
		}
	}
	return false
}

// generateVPCFixtureMessage provides guidance for creating VPC test fixtures.
func generateVPCFixtureMessage() string {
	return fmt.Sprintf(`
To run integration tests for the VPC module, create a fixture at:
  test/fixtures/vpc/main.tf

Example content:
  provider "aws" {
    region = "us-east-1"
  }

  module "vpc" {
    source   = "../../../modules/vpc"
    vpc_cidr = "10.99.0.0/16"
    vpc_name = "terratest-vpc"
  }
`)
}
