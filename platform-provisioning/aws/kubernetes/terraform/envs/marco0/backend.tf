terraform {
  backend "s3" {
    bucket         = "terraform-state-marco0-891377105802"
    key            = "marco0/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
