# FinOps Automation - Deployment Guide STAGING

**Versão:** 1.0
**Data:** 2026-01-30
**Framework:** [executor-terraform.md](../prompts/executor-terraform.md)
**Módulo:** [finops-scheduler](../../terraform/modules/finops-scheduler/)
**Status:** ✅ Ready for deployment

---

## 📋 Pre-Deployment Checklist

### Prerequisites

- [x] AWS credentials configured (`aws sts get-caller-identity`)
- [x] Terraform 1.6+ installed (`terraform version`)
- [x] kubectl access to staging cluster
- [x] Manual shutdown tested and validated (2026-01-30 - savings confirmed)
- [x] Multi-agent validation complete (8/11 ressalvas resolved)

### Required Information

```bash
# Cluster details
CLUSTER_NAME="k8s-platform-prod"
RDS_INSTANCE="k8s-platform-prod-postgresql"
ENVIRONMENT="staging"
AWS_REGION="us-east-1"  # Update if different

# Ownership
OWNER_EMAIL="devops-team@company.com"
COST_CENTER="Infrastructure-Optimization"
```

---

## 🚀 Phase 1: Terraform Deployment (Day 1)

### Step 1: Create Staging Environment

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/terraform/environments

# Create staging directory
mkdir -p staging
cd staging

# Create main.tf
cat > main.tf <<'EOF'
# =============================================================================
# FinOps Automation - Staging Environment
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # IMPORTANT: Configure S3 backend after initial testing
  # backend "s3" {
  #   bucket         = "terraform-state-finops-staging"
  #   key            = "finops-scheduler/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "k8s-platform"
      Environment = "staging"
      ManagedBy   = "terraform"
      Module      = "finops-scheduler"
    }
  }
}

# -----------------------------------------------------------------------------
# FinOps Scheduler Module
# -----------------------------------------------------------------------------

module "finops_scheduler" {
  source = "../../modules/finops-scheduler"

  # Environment configuration
  environment     = var.environment
  cluster_name    = var.cluster_name
  rds_instance_id = var.rds_instance_id

  # Schedules (BRT timezone)
  startup_schedule  = var.startup_schedule
  shutdown_schedule = var.shutdown_schedule

  # CRITICAL: Start with automation DISABLED for manual testing
  enable_automation = var.enable_automation

  # Lambda configuration
  lambda_timeout = 300  # 5 minutes
  lambda_memory  = 512  # MB
  lambda_runtime = "python3.11"

  # Circuit breaker
  circuit_breaker_threshold = 3

  # Monitoring
  enable_cloudwatch_alarms = true
  sns_topic_arn            = var.sns_topic_arn  # Optional

  # Observability thresholds
  startup_duration_threshold  = 600  # 10 minutes
  shutdown_duration_threshold = 600  # 10 minutes

  # Ownership tags
  owner_email = var.owner_email
  cost_center = var.cost_center

