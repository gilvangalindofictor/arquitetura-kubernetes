# PROMPT DE EXECUCAO — Agente ETL-Onboarding Specialist

> Dispare com: Agent(prompt=<conteudo deste arquivo>, run_in_background=true)

---

## PAPEL

Voce e o **Agente ETL-Onboarding** — especialista em Kubernetes, Vault, ArgoCD e CI/CD pipelines.
Opera sob `docs/prompts/executor-terraform.md`.

## MISSAO

Resolver TODOS os GAPs P0/P1 abertos nos ETLs Hatch e VemSoft em staging, elevando ambos a 95%+ de completude.

## AMBIENTE

- AWS Account: 891377105802 | Profile: k8s-platform-prod
- Credenciais AWS: `~/.aws/cli/cache/9f96c2165544e66612973182e4b515dd261e84f7.json`
- Vault: `localhost:8200` | Token: `VAULT_ROOT_TOKEN_REDACTED`
- RDS: `k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com:5432`
- kubectl: usar env vars exportadas do cache (nao AWS_PROFILE)

```bash
CREDS=$(cat ~/.aws/cli/cache/9f96c2165544e66612973182e4b515dd261e84f7.json)
export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin)['Credentials']['AccessKeyId'])")
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin)['Credentials']['SecretAccessKey'])")
export AWS_SESSION_TOKEN=$(echo "$CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin)['Credentials']['SessionToken'])")
export AWS_DEFAULT_REGION=us-east-1
```

## ESTADO ATUAL

### ETL/Hatch (77% completo)

| Aspecto | Status | Detalhes |
|---------|--------|----------|
| Namespace | `staging-data-hatch-etl` | Ativo |
| CI/CD Pipeline | 81% | 6 stages, 16 jobs, Kaniko v1.23.2, Trivy 0.50.0 enforced |
| K8s Manifests | 65% | 3/10 deployments ativos (etl-core, api-gateway, web) |
| ExternalSecrets | 6 configurados | TODOS com valores PLACEHOLDER no Vault |
| Observability | 100% | ServiceMonitor + PrometheusRule + Grafana + OTEL |
| Registry | `harbor.staging.internal/hatch-etl/` | Kaniko push OK |

### ETL/VemSoft (83% completo)

| Aspecto | Status | Detalhes |
|---------|--------|----------|
| Namespace | `staging-data-vemsoft-etl` | Ativo |
| Pod | Running 1/1, Ready=True, 0 restarts | Imagem: `harbor.staging.internal/etl/vemsoft-etl:develop` |
| CI/CD Pipeline | 80% | 5 stages, Kaniko v1.23.2, Trivy 0.50.0 (observation mode) |
| ExternalSecrets | 2 configurados | database + api — valores PLACEHOLDER |
| Observability | 100% | ServiceMonitor + PrometheusRule + Grafana + OTEL |
| Registry | `harbor.staging.internal/etl/vemsoft-etl` | Kaniko push OK |
| Vault paths | `secret/staging/data/vemsoft-etl/{database,api}` | Synced |

---

## GAPs A RESOLVER (ORDENADOS POR PRIORIDADE)

### FASE 1 — Diagnostico de Conectividade (ambos ETLs)

**GAP-RDS-ACCESS (P0)** — RDS inacessivel de dentro dos pods

1. Verificar Security Group do RDS:
```bash
# Encontrar SG do RDS
aws rds describe-db-instances --db-instance-identifier k8s-platform-prod-postgresql \
  --query 'DBInstances[0].VpcSecurityGroups[*].VpcSecurityGroupId' --output text

# Verificar regras inbound
aws ec2 describe-security-groups --group-ids <SG_ID> \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`5432`]'
```

2. Verificar CIDR dos nodes EKS:
```bash
kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}' | tr ' ' '\n'
```

3. Se SG nao tem regra para CIDR EKS, adicionar:
```bash
aws ec2 authorize-security-group-ingress --group-id <SG_ID> \
  --protocol tcp --port 5432 --cidr 10.0.128.0/17
```

4. Testar conectividade de dentro do cluster:
```bash
kubectl run pg-test --rm -it --image=postgres:15-alpine --restart=Never -- \
  psql "host=k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com port=5432 user=postgres dbname=postgres sslmode=require" -c "SELECT 1"
```

### FASE 2 — Vault Secrets Hatch (GAP-VAULT-HATCH P0)

Verificar script existente e executar:

1. Localizar: `find /home/gilvangalindo/projects -name "vault-setup-hatch-etl.sh" -o -name "vault-setup*.sh" 2>/dev/null`
2. Se script existe, ler e validar os paths
3. Se nao existe, popular manualmente:

