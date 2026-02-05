#!/bin/bash
# Harbor Robot Account Creation Script
# Creates a robot account for CI/CD pipelines to push images

set -e

HARBOR_URL="${HARBOR_URL:-http://harbor-core.harbor-system.svc.cluster.local}"
HARBOR_ADMIN_USER="${HARBOR_ADMIN_USER:-admin}"
HARBOR_ADMIN_PASSWORD="${HARBOR_ADMIN_PASSWORD}"
ROBOT_NAME="${ROBOT_NAME:-gitlab-ci}"
PROJECT_NAME="${PROJECT_NAME:-library}"

if [ -z "$HARBOR_ADMIN_PASSWORD" ]; then
  echo "❌ HARBOR_ADMIN_PASSWORD not set"
  echo "Usage: HARBOR_ADMIN_PASSWORD=\$(kubectl get secret harbor-admin-password -n harbor-system -o jsonpath='{.data.password}' | base64 -d) $0"
  exit 1
fi

echo "=== Harbor Robot Account Setup ==="
echo "Harbor URL: $HARBOR_URL"
echo "Project: $PROJECT_NAME"
echo "Robot Name: $ROBOT_NAME"
echo ""

# Wait for Harbor to be ready
echo "Waiting for Harbor API..."
until curl -s -o /dev/null -w "%{http_code}" "$HARBOR_URL/api/v2.0/health" | grep -q "200"; do
  echo "  Harbor not ready yet, retrying in 5s..."
  sleep 5
done

echo "✓ Harbor API is responding"

# Check if project exists
echo "Checking project '$PROJECT_NAME'..."

PROJECT_ID=$(curl -s -u "$HARBOR_ADMIN_USER:$HARBOR_ADMIN_PASSWORD" \
  "$HARBOR_URL/api/v2.0/projects?name=$PROJECT_NAME" | \
  jq -r '.[0].project_id // empty')

if [ -z "$PROJECT_ID" ]; then
  echo "Creating project '$PROJECT_NAME'..."

  PROJECT_ID=$(curl -s -X POST -u "$HARBOR_ADMIN_USER:$HARBOR_ADMIN_PASSWORD" \
    -H "Content-Type: application/json" \
    "$HARBOR_URL/api/v2.0/projects" \
    -d "{
      \"project_name\": \"$PROJECT_NAME\",
      \"metadata\": {
        \"public\": \"false\",
        \"enable_content_trust\": \"false\",
        \"auto_scan\": \"true\",
        \"severity\": \"low\",
        \"reuse_sys_cve_allowlist\": \"true\"
      }
    }" | jq -r '.project_id // empty')

  if [ -z "$PROJECT_ID" ]; then
    echo "❌ Failed to create project"
    exit 1
  fi

  echo "✓ Project created with ID: $PROJECT_ID"
else
  echo "✓ Project exists with ID: $PROJECT_ID"
fi

# Check if robot account already exists
echo "Checking robot account 'robot\$$ROBOT_NAME'..."

ROBOT_EXISTS=$(curl -s -u "$HARBOR_ADMIN_USER:$HARBOR_ADMIN_PASSWORD" \
  "$HARBOR_URL/api/v2.0/robots" | \
  jq -r ".[] | select(.name==\"robot\$$ROBOT_NAME\") | .id // empty")

if [ -n "$ROBOT_EXISTS" ]; then
  echo "⚠️  Robot account already exists (ID: $ROBOT_EXISTS)"
  echo "   To recreate, delete it first via Harbor UI"
  exit 0
fi

echo "Creating robot account..."

ROBOT_RESPONSE=$(curl -s -X POST -u "$HARBOR_ADMIN_USER:$HARBOR_ADMIN_PASSWORD" \
  -H "Content-Type: application/json" \
  "$HARBOR_URL/api/v2.0/robots" \
  -d "{
    \"name\": \"$ROBOT_NAME\",
    \"description\": \"Robot account for GitLab CI/CD pipeline\",
    \"duration\": -1,
    \"level\": \"project\",
    \"disable\": false,
    \"permissions\": [{
      \"kind\": \"project\",
      \"namespace\": \"$PROJECT_NAME\",
      \"access\": [{
        \"resource\": \"repository\",
        \"action\": \"push\"
      },{
        \"resource\": \"repository\",
        \"action\": \"pull\"
      },{
        \"resource\": \"artifact\",
        \"action\": \"delete\"
      }]
    }]
  }")

ROBOT_ID=$(echo "$ROBOT_RESPONSE" | jq -r '.id // empty')
ROBOT_SECRET=$(echo "$ROBOT_RESPONSE" | jq -r '.secret // empty')

if [ -z "$ROBOT_ID" ] || [ -z "$ROBOT_SECRET" ]; then
  echo "❌ Failed to create robot account"
  echo "$ROBOT_RESPONSE"
  exit 1
fi

echo "✓ Robot account created successfully"
echo ""
echo "=== IMPORTANT: Save these credentials ==="
echo "Robot ID: $ROBOT_ID"
echo "Robot Name: robot\$$ROBOT_NAME"
echo "Robot Secret: $ROBOT_SECRET"
echo ""
echo "=== Docker login command ==="
echo "docker login $HARBOR_URL -u 'robot\$$ROBOT_NAME' -p '$ROBOT_SECRET'"
echo ""
echo "=== Kubernetes secret creation ==="
echo "kubectl create secret docker-registry harbor-registry \\"
echo "  --docker-server=$HARBOR_URL \\"
echo "  --docker-username='robot\$$ROBOT_NAME' \\"
echo "  --docker-password='$ROBOT_SECRET' \\"
echo "  --namespace=<your-namespace>"
echo ""
echo "✓ Setup complete"
