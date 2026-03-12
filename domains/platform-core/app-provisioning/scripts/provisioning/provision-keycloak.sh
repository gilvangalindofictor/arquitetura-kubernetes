#!/bin/bash
# =============================================================================
# provision-keycloak.sh — Provisiona Keycloak OIDC client (idempotente)
# =============================================================================
# Descricao: Cria client OIDC no Keycloak (confidential ou public),
#            armazena client_secret + metadata no Vault e cria K8s Secret.
# Uso:       ./provision-keycloak.sh --app <name> --domain <d> --namespace <ns> --env <e> --client-type <confidential|public> [--realm <r>] [--redirect-uris <uris>] [--manifest <path>]
# Deps:      kubectl, vault (CLI), curl, jq, yq (se --manifest)
# Ref:       ADR-104, P8 (Keycloak Admin REST API via Vault), GAP-013
# Idempotente: SIM — verifica existencia do client antes de criar
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libs
LOG_PREFIX="KEYCLOAK"
source "${SCRIPT_DIR}/../lib/common.sh"

# Source vault-auth.sh — Kubernetes Auth para token dinamico
# Ref: GAP-009 — eliminar VAULT_TOKEN estatico
if [[ -f "${SCRIPT_DIR}/../lib/vault-auth.sh" ]]; then
    # shellcheck source=../lib/vault-auth.sh
    source "${SCRIPT_DIR}/../lib/vault-auth.sh"
else
    log_error "vault-auth.sh nao encontrado em ${SCRIPT_DIR}/../lib"
    log_error "Biblioteca de autenticacao Vault e obrigatoria"
    exit 1
fi

# Source manifest-parser.sh (opcional — necessario se --manifest for usado)
if [[ -f "${SCRIPT_DIR}/../lib/manifest-parser.sh" ]]; then
    # shellcheck source=../lib/manifest-parser.sh
    source "${SCRIPT_DIR}/../lib/manifest-parser.sh"
fi

# Cleanup
_cleanup() { :; }
register_cleanup _cleanup

# -----------------------------------------------------------------------------
# Parse argumentos
# -----------------------------------------------------------------------------
parse_args() {
    APP_NAME="" DOMAIN="" NAMESPACE="" ENV="" CLIENT_TYPE="confidential"
    REALM="" REDIRECT_URIS="" MANIFEST_PATH="" DRY_RUN=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --app)            APP_NAME="$2"; shift 2 ;;
            --domain)         DOMAIN="$2"; shift 2 ;;
            --namespace)      NAMESPACE="$2"; shift 2 ;;
            --env)            ENV="$2"; shift 2 ;;
            --client-type)    CLIENT_TYPE="$2"; shift 2 ;;
            --realm)          REALM="$2"; shift 2 ;;
            --redirect-uris)  REDIRECT_URIS="$2"; shift 2 ;;
            --manifest)       MANIFEST_PATH="$2"; shift 2 ;;
            --dry-run)        DRY_RUN=true; shift ;;
            *) log_error "Opcao desconhecida: $1"; exit 1 ;;
        esac
    done

    validate_required_args APP_NAME DOMAIN NAMESPACE ENV || exit 1
}

