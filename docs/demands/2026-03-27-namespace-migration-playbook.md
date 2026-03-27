# Playbook: Migracao de Namespaces para Convencao ADR-048

**Data:** 2026-03-27
**Status:** PLANEJAMENTO
**Prioridade:** P2
**Referencia:** ADR-048 (Naming Conventions Deterministicas)

---

## 1. Contexto

O cluster possui namespaces legados criados antes da ADR-048 que nao seguem a convencao
`{env}-{dominio}-{servico}`. Esses namespaces precisam ser migrados para garantir
conformidade com Kyverno policies e permitir transicao da policy
`enforce-argocd-appproject-destinations` de Audit para Enforce.

A FinOps Lambda utiliza `EXCLUDED_NAMESPACES` com exact string match (set membership).
Qualquer namespace cujo nome nao coincida exatamente esta DESPROTEGIDO da exclusao.

### Fix Lambda aplicado (2026-03-27)

| Arquivo | Fix |
|---------|-----|
| `environments/prod/finops-automation-prod.tf` L90-104 | `"kyverno"` -> `"staging-governance-kyverno"`, adicionado `"staging-security-certmanager"` |
| `modules/finops-automation/lambda/lambda_start_prod.py` L143-145 | Adicionado `"staging-security-certmanager"` |
| `modules/finops-automation/lambda/lambda_stop_prod.py` L153-155 | Ja corrigido previamente |

---

## 2. Inventario -- Namespaces Legados vs ADR-048

| Namespace Legado | Tipo | Workloads Ativos? | Namespace ADR-048 Alvo | Prioridade |
|---|---|---|---|---|
| `cert-manager` | Vazio (migrado) | NAO -- 0 pods | `staging-security-certmanager` (ja existe, 3 pods) | DONE |
| `external-secrets-system` | Vazio (migrado) | NAO -- 0 recursos | `staging-security-externalsecrets` (ja existe) | Remover NS |
| `harbor-system` | ATIVO Harbor staging | SIM -- 7+ pods | Coexiste com `staging-platform-harbor` | P1 |
| `vault-system` | Vazio (migrado) | NAO -- 0 recursos | `staging-security-vault` (ja existe) | Remover NS |
| `calico-system` | Sistema CNI | SIM (15 pods) | Manter (CNI nao segue ADR-048) | N/A |
| `linkerd` | Service Mesh | SIM (3 pods) | Manter (mesh nao segue ADR-048) | N/A |
| `linkerd-cni` | Service Mesh CNI | SIM (14 pods) | Manter (mesh nao segue ADR-048) | N/A |
| `linkerd-viz` | Mesh Viz | SIM (4 pods) | Manter (mesh nao segue ADR-048) | N/A |
| `kube-system` | Kubernetes core | SIM | Manter (K8s core) | N/A |
| `kube-public` | Kubernetes core | NAO | Manter (K8s core) | N/A |
| `kube-node-lease` | Kubernetes core | NAO | Manter (K8s core) | N/A |
| `ingress-nginx` | Ingress | NAO -- 0 recursos | Remover NS | Remover NS |
| `default` | Kubernetes | NAO (vazio) | Manter (K8s core) | N/A |
| `velero` | Backup | SIM | Manter (cluster-wide service) | N/A |
| `rabbitmq-system` | Operator CRD | Verificar | Manter (operator) | P3 |
| `cicd-argocd` | Legado | NAO -- 0 recursos | Remover NS | Remover NS |
| `platform-system` | Operator | SIM -- 2 pods platform-operator | Avaliar migracao ou excecao | P2 |
| `staging-platform-new-service` | Scaffold/Teste | SIM -- 1 pod new-service | Remover ou formalizar | P3 |

### Namespaces ja Conformes ADR-048

Todos os namespaces `staging-*` e `prod-*` ja seguem a convencao ADR-048.
Total: ~35 namespaces conformes.

---

## 3. Playbooks Detalhados por Migracao

---

### B-01: ESO -- `external-secrets-system` -> `external-secrets-system` (cleanup only)

**Estado atual:** Namespace `external-secrets-system` VAZIO (0 pods, 0 recursos ativos).
Workloads ESO ja rodam em `staging-security-externalsecrets` (TF module `external_secrets_staging`).

**Acao:** Remover namespace legado vazio. Nao ha workloads para migrar.

**Downtime estimado:** ZERO

#### Pre-checks

