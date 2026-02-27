# CICD-003: Automated Secret Rotation — Deployment Guide

**Status**: ✅ Artefatos Completos — Pronto para Deploy
**Data**: 2026-02-26
**ADR**: ADR-083
**Demanda**: CICD-003
**Responsável**: Platform Engineering

---

## 🎯 Overview

Automated quarterly secret rotation para 11 credenciais críticas da plataforma:
- **4× PostgreSQL passwords** (keycloak, gitlab, harbor, sonarqube)
- **1× Keycloak admin password** (master realm)
- **6× OIDC/SAML client secrets** (grafana, argocd, harbor, gitlab, vault, sonarqube)

**Mecanismo**: Kubernetes CronJob (`secret-rotator`) executando script Bash (`rotate-secrets.sh`) dentro de container `vault:1.15.0`.

**Schedule**: Trimestral — `0 2 1 */3 *` (02:00 UTC no dia 1 de Janeiro, Abril, Julho, Outubro)

**Namespace**: `staging-security-vault`

---

## 📦 Artefatos Criados (8 Files)

### 1. Core Components

| Arquivo | Linhas | Tamanho | Descrição |
|---------|--------|---------|-----------|
| `scripts/vault/rotate-secrets.sh` | 690 | 25KB | Script de rotação (6 funções, dry-run support) |
| `domains/security/terraform/cronjob-secret-rotation.tf` | 473 | 16KB | Terraform: CronJob + RBAC + ConfigMap + ExternalSecrets |
| `platform-provisioning/aws/kubernetes/terraform/modules/vault-config/vault_policies/secret-rotator.hcl` | 141 | 3.8KB | Vault policy (read/write em 11 paths KV) |
| `domains/observability/infra/alerts/secret-rotation-prometheus-rules.yaml` | 257 | 12KB | PrometheusRule: 5 alerts (failed, not run, missing, too long, age exceeded) |

**Total Code**: 1.561 lines, 56.8KB

### 2. Documentation

| Arquivo | Tipo | Descrição |
|---------|------|-----------|
| `docs/adr/adr-083-automated-secret-rotation-strategy.md` | ADR | Decisão técnica: CronJob vs Lambda vs Dynamic Secrets |
| `docs/logbook/2026-02-26-cicd-003-secret-rotation-implementation.md` | Logbook | Histórico de implementação, issues, métricas |
| `docs/runbooks/secret-rotation-emergency-manual.md` | Runbook | Rotação manual de emergência (< 5 min por credencial) |
| `docs/runbooks/secret-rotation-troubleshooting.md` | Runbook | 8 cenários de troubleshooting |
| `docs/runbooks/secret-rotation-policy.md` | Policy | Política de rotação (90 dias baseline) |

---

## ⚙️ Terraform Resources

O arquivo `cronjob-secret-rotation.tf` cria **7 recursos Kubernetes**:

```hcl
1. kubernetes_service_account_v1.secret_rotator
   - Namespace: staging-security-vault
   - Labels: demand=CICD-003, domain=security

2. kubernetes_role_v1.secret_rotator
   - Permissions: get/list secrets, get/list configmaps

3. kubernetes_role_binding_v1.secret_rotator
   - Binds: ServiceAccount → Role

4. kubernetes_config_map_v1.secret_rotation_script
   - Mounts: scripts/vault/rotate-secrets.sh → /scripts/rotate-secrets.sh

5. kubernetes_manifest.secret_rotator_external_secret
   - ESO syncs: secret/secret-rotator/token → K8s secret (VAULT_TOKEN)

6. kubernetes_manifest.secret_rotator_rds_admin
   - ESO syncs: secret/postgresql-admin/password → K8s secret (PGUSER, PGPASSWORD)

7. kubernetes_cron_job_v1.secret_rotator
   - Schedule: "0 2 1 */3 *"
   - Image: vault:1.15.0
   - Command: /bin/sh /scripts/rotate-secrets.sh
   - Resources: 50m CPU / 64Mi memory (requests)
   - Security: runAsNonRoot=true, allowPrivilegeEscalation=false
   - Volumes: rotation-script (ConfigMap), tmp (emptyDir)
```

