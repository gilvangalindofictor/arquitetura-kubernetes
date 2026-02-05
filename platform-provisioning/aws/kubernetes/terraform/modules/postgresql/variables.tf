variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs for Security Group ingress (least privilege)"
  type        = list(string)
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.small"  # FinOps: Start small, scale up when needed ($315.36/year saved)
}

variable "allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 100
}

variable "max_allocated_storage" {
  description = "Max allocated storage in GB"
  type        = number
  default     = 500
}

variable "common_tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}

variable "additional_databases" {
  description = "List of additional databases to create (with user/password)"
  type = list(object({
    name     = string
    username = string
    password = string
  }))
  default = []
}
