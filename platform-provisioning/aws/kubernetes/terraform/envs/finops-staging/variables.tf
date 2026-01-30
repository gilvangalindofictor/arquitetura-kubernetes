variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "k8s-platform-prod"
}

variable "rds_instance_identifier" {
  description = "RDS instance identifier"
  type        = string
  default     = "k8s-platform-prod-postgresql"
}

variable "asg_names" {
  description = "Auto Scaling Group names"
  type        = list(string)
  default = [
    "eks-critical-02ce02d9-0774-ad97-9aab-8c24c1479479",
    "eks-system-a8ce02d9-0774-d561-d896-d70f87493bc5",
    "eks-workloads-b4ce02d9-0776-c3d4-0fd8-ef599f0ab69d"
  ]
}