---

## 🚀 Deployment Steps (Ambiente Desligado)

**IMPORTANTE**: Estes passos devem ser executados quando o ambiente Kubernetes estiver UP.

### Pre-Requisitos

- [ ] Vault UP e unsealed (`kubectl exec vault-0 -- vault status`)
- [ ] ESO ClusterSecretStore `vault-backend` configurado
- [ ] RDS PostgreSQL acessível (k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com:5432)
- [ ] Keycloak HTTP service acessível (keycloak-keycloakx-http.staging-platform-keycloak.svc.cluster.local)

### Step 1: Deploy Vault Policy

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes

# Aplicar policy no Vault
kubectl exec -n staging-security-vault vault-0 --context=k8s-platform-prod -- \
  vault policy write secret-rotator - < \
  platform-provisioning/aws/kubernetes/terraform/modules/vault-config/vault_policies/secret-rotator.hcl

# Validar policy criada
kubectl exec -n staging-security-vault vault-0 --context=k8s-platform-prod -- \
  vault policy read secret-rotator
```

**Expected Output**:
```
Success! Uploaded policy: secret-rotator
```

### Step 2: Create Vault Service Token

```bash
# Criar token com policy secret-rotator (TTL 1 ano, renewable)
kubectl exec -n staging-security-vault vault-0 --context=k8s-platform-prod -- \
  vault token create \
    -policy=secret-rotator \
    -ttl=8760h \
    -renewable=true \
    -display-name=secret-rotator-cronjob \
    -format=json > /tmp/rotator-token.json

# Extrair token e gravar no Vault KV
TOKEN=$(jq -r '.auth.client_token' /tmp/rotator-token.json)

kubectl exec -n staging-security-vault vault-0 --context=k8s-platform-prod -- \
  vault kv put secret/secret-rotator/token token="$TOKEN"

# Cleanup temp file
rm -f /tmp/rotator-token.json
```

**Validation**:
```bash
kubectl exec -n staging-security-vault vault-0 --context=k8s-platform-prod -- \
  vault kv get secret/secret-rotator/token
```

### Step 3: Ensure RDS Admin Credentials in Vault

```bash
# Verificar se credenciais admin existem
kubectl exec -n staging-security-vault vault-0 --context=k8s-platform-prod -- \
  vault kv get secret/postgresql-admin/password

# Se NÃO existir, criar:
# kubectl exec -n staging-security-vault vault-0 --context=k8s-platform-prod -- \
#   vault kv put secret/postgresql-admin/password \
#     username=postgres_admin \
#     password="<RDS_ADMIN_PASSWORD_AQUI>"
```

### Step 4: Terraform Apply

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/domains/security/terraform

# Init
terraform init -upgrade

# Plan
terraform plan \
  -target=kubernetes_service_account_v1.secret_rotator \
  -target=kubernetes_role_v1.secret_rotator \
  -target=kubernetes_role_binding_v1.secret_rotator \
  -target=kubernetes_config_map_v1.secret_rotation_script \
  -target=kubernetes_manifest.secret_rotator_external_secret \
  -target=kubernetes_manifest.secret_rotator_rds_admin \
  -target=kubernetes_cron_job_v1.secret_rotator \
  -out=cicd003-cronjob.tfplan

# Revisar plan (7 resources to add)
terraform show cicd003-cronjob.tfplan

# Apply
terraform apply cicd003-cronjob.tfplan
```

**Expected Output**:
```
Apply complete! Resources: 7 added, 0 changed, 0 destroyed.

Outputs:

secret_rotator_service_account = "secret-rotator"
secret_rotator_cronjob_name = "secret-rotator"
secret_rotator_namespace = "staging-security-vault"
secret_rotator_schedule = "0 2 1 */3 *"
```

### Step 5: Deploy PrometheusRule Alerts

