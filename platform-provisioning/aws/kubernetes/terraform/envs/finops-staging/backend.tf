terraform {
  backend "s3" {
    bucket  = "terraform-state-marco0-891377105802"
    key     = "finops-staging/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