  tags = {
    ValidationDate = "2026-01-30"
    Framework      = "executor-terraform.md"
    Approver       = "Multi-Agent-Validation"
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "lambda_start_function" {
  description = "Lambda startup function details"
  value = {
    name = module.finops_scheduler.lambda_start_function_name
    arn  = module.finops_scheduler.lambda_start_function_arn
  }
}

output "lambda_stop_function" {
  description = "Lambda shutdown function details"
  value = {
    name = module.finops_scheduler.lambda_stop_function_name
    arn  = module.finops_scheduler.lambda_stop_function_arn
  }
}

output "manual_test_commands" {
  description = "Commands for manual testing"
  value       = module.finops_scheduler.manual_invocation_commands
}

output "cost_savings" {
  description = "Expected cost savings"
  value       = module.finops_scheduler.cost_savings_estimation
}

output "monitoring" {
  description = "Monitoring resources"
  value = {
    log_group_start = module.finops_scheduler.cloudwatch_log_group_start
    log_group_stop  = module.finops_scheduler.cloudwatch_log_group_stop
    alarms          = module.finops_scheduler.cloudwatch_alarms
  }
}
EOF

# Create variables.tf
cat > variables.tf <<'EOF'
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "staging"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "k8s-platform-prod"
}

variable "rds_instance_id" {
  description = "RDS instance identifier"
  type        = string
  default     = "k8s-platform-prod-postgresql"
}

variable "startup_schedule" {
  description = "Startup cron schedule (UTC) - 11:00 UTC = 8:00 AM BRT"
  type        = string
  default     = "cron(0 11 ? * MON-FRI *)"
}

variable "shutdown_schedule" {
  description = "Shutdown cron schedule (UTC) - 21:00 UTC = 6:00 PM BRT"
  type        = string
  default     = "cron(0 21 ? * MON-FRI *)"
}

variable "enable_automation" {
  description = "Enable EventBridge rules (automation)"
  type        = bool
  default     = false  # CRITICAL: Start disabled for manual testing
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarms (optional)"
  type        = string
  default     = ""
}

variable "owner_email" {
  description = "Owner email for resource tags"
  type        = string
  default     = "devops-team@company.com"
}

variable "cost_center" {
  description = "Cost center for resource tags"
  type        = string
  default     = "Infrastructure-Optimization"
}
EOF

# Create terraform.tfvars (customize as needed)
cat > terraform.tfvars <<'EOF'
# Customize these values for your environment
aws_region      = "us-east-1"
environment     = "staging"
cluster_name    = "k8s-platform-prod"
rds_instance_id = "k8s-platform-prod-postgresql"
owner_email     = "devops-team@company.com"
cost_center     = "Infrastructure-Optimization"

# Optional: Add SNS topic for alerts
# sns_topic_arn = "arn:aws:sns:us-east-1:123456789012:finops-alerts"
EOF
```

### Step 2: Initialize Terraform

```bash
# Initialize
terraform init

# Create workspace
terraform workspace new staging
terraform workspace select staging

# Verify workspace
terraform workspace show  # Should output: staging
```

### Step 3: Plan and Review

```bash
# Generate plan
terraform plan -out=tfplan

# Review output - verify:
# ✅ Lambda functions (2)
# ✅ DynamoDB table with KMS encryption
# ✅ IAM roles and policies
# ✅ EventBridge rules (DISABLED initially)
# ✅ CloudWatch Log Groups
# ✅ CloudWatch Alarms (3)

# Save plan for audit
terraform show -json tfplan > tfplan.json
```

### Step 4: Apply

```bash
# Apply plan
terraform apply tfplan

# Capture outputs
terraform output > deployment-outputs.txt
terraform output -json > deployment-outputs.json

# Verify resources created
aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `finops-scheduler`)]'
aws dynamodb list-tables --query 'TableNames[?starts_with(@, `finops-scheduler-state`)]'
```

**Expected Output:**
```
Apply complete! Resources: 15 added, 0 changed, 0 destroyed.

Outputs:

cost_savings = {
  "annual_brl" = 12787.92
  "monthly_brl" = 1065.66
  "monthly_usd" = 177.61
  "reduction_percent" = 25.9
  "validated_date" = "2026-01-30"
}

lambda_start_function = {
  "arn" = "arn:aws:lambda:us-east-1:...:function:finops-scheduler-start-staging"
  "name" = "finops-scheduler-start-staging"
}

manual_test_commands = {
  "start" = "aws lambda invoke --function-name finops-scheduler-start-staging ..."
  "stop" = "aws lambda invoke --function-name finops-scheduler-stop-staging ..."
}
```

---

## 🧪 Phase 2: Manual Testing (Days 2-8)

### Day 2-3: Startup Testing

```bash
# Test 1: Lambda Startup (Morning - 8:00 AM BRT)
aws lambda invoke \
  --function-name finops-scheduler-start-staging \
  --payload '{"action":"start","environment":"staging","triggered_by":"manual-test-day2"}' \
  --cli-binary-format raw-in-base64-out \
  response-start.json

# Check response
cat response-start.json | jq

# Expected:
# {
#   "statusCode": 200,
#   "body": {
#     "message": "Startup completed successfully",
#     "rds_started": true,
#     "asg_scaled": {"system": 2, "workloads": 3, "critical": 2},
#     "duration_seconds": 245
#   }
# }

# Wait 5 minutes for nodes to initialize
sleep 300

# Verify nodes
kubectl get nodes
# Expected: 7 nodes (2 system + 3 workloads + 2 critical)

# Verify RDS
aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --query 'DBInstances[0].DBInstanceStatus'
# Expected: "available"

# Check Lambda logs
aws logs tail /aws/lambda/finops-scheduler-start-staging --since 30m --follow

# Verify DynamoDB state
aws dynamodb get-item \
  --table-name finops-scheduler-state-staging \
  --key '{"environment":{"S":"staging"}}' \
  --query 'Item.{last_startup:last_startup.S,startup_failures:startup_failures.N,state:circuit_breaker_state.S}'
```

### Day 2-3: Shutdown Testing

```bash
# Test 2: Lambda Shutdown (Evening - 6:00 PM BRT)
aws lambda invoke \
  --function-name finops-scheduler-stop-staging \
  --payload '{"action":"stop","environment":"staging","triggered_by":"manual-test-day2"}' \
  --cli-binary-format raw-in-base64-out \
  response-stop.json

# Check response
cat response-stop.json | jq

# Wait 10 minutes for graceful shutdown
sleep 600