```bash
# 1. Confirmar namespace vazio
kubectl get all -n external-secrets-system
# Esperado: "No resources found"

# 2. Confirmar sem PVCs
kubectl get pvc -n external-secrets-system
# Esperado: "No resources found"

# 3. Confirmar sem secrets residuais
kubectl get secrets -n external-secrets-system --no-headers | wc -l
# Esperado: 0 ou 1 (default SA token)

# 4. Confirmar sem ExternalSecrets referenciando este namespace
kubectl get externalsecrets -A -o json | jq -r \
  '.items[] | select(.metadata.namespace == "external-secrets-system") | .metadata.name'
# Esperado: vazio

# 5. Confirmar sem ArgoCD Applications apontando para este namespace
kubectl get applications.argoproj.io -A -o json | jq -r \
  '.items[] | select(.spec.destination.namespace == "external-secrets-system") | .metadata.name'
# Esperado: vazio

# 6. Confirmar workloads ESO ativos no namespace correto
kubectl get pods -n staging-security-externalsecrets
# Esperado: external-secrets controller Running
```

#### Steps

```bash
# STEP 1: Criar Velero backup de seguranca (mesmo namespace vazio)
velero backup create pre-cleanup-eso-$(date +%Y%m%d) \
  --include-namespaces=external-secrets-system \
  --wait

# STEP 2: Deletar namespace legado
kubectl delete namespace external-secrets-system

# STEP 3: Verificar que ESO continua funcionando
kubectl get pods -n staging-security-externalsecrets
kubectl get clustersecretstore -o wide
# Esperado: vault-backend READY
```

#### Post-checks

```bash
# 1. Namespace nao existe mais
kubectl get namespace external-secrets-system 2>&1 | grep -q "not found" && echo "OK: removed"

# 2. ESO controller healthy
kubectl get pods -n staging-security-externalsecrets -o wide
# Esperado: Running, 0 restarts recentes

# 3. ExternalSecrets continuam sincronizando
kubectl get externalsecrets -A --no-headers | head -5
# Esperado: SecretSynced status

# 4. FinOps Lambda exclusion
# "external-secrets-system" permanece na EXCLUDED_NAMESPACES como dead entry (harmless).
# Remover na proxima sessao de cleanup se desejado.
```

#### Rollback

```bash
# Se necessario recriar o namespace (improvavel -- namespace vazio):
kubectl create namespace external-secrets-system
kubectl label namespace external-secrets-system \
  app.kubernetes.io/managed-by=terraform
```

#### IaC pendente

Nenhum. O TF module `external_secrets_staging` ja usa `namespace = "staging-security-externalsecrets"`.
O namespace `external-secrets-system` nao esta no TF state (criado manualmente no passado).

---

### B-02: Kyverno -- `kyverno` (inexistente) -> `staging-governance-kyverno` (ja migrado)

**Estado atual:** O namespace `kyverno` NAO EXISTE no cluster. Os workloads Kyverno
ja rodam em `staging-governance-kyverno` (TF: `helm_release.kyverno`, kyverno.tf L41).

**Acao:** Nenhuma migracao necessaria. O fix ja foi aplicado na Lambda:
- Python: `"staging-governance-kyverno"` substituiu `"kyverno"` nos 3 arquivos
- TF locals: `"staging-governance-kyverno"` substituiu `"kyverno"` em finops-automation-prod.tf

**Downtime estimado:** ZERO

#### Pre-checks

```bash
# 1. Confirmar namespace "kyverno" NAO existe
kubectl get namespace kyverno 2>&1 | grep -q "not found" && echo "OK: does not exist"

# 2. Confirmar workloads rodam no namespace correto
kubectl get pods -n staging-governance-kyverno
# Esperado: kyverno-new-admission-controller, kyverno-new-background-controller,
#           kyverno-new-cleanup-controller, kyverno-new-reports-controller — todos Running

# 3. Confirmar Kyverno webhooks ativos
kubectl get validatingwebhookconfigurations | grep kyverno
kubectl get mutatingwebhookconfigurations | grep kyverno
# Esperado: kyverno-resource-validating-webhook-cfg, etc.
```

#### Steps

Nenhuma acao no cluster. Fix aplicado apenas nos arquivos Lambda/TF:

```
# Ja aplicado 2026-03-27:
# 1. environments/prod/finops-automation-prod.tf L103-104:
#    "kyverno" -> "staging-governance-kyverno"
#
# 2. modules/finops-automation/lambda/lambda_start_prod.py L158-162:
#    "staging-governance-kyverno" (ja corrigido previamente)
#
# 3. modules/finops-automation/lambda/lambda_stop_prod.py L172-174:
#    "staging-governance-kyverno" (ja corrigido previamente)
```

#### Post-checks

