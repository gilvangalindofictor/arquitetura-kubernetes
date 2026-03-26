# PROMPT DE CONTINUAÇÃO — Sessão 2026-03-23 Handoff

> Cole este prompt inteiro no início de um novo chat Claude Code.
> Ele contém o estado EXATO das 2 demandas pendentes da sessão 2026-03-21/22.

---

Você é o Orquestrador DevOps Sênior operando sob `docs/prompts/executor-terraform.md`.

## CONTEXTO DO AMBIENTE

### Credenciais AWS
- Profile: `k8s-platform-prod` | Account: `891377105802`
- Cluster: `k8s-platform-prod` | Region: `us-east-1`
- SSO tokens **PROVAVELMENTE EXPIRADOS** — renovar antes de qualquer ação:

```bash
aws sso login --profile k8s-platform-prod --no-browser
aws eks update-kubeconfig --name k8s-platform-prod --region us-east-1
```

### Working Dirs
- Kubernetes: `/home/gilvangalindo/projects/Arquitetura/Kubernetes`
- TF staging: `platform-provisioning/aws/kubernetes/terraform/environments/staging`
- TF prod: `platform-provisioning/aws/kubernetes/terraform/environments/prod`
- TF modules: `platform-provisioning/aws/kubernetes/terraform/modules/vault`

---

## DEMANDA 1 — Reescrita do Histórico Git (URGENTE | P0)

### Problema
Token do Vault (`VAULT_ROOT_TOKEN_REDACTED`) foi commitado em:
- Repo: `Arquitetura/Kubernetes` (GitHub: `gilvangalindofictor/arquitetura-kubernetes`)
- Commit: `60ed457` — arquivo `docs/prompts/sessao-continuacao-2026-03-21-handoff.md`
- GitHub Secret Scanning está bloqueando o push do commit `a3e20c9` (WAF IP allowlist)

### Estado Git Atual
```
a3e20c9  feat(waf): IP allowlist — office-only access for staging and prod ALBs
60ed457  feat: sessão 2026-03-20/21 — ECR pull-through, DNS Fase 5-6, Kyverno, OTel fix  ← TOKEN AQUI
763801f  feat(dns): hosted zones criadas — NS reais no documento
...
```

### Plano de Execução

#### Passo 1 — Instalar git-filter-repo (se necessário)
```bash
pip install git-filter-repo 2>/dev/null || pip3 install git-filter-repo
# Ou via apt: sudo apt-get install git-filter-repo
git filter-repo --version  # confirmar instalação
```

#### Passo 2 — Fazer backup local antes da reescrita
```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes
git bundle create /tmp/backup-arquitetura-kubernetes-$(date +%Y%m%d%H%M).bundle --all
echo "Backup criado em /tmp/backup-arquitetura-kubernetes-*.bundle"
```

#### Passo 3 — Remover o arquivo problemático do histórico inteiro
```bash
# OPÇÃO A (preferida): remover apenas o arquivo de handoff do histórico
git filter-repo --path docs/prompts/sessao-continuacao-2026-03-21-handoff.md --invert-paths --force

# OPÇÃO B (fallback): substituir apenas o token pelo texto [REDACTED]
# git filter-repo --replace-text <(echo "VAULT_ROOT_TOKEN_REDACTED==>VAULT_TOKEN_REDACTED") --force
```

#### Passo 4 — Verificar que o token não existe mais em nenhum commit
```bash
git log --all --full-history -- "docs/prompts/sessao-continuacao-2026-03-21-handoff.md"
# Deve retornar vazio (arquivo removido do histórico)

git log --oneline -10
# Verificar que commits a3e20c9 e 60ed457 foram reescritos com novos SHAs
```

#### Passo 5 — Reconfigurar o remote (git-filter-repo remove remotes por segurança)
```bash
git remote add origin https://github.com/gilvangalindofictor/arquitetura-kubernetes.git
git remote -v  # confirmar
```

#### Passo 6 — Force push para GitHub
```bash
# ATENÇÃO: Force push destrutivo — confirmar com o usuário antes de executar
git push origin --force --all
git push origin --force --tags
```

#### Passo 7 — Confirmar que GitHub desbloqueou (Secret Scanning)
```bash
# Verificar se o push foi aceito sem bloqueio
git log --oneline -5
# Testar push normal (sem --force) para confirmar estado limpo
git push origin main
```

