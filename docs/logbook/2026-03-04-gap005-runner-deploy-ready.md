# 2026-03-04 — GAP-005: Runner Deploy — Scripts e Runbook Prontos

**Demanda:** GAP-005 — Pipeline validation com job real (smoke test)
**Data:** 2026-03-04
**Status:** PRONTO PARA DEPLOY — 3 scripts + 1 runbook entregues

---

## Contexto

O runner GitLab está Running no cluster (pod: gitlab-gitlab-runner-*) mas o
`helm upgrade` com `values-staging-working.yaml` ainda não foi aplicado ao cluster.

Resultado: runner deployment NO cluster não possui `envFrom → gitlab-ci-credentials`,
impedindo que jobs CI recebam as credenciais HARBOR_* e SONAR_*.

## Estado do values-staging-working.yaml (COMPLETO)

Configs já presentes e prontos para deploy:

| Config | Valor | Propósito |
|--------|-------|-----------|
| `envFrom[0].secretRef.name` | `gitlab-ci-credentials` | Injeta credenciais no runner pod |
| `runners.config.request_concurrency` | `2` | Fix long-polling bottleneck |
| `runners.kubernetes.namespace` | `gitlab-staging` | Executor namespace correto |
| `runners.kubernetes.pod_labels` | `domain=integration,...` | ADR-048 compliance |
| `runners.kubernetes.pod_spec` | inject envFrom | Credenciais nos job pods |

## Artefatos Entregues

| Arquivo | Propósito |
|---------|-----------|
| `scripts/cicd/gap005-vault-unseal-gate.sh` | 8 checks pré-deploy (Vault, ESO, Secret) |
| `scripts/cicd/gap005-runner-deploy.sh` | Deploy end-to-end (gate → upgrade → verify) |
| `docs/runbooks/gap005-runner-deploy-runbook.md` | Runbook manual + troubleshooting |

## Sequência de Deploy (quando executar)

```bash
# 1. Garantir contexto kubectl correto
kubectl config current-context  # deve apontar para k8s-platform-prod

# 2. Rodar gate (valida Vault + ESO)
bash scripts/cicd/gap005-vault-unseal-gate.sh
# Exit 0 → prosseguir | Exit 1 → resolver FAILs primeiro | Exit 2 → prosseguir com cautela

# 3. Dry-run (opcional — visualizar sem aplicar)
bash scripts/cicd/gap005-runner-deploy.sh --dry-run

# 4. Deploy real
bash scripts/cicd/gap005-runner-deploy.sh

# 5. Verificar logs do runner
kubectl logs -n gitlab-staging -l app=gitlab-runner --tail=50

# 6. Smoke test
bash scripts/cicd/create-smoke-test-project.sh
```

## Impacto Esperado Pós-Deploy

- Runner pod reinicia com `envFrom → gitlab-ci-credentials`
- Jobs CI recebem automaticamente: `HARBOR_REGISTRY`, `HARBOR_USER`, `HARBOR_PASSWORD`, `SONAR_HOST_URL`, `SONAR_TOKEN`
- Pipeline smoke test consegue push Harbor + SonarQube scan sem variáveis manuais
- ADR-048: job pods têm labels `domain=integration` (Kyverno compliant)
- request_concurrency=2: elimina long-polling bottleneck

## Pós-Deploy Checklist

- [ ] `kubectl get deployment gitlab-gitlab-runner -n gitlab-staging -o yaml | grep envFrom` → resultado não vazio
- [ ] `kubectl exec <runner-pod> -- sh -c 'echo $HARBOR_REGISTRY'` → retorna URL
- [ ] Pipeline smoke-test-ci: stages validate/build/push = PASSED
- [ ] Kyverno: job pods com `domain=integration` label = PASS