```bash
# Confirmar apos terraform apply (prod):
# ENV var EXCLUDED_NAMESPACES da Lambda deve conter "staging-governance-kyverno"
# e NAO conter "kyverno"
aws lambda get-function-configuration \
  --function-name finops-scheduler-start-prod \
  --query 'Environment.Variables.EXCLUDED_NAMESPACES' --output text | tr ',' '\n' | grep kyverno
# Esperado: staging-governance-kyverno (sem "kyverno" isolado)

aws lambda get-function-configuration \
  --function-name finops-scheduler-stop-prod \
  --query 'Environment.Variables.EXCLUDED_NAMESPACES' --output text | tr ',' '\n' | grep kyverno
# Esperado: staging-governance-kyverno
```

#### Rollback

N/A -- nao ha mudanca no cluster, apenas nos fontes Lambda/TF. Reverter commits se necessario.

#### IaC pendente

- `terraform apply` em `environments/prod/` para que a Lambda receba a env var atualizada.
- Python defaults ja corrigidos (fallback caso env var nao esteja setada).

---

### B-03: cert-manager -- `cert-manager` (vazio) -> `staging-security-certmanager` (ja migrado)

**Estado atual:** O namespace `cert-manager` EXISTE mas esta VAZIO (0 pods).
Os workloads cert-manager ja rodam em `staging-security-certmanager` (3 pods: cainjector, controller, webhook).
O cert-manager NAO e gerenciado por Terraform nem ArgoCD (Helm install manual historico).

**Acao:** Remover namespace legado vazio + garantir Lambda exclui o namespace real.

**Downtime estimado:** ZERO

#### Pre-checks

```bash
# 1. Confirmar namespace cert-manager vazio
kubectl get all -n cert-manager
# Esperado: "No resources found"

# 2. Confirmar sem PVCs
kubectl get pvc -n cert-manager
# Esperado: "No resources found"

# 3. Confirmar sem CRDs orphaned apontando para cert-manager namespace
kubectl get certificates -A -o json | jq -r \
  '.items[] | select(.metadata.namespace == "cert-manager") | .metadata.name'
# Esperado: vazio

kubectl get issuers -n cert-manager 2>/dev/null
kubectl get clusterissuers 2>/dev/null
# Nota: ClusterIssuers sao cluster-scoped, nao perdem referencia com delete do namespace

# 4. Confirmar workloads ativos no namespace correto
kubectl get pods -n staging-security-certmanager
# Esperado: cert-manager, cert-manager-cainjector, cert-manager-webhook — todos Running

# 5. Confirmar sem ArgoCD Applications apontando para cert-manager
kubectl get applications.argoproj.io -A -o json | jq -r \
  '.items[] | select(.spec.destination.namespace == "cert-manager") | .metadata.name'
# Esperado: vazio

# 6. Verificar se Velero usa cert-manager como TEST_SOURCE_NAMESPACE
grep -r "cert-manager" /home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/kubectl-manifests/velero/
# ATENCAO: restore-testing-cronjob.yaml L119 usa cert-manager como TEST_SOURCE_NAMESPACE!
# Se namespace for deletado, atualizar para staging-security-certmanager antes.
```

#### Steps

```bash
# STEP 0: Atualizar Velero restore-testing se necessario
# Verificar se restore-testing-cronjob.yaml aponta para cert-manager:
kubectl get cronjob -n velero -o yaml | grep -A1 TEST_SOURCE_NAMESPACE
# Se sim, atualizar para staging-security-certmanager ANTES de deletar o namespace.

# STEP 1: Criar Velero backup de seguranca
velero backup create pre-cleanup-certmanager-$(date +%Y%m%d) \
  --include-namespaces=cert-manager \
  --wait

# STEP 2: Deletar namespace legado vazio
kubectl delete namespace cert-manager

# STEP 3: Validar cert-manager funcional
kubectl get pods -n staging-security-certmanager
# Esperado: 3 pods Running

# STEP 4: Testar emissao de certificado (dry run)
kubectl get certificates -A
# Verificar que certificados existentes continuam READY=True
```

#### Post-checks

```bash
# 1. Namespace cert-manager removido
kubectl get namespace cert-manager 2>&1 | grep -q "not found" && echo "OK: removed"

# 2. cert-manager pods healthy
kubectl get pods -n staging-security-certmanager -o wide
# Esperado: 3/3 Running, 0 restarts recentes

# 3. Certificates continuam validos
kubectl get certificates -A -o wide | head -10
# Esperado: READY=True em todos

# 4. ClusterIssuers intactos (cluster-scoped, nao afetados)
kubectl get clusterissuers -o wide

# 5. FinOps Lambda exclusion verificada
# "cert-manager" permanece na lista (dead entry, harmless)
# "staging-security-certmanager" adicionado (2026-03-27 fix)
```

#### Rollback

```bash
# Se necessario recriar namespace (improvavel -- vazio):
kubectl create namespace cert-manager
```

#### IaC pendente

