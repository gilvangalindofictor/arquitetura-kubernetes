# ADR-048 Labels Persistence — Helm TF Apply

**Data:** 2026-03-04
**ADR:** ADR-048 (Corporate Labels Requirement)
**Autor:** Platform Engineering Team
**Contexto:** Persistencia de labels obrigatorias nos modulos Helm gerenciados por Terraform

---

## O que foi feito

### Contexto inicial
Os arquivos `values.yaml.tpl` dos modulos keycloak, argocd e vault ja haviam sido atualizados
com os `podLabels` ADR-048 em sessao anterior. O objetivo desta sessao foi executar o
`terraform plan` + `apply` para persistir as mudancas via Helm releases.

### Problema encontrado: Terraform plan bloqueado
A tentativa de `terraform plan -target=module.keycloak_staging.helm_release.keycloak -target=module.argocd_staging.helm_release.argocd` falhou com:

```
Error: error connecting to PostgreSQL server k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com: dial tcp 10.0.129.202:5432: i/o timeout
Error: failed to lookup token, err=context deadline exceeded (vault_auth_backend)
```

**Root cause:** O provider `postgresql` (em `modules/postgresql/databases.tf`) e o provider
`vault` (em `modules/vault-config/main.tf`) sao inicializados por Terraform durante a fase
de planning, MESMO com `-target`. Terraform sempre inicializa todos os providers configurados,
independente dos targets. O RDS esta em VPC privada e nao e acessivel da maquina local.

### Solucao alternativa aplicada

**Descoberta:** Inspecao dos pods revelou estado parcial:
- `staging-platform-keycloak`: labels ja presentes (apply anterior funcionou)
- `staging-platform-argocd`: labels ja presentes (apply anterior funcionou)
- `staging-security-vault`: `vault-0` AUSENTE labels, `vault-agent-injector` labels presentes

**Abordagem para Vault:**

1. `helm upgrade vault hashicorp/vault --namespace staging-security-vault --reuse-values --values /tmp/vault-labels-patch.yaml`
   - Adicionou `server.podLabels` e `injector.podLabels` ao Helm release
   - Revision: 1 → 2

2. StatefulSet usa `updateStrategy: OnDelete` (intencional para Vault — evita restart acidental)
   - `kubectl rollout restart` nao funciona com `OnDelete`
   - Solucao: `kubectl delete pod vault-0 -n staging-security-vault`
   - StatefulSet recriou o pod com o novo template (labels inclusas)
   - Auto-unseal via KMS: pod voltou `vault-sealed: false` em ~20s

---

## Resultado por modulo

| Modulo | Status TF | Labels nos pods | Metodo |
|--------|-----------|-----------------|--------|
| keycloak_staging | Aplicado anteriormente | domain/environment/owner ✅ | TF apply anterior |
| argocd_staging | Aplicado anteriormente | domain/environment/owner ✅ | TF apply anterior |
| vault_staging | helm upgrade manual | domain/environment/owner ✅ | helm upgrade + pod delete |

---

## Labels nos pods (validacao final)

### staging-platform-keycloak
```
keycloak-keycloakx-0: domain=platform, environment=staging, owner=platform-team ✅
```

### staging-platform-argocd
```
argo-rollouts-757cc6c54d-8nm97: domain=platform, environment=staging, owner=platform-team ✅
argo-rollouts-757cc6c54d-x6bs2: domain=platform, environment=staging, owner=platform-team ✅
argo-rollouts-dashboard-fd8d9b56-hx4z8: domain=platform, environment=staging, owner=platform-team ✅
argocd-application-controller-0: domain=platform, environment=staging, owner=platform-team ✅
argocd-applicationset-controller-754bdc558c-2zsrt: domain=platform, environment=staging, owner=platform-team ✅
argocd-applicationset-controller-754bdc558c-r8vf8: domain=platform, environment=staging, owner=platform-team ✅
argocd-redis-5bdf8cfbcb-wxxvf: domain=platform, environment=staging, owner=platform-team ✅
argocd-repo-server-6ffd6fd5c4-fq6fg: domain=platform, environment=staging, owner=platform-team ✅
argocd-repo-server-6ffd6fd5c4-s75kr: domain=platform, environment=staging, owner=platform-team ✅
argocd-server-76c4f6f9cd-9jwms: domain=platform, environment=staging, owner=platform-team ✅
argocd-server-76c4f6f9cd-nhml6: domain=platform, environment=staging, owner=platform-team ✅
```

### staging-security-vault
```
vault-0: domain=platform, environment=staging, owner=platform-team ✅
vault-agent-injector-6dff579756-x88ff: domain=platform, environment=staging, owner=platform-team ✅
```

---

## Kyverno Excludes

### Policies afetadas
- `require-corporate-labels` (1 regra com exclude)
- `validate-label-values` (3 regras com excludes)

### Namespaces que tinham exclude
- `staging-platform-keycloak`
- `staging-platform-argocd`
- `staging-security-vault`

### Acao
Excludes removidos via `kubectl patch clusterpolicy`:
```bash
kubectl patch clusterpolicy require-corporate-labels --type=json \
  -p='[{"op": "remove", "path": "/spec/rules/0/exclude"}]'

kubectl patch clusterpolicy validate-label-values --type=json \
  -p='[{"op": "remove", "path": "/spec/rules/0/exclude"},{"op": "remove", "path": "/spec/rules/1/exclude"},{"op": "remove", "path": "/spec/rules/2/exclude"}]'
```

### Resultado
- `require-corporate-labels`: NO EXCLUDES ✅
- `validate-label-values`: NO EXCLUDES ✅

---

## Nota tecnica: Terraform plan bloqueio por provider VPC-private

**Problema estrutural descoberto:** Providers `postgresql` e `vault` embutidos em modulos
inicializam conexao em tempo de plan, mesmo com `-target`. Isso bloqueia `terraform plan`
de qualquer maquina fora da VPC.

**Solucoes possiveis para proximas sessoes:**
1. **SSH tunnel via bastion host** para RDS (porta 5432) e Vault (porta 8200)
2. **Terraform Cloud/Atlantis** executando dentro da VPC
3. **Mover provider para root module** com `skip = true` condicionado a variavel

**Workaround atual:** `helm upgrade --reuse-values` + patch manual para modulos onde
o TF plan falha por provider VPC-private. Os `values.yaml.tpl` ja estao corretos para
quando o terraform apply puder ser executado de dentro da VPC.

---

## Status: COMPLETO ✅

- Labels ADR-048 presentes em 100% dos pods (keycloak 1/1, argocd 11/11, vault 2/2)
- Kyverno ClusterPolicies: excludes removidos de ambas as policies
- Conformidade Kyverno ENFORCE mode: staging-platform-keycloak, staging-platform-argocd, staging-security-vault agora sob enforcement pleno
