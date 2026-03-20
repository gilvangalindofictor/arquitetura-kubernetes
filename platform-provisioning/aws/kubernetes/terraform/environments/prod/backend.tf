# Backend configuration for PROD environment
# S3 remote state with encryption and DynamoDB locking

terraform {
  backend "s3" {
    bucket         = "terraform-state-marco0-891377105802"
    key            = "environments/prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"

    # Profile for AWS SSO authentication
    # profile = "k8s-platform-prod" # COMMENTED-SSO-WORKAROUND
  }
}
