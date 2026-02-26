# ADR-083: Automated Secret Rotation Strategy

**Data**: 2026-02-26
**Status**: Accepted
**Decisor**: Platform Engineering
**Contexto**: CICD-003 — Quarterly Secret Rotation Automation
**Referencia**: ADR-003 (Secrets Management), ADR-052 (Velero), secret-rotation-policy.md

---

## Contexto

### Problema

A plataforma Kubernetes (staging) possui **10 ExternalSecrets sincronizados** e **6 clients SSO** configurados via Keycloak. A rotacao de credenciais era 100% manual, documentada em `docs/runbooks/secret-rotation-policy.md`, mas sem automacao.

Riscos do processo manual:
- **Esquecimento**: sem alarme de vencimento de credencial, rotacoes eram adiadas
- **Erro humano**: sequencia de passos errada pode causar split-brain (RDS alterado, Vault nao atualizado)
- **Inconsistencia**: sem registro auditavel de quando cada credencial foi rotacionada
- **Escala**: 4 databases + 1 admin Keycloak + 6 OIDC clients = 11 objetos para rotacionar manualmente

### Estado Pre-Decisao (2026-02-26)

| Componente | Status |
|-----------|--------|
| Vault + ESO | 100% coverage (10/10 ExternalSecrets synced) |
| Rotacao manual | Documentada, nao automatizada |
| Monitoring de idade | Ausente |
| Alertas de falha | Ausentes |
| Ultimo ciclo de rotacao | 2026-02-11 (Keycloak), 2026-02-14 (Harbor/SonarQube) |

---

## Decisao

**Implementar rotacao automatica trimestral via Kubernetes CronJob** com as seguintes caracteristicas:

### Arquitetura de Rotacao

```
CronJob: secret-rotator (schedule: "0 2 1 */3 *")
  Namespace: staging-security-vault
  Image: vault:1.15.0
  ServiceAccount: secret-rotator (Vault policy: secret-rotator.hcl)
         |
         v
  ┌──────────────────────────────────────────┐
  │          rotate-secrets.sh               │
  │                                          │
  │  Phase 1: rotate_postgresql_passwords()  │
  │    ├─ keycloak_user / keycloak DB        │
  │    ├─ gitlab_user / gitlabhq_production  │
  │    ├─ harbor_user / registry             │
  │    └─ sonarqube_user / sonarqube         │
  │                                          │
  │  Phase 2: rotate_keycloak_admin()        │
  │    └─ admin / master realm               │
  │                                          │
  │  Phase 3: rotate_oidc_clients()          │
  │    ├─ grafana (OIDC)                     │
  │    ├─ argocd (OIDC)                      │
  │    ├─ harbor (OIDC)                      │
  │    ├─ gitlab (OIDC)                      │
  │    ├─ vault (OIDC)                       │
  │    └─ sonarqube (SAML SP key)            │
  └──────────────────────────────────────────┘
         |
         v
  Vault KV v2 (writes new secrets)
         |
         v
  ESO re-syncs K8s Secrets (within 1h, refreshInterval configured)
         |
         v
  Workloads pick up new secrets on next restart
```

### Schedule

`0 2 1 */3 *` — 02:00 UTC no dia 1 de cada trimestre:
- 2026-04-01T02:00Z
- 2026-07-01T02:00Z
- 2026-10-01T02:00Z
- 2027-01-01T02:00Z

### Grace Period (24 horas)

A rotacao ocorre sem restart imediato de workloads. O fluxo e:

```
T+0h   CronJob executa — novas credenciais escritas no Vault
T+0h   ESO detecta nova versao KV — agenda re-sync
T+1h   ESO re-sincroniza K8s Secrets com novas credenciais
T+1h   K8s Secrets atualizados (workloads ainda usam credenciais antigas da memória)
T+24h  Proxima reinicializacao natural de pods (rolling updates, healthchecks, etc.)
       Workloads montam novos secrets — credenciais novas ativas
T+24h  Credenciais antigas podem ser invalidadas (se aplicavel)
```

O grace period de 24h garante que:
- ESO tenha tempo para re-sincronizar (refreshInterval: 1h)
- Workloads nao sejam forcados a reiniciar fora de horario de pico
- Rollback seja possivel se nova credencial for invalida