```bash
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=VAULT_ROOT_TOKEN_REDACTED

# Hatch database credentials
vault kv put secret/staging/hatch-etl/database \
  DATABASE_HOST="k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com" \
  DATABASE_PORT="5432" \
  DATABASE_NAME="hatch_etl" \
  DATABASE_USER="hatch_etl_app" \
  DATABASE_PASSWORD="<SOLICITAR_AO_USUARIO>"

# Hatch Redis
vault kv put secret/staging/hatch-etl/redis \
  REDIS_PASSWORD="<SOLICITAR_AO_USUARIO>"

# Hatch API credentials (Hatch system)
vault kv put secret/staging/hatch-etl/api-credentials \
  HATCH_API_USERNAME="<SOLICITAR_AO_USUARIO>" \
  HATCH_API_PASSWORD="<SOLICITAR_AO_USUARIO>" \
  HATCH_API_BASE_URL="<SOLICITAR_AO_USUARIO>"
```

**IMPORTANTE**: Se credenciais reais nao estiverem disponiveis, usar valores de teste documentados e reportar como pendencia.

### FASE 3 — Security Fixes Hatch (P1)

**GAP-SEC-02**: imagePullSecrets faltando em hatch-etl Deployment
- Arquivo: `ETL/Hatch/k8s/overlays/staging/patches/deployment.yaml`
- Adicionar `imagePullSecrets: [{name: harbor-registry-secret}]` no patch do hatch-etl

**GAP-SEC-01**: NetworkPolicies ausentes
- Criar `ETL/Hatch/k8s/base/network-policy.yaml`:
  - Default deny ingress/egress
  - Allow egress: DNS (53), RDS (5432), Redis (6379), OTEL (4317), Harbor (443)
  - Allow ingress: Prometheus scrape (9090), API gateway (8000)
- Adicionar ao `ETL/Hatch/k8s/base/kustomization.yaml`

### FASE 4 — VemSoft Fixes (P1/P2)

**GAP-DEPLOY-SSH**: deploy:staging usa sed em vez de kustomize
- Arquivo: `ETL/VemSoft/.gitlab-ci.yml`
- Refatorar deploy job para usar `kustomize edit set image` (mesmo padrao do Hatch)

**GAP-ARGOCD-AUTOSYNC**: Habilitar auto-sync
```bash
kubectl patch application staging-data-vemsoft-etl -n staging-platform-argocd \
  --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
```

### FASE 5 — Validacao Final

1. Verificar ExternalSecrets synced:
```bash
kubectl get externalsecrets -n staging-data-hatch-etl
kubectl get externalsecrets -n staging-data-vemsoft-etl
```

2. Verificar pods saudaveis:
```bash
kubectl get pods -n staging-data-hatch-etl
kubectl get pods -n staging-data-vemsoft-etl
```

3. Verificar pull errors:
```bash
kubectl get events -n staging-data-hatch-etl --field-selector reason=Failed 2>/dev/null | grep -i pull
kubectl get events -n staging-data-vemsoft-etl --field-selector reason=Failed 2>/dev/null | grep -i pull
```

4. Testar conectividade RDS de dentro dos pods:
```bash
kubectl exec -n staging-data-vemsoft-etl deploy/vemsoft-etl -- python3 -c "
import socket; s=socket.socket(); s.settimeout(5)
try: s.connect(('k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com',5432)); print('RDS: CONNECTED')
except: print('RDS: FAILED')
finally: s.close()
"
```

---

## ARQUIVOS CRITICOS

| Arquivo | ETL | Acao |
|---------|-----|------|
| `ETL/Hatch/k8s/overlays/staging/patches/deployment.yaml` | Hatch | Adicionar imagePullSecrets |
| `ETL/Hatch/k8s/base/network-policy.yaml` | Hatch | CRIAR — default deny + allow rules |
| `ETL/Hatch/k8s/base/kustomization.yaml` | Hatch | Adicionar network-policy.yaml |
| `ETL/VemSoft/.gitlab-ci.yml` | VemSoft | Refatorar deploy job (sed → kustomize) |
| Vault paths hatch-etl/* | Hatch | Popular com credenciais reais |

## RESTRICOES

- NAO fazer force-push, NAO deletar branches, NAO alterar terraform state
- Se credenciais reais nao disponiveis → usar placeholders documentados + reportar
- Se RDS SG precisa de alteracao → CONFIRMAR com usuario antes de aplicar
- Commits em portugues, codigo em ingles
- Documentar TUDO no retorno

## RETORNAR

Relatorio estruturado:
1. GAPs resolvidos (com evidencia: comando + output)
2. GAPs pendentes (com justificativa: por que nao resolvido)
3. Completude atualizada (Hatch X% → Y%, VemSoft X% → Y%)
4. Proximas acoes recomendadas
