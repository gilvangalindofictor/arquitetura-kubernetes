# Secret Rotation Policy — K8s Platform Staging

**Data:** 2026-02-18
**Responsável:** Platform Engineering
**Classificação:** Operacional — Segurança
**Referência:** R-010 (risks.md), ADR-055

---

## Escopo

Este documento define a política de rotação de credenciais para o ambiente **staging** da plataforma Kubernetes. Inclui todos os segredos armazenados em AWS Secrets Manager, Vault, e Kubernetes Secrets.

---

## Inventário de Credenciais e Frequência de Rotação

| Credencial | Armazenamento | Frequência | Última Rotação | Responsável |
|---|---|---|---|---|
| AWS IAM Access Keys (CI/CD) | Secrets Manager | 90 dias | 2026-02-18 | DevOps |
| RDS postgres_admin password | Secrets Manager | 90 dias | 2026-01-28 | DBA/DevOps |
| RDS app users (gitlab, keycloak, sonarqube) | Secrets Manager | 180 dias | 2026-01-28 | DBA |
| Keycloak admin password | K8s Secret + Vault | 90 dias | 2026-02-11 | Platform |
| GitLab OIDC client secret | Keycloak + K8s | 180 dias | 2026-02-11 | Platform |
| Harbor admin password | K8s Secret | 90 dias | 2026-02-14 | Platform |
| SonarQube admin password | K8s Secret | 90 dias | 2026-02-14 | Platform |
| Vault root token | Vault (sealed) | Única rotação pós-init | 2026-02-09 | Vault Admin |
| Vault unseal keys | Vault (sealed) | A cada re-init | 2026-02-09 | Vault Admin |
| Grafana admin password | K8s Secret | 180 dias | 2026-01-28 | Platform |
| ArgoCD admin password | K8s Secret | 90 dias | 2026-01-28 | Platform |
| RabbitMQ default_user password | K8s Secret | 180 dias | 2026-01-28 | Platform |

---

## Procedimento de Rotação

### 1. RDS Passwords (postgres_admin)

```bash
# 1. Gerar nova senha segura
NEW_PASS=$(openssl rand -base64 32 | tr -d '/@"')

# 2. Atualizar no AWS Secrets Manager
aws secretsmanager put-secret-value \
  --secret-id "k8s-platform-staging/rds/master" \
  --secret-string "{\"password\":\"$NEW_PASS\"}"

# 3. Atualizar no RDS
aws rds modify-db-instance \
  --db-instance-identifier k8s-platform-staging-postgresql \
  --master-user-password "$NEW_PASS" \
  --apply-immediately

# 4. Atualizar K8s Secret (se referenciado diretamente)
kubectl create secret generic rds-master-password \
  -n monitoring --from-literal=password="$NEW_PASS" \
  --dry-run=client -o yaml | kubectl apply -f -

# 5. Restart workloads que usam a credential
kubectl rollout restart deployment -n gitlab-staging
```

### 2. RDS App Users (gitlab, keycloak, sonarqube)

```bash
# 1. Gerar nova senha
NEW_PASS=$(openssl rand -base64 32 | tr -d '/@"')
APP=gitlab  # ou keycloak, sonarqube

# 2. Atualizar no RDS via psql
kubectl run psql-rotate -n data-services --restart=Never --rm -it \
  --image=postgres:16.4-alpine -- \
  psql "postgresql://postgres_admin:<admin-pass>@<rds-endpoint>:5432/postgres?sslmode=require" \
  -c "ALTER USER ${APP}_user WITH PASSWORD '$NEW_PASS';"

# 3. Atualizar Secrets Manager
aws secretsmanager put-secret-value \
  --secret-id "k8s-platform-staging/rds/${APP}" \
  --secret-string "{\"username\":\"${APP}_user\",\"password\":\"$NEW_PASS\"}"

# 4. Atualizar K8s Secret
kubectl create secret generic ${APP}-db-password \
  -n ${APP}-staging --from-literal=password="$NEW_PASS" \
  --dry-run=client -o yaml | kubectl apply -f -

# 5. Restart workload
kubectl rollout restart deployment -n ${APP}-staging
```

### 3. Keycloak Admin Password

```bash
# Via Keycloak Admin CLI (se disponível)
kubectl exec -n keycloak keycloak-0 -- \
  /opt/keycloak/bin/kcadm.sh set-password \
  -r master --username admin --new-password "$NEW_PASS"

# Atualizar K8s Secret
kubectl patch secret keycloak-admin -n keycloak \
  --type='json' \
  -p='[{"op":"replace","path":"/data/admin-password","value":"'$(echo -n "$NEW_PASS" | base64)'"}]'
```

### 4. OIDC Client Secrets (GitLab, ArgoCD, Grafana, Harbor, SonarQube)

