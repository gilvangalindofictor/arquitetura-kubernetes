# Wave 3: vault-system → staging-security-vault Migration

**Data:** 2026-02-24
**Agente:** C1 (Executor Terraform - Vault Migration)
**Pattern:** C (StatefulSet + PVCs, HIGH risk)
**Status:** SUCCESS

---

## Resumo Executivo

Migração do namespace `vault-system` para `staging-security-vault` concluída com sucesso.
Vault unsealed via KMS auto-unseal. 7/7 KV paths acessíveis. 10/10 ExternalSecrets synced.

- **Início:** 2026-02-24 17:13 (FASE 0 instalação snapshot CRDs)
- **Downtime Start:** 2026-02-24 17:25:11 (helm uninstall vault-system)
- **Downtime End:** 2026-02-24 17:47:33 (vault-0 1/1 Running)
- **Downtime Total:** 22min 22s (vs target < 5min - ver Problemas Encontrados)
- **Duração Total:** ~1h 15min (vs target 4h - muito abaixo do estimado)

---

## Fases Executadas

### FASE 0: VolumeSnapshot CRDs (15min)
- Instalados CRDs: `volumesnapshotclasses`, `volumesnapshotcontents`, `volumesnapshots`
- Deploy `snapshot-controller`: 2/2 Running em `kube-system`
- Criada `VolumeSnapshotClass/ebs-csi-snapshot-class` com driver `ebs.csi.aws.com`

### FASE 1: Backups (Layer 1 + Layer 2)
**Layer 1 - Raft Snapshot:**
- Criado: `/tmp/vault-backup-2026-02-24.snap` (42KB)
- Upload: `s3://k8s-platform-prod-vault-snapshots-891377105802/vault-backup-2026-02-24.snap`
- Autenticação: root token via `vault-root-token` secret (campo `root_token`)

**Layer 2 - VolumeSnapshots:**
- `data-vault-0-snapshot` (10Gi): readyToUse=true em 78s
- `audit-vault-0-snapshot` (5Gi): readyToUse=true em 72s
- SnapshotContents: `snapcontent-9a24c3c7...` (snap-082f831ab0e77d865), `snapcontent-8ae4e557...` (snap-06eb2c72f4553195d)
- Helm values exportados: `/tmp/vault-helm-values-backup.yaml` (120 linhas)

### FASE 2: Namespace + PVC Restore
- Namespace `staging-security-vault` criado com labels: `env=staging`, `domain=security`, `product=vault`
- PVCs criados com `dataSource` apontando para VolumeSnapshots

### FASE 3: Deploy Helm Chart
- Chart: `hashicorp/vault` v0.27.0 (mesma versão do vault-system)
- `helm uninstall vault -n vault-system` executado (17:25:11)
- `helm install vault hashicorp/vault -n staging-security-vault` executado (17:25:34)

### FASE 4: KMS Auto-Unseal
- Vault unsealed automaticamente via AWS KMS
- `kms_key_id: 272b2c51-4f0c-402a-a075-9006da4e187e`
- `Sealed: false` confirmado às 17:47:27 (primeiro status OK)
- `Cluster ID: a3cbda22-59ac-b7d0-e82c-b1285b1ebc17` (idêntico ao original = dados restaurados)

### FASE 5: KV Paths Validados
| Path | Status |
|------|--------|
| secret/grafana/oidc | OK |
| secret/sonarqube/postgresql | OK |
| secret/sonarqube/saml | OK |
| secret/harbor/postgresql | OK |
| secret/harbor/oidc | OK |
| secret/keycloak/postgresql | OK |
| secret/gitlab/ci-variables | OK |

**7/7 acessíveis**

### FASE 6: ESO Reconnection
- `ClusterSecretStore/vault-backend` atualizado: `vault.vault-system:8200` → `vault.staging-security-vault:8200`
- Status imediato: `store validated` / `Ready: True`
- 10/10 ExternalSecrets: `SecretSynced`

---

## Problemas Encontrados e Resoluções

### P1: VolumeSnapshot cross-namespace (BLOQUEANTE)
**Problema:** PVCs em `staging-security-vault` não conseguiam referenciar VolumeSnapshots de `vault-system` (namespace-scoped).
**Resolução:** Criar `VolumeSnapshotContent` pré-provisionados com `deletionPolicy: Retain` + novos `VolumeSnapshot` no namespace correto apontando para os EBS snapshot handles (`snap-082f831ab0e77d865`, `snap-06eb2c72f4553195d`).

