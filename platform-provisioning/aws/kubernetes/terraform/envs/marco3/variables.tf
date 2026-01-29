variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

variable "vpc_id" {
  description = "VPC ID (fictor-vpc)"
  type        = string
}

# PostgreSQL variables
variable "postgresql_instance_class" {
  description = "PostgreSQL RDS instance class"
  type        = string
  default     = "db.t3.medium"
}

variable "postgresql_allocated_storage" {
  description = "PostgreSQL allocated storage in GB"
  type        = number
  default     = 100
}

variable "postgresql_max_allocated_storage" {
  description = "PostgreSQL max allocated storage in GB"
  type        = number
  default     = 500
}

# Redis variables
variable "redis_replicas" {
  description = "Number of Redis replicas"
  type        = number
  default     = 2
}

variable "redis_pvc_size" {
  description = "Redis PVC size"
  type        = string
  default     = "8Gi"
}

# RabbitMQ variables
variable "rabbitmq_replicas" {
  description = "Number of RabbitMQ nodes"
  type        = number
  default     = 3
}

variable "rabbitmq_pvc_size" {
  description = "RabbitMQ PVC size per node"
  type        = string
  default     = "10Gi"
}
