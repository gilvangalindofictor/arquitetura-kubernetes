#!/usr/bin/env bash

################################################################################
# SSO Smoke Test Script
# Purpose: Validate SSO/OIDC integration across all platform services
# Usage: ./sso-smoke-test.sh [OPTIONS]
# Author: Platform Team
# Date: 2026-02-13
################################################################################

set -euo pipefail

# Configuration
KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-keycloak}"
GITLAB_NAMESPACE="${GITLAB_NAMESPACE:-gitlab-staging}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
GRAFANA_NAMESPACE="${GRAFANA_NAMESPACE:-monitoring}"
SONARQUBE_NAMESPACE="${SONARQUBE_NAMESPACE:-sonarqube}"
HARBOR_NAMESPACE="${HARBOR_NAMESPACE:-harbor}"
VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault}"

KEYCLOAK_INTERNAL_HOST="${KEYCLOAK_INTERNAL_HOST:-keycloak-keycloakx-http.keycloak.svc.cluster.local}"
KEYCLOAK_SVC_NAME="${KEYCLOAK_SVC_NAME:-keycloak-keycloakx-http}"
KEYCLOAK_EXTERNAL_HOST="${KEYCLOAK_EXTERNAL_HOST:-keycloak.staging.internal}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-platform}"
KEYCLOAK_BASE_PATH="${KEYCLOAK_BASE_PATH:-/auth}"
KEYCLOAK_HTTP_PORT="${KEYCLOAK_HTTP_PORT:-80}"
KEYCLOAK_MGMT_PORT="${KEYCLOAK_MGMT_PORT:-9000}"

# Test results
TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0
FAILURES=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Options
VERBOSE="${VERBOSE:-false}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-text}"
REPORT_FILE=""

################################################################################
# Helpers
################################################################################

print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}"
}

print_section() {
    echo ""
    echo -e "${BOLD}${BLUE}─── $1 ───${NC}"
}

pass() {
    TOTAL=$((TOTAL + 1))
    PASSED=$((PASSED + 1))
    echo -e "  ${GREEN}[PASS]${NC} $1"
}

fail() {
    TOTAL=$((TOTAL + 1))
    FAILED=$((FAILED + 1))
    FAILURES+=("$1: $2")
    echo -e "  ${RED}[FAIL]${NC} $1"
    if [[ -n "${2:-}" ]]; then
        echo -e "         ${RED}-> $2${NC}"
    fi
}

skip() {
    TOTAL=$((TOTAL + 1))
    SKIPPED=$((SKIPPED + 1))
    echo -e "  ${YELLOW}[SKIP]${NC} $1"
    if [[ -n "${2:-}" ]]; then
        echo -e "         ${YELLOW}-> $2${NC}"
    fi
}

info() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "  ${BLUE}[INFO]${NC} $1"
    fi
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        fail "Prerequisite: $1" "command not found"
        return 1
    fi
    return 0
}

# Run a kubectl command with timeout and capture output
kube_exec() {
    timeout 15 kubectl "$@" 2>/dev/null
}

# Trim whitespace and newlines from a value (for safe arithmetic)
trim() {
    echo "$1" | tr -d '[:space:]'
}

# Run a curl-like test from inside the cluster using a temporary pod
cluster_curl() {
    local url="$1"
    local expected_code="${2:-200}"

    local result
    result=$(kubectl run sso-smoke-curl-$RANDOM \
        --image=curlimages/curl:latest \
        --restart=Never \
        --rm -i --quiet \
        --timeout=30s \
        -- -s -o /dev/null -w "%{http_code}" -m 10 "$url" 2>/dev/null) || true

    echo "$result"
}

# Run a curl test from inside the cluster and return body
cluster_curl_body() {
    local url="$1"

    local result
    result=$(kubectl run sso-smoke-curl-$RANDOM \
        --image=curlimages/curl:latest \
        --restart=Never \
        --rm -i --quiet \
        --timeout=30s \
        -- -s -m 10 "$url" 2>/dev/null) || true

    echo "$result"
}

################################################################################
# Prerequisite Checks
################################################################################

check_prerequisites() {
    print_section "Prerequisites"

    check_command kubectl || return 1
    check_command jq || return 1

    if kube_exec cluster-info &> /dev/null; then
        pass "Kubernetes cluster connectivity"
    else
        fail "Kubernetes cluster connectivity" "Cannot connect to cluster"
        return 1
    fi

    # Check current context
    local context
    context=$(kubectl config current-context 2>/dev/null || echo "unknown")
    info "Current context: $context"
    pass "kubectl context active: $context"
}

