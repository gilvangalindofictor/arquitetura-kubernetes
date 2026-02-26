# Runbook: Secret Rotation — Troubleshooting

**Versao**: 1.0
**Data**: 2026-02-26
**Contexto**: CICD-003 | ADR-083
**Audience**: Platform Engineering / SRE on-call
**Tempo estimado de resolucao**: 15-45 min (depende do cenario)

---

## Diagrama de Fluxo de Troubleshooting

```
Alert recebido (SecretRotationFailed ou SecretRotationNotRun)
        |
        v
[1] Verificar status do CronJob e Jobs recentes
        |
        +-- Jobs OK? --> Falso positivo de alerta? --> Verificar kube-state-metrics
        |
        +-- Job Failed --> [2] Verificar logs do Job
                                |
                                +-- Pre-flight FAILED (exit 2) --> [3] Conectividade
                                |
                                +-- Rotacao parcial (exit 1) --> [4] Split-brain check
                                |
                                +-- Script error --> [5] Script / ambiente
```

---

## Checklist Rapido (Primeiros 5 minutos)

```bash
# Namespace e namespace aliases
NS="staging-security-vault"

# 1. Status do CronJob
kubectl get cronjob secret-rotator -n $NS

# 2. Jobs recentes (ultimos 7)
kubectl get jobs -n $NS --sort-by=.status.startTime | tail -10

# 3. Logs do ultimo Job
kubectl logs -n $NS \
  $(kubectl get pods -n $NS -l app.kubernetes.io/name=secret-rotator \
    --sort-by=.metadata.creationTimestamp -o name | tail -1) \
  --tail=100

# 4. Ultima rotacao bem-sucedida (via Vault)
vault kv get secret/secret-rotator/last-rotation
```

---

## Cenario 1: CronJob Suspended ou Missing

**Sintoma**: `SecretRotationCronJobMissing` alert, ou CronJob com `SUSPEND: true`

```bash
# Verificar se CronJob existe
kubectl get cronjob -n staging-security-vault

# Verificar se esta suspenso
kubectl get cronjob secret-rotator -n staging-security-vault \
  -o jsonpath='{.spec.suspend}'

# Reativar se suspenso
kubectl patch cronjob secret-rotator -n staging-security-vault \
  -p '{"spec":{"suspend":false}}'

# Se CronJob nao existe — re-aplicar Terraform
cd /path/to/platform-provisioning/aws/kubernetes/terraform
terraform plan -target=kubernetes_cron_job_v1.secret_rotator
terraform apply -target=kubernetes_cron_job_v1.secret_rotator

# Verificar apos aplicacao
kubectl get cronjob secret-rotator -n staging-security-vault
```

---

## Cenario 2: Pre-flight Check Falhou (exit code 2)

**Sintoma**: Logs mostram `Pre-flight checks FAILED — aborting rotation (no changes made)`

O script saiu com exit 2 = nenhuma credencial foi alterada. Seguro de investigar.

### 2a. Vault inacessivel

```bash
# Verificar Vault pod
kubectl get pods -n staging-security-vault -l app.kubernetes.io/instance=vault

# Verificar conectividade do namespace
kubectl run vault-test --rm -it --restart=Never -n staging-security-vault \
  --image=curlimages/curl:latest -- \
  curl -s http://vault.staging-security-vault.svc.cluster.local:8200/v1/sys/health

# Verificar VAULT_ADDR no CronJob
kubectl get cronjob secret-rotator -n staging-security-vault \
  -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].env}' | \
  python3 -m json.tool
```

### 2b. Vault token invalido ou expirado

```bash
# Verificar se o secret foi sincronizado pelo ESO
kubectl get secret secret-rotator-vault-token -n staging-security-vault

# Verificar o valor (base64 decoded)
kubectl get secret secret-rotator-vault-token -n staging-security-vault \
  -o jsonpath='{.data.VAULT_TOKEN}' | base64 -d | head -c 20
# (deve comecar com "hvs." para Vault tokens)

# Verificar status do ExternalSecret
kubectl get externalsecret secret-rotator-vault-token -n staging-security-vault

# Se ExternalSecret nao sincronizado — forcara sync
kubectl annotate externalsecret secret-rotator-vault-token \
  -n staging-security-vault \
  force-sync=$(date +%s)

# Verificar token no Vault
vault token lookup $(kubectl get secret secret-rotator-vault-token \
  -n staging-security-vault \
  -o jsonpath='{.data.VAULT_TOKEN}' | base64 -d)
```

