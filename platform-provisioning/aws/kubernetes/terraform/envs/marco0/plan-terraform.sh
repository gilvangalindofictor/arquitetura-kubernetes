#!/usr/bin/env bash
set -euo pipefail

# plan-terraform.sh
# Script para executar terraform plan com backend remoto S3
# Este script carrega as credenciais AWS automaticamente e executa terraform plan
#
# Uso: ./plan-terraform.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Terraform Plan - Marco 0 ==="
echo ""

# Função para carregar credenciais do cache do AWS CLI
load_aws_credentials() {
  # Verifica se há credenciais no cache do AWS CLI login
  if [ -d "$HOME/.aws/login/cache" ]; then
    # Pega o arquivo de credenciais mais recente
    CRED_FILE=$(ls -t "$HOME/.aws/login/cache"/*.json 2>/dev/null | head -1)

    if [ -n "$CRED_FILE" ]; then
      echo "[INFO] Carregando credenciais do cache AWS..."

      # Extrai credenciais do JSON usando jq (se disponível) ou python
      if command -v jq &> /dev/null; then
        export AWS_ACCESS_KEY_ID=$(jq -r '.accessToken.accessKeyId' "$CRED_FILE")
        export AWS_SECRET_ACCESS_KEY=$(jq -r '.accessToken.secretAccessKey' "$CRED_FILE")
        export AWS_SESSION_TOKEN=$(jq -r '.accessToken.sessionToken' "$CRED_FILE")
      elif command -v python3 &> /dev/null; then
        export AWS_ACCESS_KEY_ID=$(python3 -c "import json; print(json.load(open('$CRED_FILE'))['accessToken']['accessKeyId'])")
        export AWS_SECRET_ACCESS_KEY=$(python3 -c "import json; print(json.load(open('$CRED_FILE'))['accessToken']['secretAccessKey'])")
        export AWS_SESSION_TOKEN=$(python3 -c "import json; print(json.load(open('$CRED_FILE'))['accessToken']['sessionToken'])")
      else
        echo "[WARNING] jq ou python3 não encontrado. Usando credenciais do AWS CLI padrão."
        return 1
      fi

      export AWS_DEFAULT_REGION="us-east-1"
      echo "[INFO] Credenciais carregadas com sucesso"
      return 0
    fi
  fi

  # Se não encontrou no cache, tenta usar credenciais padrão do AWS CLI
  echo "[INFO] Usando credenciais padrão do AWS CLI"
  export AWS_DEFAULT_REGION="us-east-1"
  return 0
}

# Carrega credenciais
load_aws_credentials

# Verifica se tem credenciais configuradas
echo ""
echo "[CHECK] Verificando credenciais AWS..."
if aws sts get-caller-identity &>/dev/null; then
  echo "[OK] Credenciais AWS válidas"
  aws sts get-caller-identity
else
  echo "[ERROR] Credenciais AWS não configuradas ou inválidas"
  echo "Execute: aws configure ou aws sso login"
  exit 1
fi

echo ""
echo "[STEP] Executando terraform plan..."
echo ""

terraform plan "$@"

echo ""
echo "[INFO] Plan concluído!"
echo ""