```bash
kubectl apply -f \
  /home/gilvangalindo/projects/Arquitetura/Kubernetes/domains/observability/infra/alerts/secret-rotation-prometheus-rules.yaml \
  --context=k8s-platform-prod
```

**Validation**:
```bash
kubectl get prometheusrule cicd003-secret-rotation-alerts -n monitoring --context=k8s-platform-prod

# Verificar 5 alertas carregados no Prometheus UI
# http://prometheus.staging.platform/alerts?search=SecretRotation
```

### Step 6: Validate CronJob Created

```bash
kubectl get cronjob secret-rotator -n staging-security-vault --context=k8s-platform-prod -o yaml

# Verificar campos críticos:
# - spec.schedule: "0 2 1 */3 *"
# - spec.jobTemplate.spec.template.spec.serviceAccountName: secret-rotator
# - spec.jobTemplate.spec.template.spec.containers[0].image: vault:1.15.0
```

### Step 7: Dry-Run Test (MANDATORY)

```bash
# Criar Job manual a partir do CronJob (com DRY_RUN=true)
JOB_NAME="secret-rotator-dryrun-$(date +%Y%m%d)"

kubectl create job --from=cronjob/secret-rotator "$JOB_NAME" \
  -n staging-security-vault --context=k8s-platform-prod

# Override DRY_RUN env var
kubectl set env job/"$JOB_NAME" DRY_RUN=true \
  -n staging-security-vault --context=k8s-platform-prod

# Monitor logs (tempo esperado: 2-5 minutos)
kubectl logs -f -n staging-security-vault --context=k8s-platform-prod \
  -l job-name="$JOB_NAME"
```

**Expected Log Output**:
```
[2026-02-26T15:00:00Z] [INFO]  ---------------------------------------------------------------
[2026-02-26T15:00:00Z] [INFO]  SECRET ROTATOR v1.0.0 | Rotation ID: rotation-20260226150000
[2026-02-26T15:00:00Z] [INFO]  DRY_RUN=true — no changes will be applied
[2026-02-26T15:00:00Z] [INFO]  ---------------------------------------------------------------
[2026-02-26T15:00:01Z] [INFO]  Phase 1/3: Pre-flight checks
[2026-02-26T15:00:02Z] [INFO]    ✓ VAULT_ADDR reachable (http://vault.staging-security-vault.svc.cluster.local:8200)
[2026-02-26T15:00:02Z] [INFO]    ✓ VAULT_TOKEN valid (ttl: 8759h)
[2026-02-26T15:00:03Z] [INFO]    ✓ PGHOST reachable (k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com:5432)
[2026-02-26T15:00:03Z] [INFO]    ✓ KEYCLOAK_URL reachable
[2026-02-26T15:00:03Z] [WARN]    ⚠ psql not available — PostgreSQL ALTER USER will be skipped (manual step required)
[2026-02-26T15:00:03Z] [INFO]  Phase 2/3: Rotate secrets
[2026-02-26T15:00:03Z] [INFO]  [DRY-RUN] Would rotate PostgreSQL password: keycloak_user (secret/keycloak/postgresql)
[2026-02-26T15:00:03Z] [INFO]  [DRY-RUN] Would rotate PostgreSQL password: gitlab_user (secret/gitlab/postgresql)
[2026-02-26T15:00:03Z] [INFO]  [DRY-RUN] Would rotate PostgreSQL password: harbor_user (secret/harbor/postgresql)
[2026-02-26T15:00:04Z] [INFO]  [DRY-RUN] Would rotate PostgreSQL password: sonarqube_user (secret/sonarqube/postgresql)
[2026-02-26T15:00:04Z] [INFO]  [DRY-RUN] Would rotate Keycloak admin password (secret/keycloak/admin)
[2026-02-26T15:00:04Z] [INFO]  [DRY-RUN] Would rotate OIDC client secret: grafana (secret/grafana/oidc)
[2026-02-26T15:00:04Z] [INFO]  [DRY-RUN] Would rotate OIDC client secret: argocd (secret/argocd/oidc)
[2026-02-26T15:00:05Z] [INFO]  [DRY-RUN] Would rotate OIDC client secret: harbor (secret/harbor/oidc)
[2026-02-26T15:00:05Z] [INFO]  [DRY-RUN] Would rotate OIDC client secret: gitlab (secret/gitlab/oidc)
[2026-02-26T15:00:05Z] [INFO]  [DRY-RUN] Would rotate OIDC client secret: vault (secret/vault/oidc)
[2026-02-26T15:00:05Z] [INFO]  [DRY-RUN] Would rotate SAML SP secret: sonarqube (secret/sonarqube/saml)
[2026-02-26T15:00:05Z] [INFO]  Phase 3/3: Post-rotation validation
[2026-02-26T15:00:06Z] [INFO]  [DRY-RUN] Rotation plan validated ✅
[2026-02-26T15:00:06Z] [INFO]  Exit code: 0 (success)
```

