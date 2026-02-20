# =============================================================================
# Makefile - Terraform IaC Testing (DT-003)
#
# Usage:
#   make test-unit        Run unit tests (no AWS credentials needed)
#   make test-lint        Run terraform fmt check on all modules
#   make test-static      Run static analysis (security, best practices)
#   make test-all         Run all tests except integration
#   make test-integration Run integration tests (requires AWS credentials)
#   make fmt              Auto-format all modules
#   make tflint-init      Initialize tflint plugins
#   make tflint           Run tflint on all modules
# =============================================================================

MODULES_DIR := ../modules
TEST_DIR := .
TFLINT_CONFIG := ../.tflint.hcl

.PHONY: help test-unit test-lint test-validate test-static test-vpc test-postgresql test-all test-integration fmt tflint-init tflint deps clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

test-unit: ## Run unit tests (no AWS credentials)
	@echo "=== Running Unit Tests ==="
	go test -v -timeout 10m \
		-run "TestTerraformFmt|TestTerraformFiles|TestCriticalModules|TestNoHardcoded|TestModulesHaveVersion|TestVPCModule|TestVPCDNS|TestVPCTag|TestVPCCIDR|TestVPCVersion|TestVPCSubnets|TestVPCSecurity|TestPostgreSQL|TestS3Buckets|TestSecurityGroups|TestIAMRoles|TestKMSKey|TestResourceNaming|TestRDSInstances|TestEKS|TestVaultModule" \
		./...

test-lint: ## Run terraform fmt check
	@echo "=== Checking Terraform Formatting ==="
	go test -v -timeout 5m -run "TestTerraformFmtAllModules" ./...

test-validate: ## Run terraform validate
	@echo "=== Running Terraform Validate ==="
	go test -v -timeout 10m -run "TestTerraformValidateAllModules" ./...

test-static: ## Run static analysis tests
	@echo "=== Running Static Analysis ==="
	go test -v -timeout 10m \
		-run "TestTFLint|TestS3Buckets|TestSecurityGroups|TestIAMRoles|TestKMSKey|TestRDSInstances|TestEKS|TestVaultModule" \
		./...

test-vpc: ## Run VPC module tests only
	@echo "=== Running VPC Tests ==="
	go test -v -timeout 5m -run "TestVPC" ./...

test-postgresql: ## Run PostgreSQL module tests only
	@echo "=== Running PostgreSQL Tests ==="
	go test -v -timeout 5m -run "TestPostgreSQL" ./...

test-all: ## Run all tests except integration
	@echo "=== Running All Tests (excluding integration) ==="
	go test -v -timeout 15m ./...

test-integration: ## Run integration tests (requires AWS credentials)
	@echo "=== Running Integration Tests ==="
	RUN_INTEGRATION_TESTS=true go test -v -timeout 30m -run "Integration|TerraformPlan" ./...

fmt: ## Auto-format all Terraform modules
	@echo "=== Formatting All Modules ==="
	@for dir in $(MODULES_DIR)/*/; do \
		echo "Formatting: $$(basename $$dir)"; \
		terraform fmt -recursive "$$dir"; \
	done
	@echo "Done."

tflint-init: ## Initialize tflint plugins
	@echo "=== Initializing TFLint ==="
	tflint --init --config $(TFLINT_CONFIG)

tflint: tflint-init ## Run tflint on all modules
	@echo "=== Running TFLint ==="
	@for dir in $(MODULES_DIR)/*/; do \
		echo "--- Linting: $$(basename $$dir) ---"; \
		tflint --config $(TFLINT_CONFIG) "$$dir" || true; \
	done

deps: ## Download Go dependencies
	@echo "=== Downloading Dependencies ==="
	go mod download
	go mod tidy

clean: ## Clean test artifacts
	@echo "=== Cleaning ==="
	rm -rf fixtures/vpc/.terraform* fixtures/vpc/terraform.tfstate*
	rm -rf fixtures/postgresql/.terraform* fixtures/postgresql/terraform.tfstate*
	rm -rf fixtures/s3-buckets/.terraform* fixtures/s3-buckets/terraform.tfstate*
	@echo "Done."