**Se o token expirou**, criar novo:
```bash
vault token create \
  -policy=secret-rotator \
  -ttl=8760h \
  -renewable=true \
  -display-name=secret-rotator-cronjob \
  -format=json | jq -r .auth.client_token | \
  vault kv put secret/secret-rotator/token token=-

# Forcar re-sync do ESO
kubectl annotate externalsecret secret-rotator-vault-token \
  -n staging-security-vault \
  force-sync=$(date +%s)
```

### 2c. RDS inacessivel (se psql disponivel no container)

```bash
# Verificar conectividade com RDS do namespace
kubectl run pg-test --rm -it --restart=Never \
  -n staging-security-vault \
  --image=postgres:16-alpine -- \
  psql "postgresql://postgres_admin:<password>@k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com:5432/postgres?sslmode=require" \
  -c "SELECT version();"

# Verificar security group do RDS (regra de entrada para CIDR do node group)
aws ec2 describe-security-groups \
  --group-ids <rds-sg-id> \
  --query 'SecurityGroups[0].IpPermissions'
```

### 2d. Keycloak inacessivel

```bash
# Teste de conectividade Keycloak do namespace
kubectl run kc-test --rm -it --restart=Never \
  -n staging-security-vault \
  --image=curlimages/curl:latest -- \
  curl -s "http://keycloak-keycloakx-http.staging-platform-keycloak.svc.cluster.local/realms/master/.well-known/openid-configuration" | \
  python3 -m json.tool | head -5

# Verificar pods Keycloak
kubectl get pods -n staging-platform-keycloak
```

---

## Cenario 3: Rotacao Parcial — Split-brain (exit code 1)

**Sintoma**: Logs mostram rotacao de PostgreSQL OK, mas Vault write failed.
Significa que o password no RDS foi alterado mas o Vault ainda tem o password antigo.

**Risco**: Workloads que reiniciarem pegarao o password antigo do Vault e falharao.

### Identificar o estado

```bash
# Ver logs completos do job com falha
kubectl logs -n staging-security-vault \
  $(kubectl get pods -n staging-security-vault \
    -l app.kubernetes.io/name=secret-rotator \
    --sort-by=.metadata.creationTimestamp -o name | tail -1) 2>&1 | \
  grep -E "(ERROR|WARN|FAILED|OK)"

# Verificar ultima rotacao no Vault
vault kv get secret/secret-rotator/last-rotation
```

### Recuperar o split-brain

Para cada database/credencial afetada, voce tem duas opcoes:

**Opcao A — Atualizar Vault com o novo password (se souber qual foi gerado)**:
```bash
# O script gera passwords com: cat /dev/urandom | tr -dc 'A-Za-z0-9!#%^&*...' | head -c 32
# Nao e possivel saber qual password foi gerado apos o fato.
# Usar a Opcao B.
```

**Opcao B — Reverter RDS para o password do Vault (senha mais simples)**:
```bash
# 1. Ler password atual do Vault (que o workload ainda usa)
vault kv get -field=password secret/keycloak/postgresql

# 2. Conectar ao RDS com credenciais admin e reverter
kubectl run pg-rollback --rm -it --restart=Never \
  -n staging-security-vault \
  --image=postgres:16-alpine -- \
  psql "postgresql://postgres_admin:<admin_pass>@k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com:5432/postgres?sslmode=require" \
  -c "ALTER USER keycloak_user WITH PASSWORD '<password_do_vault>';"

# 3. Verificar que workloads ainda estao OK
kubectl get pods -n staging-platform-keycloak
kubectl get pods -n staging-platform-gitlab
kubectl get pods -n harbor-system
kubectl get pods -n staging-platform-sonarqube
```

**Opcao C — Rotacionar novamente (seguro apos reverter RDS)**:
```bash
# Apos garantir que RDS e Vault estao sincronizados:
kubectl create job --from=cronjob/secret-rotator secret-rotator-retry-$(date +%Y%m%d%H%M) \
  -n staging-security-vault
```

---

## Cenario 4: Rotacao OK, Workloads Falhando

**Sintoma**: CronJob bem-sucedido, mas pods em CrashLoopBackOff apos restart.

A causa mais comum e o workload ter reiniciado antes do ESO re-sincronizar o K8s Secret.

```bash
# Verificar se ESO sincronizou o secret
kubectl get externalsecret -A | grep -v SecretSynced

# Para cada ExternalSecret nao sincronizado, forcara sync:
kubectl annotate externalsecret <nome> -n <namespace> force-sync=$(date +%s)

# Verificar se o K8s Secret foi atualizado (checar annotation)
kubectl get secret <nome-secret> -n <namespace> \
  -o jsonpath='{.metadata.annotations}' | python3 -m json.tool

# Reiniciar workload APOS ESO sincronizar
kubectl rollout restart deployment -n staging-platform-keycloak
kubectl rollout restart deployment -n staging-platform-gitlab
kubectl rollout restart deployment -n harbor-system
kubectl rollout restart deployment -n staging-platform-sonarqube
```

