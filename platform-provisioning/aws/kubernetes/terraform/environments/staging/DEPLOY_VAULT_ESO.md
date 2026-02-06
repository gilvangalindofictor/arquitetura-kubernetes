# 🚀 Guia de Deploy: Vault K8s Auth + ESO + Keycloak

## 📋 Pré-requisitos

```bash
# 1. AWS SSO login
aws sso login --profile k8s-platform-prod

# 2. Verificar conectividade EKS
kubectl get nodes
kubectl get ns vault-system external-secrets-system

# 3. Recuperar Vault root token
# Opção A: De secret K8s (se Vault já inicializado)
export VAULT_ROOT_TOKEN=$(kubectl get secret vault-root-token -n vault-system -o jsonpath='{.data.root_token}' 2>/dev/null | base64 -d)

# Opção B: Inicializar Vault (se primeira vez)
# kubectl exec -n vault-system vault-0 -- vault operator init -format=json > vault-init.json
# export VAULT_ROOT_TOKEN=$(cat vault-init.json | jq -r '.root_token')
# kubectl create secret generic vault-root-token -n vault-system --from-literal=root_token=$VAULT_ROOT_TOKEN

# 4. Validar Vault está unsealed
kubectl exec -n vault-system vault-0 -- vault status
```

## 🔧 Deploy (3 fases)

### FASE 1: Terraform Plan (3min)

```bash
cd platform-provisioning/aws/kubernetes/terraform/environments/staging

# Export sensitive variables
export TF_VAR_vault_root_token="$VAULT_ROOT_TOKEN"
export TF_VAR_keycloak_postgresql_password="" # Empty = auto-generate

# Terraform plan (target vault-config + keycloak)
terraform init -upgrade
terraform plan \
  -target=module.vault_config_staging \
  -target=module.keycloak_staging \
  -out=tfplan

# Revisar output:
# ✓ vault_auth_backend.kubernetes (enable K8s auth)
# ✓ vault_policy.eso_reader (read-only secret/*)
# ✓ vault_kubernetes_auth_backend_role.eso_reader (bind SA)
# ✓ vault_kv_secret_v2.keycloak_postgresql (credentials)
# ✓ kubectl_manifest.keycloak_postgresql_externalsecret
# ✓ helm_release.keycloak
```

### FASE 2: Terraform Apply com AML (15-20min)

```bash
# Apply em background (AML obrigatório)
terraform apply tfplan > /tmp/tf-apply-vault-eso.log 2>&1 &
TF_PID=$!
echo "Terraform PID: $TF_PID"

# Active Monitoring Loop (poll_interval=15s)
CYCLE=0
while kill -0 $TF_PID 2>/dev/null; do
  sleep 15
  CYCLE=$((CYCLE + 1))
  echo "=== [AML-C$CYCLE] $(date '+%H:%M:%S') ==="

  # Terraform progress
  echo "--- TF Output (tail) ---"
  tail -20 /tmp/tf-apply-vault-eso.log

  # ESO ClusterSecretStore status
  echo "--- ClusterSecretStore ---"
  kubectl get clustersecretstore vault-backend -o yaml 2>/dev/null | grep -A3 "status:"

  # Keycloak ExternalSecret status
  echo "--- ExternalSecret ---"
  kubectl get externalsecret -n keycloak keycloak-postgresql-credentials 2>/dev/null

  # Keycloak pods
  echo "--- Keycloak Pods ---"
  kubectl get pods -n keycloak 2>/dev/null

  # K8s events (errors)
  echo "--- Recent Events ---"
  kubectl get events -n keycloak --sort-by='.lastTimestamp' 2>/dev/null | tail -5
done

# Capturar exit code
wait $TF_PID
EXIT_CODE=$?
echo "Terraform exit code: $EXIT_CODE"
```

### FASE 3: Validação (5min)

```bash
# 1. Validar Vault K8s auth
kubectl exec -n vault-system vault-0 -- vault auth list | grep kubernetes

# 2. Validar policy eso-reader
kubectl exec -n vault-system vault-0 -- vault policy read eso-reader

# 3. Validar secret no Vault
kubectl exec -n vault-system vault-0 -- vault kv get secret/keycloak/postgresql

# 4. Validar ClusterSecretStore Ready
kubectl get clustersecretstore vault-backend
# STATUS: Ready=True

# 5. Validar ExternalSecret synced
kubectl get externalsecret -n keycloak keycloak-postgresql-credentials
# STATUS: SecretSynced=True, Ready=True

# 6. Validar K8s secret criado pelo ESO
kubectl get secret -n keycloak keycloak-postgresql-credentials -o yaml
# Deve conter: password, username, host, port, database

# 7. Validar Keycloak pods Running
kubectl get pods -n keycloak
# STATUS: 2/2 Running

# 8. Keycloak health check
kubectl exec -n keycloak keycloak-0 -- curl -f http://localhost:8080/health/ready

# 9. OIDC endpoint
kubectl port-forward -n keycloak svc/keycloak-http 8080:8080 &
curl http://localhost:8080/realms/master/.well-known/openid-configuration | jq .
```

