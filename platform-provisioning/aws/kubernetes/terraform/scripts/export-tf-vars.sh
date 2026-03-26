#!/usr/bin/env bash
# =============================================================================
# export-tf-vars.sh — Substituto do secrets.auto.tfvars (GAP-TF-006)
# =============================================================================
#
# PROBLEMA (GAP-TF-006):
#   secrets.auto.tfvars em staging e prod continha tokens Vault e PATs Docker Hub
#   em texto plano. Mesmo git-ignorado, esse padrão é inseguro: exposição acidental
#   via grep, log, IDE, CI runner com artefatos, etc.
#
# SOLUÇÃO:
#   Este script lê os secrets do AWS Secrets Manager e os exporta como TF_VAR_*,
#   que o Terraform lê automaticamente (precedência sobre *.auto.tfvars).
#   Nenhum valor sensível é escrito em disco.
#
# USO LOCAL (developer):
#   source scripts/export-tf-vars.sh staging
#   source scripts/export-tf-vars.sh prod
#   terraform plan -var-file=terraform.tfvars
#
# USO CI/CD (GitLab CI / GitHub Actions):
#   - O runner deve ter permissão IAM: secretsmanager:GetSecretValue
#   - Adicionar no job before_script:
#       source platform-provisioning/aws/kubernetes/terraform/scripts/export-tf-vars.sh $TF_ENV
#
# PRÉ-REQUISITOS:
#   - AWS CLI v2 instalado e configurado (SSO ou role)
#   - jq instalado
#   - Permissão IAM: secretsmanager:GetSecretValue nos secrets abaixo
#
# SECRETS MANAGER PATHS (AWS):
#   staging:
#     k8s-platform/staging/vault          → vault_root_token
#     k8s-platform/staging/dockerhub      → docker_hub_username, docker_hub_access_token
#     k8s-platform/staging/grafana        → grafana_oidc_client_secret, grafana_admin_password
#     k8s-platform/staging/sonarqube      → sonarqube_postgresql_password
#     k8s-platform/staging/harbor         → harbor_postgresql_password, harbor_admin_password, harbor_redis_password
#     k8s-platform/staging/argocd         → argocd_postgresql_password, argocd_oidc_client_secret
#     k8s-platform/staging/keycloak       → keycloak_postgresql_password, keycloak_admin_password
#     k8s-platform/staging/backstage      → backstage_db_password, backstage_keycloak_client_secret,
#                                            backstage_gitlab_token, backstage_argocd_token,
#                                            backstage_sonarqube_token, backstage_auth_session_secret,
#                                            backstage_harbor_robot_token
#     k8s-platform/staging/hatch-etl      → hatch_etl_db_password, hatch_etl_redis_password,
#                                            hatch_etl_api_username, hatch_etl_api_password
#   prod:
#     k8s-platform/prod/vault             → vault_root_token
#     k8s-platform/prod/grafana           → grafana_oidc_client_secret, grafana_admin_password
#     k8s-platform/prod/sonarqube         → sonarqube_postgresql_password
#     k8s-platform/prod/harbor            → harbor_postgresql_password, harbor_admin_password, harbor_redis_password
#     k8s-platform/prod/argocd            → argocd_postgresql_password, argocd_oidc_client_secret
#     k8s-platform/prod/keycloak          → keycloak_postgresql_password, keycloak_admin_password
#     k8s-platform/prod/vault-oidc        → vault_oidc_client_secret
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log()  { echo "[export-tf-vars] $*" >&2; }
err()  { echo "[export-tf-vars] ERROR: $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || err "Comando '$1' não encontrado. Instale e tente novamente."
}

# Lê um secret do AWS Secrets Manager e retorna o JSON completo
get_secret() {
  local secret_name="$1"
  aws secretsmanager get-secret-value \
    --secret-id "$secret_name" \
    --query SecretString \
    --output text 2>/dev/null || {
    log "AVISO: Secret '$secret_name' não encontrado ou sem permissão. Variáveis correspondentes não serão exportadas."
    echo "{}"
  }
}