# -----------------------------------------------------------------------------
# resolve_from_manifest — Le configuracoes do manifest.yaml se disponivel
# -----------------------------------------------------------------------------
resolve_from_manifest() {
    if [[ -z "$MANIFEST_PATH" ]]; then
        return 0
    fi

    if [[ -z "${_LIB_MANIFEST_PARSER_LOADED:-}" ]]; then
        log_error "manifest-parser.sh nao carregado — impossivel usar --manifest"
        log_error "Verifique se ${SCRIPT_DIR}/../lib/manifest-parser.sh existe"
        exit 1
    fi

    log_info "Lendo configuracoes do manifest: $MANIFEST_PATH"
    parse_manifest "$MANIFEST_PATH" || {
        log_error "Falha ao parsear manifest: $MANIFEST_PATH"
        exit 1
    }

    # Realm do manifest (se nao passado via --realm)
    if [[ -z "$REALM" ]]; then
        local manifest_realm
        manifest_realm=$(manifest_get '.dependencies.keycloak.realm' '')
        if [[ -n "$manifest_realm" ]]; then
            REALM="$manifest_realm"
            log_info "Realm do manifest: $REALM"
        fi
    fi

    # Redirect URIs do manifest (se nao passado via --redirect-uris)
    if [[ -z "$REDIRECT_URIS" ]]; then
        local manifest_uris
        manifest_uris=$(manifest_get '.dependencies.keycloak.redirectUris | join(",")' '' 2>/dev/null || \
                        manifest_get '.dependencies.keycloak.redirectUris' '' 2>/dev/null || echo "")
        if [[ -n "$manifest_uris" && "$manifest_uris" != "null" ]]; then
            REDIRECT_URIS="$manifest_uris"
            log_info "Redirect URIs do manifest: $REDIRECT_URIS"
        fi
    fi

    # Client type do manifest (se nao explicitamente passado)
    local manifest_client_type
    manifest_client_type=$(manifest_get '.dependencies.keycloak.clientType' '')
    if [[ -n "$manifest_client_type" ]]; then
        CLIENT_TYPE="$manifest_client_type"
        log_info "Client type do manifest: $CLIENT_TYPE"
    fi
}

# -----------------------------------------------------------------------------
# resolve_realm — Determina realm com fallback inteligente
# -----------------------------------------------------------------------------
resolve_realm() {
    # Prioridade: --realm > manifest > DOMAIN fallback
    if [[ -n "$REALM" ]]; then
        return 0
    fi

    # Fallback: usar DOMAIN como realm
    REALM="${DOMAIN}"
    log_info "Realm nao especificado — usando DOMAIN como fallback: $REALM"
}

