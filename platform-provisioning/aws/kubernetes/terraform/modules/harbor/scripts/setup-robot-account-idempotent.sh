#!/bin/bash
# Setup Harbor Robot Account (Idempotent)
# Creates robot account for GitLab CI/CD with push/pull permissions
# Usage: ./setup-robot-account-idempotent.sh [HARBOR_URL] [ADMIN_PASSWORD]

set -e

HARBOR_URL=${1:-"http://harbor.harbor-system.svc.cluster.local"}
ADMIN_USER="admin"
ADMIN_PASSWORD=${2:-"Harbor12345"}
PROJECT_NAME="library"
ROBOT_NAME="gitlab-ci"
ROBOT_FULL_NAME="robot\$${ROBOT_NAME}"

echo "🤖 Harbor Robot Account Setup (Idempotent)"
echo "=========================================="
echo "Harbor URL: $HARBOR_URL"
echo "Project: $PROJECT_NAME"
echo "Robot: $ROBOT_FULL_NAME"
echo ""

# Check if robot account already exists
echo "🔍 Checking if robot account exists..."
EXISTING_ROBOT=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASSWORD}" \
  "${HARBOR_URL}/api/v2.0/projects/${PROJECT_NAME}/robots" | \
  jq -r ".[] | select(.name == \"${ROBOT_FULL_NAME}\") | .name" || echo "")

if [ -n "$EXISTING_ROBOT" ]; then
  echo "✅ Robot account already exists: $ROBOT_FULL_NAME"
  echo ""
  echo "⚠️  To regenerate token, delete existing robot first:"
  echo "    curl -X DELETE -u admin:PASSWORD \\"
  echo "      ${HARBOR_URL}/api/v2.0/projects/${PROJECT_NAME}/robots/<ROBOT_ID>"
  exit 0
fi

# Create robot account
echo "📝 Creating robot account..."
ROBOT_RESPONSE=$(curl -s -X POST -u "${ADMIN_USER}:${ADMIN_PASSWORD}" \
  -H "Content-Type: application/json" \
  "${HARBOR_URL}/api/v2.0/projects/${PROJECT_NAME}/robots" \
  -d '{
    "name": "'"${ROBOT_NAME}"'",
    "description": "GitLab CI/CD robot account",
    "duration": -1,
    "level": "project",
    "permissions": [
      {
        "kind": "project",
        "namespace": "'"${PROJECT_NAME}"'",
        "access": [
          {"resource": "repository", "action": "push"},
          {"resource": "repository", "action": "pull"},
          {"resource": "artifact", "action": "delete"}
        ]
      }
    ]
  }')

ROBOT_ID=$(echo "$ROBOT_RESPONSE" | jq -r '.id')
ROBOT_SECRET=$(echo "$ROBOT_RESPONSE" | jq -r '.secret')

if [ -z "$ROBOT_ID" ] || [ "$ROBOT_ID" == "null" ]; then
  echo "❌ Failed to create robot account"
  echo "Response: $ROBOT_RESPONSE"
  exit 1
fi

echo "✅ Robot account created successfully!"
echo ""
echo "=========================================="
echo "📋 Robot Account Credentials"
echo "=========================================="
echo "Name:     $ROBOT_FULL_NAME"
echo "ID:       $ROBOT_ID"
echo "Secret:   $ROBOT_SECRET"
echo ""
echo "=========================================="
echo "🔐 Store in Vault:"
echo "=========================================="
echo "vault kv put secret/harbor/robot-account \\"
echo "  name=$ROBOT_FULL_NAME \\"
echo "  secret=$ROBOT_SECRET"
echo ""
echo "=========================================="
echo "🔧 GitLab CI/CD Variables:"
echo "=========================================="
echo "HARBOR_URL:      $HARBOR_URL"
echo "HARBOR_USER:     $ROBOT_FULL_NAME"
echo "HARBOR_PASSWORD: $ROBOT_SECRET"
echo ""
echo "=========================================="
echo "🧪 Test Docker Login:"
echo "=========================================="
echo "docker login $HARBOR_URL \\"
echo "  -u $ROBOT_FULL_NAME \\"
echo "  -p $ROBOT_SECRET"
echo ""
