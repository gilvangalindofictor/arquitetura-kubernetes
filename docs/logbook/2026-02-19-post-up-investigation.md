# 2026-02-19 — Post-Up Investigation + STOP-AND-FIX (3 issues)

**Executor:** Orquestrador DevOps (executor-terraform.md)
**Protocolo:** Investigação pós-up + consulta histórico + fix permanente
**Duração:** ~60min

---

## Contexto

Investigação do ambiente após startup semanal (2026-02-19 manhã).
Histórico consultado: `2026-02-18-cluster-recovery-stop-and-fix.md`, `2026-02-18-cluster-recovery-afternoon.md`, ADR-022, ADR-056.

---

## Estado no Início

```
[09:11] Pre-check | Sessão AWS expirada → SSO login → account: 891377105802 | ✅
[09:11] Nodes | 8/8 Ready | system×2 (t3.med), workloads×4 (t3.lg), critical×2 (t3.xl) | ✅
[09:11] RDS   | k8s-platform-prod-postgresql | available | db.t3.medium | ✅
[09:11] LBs   | 4 ALBs active | ✅
[09:11] Vault | UNSEALED (KMS auto-unseal) | ✅
[09:11] Pods  | 132 Running | 1 Pending | 1 CrashLoopBackOff | ⚠️
```

---

## STOP-AND-FIX #1: Keycloak Pending (nodeName stale)

**Problema:** `keycloak-keycloakx-0` em Pending há 9h — x935 creates / x538 deletes loop.

**Root Cause:** `.spec.template.spec.nodeName: ip-10-0-153-218.ec2.internal` hardcoded no StatefulSet. Após o shutdown/restart, o node `ip-10-0-153-218` foi terminado e um novo critical node (`ip-10-0-153-44`) foi provisionado. O STS template tinha o `nodeName` fixo no node antigo (stale desde o deploy de 2026-02-18).

**Fix:**
```bash
kubectl patch sts keycloak-keycloakx -n keycloak --type='json' \
  -p='[{"op":"remove","path":"/spec/template/spec/nodeName"}]'
kubectl delete pod keycloak-keycloakx-0 -n keycloak
```

**Resultado:** Pod schedulado em `ip-10-0-137-175.ec2.internal` (critical, us-east-1a) | ✅

---

## STOP-AND-FIX #2: Keycloak CrashLoopBackOff (DB password drift)

**Problema:** `keycloak-keycloakx-0` → `FATAL: password authentication failed for user "keycloak_user"` após fix do nodeName.

**Root Cause:** Drift de senha entre Vault e RDS:
- Vault `secret/keycloak/postgresql` → senha antiga (da migração 2026-02-11)
- RDS `keycloak_user` → senha nova (gerenciada pelo Terraform)
- AWS Secrets Manager `staging/postgresql/keycloak-password` → senha correta (=RDS)
- ESO lê do Vault → K8s secret com senha errada

**Padrão identificado:** Mesmo padrão do STOP-AND-FIX #7 de 2026-02-18 (SonarQube).

**Fix imediato:**
```bash
# 1. Atualizar Vault com senha correta (do Secrets Manager)
SM_PASS=$(aws secretsmanager get-secret-value \
  --secret-id "staging/postgresql/keycloak-password" \
  --query 'SecretString' --output text)
kubectl exec -n vault-system vault-0 -- \
  env VAULT_TOKEN="$VAULT_TOKEN" VAULT_ADDR=http://127.0.0.1:8200 \
  vault kv put secret/keycloak/postgresql \
  username=keycloak_user password="$SM_PASS" \
  host=postgresql-external.default.svc.cluster.local port=5432 database=keycloak

# 2. Forçar ESO sync
kubectl annotate externalsecret keycloak-postgresql-credentials \
  -n keycloak force-sync="$(date +%s)" --overwrite

# 3. Verificar: SM password != RDS actual password → ALTER USER
kubectl run keycloak-psql-fix --image=postgres:15 -n keycloak \
  --restart=Never --env="PGPASSWORD=$MASTER_PASS" -- \
  psql -h k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com \
  -U postgres_admin -d postgres \
  -c "ALTER USER keycloak_user WITH PASSWORD '$KC_PASS';"
# → ALTER ROLE ✅

# 4. Restart pod
kubectl delete pod keycloak-keycloakx-0 -n keycloak
```

**Resultado:** `keycloak-keycloakx-0` 1/1 Running | RESTARTS: 0 | ✅

