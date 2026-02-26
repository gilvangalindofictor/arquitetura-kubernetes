# Logbook: CICD-003 — Automated Secret Rotation Implementation

**Data**: 2026-02-26
**Duracao**: ~2 horas
**Status**: Artefatos criados — aguardando apply (ambiente desligado)
**Responsavel**: Platform Engineering (Claude Code)
**ADR**: ADR-083
**Demanda**: CICD-003

---

## Contexto

Apos completar V-008/009/011/012 (Velero DR Stack) e TASK-002 (Keycloak IaC), a
proxima prioridade de seguranca era automatizar a rotacao trimestral de credenciais
da plataforma.

Estado pre-implementacao:
- 10/10 ExternalSecrets sincronizados (100% ESO coverage)
- 6 clients OIDC/SAML configurados via Keycloak
- Rotacao de credentials: **100% manual**, sem alertas, sem auditoria automatica

---

## Decisoes Tecnicas

### Container image: vault:1.15.0

Escolhido por:
- Vault CLI ja disponivel (sem instalacao adicional)
- Imagem oficial HashiCorp (auditada)
- `wget` disponivel para chamadas Keycloak API

Limitacao identificada: **psql nao disponivel** no container vault:1.15.0.
Consequencia: ALTER USER PostgreSQL requer um dos seguintes workarounds:
1. Adicionar init container `postgres:16-alpine` (proxima iteracao)
2. Usar `kubectl run` manual pos-rotacao de Vault (documentado no runbook de emergencia)
3. Usar AWS RDS Data API (alternativa futura)

Por ora, o script detecta a ausencia de psql e loga warning, gravando o novo
password no Vault mas sinalizando a necessidade de ALTER USER manual.

### Sequencia de rotacao (ordem importa)

1. PostgreSQL primeiro — sem dependencias entre si
2. Keycloak admin segundo — necessario para passo 3
3. OIDC clients terceiro — usa token do admin rotacionado em (2)

### Grace period de 24h (nao forca restart de workloads)

Decisao deliberada para evitar indisponibilidade fora de janela de manutencao.
O ESO re-sincroniza dentro de 1h (refreshInterval: 1h). Workloads pegam novos
secrets no proximo restart natural (rolling update, node drain, etc.).

Risco aceito: janela de 0-24h onde workload usa credencial velha do Vault mas
RDS ja tem nova. Mitigado porque:
- O ESO so sincroniza o K8s Secret, workload nao le diretamente do K8s Secret em runtime (la de memoria/disk)
- A maioria dos workloads (Keycloak, GitLab, Harbor) abre conexoes DB ao iniciar e nao recarregam automaticamente

---

## Artefatos Criados

### 1. Vault Policy

**Arquivo**: `platform-provisioning/aws/kubernetes/terraform/modules/vault-config/vault_policies/secret-rotator.hcl`

Permissoes:
- `read/create/update` em `secret/data/{keycloak,gitlab,harbor,sonarqube}/postgresql`
- `read/create/update` em `secret/data/keycloak/admin`
- `read/create/update` em `secret/data/{grafana,argocd,harbor,gitlab,vault}/oidc`
- `read/create/update` em `secret/data/sonarqube/saml`
- `read` em `secret/data/postgresql-admin/*` (para ALTER USER)
- `read/create/update` em `secret/data/secret-rotator/*` (metadata de auditoria)
- `update` em `auth/token/renew-self` (renovacao durante runs longas)

### 2. Terraform — CronJob + RBAC

**Arquivo**: `domains/security/terraform/cronjob-secret-rotation.tf`

Recursos:
- `kubernetes_service_account_v1.secret_rotator`
- `kubernetes_role_v1.secret_rotator` (get/list secrets + configmaps)
- `kubernetes_role_binding_v1.secret_rotator`
- `kubernetes_config_map_v1.secret_rotation_script` (monta o shell script)
- `kubernetes_manifest.secret_rotator_external_secret` (ESO → VAULT_TOKEN)
- `kubernetes_manifest.secret_rotator_rds_admin` (ESO → RDS admin creds)
- `kubernetes_cron_job_v1.secret_rotator`

Configuracao CronJob:
- Schedule: `0 2 1 */3 *` (trimestral, 02:00 UTC dia 1)
- concurrencyPolicy: Forbid
- backoffLimit: 2
- activeDeadlineSeconds: 1800 (30 min)
- restartPolicy: OnFailure
- Imagem: vault:1.15.0
- runAsUser: 100, runAsNonRoot: true, allowPrivilegeEscalation: false

### 3. Rotation Script

**Arquivo**: `scripts/vault/rotate-secrets.sh`

Funcionalidades:
- `preflight_checks()`: valida env vars, conectividade Vault/RDS/Keycloak antes de qualquer alteracao
- `rotate_postgresql_passwords()`: 4 databases (keycloak, gitlab, harbor, sonarqube)
- `rotate_keycloak_admin()`: admin master realm via Keycloak Admin REST API
- `rotate_oidc_clients()`: 5 OIDC clients + 1 SAML SP secret (sonarqube)
- `record_rotation_metadata()`: grava auditoria em `secret/secret-rotator/last-rotation`
- `post_rotation_validation()`: verifica token Vault ainda valido, paths lesiveis

Flags:
- `DRY_RUN=true`: log-only, zero alteracoes
- `ROTATE_ONLY=postgresql|keycloak_admin|oidc_clients|all`: escopo seletivo
- `LOG_LEVEL=DEBUG`: verbose logging