################################################################################
# Test 1: Keycloak Infrastructure
################################################################################

test_keycloak_infrastructure() {
    print_section "1. Keycloak Infrastructure"

    # 1.1 Namespace exists
    if kube_exec get namespace "$KEYCLOAK_NAMESPACE" &> /dev/null; then
        pass "Namespace '$KEYCLOAK_NAMESPACE' exists"
    else
        fail "Namespace '$KEYCLOAK_NAMESPACE' exists" "namespace not found"
        return
    fi

    # 1.2 Pods running
    local pod_count
    pod_count=$(kube_exec get pods -n "$KEYCLOAK_NAMESPACE" \
        -l "app.kubernetes.io/name=keycloakx" \
        --field-selector=status.phase=Running \
        -o name 2>/dev/null | wc -l | tr -d ' ')

    if [[ $pod_count -gt 0 ]]; then
        pass "Keycloak pods running: $pod_count replica(s)"
    else
        # Try alternative label
        pod_count=$(kube_exec get pods -n "$KEYCLOAK_NAMESPACE" \
            -l "app=keycloak" \
            --field-selector=status.phase=Running \
            -o name 2>/dev/null | wc -l | tr -d ' ')

        if [[ $pod_count -gt 0 ]]; then
            pass "Keycloak pods running: $pod_count replica(s)"
        else
            fail "Keycloak pods running" "no running pods found"
            return
        fi
    fi

    # 1.3 All pods ready (no CrashLoopBackOff)
    local not_ready
    not_ready=$(kube_exec get pods -n "$KEYCLOAK_NAMESPACE" \
        -o jsonpath='{.items[*].status.containerStatuses[?(@.ready==false)].name}' 2>/dev/null || echo "")

    if [[ -z "$not_ready" ]]; then
        pass "All Keycloak containers ready"
    else
        fail "All Keycloak containers ready" "not ready: $not_ready"
    fi

    # 1.4 Service exists
    if kube_exec get svc -n "$KEYCLOAK_NAMESPACE" "$KEYCLOAK_SVC_NAME" &> /dev/null; then
        pass "Service '$KEYCLOAK_SVC_NAME' exists"
    else
        fail "Service '$KEYCLOAK_SVC_NAME' exists" "service not found"
    fi

    # 1.5 PodDisruptionBudget
    local pdb_count
    pdb_count=$(kube_exec get pdb -n "$KEYCLOAK_NAMESPACE" -o name 2>/dev/null | wc -l | tr -d ' ')

    if [[ $pdb_count -gt 0 ]]; then
        pass "PodDisruptionBudget configured"
    else
        skip "PodDisruptionBudget configured" "none found (optional for staging)"
    fi
}

################################################################################
# Test 2: Keycloak Health Endpoints
################################################################################

