// Package test contains automated tests for Terraform IaC modules.
//
// DT-003: Implement automated IaC testing with Terratest
//
// Test categories:
//   - Static Analysis: terraform fmt, validate, tflint (no AWS credentials needed)
//   - Unit Tests: HCL structure validation, variable/output checks (no AWS credentials needed)
//   - Integration Tests: terraform plan/apply cycles (AWS credentials required, tagged _integration)
package test

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// ModulesBasePath is the relative path from the test directory to the modules directory.
const ModulesBasePath = "../modules"

// AllModules is the complete list of Terraform modules in the project.
var AllModules = []string{
	"argocd",
	"ecr",
	"eks",
	"external-secrets",
	"finops-automation",
	"gitlab",
	"harbor",
	"iam",
	"internet-gateway",
	"keycloak",
	"kms",
	"kube-prometheus-stack",
	"loki",
	"nat-gateways",
	"observability",
	"opentelemetry-collector",
	"orphan-detector",
	"postgresql",
	"rabbitmq",
	"redis",
	"route-tables",
	"s3",
	"s3-buckets",
	"security-groups",
	"snapshot-cleanup",
	"sonarqube",
	"subnets",
	"tempo",
	"vault",
	"vault-config",
	"vpc",
}

// CriticalModules are modules that require deeper testing (network, cluster, databases, security).
var CriticalModules = []string{
	"vpc",
	"subnets",
	"security-groups",
	"eks",
	"postgresql",
	"vault",
	"s3-buckets",
	"keycloak",
	"argocd",
	"sonarqube",
	"kms",
	"iam",
}

// getModulePath returns the absolute path to a given module directory.
func getModulePath(t *testing.T, moduleName string) string {
	t.Helper()
	absPath, err := filepath.Abs(filepath.Join(ModulesBasePath, moduleName))
	if err != nil {
		t.Fatalf("Failed to resolve absolute path for module %s: %v", moduleName, err)
	}
	return absPath
}

// moduleExists checks if a module directory exists.
func moduleExists(moduleName string) bool {
	absPath, err := filepath.Abs(filepath.Join(ModulesBasePath, moduleName))
	if err != nil {
		return false
	}
	info, err := os.Stat(absPath)
	return err == nil && info.IsDir()
}

// listTerraformFiles returns all .tf files in a given directory.
func listTerraformFiles(t *testing.T, dir string) []string {
	t.Helper()
	var files []string
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("Failed to read directory %s: %v", dir, err)
	}
	for _, entry := range entries {
		if !entry.IsDir() && strings.HasSuffix(entry.Name(), ".tf") {
			files = append(files, filepath.Join(dir, entry.Name()))
		}
	}
	return files
}

// readFileContent reads the entire content of a file.
func readFileContent(t *testing.T, filePath string) string {
	t.Helper()
	content, err := os.ReadFile(filePath)
	if err != nil {
		t.Fatalf("Failed to read file %s: %v", filePath, err)
	}
	return string(content)
}

// assertFileExists verifies that a file exists at the given path.
func assertFileExists(t *testing.T, path string) {
	t.Helper()
	_, err := os.Stat(path)
	if os.IsNotExist(err) {
		t.Errorf("Expected file to exist: %s", path)
	}
}

// assertFileContains verifies that a file contains a specific substring.
func assertFileContains(t *testing.T, filePath string, substring string) {
	t.Helper()
	content := readFileContent(t, filePath)
	if !strings.Contains(content, substring) {
		t.Errorf("File %s does not contain expected string: %q", filePath, substring)
	}
}

// assertFileNotContains verifies that a file does NOT contain a specific substring.
func assertFileNotContains(t *testing.T, filePath string, substring string) {
	t.Helper()
	content := readFileContent(t, filePath)
	if strings.Contains(content, substring) {
		t.Errorf("File %s should not contain string: %q", filePath, substring)
	}
}

// isIntegrationTest returns true if the test should be treated as an integration
// test (requires AWS credentials). These tests are skipped unless
// RUN_INTEGRATION_TESTS=true is set.
func isIntegrationTest() bool {
	return os.Getenv("RUN_INTEGRATION_TESTS") == "true"
}

// skipUnlessIntegration skips the test unless integration test mode is enabled.
func skipUnlessIntegration(t *testing.T) {
	t.Helper()
	if !isIntegrationTest() {
		t.Skip("Skipping integration test. Set RUN_INTEGRATION_TESTS=true to run.")
	}
}

// logModuleInfo logs basic information about a module being tested.
func logModuleInfo(t *testing.T, moduleName string, testType string) {
	t.Helper()
	modulePath := getModulePath(t, moduleName)
	tfFiles := listTerraformFiles(t, modulePath)
	t.Logf("[%s] Module: %s | Path: %s | TF files: %d", testType, moduleName, modulePath, len(tfFiles))
}

// getTerraformBinary returns the path to the terraform binary.
// It checks TERRAFORM_BINARY env var first, then falls back to "terraform".
func getTerraformBinary() string {
	if bin := os.Getenv("TERRAFORM_BINARY"); bin != "" {
		return bin
	}
	return "terraform"
}

// formatTestName creates a consistent test name from module and test type.
func formatTestName(module string, testType string) string {
	return fmt.Sprintf("%s/%s", module, testType)
}