Exit codes:
- 0: sucesso total
- 1: erros parciais (rollback manual pode ser necessario)
- 2: pre-flight falhou (nenhuma alteracao feita — seguro)

### 4. PrometheusRule

**Arquivo**: `domains/observability/infra/alerts/secret-rotation-prometheus-rules.yaml`

Alerts:
- `SecretRotationFailed` (critical, 5m): `kube_job_status_failed{job_name=~"secret-rotator.*"} > 0`
- `SecretRotationNotRun` (warning, 1h): ultima execucao bem-sucedida > 95 dias
- `SecretRotationCronJobMissing` (warning, 30m): CronJob ausente no cluster
- `SecretRotationRunningTooLong` (warning, 5m): Job ativo > 40 min
- `SecretAgeExceeded` (warning, 2h): Secret Vault sem update > 100 dias

### 5. ADR-083

**Arquivo**: `docs/adr/adr-083-automated-secret-rotation-strategy.md`

Conteudo:
- Contexto e problema
- Decisao: CronJob vs Lambda vs Dynamic Secrets
- Arquitetura de rotacao (diagrama ASCII)
- Schedule e grace period justificados
- Security (least privilege, token management)
- Operacao (deploy inicial, trigger manual, rollback)
- Divida tecnica documentada

### 6. Runbook Troubleshooting

**Arquivo**: `docs/runbooks/secret-rotation-troubleshooting.md`

Cenarios cobertos:
1. CronJob suspended/missing
2. Pre-flight falhou (exit 2) — 4 sub-cenarios
3. Split-brain PostgreSQL (exit 1)
4. Rotacao OK, workloads falhando
5. Job travado (> 40 min)
6. Rotar apenas um secret especifico
7. OIDC client rotacionado, SSO quebrando
8. Verificar historico de rotacoes

### 7. Runbook Emergencia

**Arquivo**: `docs/runbooks/secret-rotation-emergency-manual.md`

Secoes:
1. Rotacao PostgreSQL (individual + batch + sem psql via pod temporario)
2. Rotacao Keycloak admin via REST API
3. Rotacao OIDC client secrets via Keycloak API
4. Breach response (< 5 min por credencial)
5. Verificacao pos-rotacao

---

## Proximos Passos Para Apply

```bash
# 1. Registrar Vault policy
vault policy write secret-rotator \
  platform-provisioning/aws/kubernetes/terraform/modules/vault-config/vault_policies/secret-rotator.hcl

# 2. Criar service token do rotator
vault token create \
  -policy=secret-rotator \
  -ttl=8760h \
  -renewable=true \
  -display-name=secret-rotator-cronjob \
  -format=json | jq -r .auth.client_token | \
  vault kv put secret/secret-rotator/token token=-

# 3. Garantir que RDS admin secret existe no Vault
vault kv get secret/postgresql-admin/password || \
  vault kv put secret/postgresql-admin/password \
    username=postgres_admin \
    password="<senha_do_admin_rds>"

# 4. Apply Terraform
cd domains/security/terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# 5. Apply PrometheusRule
kubectl apply -f domains/observability/infra/alerts/secret-rotation-prometheus-rules.yaml

# 6. Validar CronJob criado
kubectl get cronjob secret-rotator -n staging-security-vault

# 7. Testar com dry-run
JOB="secret-rotator-dryrun-$(date +%Y%m%d)"
kubectl create job --from=cronjob/secret-rotator $JOB -n staging-security-vault
kubectl set env job/$JOB DRY_RUN=true -n staging-security-vault
kubectl logs -f -n staging-security-vault -l job-name=$JOB
```

---

## Issues Identificados Durante Implementacao

### Issue 1: psql nao disponivel em vault:1.15.0

**Impacto**: ALTER USER PostgreSQL nao pode ser executado automaticamente
**Opcoes**:
- A) Adicionar init container postgres:16-alpine (complexifica o CronJob spec)
- B) Usar pod temporario kubectl run (requer RBAC adicional para criar pods)
- C) Aceitar comportamento atual: Vault atualizado, ALTER USER manual (documentado)

**Decisao para V1**: Opcao C (aceitar, documentar). O script loga WARN e continua.
O novo password esta no Vault. Um segundo passo manual e necessario para sincronizar o RDS.

**Para V2**: Implementar init container com postgres:16-alpine ou migrar para Vault Dynamic Secrets.

### Issue 2: Vault Dynamic Secrets seria melhor a longo prazo

O Vault Database Engine (dynamic secrets) eliminaria o split-brain completamente,
mas requer:
- Configurar vault database plugin para PostgreSQL
- Mudar ESO de KV secret para dynamic secret
- Testar impacto de credentials efemeras em workloads stateful (Keycloak, GitLab)

Documentado em ADR-083 como divida tecnica para producao.

---

## Metricas de Sucesso

| Metrica | Baseline | Objetivo |
|---------|---------|---------|
| Rotacao manual por ciclo | 11 objetos (~2h) | 0 (100% automatico) |
| MTTR de credencial comprometida | ~30 min | < 5 min (runbook emergencia) |
| Tempo sem alerta de credencial expirada | N/A | 0 dias (alertas proativos) |
| Conformidade com politica 90 dias | Parcial | 100% (CronJob garante ciclo) |

---

## Commits Relacionados

- Este logbook e todos os artefatos serao commitados juntos
- Nenhuma credencial real foi incluida em nenhum arquivo
- O script usa `vault kv get` para ler credenciais em runtime (nunca hardcoded)
