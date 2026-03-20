# PROMPT DE CONTINUACAO — Sessao 2026-03-22 Handoff

> Cole este prompt inteiro no inicio de um novo chat Claude Code.
> Ele contem o estado EXATO de todas as demandas, entregas e pendencias da sessao 2026-03-20 (tarde).

---

Voce e o Orquestrador DevOps Senior operando sob `docs/prompts/executor-terraform.md`.

## CONTEXTO DA SESSAO ANTERIOR (2026-03-20, ~18:00 UTC)

Sessao com framework de orquestracao completo: **8 tasks concluidas**, **3 GAPs pendentes**, **1 divida tecnica planejada (Mesa Tecnica)**.

---

## ESTADO DO AMBIENTE

### Credenciais AWS
- Profile: `k8s-platform-staging` | Account: `891377105802`
- Cluster: `k8s-platform-prod` | Region: `us-east-1`
- SSO tokens **PROVAVELMENTE EXPIRADOS** — renovar antes de qualquer acao

```bash
# PRIMEIRA ACAO: Autenticar
aws sso login --profile k8s-platform-staging --no-browser
eval $(aws configure export-credentials --profile k8s-platform-staging --format env)
unset AWS_PROFILE && export AWS_DEFAULT_REGION=us-east-1
aws eks update-kubeconfig --name k8s-platform-prod --region us-east-1
```

### Terraform Working Dirs
- Staging: `platform-provisioning/aws/kubernetes/terraform/environments/staging`
- Prod: `platform-provisioning/aws/kubernetes/terraform/environments/prod`

### Estado do Cluster (pos-sessao)
- **15/15 nodes Ready**
- **~325/332 pods Running (~97.9%)**
- **~7 pods com problema** (eram 18 no inicio da sessao)

---

## ENTREGAS CONCLUIDAS (NAO refazer)

### 1. Loki Apply — ZERO DRIFT
- Helm release estava em `pending-upgrade` (rev 26) → rollback para rev 25
- Apply: write memory 512Mi→2Gi, timeout 300→900
- `modules/loki/main.tf` — ZERO DRIFT confirmado

### 2. Vault Staging Drift — ZERO DRIFT
- Apply: 4 changes in-place (trust policy + tags)
- `iam_name_override = "VaultIRSA-${local.cluster_name}"` aplicado
- Trust policy corrigida: `staging-security-vault:vault`
- Vault staging KMS auto-unseal restaurado (down 1h09m → healthy)

### 3. Vault Prod — Fix Emergencial Aplicado
- Trust policy `VaultIRSA-k8s-platform-prod` atualizada com 2 statements:
  - `system:serviceaccount:staging-security-vault:vault`
  - `system:serviceaccount:prod-security-vault:vault`
- Vault prod 3/3 HA Running, unsealed, KMS operacional
- **NOTA**: Este e um fix TEMPORARIO — role dedicada pendente (ver GAP-VAULT abaixo)

### 4. Promtail — ZERO DRIFT
- Image prefix corrigido: `ecr-public/` → `docker-hub/grafana/promtail:3.0.0`
- **15/15 pods Running**

### 5. Velero — ZERO DRIFT
- Image prefix corrigido: `ecr-public/` → `docker-hub/velero/velero:v1.15.0`
- `wait = false` + timeout 600s adicionados ao modulo (node-agent DaemonSet tem 1 Pending por CPU)
- **14/15 pods Running** (1 Pending = pre-existing node capacity)

### 6. External Secrets — ZERO DRIFT
- ghcr pull-through cache requer GitHub PAT → revertido para `ghcr.io` direto
- `enable_ghcr = false` em `environments/staging/main.tf`
- **3/3 pods Running**

### 7. Mesa Tecnica Vault IAM — Consenso Obtido
- 3 especialistas (AWS + TF + Security) analisaram o problema de isolamento
- Consenso documentado com 3 fases de execucao (ver abaixo)

---

## GAPS PENDENTES — ATACAR NESTA SESSAO

### GAP-OBS-002: Harbor-System Instavel (staging) | GRAVIDADE: ALTO

**Descricao:** harbor-system (namespace `harbor-system`) tem 3 pods com problema:
- `harbor-exporter` — CrashLoopBackOff (17 restarts) — linkerd-proxy PostStartHook failed
- `harbor-jobservice` (new RS) — ContainerCreating stuck 100+ min
- `harbor-registry` (new RS) — ContainerCreating stuck 100+ min

Pods ANTIGOS do jobservice e registry estao funcionando (rollout incompleto de nova versao).

**Diagnostico provavel:**
- Exporter: Linkerd sidecar injection com PostStartHook falhando. Verificar se o namespace tem annotation de injection e se a PolicyException existe.
- ContainerCreating stuck: Pode ser secret mount issue ou linkerd injection pendente. Pods sem events recentes.

