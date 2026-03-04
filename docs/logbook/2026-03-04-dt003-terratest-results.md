# DT-003 Terratest CI — Execution Results

**Date:** 2026-03-04
**Agent:** Terraform Specialist
**Demanda:** DT-003 (Terratest CI — rodar make test-all)
**Duration:** ~30 min

---

## Environment

| Item | Value |
|------|-------|
| Go version | 1.22.2 linux/amd64 |
| Terraform version | v1.14.3 |
| tflint | available (in PATH) |
| Test directory | `platform-provisioning/aws/kubernetes/terraform/test` |
| Go module | `github.com/observability-platform/terraform-tests` |
| Test files | 7 (`eks_test.go`, `helpers_test.go`, `postgresql_test.go`, `s3_buckets_test.go`, `static_analysis_test.go`, `terraform_validate_test.go`, `vpc_test.go`) |

---

## go mod tidy

**Result: OK** — No errors. `go.mod` already contained all required dependencies (`github.com/stretchr/testify v1.9.0`). Note: Terratest (`github.com/gruntwork-io/terratest`) is NOT used — tests are implemented with raw `os/exec` + `testify/assert`, avoiding the heavy Terratest dependency.

---

## make test-all Results

### Initial run (before fixes)

`go test -v -timeout 15m ./...` timed out at 900s (15 min). Root cause: `TestTerraformValidateAllModules` calls `terraform init` for each of the 31 modules, which downloads Terraform providers from the internet. This exhausts the timeout in an offline/slow-network environment.

Before timeout, the following results were captured:

| Status | Count |
|--------|-------|
| PASS | 51 |
| FAIL | 2 |
| SKIP | 1 |

### Failures Identified

#### FAIL 1: `TestVPCDNSConfiguration/enables_dns_support`

**File:** `test/vpc_test.go:74`

**Root cause:** Test searched for the exact string `"enable_dns_support = true"` but the VPC module (`modules/vpc/main.tf`) uses HCL alignment formatting: `"enable_dns_support   = true"` (3 spaces before `=` to align with `cidr_block`). `terraform fmt` preserves this alignment, so it is valid HCL. The string match failed due to whitespace mismatch.

**Fix applied:** Updated `vpc_test.go` to normalize whitespace before the string comparison:
```go
// Before (failing):
assert.Contains(t, content, "enable_dns_support = true", ...)

// After (passing):
normalizedContent := strings.Join(strings.Fields(content), " ")
assert.Contains(t, normalizedContent, "enable_dns_support = true", ...)
```
Also added `"strings"` to the import block (was missing — caught by IDE diagnostics).

**Files changed:**
- `test/vpc_test.go` — added `"strings"` import + whitespace normalization

#### FAIL 2: `TestTerraformFmtAllModules/gitlab/fmt`

**File:** `modules/gitlab/variables.tf:52`

**Root cause:** Variable `gitlab_version` had two spaces before inline comment (`"9.9.1"  # comment`). `terraform fmt` requires a single space before `#` inline comments.

**Fix applied:** Removed the extra space:
```hcl
# Before (failing):
default     = "9.9.1"  # INFRA-001: COMPLETO 2026-03-03 ...

# After (passing):
default     = "9.9.1" # INFRA-001: COMPLETO 2026-03-03 ...
```

**Files changed:**
- `modules/gitlab/variables.tf:52` — single space before `#`

---

## Final Test Results (after fixes)

All tests excluding `TestTerraformValidateAllModules` (which requires network):

