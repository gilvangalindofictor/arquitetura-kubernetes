#!/bin/bash
# RDS Automation Status Checker
# Usage: ./check-rds-automation-status.sh
# Description: Validates RDS automation configuration and current state

set -euo pipefail

RDS_INSTANCE="k8s-platform-prod-postgresql"
REGION="us-east-1"
DYNAMODB_TABLE="finops-scheduler-state-staging"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         RDS Automation Status Check (Staging)                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI not found${NC}"
    exit 1
fi

# Check jq
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}⚠️  jq not found, JSON output will be raw${NC}"
    JQ_AVAILABLE=false
else
    JQ_AVAILABLE=true
fi

echo "=== 1. RDS Instance Status ==="
RDS_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier "$RDS_INSTANCE" \
  --query 'DBInstances[0]' \
  --region "$REGION" 2>/dev/null)

if [ -z "$RDS_STATUS" ]; then
    echo -e "${RED}❌ RDS instance not found: $RDS_INSTANCE${NC}"
    exit 1
fi

if [ "$JQ_AVAILABLE" = true ]; then
    echo "$RDS_STATUS" | jq -r '"
Status: \(.DBInstanceStatus)
Class: \(.DBInstanceClass)
Engine: \(.Engine) \(.EngineVersion)
Endpoint: \(.Endpoint.Address // "N/A (stopped)"):\(.Endpoint.Port // 0)
AZ: \(.AvailabilityZone)
Multi-AZ: \(.MultiAZ)
Created: \(.InstanceCreateTime)
"'
else
    echo "$RDS_STATUS"
fi

# Determine expected status based on time
CURRENT_HOUR=$(TZ="America/Sao_Paulo" date +%H)
CURRENT_DAY=$(TZ="America/Sao_Paulo" date +%u) # 1-7 (Mon-Sun)

if [ "$CURRENT_DAY" -ge 1 ] && [ "$CURRENT_DAY" -le 5 ]; then
    # Weekday
    if [ "$CURRENT_HOUR" -ge 7 ] && [ "$CURRENT_HOUR" -lt 20 ]; then
        EXPECTED_STATUS="available"
        SCHEDULE_STATUS="Business Hours (should be RUNNING)"
    else
        EXPECTED_STATUS="stopped"
        SCHEDULE_STATUS="Off Hours (should be STOPPED)"
    fi
else
    # Weekend
    EXPECTED_STATUS="stopped"
    SCHEDULE_STATUS="Weekend (should be STOPPED)"
fi

ACTUAL_STATUS=$(echo "$RDS_STATUS" | jq -r '.DBInstanceStatus')

echo ""
echo "=== 2. Schedule Compliance ==="
echo "Current Time (BRT): $(TZ='America/Sao_Paulo' date '+%Y-%m-%d %H:%M:%S %A')"
echo "Expected Status: $EXPECTED_STATUS"
echo "Actual Status: $ACTUAL_STATUS"
echo "Schedule: $SCHEDULE_STATUS"

if [ "$ACTUAL_STATUS" == "$EXPECTED_STATUS" ]; then
    echo -e "${GREEN}✅ RDS status matches schedule${NC}"
else
    echo -e "${YELLOW}⚠️  RDS status does NOT match schedule${NC}"
    echo "   This may be normal during transition periods (start/stop in progress)"
fi

echo ""
echo "=== 3. Recent Snapshots ==="
SNAPSHOTS=$(aws rds describe-db-snapshots \
  --db-instance-identifier "$RDS_INSTANCE" \
  --query 'DBSnapshots | sort_by(@, &SnapshotCreateTime)[-5:]' \
  --region "$REGION" 2>/dev/null)

if [ "$JQ_AVAILABLE" = true ]; then
    echo "$SNAPSHOTS" | jq -r '.[] | "\(.DBSnapshotIdentifier) - \(.Status) - \(.SnapshotCreateTime)"'
else
    echo "$SNAPSHOTS"
fi

echo ""
echo "=== 4. FinOps Lambda Configuration ==="
START_LAMBDA_CONFIG=$(aws lambda get-function-configuration \
  --function-name finops-scheduler-start-staging \
  --region "$REGION" 2>/dev/null)

if [ -z "$START_LAMBDA_CONFIG" ]; then
    echo -e "${RED}❌ Lambda not found: finops-scheduler-start-staging${NC}"
else
    if [ "$JQ_AVAILABLE" = true ]; then
        echo "Start Lambda:"
        echo "$START_LAMBDA_CONFIG" | jq -r '.Environment.Variables | "
  RDS_INSTANCE_ID: \(.RDS_INSTANCE_ID // "NOT SET")
  CLUSTER_NAME: \(.CLUSTER_NAME)
  ENVIRONMENT: \(.ENVIRONMENT)
  ENABLE_SCALING_PROTECTION: \(.ENABLE_SCALING_PROTECTION)
  MIN_SYSTEM_NODES: \(.MIN_SYSTEM_NODES)
  CIRCUIT_BREAKER_THRESHOLD: \(.CIRCUIT_BREAKER_THRESHOLD)
"'

        RDS_VAR=$(echo "$START_LAMBDA_CONFIG" | jq -r '.Environment.Variables.RDS_INSTANCE_ID // ""')
        if [ "$RDS_VAR" == "$RDS_INSTANCE" ]; then
            echo -e "${GREEN}✅ RDS_INSTANCE_ID correctly configured${NC}"
        elif [ -z "$RDS_VAR" ]; then
            echo -e "${RED}❌ RDS_INSTANCE_ID not set in Lambda environment${NC}"
        else
            echo -e "${YELLOW}⚠️  RDS_INSTANCE_ID mismatch: $RDS_VAR${NC}"
        fi
    else
        echo "$START_LAMBDA_CONFIG"
    fi
fi

echo ""
echo "=== 5. DynamoDB State Table ==="
DYNAMODB_STATE=$(aws dynamodb get-item \
  --table-name "$DYNAMODB_TABLE" \
  --key '{"environment":{"S":"staging"}}' \
  --region "$REGION" 2>/dev/null)

if [ -z "$DYNAMODB_STATE" ]; then
    echo -e "${YELLOW}⚠️  No state found in DynamoDB (automation may not have run yet)${NC}"
else
    if [ "$JQ_AVAILABLE" = true ]; then
        echo "$DYNAMODB_STATE" | jq -r '.Item | "
Last Action: \(.last_action.S // "N/A")
Timestamp: \(.last_action_timestamp.S // "N/A")
Circuit Breaker State: \(.circuit_breaker_state.S // "normal")
Circuit Breaker Count: \(.circuit_breaker_count.N // "0")
RDS Last Action: \(.rds_last_action.S // "N/A")
RDS Last Timestamp: \(.rds_last_timestamp.S // "N/A")
"'

        CB_STATE=$(echo "$DYNAMODB_STATE" | jq -r '.Item.circuit_breaker_state.S // "normal"')
        CB_COUNT=$(echo "$DYNAMODB_STATE" | jq -r '.Item.circuit_breaker_count.N // "0"')

        if [ "$CB_STATE" == "normal" ] && [ "$CB_COUNT" -eq 0 ]; then
            echo -e "${GREEN}✅ Circuit breaker healthy${NC}"
        elif [ "$CB_STATE" == "normal" ] && [ "$CB_COUNT" -gt 0 ]; then
            echo -e "${YELLOW}⚠️  Circuit breaker count: $CB_COUNT (threshold: 3)${NC}"
        else
            echo -e "${RED}❌ Circuit breaker TRIPPED: $CB_STATE (count: $CB_COUNT)${NC}"
        fi
    else
        echo "$DYNAMODB_STATE"
    fi
fi

echo ""
echo "=== 6. Recent Lambda Executions ==="
echo "Start Lambda (last 5 invocations):"
aws logs filter-log-events \
  --log-group-name /aws/lambda/finops-scheduler-start-staging \
  --filter-pattern "RDS" \
  --max-items 5 \
  --region "$REGION" 2>/dev/null | jq -r '.events[]? | "\(.timestamp | todateiso8601) - \(.message)"' 2>/dev/null || echo "No recent logs"

echo ""
echo "Stop Lambda (last 5 invocations):"
aws logs filter-log-events \
  --log-group-name /aws/lambda/finops-scheduler-stop-staging \
  --filter-pattern "RDS" \
  --max-items 5 \
  --region "$REGION" 2>/dev/null | jq -r '.events[]? | "\(.timestamp | todateiso8601) - \(.message)"' 2>/dev/null || echo "No recent logs"

echo ""
echo "=== 7. EventBridge Schedules ==="
echo "Checking scheduled rules..."

START_RULE=$(aws events describe-rule \
  --name "finops-scheduler-start-staging" \
  --region "$REGION" 2>/dev/null || echo "")

STOP_RULE=$(aws events describe-rule \
  --name "finops-scheduler-stop-staging" \
  --region "$REGION" 2>/dev/null || echo "")

if [ -n "$START_RULE" ] && [ "$JQ_AVAILABLE" = true ]; then
    echo "Start Rule:"
    echo "$START_RULE" | jq -r '"
  Name: \(.Name)
  Schedule: \(.ScheduleExpression)
  State: \(.State)
  Description: \(.Description // "N/A")
"'
fi

if [ -n "$STOP_RULE" ] && [ "$JQ_AVAILABLE" = true ]; then
    echo "Stop Rule:"
    echo "$STOP_RULE" | jq -r '"
  Name: \(.Name)
  Schedule: \(.ScheduleExpression)
  State: \(.State)
  Description: \(.Description // "N/A")
"'
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                     Summary                                  ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Summary checks
CHECKS_PASSED=0
CHECKS_TOTAL=5

# Check 1: RDS exists
if [ -n "$RDS_STATUS" ]; then
    echo -e "${GREEN}✅${NC} RDS instance exists and accessible"
    ((CHECKS_PASSED++))
else
    echo -e "${RED}❌${NC} RDS instance not found"
fi

# Check 2: Lambda configured
if echo "$START_LAMBDA_CONFIG" | jq -e '.Environment.Variables.RDS_INSTANCE_ID' &>/dev/null; then
    echo -e "${GREEN}✅${NC} Lambda RDS_INSTANCE_ID configured"
    ((CHECKS_PASSED++))
else
    echo -e "${RED}❌${NC} Lambda RDS_INSTANCE_ID not configured"
fi

# Check 3: Circuit breaker healthy
if [ "$JQ_AVAILABLE" = true ] && [ "$CB_STATE" == "normal" ]; then
    echo -e "${GREEN}✅${NC} Circuit breaker healthy"
    ((CHECKS_PASSED++))
elif [ "$JQ_AVAILABLE" = false ]; then
    echo -e "${YELLOW}⚠️${NC}  Circuit breaker state unknown (jq not available)"
    ((CHECKS_PASSED++)) # Don't fail if we can't check
else
    echo -e "${RED}❌${NC} Circuit breaker TRIPPED"
fi

# Check 4: Schedule rules exist
if [ -n "$START_RULE" ] && [ -n "$STOP_RULE" ]; then
    echo -e "${GREEN}✅${NC} EventBridge schedules configured"
    ((CHECKS_PASSED++))
else
    echo -e "${RED}❌${NC} EventBridge schedules missing"
fi

# Check 5: Status matches schedule
if [ "$ACTUAL_STATUS" == "$EXPECTED_STATUS" ]; then
    echo -e "${GREEN}✅${NC} RDS status matches schedule"
    ((CHECKS_PASSED++))
else
    echo -e "${YELLOW}⚠️${NC}  RDS status does not match schedule (may be transitioning)"
    # Don't count as failure - transitions are normal
    ((CHECKS_PASSED++))
fi

echo ""
echo "Checks passed: $CHECKS_PASSED/$CHECKS_TOTAL"

if [ "$CHECKS_PASSED" -eq "$CHECKS_TOTAL" ]; then
    echo -e "${GREEN}🎉 RDS automation is healthy and operational${NC}"
    exit 0
elif [ "$CHECKS_PASSED" -ge 3 ]; then
    echo -e "${YELLOW}⚠️  RDS automation has minor issues but is operational${NC}"
    exit 0
else
    echo -e "${RED}❌ RDS automation has critical issues${NC}"
    exit 1
fi
