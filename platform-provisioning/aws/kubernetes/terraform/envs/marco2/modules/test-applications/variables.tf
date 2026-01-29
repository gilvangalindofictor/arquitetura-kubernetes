# Variables for Test Applications Module

variable "namespace" {
  description = "Namespace para test applications"
  type        = string
  default     = "test-apps"
}

variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
}

variable "tags" {
  description = "Tags para recursos AWS"
  type        = map(string)
  default     = {}
}