# -----------------------------------------------------------------------------
# create_external_secret — Cria ExternalSecret CR via ESO (External Secrets Operator)
# Ref: GAP-013 ITEM 5, GAP-013a — mecanismo principal em clusters com ESO instalado
# Idempotente: kubectl apply garante convergencia sem erro em re-execucoes
# -----------------------------------------------------------------------------
create_external_secret() {
    log_info "Criando ExternalSecret CR para $APP_NAME (namespace=$NAMESPACE)..."

    if kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: ${APP_NAME}-keycloak
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${APP_NAME}
    app.kubernetes.io/component: keycloak-credentials
    app.kubernetes.io/managed-by: platform-provisioner
    environment: ${ENV}
    domain: ${DOMAIN}
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-secret-store
    kind: ClusterSecretStore
  target:
    name: ${APP_NAME}-keycloak-credentials
    creationPolicy: Owner
  data:
    - secretKey: KEYCLOAK_CLIENT_ID
      remoteRef:
        key: secret/${ENV}/${DOMAIN}/${APP_NAME}/keycloak
        property: client-id
    - secretKey: KEYCLOAK_CLIENT_SECRET
      remoteRef:
        key: secret/${ENV}/${DOMAIN}/${APP_NAME}/keycloak
        property: client-secret
    - secretKey: KEYCLOAK_REALM
      remoteRef:
        key: secret/${ENV}/${DOMAIN}/${APP_NAME}/keycloak
        property: realm
    - secretKey: KEYCLOAK_AUTH_SERVER_URL
      remoteRef:
        key: secret/${ENV}/${DOMAIN}/${APP_NAME}/keycloak
        property: auth-server-url
    - secretKey: KEYCLOAK_TOKEN_URL
      remoteRef:
        key: secret/${ENV}/${DOMAIN}/${APP_NAME}/keycloak
        property: token-url
    - secretKey: KEYCLOAK_JWKS_URL
      remoteRef:
        key: secret/${ENV}/${DOMAIN}/${APP_NAME}/keycloak
        property: jwks-url
EOF
    then
        log_success "ExternalSecret '${APP_NAME}-keycloak' aplicado em namespace '${NAMESPACE}'"
    else
        log_error "Falha ao criar ExternalSecret '${APP_NAME}-keycloak'"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    parse_args "$@"

    # Ler configuracoes do manifest (se fornecido)
    resolve_from_manifest

    # Resolver realm (parametro > manifest > domain fallback)
    resolve_realm

    # KEYCLOAK_URL deve vir de variavel de ambiente — zero hardcoded
    KEYCLOAK_URL="${KEYCLOAK_URL:?KEYCLOAK_URL nao definido — defina via variavel de ambiente}"

    CLIENT_ID="${DOMAIN}-${APP_NAME}"
    SECRET_NAME="${APP_NAME}-keycloak-credentials"
    VAULT_PATH="secret/${ENV}/${DOMAIN}/${APP_NAME}/keycloak"
    VAULT_ADMIN_PATH="secret/${ENV}/platform/keycloak/admin"

    # URLs derivadas (auto-calculadas)
    AUTH_SERVER_URL="${KEYCLOAK_URL}"
    TOKEN_URL="${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token"
    JWKS_URL="${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/certs"

    log_info "Client: $CLIENT_ID | Type: $CLIENT_TYPE | Realm: $REALM | Env: $ENV"
    log_info "Vault path: $VAULT_PATH"
    log_info "JWKS URL: $JWKS_URL"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Criaria Keycloak client '$CLIENT_ID', Secret e ExternalSecret"
        log_info "[DRY-RUN] Vault path: $VAULT_PATH"
        log_info "[DRY-RUN] JWKS URL: $JWKS_URL"
        exit 0
    fi

    # Check-before-create: Secret
    if resource_exists secret "$SECRET_NAME" "$NAMESPACE"; then
        log_warn "Secret '$SECRET_NAME' ja existe — pulando"
        exit 0
    fi

    # ---------- Vault Auth (token dinamico via Kubernetes Auth) ----------
    # Ref: GAP-009, GAP-013 — eliminar VAULT_TOKEN estatico
    log_info "Autenticando no Vault via Kubernetes Auth..."

    export ENV DOMAIN APP_NAME

    vault_k8s_login --role "platform-provisioner-${ENV}" || {
        log_error "Falha na autenticacao Vault — abortando provisioning"
        exit 1
    }

    # Garantir revogacao do token ao sair
    register_cleanup vault_token_revoke

    # ---------- Obter credenciais admin do Keycloak via Vault ----------
    log_info "Obtendo credenciais admin do Keycloak..."

    KC_ADMIN_USER=$(vault kv get -field=username "${VAULT_ADMIN_PATH}" 2>/dev/null || echo "")
    KC_ADMIN_PASSWORD=$(vault kv get -field=password "${VAULT_ADMIN_PATH}" 2>/dev/null || echo "")

    # Fallback para env vars (CI local / debug)
    KC_ADMIN_USER="${KC_ADMIN_USER:-${KEYCLOAK_ADMIN_USER:-}}"
    KC_ADMIN_PASSWORD="${KC_ADMIN_PASSWORD:-${KEYCLOAK_ADMIN_PASSWORD:-}}"

    if [[ -z "$KC_ADMIN_PASSWORD" ]]; then
        log_error "Credenciais admin do Keycloak nao encontradas (Vault path: ${VAULT_ADMIN_PATH} ou env vars)"
        exit 1
    fi

    ACCESS_TOKEN=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
        -d "grant_type=password&client_id=admin-cli&username=${KC_ADMIN_USER}&password=${KC_ADMIN_PASSWORD}" \
        | jq -r '.access_token')

    if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
        log_error "Falha ao obter token admin do Keycloak"
        exit 1
    fi

    # ---------- Check-before-create: Client no Keycloak ----------
    EXISTING_CLIENT=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM}/clients?clientId=${CLIENT_ID}" \
        | jq -r '.[0].id // empty')

    if [[ -n "$EXISTING_CLIENT" ]]; then
        log_warn "Client '$CLIENT_ID' ja existe no Keycloak (id=$EXISTING_CLIENT) — pulando criacao"
        CLIENT_SECRET=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
            "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${EXISTING_CLIENT}/client-secret" \
            | jq -r '.value')
    else
        log_info "Criando client '$CLIENT_ID'..."

        if [[ "$CLIENT_TYPE" == "confidential" ]]; then
            PUBLIC_CLIENT="false"
            SERVICE_ACCOUNTS="true"
        else
            PUBLIC_CLIENT="true"
            SERVICE_ACCOUNTS="false"
        fi

        REDIRECT_URIS_JSON="[]"
        if [[ -n "$REDIRECT_URIS" ]]; then
            REDIRECT_URIS_JSON=$(echo "$REDIRECT_URIS" | tr ',' '\n' | jq -R . | jq -s .)
        fi

        curl -s -X POST -H "Authorization: Bearer ${ACCESS_TOKEN}" \
            -H "Content-Type: application/json" \
            "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" \
            -d "{
                \"clientId\": \"${CLIENT_ID}\",
                \"name\": \"${APP_NAME} (${DOMAIN})\",
                \"description\": \"Provisionado por platform-provisioner — env: ${ENV}\",
                \"enabled\": true,
                \"publicClient\": ${PUBLIC_CLIENT},
                \"serviceAccountsEnabled\": ${SERVICE_ACCOUNTS},
                \"standardFlowEnabled\": true,
                \"directAccessGrantsEnabled\": false,
                \"protocol\": \"openid-connect\",
                \"redirectUris\": ${REDIRECT_URIS_JSON},
                \"attributes\": {
                    \"domain\": \"${DOMAIN}\",
                    \"environment\": \"${ENV}\",
                    \"managed-by\": \"platform-provisioner\"
                }
            }"

        EXISTING_CLIENT=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
            "${KEYCLOAK_URL}/admin/realms/${REALM}/clients?clientId=${CLIENT_ID}" \
            | jq -r '.[0].id')

        CLIENT_SECRET=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
            "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${EXISTING_CLIENT}/client-secret" \
            | jq -r '.value')

        log_success "Client criado: $CLIENT_ID"
    fi

    # ---------- Kubernetes Secret ----------
    log_info "Criando Secret..."

    create_secret_idempotent "$SECRET_NAME" "$NAMESPACE" \
        --from-literal=client-id="$CLIENT_ID" \
        --from-literal=client-secret="${CLIENT_SECRET:-}" \
        --from-literal=realm="$REALM" \
        --from-literal=auth-server-url="$AUTH_SERVER_URL" \
        --from-literal=token-url="$TOKEN_URL" \
        --from-literal=jwks-url="$JWKS_URL"

    label_secret "$SECRET_NAME" "$NAMESPACE" "$APP_NAME" "auth" "$ENV" "$DOMAIN"

    log_success "Secret criado"

    # ---------- Vault: armazenar todas as chaves (alinhado com ExternalSecret) ----------
    # Chaves em kebab-case — ExternalSecret.remoteRef.property deve referenciar estes nomes
    vault_kv_put_safe "${VAULT_PATH}" \
        client-id="$CLIENT_ID" \
        client-secret="${CLIENT_SECRET:-}" \
        realm="$REALM" \
        auth-server-url="$AUTH_SERVER_URL" \
        token-url="$TOKEN_URL" \
        jwks-url="$JWKS_URL" \
        created-at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    log_success "Vault atualizado: $VAULT_PATH (inclui jwks-url e token-url)"

    # ---------- ExternalSecret CR (mecanismo principal em clusters com ESO) ----------
    # O K8s Secret nativo criado acima e fallback para ambientes sem External Secrets Operator.
    # O ExternalSecret CR e o mecanismo principal: o ESO le as chaves do Vault e reconcilia
    # o Secret automaticamente, garantindo rotacao e auditabilidade via Vault.
    create_external_secret

    log_success "Keycloak totalmente provisionado para $APP_NAME (env=$ENV, domain=$DOMAIN, realm=$REALM)"
}

main "$@"
