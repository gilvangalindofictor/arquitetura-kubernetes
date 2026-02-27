# Backend configuration for Security Domain
# S3 remote state with encryption and DynamoDB locking
# Scoped to: CICD-003 Secret Rotation automation

terraform {
  backend "s3" {
    bucket         = "terraform-state-marco0-891377105802"
    key            = "domains/security/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"

    # Profile for AWS SSO authentication
    profile = "k8s-platform-prod"
  }
}
