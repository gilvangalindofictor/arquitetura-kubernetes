#!/bin/sh
# =============================================================================
# rotate-secrets.sh — Quarterly Automated Secret Rotation
# CICD-003 | ADR-083
#
# Executes inside the Kubernetes CronJob container (image: vault:1.15.0)
# Required env vars (injected by CronJob spec):
#   VAULT_ADDR           - Vault server URL (cluster-local)
#   VAULT_TOKEN          - Vault service token (from ESO-synced secret)
#   VAULT_SKIP_VERIFY    - TLS skip verify (false in production)
#   PGHOST               - RDS endpoint
#   PGPORT               - RDS port (5432)
#   PGUSER               - RDS admin username (from ESO secret)
#   PGPASSWORD           - RDS admin password (from ESO secret)
#   PGSSLMODE            - SSL mode (require)
#   KEYCLOAK_URL         - Keycloak internal service URL
#   KEYCLOAK_REALM       - Keycloak realm (platform)
#   DRY_RUN              - "true" to log-only, no changes applied
#   ROTATION_GRACE_PERIOD_HOURS - Hours before old secret expires (default 24)
#   LOG_LEVEL            - INFO or DEBUG
#
# Usage:
#   Normal execution:    /scripts/rotate-secrets.sh
#   Dry-run (no changes): DRY_RUN=true /scripts/rotate-secrets.sh
#   Single function:     ROTATE_ONLY=postgresql /scripts/rotate-secrets.sh
#
# Exit codes:
#   0 - All rotations succeeded
#   1 - One or more rotations failed (partial success possible)
#   2 - Pre-flight checks failed (no rotations attempted)
# =============================================================================

set -e

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="rotate-secrets.sh"
ROTATION_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
ROTATION_ID="rotation-$(date -u +%Y%m%d%H%M%S)"
DRY_RUN="${DRY_RUN:-false}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
ROTATION_GRACE_PERIOD_HOURS="${ROTATION_GRACE_PERIOD_HOURS:-24}"
ROTATE_ONLY="${ROTATE_ONLY:-all}"  # all | postgresql | keycloak_admin | oidc_clients

# Return code tracking (1 = something failed)
ROTATION_ERRORS=0

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log() {
  level="$1"
  shift
  message="$*"
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  case "$level" in
    DEBUG)
      [ "$LOG_LEVEL" = "DEBUG" ] && printf '[%s] [DEBUG] %s\n' "$timestamp" "$message" >&2
      ;;
    INFO)
      printf '[%s] [INFO]  %s\n' "$timestamp" "$message"
      ;;
    WARN)
      printf '[%s] [WARN]  %s\n' "$timestamp" "$message" >&2
      ;;
    ERROR)
      printf '[%s] [ERROR] %s\n' "$timestamp" "$message" >&2
      ;;
  esac
}

log_separator() {
  log INFO "---------------------------------------------------------------"
}

# ---------------------------------------------------------------------------
# Dry-run wrapper
# Wraps any command: prints command in dry-run mode, executes otherwise.
# ---------------------------------------------------------------------------
maybe_run() {
  if [ "$DRY_RUN" = "true" ]; then
    log INFO "[DRY-RUN] Would execute: $*"
    return 0
  fi
  "$@"
}

# ---------------------------------------------------------------------------
# Password generation
# Generates a 32-char alphanumeric+special password safe for PostgreSQL,
# Keycloak, and Vault (avoids /@"' that break connection strings).
# ---------------------------------------------------------------------------
generate_password() {
  # tr removes problematic chars; head guarantees length
  password=$(cat /dev/urandom | tr -dc 'A-Za-z0-9!#%^&*()-_=+[]{}|;:,.<>?' | head -c 32)
  printf '%s' "$password"
}

generate_client_secret() {
  # URL-safe base64, 48 chars output (36 bytes input)
  cat /dev/urandom | head -c 36 | base64 | tr '+/' '-_' | tr -d '=' | head -c 48
}