## ✅ Validação de Idempotência (OBRIGATÓRIO)

```bash
# Após apply bem-sucedido, re-plan DEVE retornar "No changes"
terraform plan -target=module.vault_config_staging -target=module.keycloak_staging

# Resultado esperado:
# "No changes. Your infrastructure matches the configuration."

# Se houver diff → DRIFT detectado → investigar e corrigir .tf
```

## 📊 Checklist Final

```
[ ] Vault K8s auth habilitado (vault auth list | grep kubernetes)
[ ] Policy eso-reader criada (vault policy read eso-reader)
[ ] Role eso-reader criada (vault read auth/kubernetes/role/eso-reader)
[ ] Secret keycloak/postgresql existe no Vault
[ ] ClusterSecretStore status Ready=True
[ ] ExternalSecret status SecretSynced=True
[ ] K8s secret keycloak-postgresql-credentials criado
[ ] Keycloak pods 2/2 Running
[ ] Keycloak health check OK (200)
[ ] OIDC endpoints responding
[ ] terraform plan = "No changes" (idempotência)
```

## 🔄 Rollback (em caso de erro)

```bash
# Destruir apenas recursos criados
terraform destroy \
  -target=module.keycloak_staging \
  -target=module.vault_config_staging

# Verificar limpeza
kubectl get externalsecret,secret -n keycloak | grep keycloak-postgresql
kubectl get pods -n keycloak

# Re-apply após correção
terraform plan -target=module.vault_config_staging -target=module.keycloak_staging -out=tfplan
terraform apply tfplan
```

## 📝 Troubleshooting

| Problema | Diagnóstico | Solução |
|----------|-------------|---------|
| **ClusterSecretStore Ready=False** | `kubectl describe clustersecretstore vault-backend` | Verificar Vault acessível: `kubectl exec -n external-secrets-system <eso-pod> -- curl -v http://vault.vault-system.svc.cluster.local:8200/v1/sys/health` |
| **ExternalSecret SecretSynced=False** | `kubectl describe externalsecret -n keycloak keycloak-postgresql-credentials` | Verificar logs ESO: `kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets` |
| **Keycloak CrashLoopBackOff** | `kubectl logs -n keycloak keycloak-0` | Verificar PostgreSQL connection: `kubectl exec -n keycloak keycloak-0 -- nc -zv postgresql-external.default.svc.cluster.local 5432` |
| **Secret não criado** | `kubectl get events -n keycloak --sort-by='.lastTimestamp'` | Verificar RBAC ESO: `kubectl auth can-i create secrets --as=system:serviceaccount:external-secrets-system:external-secrets -n keycloak` |
| **Vault auth permission denied** | `kubectl logs -n external-secrets-system <eso-pod>` | Validar role binding: `kubectl exec -n vault-system vault-0 -- vault read auth/kubernetes/role/eso-reader` |

## 🎯 Resultado Esperado

Após deploy bem-sucedido:

- ✅ Vault K8s auth configurado (role `eso-reader`)
- ✅ Secrets Keycloak gerenciados pelo Vault KV v2
- ✅ ESO sincronizando secrets automaticamente (refresh: 1h)
- ✅ Keycloak 2 replicas Running com HA
- ✅ Pattern ESO+Vault validado (replicável para GitLab, Harbor, SonarQube)
- ✅ R-029 completamente resolvido (conformidade 100% ADR-032)
- ✅ Zero dependência AWS Secrets Manager
- ✅ Idempotência garantida (terraform plan = No changes)

## 📄 Próximos Passos (opcional)

1. Migrar GitLab para mesmo pattern:
   ```bash
   # Criar secret no Vault
   kubectl exec -n vault-system vault-0 -- vault kv put secret/gitlab/postgresql \
     password="..." username="gitlab_user" host="..." port="5432" database="gitlab"

   # Atualizar módulo GitLab para usar ExternalSecret
   ```

2. Migrar Harbor para mesmo pattern:
   ```bash
   kubectl exec -n vault-system vault-0 -- vault kv put secret/harbor/registry \
     password="..." username="admin"
   ```

3. Habilitar auto-rotation de secrets:
   ```bash
   # Vault dynamic secrets (PostgreSQL backend)
   kubectl exec -n vault-system vault-0 -- vault secrets enable database
   ```