**Fix permanente (TF):**
Adicionado ao `modules/postgresql/databases.tf`:
```hcl
resource "aws_secretsmanager_secret" "keycloak_user_password" {
  name = "staging/postgresql/keycloak-password"
  ...
}
resource "aws_secretsmanager_secret_version" "keycloak_user_password" {
  secret_string = random_password.keycloak_user.result
}
```
→ Garante SM sempre reflete TF state. Evita drift futuro.

**⚠️ Próximo TF apply requer:**
```bash
terraform import module.postgresql.aws_secretsmanager_secret.keycloak_user_password \
  "staging/postgresql/keycloak-password"
```

---

## STOP-AND-FIX #3: Tempo Ingester S3 TLS Timeout (root cause corrigido)

**Problema:** `tempo-ingester-0/1` CrashLoopBackOff desde o startup (9h). 6 restarts totais.
```
err="failed to create store: unexpected error from ListObjects on k8s-platform-tempo-891377105802:
     Get \"https://...s3.us-east-1.amazonaws.com/...\": net/http: TLS handshake timeout"
```

**Root Cause Real (corrigido — análise anterior de 2026-02-18 estava INCORRETA):**

A análise de 2026-02-18 concluiu: "EC2 stop/start causa estado inconsistente no S3 VPC Gateway Endpoint routing — fresh nodes resolvem". Isso estava ERRADO.

**Causa real:** VPC CNI secondary ENI routing incompatibility com S3 VPC Gateway Endpoint:
1. Node `ip-10-0-153-44` (critical, us-east-1b) tem 3 ENIs (primary + 2 secondary)
2. Pod IP `10.0.145.81` foi atribuído à **ENI secundária** (device=1, eni-0ef2a5948e1bed18a)
3. VPC CNI cria `ip rule from 10.0.145.81 lookup VPC_CNI_RT_TABLE` para ENIs secundárias
4. A routing table do VPC CNI **NÃO contém** as rotas do S3 Gateway Endpoint
5. S3 traffic vai via NAT Gateway → TLS handshake timeout (S3 endpoint rejeita/dropa)

**Confirmação:** Route tables do subnet TÊM a rota S3 Endpoint:
```
✅ rtb-00c7af803ee93ac2c | fictor-rtb-private2-us-east-1b
✅ rtb-09656e8e3e2f44c62 | fictor-rtb-private1-us-east-1a
```
Mas a per-pod routing table criada pelo VPC CNI NÃO tem as rotas de prefixo S3.

**Por que o nodeSelector/affinity (fix anterior) NÃO resolve:** A ENI secundária é criada em QUALQUER node do critical nodegroup, independente da AZ. A afinidade `zone NotIn us-east-1a` apenas move o pod para us-east-1b, mas o pod ainda pode receber IP de ENI secundária.

**Fix permanente — AWS_VPC_K8S_CNI_EXTERNALSNAT=true:**
```bash
# Identificar índice do env var
IDX=$(kubectl get daemonset aws-node -n kube-system \
  -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}{"\n"}{end}' \
  | grep -n "AWS_VPC_K8S_CNI_EXTERNALSNAT" | cut -d: -f1)
IDX=$((IDX-1))  # zero-based

kubectl patch daemonset aws-node -n kube-system --type='json' \
  -p="[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/env/$IDX/value\",\"value\":\"true\"}]"
```

**Mecanismo do fix:**
- `EXTERNALSNAT=true` → pods usam SNAT via IP primário do node para tráfego outbound
- Tráfego S3 aparece com source IP = node primary ENI IP
- Node primary ENI usa subnet route table (que tem rota S3 Gateway Endpoint)
- S3 Gateway Endpoint route é matchada → tráfego vai para endpoint (não NAT) ✅

**Trade-off:** IP de saída para tráfego externo = IP do node (não pod). Aceitável em staging.

**Rolling update:**
```
[09:33] aws-node patched | 8/8 UP-TO-DATE | rolling update 15s | ✅
```

**Resultado:** `tempo-ingester-0/1` 1/1 Running | "Tempo started" sem TLS timeout | ✅

---

## AVISO: Drift SonarQube esperado no próximo up

**Por analogia:** `sonarqube_user` também não tem SM write no databases.tf (mesmo padrão).
Recomendação: adicionar `aws_secretsmanager_secret.sonarqube_user_password` ao databases.tf.

---

## Estado Final