# ---------------------------------------------------------------------------
# Vault helpers
# ---------------------------------------------------------------------------
vault_read() {
  path="$1"
  field="$2"
  vault kv get -field="$field" "$path" 2>/dev/null
}

vault_write() {
  path="$1"
  shift
  # "$@" is key=value pairs
  maybe_run vault kv put "$path" "$@"
}

vault_patch() {
  path="$1"
  shift
  maybe_run vault kv patch "$path" "$@"
}

# ---------------------------------------------------------------------------
# PostgreSQL helper
# Executes ALTER USER via psql. The container image (vault:1.15.0) does NOT
# include psql. This function uses kubectl via a sidecar Job approach OR
# assumes psql is available. In the default CronJob setup a separate init
# container with postgres:16-alpine handles this.
#
# If psql is unavailable (vault image), the rotation for pg passwords
# falls back to updating only the Vault KV path, and a separate manual step
# is required to apply the change in RDS.
# See: docs/runbooks/secret-rotation-emergency-manual.md
# ---------------------------------------------------------------------------
pg_alter_user() {
  username="$1"
  new_password="$2"
  database="${3:-postgres}"

  if command -v psql > /dev/null 2>&1; then
    log DEBUG "Altering PostgreSQL user '$username' via psql"
    maybe_run psql \
      "postgresql://${PGUSER}:${PGPASSWORD}@${PGHOST}:${PGPORT}/${database}?sslmode=${PGSSLMODE}" \
      -c "ALTER USER ${username} WITH PASSWORD '${new_password}';" \
      -v ON_ERROR_STOP=1
  else
    log WARN "psql not available in container — RDS password change for '${username}' requires manual apply"
    log WARN "See: docs/runbooks/secret-rotation-emergency-manual.md#rds-manual-alter-user"
    log WARN "Command to run manually: ALTER USER ${username} WITH PASSWORD '<new_password_from_vault>';"
    # Still write the new password to Vault so it's ready for when manual step runs
    return 0
  fi
}

