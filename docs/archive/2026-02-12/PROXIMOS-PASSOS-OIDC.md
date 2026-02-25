# GitLab OIDC - Próximos Passos (2026-02-12)

## Status Atual ✅

- CoreDNS split-horizon: ATIVO
- Keycloak client `gitlab`: CRIADO (secret: <STORED_IN_VAULT>)
- K8s Secret `gitlab-oidc-keycloak`: CRIADO
- Terraform modules: ATUALIZADOS (enable_oidc=true)
- Prometheus Operator: FIXADO

## Bloqueios ⚠️

1. **Helm Release**: `pending-upgrade` (rev 2)
2. **Terraform**: Aguardando rollback do Helm

## Comandos para Executar Amanhã

### 1. Resolver Helm Pending-Upgrade

```bash
# Check status
helm list -n gitlab-staging -a

# Rollback to rev 1
helm rollback gitlab 1 -n gitlab-staging --wait --timeout=5m

# Verify
helm list -n gitlab-staging
```

### 2. AWS SSO Login

```bash
aws sso login --profile k8s-platform-prod

# Verify
aws sts get-caller-identity --profile k8s-platform-prod
```

### 3. Terraform Apply

```bash
cd platform-provisioning/aws/kubernetes/terraform/environments/staging

# Apply GitLab module
AWS_PROFILE=k8s-platform-prod terraform apply \
  -target=module.gitlab_staging \
  -var='vault_root_token=dummy' \
  -auto-approve

# Monitor
kubectl rollout status deployment gitlab-webservice-default -n gitlab-staging
```

### 4. Verificar OmniAuth

```bash
# Check Helm values
helm get values gitlab -n gitlab-staging | grep -A 10 omniauth

# Check ConfigMap
kubectl get configmap gitlab-webservice -n gitlab-staging -o yaml | \
  grep -A 15 "omniauth:"

# Check pods
kubectl get pods -n gitlab-staging -l app=webservice
```

### 5. Testar OIDC Login

```bash
# Port-forward GitLab
kubectl port-forward -n gitlab-staging svc/gitlab-webservice-default 8082:8181 &

# Port-forward Keycloak (opcional)
kubectl port-forward -n keycloak svc/keycloak-keycloakx-http 8081:80 &

# Browser: http://localhost:8082
# Clicar em "Keycloak SSO"
# Login e verificar callback
```

### 6. Validações

```bash
# Test DNS resolution
kubectl run dns-test --image=nicolaka/netshoot --rm --restart=Never -- \
  nslookup keycloak.staging.internal

# Check Keycloak client
kubectl get secret -n gitlab-staging gitlab-oidc-keycloak -o yaml

# Verify service endpoints
kubectl get endpoints -n keycloak keycloak-http
```

## Se Algo Falhar

### Helm Rollback Não Funciona

```bash
# Force delete pending release
kubectl delete secret -n gitlab-staging sh.helm.release.v1.gitlab.v2

# Verify
helm list -n gitlab-staging
```

### Terraform State Lock

```bash
# Check lock
terraform plan -target=module.gitlab_staging 2>&1 | grep "Lock ID"

# Unlock
AWS_PROFILE=k8s-platform-prod terraform force-unlock -force <LOCK_ID>
```

### GitLab Pods CrashLoop

```bash
# Check logs
kubectl logs -n gitlab-staging -l app=webservice --tail=100

# Check events
kubectl get events -n gitlab-staging --sort-by='.lastTimestamp' | grep webservice

# Rollback Helm if needed
helm rollback gitlab 1 -n gitlab-staging
```

## Arquivos Importantes

- Logbook: `docs/logbook/2026-02-11-gitlab-oidc-integration.md`
- Secret YAML: `/tmp/gitlab-oidc-keycloak-secret.yaml`
- CoreDNS Config: `/tmp/coredns-staging-internal-fixed.yaml`
- Runbook: `/tmp/gitlab-oidc-deployment-runbook.md`

## Credenciais

**Keycloak Client**:
- Client ID: `gitlab`
- Client Secret: `<STORED_IN_VAULT>`
- Issuer: `http://keycloak.staging.internal/auth/realms/platform`

**Secret K8s**: `gitlab-oidc-keycloak` (namespace: `gitlab-staging`)

## Tempo Estimado

- Rollback Helm: 5 minutos
- Terraform apply: 10-15 minutos
- Validação: 10 minutos
- Teste E2E: 15 minutos

**Total**: ~45 minutos