#### Passo 8 — Rotacionar o Vault Token (OBRIGATÓRIO após limpeza)
```bash
# O token VAULT_ROOT_TOKEN_REDACTED foi exposto no histórico git
# MESMO APÓS limpeza, o token deve ser revogado pois pode ter sido clonado antes

# Port-forward ao Vault staging
AWS_PROFILE=k8s-platform-prod kubectl port-forward -n staging-security-vault svc/vault 8200:8200 &
sleep 3

export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=VAULT_ROOT_TOKEN_REDACTED

# Gerar novo token root
vault token create -policy=root -ttl=0 -period=0 -orphan=true 2>/dev/null || \
vault operator generate-root -init 2>/dev/null

# IMPORTANTE: Atualizar o token em:
# 1. memory/MEMORY.md (substituir o token exposto)
# 2. Qualquer secret no Kubernetes que referencie o root token
# 3. Documentar o novo token de forma segura (NÃO commitar em repos)
```

### GATE Demanda 1
- [ ] `git log --all -- docs/prompts/sessao-continuacao-2026-03-21-handoff.md` retorna vazio
- [ ] Push para GitHub bem-sucedido sem bloqueio de Secret Scanning
- [ ] Vault root token rotacionado
- [ ] Arquivo `memory/MEMORY.md` atualizado com novo token (ou token removido do arquivo)

---

## DEMANDA 2 — Vault IAM Fase 2: Isolamento KMS e S3 (MÉDIO | P1)

### Contexto (Estado Atual pós-Fase 1)

A Fase 1 foi concluída com sucesso:
- **IAM roles**: agora dedicadas
  - Prod: `VaultIRSA-k8s-platform-prod` (trust: prod-only)
  - Staging: `VaultIRSA-staging-k8s-platform-prod` (trust: staging-only)

**Ainda compartilhados:**
- KMS key: `272b2c51-4f0c-402a-a075-9006da4e187e`
  - Alias atual: `alias/vault-unseal-k8s-platform-prod` (ÚNICO alias, usado por ambos)
- S3 bucket: `k8s-platform-prod-vault-snapshots-891377105802`

### Risco
Se staging e prod rodarem `terraform apply` independentemente, ambos tentarão gerenciar os mesmos recursos KMS alias e S3 bucket → colisão de state / recurso destruído.

**Vault prod E staging foram inicializados com a MESMA KMS key** → não criar nova key sem migração cuidadosa.

### Plano de Execução

#### Fase 2A — Diagnóstico inicial (EXECUTAR PRIMEIRO)

```bash
# 1. Verificar em qual TF state cada recurso está rastreado
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/environments/staging
AWS_PROFILE=k8s-platform-prod terraform state list 2>/dev/null | grep -E "kms|s3|bucket|vault"

cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/environments/prod
AWS_PROFILE=k8s-platform-prod terraform state list 2>/dev/null | grep -E "kms|s3|bucket|vault"

# 2. Verificar alias KMS atual
AWS_PROFILE=k8s-platform-prod aws kms list-aliases --region us-east-1 2>/dev/null | \
  python3 -c "import json,sys; [print(a['AliasName'], '->', a.get('TargetKeyId','n/a')) for a in json.load(sys.stdin)['Aliases'] if 'vault' in a['AliasName'].lower()]"

# 3. Verificar qual alias o Vault staging usa para unseal
AWS_PROFILE=k8s-platform-prod kubectl get cm -n staging-security-vault -o yaml 2>/dev/null | grep -E "kms|arn|alias" | head -5
AWS_PROFILE=k8s-platform-prod kubectl exec -n staging-security-vault vault-0 -- vault status 2>/dev/null | grep -E "Seal|KMS|Key"
# OU via Helm values:
AWS_PROFILE=k8s-platform-prod helm get values vault -n staging-security-vault 2>/dev/null | grep -E "kms|alias|arn" | head -10

# 4. Verificar qual alias o Vault prod usa para unseal
AWS_PROFILE=k8s-platform-prod kubectl exec -n prod-security-vault vault-prod-0 -- vault status 2>/dev/null | grep -E "Seal|KMS|Key"
AWS_PROFILE=k8s-platform-prod helm get values vault-prod -n prod-security-vault 2>/dev/null | grep -E "kms|alias|arn" | head -10

# 5. Verificar S3 bucket (snapshots existem?)
AWS_PROFILE=k8s-platform-prod aws s3 ls s3://k8s-platform-prod-vault-snapshots-891377105802/ 2>/dev/null | head -10
```

