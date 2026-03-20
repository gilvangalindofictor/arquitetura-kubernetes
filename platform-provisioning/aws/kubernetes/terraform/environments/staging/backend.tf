# Backend configuration for STAGING environment
# S3 remote state with encryption and DynamoDB locking

terraform {
  backend "s3" {
    bucket         = "terraform-state-marco0-891377105802"
    key            = "environments/staging/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"

    # Profile for AWS SSO authentication
    # TEMP: Using k8s-platform-prod (same AWS account 891377105802)
    # profile = "k8s-platform-prod" # COMMENTED-SSO-WORKAROUND
  }
}
