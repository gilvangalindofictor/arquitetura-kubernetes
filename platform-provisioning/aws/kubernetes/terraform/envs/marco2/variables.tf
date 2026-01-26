# -----------------------------------------------------------------------------
# Variables - Marco 2 Environment
# -----------------------------------------------------------------------------

variable "region" {
  description = "Região AWS"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC"
  type        = string
}
