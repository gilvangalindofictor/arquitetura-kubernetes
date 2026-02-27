#!/bin/bash

# This script initializes the LocalStack environment for the observability project.
# It configures the AWS CLI and creates the necessary S3 buckets.

# --- Colors for output ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}--- Configuring AWS CLI profile for LocalStack ---${NC}"

aws configure set aws_access_key_id "test" --profile localstack
aws configure set aws_secret_access_key "test" --profile localstack
aws configure set region "us-east-1" --profile localstack
aws configure set output "json" --profile localstack

echo -e "${GREEN}✔ AWS CLI 'localstack' profile configured.${NC}\n"

# Alias for aws cli to target localstack
alias awslocal='aws --endpoint-url=http://localhost:4566 --profile=localstack'

echo -e "${YELLOW}--- Creating S3 buckets in LocalStack ---${NC}"

# Bucket names from terraform/variables.tf
LOKI_BUCKET="observabilidade-loki-data"
TEMPO_BUCKET="observabilidade-tempo-data"
GRAFANA_BUCKET="observabilidade-grafana-backup"

awslocal s3 mb "s3://${LOKI_BUCKET}"
if [ $? -eq 0 ]; then echo -e "${GREEN}✔ Bucket '${LOKI_BUCKET}' created.${NC}"; else echo -e "${RED}✖ Failed to create bucket '${LOKI_BUCKET}'.${NC}"; fi

awslocal s3 mb "s3://${TEMPO_BUCKET}"
if [ $? -eq 0 ]; then echo -e "${GREEN}✔ Bucket '${TEMPO_BUCKET}' created.${NC}"; else echo -e "${RED}✖ Failed to create bucket '${TEMPO_BUCKET}'.${NC}"; fi

awslocal s3 mb "s3://${GRAFANA_BUCKET}"
if [ $? -eq 0 ]; then echo -e "${GREEN}✔ Bucket '${GRAFANA_BUCKET}' created.${NC}"; else echo -e "${RED}✖ Failed to create bucket '${GRAFANA_BUCKET}'.${NC}"; fi

echo -e "\n${GREEN}LocalStack initialization complete! You can now proceed with Terraform.${NC}"
