#!/bin/bash
# GAP-008: Store SonarQube exporter credentials in Vault
# Run ONCE after obtaining the token from SonarQube UI
# Prerequisites: vault CLI authenticated with write permission to secret/sonarqube/*

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-https://vault.staging.internal}"
SONARQUBE_TOKEN="${1:?Usage: $0 <sonarqube-token>}"
SONARQUBE_URL="https://sonarqube.staging.internal"

echo "[INFO] Writing SonarQube exporter credentials to Vault..."
vault kv put secret/sonarqube/prometheus-exporter \
  token="${SONARQUBE_TOKEN}" \
  url="${SONARQUBE_URL}"

echo "[OK] Secret written to secret/sonarqube/prometheus-exporter"
echo "[INFO] Now apply ExternalSecret to sync to Kubernetes:"
echo "       kubectl apply -f external-secret.yaml"