test_keycloak_health() {
    print_section "2. Keycloak Health & OIDC Discovery"

    # 2.1 Readiness probe (uses HTTP port with base path, same as K8s probe)
    local health_url="http://${KEYCLOAK_INTERNAL_HOST}:${KEYCLOAK_HTTP_PORT}${KEYCLOAK_BASE_PATH}/health/ready"
    local status_code
    status_code=$(cluster_curl "$health_url" 2>/dev/null)

    if [[ "$status_code" == "200" ]]; then
        pass "Keycloak readiness endpoint (/health/ready)"
    else
        fail "Keycloak readiness endpoint (/health/ready)" "HTTP $status_code (expected 200)"
    fi

    # 2.2 Liveness probe
    local live_url="http://${KEYCLOAK_INTERNAL_HOST}:${KEYCLOAK_HTTP_PORT}${KEYCLOAK_BASE_PATH}/health/live"
    status_code=$(cluster_curl "$live_url" 2>/dev/null)

    if [[ "$status_code" == "200" ]]; then
        pass "Keycloak liveness endpoint (/health/live)"
    else
        fail "Keycloak liveness endpoint (/health/live)" "HTTP $status_code (expected 200)"
    fi

    # 2.3 OIDC Discovery endpoint (HTTP port)
    local discovery_url="http://${KEYCLOAK_INTERNAL_HOST}:${KEYCLOAK_HTTP_PORT}${KEYCLOAK_BASE_PATH}/realms/${KEYCLOAK_REALM}/.well-known/openid-configuration"
    local discovery_body
    discovery_body=$(cluster_curl_body "$discovery_url" 2>/dev/null)

    if echo "$discovery_body" | jq -e '.issuer' &> /dev/null; then
        pass "OIDC Discovery endpoint returns valid JSON"

        # Validate required OIDC fields
        local issuer
        issuer=$(echo "$discovery_body" | jq -r '.issuer' 2>/dev/null)
        info "Issuer: $issuer"

        for field in authorization_endpoint token_endpoint userinfo_endpoint jwks_uri; do
            if echo "$discovery_body" | jq -e ".$field" &> /dev/null; then
                pass "OIDC Discovery: '$field' present"
            else
                fail "OIDC Discovery: '$field' present" "field missing from discovery response"
            fi
        done

        # Check supported grant types
        if echo "$discovery_body" | jq -e '.grant_types_supported | index("authorization_code")' &> /dev/null; then
            pass "OIDC: authorization_code grant supported"
        else
            fail "OIDC: authorization_code grant supported" "grant type not listed"
        fi

        # Check supported scopes
        for scope in openid profile email; do
            if echo "$discovery_body" | jq -e ".scopes_supported | index(\"$scope\")" &> /dev/null; then
                pass "OIDC: scope '$scope' supported"
            else
                fail "OIDC: scope '$scope' supported" "scope not listed"
            fi
        done
    else
        fail "OIDC Discovery endpoint" "invalid or empty response"
    fi

    # 2.4 Realm exists
    local realm_url="http://${KEYCLOAK_INTERNAL_HOST}:${KEYCLOAK_HTTP_PORT}${KEYCLOAK_BASE_PATH}/realms/${KEYCLOAK_REALM}"
    status_code=$(cluster_curl "$realm_url" 2>/dev/null)

    if [[ "$status_code" == "200" ]]; then
        pass "Keycloak realm '${KEYCLOAK_REALM}' accessible"
    else
        fail "Keycloak realm '${KEYCLOAK_REALM}' accessible" "HTTP $status_code"
    fi
}

################################################################################
# Test 3: DNS Resolution (Split-Horizon)
################################################################################

test_dns_resolution() {
    print_section "3. DNS Resolution (Split-Horizon)"

    local hosts=(
        "$KEYCLOAK_EXTERNAL_HOST"
        "argocd.staging.internal"
        "gitlab.staging.internal"
    )

    for host in "${hosts[@]}"; do
        local dns_output
        dns_output=$(kubectl run "sso-smoke-dns-$RANDOM" \
            --image=busybox:latest \
            --restart=Never \
            --rm -i --quiet \
            --timeout=15s \
            -- nslookup "$host" 2>&1 || true)

        local resolved
        resolved=$(echo "$dns_output" | grep -c "Address" 2>/dev/null || echo "0")
        resolved=$(echo "$resolved" | tr -d '[:space:]')

        # nslookup returns at least 2 'Address' lines if resolved (server + result)
        if [[ "$resolved" -ge 2 ]]; then
            pass "DNS resolves: $host"
        else
            fail "DNS resolves: $host" "could not resolve hostname"
        fi
    done
}

################################################################################
# Test 4: ArgoCD OIDC Integration
################################################################################

