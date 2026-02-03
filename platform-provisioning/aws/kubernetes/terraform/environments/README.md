# Multi-Environment Terraform Structure

This directory contains environment-specific Terraform configurations for the K8s Platform.

## Directory Structure

```
environments/
├── common/
│   └── common.tfvars          # Shared variables (AWS account, VPC, tags)
├── staging/
│   ├── main.tf                # STAGING environment configuration
│   ├── backend.tf             # S3 backend: environments/staging/terraform.tfstate
│   ├── terraform.tfvars       # STAGING-specific values (downsized resources)
│   └── outputs.tf             # STAGING outputs
└── prod/
    ├── main.tf                # PROD environment configuration
    ├── backend.tf             # S3 backend: environments/prod/terraform.tfstate
    ├── terraform.tfvars       # PROD-specific values (production-grade)
    └── outputs.tf             # PROD outputs
```

## Shared Modules

All environments use shared modules from `../../modules/`:

- **Infrastructure:** eks, vpc, subnets, security-groups, iam, kms
- **Data Services:** postgresql, redis, rabbitmq, s3-buckets
- **Platform Services:** gitlab
- **Observability:** kube-prometheus-stack, loki, tempo
- **FinOps:** finops-automation (STAGING only)

## Environment Differences

### STAGING (Cost-Optimized)
- **PostgreSQL:** db.t3.micro, single-AZ (accept downtime)
- **Redis:** 1 replica, no Sentinel
- **RabbitMQ:** 1 replica, no quorum
- **Nodes:** 2× t3.medium (FinOps auto-shutdown 18h-8h BRT)
- **Retention:** Logs 7d, metrics 7d
- **Tags:** `Environment=staging`, `DataClassification=Internal`, `LGPD=Synthetic`

### PROD (Production-Grade)
- **PostgreSQL:** db.t3.medium, Multi-AZ (99.95% SLA)
- **Redis:** 3 replicas + Sentinel (HA failover <30s)
- **RabbitMQ:** 3 replicas quorum (HA)
- **Nodes:** 3× t3.large (24/7 always on)
- **Retention:** Logs 30d, metrics 30d
- **Tags:** `Environment=prod`, `DataClassification=Sensitive`, `LGPD=PII`

## Shared Components

### GitLab (Shared)
- Single GitLab CE instance in `gitlab` namespace
- Projects organized by groups: `staging/` and `prod/`
- GitLab Runners deploy to STAGING or PROD via Kubernetes RBAC

### Observability (Hybrid)
- Shared Prometheus + Grafana + Loki + Tempo in `observability` namespace
- Separation via labels: `environment=staging|prod`
- Loki S3 prefixes: `staging/` (7d) vs `prod/` (30d)
- Tempo tenant separation via headers

## Network Isolation

NetworkPolicies enforce cross-environment isolation:

- STAGING apps → STAGING data services ONLY
- PROD apps → PROD data services ONLY
- Default DENY all cross-namespace traffic

## Usage

### Deploy STAGING

```bash
cd environments/staging
terraform init
terraform plan -out=staging.tfplan
terraform apply staging.tfplan
```

### Deploy PROD

```bash
cd environments/prod
terraform init
terraform plan -out=prod.tfplan
terraform apply prod.tfplan
```

## Cost Estimate

- **STAGING:** ~$100/month (with FinOps automation)
- **PROD:** ~$380/month (production-grade SLA)
- **TOTAL:** ~$481/month (R$ 2.887/mês @ R$ 6.00 exchange rate)

## References

- [ADR-026: Multi-Environment Refactoring](../../docs/context/decisions.md#adr-026)
- [ADR-027: Shared GitLab with Separated DataServices](../../docs/context/decisions.md#adr-027)
- [ADR-028: Hybrid Observability](../../docs/context/decisions.md#adr-028)
- [Cost Analysis](../../docs/context/costs.md)