**Acoes recomendadas:**
```bash
# Diagnosticar exporter
kubectl describe pod -n harbor-system -l app=harbor -l component=exporter 2>&1
kubectl logs -n harbor-system -l component=exporter -c linkerd-proxy --tail=20 2>&1

# Diagnosticar stuck pods
kubectl describe pod -n harbor-system -l component=jobservice 2>&1 | grep -A 20 "Events:"
kubectl describe pod -n harbor-system -l component=registry 2>&1 | grep -A 20 "Events:"

# Quick fix: deletar pods stuck para retry
kubectl delete pod -n harbor-system -l component=jobservice --field-selector=status.phase!=Running
kubectl delete pod -n harbor-system -l component=registry --field-selector=status.phase!=Running
```

**Gate:** harbor-system com todos os pods Running, exporter sem CrashLoop.

---

### GAP-OBS-003: OTel Collector Bloqueado por Kyverno | GRAVIDADE: MEDIO

**Descricao:** ReplicaSet `opentelemetry-collector-6f55bfb8cf` nao consegue criar pods — Kyverno **Enforce** bloqueia por falta de labels corporativas (`domain`, `owner`, `environment`).

RS antigo (2 pods) funciona normalmente. O update esta bloqueado.

**Diagnostico:**
- A ClusterPolicy `inject-corporate-labels` ou similar nao cobre o namespace `staging-observability-monitoring`
- OU o Helm chart do OTel Collector nao inclui os labels requeridos nos pod templates

**Acoes recomendadas:**
```bash
# Ver qual policy bloqueia
kubectl get events -n staging-observability-monitoring --field-selector reason=PolicyViolation 2>&1 | tail -10

# Opcao A: Criar/atualizar MutatingPolicy para injetar labels
# Ver policies existentes como referencia:
kubectl get clusterpolicy -o name 2>&1
kubectl get clusterpolicy inject-corporate-labels-prod-namespaces -o yaml 2>&1

# Opcao B: Adicionar labels no Helm values do OTel Collector
# Arquivo: modules/opentelemetry-collector/values.yaml.tpl
# Adicionar labels no podTemplate
```

**Gate:** OTel Collector novo RS com pods Running. Kyverno nao bloqueando.

---

### GAP-OBS-004: Hatch ETL ExternalSecrets — Vault Paths Ausentes | GRAVIDADE: MEDIO

**Descricao:** 6 ExternalSecrets em `staging-data-hatch-etl` com status `UpdateFailed`. Paths no Vault nao existem ou keys faltando:
- `secret/staging/hatch-etl/redis` → key `url` ausente
- `secret/staging/hatch-etl/api` → Secret nao existe no Vault
- `secret/staging/hatch-etl/database` → keys `url`, `user` ausentes

Pods hatch-etl estao Running (usando secrets em cache), mas sincronizacao esta quebrada.

**Acoes recomendadas:**
```bash
# Verificar ExternalSecrets
kubectl get externalsecret -n staging-data-hatch-etl 2>&1
kubectl describe externalsecret -n staging-data-hatch-etl 2>&1 | grep -A5 "Status:"

# Verificar Vault (requer port-forward)
kubectl port-forward -n staging-security-vault svc/vault 8200:8200 &
export VAULT_ADDR=http://localhost:8200
vault kv list secret/staging/hatch-etl/
vault kv get secret/staging/hatch-etl/redis
vault kv get secret/staging/hatch-etl/api
vault kv get secret/staging/hatch-etl/database

# Se paths nao existirem, criar:
vault kv put secret/staging/hatch-etl/redis url="redis://redis-master.staging-data-hatch-etl:6379"
vault kv put secret/staging/hatch-etl/api Secret="<valor-do-api-secret>"
vault kv put secret/staging/hatch-etl/database url="postgresql://..." user="hatch_etl"
```

**ATENCAO:** Os valores dos secrets devem ser obtidos com o usuario ou da documentacao. NAO inventar valores.

**Gate:** ExternalSecrets com status `SecretSynced`. Pods hatch-etl com secrets atualizados.

---

## DIVIDA TECNICA PLANEJADA — VAULT IAM ISOLATION

### Consenso da Mesa Tecnica (AWS + TF + Security)

**Problema:** Os modules `vault_staging` e `vault_prod` compartilham a MESMA IAM role `VaultIRSA-k8s-platform-prod`. Ambos em TF states diferentes. O ultimo apply ganha e sobrescreve a trust policy do outro.

Alem da role, ha colisao potencial em:
- KMS alias: `alias/vault-unseal-k8s-platform-prod`
- S3 bucket: `k8s-platform-prod-vault-snapshots-891377105802`
- IAM policy: mesmo nome

### Fase 1 — URGENTE (30-45min): Isolamento Prod

1. **Ajustar `modules/vault/main.tf`** — incluir `var.environment` nos nomes de:
   - KMS alias: `alias/vault-unseal-${var.environment}-${var.cluster_name}`
   - S3 bucket: `${var.cluster_name}-${var.environment}-vault-snapshots-${var.aws_account_id}`

