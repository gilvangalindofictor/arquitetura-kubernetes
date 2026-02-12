# Scripts Directory

This directory contains operational scripts for managing the Kubernetes platform.

## OIDC Monitoring

### oidc-monitor.sh

Monitors OIDC authentication logs from Keycloak, GitLab, and ArgoCD for errors and issues.

**Features:**
- Detects 8 error patterns (login errors, PKCE issues, token errors, etc.)
- Generates JSON reports with error counts and samples
- Sends Slack alerts when thresholds are exceeded
- Supports continuous monitoring or single checks

**Usage:**
```bash
# Run single check (last hour)
./oidc-monitor.sh --single

# Continuous monitoring for 48 hours
./oidc-monitor.sh --duration 172800 --interval 3600

# Custom threshold
./oidc-monitor.sh --single --threshold 20
```

**Documentation:** [OIDC Monitoring Runbook](../docs/runbooks/oidc-monitoring.md)

### deploy-oidc-monitor.sh

Deploys the OIDC monitoring system to Kubernetes.

**Features:**
- Automated deployment of CronJob, ServiceAccount, RBAC, PVC
- Updates ConfigMap with latest monitoring script
- Configures Slack webhook
- Can run test job after deployment

**Usage:**
```bash
# Deploy with Slack alerts
./deploy-oidc-monitor.sh --slack-webhook https://hooks.slack.com/services/YOUR/WEBHOOK/URL --test

# Update script only
./deploy-oidc-monitor.sh --update-only
```

**Documentation:** [Implementation Guide](../docs/oidc-monitoring-implementation.md)

---

## Environment Setup

### setup-wsl-environment.sh

Sets up WSL2 development environment with required tools and configurations.

**Usage:**
```bash
./setup-wsl-environment.sh
```

### install-tools.sh

Installs required CLI tools (kubectl, helm, terraform, etc.).

**Usage:**
```bash
./install-tools.sh
```

### install-vscode-extensions.sh

Installs recommended VS Code extensions for Kubernetes development.

**Usage:**
```bash
./install-vscode-extensions.sh
```

### configure-aliases.sh

Configures useful shell aliases for kubectl and other tools.

**Usage:**
```bash
./configure-aliases.sh
```

### install-local-dns.sh

Installs and configures local DNS for Kubernetes services.

**Usage:**
```bash
./install-local-dns.sh
```

---

## Validation

### validate-project-structure.sh

Validates the project directory structure and required files.

**Usage:**
```bash
./validate-project-structure.sh
```

### validate-metrics.sh

Validates Prometheus metrics collection and alerting.

**Usage:**
```bash
./validate-metrics.sh
```

---

## FinOps

Scripts related to cost optimization are located in the `finops/` subdirectory.

See [finops/README.md](finops/README.md) for details.

---

## Adding New Scripts

When adding new scripts to this directory:

1. Make them executable: `chmod +x script-name.sh`
2. Include shebang: `#!/usr/bin/env bash`
3. Use `set -euo pipefail` for safety
4. Add usage documentation in comments
5. Update this README with description and usage
6. Follow existing naming conventions (lowercase with hyphens)

---

## Related Documentation

- [Operations Runbooks](../docs/runbooks/)
- [Project Context](../PROJECT-CONTEXT.md)
- [Architecture Diagrams](../ARCHITECTURE-DIAGRAMS.md)