test_argocd_oidc() {
    print_section "4. ArgoCD OIDC Integration"

    # 4.1 Namespace/pods
    if ! kube_exec get namespace "$ARGOCD_NAMESPACE" &> /dev/null; then
        skip "ArgoCD namespace" "namespace '$ARGOCD_NAMESPACE' not found"
        return
    fi

    local server_pods
    server_pods=$(kube_exec get pods -n "$ARGOCD_NAMESPACE" \
        -l "app.kubernetes.io/name=argocd-server" \
        --field-selector=status.phase=Running \
        -o name 2>/dev/null | wc -l | tr -d ' ')

    if [[ $server_pods -gt 0 ]]; then
        pass "ArgoCD server pods running: $server_pods"
    else
        fail "ArgoCD server pods running" "no running pods"
        return
    fi

    # 4.2 OIDC config in argocd-cm ConfigMap
    local oidc_config
    oidc_config=$(kube_exec get configmap argocd-cm -n "$ARGOCD_NAMESPACE" \
        -o jsonpath='{.data.oidc\.config}' 2>/dev/null || echo "")

    if [[ -n "$oidc_config" ]]; then
        pass "ArgoCD ConfigMap has OIDC config"

        # Check issuer
        if echo "$oidc_config" | grep -q "issuer"; then
            local issuer_value
            issuer_value=$(echo "$oidc_config" | grep "issuer" | head -1 | awk '{print $2}')
            pass "ArgoCD OIDC issuer configured: $issuer_value"

            # Warn if using internal URL (browser won't resolve it)
            if echo "$issuer_value" | grep -q "svc.cluster.local"; then
                fail "ArgoCD OIDC issuer uses external hostname" \
                    "uses svc.cluster.local (browser can't resolve). Change to external hostname"
            else
                pass "ArgoCD OIDC issuer uses external hostname"
            fi
        else
            fail "ArgoCD OIDC issuer configured" "issuer field not found in oidc.config"
        fi

        # Check clientID
        if echo "$oidc_config" | grep -q "clientID"; then
            pass "ArgoCD OIDC clientID configured"
        else
            fail "ArgoCD OIDC clientID configured" "clientID not found"
        fi

        # Check scopes
        if echo "$oidc_config" | grep -q "openid"; then
            pass "ArgoCD OIDC scopes include 'openid'"
        else
            fail "ArgoCD OIDC scopes include 'openid'" "openid scope not found"
        fi
    else
        fail "ArgoCD ConfigMap has OIDC config" "oidc.config not found in argocd-cm"
    fi

    # 4.3 OIDC secret exists
    if kube_exec get secret argocd-secret -n "$ARGOCD_NAMESPACE" &> /dev/null; then
        pass "ArgoCD secret 'argocd-secret' exists"
    else
        fail "ArgoCD secret 'argocd-secret' exists" "secret not found"
    fi

    # 4.4 RBAC policy
    local rbac_policy
    rbac_policy=$(kube_exec get configmap argocd-rbac-cm -n "$ARGOCD_NAMESPACE" \
        -o jsonpath='{.data.policy\.csv}' 2>/dev/null || echo "")

    if [[ -n "$rbac_policy" ]]; then
        pass "ArgoCD RBAC policy configured"
    else
        skip "ArgoCD RBAC policy configured" "no policy.csv in argocd-rbac-cm (using default)"
    fi
}

################################################################################
# Test 5: GitLab OIDC Integration
################################################################################

test_gitlab_oidc() {
    print_section "5. GitLab OIDC Integration"

    # 5.1 Namespace/pods
    if ! kube_exec get namespace "$GITLAB_NAMESPACE" &> /dev/null; then
        skip "GitLab namespace" "namespace '$GITLAB_NAMESPACE' not found"
        return
    fi

    local webservice_pods
    webservice_pods=$(kube_exec get pods -n "$GITLAB_NAMESPACE" \
        -l "app=webservice" \
        --field-selector=status.phase=Running \
        -o name 2>/dev/null | wc -l | tr -d ' ')

    if [[ $webservice_pods -gt 0 ]]; then
        pass "GitLab webservice pods running: $webservice_pods"
    else
        fail "GitLab webservice pods running" "no running pods"
        return
    fi

    # 5.2 OIDC secret exists
    if kube_exec get secret gitlab-oidc-keycloak -n "$GITLAB_NAMESPACE" &> /dev/null; then
        pass "GitLab OIDC secret 'gitlab-oidc-keycloak' exists"
    else
        fail "GitLab OIDC secret 'gitlab-oidc-keycloak' exists" "secret not found"
    fi

    # 5.3 OmniAuth config in GitLab
    local omniauth_enabled
    omniauth_enabled=$(kube_exec get configmap -n "$GITLAB_NAMESPACE" \
        -l "app=webservice" \
        -o jsonpath='{.items[*].data}' 2>/dev/null | grep -c "omniauth" || echo "0")

    # Alternative: check via Helm values in the release
    local helm_values
    helm_values=$(kube_exec get secret -n "$GITLAB_NAMESPACE" \
        -l "owner=helm" \
        -o name 2>/dev/null | head -1)

    if [[ -n "$helm_values" ]]; then
        pass "GitLab Helm release found in namespace"
    else
        info "Could not find Helm release secret"
    fi

    # 5.4 Check GitLab can reach Keycloak (OIDC discovery from GitLab pod)
    local gitlab_pod
    gitlab_pod=$(kube_exec get pods -n "$GITLAB_NAMESPACE" \
        -l "app=webservice" \
        --field-selector=status.phase=Running \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -n "$gitlab_pod" ]]; then
        local kc_reachable
        kc_reachable=$(kube_exec exec -n "$GITLAB_NAMESPACE" "$gitlab_pod" -c webservice -- \
            curl -sf --max-time 5 \
            "http://${KEYCLOAK_INTERNAL_HOST}:${KEYCLOAK_HTTP_PORT}${KEYCLOAK_BASE_PATH}/realms/${KEYCLOAK_REALM}/.well-known/openid-configuration" \
            2>/dev/null | head -c 20 || echo "")

        if [[ -n "$kc_reachable" ]]; then
            pass "GitLab -> Keycloak OIDC Discovery reachable"
        else
            fail "GitLab -> Keycloak OIDC Discovery reachable" \
                "GitLab pod cannot reach Keycloak discovery endpoint"
        fi
    else
        skip "GitLab -> Keycloak connectivity" "could not identify GitLab pod"
    fi
}