```bash
# 1. Gerar novo secret no Keycloak Admin UI ou via kcadm.sh
kubectl exec -n keycloak keycloak-0 -- \
  /opt/keycloak/bin/kcadm.sh regenerate-secret \
  -r platform --id <client-uuid>

# 2. Atualizar K8s Secret no namespace do cliente
# Exemplo GitLab:
kubectl create secret generic gitlab-oidc-keycloak \
  -n gitlab-staging \
  --from-literal=provider="$(cat /tmp/gitlab-oidc-provider.yaml)" \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. Restart workload
kubectl rollout restart deployment gitlab-webservice-default -n gitlab-staging
```

### 5. AWS IAM Access Keys (CI/CD)

```bash
# 1. Criar nova access key
aws iam create-access-key --user-name <ci-user> > /tmp/new-key.json

# 2. Atualizar secret no CI/CD (GitHub Actions, GitLab CI)
# GitHub:
gh secret set AWS_ACCESS_KEY_ID --body "$(jq -r .AccessKey.AccessKeyId /tmp/new-key.json)"
gh secret set AWS_SECRET_ACCESS_KEY --body "$(jq -r .AccessKey.SecretAccessKey /tmp/new-key.json)"

# 3. Desativar access key antiga (APÓS confirmar novo funciona)
aws iam update-access-key --access-key-id <OLD_KEY> --status Inactive --user-name <ci-user>

# 4. Deletar access key antiga (após 7 dias)
aws iam delete-access-key --access-key-id <OLD_KEY> --user-name <ci-user>

# 5. Limpar arquivo temporário
rm -f /tmp/new-key.json
```

---

## Calendário de Rotação (2026)

| Mês | Credenciais a Rotacionar |
|---|---|
| Março/2026 | RDS postgres_admin, Keycloak admin, Harbor admin, SonarQube admin, ArgoCD admin |
| Abril/2026 | AWS IAM Access Keys (CI/CD) |
| Maio/2026 | RDS postgres_admin, Keycloak admin, Harbor admin, SonarQube admin |
| Junho/2026 | RDS app users, OIDC client secrets, Grafana admin, RabbitMQ password |
| Agosto/2026 | RDS postgres_admin, Keycloak admin, Harbor admin, SonarQube admin, AWS IAM |
| Novembro/2026 | RDS postgres_admin, Keycloak admin, Harbor admin, SonarQube admin |

---

## Processo de Emergência (Breach Response)

Em caso de suspeita de comprometimento de credencial:

1. **Revogar imediatamente** a credencial suspeita (disable, não delete)
2. **Criar nova credencial** e atualizar todos os sistemas dependentes
3. **Analisar CloudTrail** para acesso não autorizado:
   ```bash
   aws cloudtrail lookup-events \
     --lookup-attributes AttributeKey=Username,AttributeValue=<user> \
     --start-time 2026-01-01 \
     --query 'Events[?ErrorCode!=`null`]'
   ```
4. **Notificar** responsável de segurança
5. **Documentar** incidente no logbook (`docs/logbook/`)
6. **Rotation audit** — revisar todos os segredos relacionados

---

## Validação Pós-Rotação

Após cada rotação, executar:

```bash
# 1. Verificar pods em Running (sem CrashLoop)
kubectl get pods -A | grep -v Running | grep -v Completed | grep -v Pending

# 2. Health check por namespace crítico
for ns in keycloak gitlab-staging monitoring argocd vault-system; do
  echo "=== $ns ==="
  kubectl get pods -n $ns --no-headers | awk '{print $3}' | sort | uniq -c
done

# 3. Validar git-secrets scan (sem false positives)
git secrets --scan-history 2>&1 | tail -5
```

---

## Auditoria Mensal

Executar mensalmente (`cron` ou manualmente):

```bash
# Listar access keys por idade
aws iam list-users --query 'Users[].UserName' --output text | \
  xargs -I{} aws iam list-access-keys --user-name {} \
  --query 'AccessKeyMetadata[?Status==`Active`].{User:`{}`}[],AccessKeyMetadata[?Status==`Active`].{Created:CreateDate}[]'

# Verificar secrets no Secrets Manager por LastChangedDate
aws secretsmanager list-secrets \
  --query 'SecretList[].{Name:Name,LastChanged:LastChangedDate}' \
  --output table
```

---

## Referências

- [R-010 — Secrets Leak em Git](../context/risks.md#r-010-secrets-leak-em-git)
- [STRICT-RULES.md](../governance/STRICT-RULES.md)
- [Pre-commit hook](.git/hooks/pre-commit) — git-secrets AWS plugin
- AWS Secrets Manager: `k8s-platform-staging/*`
- CloudTrail: Região us-east-1
