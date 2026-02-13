variable "repositories" {
  description = "Map of ECR repositories to create with their configurations"
  type = map(object({
    image_tag_mutability      = string
    scan_on_push              = bool
    encryption_type           = string
    kms_key_arn               = optional(string)
    allow_cross_account_pull  = optional(bool, false)
    trusted_account_ids       = optional(list(string), [])
  }))
  default = {}
}

variable "environment" {
  description = "Environment name (staging, production)"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "untagged_expiration_days" {
  description = "Number of days after which untagged images expire"
  type        = number
  default     = 7
}

variable "tagged_image_count" {
  description = "Maximum number of tagged images to keep per prefix"
  type        = number
  default     = 10
}