#### Fase 2B — KMS Isolation (sem criar nova key)

**Estratégia**: Adicionar alias dedicado por ambiente apontando para a MESMA key (`272b2c51-4f0c-402a-a075-9006da4e187e`). Não destruir a key nem o alias antigo até tudo estar migrado.

```bash
# 1. Criar alias dedicado para staging (aponta para MESMA key)
AWS_PROFILE=k8s-platform-prod aws kms create-alias \
  --alias-name alias/vault-unseal-staging-k8s-platform-prod \
  --target-key-id 272b2c51-4f0c-402a-a075-9006da4e187e \
  --region us-east-1

# 2. Criar alias dedicado para prod (aponta para MESMA key)
AWS_PROFILE=k8s-platform-prod aws kms create-alias \
  --alias-name alias/vault-unseal-prod-k8s-platform-prod \
  --target-key-id 272b2c51-4f0c-402a-a075-9006da4e187e \
  --region us-east-1

# 3. Verificar os 3 aliases agora existem
AWS_PROFILE=k8s-platform-prod aws kms list-aliases --region us-east-1 2>/dev/null | grep vault
```

#### Fase 2C — Atualizar o módulo TF para usar var.environment nos nomes

**Arquivo**: `platform-provisioning/aws/kubernetes/terraform/modules/vault/main.tf`

Localizar e editar:
```hcl
# DE:
resource "aws_kms_alias" "vault_unseal" {
  name          = "alias/vault-unseal-${var.cluster_name}"
  target_key_id = aws_kms_key.vault_unseal.key_id
}

# PARA:
resource "aws_kms_alias" "vault_unseal" {
  name          = "alias/vault-unseal-${var.environment}-${var.cluster_name}"
  target_key_id = aws_kms_key.vault_unseal.key_id
}
```

E para S3:
```hcl
# DE:
resource "aws_s3_bucket" "vault_snapshots" {
  bucket = "${var.cluster_name}-vault-snapshots-${var.aws_account_id}"

# PARA:
resource "aws_s3_bucket" "vault_snapshots" {
  bucket = "${var.cluster_name}-${var.environment}-vault-snapshots-${var.aws_account_id}"
```

**VERIFICAR** que `var.environment` existe no `variables.tf` do módulo (provavelmente já existe).

#### Fase 2D — State Surgery (remover recursos compartilhados do state de staging)

**Backup OBRIGATÓRIO antes:**
```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/environments/staging
AWS_PROFILE=k8s-platform-prod terraform state pull > /tmp/backup-state-staging-fase2-$(date +%Y%m%d%H%M).json
echo "Backup: $(wc -c < /tmp/backup-state-staging-fase2-*.json) bytes"
```

```bash
# Verificar recursos KMS e S3 no state de staging
AWS_PROFILE=k8s-platform-prod terraform state list | grep -E "kms|s3_bucket|vault_snapshots"

# Se aws_kms_key.vault_unseal E aws_s3_bucket.vault_snapshots estão no state de staging:
# Remover do state (recursos continuam existindo na AWS, só saem do controle do staging TF)
AWS_PROFILE=k8s-platform-prod terraform state rm module.vault_staging.aws_kms_key.vault_unseal 2>/dev/null
AWS_PROFILE=k8s-platform-prod terraform state rm module.vault_staging.aws_kms_alias.vault_unseal 2>/dev/null
AWS_PROFILE=k8s-platform-prod terraform state rm module.vault_staging.aws_s3_bucket.vault_snapshots 2>/dev/null
# (remover recursos associados ao S3: versioning, encryption, public_access_block, lifecycle)
```

#### Fase 2E — Importar recursos dedicados no state de staging

```bash
# Importar a KMS KEY existente no state de staging (staging agora "owns" a key compartilhada)
# OU deixar a key apenas no state de prod e staging cria nova key
# DECISÃO: Staging importa a key existente (mais seguro, evita criar nova key)

AWS_PROFILE=k8s-platform-prod terraform import \
  module.vault_staging.aws_kms_key.vault_unseal \
  272b2c51-4f0c-402a-a075-9006da4e187e

# Importar o NOVO alias dedicado de staging
AWS_PROFILE=k8s-platform-prod terraform import \
  module.vault_staging.aws_kms_alias.vault_unseal \
  alias/vault-unseal-staging-k8s-platform-prod

# Importar (ou criar) bucket S3 dedicado para staging
# OPÇÃO A: Criar novo bucket para staging
AWS_PROFILE=k8s-platform-prod aws s3 mb \
  s3://k8s-platform-prod-staging-vault-snapshots-891377105802 \
  --region us-east-1

# OPÇÃO B: Manter bucket existente para staging (prod cria bucket novo)
# → Depende de qual state tem o bucket atualmente
```

