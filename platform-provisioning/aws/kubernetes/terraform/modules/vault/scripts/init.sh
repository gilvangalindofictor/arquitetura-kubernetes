#!/bin/bash
# Vault Initialization Script
# Initializes Vault cluster and stores recovery keys in S3

set -e

VAULT_ADDR="${VAULT_ADDR:-http://vault.vault-system.svc.cluster.local:8200}"
NAMESPACE="${VAULT_NAMESPACE:-vault-system}"
S3_BUCKET="${VAULT_S3_BUCKET}"

echo "=== Vault Initialization Script ==="
echo "Vault Address: $VAULT_ADDR"
echo "Namespace: $NAMESPACE"

# Wait for Vault to be ready
echo "Waiting for Vault service..."
until curl -s -o /dev/null -w "%{http_code}" "$VAULT_ADDR/v1/sys/health" | grep -q "50[123]"; do
  echo "  Vault not ready yet, retrying in 5s..."
  sleep 5
done

echo "✓ Vault service is responding"

# Check if Vault is already initialized
INIT_STATUS=$(curl -s "$VAULT_ADDR/v1/sys/init" | jq -r '.initialized')

if [ "$INIT_STATUS" = "true" ]; then
  echo "✓ Vault is already initialized"
  echo "  Checking unseal status..."

  SEAL_STATUS=$(curl -s "$VAULT_ADDR/v1/sys/seal-status" | jq -r '.sealed')

  if [ "$SEAL_STATUS" = "false" ]; then
    echo "✓ Vault is unsealed (KMS auto-unseal working)"
  else
    echo "✗ Vault is sealed! Check KMS permissions"
    exit 1
  fi

  exit 0
fi

echo "Initializing Vault..."

# Initialize Vault with recovery keys (KMS auto-unseal)
INIT_OUTPUT=$(curl -s -X POST "$VAULT_ADDR/v1/sys/init" \
  -d '{
    "recovery_shares": 5,
    "recovery_threshold": 3
  }')

ROOT_TOKEN=$(echo "$INIT_OUTPUT" | jq -r '.root_token')
RECOVERY_KEYS=$(echo "$INIT_OUTPUT" | jq -r '.recovery_keys[]')

if [ -z "$ROOT_TOKEN" ]; then
  echo "✗ Failed to initialize Vault"
  echo "$INIT_OUTPUT"
  exit 1
fi

echo "✓ Vault initialized successfully"
echo ""
echo "=== IMPORTANT: Save these recovery keys in a secure location ==="
echo "Recovery Keys:"
echo "$RECOVERY_KEYS"
echo ""
echo "Root Token: $ROOT_TOKEN"
echo ""
echo "=== End of sensitive data ==="
echo ""

# Store recovery keys in S3 (encrypted)
if [ -n "$S3_BUCKET" ]; then
  echo "Storing recovery keys in S3: s3://$S3_BUCKET/vault-recovery-keys.json"

  echo "$INIT_OUTPUT" | aws s3 cp - "s3://$S3_BUCKET/vault-recovery-keys.json" \
    --server-side-encryption AES256 \
    --metadata "initialized-at=$(date -Iseconds)"

  echo "✓ Recovery keys stored in S3"
else
  echo "⚠️  S3_BUCKET not set, recovery keys NOT stored in S3"
  echo "   Make sure to save the recovery keys manually!"
fi

# Store root token in Kubernetes secret (temporary - should be rotated)
echo "Storing root token in Kubernetes secret..."

kubectl create secret generic vault-root-token \
  --from-literal=token="$ROOT_TOKEN" \
  --namespace="$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Root token stored in secret vault-root-token"
echo ""
echo "=== Next Steps ==="
echo "1. Rotate the root token: vault token create -orphan -policy=root"
echo "2. Enable auth methods: vault auth enable kubernetes"
echo "3. Configure policies and roles"
echo "4. Delete the vault-root-token secret after setup"
echo ""
echo "✓ Vault initialization complete"