################################################################################
# Test 6: Keycloak Clients (via DB or API)
################################################################################

test_keycloak_clients() {
    print_section "6. Keycloak OIDC Clients"

    # Try to check clients via Keycloak Admin REST API (needs admin token)
    # Fallback: check via database if possible

    local expected_clients=("argocd" "gitlab")

    # Attempt via Admin REST API (if admin credentials available)
    local admin_url="http://${KEYCLOAK_INTERNAL_HOST}:${KEYCLOAK_HTTP_PORT}${KEYCLOAK_BASE_PATH}/admin/realms/${KEYCLOAK_REALM}/clients"

    # Try to get admin token
    local admin_password
    admin_password=$(kube_exec get secret -n "$KEYCLOAK_NAMESPACE" \
        keycloak-admin-credentials \
        -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")

    if [[ -z "$admin_password" ]]; then
        # Try alternative secret names
        admin_password=$(kube_exec get secret -n "$KEYCLOAK_NAMESPACE" \
            keycloak-http \
            -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    fi

    if [[ -n "$admin_password" ]]; then
        # Get admin token
        local token_url="http://${KEYCLOAK_INTERNAL_HOST}:${KEYCLOAK_HTTP_PORT}${KEYCLOAK_BASE_PATH}/realms/master/protocol/openid-connect/token"
        local token_response
        token_response=$(kubectl run sso-smoke-token-$RANDOM \
            --image=curlimages/curl:latest \
            --restart=Never \
            --rm -i --quiet \
            --timeout=30s \
            -- -s -X POST "$token_url" \
            -d "grant_type=client_credentials&client_id=admin-cli" \
            -d "grant_type=password&client_id=admin-cli&username=admin&password=${admin_password}" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            2>/dev/null || echo "")

        local access_token
        access_token=$(echo "$token_response" | jq -r '.access_token' 2>/dev/null || echo "")

        if [[ -n "$access_token" && "$access_token" != "null" ]]; then
            pass "Keycloak admin token obtained"

            # List clients
            local clients_response
            clients_response=$(kubectl run sso-smoke-clients-$RANDOM \
                --image=curlimages/curl:latest \
                --restart=Never \
                --rm -i --quiet \
                --timeout=30s \
                -- -s "$admin_url" \
                -H "Authorization: Bearer $access_token" \
                2>/dev/null || echo "")

            for client_id in "${expected_clients[@]}"; do
                if echo "$clients_response" | jq -e ".[] | select(.clientId == \"$client_id\")" &> /dev/null; then
                    local client_enabled
                    client_enabled=$(echo "$clients_response" | jq -r ".[] | select(.clientId == \"$client_id\") | .enabled" 2>/dev/null)

                    if [[ "$client_enabled" == "true" ]]; then
                        pass "Keycloak client '$client_id' exists and enabled"
                    else
                        fail "Keycloak client '$client_id' enabled" "client exists but disabled"
                    fi

                    # Check redirect URIs
                    local redirect_uris
                    redirect_uris=$(echo "$clients_response" | jq -r ".[] | select(.clientId == \"$client_id\") | .redirectUris[]?" 2>/dev/null || echo "")
                    if [[ -n "$redirect_uris" ]]; then
                        pass "Keycloak client '$client_id' has redirect URIs configured"
                        info "Redirect URIs: $redirect_uris"
                    else
                        fail "Keycloak client '$client_id' has redirect URIs" "no redirect URIs configured"
                    fi
                else
                    fail "Keycloak client '$client_id' exists" "client not found in realm '$KEYCLOAK_REALM'"
                fi
            done

            # Check for future clients (informational)
            for future_client in grafana harbor sonarqube; do
                if echo "$clients_response" | jq -e ".[] | select(.clientId == \"$future_client\")" &> /dev/null; then
                    pass "Keycloak client '$future_client' exists (future integration)"
                else
                    skip "Keycloak client '$future_client'" "not yet created (planned)"
                fi
            done
        else
            skip "Keycloak client validation via API" "could not obtain admin token"
            info "Skipping client-level checks. Verify manually via Keycloak Admin UI."
        fi
    else
        skip "Keycloak client validation" "admin credentials not found in cluster secrets"
        info "To enable: create secret 'keycloak-admin-credentials' with 'password' key"
    fi
}

################################################################################
# Test 7: Services Pending SSO (Status Report)
################################################################################

test_pending_services() {
    print_section "7. Services Pending SSO Integration"

    # Grafana
    if kube_exec get namespace "$GRAFANA_NAMESPACE" &> /dev/null; then
        local grafana_pods
        grafana_pods=$(kube_exec get pods -n "$GRAFANA_NAMESPACE" \
            -l "app.kubernetes.io/name=grafana" \
            --field-selector=status.phase=Running \
            -o name 2>/dev/null | wc -l | tr -d ' ')

        if [[ $grafana_pods -gt 0 ]]; then
            # Check if generic_oauth is configured
            local grafana_ini
            grafana_ini=$(kube_exec get configmap -n "$GRAFANA_NAMESPACE" \
                -l "app.kubernetes.io/name=grafana" \
                -o jsonpath='{.items[*].data}' 2>/dev/null | grep -c "generic_oauth" 2>/dev/null || echo "0")
            grafana_ini=$(echo "$grafana_ini" | tr -d '[:space:]')

            if [[ $grafana_ini -gt 0 ]]; then
                pass "Grafana: generic_oauth configured"
            else
                skip "Grafana SSO" "pods running but no generic_oauth config (pending Fase 3)"
            fi
        else
            skip "Grafana SSO" "no running pods found"
        fi
    else
        skip "Grafana SSO" "namespace '$GRAFANA_NAMESPACE' not found"
    fi

    # SonarQube
    if kube_exec get namespace "$SONARQUBE_NAMESPACE" &> /dev/null; then
        local sq_pods
        sq_pods=$(kube_exec get pods -n "$SONARQUBE_NAMESPACE" \
            --field-selector=status.phase=Running \
            -o name 2>/dev/null | wc -l | tr -d ' ')

        if [[ $sq_pods -gt 0 ]]; then
            skip "SonarQube SSO" "pods running, pending migration to GitLab OAuth (Fase 2)"
        else
            skip "SonarQube SSO" "no running pods found"
        fi
    else
        skip "SonarQube SSO" "namespace '$SONARQUBE_NAMESPACE' not found"
    fi

    # Harbor
    if kube_exec get namespace "$HARBOR_NAMESPACE" &> /dev/null; then
        local harbor_pods
        harbor_pods=$(kube_exec get pods -n "$HARBOR_NAMESPACE" \
            -l "app=harbor" \
            --field-selector=status.phase=Running \
            -o name 2>/dev/null | wc -l | tr -d ' ')

        if [[ $harbor_pods -gt 0 ]]; then
            skip "Harbor SSO" "pods running, pending OIDC config (Fase 4)"
        else
            skip "Harbor SSO" "no running pods found"
        fi
    else
        skip "Harbor SSO" "namespace '$HARBOR_NAMESPACE' not found"
    fi

    # Vault
    if kube_exec get namespace "$VAULT_NAMESPACE" &> /dev/null; then
        local vault_oidc
        vault_oidc=$(kube_exec exec -n "$VAULT_NAMESPACE" vault-0 -- \
            vault auth list -format=json 2>/dev/null | jq -r 'keys[] | select(. == "oidc/")' 2>/dev/null || echo "")

        if [[ -n "$vault_oidc" ]]; then
            pass "Vault: OIDC auth method enabled"
        else
            skip "Vault SSO" "OIDC auth method not enabled (P2 - planned)"
        fi
    else
        skip "Vault SSO" "namespace '$VAULT_NAMESPACE' not found"
    fi
}

################################################################################
# Test 8: OIDC Log Analysis (Quick Scan)
################################################################################

test_oidc_logs() {
    print_section "8. OIDC Error Log Scan (last 10 min)"

    local since=600 # 10 minutes

    # Keycloak errors
    local kc_pods
    kc_pods=$(kube_exec get pods -n "$KEYCLOAK_NAMESPACE" \
        -l "app.kubernetes.io/name=keycloakx" \
        --field-selector=status.phase=Running \
        -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

    if [[ -z "$kc_pods" ]]; then
        kc_pods=$(kube_exec get pods -n "$KEYCLOAK_NAMESPACE" \
            -l "app=keycloak" \
            --field-selector=status.phase=Running \
            -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    fi

    local kc_errors=0
    for pod in $kc_pods; do
        local errors
        errors=$(kube_exec logs -n "$KEYCLOAK_NAMESPACE" "$pod" \
            --since="${since}s" 2>/dev/null \
            | grep -ciE "LOGIN_ERROR|INVALID_REQUEST|PKCE.*enforced|authentication.*failed" 2>/dev/null || true)
        errors=$(echo "$errors" | tr -d '[:space:]')
        [[ -z "$errors" ]] && errors=0
        kc_errors=$((kc_errors + errors))
    done

    if [[ $kc_errors -eq 0 ]]; then
        pass "Keycloak: no authentication errors in last 10 min"
    else
        fail "Keycloak: authentication errors detected" "$kc_errors error(s) in last 10 min"
    fi

    # ArgoCD OIDC errors
    local argocd_pods
    argocd_pods=$(kube_exec get pods -n "$ARGOCD_NAMESPACE" \
        -l "app.kubernetes.io/name=argocd-server" \
        --field-selector=status.phase=Running \
        -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

    local argocd_errors=0
    for pod in $argocd_pods; do
        local errors
        errors=$(kube_exec logs -n "$ARGOCD_NAMESPACE" "$pod" \
            --since="${since}s" 2>/dev/null \
            | grep -ciE "oidc.*error|token.*error|redirect.*mismatch" 2>/dev/null || true)
        errors=$(echo "$errors" | tr -d '[:space:]')
        [[ -z "$errors" ]] && errors=0
        argocd_errors=$((argocd_errors + errors))
    done

    if [[ $argocd_errors -eq 0 ]]; then
        pass "ArgoCD: no OIDC errors in last 10 min"
    else
        fail "ArgoCD: OIDC errors detected" "$argocd_errors error(s) in last 10 min"
    fi

    # GitLab OmniAuth errors
    local gl_pods
    gl_pods=$(kube_exec get pods -n "$GITLAB_NAMESPACE" \
        -l "app=webservice" \
        --field-selector=status.phase=Running \
        -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

    local gl_errors=0
    for pod in $gl_pods; do
        local errors
        errors=$(kube_exec logs -n "$GITLAB_NAMESPACE" "$pod" -c webservice \
            --since="${since}s" 2>/dev/null \
            | grep -ciE "omniauth.*error|oidc.*fail|oauth.*error" 2>/dev/null || true)
        errors=$(echo "$errors" | tr -d '[:space:]')
        [[ -z "$errors" ]] && errors=0
        gl_errors=$((gl_errors + errors))
    done

    if [[ $gl_errors -eq 0 ]]; then
        pass "GitLab: no OmniAuth/OIDC errors in last 10 min"
    else
        fail "GitLab: OmniAuth/OIDC errors detected" "$gl_errors error(s) in last 10 min"
    fi
}

################################################################################
# Test 9: Keycloak Database Health
################################################################################

test_keycloak_database() {
    print_section "9. Keycloak Database Health"

    # Check if ExternalSecret or regular Secret for DB credentials exist
    local db_secret_found=false

    if kube_exec get externalsecret -n "$KEYCLOAK_NAMESPACE" &> /dev/null 2>&1; then
        local ext_secrets
        ext_secrets=$(kube_exec get externalsecret -n "$KEYCLOAK_NAMESPACE" -o name 2>/dev/null | wc -l | tr -d ' ')

        if [[ $ext_secrets -gt 0 ]]; then
            pass "ExternalSecret(s) configured for Keycloak: $ext_secrets"
            db_secret_found=true

            # Check sync status
            local synced
            synced=$(kube_exec get externalsecret -n "$KEYCLOAK_NAMESPACE" \
                -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")

            if echo "$synced" | grep -q "True"; then
                pass "ExternalSecret sync status: Ready"
            else
                fail "ExternalSecret sync status" "not in Ready state"
            fi
        fi
    fi

    if [[ "$db_secret_found" == "false" ]]; then
        # Check for regular DB secret
        if kube_exec get secret -n "$KEYCLOAK_NAMESPACE" keycloak-db-credentials &> /dev/null; then
            pass "Database credentials secret exists"
        else
            skip "Database credentials" "no ExternalSecret or keycloak-db-credentials found"
        fi
    fi
}

################################################################################
# Report
################################################################################

print_report() {
    print_header "SSO Smoke Test Report"

    echo ""
    echo -e "  ${BOLD}Date:${NC}     $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo -e "  ${BOLD}Context:${NC}  $(kubectl config current-context 2>/dev/null || echo 'unknown')"
    echo ""

    echo -e "  ${BOLD}Results:${NC}"
    echo -e "    Total:   $TOTAL"
    echo -e "    ${GREEN}Passed:  $PASSED${NC}"
    echo -e "    ${RED}Failed:  $FAILED${NC}"
    echo -e "    ${YELLOW}Skipped: $SKIPPED${NC}"
    echo ""

    if [[ $FAILED -gt 0 ]]; then
        echo -e "  ${BOLD}${RED}Failures:${NC}"
        for failure in "${FAILURES[@]}"; do
            echo -e "    ${RED}- $failure${NC}"
        done
        echo ""
    fi

    # Overall status
    if [[ $FAILED -eq 0 ]]; then
        echo -e "  ${BOLD}${GREEN}STATUS: ALL CHECKS PASSED${NC}"
    else
        echo -e "  ${BOLD}${RED}STATUS: $FAILED CHECK(S) FAILED${NC}"
    fi

    echo ""
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}"

    # Generate JSON report if requested
    if [[ -n "$REPORT_FILE" ]]; then
        cat > "$REPORT_FILE" <<EOF
{
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "context": "$(kubectl config current-context 2>/dev/null || echo 'unknown')",
  "total": $TOTAL,
  "passed": $PASSED,
  "failed": $FAILED,
  "skipped": $SKIPPED,
  "status": "$([ $FAILED -eq 0 ] && echo 'PASS' || echo 'FAIL')",
  "failures": $(printf '%s\n' "${FAILURES[@]:-}" | jq -R -s 'split("\n") | map(select(. != ""))')
}
EOF
        echo ""
        echo -e "  ${BLUE}Report saved to: $REPORT_FILE${NC}"
    fi
}

################################################################################
# Usage
################################################################################

show_usage() {
    cat <<EOF
SSO Smoke Test Script

Usage: $0 [OPTIONS]

Options:
  -v, --verbose           Enable verbose output
  -r, --report FILE       Save JSON report to file
  -h, --help              Show this help message

Environment Variables:
  KEYCLOAK_NAMESPACE      Keycloak namespace (default: keycloak)
  GITLAB_NAMESPACE        GitLab namespace (default: gitlab-staging)
  ARGOCD_NAMESPACE        ArgoCD namespace (default: argocd)
  GRAFANA_NAMESPACE       Grafana namespace (default: monitoring)
  KEYCLOAK_EXTERNAL_HOST  External hostname (default: keycloak.staging.internal)
  KEYCLOAK_REALM          Realm name (default: platform)

Examples:
  # Run all smoke tests
  $0

  # Run with verbose output
  $0 --verbose

  # Run and save JSON report
  $0 --report /tmp/sso-smoke-report.json

EOF
}

################################################################################
# Main
################################################################################

main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE="true"
                shift
                ;;
            -r|--report)
                REPORT_FILE="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    print_header "SSO Smoke Test Suite - $(date '+%Y-%m-%d %H:%M')"

    check_prerequisites || { print_report; exit 1; }

    test_keycloak_infrastructure
    test_keycloak_health
    test_dns_resolution
    test_argocd_oidc
    test_gitlab_oidc
    test_keycloak_clients
    test_pending_services
    test_oidc_logs
    test_keycloak_database

    print_report

    # Exit code based on failures
    if [[ $FAILED -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
