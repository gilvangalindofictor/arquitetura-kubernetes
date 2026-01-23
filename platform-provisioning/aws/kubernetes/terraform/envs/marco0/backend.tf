terraform {
  backend "s3" {
    # Valores preenchidos via terraform.tfvars ou -backend-config
    # bucket, key, region, dynamodb_table
  }
}