---

## Alternativas Consideradas

### A1: AWS Secrets Manager + Lambda de Rotacao

**Rejeitada** por:
- Custo adicional (Lambda invocations, Secrets Manager por secret)
- Duplicacao de responsabilidades com Vault (ja e o sistema de secrets)
- Acoplamento a AWS API (perda de portabilidade)
- Maior complexidade de IAM

### A2: Rotacao manual com lembrete de calendario

**Rejeitada** por:
- Nao resolve o risco de esquecimento
- Nao gera trilha de auditoria automatica
- Escala mal com crescimento do numero de secrets

### A3: Vault Dynamic Secrets (rotacao nativa Vault)

**Considerada para iteracao futura** (nao implementada agora por):
- Requer configuracao do Vault Database Engine (adicional ao KV v2 atual)
- Mudanca de paradigma: ESO leria credentials dinamicas a cada sync
- Maior complexidade de implementacao no prazo atual
- Recomendada para producao futura (ADR a criar)

### A4: CronJob Kubernetes (ESCOLHIDA)

**Vantagens**:
- Reutiliza infra existente (Vault, ESO, Kubernetes)
- Zero custo adicional de infraestrutura
- Auditavel (logs do Job + metadata em Vault)
- Testavel (dry-run mode)
- Rollback possivel (Vault KV v2 mantem versoes anteriores)
- Sem vendor lock-in

---

## Componentes Criados

| Artefato | Localizacao |
|---------|------------|
| Vault policy | `platform-provisioning/aws/kubernetes/terraform/modules/vault-config/vault_policies/secret-rotator.hcl` |
| Terraform (CronJob + RBAC) | `domains/security/terraform/cronjob-secret-rotation.tf` |
| Shell script | `scripts/vault/rotate-secrets.sh` |
| PrometheusRule | `domains/observability/infra/alerts/secret-rotation-prometheus-rules.yaml` |
| Runbook (troubleshooting) | `docs/runbooks/secret-rotation-troubleshooting.md` |
| Runbook (emergencia) | `docs/runbooks/secret-rotation-emergency-manual.md` |

---

## Seguranca

### Principle of Least Privilege

O ServiceAccount `secret-rotator` tem:
- **Vault**: apenas write nos paths de credenciais de aplicacao + read-self token
- **Kubernetes RBAC**: apenas get/list de secrets e configmaps no namespace `staging-security-vault`
- **RDS**: usa credenciais de admin RDS (via ESO) apenas para ALTER USER — nao tem acesso a dados

### Token de Vault

O Vault token do rotator e armazenado como secret Kubernetes sincronizado via ESO:
```
Vault KV: secret/secret-rotator/token
    ↓ ESO sync
K8s Secret: secret-rotator-vault-token (namespace: staging-security-vault)
    ↓ envFrom
CronJob Container env: VAULT_TOKEN
```

O token deve ser um **service token** (nao root token) criado com:
```bash
vault token create \
  -policy=secret-rotator \
  -ttl=8760h \           # 1 ano (renovado pelo script)
  -renewable=true \
  -display-name=secret-rotator-cronjob
```

### Container Security

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 100         # Vault image UID
  readOnlyRootFilesystem: false  # Vault CLI precisa de /tmp
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
```

### Auditoria

Cada rotacao grava em `secret/secret-rotator/last-rotation`:
```
rotation_id  = rotation-20260401020000
rotation_date = 2026-04-01T02:00:00Z
status       = success | partial | failed
errors       = 0
dry_run      = false
rotate_only  = all
```

---

## Observabilidade

### Alertas Prometheus (PrometheusRule: cicd003-secret-rotation-alerts)

| Alert | Severidade | Condicao |
|-------|-----------|---------|
| SecretRotationFailed | critical | Job com status failed > 0 |
| SecretRotationNotRun | warning | ultimo sucesso > 95 dias |
| SecretRotationCronJobMissing | warning | CronJob ausente no kube-state-metrics |
| SecretRotationRunningTooLong | warning | Job ativo por > 40 min |
| SecretAgeExceeded | warning | Secret Vault com > 100 dias sem update |

### Grafana Dashboard

Metricas para construir dashboard (kube-state-metrics):
```promql
# Tempo desde ultima rotacao bem-sucedida
(time() - kube_cronjob_status_last_successful_time{cronjob="secret-rotator"}) / 86400

