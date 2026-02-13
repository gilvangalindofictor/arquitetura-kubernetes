# Logbook: SSO Smoke Test + Infrastructure Fixes

**Data:** 2026-02-13
**Operador:** Claude (executor-terraform)
**Cluster:** k8s-platform-prod (staging - account 891377105802)

## Contexto

Rodada de smoke tests SSO revelou 3 falhas de infraestrutura. Fixes aplicados seguindo protocolo executor-terraform.

## Timeline

### SSO Smoke Test (criacao + execucao)
- Criado `scripts/sso-smoke-test.sh` — 9 secoes, 44+ checks
- Resultado: **33 PASSED / 3 FAILED / 5 SKIPPED**
- Falhas identificadas: DNS CoreDNS, Redis AUTH, ExternalSecret/Vault

---

### FIX 1: CoreDNS DNS Rewrite (RESOLVIDO)
**Problema:** `keycloak.staging.internal` nao resolvia — CoreDNS rewrite apontava para `keycloak-http` (inexistente)
**Causa raiz:** Service renomeado pelo Helm chart codecentric/keycloakx para `keycloak-keycloakx-http`
**Fix:** Patch ConfigMap `coredns` em `kube-system`:
```
rewrite name keycloak.staging.internal keycloak-keycloakx-http.keycloak.svc.cluster.local
```
**Validacao:** `nslookup keycloak.staging.internal` → 172.20.156.202

---

### FIX 2: Redis AUTH Password Mismatch (RESOLVIDO)
**Problema:** GitLab envia password mas Redis nao tem `requirepass` configurado
**Causa raiz (cadeia):**
1. TF module usava SpotaHome operator (`databases.spotahome.com/v1` RedisFailover)
2. Cluster migrou para OT-Container-Kit (`redis.redis.opstreelabs.in/v1beta2` Redis) fora do TF
3. Redis CR sem `kubernetesConfig.redisSecret` (auth desabilitado)
4. Operator sem RBAC para API group `redis.redis.opstreelabs.in`
5. Imagem `redis:8.4.1-alpine` nao le env var `REDIS_PASSWORD`
6. Pod UID 999 vs imagem UID 1000 → Permission denied em `/etc/redis/redis.conf`

**Fixes aplicados (em sequencia):**
1. Patch CR: adicionado `redisSecret` → `{name: redis-password, key: password}`
2. Patch ClusterRole: adicionado `redis.redis.opstreelabs.in` API group com todas permissoes
3. Patch CR: `podSecurityContext` e `securityContext` PSS restricted compliant
4. Patch CR: `redisExporter.securityContext` PSS restricted compliant
5. Switch imagem: `redis:8.4.1-alpine` → `quay.io/opstree/redis:v8.4.0` (entrypoint le `REDIS_PASSWORD`)
6. Fix UID: `runAsUser` 999 → 1000 (match imagem redis user)
7. Removed `initContainer` (nao necessario com imagem correta)

**Validacao:**
- `redis-cli ping` → `NOAUTH Authentication required` (auth ativo)
- `redis-cli -a $PASS ping` → `PONG`
- GitLab webservice: `redis_calls:5, status:200` (Redis OK)

---

### FIX 3: Vault Recovery + ExternalSecret (RESOLVIDO)
**Problema:** `ClusterSecretStore vault-backend` → `unable to create client`
**Causa raiz:** 3/3 Vault EBS volumes deletados (volumes nao encontrados no EC2)
**Volumes perdidos:**
- `vol-012a9ddbdcc3d528a` (data-vault-0)
- `vol-086d07390ca0fcea2` (data-vault-2)
- `vol-0241687bfddf6b860` (data-vault-1)
- Audit volumes tambem perdidos

**Fixes aplicados:**
1. Delete PVs/PVCs orphaned (finalizers removidos)
2. Pods deletados → StatefulSet recriou com PVCs novos (gp2)
3. `vault operator init` (AWS KMS auto-unseal) → root token gerado
4. Enable `kv-v2` at `secret/`
5. Enable `kubernetes` auth method
6. Configure K8s auth: `kubernetes_host=https://kubernetes.default.svc.cluster.local:443`
7. Create policy `eso-reader` (read/list `secret/data/*`, `secret/metadata/*`)
8. Create role `eso-reader` (bound to `external-secrets` SA in `external-secrets-system`)
9. Seed secret `secret/keycloak/postgresql` (5 keys from cached K8s secret)
10. Restart ESO controller → `ClusterSecretStore` reconectou

**Validacao:**
- `ClusterSecretStore vault-backend` → `Ready: True, store validated`
- `ExternalSecret keycloak-postgresql-credentials` → `SecretSynced: True`

---

### FIX 4: Terraform Codificacao (APLICADO)
**Arquivo:** `platform-provisioning/aws/kubernetes/terraform/modules/redis/main.tf`
**Mudancas:**
- Header: SpotaHome v3.3.0 → OT-Container-Kit v0.23.0
- `helm_release`: Chart SpotaHome → OT-Container-Kit (`ot-helm/redis-operator` v0.18.1)
- `kubectl_manifest`: `RedisFailover` → `Redis` (v1beta2) com:
  - `kubernetesConfig.redisSecret` auth
  - `quay.io/opstree/redis:v8.4.0`
  - PSS restricted compliant (UID 1000)
  - Redis exporter com security context
- `outputs.tf`: Service names atualizados (backward compatible)

**NOTA:** TF apply nao executado (requer planejamento de state migration para recursos renomeados)

---

## Estado Final do Cluster

| Componente     | Status  | Observacao                                 |
| -------------- | ------- | ------------------------------------------ |
| Keycloak       | RUNNING | OIDC provider ativo, realm `platform`      |
| ArgoCD         | OK      | OIDC login funcional                       |
| GitLab         | PARTIAL | 1/3 webservice Running (capacity)          |
| Redis          | RUNNING | AUTH ativo, `quay.io/opstree/redis:v8.4.0` |
| Vault          | PARTIAL | 1/3 pods Running (capacity + PVC pending)  |
| ExternalSecret | OK      | SecretSynced = True                        |
| CoreDNS        | OK      | keycloak.staging.internal resolvendo       |

## Problemas Conhecidos (nao resolvidos)
1. **Cluster capacity**: 0/7 nodes available para novos pods (GitLab webservice 2/3 Pending, Vault 2/3 stuck)
2. **Vault HA**: Apenas vault-0 running (raft single-node), vault-1/2 com PVCs pending
3. **GitLab Runner**: CrashLoopBackOff (webservice retorna 500 no `/api/v4/runners`)
4. **TF state migration**: Redis module renomeou recursos (`redis_failover` → `redis`), precisa `terraform state mv`