#### Fase 2F — TF Plan e Apply (staging primeiro, depois prod)

```bash
# Staging plan
cd .../environments/staging
AWS_PROFILE=k8s-platform-prod terraform plan -target=module.vault_staging 2>&1 | tail -30
# GATE: Sem destroy de recursos críticos (KMS key, S3 com dados)

# Apply staging (apenas se plan for seguro)
AWS_PROFILE=k8s-platform-prod terraform apply -target=module.vault_staging -auto-approve 2>&1 | tail -20

# Prod plan
cd .../environments/prod
AWS_PROFILE=k8s-platform-prod terraform plan -target=module.vault_prod 2>&1 | tail -30

# Apply prod
AWS_PROFILE=k8s-platform-prod terraform apply -target=module.vault_prod -auto-approve 2>&1 | tail -20
```

#### Fase 2G — Verificar Vault ainda unsealed após mudanças

```bash
# Vault staging
AWS_PROFILE=k8s-platform-prod kubectl get pods -n staging-security-vault
AWS_PROFILE=k8s-platform-prod kubectl exec -n staging-security-vault vault-0 -- vault status 2>/dev/null | grep -E "Sealed|HA Mode"

# Vault prod
AWS_PROFILE=k8s-platform-prod kubectl get pods -n prod-security-vault
AWS_PROFILE=k8s-platform-prod kubectl exec -n prod-security-vault vault-prod-0 -- vault status 2>/dev/null | grep -E "Sealed|HA Mode"
```

#### Fase 2H — Cleanup (apenas após tudo validado)

```bash
# Remover alias compartilhado antigo (APENAS se ambos os Vaults usam aliases novos)
# VERIFICAR primeiro: nenhum Vault referencia o alias antigo
AWS_PROFILE=k8s-platform-prod aws kms delete-alias \
  --alias-name alias/vault-unseal-k8s-platform-prod \
  --region us-east-1

# Remover S3 bucket compartilhado (APENAS se vazio ou migrado)
# AWS_PROFILE=k8s-platform-prod aws s3 rb s3://k8s-platform-prod-vault-snapshots-891377105802 --force
```

### GATE Demanda 2
- [ ] Cada Vault usa alias KMS dedicado (`staging-` ou `prod-` prefix)
- [ ] Cada Vault usa bucket S3 dedicado
- [ ] `terraform plan` em ambos os environments retorna **No changes**
- [ ] `vault status` em staging e prod: `Sealed: false`
- [ ] Alias antigo `alias/vault-unseal-k8s-platform-prod` removido (cleanup)

---

## ALERTAS CRÍTICOS

```
⚠️  NUNCA executar DEMANDA 2 se Vault prod OU staging estiver Sealed
⚠️  NUNCA deletar a KMS key 272b2c51-4f0c-402a-a075-9006da4e187e sem garantir ambos os Vaults migraram
⚠️  SEMPRE fazer backup do TF state antes de qualquer state surgery
⚠️  Para git force push: garantir que nenhum colega está trabalhando no repo simultaneamente
⚠️  O Vault root token VAULT_ROOT_TOKEN_REDACTED DEVE ser rotacionado após limpeza do git
```

---

## PRIORIDADE DE EXECUÇÃO

**Executar DEMANDA 1 primeiro** (git cleanup + token rotation) — não bloqueia o push de novos commits.
**DEMANDA 2 depois** — mais longa, pode ser executada em sessão separada se necessário.

---

## ARQUIVOS RELEVANTES

| Arquivo | Relevância |
|---------|-----------|
| `platform-provisioning/aws/kubernetes/terraform/modules/vault/main.tf` | KMS alias e S3 bucket names |
| `platform-provisioning/aws/kubernetes/terraform/modules/vault/variables.tf` | var.environment |
| `platform-provisioning/aws/kubernetes/terraform/environments/staging/main.tf` | module.vault_staging (iam_name_override) |
| `platform-provisioning/aws/kubernetes/terraform/environments/prod/main.tf` | module.vault_prod (iam_name_override) |
| `docs/prompts/executor-terraform.md` | Framework de orquestração |
