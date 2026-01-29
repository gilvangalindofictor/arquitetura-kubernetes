terraform {
  backend "s3" {
    bucket  = "terraform-state-marco0-891377105802"
    key     = "marco3/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