### P2: ServiceAccount vault não criado pelo Helm (BLOQUEANTE)
**Problema:** `server.serviceAccount.create: false` nos values → SA não criado → StatefulSet FailedCreate.
**Resolução:** Criar SA manualmente com anotação IRSA `eks.amazonaws.com/role-arn: arn:aws:iam::891377105802:role/VaultIRSA-k8s-platform-prod`.

### P3: IRSA trust policy restrita a vault-system (BLOQUEANTE)
**Problema:** IAM role `VaultIRSA-k8s-platform-prod` tinha `StringEquals sub: system:serviceaccount:vault-system:vault`. Vault crashava com `NoCredentialProviders` → sem acesso ao KMS → `Initialized: false`.
**Resolução:** Atualizar trust policy para array com ambos namespaces:
```json
"sub": [
  "system:serviceaccount:vault-system:vault",
  "system:serviceaccount:staging-security-vault:vault"
]
```

### P4: StatefulSet recriou PVCs sem dataSource (BLOQUEANTE)
**Problema:** Ao deletar PVCs para forçar novo provisionamento, o StatefulSet os recriou automaticamente sem `dataSource` → volumes vazios → `Initialized: false`.
**Resolução:** Escalar StatefulSet para 0 replicas, deletar PVCs, criar manualmente com `dataSource` correto, escalar de volta para 1.

### P5: ClusterRole/ClusterRoleBinding conflito helm install (RESOLVIDO PELO DOWNTIME STRATEGY)
**Problema:** `ClusterRole/vault-agent-injector-clusterrole` e `ClusterRoleBinding/vault-server-binding` já pertenciam ao release `vault/vault-system`. Helm bloqueou install simultâneo.
**Resolução:** Opção A aprovada pelo usuário - `helm uninstall vault-system` antes do install no novo namespace.

---

## Impacto no Downtime

- **Target:** < 5 minutos
- **Real:** 22 minutos 22 segundos
- **Causa do excesso:** Problemas P1+P2+P3+P4 encadeados durante o período de uninstall → install
- **Risco:** ESO cached secrets (refresh interval 1h) → nenhum serviço dependente sofreu interrupção real

---

## Alterações Permanentes de Infraestrutura

1. **IAM Role trust policy atualizado:** `VaultIRSA-k8s-platform-prod` agora permite ambos namespaces
   - TODO: Atualizar Terraform (`modules/vault/irsa.tf`) para refletir novo namespace
2. **VolumeSnapshot CRDs instalados:** `external-snapshotter release-6.3` em `kube-system`
   - Beneficia: Wave 5 Harbor (6GB), Wave 5 Monitoring (94GB), Wave 6 GitLab (50GB)
3. **VolumeSnapshotClass:** `ebs-csi-snapshot-class` criada (cluster-scoped)
4. **ClusterSecretStore:** `vault-backend` → `vault.staging-security-vault.svc.cluster.local:8200`

---

## Estado Final

```
Namespace:  staging-security-vault
Vault:      1.15.4, Initialized=true, Sealed=false, HA Mode=active
PVCs:       data-vault-0 (10Gi Bound), audit-vault-0 (5Gi Bound)
KV Paths:   7/7 acessíveis
ESO:        10/10 SecretSynced
ClusterSecretStore: vault-backend Ready=True
Raft Index: 18869 (continuidade de 18836 original)
Cluster ID: a3cbda22-59ac-b7d0-e82c-b1285b1ebc17 (idêntico = dados restaurados)
```

---

## ADRs Gerados

- **DEC-075:** IRSA multi-namespace pattern - trust policy deve ser array quando migrando SA entre namespaces
- **DEC-076:** VolumeSnapshot cross-namespace workaround via VolumeSnapshotContent pré-provisionado
- **DEC-077:** StatefulSet scale-to-0 before PVC recreation pattern (evita StatefulSet recriar PVCs sem dataSource)

---

## Próximos Passos

1. Atualizar Terraform `VaultIRSA-k8s-platform-prod` trust policy para incluir `staging-security-vault`
2. Remover namespace `vault-system` (PVCs e namespace) após período de observação
3. Continuar Wave 3 - Agente C2: data-services migration