| Test suite | Result | Sub-tests |
|------------|--------|-----------|
| TestTerraformFmtAllModules | PASS | 31/31 modules |
| TestTerraformFilesExist | PASS | 31/31 modules |
| TestCriticalModulesHaveVariablesOrOutputs | PASS | 12/12 modules |
| TestNoHardcodedCredentials | PASS | 31/31 modules |
| TestModulesHaveVersionConstraints | PASS | 13/13 modules |
| TestResourceNamingConventions | PASS | 13/13 modules |
| TestVPCDNSConfiguration | PASS | 2/2 (incl. fixed subtest) |
| TestVPCModuleStructure | PASS | 5/5 |
| TestVPCTagCompliance | PASS | 1/1 |
| TestVPCCIDRValidation | PASS | 7/7 |
| TestVPCVersionConstraints | PASS | 2/2 |
| TestVPCSubnetsModuleStructure | PASS | 5/5 |
| TestVPCSecurityGroupsModuleStructure | PASS | 4/4 |
| TestVPCTerraformPlan | SKIP | (integration, no AWS creds) |
| TestEKSModuleStructure | PASS | 2/2 |
| TestEKSClusterConfiguration | PASS | all |
| TestEKSIAMConfiguration | PASS | all |
| TestEKSSecurityGroupConfiguration | PASS | all |
| TestEKSNodeGroupConfiguration | PASS | all |
| TestEKSClusterEndpointConfiguration | PASS | all |
| TestEKSOutputs | PASS | all |
| TestEKSOIDCProvider | PASS | all |
| TestEKSTaggingCompliance | PASS | all |
| TestEKSNodeGroupDefaults | PASS | all |
| TestEKSClusterLogging | PASS | 4/4 |
| TestEKSPrivateEndpoint | PASS | 1/1 |
| TestPostgreSQLModuleStructure | PASS | all |
| TestPostgreSQLSecurityGroupRules | PASS | all |
| TestPostgreSQLEncryption | PASS | all |
| TestPostgreSQLMonitoring | PASS | all |
| TestPostgreSQLBackupConfiguration | PASS | all |
| TestPostgreSQLSecretsManagement | PASS | all |
| TestPostgreSQLVariables | PASS | all |
| TestPostgreSQLOutputs | PASS | all |
| TestPostgreSQLVersionConstraints | PASS | all |
| TestS3BucketsModuleStructure | PASS | all |
| TestS3BucketsDefinitions | PASS | all |
| TestS3BucketsSecurityConfiguration | PASS | all |
| TestS3BucketsLifecycleRules | PASS | all |
| TestS3BucketsIAMPolicies | PASS | all |
| TestS3BucketsOutputs | PASS | all |
| TestS3BucketsVariables | PASS | all |
| TestS3BucketsFCTProposalsLGPDCompliance | PASS | 2/2 |
| TestS3BucketsPublicAccessBlocked | PASS | all |
| TestS3BucketsEncryptionEnabled | PASS | all |
| TestS3BucketsVersioningEnabled | PASS | all |
| TestSecurityGroupsHaveDescriptions | PASS | all |
| TestIAMRolesFollowLeastPrivilege | PASS | all |
| TestKMSKeyRotationEnabled | PASS | all |
| TestRDSInstancesNotPubliclyAccessible | PASS | all |
| TestVaultModuleSecurityBestPractices | PASS | 6/6 |
| TestTFLintAllModules | PASS | 32/32 (warnings logged, not failures) |

**Total:** 0 FAIL, 1 SKIP (integration), all others PASS
**Execution time:** ~1.4s (unit+static) + ~0.2s (fmt)

---

## tflint Warnings (non-blocking)

The following tflint warnings were logged but do NOT fail the tests (exit code 2 = warnings only, handled gracefully in test code):

| Module | Warning |
|--------|---------|
| `finops-automation` | `variable "node_groups_config"` declared but not used |
| `finops-automation` | `variable "circuit_breaker_reset_hours"` declared but not used |
| `tempo` | `data "aws_eks_cluster_auth"` declared but not used |
| `gitlab` | `terraform "required_version"` attribute missing |
| `gitlab` | `variable "environment"` declared but not used |

These are minor code hygiene issues. Recommend cleanup in a dedicated refactor ticket.

---

## TestTerraformValidateAllModules — Timeout Analysis

This test runs `terraform init -backend=false` + `terraform validate` for each of 31 modules. In a network-enabled CI environment this should complete within 10-20 minutes (providers cached after first run). It timed out locally at 15 min because:

1. Provider downloads are slow on the local WSL2 network
2. 31 modules × multiple providers = significant download time on first run
3. Some modules (vault, keycloak, argocd, etc.) use helm/kubernetes providers that are large

**CI solution:** The `terratest.gitlab-ci.yml` template splits this into a dedicated `terratest-validate` job with `cache:` for `.terraform` directories and `timeout: 20m`. This ensures provider downloads are cached between pipeline runs.

---

## Artefatos Criados / Modificados

| File | Action | Description |
|------|--------|-------------|
| `platform-provisioning/aws/kubernetes/terraform/test/vpc_test.go` | Modified | Added `"strings"` import; fixed `enables_dns_support` assertion to normalize HCL whitespace |
| `platform-provisioning/aws/kubernetes/terraform/modules/gitlab/variables.tf` | Modified | Fixed double-space before `#` comment on line 52 (terraform fmt compliance) |
| `domains/cicd-platform/infra/gitlab-ci/templates/terratest.gitlab-ci.yml` | Created | 4-job CI pipeline: unit, fmt, static, validate (separate stages), integration (manual) |

---

## Proximos Passos

1. **Merge / commit** these 3 file changes
2. **tflint cleanup** (optional): remove unused variables in `finops-automation`, `gitlab`, `tempo` modules
3. **TestTerraformValidateAllModules in CI**: the `terratest-validate` job in the new CI template will run this with provider caching — validate it works on the first CI pipeline run
4. **Integration tests**: when AWS credentials are available, trigger `RUN_TERRATEST_INTEGRATION=true` in GitLab CI to run `TestVPCTerraformPlan` and other `*Integration*` tests
