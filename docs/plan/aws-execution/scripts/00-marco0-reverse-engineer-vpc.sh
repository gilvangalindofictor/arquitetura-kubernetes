#!/usr/bin/env bash
set -euo pipefail

# 00-marco0-reverse-engineer-vpc.sh
# Esboço: engenharia reversa da VPC existente - extrai recursos e gera JSONs brutos
# Uso: ./00-marco0-reverse-engineer-vpc.sh --vpc-id vpc-xxxx --out-dir ./vpc-reverse-output --dry-run

OUT_DIR="./vpc-reverse-output"
VPC_ID=""
DRY_RUN=true
REGION=us-east-1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vpc-id) VPC_ID="$2"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --apply) DRY_RUN=false; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) echo "Usage: $0 --vpc-id VPC_ID [--out-dir DIR] [--region REGION] [--dry-run|--apply]"; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [ -z "$VPC_ID" ]; then
  echo "ERROR: --vpc-id is required"
  exit 1
fi

mkdir -p "$OUT_DIR"

echo "[INFO] Region: $REGION, VPC: $VPC_ID, out: $OUT_DIR, dry-run: $DRY_RUN"

echo "[STEP] Descrevendo VPC..."
aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --region "$REGION" > "$OUT_DIR/vpc.json"

echo "[STEP] Descrevendo Subnets..."
aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC_ID" --region "$REGION" > "$OUT_DIR/subnets.json"

echo "[STEP] Descrevendo Route Tables..."
aws ec2 describe-route-tables --filters Name=vpc-id,Values="$VPC_ID" --region "$REGION" > "$OUT_DIR/route-tables.json"

echo "[STEP] Descrevendo Internet Gateways..."
aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values="$VPC_ID" --region "$REGION" > "$OUT_DIR/igw.json"

echo "[STEP] Descrevendo NAT Gateways..."
aws ec2 describe-nat-gateways --filter Name=vpc-id,Values="$VPC_ID" --region "$REGION" > "$OUT_DIR/nat-gateways.json"

echo "[STEP] Descrevendo Security Groups..."
aws ec2 describe-security-groups --filters Name=vpc-id,Values="$VPC_ID" --region "$REGION" > "$OUT_DIR/security-groups.json"

echo "[DONE] JSONs gerados em: $OUT_DIR"

if [ "$DRY_RUN" = true ]; then
  echo "[INFO] Dry-run mode: não gerarei código Terraform automaticamente. Revise os JSONs em $OUT_DIR e converta para módulos Terraform conforme processo."
else
  echo "[TODO] Aqui poderíamos invocar uma ferramenta de conversão (terraformer) ou gerar templates Terraform."
fi

echo "[NEXT] Sugerido: revisar $OUT_DIR/*.json e gerar 'vpc-reverse-engineered/terraform' com módulos modulares."