# Exporta uma chave JSON como TF_VAR_*
export_var() {
  local tf_var_name="$1"
  local json_payload="$2"
  local json_key="${3:-$1}"

  local value
  value=$(echo "$json_payload" | jq -r --arg k "$json_key" '.[$k] // empty')

  if [[ -z "$value" ]]; then
    log "AVISO: chave '$json_key' ausente no secret — TF_VAR_${tf_var_name} não exportado."
    return 0
  fi

  export "TF_VAR_${tf_var_name}=${value}"
  log "  ✓ TF_VAR_${tf_var_name} exportado"
}

# ---------------------------------------------------------------------------
# Validações
# ---------------------------------------------------------------------------

require_cmd aws
require_cmd jq

ENV="${1:-}"
if [[ -z "$ENV" ]]; then
  err "Ambiente não especificado. Uso: source export-tf-vars.sh <staging|prod>"
fi

if [[ "$ENV" != "staging" && "$ENV" != "prod" ]]; then
  err "Ambiente inválido: '$ENV'. Use 'staging' ou 'prod'."
fi

AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
log "Carregando TF_VAR_* para ambiente: $ENV (região: $AWS_REGION)"

# ---------------------------------------------------------------------------
# Staging
# ---------------------------------------------------------------------------

if [[ "$ENV" == "staging" ]]; then

  log "--- Vault ---"
  _vault=$(get_secret "k8s-platform/staging/vault")
  export_var "vault_root_token"       "$_vault" "vault_root_token"

  log "--- Docker Hub ---"
  _dockerhub=$(get_secret "k8s-platform/staging/dockerhub")
  export_var "docker_hub_username"     "$_dockerhub" "docker_hub_username"
  export_var "docker_hub_access_token" "$_dockerhub" "docker_hub_access_token"

  log "--- Vault OIDC ---"
  _vault_oidc=$(get_secret "k8s-platform/staging/vault-oidc")
  export_var "vault_oidc_client_secret" "$_vault_oidc" "vault_oidc_client_secret"

  log "--- Grafana ---"
  _grafana=$(get_secret "k8s-platform/staging/grafana")
  export_var "grafana_oidc_client_secret" "$_grafana" "grafana_oidc_client_secret"
  export_var "grafana_admin_password"     "$_grafana" "grafana_admin_password"

  log "--- SonarQube ---"
  _sonar=$(get_secret "k8s-platform/staging/sonarqube")
  export_var "sonarqube_postgresql_password" "$_sonar" "sonarqube_postgresql_password"

  log "--- Harbor ---"
  _harbor=$(get_secret "k8s-platform/staging/harbor")
  export_var "harbor_postgresql_password" "$_harbor" "harbor_postgresql_password"
  export_var "harbor_admin_password"      "$_harbor" "harbor_admin_password"
  export_var "harbor_redis_password"      "$_harbor" "harbor_redis_password"

  log "--- ArgoCD ---"
  _argocd=$(get_secret "k8s-platform/staging/argocd")
  export_var "argocd_postgresql_password" "$_argocd" "argocd_postgresql_password"
  export_var "argocd_oidc_client_secret"  "$_argocd" "argocd_oidc_client_secret"

  log "--- Keycloak ---"
  _keycloak=$(get_secret "k8s-platform/staging/keycloak")
  export_var "keycloak_postgresql_password" "$_keycloak" "keycloak_postgresql_password"
  export_var "keycloak_admin_password"      "$_keycloak" "keycloak_admin_password"

  log "--- Backstage ---"
  _backstage=$(get_secret "k8s-platform/staging/backstage")
  export_var "backstage_db_password"              "$_backstage" "backstage_db_password"
  export_var "backstage_keycloak_client_secret"   "$_backstage" "backstage_keycloak_client_secret"
  export_var "backstage_gitlab_token"             "$_backstage" "backstage_gitlab_token"
  export_var "backstage_argocd_token"             "$_backstage" "backstage_argocd_token"
  export_var "backstage_sonarqube_token"          "$_backstage" "backstage_sonarqube_token"
  export_var "backstage_auth_session_secret"      "$_backstage" "backstage_auth_session_secret"
  export_var "backstage_harbor_robot_token"       "$_backstage" "backstage_harbor_robot_token"

  log "--- Hatch ETL ---"
  _hatch=$(get_secret "k8s-platform/staging/hatch-etl")
  export_var "hatch_etl_db_password"   "$_hatch" "hatch_etl_db_password"
  export_var "hatch_etl_redis_password" "$_hatch" "hatch_etl_redis_password"
  export_var "hatch_etl_api_username"  "$_hatch" "hatch_etl_api_username"
  export_var "hatch_etl_api_password"  "$_hatch" "hatch_etl_api_password"

  # Alertmanager webhook — NÃO armazenado no SM; passar diretamente se necessário:
  # export TF_VAR_alertmanager_webhook_url="https://hooks.slack.com/services/XXX/YYY/ZZZ"
  if [[ -n "${TF_VAR_alertmanager_webhook_url:-}" ]]; then
    log "  ✓ TF_VAR_alertmanager_webhook_url já definido no ambiente (não sobrescrever)"
  else
    log "  INFO: TF_VAR_alertmanager_webhook_url não definido — alertas desativados (default='')"
  fi