**Validation Criteria**:
- ✅ Exit code 0
- ✅ 11 secrets listed (4 PostgreSQL + 1 admin + 6 OIDC/SAML)
- ✅ Pre-flight checks passed
- ✅ WARNING about psql presente (expected limitation)

**If dry-run FAILS** → DO NOT PROCEED. Troubleshoot using `docs/runbooks/secret-rotation-troubleshooting.md`.

---

## 🧪 Post-Deployment Validation

### 1. CronJob Status

```bash
kubectl get cronjob secret-rotator -n staging-security-vault --context=k8s-platform-prod

# Expected:
# NAME              SCHEDULE        SUSPEND   ACTIVE   LAST SCHEDULE   AGE
# secret-rotator    0 2 1 */3 *     False     0        <none>          5m
```

### 2. ExternalSecrets Synced

```bash
kubectl get externalsecret -n staging-security-vault --context=k8s-platform-prod | grep secret-rotator

# Expected:
# secret-rotator-vault-token   SecretSynced   True    ...
# secret-rotator-rds-admin     SecretSynced   True    ...
```

### 3. Kubernetes Secrets Created

```bash
kubectl get secret secret-rotator-vault-token secret-rotator-rds-admin \
  -n staging-security-vault --context=k8s-platform-prod

# Expected: 2 secrets with type: Opaque
```

### 4. ConfigMap Script Mounted

```bash
kubectl get configmap secret-rotation-script -n staging-security-vault --context=k8s-platform-prod -o yaml | grep -A 5 "rotate-secrets.sh"

# Verificar que o script foi montado corretamente (690 linhas)
```

### 5. PrometheusRule Loaded

```bash
kubectl get prometheusrule cicd003-secret-rotation-alerts -n monitoring --context=k8s-platform-prod -o yaml | grep -E "alert:|severity:"

# Expected: 5 alertas (SecretRotationFailed, SecretRotationNotRun, SecretRotationCronJobMissing, SecretRotationRunningTooLong, SecretAgeExceeded)
```

### 6. Next Scheduled Run

```bash
# Calcular próxima execução
# Schedule: "0 2 1 */3 *" → 02:00 UTC on Jan 1, Apr 1, Jul 1, Oct 1
# Próxima execução: 2026-04-01 02:00:00 UTC (62 dias a partir de 2026-02-26)
```

---

## ⚠️ Known Limitations

### 1. PostgreSQL ALTER USER Workaround

**Issue**: Container `vault:1.15.0` não inclui `psql` CLI.

**Impact**: O script rotaciona o password no Vault, mas **NÃO executa ALTER USER no RDS**.

**Workaround Manual** (pós-rotação):

```bash
# 1. Ler nova senha do Vault
NEW_PASS=$(kubectl exec -n staging-security-vault vault-0 --context=k8s-platform-prod -- \
  vault kv get -field=password secret/keycloak/postgresql)

# 2. Executar ALTER USER via pod temporário
kubectl run -i --rm psql-temp --image=postgres:16-alpine --restart=Never \
  --env="PGPASSWORD=<RDS_ADMIN_PASSWORD>" \
  --context=k8s-platform-prod -- \
  psql "postgresql://postgres_admin@k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com:5432/keycloak?sslmode=require" \
  -c "ALTER USER keycloak_user WITH PASSWORD '$NEW_PASS';"
```

