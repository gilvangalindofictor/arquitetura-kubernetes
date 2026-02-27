# Runbook: Vault Secret Rotation (CICD-003)

**Data:** 2026-02-27
**Responsavel:** Platform Engineering
**Demanda:** CICD-003
**ADR:** ADR-083 (Automated Secret Rotation Strategy)
**Namespace:** staging-security-vault
**CronJob:** secret-rotator
**Schedule:** `0 2 1 */3 *` (quarterly: 02:00 UTC on Jan 1, Apr 1, Jul 1, Oct 1)

---

## Visao Geral

O CronJob `secret-rotator` executa trimestralmente e rota automaticamente as seguintes credenciais:

| Credencial | Vault Path | Frequencia |
|-----------|------------|-----------|
| PostgreSQL (keycloak_user) | secret/keycloak/postgresql | 90 dias |
| PostgreSQL (harbor_user) | secret/harbor/postgresql | 90 dias |
| PostgreSQL (sonarqube_user) | secret/sonarqube/postgresql | 90 dias |
| PostgreSQL (gitlab_user) | secret/gitlab/postgresql | 90 dias |
| Keycloak admin password | secret/keycloak/admin | 90 dias |
| Harbor admin password | secret/harbor/admin | 90 dias |
| OIDC client secrets (5 clients) | secret/*/oidc | 90 dias |
| SAML SP metadata (SonarQube) | secret/sonarqube/saml | 90 dias |

---

## Pre-requisitos

- Vault running e unsealed: `kubectl get pods -n staging-security-vault`
- ESO ExternalSecrets synced: `kubectl get externalsecrets -A | grep -v True` (should be empty)
- Vault policy `secret-rotation` aplicada (ver secao abaixo)
- ServiceAccount `secret-rotator` com token em `secret/secret-rotator/token`

---

## Verificacao de Status Normal

```bash
# Ver status do CronJob
kubectl get cronjob secret-rotator -n staging-security-vault

# Historico de execucoes
kubectl get jobs -n staging-security-vault | grep secret-rotator

# Logs da ultima execucao
kubectl logs -n staging-security-vault \
  -l app.kubernetes.io/name=secret-rotator \
  --tail=100

# Verificar ultimo registro de rotacao no Vault
kubectl exec -n staging-security-vault vault-0 -- \
  vault kv get secret/secret-rotator/last-rotation
```

---

## Trigger de Rotacao Manual

### Dry-run (sem alteracoes)

```bash
# Criar job de dry-run
kubectl create job \
  --from=cronjob/secret-rotator \
  secret-rotator-dryrun-$(date +%Y%m%d) \
  -n staging-security-vault

# Patch DRY_RUN=true antes de criar o job (se quiser dry-run persistente)
kubectl set env cronjob/secret-rotator DRY_RUN=true -n staging-security-vault

# Reverter apos teste
kubectl set env cronjob/secret-rotator DRY_RUN=false -n staging-security-vault
```

### Rotacao real

```bash
# Trigger imediato (producao — use com cuidado)
kubectl create job \
  --from=cronjob/secret-rotator \
  secret-rotator-manual-$(date +%Y%m%d%H%M%S) \
  -n staging-security-vault

# Acompanhar logs em tempo real
kubectl logs -f \
  -n staging-security-vault \
  -l app.kubernetes.io/name=secret-rotator
```

### Rotacao parcial (somente um servico)

```bash
# Exemplo: rotacionar apenas credenciais PostgreSQL
kubectl set env cronjob/secret-rotator ROTATE_ONLY=postgresql -n staging-security-vault

kubectl create job \
  --from=cronjob/secret-rotator \
  secret-rotator-pg-$(date +%Y%m%d) \
  -n staging-security-vault

# Reverter apos execucao
kubectl set env cronjob/secret-rotator ROTATE_ONLY=all -n staging-security-vault
```

Valores validos para `ROTATE_ONLY`: `all` | `postgresql` | `keycloak_admin` | `oidc_clients`

---

## Aplicar Vault Policy

```bash
# Port-forward ao Vault
kubectl port-forward -n staging-security-vault svc/vault 8200:8200 &
export VAULT_ADDR=http://localhost:8200

# Obter token (via ExternalSecret ou manual)
export VAULT_TOKEN=$(kubectl get secret vault-admin-token \
  -n staging-security-vault \
  -o jsonpath='{.data.token}' | base64 -d)

# Aplicar policy
vault policy write secret-rotation \
  scripts/vault/vault-rotation-policy.hcl

# Verificar policy
vault policy read secret-rotation

# Criar role Kubernetes para o ServiceAccount
vault write auth/kubernetes/role/secret-rotator \
  bound_service_account_names=secret-rotator \
  bound_service_account_namespaces=staging-security-vault \
  policies=secret-rotation \
  ttl=1h

# Matar port-forward
kill %1
```

---

## Verificacao Pos-Rotacao

```bash
# 1. Verificar job completado com sucesso
kubectl get jobs -n staging-security-vault | grep secret-rotator

# 2. Verificar ExternalSecrets re-sincronizados (pode levar ate 1h)
kubectl get externalsecrets -A -o wide

# 3. Verificar que servicos continuam funcionando
kubectl get pods -n staging-platform-keycloak
kubectl get pods -n harbor-system
kubectl get pods -n staging-platform-gitlab

# 4. Verificar versao atual dos segredos no Vault
kubectl exec -n staging-security-vault vault-0 -- \
  vault kv metadata get secret/keycloak/admin

# 5. Verificar ultimo registro de rotacao
kubectl exec -n staging-security-vault vault-0 -- \
  vault kv get secret/secret-rotator/last-rotation
```

---

## Alertas Relacionados (PrometheusRule)

| Alerta | Severidade | Condicao |
|--------|-----------|---------|
| SecretRotationFailed | critical | Job failed > 0 |
| SecretRotationNotRun | warning | Last success > 95 dias |
| SecretRotationCronJobMissing | warning | CronJob ausente |
| SecretRotationRunningTooLong | warning | Job rodando > 40 min |
| SecretAgeExceeded | warning | Secret no Vault > 100 dias |

Ver arquivo: `domains/observability/infra/alerts/secret-rotation-prometheus-rules.yaml`

---

## Troubleshooting

Para problemas especificos, consultar:
- `docs/runbooks/secret-rotation-troubleshooting.md` — problemas operacionais
- `docs/runbooks/secret-rotation-emergency-manual.md` — rotacao emergencial manual
- `docs/runbooks/secret-rotation-policy.md` — politica e frequencias

---

## Rollback

Se a rotacao causar problemas (ex: servico nao consegue autenticar com novas credenciais):

```bash
# Verificar versao anterior no Vault (KV v2 mantem historico)
kubectl exec -n staging-security-vault vault-0 -- \
  vault kv get -version=1 secret/keycloak/postgresql

# Restaurar versao anterior
kubectl exec -n staging-security-vault vault-0 -- \
  vault kv rollback -version=1 secret/keycloak/postgresql

# Forcar re-sync do ExternalSecret
kubectl annotate externalsecret keycloak-postgresql-credentials \
  -n staging-platform-keycloak \
  force-sync=$(date +%s) --overwrite

# IMPORTANTE: se o banco ja foi alterado via ALTER USER e o Vault foi revertido,
# o banco e o Vault estarao dessincronizados. Nesse caso, seguir o runbook de emergencia:
# docs/runbooks/secret-rotation-emergency-manual.md
```

---

## Referencias

- ADR-083: `docs/adr/adr-083-automated-secret-rotation-strategy.md`
- Deployment Guide: `docs/deployments/cicd-003-secret-rotation-deployment-guide.md`
- Rotation Script: `scripts/vault/rotate-secrets.sh`
- Vault Policy: `scripts/vault/vault-rotation-policy.hcl`
- PrometheusRules: `domains/observability/infra/alerts/secret-rotation-prometheus-rules.yaml`
- Terraform: `domains/security/terraform/cronjob-secret-rotation.tf`
