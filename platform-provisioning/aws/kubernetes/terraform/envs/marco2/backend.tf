# -----------------------------------------------------------------------------
# Backend Configuration - Marco 2
# Armazena state no S3 com locking via DynamoDB
# -----------------------------------------------------------------------------

terraform {
  backend "s3" {
    bucket         = "terraform-state-marco0-891377105802"
    key            = "marco2/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
