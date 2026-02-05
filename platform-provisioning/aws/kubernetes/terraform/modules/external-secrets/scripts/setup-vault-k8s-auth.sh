#!/bin/bash
# Setup Vault Kubernetes Authentication for External Secrets Operator
# This script configures Vault to allow ESO to authenticate and read secrets

set -e

VAULT_ADDR="${VAULT_ADDR:-http://vault.vault-system.svc.cluster.local:8200}"
VAULT_TOKEN="${VAULT_TOKEN}"
K8S_HOST="${K8S_HOST:-https://kubernetes.default.svc:443}"
ESO_NAMESPACE="${ESO_NAMESPACE:-external-secrets-system}"
ESO_SA="${ESO_SA:-external-secrets}"

if [ -z "$VAULT_TOKEN" ]; then
  echo "ERROR: VAULT_TOKEN not set"
  echo "Usage: VAULT_TOKEN=<root-token> $0"
  exit 1
fi

echo "=== Vault Kubernetes Auth Setup for ESO ==="
echo "Vault Address: $VAULT_ADDR"
echo "K8s Host: $K8S_HOST"
echo "ESO Namespace: $ESO_NAMESPACE"
echo "ESO ServiceAccount: $ESO_SA"
echo ""

# Get Kubernetes CA cert and JWT token from ESO ServiceAccount
echo "Getting Kubernetes CA cert and SA token..."

K8S_CA_CERT=$(kubectl get cm kube-root-ca.crt -n "$ESO_NAMESPACE" -o jsonpath='{.data.ca\.crt}')
SA_JWT_TOKEN=$(kubectl create token "$ESO_SA" -n "$ESO_NAMESPACE" --duration=24h)

if [ -z "$K8S_CA_CERT" ] || [ -z "$SA_JWT_TOKEN" ]; then
  echo "ERROR: Failed to get K8s CA cert or SA token"
  exit 1
fi

echo "✓ K8s credentials obtained"

# Enable Kubernetes auth method in Vault
echo "Enabling Kubernetes auth method..."

vault auth enable -address="$VAULT_ADDR" kubernetes 2>/dev/null || {
  echo "  (already enabled)"
}

echo "✓ Kubernetes auth method enabled"

# Configure Kubernetes auth
echo "Configuring Kubernetes auth..."

vault write -address="$VAULT_ADDR" auth/kubernetes/config \
  kubernetes_host="$K8S_HOST" \
  kubernetes_ca_cert="$K8S_CA_CERT" \
  token_reviewer_jwt="$SA_JWT_TOKEN"

echo "✓ Kubernetes auth configured"

# Create Vault policy for ESO
echo "Creating Vault policy: eso-reader"

vault policy write -address="$VAULT_ADDR" eso-reader - <<EOF
# Allow ESO to read secrets from KV v2 secret engine
path "secret/data/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/*" {
  capabilities = ["read", "list"]
}

# Allow ESO to read database credentials
path "database/creds/*" {
  capabilities = ["read"]
}
EOF

echo "✓ Policy eso-reader created"

# Create Kubernetes auth role for ESO
echo "Creating Kubernetes auth role: eso-reader"

vault write -address="$VAULT_ADDR" auth/kubernetes/role/eso-reader \
  bound_service_account_names="$ESO_SA" \
  bound_service_account_namespaces="$ESO_NAMESPACE" \
  policies="eso-reader" \
  ttl="1h"

echo "✓ Role eso-reader created"

# Enable KV v2 secret engine (if not enabled)
echo "Enabling KV v2 secret engine..."

vault secrets enable -address="$VAULT_ADDR" -path=secret kv-v2 2>/dev/null || {
  echo "  (already enabled)"
}

echo "✓ KV v2 secret engine enabled"

# Create test secret
echo "Creating test secret: secret/data/test/hello"

vault kv put -address="$VAULT_ADDR" secret/test/hello \
  username="demo-user" \
  password="demo-password"

echo "✓ Test secret created"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Test ESO integration:"
echo "  kubectl apply -f - <<EOF"
echo "  apiVersion: external-secrets.io/v1beta1"
echo "  kind: ExternalSecret"
echo "  metadata:"
echo "    name: test-secret"
echo "    namespace: default"
echo "  spec:"
echo "    refreshInterval: 1h"
echo "    secretStoreRef:"
echo "      name: vault-backend"
echo "      kind: ClusterSecretStore"
echo "    target:"
echo "      name: test-secret"
echo "      creationPolicy: Owner"
echo "    data:"
echo "      - secretKey: username"
echo "        remoteRef:"
echo "          key: secret/data/test/hello"
echo "          property: username"
echo "      - secretKey: password"
echo "        remoteRef:"
echo "          key: secret/data/test/hello"
echo "          property: password"
echo "  EOF"
echo ""
echo "  kubectl get secret test-secret -o yaml"
echo ""