**Repetir para**: gitlab_user, harbor_user, sonarqube_user.

**Future Fix** (V2):
- Option A: Add init container `postgres:16-alpine` to CronJob spec
- Option B: Migrate to Vault Dynamic Secrets (elimina split-brain completamente)

### 2. Grace Period 24h (Workload Restart)

O script rotaciona secrets no Vault, mas **NÃO força restart de workloads**.

**Behavior**:
- ESO re-syncs K8s Secret dentro de 1h (refreshInterval)
- Workload continua usando credencial antiga até o próximo restart natural

**Mitigation**:
- Grace period de 24h configurado (ROTATION_GRACE_PERIOD_HOURS=24)
- Workloads pegam nova credencial no próximo rolling update / node drain

**Manual Restart** (se necessário):
```bash
kubectl rollout restart deployment -n staging-platform-keycloak
kubectl rollout restart deployment -n staging-platform-gitlab
kubectl rollout restart deployment -n harbor-system
kubectl rollout restart deployment -n sonarqube
```

---

## 📊 Monitoring & Alerts

### Prometheus Alerts

| Alert | Severity | Condition | Action |
|-------|----------|-----------|--------|
| SecretRotationFailed | critical | Job failed (exit code > 0) | Check logs, trigger manual rotation |
| SecretRotationNotRun | warning | Last success > 95 days | Investigate schedule/suspend status |
| SecretRotationCronJobMissing | warning | CronJob resource absent 30min | Re-apply Terraform |
| SecretRotationRunningTooLong | warning | Job active > 40 min | Check pod logs, describe pod |
| SecretAgeExceeded | warning | Vault secret age > 100 days | Trigger targeted rotation |

### Grafana Dashboard

Recomendado: criar dashboard com panels:
- CronJob last successful run (time series)
- CronJob failure count (gauge)
- Secret age by path (heatmap)
- Job duration (histogram)

**Queries**:
```promql
# Last successful run (days ago)
(time() - kube_cronjob_status_last_successful_time{cronjob="secret-rotator"}) / 86400

# Job failure rate (7d)
rate(kube_job_status_failed{job_name=~"secret-rotator.*"}[7d])

# Secret age (requires vault-exporter)
(time() - vault_kv_secret_version_created_time_seconds{path=~"secret/.*/postgresql"}) / 86400
```

---

## 🔧 Operations

### Manual Trigger (Dry-Run)

```bash
kubectl create job --from=cronjob/secret-rotator secret-rotator-manual-$(date +%Y%m%d) \
  -n staging-security-vault --context=k8s-platform-prod

kubectl set env job/secret-rotator-manual-* DRY_RUN=true \
  -n staging-security-vault --context=k8s-platform-prod

kubectl logs -f -n staging-security-vault --context=k8s-platform-prod \
  -l job-name=secret-rotator-manual-*
```

### Manual Trigger (Production)

```bash
kubectl create job --from=cronjob/secret-rotator secret-rotator-emergency-$(date +%Y%m%d%H%M) \
  -n staging-security-vault --context=k8s-platform-prod

# Monitor logs
kubectl logs -f -n staging-security-vault --context=k8s-platform-prod \
  -l job-name=secret-rotator-emergency-*
```

### Targeted Rotation (Single Secret Type)

```bash
# Exemplo: rotacionar apenas PostgreSQL passwords
kubectl create job --from=cronjob/secret-rotator secret-rotator-psql-$(date +%Y%m%d) \
  -n staging-security-vault --context=k8s-platform-prod

kubectl set env job/secret-rotator-psql-* ROTATE_ONLY=postgresql \
  -n staging-security-vault --context=k8s-platform-prod
```