---

## Cenario 5: Job Travado (Running > 40 minutos)

**Sintoma**: `SecretRotationRunningTooLong` alert. Pod em Running ha mais de 40 min.

```bash
# Identificar o pod
kubectl get pods -n staging-security-vault -l app.kubernetes.io/name=secret-rotator

# Ver logs atuais (pode estar esperando conexao)
kubectl logs -f -n staging-security-vault \
  $(kubectl get pods -n staging-security-vault \
    -l app.kubernetes.io/name=secret-rotator -o name | head -1)

# Se o pod esta pendurado, matar o Job (o CronJob vai recriar se backoffLimit nao atingido)
kubectl delete job -n staging-security-vault \
  $(kubectl get jobs -n staging-security-vault \
    -l app.kubernetes.io/name=secret-rotator \
    --sort-by=.status.startTime -o name | tail -1)

# Verificar o que foi alterado antes da interrupcao
vault kv get secret/secret-rotator/last-rotation
```

O CronJob tem `activeDeadlineSeconds: 1800` (30 min) — sera auto-terminado pelo Kubernetes.

---

## Cenario 6: Rotar Apenas um Secret Especifico

Para situacoes onde apenas uma credencial precisa ser rotacionada sem executar o ciclo completo:

```bash
NS="staging-security-vault"

# Criar job temporario
kubectl create job secret-rotator-targeted-$(date +%Y%m%d%H%M) \
  --from=cronjob/secret-rotator \
  -n $NS

JOB_NAME="secret-rotator-targeted-$(date +%Y%m%d%H%M)"

# Definir scope da rotacao
# Opcoes: all | postgresql | keycloak_admin | oidc_clients
kubectl set env job/$JOB_NAME ROTATE_ONLY=postgresql -n $NS

# Monitorar
kubectl logs -f -n $NS -l job-name=$JOB_NAME
```

---

## Cenario 7: OIDC Client Secret Rotacionado, SSO Quebrando

Quando o client secret OIDC e rotacionado no Keycloak, as aplicacoes precisam reiniciar para pegar o novo secret do K8s Secret (sincronizado via ESO).

```bash
# 1. Verificar se ESO sincronizou
kubectl get externalsecret -A | grep oidc

# 2. Forcara re-sync de todos os ExternalSecrets OIDC
for es in grafana-oidc-credentials harbor-oidc-credentials; do
  for ns in monitoring harbor-system; do
    kubectl annotate externalsecret $es -n $ns \
      force-sync=$(date +%s) --overwrite 2>/dev/null || true
  done
done

# 3. Reiniciar aplicacoes SSO
kubectl rollout restart deployment -n monitoring -l app.kubernetes.io/name=grafana
kubectl rollout restart statefulset -n staging-security-vault vault
kubectl rollout restart deployment -n harbor-system -l component=core

# 4. Testar SSO (apos restart completar)
# Acessar cada aplicacao e tentar login via Keycloak
```

---

## Cenario 8: Verificar Historico de Rotacoes

```bash
# Rotacao mais recente
vault kv get secret/secret-rotator/last-rotation

# Historico via K8s (jobs dos ultimos 6 meses)
kubectl get jobs -n staging-security-vault \
  --sort-by=.status.startTime | grep secret-rotator

# Verificar data de criacao de um secret especifico no Vault
vault kv metadata get secret/keycloak/postgresql | grep created_time
vault kv metadata get secret/keycloak/admin | grep created_time
vault kv metadata get secret/grafana/oidc | grep created_time
```

---

## Escalonamento

Se nenhum dos cenarios acima resolver o problema:

1. Executar rotacao manual de emergencia (< 5 min):
   `docs/runbooks/secret-rotation-emergency-manual.md`

2. Verificar ADR-083 para contexto de arquitetura

3. Abrir issue com:
   - Output completo dos logs do Job
   - `vault kv get secret/secret-rotator/last-rotation`
   - `kubectl describe cronjob secret-rotator -n staging-security-vault`
   - Estado dos ExternalSecrets: `kubectl get externalsecret -A`

---

## Referencias

- ADR-083: `docs/adr/adr-083-automated-secret-rotation-strategy.md`
- Rotacao manual de emergencia: `docs/runbooks/secret-rotation-emergency-manual.md`
- Politica de rotacao: `docs/runbooks/secret-rotation-policy.md`
- Vault policy: `platform-provisioning/.../vault_policies/secret-rotator.hcl`