fi

# ---------------------------------------------------------------------------
# Prod
# ---------------------------------------------------------------------------

if [[ "$ENV" == "prod" ]]; then

  log "--- Vault ---"
  _vault=$(get_secret "k8s-platform/prod/vault")
  export_var "vault_root_token" "$_vault" "vault_root_token"

  log "--- Vault OIDC ---"
  _vault_oidc=$(get_secret "k8s-platform/prod/vault-oidc")
  export_var "vault_oidc_client_secret" "$_vault_oidc" "vault_oidc_client_secret"

  log "--- Grafana ---"
  _grafana=$(get_secret "k8s-platform/prod/grafana")
  export_var "grafana_oidc_client_secret" "$_grafana" "grafana_oidc_client_secret"
  export_var "grafana_admin_password"     "$_grafana" "grafana_admin_password"

  log "--- SonarQube ---"
  _sonar=$(get_secret "k8s-platform/prod/sonarqube")
  export_var "sonarqube_postgresql_password" "$_sonar" "sonarqube_postgresql_password"

  log "--- Harbor ---"
  _harbor=$(get_secret "k8s-platform/prod/harbor")
  export_var "harbor_postgresql_password" "$_harbor" "harbor_postgresql_password"
  export_var "harbor_admin_password"      "$_harbor" "harbor_admin_password"
  export_var "harbor_redis_password"      "$_harbor" "harbor_redis_password"

  log "--- ArgoCD ---"
  _argocd=$(get_secret "k8s-platform/prod/argocd")
  export_var "argocd_postgresql_password" "$_argocd" "argocd_postgresql_password"
  export_var "argocd_oidc_client_secret"  "$_argocd" "argocd_oidc_client_secret"

  log "--- Keycloak ---"
  _keycloak=$(get_secret "k8s-platform/prod/keycloak")
  export_var "keycloak_postgresql_password" "$_keycloak" "keycloak_postgresql_password"
  export_var "keycloak_admin_password"      "$_keycloak" "keycloak_admin_password"

fi

# ---------------------------------------------------------------------------
# Resultado
# ---------------------------------------------------------------------------

log ""
log "Exportacao concluida para ambiente: $ENV"
log "Use: terraform plan -var-file=terraform.tfvars"
log "NAO execute terraform plan -var-file=secrets.auto.tfvars (arquivo descontinuado)"