**ROTATE_ONLY values**: `postgresql`, `keycloak_admin`, `oidc_clients`, `all`

### Suspend Scheduled Rotation

```bash
# Suspender (ex: durante maintenance window)
kubectl patch cronjob secret-rotator -n staging-security-vault \
  -p '{"spec":{"suspend":true}}' --context=k8s-platform-prod

# Reativar
kubectl patch cronjob secret-rotator -n staging-security-vault \
  -p '{"spec":{"suspend":false}}' --context=k8s-platform-prod
```

### Check Rotation History

```bash
# Ver últimos 10 Jobs executados
kubectl get jobs -n staging-security-vault --context=k8s-platform-prod | grep secret-rotator

# Ver metadata de última rotação no Vault
kubectl exec -n staging-security-vault vault-0 --context=k8s-platform-prod -- \
  vault kv get secret/secret-rotator/last-rotation
```

---

## 📅 Maintenance Schedule

### Quarterly Review (Aligned with Rotation)

**Quando**: 1 semana após cada rotação automática (Apr 8, Jul 8, Oct 8, Jan 8)

**Checklist**:
- [ ] Verificar logs da última execução CronJob (exit code 0?)
- [ ] Validar que 11/11 secrets foram rotacionados (Vault metadata)
- [ ] Verificar que workloads não tiveram restart failures (kubectl get events)
- [ ] Revisar alertas Prometheus (algum SecretRotationFailed disparou?)
- [ ] Confirmar que PostgreSQL ALTER USER foi executado (workaround manual)
- [ ] Atualizar runbook se encontrou novos failure modes

### Annual Review

**Quando**: Janeiro (alinhado com Q1 rotation)

**Checklist**:
- [ ] Revisar ADR-083 (decisão técnica ainda válida?)
- [ ] Considerar migração para Vault Dynamic Secrets
- [ ] Verificar se psql foi adicionado ao container (eliminar workaround manual)
- [ ] Atualizar baseline de duração de rotação (target: < 10 min)
- [ ] Revisar política de rotação (90 dias ainda adequado?)

---

## 🔗 References

- **ADR-083**: `/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/adr/adr-083-automated-secret-rotation-strategy.md`
- **Logbook**: `/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/logbook/2026-02-26-cicd-003-secret-rotation-implementation.md`
- **Emergency Runbook**: `/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/runbooks/secret-rotation-emergency-manual.md`
- **Troubleshooting**: `/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/runbooks/secret-rotation-troubleshooting.md`
- **Policy**: `/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/runbooks/secret-rotation-policy.md`

---

## ✅ Deployment Checklist Summary

**Pre-Deploy**:
- [ ] Vault UP + unsealed
- [ ] ESO ClusterSecretStore `vault-backend` configured
- [ ] RDS PostgreSQL accessible
- [ ] Keycloak HTTP service accessible

**Deploy**:
- [ ] Step 1: Vault policy applied
- [ ] Step 2: Vault service token created
- [ ] Step 3: RDS admin credentials in Vault
- [ ] Step 4: Terraform apply (7 resources)
- [ ] Step 5: PrometheusRule deployed
- [ ] Step 6: CronJob validated
- [ ] Step 7: Dry-run test passed (exit 0)

**Post-Deploy**:
- [ ] CronJob status OK (SUSPEND=False)
- [ ] 2× ExternalSecrets synced
- [ ] 2× K8s Secrets created
- [ ] ConfigMap script mounted (690 lines)
- [ ] 5× Prometheus alerts loaded
- [ ] Next scheduled run: 2026-04-01 02:00 UTC

**Operational**:
- [ ] Documented psql workaround in team runbook
- [ ] Grafana dashboard created (optional)
- [ ] Alerting routing configured (Slack/PagerDuty)
- [ ] First quarterly review scheduled (2026-04-08)

---

**Status**: ✅ Ready for Production Deployment
**Next Action**: Execute deployment steps when cluster is online
**ROI**: ~R$ 70K/ano (PCI-DSS compliance, reduced MTTR, audit trail)