1. **Velero restore-testing-cronjob.yaml** L119: atualizar `cert-manager` -> `staging-security-certmanager`
   Arquivo: `kubectl-manifests/velero/restore-testing-cronjob.yaml`

2. **ArgoCD AppProject platform.yaml** L41: atualizar `cert-manager` -> `staging-security-certmanager`
   Arquivo: `modules/argocd/projects/platform.yaml`

3. **Lambda env vars**: `terraform apply` em `environments/prod/` para propagar `staging-security-certmanager`
   para as Lambda env vars (TF locals ja corrigidos nesta sessao).

4. **Cleanup futuro**: remover `"cert-manager"` das EXCLUDED_NAMESPACES apos 30 dias
   (periodo de graca para confirmar que nenhum recurso residual reaparece).

---

## 4. Risco e Mitigacoes

| Risco | Impacto | Mitigacao |
|---|---|---|
| PVC com dados nao pode mover | Alto | Velero backup pre-migracao + snapshot EBS |
| ArgoCD sync quebra | Medio | Atualizar Application antes de deletar namespace |
| ExternalSecrets param | Medio | Recriar ESO no novo namespace antes de migrar pods |
| Kyverno bloqueia deploy | Baixo | PolicyException pre-criada no novo namespace |
| FinOps Lambda escala workload errado | Baixo | EXCLUDED_NAMESPACES atualizado ANTES da migracao |
| Velero restore-test falha | Baixo | Atualizar TEST_SOURCE_NAMESPACE antes de deletar cert-manager |

---

## 5. Namespaces que NAO Migram (Excecoes Aceitas)

- `kube-system`, `kube-public`, `kube-node-lease` -- Kubernetes core
- `calico-system`, `calico-apiserver` -- CNI (instalado via manifest, nao Helm)
- `linkerd`, `linkerd-cni`, `linkerd-viz` -- Service mesh (Helm chart define namespace)
- `default` -- Kubernetes core (deve permanecer vazio)
- `velero` -- Cluster-wide backup (chart define namespace)
- `rabbitmq-system` -- Operator CRD namespace (chart padrao)

Essas excecoes devem ser documentadas na Kyverno allowlist como `system-namespaces`.

---

## 6. Cronograma Sugerido

| Semana | Acao | Playbook |
|---|---|---|
| S1 | `terraform apply` prod (propagar Lambda env vars) | B-02 post-check |
| S1 | Remover `external-secrets-system` (vazio) | B-01 |
| S1 | Remover `cert-manager` (vazio) + atualizar Velero CronJob | B-03 |
| S1 | Remover `vault-system`, `cicd-argocd`, `ingress-nginx` (vazios) | N/A (simples delete) |
| S2 | Migrar `harbor-system` residual (PVCs criticos -- playbook separado) | Separado |
| S4 | Cleanup: remover `"cert-manager"` e `"external-secrets-system"` das EXCLUDED_NAMESPACES | Cleanup |
| S4 | Kyverno policy Audit -> Enforce | Separado |

---

## 7. Checklist Pre-Execucao

- [ ] Velero backup full cluster confirmado (schedule existente: daily-full + hourly-incremental)
- [ ] Verificar cada namespace legado com `kubectl get all`
- [ ] Confirmar novo namespace existe e workloads ativos
- [ ] ArgoCD Applications verificados (nenhum aponta para namespaces legados vazios)
- [x] FinOps Lambda EXCLUDED_NAMESPACES atualizado (2026-03-27 -- TF locals + Python defaults)
- [ ] Velero restore-testing-cronjob.yaml atualizado (cert-manager -> staging-security-certmanager)
- [ ] ArgoCD AppProject platform.yaml atualizado (cert-manager -> staging-security-certmanager)
- [ ] `terraform apply` prod executado (propagar env vars Lambda)
- [ ] Comunicar equipe sobre janela de cleanup

---

## 8. Resumo de Fixes Lambda (2026-03-27)

### Mismatch corrigidos

| String original | Namespace real | Match? | Fix |
|---|---|---|---|
| `"kyverno"` | `staging-governance-kyverno` | NUNCA (exact match falha) | Substituido em TF locals + Python defaults |
| `"cert-manager"` | `staging-security-certmanager` | Somente namespace vazio legado | Adicionado `staging-security-certmanager` (manter legado como guard) |
| `"external-secrets-system"` | `staging-security-externalsecrets` | Somente namespace vazio legado | OK por ora (cleanup S4) |

### Arquivos modificados

1. `environments/prod/finops-automation-prod.tf` -- TF locals (env var passada via EXCLUDED_NAMESPACES)
2. `modules/finops-automation/lambda/lambda_start_prod.py` -- Python fallback defaults
3. `modules/finops-automation/lambda/lambda_stop_prod.py` -- Python fallback defaults (ja estava correto)
