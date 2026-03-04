# GAP-005 Runner Deploy Runbook

**Demanda:** GAP-005 — CI/CD End-to-End Pipeline Validation
**Namespace:** `gitlab-staging`
**Helm release:** `gitlab` (chart `gitlab/gitlab` v9.9.1)
**Data:** 2026-03-04

---

## Pré-requisitos

| Item | Verificação |
|------|-------------|
| kubectl | `kubectl version --client` |
| helm | `helm version` |
| helm repo gitlab | `helm repo list \| grep gitlab` |
| Acesso ao cluster | `kubectl get nodes` |
| ExternalSecret Ready | ver seção Vault Gate |

Adicionar repo se necessário:
```bash
helm repo add gitlab https://charts.gitlab.io
helm repo update
```

---

## 1. Vault Gate

Verificar que Vault está Running e unsealed antes do deploy.

```bash
# Status dos pods
kubectl get pods -n staging-security-vault -l app.kubernetes.io/name=vault

# Status de seal do vault-0
kubectl exec vault-0 -n staging-security-vault -- vault status
# Deve mostrar: Sealed: false
```

Se vault-0 estiver sealed, aguardar KMS auto-unseal (~20s). Se persistir:
```bash
kubectl delete pod vault-0 -n staging-security-vault
# KMS auto-unseal em ~20s
```

---

## 2. ESO Sync — ExternalSecret

Verificar que `gitlab-ci-credentials` está sincronizado:
```bash
kubectl get externalsecret gitlab-ci-credentials -n gitlab-staging
# STATUS: SecretSynced
```

Force-sync se necessário:
```bash
kubectl annotate externalsecret gitlab-ci-credentials \
  -n gitlab-staging \
  force-sync=$(date +%s) --overwrite
```

Verificar as 5 keys do secret resultante:
```bash
kubectl get secret gitlab-ci-credentials -n gitlab-staging \
  -o jsonpath='{.data}' | python3 -m json.tool | grep -o '"[A-Z_]*":'
# Esperado: HARBOR_REGISTRY, HARBOR_USER, HARBOR_PASSWORD, SONAR_HOST_URL, SONAR_TOKEN
```

---

## 3. Helm Upgrade

### Dry-run (recomendado antes do apply)
```bash
bash scripts/cicd/gap005-runner-deploy.sh --dry-run
```

### Apply
```bash
bash scripts/cicd/gap005-runner-deploy.sh
```

### Comando explícito (se preferir executar manualmente)
```bash
helm upgrade gitlab gitlab/gitlab \
  --namespace gitlab-staging \
  --version 9.9.1 \
  --values platform-provisioning/aws/kubernetes/terraform/modules/gitlab/values-staging-working.yaml \
  --atomic \
  --timeout 300s \
  --cleanup-on-fail
```

Pular vault gate (ambiente sem Vault acessível):
```bash
bash scripts/cicd/gap005-runner-deploy.sh --skip-gate
```

---

## 4. Verificação Pós-Deploy

### Runner pod reiniciou
```bash
kubectl rollout status deployment/gitlab-gitlab-runner -n gitlab-staging --timeout=120s

kubectl get pod -n gitlab-staging -l app=gitlab-runner
# STATUS: Running
```

### envFrom presente no deployment
```bash
kubectl get deployment gitlab-gitlab-runner -n gitlab-staging \
  -o jsonpath='{.spec.template.spec.containers[0].envFrom}' | python3 -m json.tool
# Deve conter: {"secretRef": {"name": "gitlab-ci-credentials"}}
```

### Variáveis injetadas no pod
```bash
RUNNER_POD=$(kubectl get pod -n gitlab-staging -l app=gitlab-runner \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec "$RUNNER_POD" -n gitlab-staging -- \
  sh -c 'test -n "$HARBOR_REGISTRY" && echo "HARBOR_REGISTRY: SET" || echo "HARBOR_REGISTRY: UNSET"'
```

### Logs do runner
```bash
kubectl logs -n gitlab-staging -l app=gitlab-runner --tail=20
# Deve mostrar: Registering runner... succeeded
```

### Helm history
```bash
helm history gitlab -n gitlab-staging --max 5
# Nova revision com STATUS: deployed
```

---

## 5. Rollback

Listar revisões disponíveis:
```bash
helm history gitlab -n gitlab-staging
```

Rollback para revisão anterior:
```bash
helm rollback gitlab <PREVIOUS_REVISION> -n gitlab-staging
# Exemplo: helm rollback gitlab 36 -n gitlab-staging
```

Verificar rollback:
```bash
helm history gitlab -n gitlab-staging --max 3
kubectl rollout status deployment/gitlab-gitlab-runner -n gitlab-staging
```

---

## 6. Troubleshooting

### Cenário 1: Vault sealed

**Sintoma:** Gate BLOQUEADO — `Sealed: true`

```bash
# Verificar status
kubectl exec vault-0 -n staging-security-vault -- vault status

# Aguardar KMS (20s) ou forçar restart
kubectl delete pod vault-0 -n staging-security-vault
sleep 25
kubectl exec vault-0 -n staging-security-vault -- vault status | grep Sealed
```

### Cenário 2: ExternalSecret não sincroniza

**Sintoma:** `ESO_STATUS != SecretSynced` ou secret com menos de 5 keys

```bash
# Verificar eventos do ESO
kubectl describe externalsecret gitlab-ci-credentials -n gitlab-staging

# Verificar se ESO operator está Running
kubectl get pods -n external-secrets

# Verificar SecretStore
kubectl get secretstore -n gitlab-staging
kubectl describe secretstore vault-backend -n gitlab-staging

# Paths esperados no Vault:
#   secret/gitlab-ci/harbor → HARBOR_REGISTRY, HARBOR_USER, HARBOR_PASSWORD
#   secret/gitlab-ci/sonar  → SONAR_HOST_URL, SONAR_TOKEN

# Force-sync
kubectl annotate externalsecret gitlab-ci-credentials \
  -n gitlab-staging \
  force-sync=$(date +%s) --overwrite
```

### Cenário 3: envFrom ausente após deploy

**Sintoma:** `envFrom NÃO detectado` no post-check

```bash
# Verificar spec do deployment
kubectl get deployment gitlab-gitlab-runner -n gitlab-staging \
  -o yaml | grep -A 10 envFrom

# Se ausente, verificar se values file tem a configuração correta
grep -A 5 "envFrom" \
  platform-provisioning/aws/kubernetes/terraform/modules/gitlab/values-staging-working.yaml

# Forçar rollout para pegar ConfigMap/Secret atualizado
kubectl rollout restart deployment/gitlab-gitlab-runner -n gitlab-staging
kubectl rollout status deployment/gitlab-gitlab-runner -n gitlab-staging --timeout=120s
```
