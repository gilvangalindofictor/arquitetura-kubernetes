#!/usr/bin/env bash
set -euo pipefail

# 01-marco0-incremental-add-region.sh
# Esboço: script para preparar terraform incremental para adicionar us-east-1c (modo dry-run disponível)
# Uso: ./01-marco0-incremental-add-region.sh --out-dir ./marco0-incremental-1c --dry-run

OUT_DIR="./marco0-incremental-1c"
DRY_RUN=true
REGION=us-east-1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --apply) DRY_RUN=false; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) echo "Usage: $0 [--out-dir DIR] [--region REGION] [--dry-run|--apply]"; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

mkdir -p "$OUT_DIR/modules/subnets"
mkdir -p "$OUT_DIR/modules/route-tables"
mkdir -p "$OUT_DIR/modules/nat-gateway"

cat > "$OUT_DIR/README.md" <<EOF
Marco 0 - Incremental (us-east-1c)

Conteúdo gerado (esqueleto):
- modules/subnets/       -> módulo para criar 3 subnets em us-east-1c
- modules/route-tables/  -> rotas dedicadas para 1c
- modules/nat-gateway/   -> (opcional) NAT gateway 1c

Uso (dry-run):
  cd $OUT_DIR
  terraform init
  terraform plan

Para aplicar, executar com --apply
EOF

cat > "$OUT_DIR/main.tf" <<'TF'
// Placeholder main.tf - adicionar módulos reais gerados pela engenharia reversa
terraform {
  required_version = ">= 1.0"
}

provider "aws" {
  region = "us-east-1"
}

// Exemplo de chamada de módulo (substituir por implementação real)
module "subnets_1c" {
  source = "./modules/subnets"
}

TF

if [ "$DRY_RUN" = true ]; then
  echo "[INFO] Dry-run: esqueleto criado em $OUT_DIR. Revise e execute 'terraform plan' localmente."
else
  echo "[TODO] Implementar terraform apply flow. Este script atualmente cria esqueleto apenas."
fi
