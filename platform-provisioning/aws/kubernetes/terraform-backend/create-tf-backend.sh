#!/usr/bin/env bash
set -euo pipefail

# create-tf-backend.sh
# Bootstrap script para criar S3 bucket e DynamoDB table para backend Terraform
# Uso: BUCKET_NAME=my-tf-state DYNAMO_TABLE=terraform-state-lock ./create-tf-backend.sh --region us-east-1 --yes

REGION="us-east-1"
BUCKET_NAME=""
DYNAMO_TABLE="terraform-state-lock"
CONFIRM=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region) REGION="$2"; shift 2 ;;
    --bucket) BUCKET_NAME="$2"; shift 2 ;;
    --dynamo-table) DYNAMO_TABLE="$2"; shift 2 ;;
    --yes) CONFIRM=true; shift ;;
    -h|--help) echo "Usage: $0 --bucket BUCKET_NAME [--dynamo-table NAME] [--region REGION] [--yes]"; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [ -z "$BUCKET_NAME" ]; then
  echo "ERROR: --bucket BUCKET_NAME is required or set BUCKET_NAME env var"
  exit 1
fi

echo "[INFO] Region: $REGION"
echo "[INFO] Bucket: $BUCKET_NAME"
echo "[INFO] DynamoDB Table: $DYNAMO_TABLE"

if [ "$CONFIRM" = false ]; then
  read -p "Proceed to create S3 bucket and DynamoDB table? (y/N) " RESP
  if [[ ! $RESP =~ ^[Yy]$ ]]; then
    echo "Aborting"
    exit 0
  fi
fi

echo "[STEP] Creating S3 bucket (if not exists)"
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "  Bucket already exists: $BUCKET_NAME"
else
  if [ "$REGION" = "us-east-1" ]; then
    # us-east-1 não aceita LocationConstraint
    aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION"
  else
    aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION" --create-bucket-configuration LocationConstraint=$REGION
  fi
  echo "  Bucket created: $BUCKET_NAME"
fi

echo "[STEP] Enabling versioning and encryption"
aws s3api put-bucket-versioning --bucket "$BUCKET_NAME" --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$BUCKET_NAME" --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

echo "[STEP] Blocking public access"
aws s3api put-public-access-block --bucket "$BUCKET_NAME" --public-access-block-configuration '{"BlockPublicAcls":true,"IgnorePublicAcls":true,"BlockPublicPolicy":true,"RestrictPublicBuckets":true}'

echo "[STEP] Creating DynamoDB table for state locking (if not exists)"
if aws dynamodb describe-table --table-name "$DYNAMO_TABLE" --region "$REGION" 2>/dev/null >/dev/null; then
  echo "  Table already exists: $DYNAMO_TABLE"
else
  aws dynamodb create-table \
    --table-name "$DYNAMO_TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION"
  echo "  Table created: $DYNAMO_TABLE"
  echo "  Waiting for table to become ACTIVE..."
  aws dynamodb wait table-exists --table-name "$DYNAMO_TABLE" --region "$REGION"
  echo "  Table is now ACTIVE"
fi

echo "[DONE] Backend prepared. Configure your Terraform backend as:

terraform {
  backend \"s3\" {
    bucket = \"$BUCKET_NAME\"
    key    = \"marco0/terraform.tfstate\"
    region = \"$REGION\"
    encrypt = true
    dynamodb_table = \"$DYNAMO_TABLE\"
  }
}
"
