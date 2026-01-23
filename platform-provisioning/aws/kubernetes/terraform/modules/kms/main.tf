// Módulo esqueleto: KMS key para a plataforma
variable "alias" { type = string }

resource "aws_kms_key" "platform" {
  description             = "KMS key para k8s-platform"
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "platform_alias" {
  name          = var.alias
  target_key_id = aws_kms_key.platform.key_id
}

output "kms_key_id" { value = aws_kms_key.platform.key_id }
output "kms_alias" { value = aws_kms_alias.platform_alias.name }