# Historico de sucesso/falha
kube_job_status_succeeded{job_name=~"secret-rotator.*"}
kube_job_status_failed{job_name=~"secret-rotator.*"}
```

---

## Operacao

### Deploy Inicial

```bash
# 1. Registrar policy no Vault
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

# 3. Criar RDS admin secret no Vault (se nao existir)
vault kv put secret/postgresql-admin/password \
  username=postgres_admin \
  password="<rds_admin_password>"

# 4. Apply Terraform
cd domains/security/terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# 5. Apply PrometheusRule
kubectl apply -f domains/observability/infra/alerts/secret-rotation-prometheus-rules.yaml

# 6. Testar com dry-run
kubectl create job --from=cronjob/secret-rotator secret-rotator-dryrun-$(date +%Y%m%d) \
  -n staging-security-vault
kubectl set env job/secret-rotator-dryrun-$(date +%Y%m%d) DRY_RUN=true \
  -n staging-security-vault
```

### Trigger Manual

```bash
# Rotacao completa (producao)
kubectl create job --from=cronjob/secret-rotator secret-rotator-manual-$(date +%Y%m%d) \
  -n staging-security-vault

# Apenas PostgreSQL
kubectl create job --from=cronjob/secret-rotator secret-rotator-pg-$(date +%Y%m%d) \
  -n staging-security-vault
kubectl set env job/secret-rotator-pg-$(date +%Y%m%d) ROTATE_ONLY=postgresql \
  -n staging-security-vault

# Monitorar execucao
kubectl logs -f -n staging-security-vault \
  -l app.kubernetes.io/name=secret-rotator
```

### Rollback

O Vault KV v2 mantem versoes anteriores. Para reverter uma credencial:
```bash
# Listar versoes
vault kv metadata get secret/keycloak/postgresql

# Restaurar versao anterior
vault kv rollback -version=<N> secret/keycloak/postgresql

# Forcara ESO re-sync
kubectl annotate externalsecret keycloak-postgresql-credentials \
  -n staging-platform-keycloak \
  force-sync=$(date +%s)
```

---

## Consequencias

### Positivas
- Rotacao trimestral automatica para 11 objetos de credencial
- Trilha de auditoria em Vault + logs de CronJob
- Alertas proativos de falha e envelhecimento de secrets
- Dry-run para testes seguros
- Rollback via Vault KV v2 versions
- Custo zero de infraestrutura adicional

### Negativas / Riscos
- **Split-brain window**: se script falha entre ALTER USER (RDS) e vault kv put, RDS e Vault ficam dessincronizados por ate 24h (mitigado por logs detalhados e runbook de recuperacao)
- **psql nao disponivel no container vault:1.15.0**: PostgreSQL ALTER USER requer init container adicional com postgres:16-alpine, ou execucao manual pos-rotacao de Vault
- **Restart nao forcado**: workloads so pegam novas credenciais no proximo restart (aceito pelo grace period de 24h)
- **Vault token expiracao**: token de servico tem TTL de 1 ano — necessario renovacao ou re-criacao anual

### Divida Tecnica (Proximos Passos)
- [ ] Migrar para Vault Dynamic Secrets (Database Engine) — eliminaria o split-brain
- [ ] Adicionar init container postgres:16-alpine para garantir ALTER USER no container
- [ ] Implementar rollout restart automatico pos-rotacao (com janela de manutencao)
- [ ] Dashboard Grafana dedicado para metricas de rotacao
- [ ] Vault Agent Injector como alternativa ao ESO para este caso de uso

---

## Referencias

- [CICD-003] `docs/logbook/2026-02-26-cicd-003-secret-rotation-implementation.md`
- [ADR-003] `docs/adr/adr-003-secrets-management-strategy.md`
- [Vault Policy] `platform-provisioning/aws/kubernetes/terraform/modules/vault-config/vault_policies/secret-rotator.hcl`
- [Rotation Policy] `docs/runbooks/secret-rotation-policy.md`
- [Troubleshooting] `docs/runbooks/secret-rotation-troubleshooting.md`
- [Emergency] `docs/runbooks/secret-rotation-emergency-manual.md`