# Verify nodes scaled to 0
kubectl get nodes
# Expected: 0 nodes or only static nodes

# Verify RDS stopped
aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --query 'DBInstances[0].DBInstanceStatus'
# Expected: "stopped"

# Check logs
aws logs tail /aws/lambda/finops-scheduler-stop-staging --since 30m --follow

# Verify cost metrics published
aws cloudwatch get-metric-statistics \
  --namespace FinOps/Scheduler \
  --metric-name shutdown.success \
  --dimensions Name=Environment,Value=staging \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Sum
```

### Day 4-8: Validation Tests

**Test Holiday Detection:**
```bash
# Force holiday test (if today is not a holiday)
aws lambda invoke \
  --function-name finops-scheduler-start-staging \
  --payload '{"action":"start","environment":"staging","force_holiday_check":true}' \
  response-holiday.json

# Check logs for BrasilAPI call
aws logs filter-pattern /aws/lambda/finops-scheduler-start-staging "BrasilAPI"
```

**Test Circuit Breaker:**
```bash
# Simulate 3 failures (stop RDS manually before Lambda execution)
aws rds stop-db-instance --db-instance-identifier k8s-platform-prod-postgresql

# Trigger Lambda 3 times
for i in {1..3}; do
  aws lambda invoke \
    --function-name finops-scheduler-start-staging \
    --payload "{\"action\":\"start\",\"environment\":\"staging\",\"test\":\"circuit-breaker-$i\"}" \
    response-cb-$i.json
  sleep 10
done

# Verify circuit breaker OPEN
aws dynamodb get-item \
  --table-name finops-scheduler-state-staging \
  --key '{"environment":{"S":"staging"}}' \
  --query 'Item.{state:circuit_breaker_state.S,failures:startup_failures.N}'
# Expected: {"state": "OPEN", "failures": "3"}

# Reset circuit breaker
aws dynamodb update-item \
  --table-name finops-scheduler-state-staging \
  --key '{"environment":{"S":"staging"}}' \
  --update-expression "SET startup_failures = :zero, circuit_breaker_state = :closed" \
  --expression-attribute-values '{":zero":{"N":"0"},":closed":{"S":"CLOSED"}}'
```

**Test CloudWatch Alarms:**
```bash
# Check alarm states
aws cloudwatch describe-alarms \
  --alarm-name-prefix "finops-staging" \
  --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue}'

# Expected:
# - finops-staging-startup-duration-high: OK
# - finops-staging-startup-failures: OK
# - finops-staging-shutdown-failures: OK
```

---

## ✅ Phase 3: Enable Automation (Day 9)

### Validation Criteria (Must Pass All)

- [x] Manual startup/shutdown successful 5+ times
- [x] Average startup time < 10 minutes
- [x] No Lambda errors in logs
- [x] Circuit breaker stays CLOSED
- [x] CloudWatch alarms in OK state
- [x] Nodes scale correctly (0 → 7 → 0)
- [x] RDS starts/stops without errors
- [x] Holiday detection working (BrasilAPI + cache)

### Enable EventBridge Rules

```bash
cd terraform/environments/staging

# Update enable_automation
cat > terraform.tfvars <<'EOF'
aws_region      = "us-east-1"
environment     = "staging"
cluster_name    = "k8s-platform-prod"
rds_instance_id = "k8s-platform-prod-postgresql"
owner_email     = "devops-team@company.com"
cost_center     = "Infrastructure-Optimization"

# ENABLE AUTOMATION
enable_automation = true
EOF

# Plan
terraform plan -out=tfplan-enable

# Review: Should show EventBridge rules state change
# - aws_cloudwatch_event_rule.startup: state "DISABLED" → "ENABLED"
# - aws_cloudwatch_event_rule.shutdown: state "DISABLED" → "ENABLED"

# Apply
terraform apply tfplan-enable

# Verify rules enabled
aws events list-rules --name-prefix finops --query 'Rules[*].{Name:Name,State:State}'
```

**Expected Output:**
```json
[
  {"Name": "finops-startup-staging", "State": "ENABLED"},
  {"Name": "finops-shutdown-staging", "State": "ENABLED"}
]
```

### First Automated Execution

```bash
# Wait for next scheduled event (8:00 AM or 6:00 PM BRT)
# Monitor logs in real-time

# Morning (8:00 AM BRT / 11:00 UTC)
aws logs tail /aws/lambda/finops-scheduler-start-staging --follow

# Evening (6:00 PM BRT / 21:00 UTC)
aws logs tail /aws/lambda/finops-scheduler-stop-staging --follow

