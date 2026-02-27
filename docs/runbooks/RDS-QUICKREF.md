# RDS PostgreSQL Start/Stop Quick Reference

## Emergency Start (5 Minutes)

```bash
# 1. Start RDS
aws rds start-db-instance \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --region us-east-1

# 2. Wait for available
aws rds wait db-instance-available \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --region us-east-1

# 3. Verify services recover
kubectl get pods -n staging-platform-gitlab -l app=webservice -w
```

## Emergency Stop (2 Minutes)

```bash
# 1. Stop RDS
aws rds stop-db-instance \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --region us-east-1

# 2. Monitor status
watch -n 10 'aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --region us-east-1 \
  --query "DBInstances[0].DBInstanceStatus" \
  --output text'
```

## Manual Lambda Invocation

```bash
# Start via Lambda
aws lambda invoke \
  --function-name finops-scheduler-start-staging \
  --payload '{"action":"start","environment":"staging","triggered_by":"manual"}' \
  --region us-east-1 /tmp/response.json && cat /tmp/response.json | jq

# Stop via Lambda
aws lambda invoke \
  --function-name finops-scheduler-stop-staging \
  --payload '{"action":"stop","environment":"staging","triggered_by":"manual"}' \
  --region us-east-1 /tmp/response.json && cat /tmp/response.json | jq
```

## Check Status

```bash
# RDS status
aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --region us-east-1 \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text

# Circuit breaker state
aws dynamodb get-item \
  --table-name finops-scheduler-state-staging \
  --key '{"environment":{"S":"staging"}}' \
  --region us-east-1 | jq -r '.Item.circuit_breaker_state.S'

# Lambda logs
aws logs tail /aws/lambda/finops-scheduler-start-staging --follow
```

## Validation Script

```bash
# Quick validation
./scripts/finops/validate-rds-scheduler.sh --validate

# Cost report
./scripts/finops/validate-rds-scheduler.sh --cost-report

# Full end-to-end test
./scripts/finops/validate-rds-scheduler.sh --validate-e2e
```

## Expected Recovery Times

| Component | Time | Status |
|-----------|------|--------|
| RDS Start | 5-10 min | `stopped` → `available` |
| Keycloak | 2 min | Pods restart |
| ArgoCD | 2 min | API reconnects |
| SonarQube | 3 min | Health checks pass |
| GitLab | 5 min | Init containers complete |
| **Total** | **10-15 min** | All services operational |

## Disable Automation (Emergency)

```bash
# Disable EventBridge rules
aws events disable-rule --name finops-startup-staging --region us-east-1
aws events disable-rule --name finops-shutdown-staging --region us-east-1
aws events disable-rule --name finops-weekend-shutdown-staging --region us-east-1

# Start RDS (if needed)
aws rds start-db-instance \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --region us-east-1
```

## Cost Tracking

| Scenario | Monthly Cost (BRL) | Annual Savings |
|----------|-------------------|----------------|
| 24/7 Running | R$ 300 | Baseline |
| Business Hours (50h/week) | R$ 89 | **R$ 2,532** |

**Current Month Savings:**
```bash
./scripts/finops/validate-rds-scheduler.sh --cost-report
```

## Troubleshooting

| Issue | Quick Fix |
|-------|-----------|
| RDS stuck "starting" | Wait 20 min, check AWS Service Health |
| Pods not recovering | `kubectl rollout restart deployment <name>` |
| Circuit breaker OPEN | Reset via DynamoDB after fixing root cause |
| Lambda timeout | Check logs, increase timeout in Terraform |

**Full Documentation:** `docs/runbooks/rds-start-stop-operations.md`