```
[09:40] keycloak-keycloakx-0  | 1/1 Running | RESTARTS:0 | ✅
[09:40] tempo-ingester-0       | 1/1 Running | "Tempo started" OK | ✅
[09:40] tempo-ingester-1       | 1/1 Running | "Tempo started" OK | ✅
[09:40] aws-node               | 8/8 UP-TO-DATE | EXTERNALSNAT=true | ✅
[09:40] Todos os pods          | 135/135 Running | 0 Pending | 0 CrashLoop | ✅
```

---

## Fixes Permanentes Aplicados

| # | Arquivo | Mudança |
| - | ------- | ------- |
| 1 | `modules/postgresql/databases.tf` | `aws_secretsmanager_secret.keycloak_user_password` + `aws_secretsmanager_secret_version` |
| 2 | `kubectl patch daemonset aws-node` | `AWS_VPC_K8S_CNI_EXTERNALSNAT=false→true` |
| 3 | `modules/postgresql/databases.tf` | `aws_secretsmanager_secret.sonarqube_user_password` + `aws_secretsmanager_secret_version` |
| 4 | `environments/staging/eks-addons.tf` | `aws_eks_addon.vpc_cni` com `configurationValues` EXTERNALSNAT=true |
| 5 | `docs/context/decisions.md` | DEC-064: VPC CNI EXTERNALSNAT=true |

## Pendências Pós-Sessão

| Item | Prioridade | Notas |
|------|-----------|-------|
| ~~`terraform import` do SM keycloak-password~~ | ~~ANTES do próximo `terraform apply`~~ | ✅ CONCLUÍDO 2026-02-19 |
| ~~Adicionar SM write para `sonarqube_user` no databases.tf~~ | ~~Alta~~ | ✅ CONCLUÍDO 2026-02-19 |
| ~~Persistir EXTERNALSNAT no TF (EKS add-on config)~~ | ~~Média~~ | ✅ CONCLUÍDO 2026-02-19 — `eks-addons.tf` |
| ~~Atualizar `decisions.md` com ADR-063 (EXTERNALSNAT)~~ | ~~Baixa~~ | ✅ CONCLUÍDO 2026-02-19 — DEC-064 |

## Resolução SonarQube Drift (2026-02-19 pós-sessão)

**Drift detectado:** SM `staging/postgresql/sonarqube-password` (TF random_password) ≠ RDS actual ≠ K8s secret.

**Root cause:** `sonarqube-postgresql` K8s secret não gerenciado por ESO (apenas `sonarqube-sp-saml` tem ExternalSecret). A senha original do bootstrap permanecia no K8s secret enquanto o TF `random_password.sonarqube_user` evoluiu.

**Fix:**

```bash
# 1. ALTER USER sonarqube_user → senha TF/SM
kubectl run sonar-alter-pw --image=postgres:15 -n sonarqube \
  --restart=Never --env="PGPASSWORD=$MASTER_PASS" -- \
  psql -h k8s-platform-prod-postgresql... -U postgres_admin -d postgres \
  -c "ALTER USER sonarqube_user WITH PASSWORD 'B(SYDoBqWJc)Hh!QvXE!dCUFV_CwANGF';"
# → ALTER ROLE ✅

# 2. Atualizar K8s secret
kubectl patch secret sonarqube-postgresql -n sonarqube \
  --type='merge' -p='{"data":{"postgresql-password":"<base64-de-SM-password>"}}'

# 3. Restart SonarQube
kubectl delete pod sonarqube-sonarqube-0 -n sonarqube
```

**Resultado:** `sonarqube-sonarqube-0` 1/1 Running | HikariPool conectado | RESTARTS:0 ✅

**Fonte de verdade final:**

- TF `random_password.sonarqube_user` → SM `staging/postgresql/sonarqube-password` → RDS `sonarqube_user` → K8s secret `sonarqube/sonarqube-postgresql`

---

## Lições Aprendidas

1. **nodeName no STS template** → causa loop create/delete invisível por horas. Detectar via `kubectl get sts -o jsonpath '{.spec.template.spec.nodeName}'`.
2. **VPC CNI secondary ENI + S3 Gateway Endpoint** → a causa real é a per-pod routing table, não EC2 stop/start. `EXTERNALSNAT=true` é o fix correto.
3. **DB password drift** → sempre verificar SM vs Vault vs RDS ao encontrar auth failure. Padrão de SonarQube (2026-02-18) e Keycloak (2026-02-19) — mesmo root cause.
4. **ESO force-sync** não é suficiente se o K8s secret teve a senha errada — o ALTER USER no RDS também é necessário quando SM ≠ RDS real.