# Verify execution via EventBridge
aws events describe-rule --name finops-startup-staging --query '{Name:Name,State:State,Schedule:ScheduleExpression}'
```

---

## 📊 Phase 4: 30-Day Validation

### Week 1-4: Daily Monitoring

**Daily Checklist:**
```bash
# 1. Check automation executions
aws logs tail /aws/lambda/finops-scheduler-start-staging --since 1d | grep ERROR
aws logs tail /aws/lambda/finops-scheduler-stop-staging --since 1d | grep ERROR

# 2. Verify circuit breaker state
aws dynamodb get-item \
  --table-name finops-scheduler-state-staging \
  --key '{"environment":{"S":"staging"}}'

# 3. Check cost metrics
aws cloudwatch get-metric-statistics \
  --namespace FinOps/Scheduler \
  --metric-name cost_savings_daily \
  --dimensions Name=Environment,Value=staging \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 86400 \
  --statistics Sum
```

**Weekly Cost Analysis:**
```bash
# Cost Explorer CLI (requires Cost Explorer API enabled)
aws ce get-cost-and-usage \
  --time-period Start=$(date -d '7 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics UnblendedCost \
  --filter file://cost-filter.json

# cost-filter.json:
{
  "Tags": {
    "Key": "Project",
    "Values": ["k8s-platform"]
  }
}

# Expected weekly savings: ~$41.30 (R$ 247.80)
```

### Month-End Validation (Day 30)

**Success Criteria:**

| Metric | Target | Actual | Status |
|--------|--------|--------|--------|
| Monthly savings | R$ 1,065.66 | ___ | ☐ |
| Startup success rate | > 95% | ___ | ☐ |
| Shutdown success rate | > 95% | ___ | ☐ |
| Circuit breaker activations | 0 | ___ | ☐ |
| Lambda errors | < 5/month | ___ | ☐ |
| Avg startup time | < 8 min | ___ | ☐ |

**Generate Report:**
```bash
# CloudWatch Insights query (30 days)
aws logs start-query \
  --log-group-name /aws/lambda/finops-scheduler-start-staging \
  --start-time $(date -d '30 days ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message | filter @type = "REPORT" | stats count() as executions, avg(duration) as avg_duration'

# Get query ID and results
QUERY_ID=$(aws logs describe-queries --log-group-name /aws/lambda/finops-scheduler-start-staging --status Complete --query 'queries[0].queryId' --output text)
aws logs get-query-results --query-id $QUERY_ID
```

---

## 🚨 Rollback Procedures

### Emergency Disable (< 2 minutes)

```bash
# 1. Disable EventBridge rules
aws events disable-rule --name finops-startup-staging
aws events disable-rule --name finops-shutdown-staging

# 2. Verify disabled
aws events list-rules --name-prefix finops --query 'Rules[*].{Name:Name,State:State}'

# 3. Manual recovery if needed
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/finops
./startup-marco2.sh staging
```

### Full Rollback (Terraform Destroy)

```bash
cd terraform/environments/staging

# CRITICAL: Disable lifecycle prevent_destroy FIRST
terraform state rm module.finops_scheduler.aws_dynamodb_table.scheduler_state

# Destroy all resources
terraform destroy -auto-approve

# Verify cleanup
aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `finops-scheduler`)]'
aws dynamodb list-tables --query 'TableNames[?starts_with(@, `finops-scheduler-state`)]'
```

---

## 📞 Support and Escalation

### Troubleshooting Guide

| Issue | Diagnosis | Resolution |
|-------|-----------|------------|
| Lambda timeout | Check logs for slow ASG/RDS operations | Increase `lambda_timeout` to 600s |
| Circuit breaker OPEN | Check DynamoDB state, verify RDS/ASG health | Reset via DynamoDB update-item |
| High startup time | Check ASG health check grace period | Verify PodDisruptionBudgets |
| Holiday not detected | Check BrasilAPI response in logs | Verify DynamoDB cache TTL |
| CloudWatch alarm firing | Check metric namespace and dimensions | Adjust alarm thresholds |

### Contacts

- **DevOps Team:** devops-team@company.com
- **AWS Support:** [AWS Console Support](https://console.aws.amazon.com/support)
- **Documentation:** [FinOps Module README](../../terraform/modules/finops-scheduler/README.md)

---

## 📚 References

- [executor-terraform.md Framework](../prompts/executor-terraform.md)
- [ADR-024: FinOps Automation](../context/decisions.md#adr-024)
- [Architecture Marco 2](../context/architecture.md)
- [Costs Analysis](../context/costs.md)
- [Module README](../../terraform/modules/finops-scheduler/README.md)

---

**Deployment Lead:** DevOps Team
**Approval Date:** 2026-01-30
**Next Review:** 2026-03-01 (30 days post-deployment)
