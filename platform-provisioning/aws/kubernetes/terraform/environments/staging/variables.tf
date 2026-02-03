# STAGING Environment Variables Definition

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for resources"
  type        = string
}

variable "state_bucket" {
  description = "S3 bucket for Terraform state"
  type        = string
}

variable "base_tags" {
  description = "Base tags applied to all resources"
  type        = map(string)
}

#------------------------------------------------------------------------------
# PostgreSQL RDS Variables
#------------------------------------------------------------------------------

variable "postgresql_instance_class" {
  description = "RDS instance class for PostgreSQL"
  type        = string
  default     = "db.t3.micro"
}

variable "postgresql_allocated_storage" {
  description = "Initial storage allocation in GB"
  type        = number
  default     = 20
}

variable "postgresql_max_allocated_storage" {
  description = "Maximum storage allocation in GB"
  type        = number
  default     = 50
}

#------------------------------------------------------------------------------
# Redis Variables
#------------------------------------------------------------------------------

variable "redis_replicas" {
  description = "Number of Redis replicas"
  type        = number
  default     = 1
}

variable "redis_pvc_size" {
  description = "PVC size for Redis"
  type        = string
  default     = "5Gi"
}

#------------------------------------------------------------------------------
# RabbitMQ Variables
#------------------------------------------------------------------------------

variable "rabbitmq_replicas" {
  description = "Number of RabbitMQ replicas"
  type        = number
  default     = 1
}

variable "rabbitmq_pvc_size" {
  description = "PVC size for RabbitMQ"
  type        = string
  default     = "5Gi"
}

#------------------------------------------------------------------------------
# FinOps Variables
#------------------------------------------------------------------------------

variable "finops_alert_email" {
  description = "Email for FinOps alerts"
  type        = string
}