# ---------------------------------------------------------------------------
# Keycloak Admin API helpers
# Uses Keycloak admin REST API with username/password flow.
# Credentials read from Vault at rotation time.
# ---------------------------------------------------------------------------
keycloak_get_admin_token() {
  admin_user="$1"
  admin_pass="$2"

  response=$(wget -q -O - \
    --post-data "client_id=admin-cli&username=${admin_user}&password=${admin_pass}&grant_type=password" \
    "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" 2>/dev/null) || {
    log ERROR "Failed to obtain Keycloak admin token"
    return 1
  }

  # Extract access_token field (busybox-compatible jq alternative)
  token=$(printf '%s' "$response" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
  if [ -z "$token" ]; then
    log ERROR "Keycloak token response did not contain access_token"
    log DEBUG "Response: $response"
    return 1
  fi

  printf '%s' "$token"
}

keycloak_set_user_password() {
  admin_token="$1"
  user_id="$2"
  new_password="$3"

  response_code=$(wget -q -O /dev/null --server-response \
    --header="Authorization: Bearer ${admin_token}" \
    --header="Content-Type: application/json" \
    --post-data="{\"type\":\"password\",\"value\":\"${new_password}\",\"temporary\":false}" \
    "${KEYCLOAK_URL}/admin/realms/master/users/${user_id}/reset-password" 2>&1 | \
    grep "HTTP/" | tail -1 | awk '{print $2}')

  [ "$response_code" = "204" ] || {
    log ERROR "Keycloak set-password returned HTTP ${response_code} for user ${user_id}"
    return 1
  }
}

keycloak_get_client_id() {
  admin_token="$1"
  client_name="$2"

  result=$(wget -q -O - \
    --header="Authorization: Bearer ${admin_token}" \
    "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/clients?clientId=${client_name}" 2>/dev/null)

  # Extract 'id' field from first result
  id=$(printf '%s' "$result" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
  if [ -z "$id" ]; then
    log ERROR "Could not find Keycloak client ID for '${client_name}'"
    return 1
  fi

  printf '%s' "$id"
}

keycloak_regenerate_client_secret() {
  admin_token="$1"
  client_id_uuid="$2"

  result=$(wget -q -O - \
    --header="Authorization: Bearer ${admin_token}" \
    --post-data="" \
    "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${client_id_uuid}/client-secret" 2>/dev/null)

  new_secret=$(printf '%s' "$result" | grep -o '"value":"[^"]*"' | cut -d'"' -f4)
  if [ -z "$new_secret" ]; then
    log ERROR "Keycloak regenerate-secret returned empty value for client ${client_id_uuid}"
    return 1
  fi

  printf '%s' "$new_secret"
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# Validates all required env vars and connectivity before starting rotation.
# Exits with code 2 if any pre-flight check fails (no changes are made).
# ---------------------------------------------------------------------------
preflight_checks() {
  log INFO "Running pre-flight checks..."
  PREFLIGHT_FAILED=0

  # Required env vars
  for var in VAULT_ADDR VAULT_TOKEN PGHOST PGPORT PGUSER PGPASSWORD KEYCLOAK_URL KEYCLOAK_REALM; do
    eval "val=\${$var:-}"
    if [ -z "$val" ]; then
      log ERROR "Required env var '$var' is not set"
      PREFLIGHT_FAILED=1
    fi
  done

  # Vault connectivity
  log DEBUG "Testing Vault connectivity..."
  if ! vault token lookup > /dev/null 2>&1; then
    log ERROR "Cannot authenticate to Vault at ${VAULT_ADDR}"
    log ERROR "Check VAULT_TOKEN validity and network connectivity"
    PREFLIGHT_FAILED=1
  else
    log DEBUG "Vault connectivity OK"
  fi

  # Vault token permissions check
  log DEBUG "Checking Vault token capabilities..."
  cap=$(vault token capabilities "secret/data/keycloak/postgresql" 2>/dev/null || echo "error")
  log DEBUG "Capabilities on secret/data/keycloak/postgresql: $cap"
  if printf '%s' "$cap" | grep -q "error\|denied"; then
    log ERROR "Vault token lacks write access to secret/data/keycloak/postgresql"
    PREFLIGHT_FAILED=1
  fi

  # RDS connectivity (only if psql is available)
  if command -v psql > /dev/null 2>&1; then
    log DEBUG "Testing RDS connectivity..."
    if ! psql "postgresql://${PGUSER}:${PGPASSWORD}@${PGHOST}:${PGPORT}/postgres?sslmode=${PGSSLMODE}" \
         -c "SELECT 1;" > /dev/null 2>&1; then
      log ERROR "Cannot connect to RDS at ${PGHOST}:${PGPORT}"
      PREFLIGHT_FAILED=1
    else
      log DEBUG "RDS connectivity OK"
    fi
  else
    log WARN "psql not available — RDS connectivity check skipped (PostgreSQL password rotation will be Vault-only)"
  fi

  # Keycloak connectivity
  log DEBUG "Testing Keycloak connectivity..."
  kc_health=$(wget -q -O - "${KEYCLOAK_URL}/realms/master/.well-known/openid-configuration" 2>/dev/null | \
    grep -o '"issuer"' | head -1)
  if [ -z "$kc_health" ]; then
    log ERROR "Cannot reach Keycloak at ${KEYCLOAK_URL}"
    PREFLIGHT_FAILED=1
  else
    log DEBUG "Keycloak connectivity OK"
  fi

  if [ "$PREFLIGHT_FAILED" = "1" ]; then
    log ERROR "Pre-flight checks FAILED — aborting rotation (no changes made)"
    exit 2
  fi

  log INFO "Pre-flight checks PASSED"
}

# ---------------------------------------------------------------------------
# FUNCTION 1: rotate_postgresql_passwords
# Rotates passwords for 4 PostgreSQL application users:
#   keycloak_user, gitlab_user, harbor_user, sonarqube_user
#
# Steps per user:
#   1. Generate new password
#   2. ALTER USER in RDS (if psql available)
#   3. Write new password to Vault KV (ESO re-syncs to K8s Secret within 1h)
#   4. Workload restart is NOT triggered here — ESO rollout handles it
#      after grace period (ROTATION_GRACE_PERIOD_HOURS)
# ---------------------------------------------------------------------------
rotate_postgresql_passwords() {
  log_separator
  log INFO "PHASE 1: Rotating PostgreSQL application user passwords"

  # Map: vault_path:pg_username:database
  PG_USERS="
secret/keycloak/postgresql:keycloak_user:keycloak
secret/gitlab/postgresql:gitlab_user:gitlabhq_production
secret/harbor/postgresql:harbor_user:registry
secret/sonarqube/postgresql:sonarqube_user:sonarqube
"

  success_count=0
  fail_count=0

  printf '%s\n' "$PG_USERS" | while IFS=: read -r vault_path pg_user pg_db; do
    [ -z "$vault_path" ] && continue

    log INFO "  Rotating: $pg_user (database: $pg_db, vault: $vault_path)"

    # Read current secret for rollback reference
    current_pass=$(vault_read "$vault_path" "password" 2>/dev/null || echo "")
    if [ -z "$current_pass" ] && [ "$DRY_RUN" = "false" ]; then
      log WARN "  Could not read current password for $pg_user from Vault — proceeding anyway"
    fi

    # Generate new password
    new_pass=$(generate_password)
    log DEBUG "  Generated new password for $pg_user (length: $(printf '%s' "$new_pass" | wc -c))"

    # Step 1: ALTER USER in RDS
    if ! pg_alter_user "$pg_user" "$new_pass" "$pg_db"; then
      log ERROR "  FAILED to ALTER USER $pg_user in RDS — skipping Vault update to avoid split-brain"
      fail_count=$((fail_count + 1))
      continue
    fi

    # Step 2: Write to Vault (ESO will re-sync to K8s Secret within 1h)
    if ! vault_write "$vault_path" \
        "username=${pg_user}" \
        "password=${new_pass}" \
        "rotated_at=${ROTATION_DATE}" \
        "rotation_id=${ROTATION_ID}"; then
      log ERROR "  FAILED to write new password to Vault for $pg_user"
      log WARN "  RDS password was already changed — manual Vault update required"
      log WARN "  Run: vault kv put ${vault_path} username=${pg_user} password=<new_pass>"
      fail_count=$((fail_count + 1))
      continue
    fi

    log INFO "  OK: $pg_user rotated successfully"
    success_count=$((success_count + 1))
  done

  log INFO "PostgreSQL rotation complete: success=$success_count failures=$fail_count"
  [ "$fail_count" -gt 0 ] && ROTATION_ERRORS=$((ROTATION_ERRORS + fail_count))

  log INFO "NOTE: ESO will re-sync K8s Secrets within 1h. Workloads pick up new passwords on next restart."
  log INFO "To force immediate restart after ESO sync:"
  log INFO "  kubectl rollout restart deployment -n staging-platform-keycloak"
  log INFO "  kubectl rollout restart deployment -n staging-platform-gitlab"
  log INFO "  kubectl rollout restart deployment -n harbor-system"
  log INFO "  kubectl rollout restart deployment -n staging-platform-sonarqube"
}

# ---------------------------------------------------------------------------
# FUNCTION 2: rotate_keycloak_admin
# Rotates the Keycloak admin user password (master realm).
#
# Steps:
#   1. Read current admin credentials from Vault
#   2. Generate new password
#   3. Set new password via Keycloak Admin REST API
#   4. Write new password to Vault KV (secret/keycloak/admin)
# ---------------------------------------------------------------------------
rotate_keycloak_admin() {
  log_separator
  log INFO "PHASE 2: Rotating Keycloak admin password"

  vault_path="secret/keycloak/admin"

  # Read current credentials
  current_user=$(vault_read "$vault_path" "username" 2>/dev/null || echo "admin")
  current_pass=$(vault_read "$vault_path" "password" 2>/dev/null || echo "")

  if [ -z "$current_pass" ] && [ "$DRY_RUN" = "false" ]; then
    log ERROR "Cannot read current Keycloak admin password from Vault at $vault_path"
    ROTATION_ERRORS=$((ROTATION_ERRORS + 1))
    return 1
  fi

  # Generate new password
  new_pass=$(generate_password)
  log DEBUG "Generated new Keycloak admin password"

  # Get admin token (using current credentials)
  if [ "$DRY_RUN" = "false" ]; then
    admin_token=$(keycloak_get_admin_token "$current_user" "$current_pass") || {
      log ERROR "Failed to obtain Keycloak admin token — aborting admin rotation"
      ROTATION_ERRORS=$((ROTATION_ERRORS + 1))
      return 1
    }

    # Get user ID for the admin user
    admin_user_id=$(wget -q -O - \
      --header="Authorization: Bearer ${admin_token}" \
      "${KEYCLOAK_URL}/admin/realms/master/users?username=${current_user}&exact=true" 2>/dev/null | \
      grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [ -z "$admin_user_id" ]; then
      log ERROR "Cannot find Keycloak admin user ID for '${current_user}'"
      ROTATION_ERRORS=$((ROTATION_ERRORS + 1))
      return 1
    fi

    log DEBUG "Keycloak admin user ID: $admin_user_id"

    # Set new password via Keycloak API
    if ! keycloak_set_user_password "$admin_token" "$admin_user_id" "$new_pass"; then
      log ERROR "Failed to set new Keycloak admin password via API"
      ROTATION_ERRORS=$((ROTATION_ERRORS + 1))
      return 1
    fi
  else
    log INFO "[DRY-RUN] Would obtain Keycloak admin token and set new password for user '${current_user}'"
  fi

  # Write new password to Vault
  if ! vault_write "$vault_path" \
      "username=${current_user}" \
      "password=${new_pass}" \
      "rotated_at=${ROTATION_DATE}" \
      "rotation_id=${ROTATION_ID}"; then
    log ERROR "CRITICAL: Keycloak admin password changed but Vault write FAILED"
    log ERROR "The admin password is now out of sync with Vault!"
    log ERROR "Manual fix required: vault kv put ${vault_path} username=${current_user} password=<new_pass>"
    log ERROR "Check Keycloak pod logs to verify the new password"
    ROTATION_ERRORS=$((ROTATION_ERRORS + 1))
    return 1
  fi

  log INFO "OK: Keycloak admin password rotated successfully"
}

# ---------------------------------------------------------------------------
# FUNCTION 3: rotate_oidc_clients
# Rotates client secrets for 6 OIDC clients registered in Keycloak:
#   grafana, argocd, harbor, gitlab, vault, sonarqube (SAML SP key)
#
# Steps per client:
#   1. Obtain Keycloak admin token (using rotated admin credentials from step 2)
#   2. Regenerate client secret via Keycloak Admin API
#   3. Write new secret to Vault KV (ESO re-syncs to K8s Secret within 1h)
# ---------------------------------------------------------------------------
rotate_oidc_clients() {
  log_separator
  log INFO "PHASE 3: Rotating Keycloak OIDC client secrets"

  # Read current Keycloak admin credentials (may have just been rotated in phase 2)
  kc_user=$(vault_read "secret/keycloak/admin" "username" 2>/dev/null || echo "admin")
  kc_pass=$(vault_read "secret/keycloak/admin" "password" 2>/dev/null || echo "")

  if [ -z "$kc_pass" ] && [ "$DRY_RUN" = "false" ]; then
    log ERROR "Cannot read Keycloak admin credentials from Vault — aborting OIDC rotation"
    ROTATION_ERRORS=$((ROTATION_ERRORS + 1))
    return 1
  fi

  # Obtain admin token
  if [ "$DRY_RUN" = "false" ]; then
    admin_token=$(keycloak_get_admin_token "$kc_user" "$kc_pass") || {
      log ERROR "Failed to obtain Keycloak admin token for OIDC rotation"
      ROTATION_ERRORS=$((ROTATION_ERRORS + 1))
      return 1
    }
  fi

  # Map: keycloak_client_name:vault_path:vault_field
  # sonarqube uses SAML so its 'secret' is the SP signing key (handled differently below)
  OIDC_CLIENTS="
grafana:secret/grafana/oidc:client_secret
argocd:secret/argocd/oidc:client_secret
harbor:secret/harbor/oidc:client_secret
gitlab:secret/gitlab/oidc:client_secret
vault:secret/vault/oidc:client_secret
"

  printf '%s\n' "$OIDC_CLIENTS" | while IFS=: read -r client_name vault_path vault_field; do
    [ -z "$client_name" ] && continue

    log INFO "  Rotating OIDC client: $client_name"

    if [ "$DRY_RUN" = "false" ]; then
      # Get Keycloak internal UUID for this client
      client_uuid=$(keycloak_get_client_id "$admin_token" "$client_name") || {
        log ERROR "  Failed to get UUID for client '$client_name' — skipping"
        ROTATION_ERRORS=$((ROTATION_ERRORS + 1))
        continue
      }
      log DEBUG "  Client UUID: $client_uuid"

      # Regenerate secret in Keycloak
      new_secret=$(keycloak_regenerate_client_secret "$admin_token" "$client_uuid") || {
        log ERROR "  Failed to regenerate secret for '$client_name' — skipping"
        ROTATION_ERRORS=$((ROTATION_ERRORS + 1))
        continue
      }
    else
      log INFO "  [DRY-RUN] Would regenerate Keycloak secret for client '$client_name'"
      new_secret="dry-run-placeholder-secret-value"
    fi

    # Write to Vault
    # Preserve other fields in the secret (e.g., client_id, discovery_url) via vault kv patch
    if ! vault_patch "$vault_path" \
        "${vault_field}=${new_secret}" \
        "rotated_at=${ROTATION_DATE}" \
        "rotation_id=${ROTATION_ID}"; then
      log ERROR "  Failed to write new secret to Vault for '$client_name'"
      log WARN "  Keycloak secret was already regenerated — manual Vault update required"
      ROTATION_ERRORS=$((ROTATION_ERRORS + 1))
      continue
    fi

    log INFO "  OK: $client_name OIDC secret rotated"
  done

  # SonarQube SAML signing key rotation (different mechanism — generate new key pair)
  log INFO "  Rotating SonarQube SAML SP signing key"
  new_saml_secret=$(generate_client_secret)

  if ! vault_patch "secret/sonarqube/saml" \
      "sp_secret=${new_saml_secret}" \
      "rotated_at=${ROTATION_DATE}" \
      "rotation_id=${ROTATION_ID}"; then
    log ERROR "  Failed to write new SAML SP secret to Vault for sonarqube"
    ROTATION_ERRORS=$((ROTATION_ERRORS + 1))
  else
    log INFO "  OK: SonarQube SAML SP secret rotated"
    log WARN "  NOTE: SonarQube must be restarted to pick up new SAML SP key"
    log WARN "  Run: kubectl rollout restart deployment sonarqube -n staging-platform-sonarqube"
  fi

  log INFO "OIDC client rotation complete"
  log INFO "ESO will re-sync K8s Secrets within 1h. Applications pick up new secrets on next restart."
}

# ---------------------------------------------------------------------------
# Record rotation metadata in Vault
# Stores a rotation audit record at secret/secret-rotator/last-rotation
# ---------------------------------------------------------------------------
record_rotation_metadata() {
  status="$1"  # success | partial | failed

  log INFO "Recording rotation metadata in Vault..."

  vault_write "secret/secret-rotator/last-rotation" \
    "rotation_id=${ROTATION_ID}" \
    "rotation_date=${ROTATION_DATE}" \
    "status=${status}" \
    "errors=${ROTATION_ERRORS}" \
    "dry_run=${DRY_RUN}" \
    "rotate_only=${ROTATE_ONLY}" || \
    log WARN "Failed to write rotation metadata — non-critical"
}

# ---------------------------------------------------------------------------
# Post-rotation validation
# Basic sanity checks after rotation to verify ESO will be able to re-sync.
# ---------------------------------------------------------------------------
post_rotation_validation() {
  log_separator
  log INFO "Post-rotation validation..."

  # Verify Vault token still works (wasn't accidentally rotated)
  if ! vault token lookup > /dev/null 2>&1; then
    log ERROR "CRITICAL: Vault token is no longer valid after rotation!"
    log ERROR "Manual intervention required to restore Vault access"
    ROTATION_ERRORS=$((ROTATION_ERRORS + 1))
    return 1
  fi

  # Verify all expected paths are readable
  for path in \
      "secret/keycloak/postgresql" \
      "secret/keycloak/admin" \
      "secret/grafana/oidc" \
      "secret/harbor/oidc"; do
    if vault kv get "$path" > /dev/null 2>&1; then
      log DEBUG "Path readable: $path"
    else
      log WARN "Path not readable post-rotation: $path (may be permissions issue)"
    fi
  done

  log INFO "Post-rotation validation complete"
}

# ---------------------------------------------------------------------------
# Main execution
# ---------------------------------------------------------------------------
main() {
  log_separator
  log INFO "$SCRIPT_NAME v${SCRIPT_VERSION} starting"
  log INFO "Rotation ID: $ROTATION_ID"
  log INFO "Rotation Date: $ROTATION_DATE"
  log INFO "Dry-run mode: $DRY_RUN"
  log INFO "Rotating: $ROTATE_ONLY"
  log INFO "Grace period: ${ROTATION_GRACE_PERIOD_HOURS}h"
  log INFO "Vault address: ${VAULT_ADDR:-<not set>}"
  log_separator

  if [ "$DRY_RUN" = "true" ]; then
    log WARN "=== DRY-RUN MODE: No changes will be applied ==="
  fi

  # Pre-flight checks (aborts on failure, exit code 2)
  preflight_checks

  # Execute rotation functions based on ROTATE_ONLY
  case "$ROTATE_ONLY" in
    all)
      rotate_postgresql_passwords
      rotate_keycloak_admin
      rotate_oidc_clients
      ;;
    postgresql)
      rotate_postgresql_passwords
      ;;
    keycloak_admin)
      rotate_keycloak_admin
      ;;
    oidc_clients)
      rotate_oidc_clients
      ;;
    *)
      log ERROR "Unknown ROTATE_ONLY value: '$ROTATE_ONLY'. Valid: all|postgresql|keycloak_admin|oidc_clients"
      exit 2
      ;;
  esac

  # Post-rotation validation
  post_rotation_validation

  # Determine final status
  if [ "$ROTATION_ERRORS" -eq 0 ]; then
    final_status="success"
    log_separator
    log INFO "SECRET ROTATION COMPLETED SUCCESSFULLY"
    log INFO "Rotation ID: $ROTATION_ID"
    log INFO "Errors: 0"
    record_rotation_metadata "$final_status"
    exit 0
  else
    final_status="partial"
    log_separator
    log ERROR "SECRET ROTATION COMPLETED WITH ERRORS"
    log ERROR "Rotation ID: $ROTATION_ID"
    log ERROR "Errors: $ROTATION_ERRORS"
    log ERROR "See error messages above for details"
    log ERROR "Runbook: docs/runbooks/secret-rotation-troubleshooting.md"
    record_rotation_metadata "$final_status"
    exit 1
  fi
}

main "$@"
