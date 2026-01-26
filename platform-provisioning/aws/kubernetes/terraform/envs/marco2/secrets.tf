# -----------------------------------------------------------------------------
# AWS Secrets Manager - Platform Services Secrets
# Descrição: Gerenciamento seguro de senhas e credenciais sensíveis
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Grafana Admin Password Secret
# -----------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "grafana_admin_password" {
  name        = "k8s-platform-prod/grafana-admin-password"
  description = "Senha de administrador do Grafana no cluster k8s-platform-prod"

  recovery_window_in_days = 7

  tags = {
    Environment = "production"
    Project     = "k8s-platform"
    Marco       = "marco2"
    ManagedBy   = "terraform"
    Service     = "monitoring"
    Component   = "grafana"
  }
}

resource "aws_secretsmanager_secret_version" "grafana_admin_password" {
  secret_id     = aws_secretsmanager_secret.grafana_admin_password.id
  secret_string = var.grafana_admin_password
}

# -----------------------------------------------------------------------------
# Data Source para recuperar o secret (para uso em outros módulos)
# -----------------------------------------------------------------------------

data "aws_secretsmanager_secret_version" "grafana_admin_password" {
  secret_id  = aws_secretsmanager_secret.grafana_admin_password.id
  depends_on = [aws_secretsmanager_secret_version.grafana_admin_password]
}