2. **Remover `iam_name_override`** de `environments/prod/main.tf` (L438)
   - Default gera: `VaultIRSA-prod-k8s-platform-prod` (nome correto)

3. **`terraform plan -target=module.vault_prod`** — deve criar novos recursos (role, KMS, S3, policy) com prefix `prod-`

4. **Pre-apply**: verificar se Vault prod foi inicializado com a KMS key compartilhada:
   ```bash
   kubectl exec -n prod-security-vault vault-prod-0 -- vault status
   # Se "Key ARN" aponta para alias/vault-unseal-k8s-platform-prod → KMS compartilhada
   ```

5. **Se KMS compartilhada**: NAO criar nova key — importar a existente no state de prod
   **Se KMS dedicada ja existe**: criar nova key normalmente

6. **Apply + rolling restart** dos pods Vault prod para pegar nova IRSA role

7. **Remover statement prod** da trust policy de `VaultIRSA-k8s-platform-prod` (limpar fix emergencial)

### Fase 2 — Sprint: Normalizacao Staging (20-30min)

8. Pre-criar role `VaultIRSA-staging-k8s-platform-prod` via AWS CLI
9. `terraform import` no state de staging
10. Remover `iam_name_override` de `environments/staging/main.tf` (L650)
11. `terraform plan` → confirmar zero drift
12. Limpar role orfao `VaultIRSA-k8s-platform-prod`

### Fase 3 — Sprint: Helm Secret Fix (5min)

13. Fix label do Helm secret corrompido:
    ```bash
    kubectl label secret sh.helm.release.v1.vault-prod.v1 -n prod-security-vault \
      app.kubernetes.io/managed-by=Helm owner=helm --overwrite
    ```

### Alertas Criticos
- **Vault prod JA inicializado com KMS key compartilhada** → nao criar nova key sem migration
- **S3 bucket staging pode ter snapshots** → verificar antes de renomear
- **Fazer backup do TF state** antes de qualquer state operation: `terraform state pull > /tmp/backup-state.json`

---

## LICAO NOVA A DOCUMENTAR

**Licao 20 — GHCR requer GitHub PAT para ECR Pull-Through Cache**

Problema: Tentativa de criar ECR pull-through cache rule para `ghcr.io` falhou com `UnsupportedUpstreamRegistryException`.

Causa raiz: AWS ECR exige Personal Access Token (GitHub PAT) em Secrets Manager para pull-through de GHCR, mesmo para imagens publicas.

Solucao: Usar `ghcr.io` diretamente (sem pull-through). GHCR nao tem rate limit para imagens publicas.

Regra geral: Pull-through sem credenciais funciona para: ECR Public, Quay, registry.k8s.io. Pull-through COM credenciais: Docker Hub (PAT), GHCR (PAT). Para registries que requerem PAT, avaliar se pull-through justifica o overhead de gerenciar tokens.

---

## ARQUIVOS TF MODIFICADOS NESTA SESSAO (nao commitados)

| Arquivo | Mudanca |
|---------|---------|
| `modules/loki/main.tf` | write memory 2Gi (aplicado) |
| `modules/vault/main.tf` | local iam_name + retry_join fix (staging aplicado, prod pendente) |
| `modules/vault/variables.tf` | var iam_name_override |
| `modules/vault/values.yaml.tpl` | retry_join usa helm_release_name |
| `modules/velero-helm/main.tf` | docker-hub prefix + wait=false + timeout 600 |
| `modules/velero-helm/variables.tf` | var ecr_registry |
| `modules/promtail/values.yaml.tpl` | docker-hub prefix |
| `modules/external-secrets/values.yaml.tpl` | ghcr.io direto (sem pull-through) |
| `modules/kube-prometheus-stack/main.tf` | Prometheus 3Gi/6Gi |
| `environments/staging/main.tf` | vault iam_name_override + enable_ghcr=false |
| `environments/staging/velero-helm.tf` | ecr_registry passado |
| `environments/prod/main.tf` | vault_prod iam_name_override (a remover na Fase 1) |

---

## RECOMENDACAO DE PRIORIDADE

**Opcao A — Resolver GAPs primeiro (1-2h):**
1. GAP-OBS-002 (Harbor) — 20min
2. GAP-OBS-003 (OTel/Kyverno) — 15min
3. GAP-OBS-004 (Hatch ETL) — 15min (requer valores do usuario)
4. Documentacao (logbook + licao 20) — 15min
5. Vault IAM Fase 1 — 45min

**Opcao B — Vault IAM primeiro (mais critico):**
1. Vault IAM Fase 1 — 45min (elimina anti-pattern de ownership)
2. GAPs OBS — 50min
3. Documentacao — 15min

**Opcao C — Documentar e commitar (conservadora):**
1. Commit das mudancas TF ja aplicadas
2. Logbook + licao 20
3. GAPs e Vault IAM na sessao seguinte

**Recomendacao: Opcao A** — os GAPs afetam saude operacional do cluster. Vault IAM e risco latente mas ja mitigado pelo fix emergencial.
