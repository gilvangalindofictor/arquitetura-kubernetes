# Playbook Deploy Backstage S6 — 2026-03-13

**Data:** 2026-03-13
**Sprint:** S6-A + S6-B + S6-C + S6-D
**Modo:** CONSULTIVO — comandos para aprovação e execução manual
**Cluster:** k8s-platform-prod (EKS us-east-1, conta 891377105802)
**Namespace:** staging-platform-backstage
**AWS Profile:** k8s-platform-prod

---

> ATENCAO — Este playbook contém comandos que modificam o cluster.
> Revisar cada fase antes de executar. Executar NA ORDEM especificada.
> Em caso de dúvida, parar e consultar a fase de Rollback.

---

## Status Pre-Deploy

| Item | Status | Acao |
|------|--------|------|
| Pod Backstage 2/2 Running (gen.53) | Verificar | Fase 1 |
| ExternalSecret backstage-secrets READY=True | Verificar | Fase 1 |
| Helm values atualizados (17 GAPs + BUG-001) | Pronto local | Fase 3 |
| ArgoCD Application `backstage` existente | Verificar | Fase 1 |
| ConfigMap `platform-manifest-schema` | Ausente no cluster | Fase 2 |
| Plugin `platform-scaffolder-actions` registrado | Nao registrado | Fase 6 |
| Templates S6-C/S6-D no GitLab | Nao publicados | Fase 4/5 |
| Vault policy `backstage-scaffolder` (GAP-SEC-S6-08) | Ausente | Fase 2 (Vault) |
| Ingress HTTPS/443 (GAP-SEC-S6-04) | Corrigido no values | Fase 3 |

---

## Fase 1 — Validacao de Estado do Cluster (pre-deploy)

**Pre-requisito:** Sessao AWS SSO ativa (`aws sts get-caller-identity --profile k8s-platform-prod`)
**Obrigatorio:** Sim — nao prosseguir se qualquer item falhar

### 1.1 — Verificar sessao AWS SSO

```bash
export AWS_PROFILE=k8s-platform-prod
aws sts get-caller-identity
```

**Criterio de validacao:** Retorna `"Account": "891377105802"` sem erro de credenciais.

### 1.2 — Atualizar kubeconfig

```bash
aws eks update-kubeconfig \
  --name k8s-platform-prod \
  --region us-east-1 \
  --profile k8s-platform-prod
```

**Criterio de validacao:** `kubectl config current-context` aponta para o cluster EKS correto.

### 1.3 — Verificar pod Backstage

```bash
kubectl get pods -n staging-platform-backstage -l app.kubernetes.io/name=backstage
```

**Criterio de validacao:** STATUS=Running, READY=2/2. Se Running 1/2, verificar sidecar Linkerd.

### 1.4 — Verificar helm release

```bash
helm list -n staging-platform-backstage
```

**Criterio de validacao:** Release `backstage` presente, CHART=`backstage-2.6.3`, STATUS=`deployed`.

### 1.5 — Verificar ExternalSecret

```bash
kubectl get externalsecret backstage-secrets -n staging-platform-backstage -o wide
```

**Criterio de validacao:** READY=True, STATUS=SecretSynced. Se False, ver `kubectl describe externalsecret backstage-secrets -n staging-platform-backstage`.

### 1.6 — Verificar ConfigMap CA interna (pre-requisito do helm upgrade)

```bash
kubectl get configmap staging-internal-ca -n staging-platform-backstage
```

**Criterio de validacao:** ConfigMap existe. Se ausente, o helm upgrade falhara ao montar o volume — PARAR e criar o ConfigMap antes de continuar.

### 1.7 — Verificar Vault paths (os 9 paths do ExternalSecret)

```bash
kubectl exec -n staging-security-vault vault-0 -- \
  vault kv list secret/staging/backstage
```

**Criterio de validacao:** Lista retorna: `database`, `keycloak`, `gitlab`, `vault`, `argocd`, `sonarqube`, `eks`, `session`, `harbor`.

### 1.8 — Verificar pod sem init container (BUG-001 diagnostico pre-upgrade)

```bash
kubectl describe pod -n staging-platform-backstage -l app.kubernetes.io/name=backstage \
  | grep -A 5 "Init Containers:"
```

**Criterio de validacao:** Espera-se que o pod atual (gen.53) ainda tenha init container (estado antigo). Apos o upgrade (Fase 3), o init container deve sumir — `Init Containers: <none>`.

### 1.9 — Verificar CVE-2025-55285 (GAP-SEC-S6-10)

```bash
kubectl exec -n staging-platform-backstage \
  $(kubectl get pod -n staging-platform-backstage -l app.kubernetes.io/name=backstage -o jsonpath='{.items[0].metadata.name}') \
  -- npm list @backstage/plugin-scaffolder-backend 2>/dev/null | grep scaffolder-backend
```

**Criterio de validacao:** Versao deve ser >= 2.1.1 (idealmente 3.1.3 conforme ADR-055). Se < 2.1.1, registrar como bloqueador P0 antes de prosseguir.

### 1.10 — Verificar ArgoCD Application

```bash
kubectl get application backstage -n staging-platform-argocd
```

**Criterio de validacao:** STATUS=Synced, HEALTH=Healthy. Se OutOfSync, o ArgoCD pode reverter mudancas manuais — avaliar se o upgrade sera feito via ArgoCD (recomendado) ou helm direto.

---

**GATE Fase 1:** Todos os itens 1.3, 1.4, 1.5, 1.6 devem estar OK para prosseguir.

---

## Fase 2 — Criar Recursos Pre-Helm no Cluster

**Pre-requisito:** Fase 1 completa, todos os gates OK.
**Obrigatorio:** Sim — o helm-values-staging.yaml referencia estes ConfigMaps como extraVolumes; se ausentes, os pods nao sobem.

### 2.1 — Criar ConfigMap `platform-manifest-schema` (GAP-S6C-01)

Este ConfigMap monta o JSON Schema da plataforma no container em `/app/schemas/v1/manifest-schema.json`.
O schema esta em `domains/platform-core/app-provisioning/schemas/v1/manifest-schema.json`.

**Dry-run primeiro (obrigatorio):**

```bash
# Executar a partir da raiz do repositorio Arquitetura/Kubernetes
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes

kubectl create configmap platform-manifest-schema \
  --from-file=manifest-schema.json=domains/platform-core/app-provisioning/schemas/v1/manifest-schema.json \
  -n staging-platform-backstage \
  --dry-run=client -o yaml
```

**Verificar output:** O YAML exibido deve conter `data.manifest-schema.json` com o conteudo do schema JSON. Se o path do arquivo retornar erro, verificar se o arquivo existe localmente.

**Aplicar (apos dry-run passar):**

```bash
kubectl create configmap platform-manifest-schema \
  --from-file=manifest-schema.json=domains/platform-core/app-provisioning/schemas/v1/manifest-schema.json \
  -n staging-platform-backstage
```

**Criterio de validacao:**

```bash
kubectl get configmap platform-manifest-schema -n staging-platform-backstage
kubectl describe configmap platform-manifest-schema -n staging-platform-backstage | head -20
```

Esperado: ConfigMap presente, `Data: manifest-schema.json`.

### 2.2 — Criar Vault policy `backstage-scaffolder` (GAP-SEC-S6-08)

O AppRole `app-template` precisa de uma policy dedicada para operacoes de scaffolder. Sem ela, o Scaffolder nao consegue criar novos AppRoles para servicos scaffoldados.

```bash
kubectl exec -n staging-security-vault vault-0 -- vault policy write backstage-scaffolder - <<'EOF'
# Policy backstage-scaffolder — S6-C
# Permite que o Backstage Scaffolder gerencie AppRoles e secrets de novos servicos

path "auth/approle/role/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/data/staging/*" {
  capabilities = ["create", "read", "update", "list"]
}

path "secret/metadata/staging/*" {
  capabilities = ["list", "read"]
}
EOF
```

**Atualizar role `app-template` com secret_id_num_uses e a nova policy:**

```bash
kubectl exec -n staging-security-vault vault-0 -- \
  vault write auth/approle/role/app-template \
    secret_id_ttl=24h \
    token_ttl=1h \
    token_max_ttl=4h \
    token_policies="default,backstage-scaffolder" \
    bind_secret_id=true \
    secret_id_num_uses=5
```

**Criterio de validacao:**

```bash
kubectl exec -n staging-security-vault vault-0 -- \
  vault policy list | grep backstage-scaffolder

kubectl exec -n staging-security-vault vault-0 -- \
  vault read auth/approle/role/app-template
```

Esperado: policy `backstage-scaffolder` listada; role `app-template` com `secret_id_num_uses=5`.

---

**GATE Fase 2:** ConfigMap `platform-manifest-schema` criado (item 2.1 obrigatorio). Item 2.2 recomendado antes do Fase 6.

---

## Fase 3 — Helm Upgrade (S6-A + S6-B + S6-C + S6-D + BUG-001)

**Pre-requisito:** Fases 1 e 2 completas.
**Obrigatorio:** Sim — esta fase aplica todos os 17 GAPs S6-A, config Scaffolder S6-C, HTTPS S6-B/GAP-SEC-S6-04 e fix BUG-001 (init container).

**AVISO:** O `argocd-application.yaml` atual (arquivo local) ainda contem o init container `install-oidc` com a versao antiga do Harbor proxy. O `helm-values-staging.yaml` ja contem `initContainers: []` (BUG-001 fix). Existem duas abordagens:

**Opcao A (recomendada) — Helm upgrade direto com desativacao temporaria do ArgoCD selfHeal:**

```bash
# Passo 1: Pausar selfHeal no ArgoCD para evitar rollback imediato
kubectl patch application backstage \
  -n staging-platform-argocd \
  --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":false}}}}'
```

**Passo 2: Dry-run obrigatorio antes de aplicar:**

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes

helm upgrade backstage backstage/backstage \
  -n staging-platform-backstage \
  -f docs/plan/backstage/helm-values-staging.yaml \
  --dry-run 2>&1 | head -100
```

**Criterio do dry-run:** Saida deve mostrar o diff do Deployment sem erros de validacao. Verificar especialmente:
- `initContainers: []` presente (BUG-001 fix)
- `replicas: 2` presente (GAP-S6A-01)
- `extraVolumes` inclui `platform-manifest-schema` e `staging-internal-ca`
- `ingress.annotations` inclui `alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'`

**Passo 3: Aplicar o upgrade (apos dry-run passar):**

```bash
helm upgrade backstage backstage/backstage \
  -n staging-platform-backstage \
  -f docs/plan/backstage/helm-values-staging.yaml \
  --wait \
  --timeout 5m \
  --atomic
```

Flag `--atomic`: reverte automaticamente se o rollout falhar dentro do timeout.

**Criterio de validacao imediato:**

```bash
# Verificar rollout
kubectl rollout status deployment/backstage -n staging-platform-backstage --timeout=5m

# Verificar pod sem init container (BUG-001 confirmacao)
kubectl describe pod -n staging-platform-backstage \
  $(kubectl get pod -n staging-platform-backstage -l app.kubernetes.io/name=backstage \
    -o jsonpath='{.items[0].metadata.name}') \
  | grep -A 3 "Init Containers:"

# Verificar replicas
kubectl get deployment backstage -n staging-platform-backstage

# Verificar volume mount do schema
kubectl describe pod -n staging-platform-backstage \
  $(kubectl get pod -n staging-platform-backstage -l app.kubernetes.io/name=backstage \
    -o jsonpath='{.items[0].metadata.name}') \
  | grep -A 5 "Mounts:"
```

**Criterios esperados:**
- `kubectl rollout status` retorna `successfully rolled out`
- `Init Containers:` ausente ou vazio no describe do pod
- `READY=2/2` em `kubectl get deployment`
- `/app/schemas/v1` listado nos volume mounts

**Passo 4: Reativar selfHeal no ArgoCD:**

```bash
kubectl patch application backstage \
  -n staging-platform-argocd \
  --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":true}}}}'
```

**NOTA para sincronizacao ArgoCD de longo prazo:** O `argocd-application.yaml` local precisa ser atualizado para refletir o novo estado (initContainers vazio, novos volumes, HTTPS). Isso evita que o ArgoCD reverta o upgrade. Ver item opcional no final desta fase.

**Opcao B (alternativa) — Atualizar ArgoCD Application com novo values inline:**
Editar `docs/plan/backstage/argocd-application.yaml` para incorporar os novos values do `helm-values-staging.yaml` e aplicar via `kubectl apply`. Mais trabalho de merge, mas garante GitOps consistente. Recomendado como segundo passo apos validar a Opcao A.

---

**GATE Fase 3:** `kubectl rollout status deployment/backstage -n staging-platform-backstage` retorna `successfully rolled out` e pod esta Running 2/2 sem init container.

---

## Fase 4 — Publicar Catalog Entities no GitLab (GAP-S6C-03 parcial)

**Pre-requisito:** Fase 1 completa. GitLab `platform/backstage-catalog` (ID=7) acessivel.
**Obrigatorio:** Sim — sem as entidades no GitLab, o Backstage Catalog fica vazio.

Os 4 arquivos de catalog estao prontos localmente em `docs/plan/backstage/catalog/`.

### 4.1 — Clonar repositorio backstage-catalog

```bash
cd /tmp
git clone http://gitlab.staging.internal/platform/backstage-catalog.git
cd backstage-catalog
```

**Criterio de validacao:** Repositorio clonado com sucesso. `git log --oneline -5` mostra os 3 commits iniciais (criados em 2026-03-12).

### 4.2 — Criar estrutura de diretorios

```bash
mkdir -p entities/domains
mkdir -p entities/systems/data
mkdir -p ETL/Hatch
```

### 4.3 — Copiar arquivos de catalog

```bash
REPO_LOCAL="/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/plan/backstage/catalog"

# Arquivo raiz — Location entity
cp "${REPO_LOCAL}/catalog-info.yaml" ./catalog-info.yaml

# 5 Domain entities (platform, integration, data, operations, shared-services)
cp "${REPO_LOCAL}/entities/domains/catalog-info.yaml" ./entities/domains/catalog-info.yaml

# System entity data-hatch-etl + links S6-D
cp "${REPO_LOCAL}/entities/systems/data/catalog-info.yaml" ./entities/systems/data/catalog-info.yaml

# 8 Component entities ETL/Hatch + links S6-D (Grafana, ArgoCD, Vault)
cp "${REPO_LOCAL}/ETL/Hatch/catalog-info.yaml" ./ETL/Hatch/catalog-info.yaml
```

### 4.4 — Verificar estrutura antes do commit

```bash
find . -name "catalog-info.yaml" | sort
```

**Esperado:**
```
./catalog-info.yaml
./ETL/Hatch/catalog-info.yaml
./entities/domains/catalog-info.yaml
./entities/systems/data/catalog-info.yaml
```

### 4.5 — Criar branch, commitar e abrir MR

```bash
git checkout -b feat/s6-catalog-entities

git add catalog-info.yaml \
  entities/domains/catalog-info.yaml \
  entities/systems/data/catalog-info.yaml \
  ETL/Hatch/catalog-info.yaml

git commit -m "feat: adicionar catalog entities S6-A+S6-D (domains, systems, ETL/Hatch components + observability links)"

git push origin feat/s6-catalog-entities
```

**Abrir MR via GitLab API (ou UI):**

```bash
# Via curl (ajustar TOKEN conforme secret/staging/backstage/gitlab)
GITLAB_TOKEN="<valor de secret/staging/backstage/gitlab>"

curl -s -X POST \
  "http://gitlab.staging.internal/api/v4/projects/7/merge_requests" \
  -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "source_branch": "feat/s6-catalog-entities",
    "target_branch": "main",
    "title": "feat: catalog entities S6-A+S6-D — domains, systems, ETL/Hatch + observability links",
    "description": "Adiciona 4 arquivos catalog-info.yaml:\n- Location entity raiz\n- 5 Domain entities\n- System data-hatch-etl\n- 8 Component entities ETL/Hatch com links S6-D (Grafana, ArgoCD, Vault)\n\nSprint S6-A + S6-D | ADR-055, ADR-102",
    "remove_source_branch": true,
    "squash": false
  }' | python3 -m json.tool | grep '"web_url"'
```

**Criterio de validacao:** MR criado com sucesso. URL do MR retornada pelo curl.

### 4.6 — Fazer merge do MR (apos revisao)

Apos aprovacao no GitLab UI ou via API:

```bash
# Substituir <MR_IID> pelo numero do MR retornado
MR_IID="<numero_do_mr>"

curl -s -X PUT \
  "http://gitlab.staging.internal/api/v4/projects/7/merge_requests/${MR_IID}/merge" \
  -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"merge_commit_message": "feat: catalog entities S6-A+S6-D merged"}' \
  | python3 -m json.tool | grep '"state"'
```

**Criterio de validacao:** `"state": "merged"` na resposta.

### 4.7 — Verificar descoberta no Backstage (aguardar ate 30 min ou forcando refresh)

```bash
# Obter token de acesso Backstage via Keycloak (ou usar token de service account)
# Verificar via API REST do Backstage
curl -sk -H "Authorization: Bearer <backstage-token>" \
  "https://backstage.staging.internal/api/catalog/entities?filter=kind=Domain" \
  | python3 -m json.tool | grep '"name"'
```

**Criterio de validacao:** 5 dominios listados (platform, integration, data, operations, shared-services).

Para forccar re-descoberta imediata sem aguardar o schedule de 30min:

```bash
# Trigger manual do GitLab EntityProvider (via UI Backstage: Settings > Catalog > Refresh)
# Ou via API:
curl -sk -X POST \
  -H "Authorization: Bearer <backstage-token>" \
  "https://backstage.staging.internal/api/catalog/refresh" \
  -H "Content-Type: application/json" \
  -d '{"entityRef": "location:default/platform-catalog"}'
```

---

**GATE Fase 4:** 4 arquivos commitados e mergeados no branch `main` do repo `platform/backstage-catalog`.

---

## Fase 5 — Publicar Templates S6-B e S6-C no GitLab

**Pre-requisito:** Fase 4 completa (catalog-info.yaml raiz ja referencia `./templates/catalog-info.yaml`).
**Obrigatorio:** Sim — sem os templates no GitLab, o Backstage Scaffolder nao os exibe.

Os 3 templates estao em `docs/plan/backstage/templates/`. Ha uma referencia no catalog-info.yaml raiz para `./templates/catalog-info.yaml` — este arquivo ainda precisa ser criado como um Location entity para os templates.

### 5.1 — Criar arquivo Location para templates

```bash
# Ainda dentro de /tmp/backstage-catalog (ou clonar novamente)
cd /tmp/backstage-catalog
git checkout main
git pull origin main
git checkout -b feat/s6-templates

mkdir -p templates/new-service/skeleton/.platform
mkdir -p templates/etl-service/skeleton/.platform
mkdir -p templates/api-service/skeleton/.platform
```

### 5.2 — Criar catalog-info.yaml de templates (Location entity)

```bash
cat > templates/catalog-info.yaml << 'EOF'
# =============================================================================
# templates/catalog-info.yaml — Location entity para todos os templates S6-B/S6-C
# Sprint S6-B + S6-C | ADR-055, ADR-102
# =============================================================================
apiVersion: backstage.io/v1alpha1
kind: Location
metadata:
  name: platform-templates
  description: "Templates Golden Path da plataforma — new-service, etl-service, api-service"
  annotations:
    backstage.io/managed-by-location: "url:https://gitlab.staging.internal/platform/backstage-catalog/-/raw/main/templates/catalog-info.yaml"
spec:
  targets:
    - ./new-service/template.yaml
    - ./etl-service/template.yaml
    - ./api-service/template.yaml
EOF
```

### 5.3 — Copiar templates

```bash
TEMPLATES_LOCAL="/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/plan/backstage/templates"

# Template generico (new-service) — S6-B + S6-C MR automatico
cp "${TEMPLATES_LOCAL}/new-service/template.yaml" ./templates/new-service/template.yaml

# Template ETL/Worker especializado — S6-B + S6-C
cp "${TEMPLATES_LOCAL}/etl-service/template.yaml" ./templates/etl-service/template.yaml

# Template API REST especializado — S6-B + S6-C
cp "${TEMPLATES_LOCAL}/api-service/template.yaml" ./templates/api-service/template.yaml
```

**NOTA sobre skeletons:** Os templates referenciam `./skeleton` como `url: ./skeleton`. Os diretorio skeleton (com os arquivos `.platform/manifest.yaml.njk`, `catalog-info.yaml.njk`, etc.) precisam existir junto aos templates. Se os skeletons estiverem disponiveis localmente em `docs/plan/backstage/templates/*/skeleton/`, copiá-los tambem. Se nao existirem, criar os arquivos skeleton minimos antes de publicar (ver nota abaixo).

```bash
# Verificar se skeletons existem localmente
ls /home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/plan/backstage/templates/new-service/skeleton/ 2>/dev/null || echo "SKELETON AUSENTE — criar antes de publicar"
ls /home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/plan/backstage/templates/etl-service/skeleton/ 2>/dev/null || echo "SKELETON AUSENTE — criar antes de publicar"
ls /home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/plan/backstage/templates/api-service/skeleton/ 2>/dev/null || echo "SKELETON AUSENTE — criar antes de publicar"
```

Se os skeletons existirem:

```bash
cp -r "${TEMPLATES_LOCAL}/new-service/skeleton/" ./templates/new-service/skeleton/
cp -r "${TEMPLATES_LOCAL}/etl-service/skeleton/" ./templates/etl-service/skeleton/
cp -r "${TEMPLATES_LOCAL}/api-service/skeleton/" ./templates/api-service/skeleton/
```

### 5.4 — Commitar e abrir MR

```bash
git add templates/

git commit -m "feat: adicionar templates S6-B+S6-C (new-service, etl-service, api-service com MR automatico)"

git push origin feat/s6-templates
```

**Abrir MR:**

```bash
curl -s -X POST \
  "http://gitlab.staging.internal/api/v4/projects/7/merge_requests" \
  -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "source_branch": "feat/s6-templates",
    "target_branch": "main",
    "title": "feat: templates Golden Path S6-B+S6-C — new-service, etl-service, api-service",
    "description": "Adiciona 3 templates Backstage Scaffolder com suporte a MR automatico (S6-C):\n- new-service-template: generico, suporta api/worker/etl\n- etl-service-template: especializado ETL/Worker/CronJob\n- api-service-template: especializado API REST com Ingress+HPA\n\nTodos com step platform:manifest:validate + publish:gitlab com branchName=scaffold/<name>\n\nSprint S6-B + S6-C | ADR-055, ADR-102",
    "remove_source_branch": true,
    "squash": false
  }' | python3 -m json.tool | grep '"web_url"'
```

**Criterio de validacao:**

```bash
# Apos merge, verificar templates no Backstage:
curl -sk -H "Authorization: Bearer <backstage-token>" \
  "https://backstage.staging.internal/api/catalog/entities?filter=kind=Template" \
  | python3 -m json.tool | grep '"name"'
```

**Esperado:** 3 templates listados: `new-service-template`, `etl-service-template`, `api-service-template`.

---

**GATE Fase 5:** 3 templates commitados e mergeados em `main`. Templates visiveis no Backstage Catalog via API ou UI (`/create`).

---

## Fase 6 — Registrar Plugin platform-scaffolder-actions (GAP-S6C-02)

**Pre-requisito:** Fase 3 completa (Backstage rodando com nova imagem). Acesso ao codigo-fonte do Backstage.
**Obrigatorio:** Sim — sem o plugin, a action `platform:manifest:validate` usada nos 3 templates vai falhar com erro "Action not found".

**STATUS GAP-S6C-02 (2026-03-15):** ARTEFATOS PRONTOS LOCALMENTE.
- `packages/backend/src/index.ts` ja contem o registro correto do plugin.
- `packages/backend/package.json` ja contem a dependencia `link:`.
- Plugin fonte em `docs/plan/backstage/plugins/platform-scaffolder-actions/`.
- Aguarda execucao pos-AWS-recovery para clone do repo GitLab + rebuild da imagem.

Referencia completa: `docs/plan/backstage/plugins/platform-scaffolder-actions/REGISTRATION-GUIDE.md`

Esta fase requer modificacao no codigo-fonte do Backstage e rebuild da imagem Docker. Nao e possivel fazer apenas via Helm sem rebuild.

### 6.1 — Clonar o repositorio do Backstage

```bash
git clone http://gitlab.staging.internal/platform/backstage.git /tmp/backstage-app
cd /tmp/backstage-app
```

### 6.2 — Copiar o plugin para o workspace

```bash
mkdir -p plugins/platform-scaffolder-actions

cp -r /home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/plan/backstage/plugins/platform-scaffolder-actions/. \
  ./plugins/platform-scaffolder-actions/
```

### 6.3 — Aplicar packages/backend/package.json

Copiar o arquivo ja preparado localmente (ja contem a dependencia `link:` do plugin):

```bash
cp /home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/plan/backstage/docker/packages/backend/package.json \
  ./packages/backend/package.json
```

Verificar que a linha abaixo esta presente na secao `dependencies`:

```json
"@internal/plugin-platform-scaffolder-actions": "link:../../../plugins/platform-scaffolder-actions"
```

NOTA: O path `link:` no arquivo local aponta para `../../../plugins/...` (estrutura do subdiretorio
`docker/`). Ao copiar para o repositorio real do Backstage (estrutura padrao monorepo), ajustar para:

```json
"@internal/plugin-platform-scaffolder-actions": "link:../../plugins/platform-scaffolder-actions"
```

### 6.4 — Aplicar packages/backend/src/index.ts

Copiar o arquivo ja preparado localmente (ja contem o registro completo do GAP-S6C-02):

```bash
cp /home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/plan/backstage/docker/packages/backend/src/index.ts \
  ./packages/backend/src/index.ts
```

O arquivo ja contem:
- `import { createValidateManifestAction } from '@internal/plugin-platform-scaffolder-actions'`
- `import { scaffolderActionsExtensionPoint } from '@backstage/plugin-scaffolder-node/alpha'`
- `import { createBackendModule } from '@backstage/backend-plugin-api'`
- `const platformScaffolderActionsModule = createBackendModule({ pluginId: 'scaffolder', moduleId: 'platform-actions', ... })`
- `backend.add(import('@backstage/plugin-scaffolder-backend'))`
- `backend.add(import('@backstage/plugin-scaffolder-backend-module-gitlab'))`
- `backend.add(platformScaffolderActionsModule)`

Verificar apos copiar:

```bash
grep -n "platform-scaffolder\|platform-actions\|platformScaffolderActionsModule" \
  packages/backend/src/index.ts
```

Saida esperada: 4 linhas (import, const declaration, comment, backend.add).

### 6.5 — Instalar dependencias

```bash
yarn install
```

### 6.6 — Build do backend

```bash
yarn workspace @backstage/backend build
```

**Criterio de validacao:** Build conclui sem erros TypeScript. Se houver erros de tipo
relacionados ao `scaffolderActionsExtensionPoint`, verificar versao do
`@backstage/plugin-scaffolder-node` (deve ser `0.7.1` conforme package.json do plugin).

---

**GATE Fase 6:** `yarn workspace @backstage/backend build` conclui sem erros. Verificar que `dist/index.cjs.js` foi gerado.

---

## Fase 7 — Rebuild e Redeploy da Imagem Backstage

**Pre-requisito:** Fase 6 completa (build passou sem erros). Harbor `harbor.staging.internal` acessivel.
**Obrigatorio:** Sim — o plugin precisa estar compilado na imagem Docker para o container carregar.

### 7.1 — Autenticar no Harbor

```bash
docker login harbor.staging.internal \
  -u robot\$backstage-puller \
  -p <HARBOR_ROBOT_TOKEN>
```

O token esta em `secret/staging/backstage/harbor` no Vault:

```bash
kubectl exec -n staging-security-vault vault-0 -- \
  vault kv get -field=robot-token secret/staging/backstage/harbor
```

### 7.2 — Definir nova tag da imagem

```bash
NEW_TAG="1.48.0-s6c-$(date +%Y%m%d%H%M)"
echo "Nova tag: ${NEW_TAG}"
```

### 7.3 — Build da imagem Docker

```bash
cd /tmp/backstage-app

# Build multi-stage conforme Dockerfile existente no repositorio
# Substituir pelo Dockerfile real do projeto
docker build \
  -t harbor.staging.internal/platform/backstage:${NEW_TAG} \
  -t harbor.staging.internal/platform/backstage:latest-s6c \
  --build-arg NODE_ENV=production \
  .
```

**Criterio de validacao:** Build conclui sem erros. Verificar que a imagem tem o plugin:

```bash
docker run --rm harbor.staging.internal/platform/backstage:${NEW_TAG} \
  npm list @internal/plugin-platform-scaffolder-actions 2>/dev/null | grep platform-scaffolder
```

### 7.4 — Push da imagem para Harbor

```bash
docker push harbor.staging.internal/platform/backstage:${NEW_TAG}
docker push harbor.staging.internal/platform/backstage:latest-s6c
```

**Criterio de validacao:** Push bem-sucedido. Verificar na UI do Harbor: `harbor.staging.internal/platform/backstage` — tag `${NEW_TAG}` presente.

### 7.5 — Atualizar a tag da imagem no helm-values-staging.yaml

Editar `/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/plan/backstage/helm-values-staging.yaml`:

Alterar:
```yaml
    tag: "1.48.0-oidc"
```

Para:
```yaml
    tag: "<NEW_TAG>"  # ex: "1.48.0-s6c-202603131500"
```

### 7.6 — Helm upgrade com nova imagem

```bash
# Dry-run
helm upgrade backstage backstage/backstage \
  -n staging-platform-backstage \
  -f /home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/plan/backstage/helm-values-staging.yaml \
  --dry-run 2>&1 | grep -A 2 "image:"

# Aplicar
helm upgrade backstage backstage/backstage \
  -n staging-platform-backstage \
  -f /home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/plan/backstage/helm-values-staging.yaml \
  --wait \
  --timeout 5m \
  --atomic
```

### 7.7 — Verificar novo pod rodando com a imagem correta

```bash
kubectl get pods -n staging-platform-backstage -l app.kubernetes.io/name=backstage -o wide

kubectl describe pod -n staging-platform-backstage \
  $(kubectl get pod -n staging-platform-backstage -l app.kubernetes.io/name=backstage \
    -o jsonpath='{.items[0].metadata.name}') \
  | grep "Image:"
```

**Criterio de validacao:** `Image:` mostra `harbor.staging.internal/platform/backstage:<NEW_TAG>`.

---

**GATE Fase 7:** Pod Running 2/2 com nova tag de imagem. `kubectl rollout status deployment/backstage -n staging-platform-backstage` retorna `successfully rolled out`.

---

## Fase 8 — Verificacao Final

**Pre-requisito:** Fases 1-7 completas.
**Obrigatorio:** Sim — validar o estado final do deploy antes de declarar S6 concluido em producao.

### 8.1 — Verificar pod e rollout

```bash
kubectl rollout status deployment/backstage -n staging-platform-backstage

kubectl get pods -n staging-platform-backstage -o wide
```

**Esperado:** 2 pods Running 2/2 (container backstage + sidecar linkerd-proxy), sem fase Init.

### 8.2 — Verificar ConfigMap montado no pod

```bash
kubectl exec -n staging-platform-backstage \
  $(kubectl get pod -n staging-platform-backstage -l app.kubernetes.io/name=backstage \
    -o jsonpath='{.items[0].metadata.name}') \
  -- ls -la /app/schemas/v1/
```

**Esperado:** `manifest-schema.json` presente no diretorio `/app/schemas/v1/`.

### 8.3 — Verificar variavel de ambiente PLATFORM_SCHEMA_PATH

```bash
kubectl exec -n staging-platform-backstage \
  $(kubectl get pod -n staging-platform-backstage -l app.kubernetes.io/name=backstage \
    -o jsonpath='{.items[0].metadata.name}') \
  -- env | grep PLATFORM_SCHEMA_PATH
```

**Esperado:** `PLATFORM_SCHEMA_PATH=/app/schemas/v1/manifest-schema.json`

### 8.4 — Verificar Ingress HTTPS (GAP-SEC-S6-04)

```bash
kubectl get ingress -n staging-platform-backstage -o yaml | grep -A 10 "listen-ports"
```

**Esperado:** `listen-ports: '[{"HTTP":80},{"HTTPS":443}]'` e `ssl-redirect: "443"`.

```bash
# Verificar conectividade HTTPS
curl -sk -o /dev/null -w "%{http_code}" https://backstage.staging.internal/healthcheck
```

**Esperado:** `200` ou `301` (redirect). Se `000`, verificar DNS e ALB.

### 8.5 — Verificar autenticacao Backstage

Acessar via navegador (ou curl com cookie):

```bash
curl -sk -L -o /dev/null -w "%{http_code}\n%{url_effective}\n" \
  https://backstage.staging.internal/
```

**Esperado:** Redirect para Keycloak (`http_code=302` para `https://backstage.staging.internal`) — confirma que OIDC esta ativo.

### 8.6 — Verificar Backstage API e Catalog (autenticado)

Para obter um token de acesso, fazer login no Backstage UI e extrair o token Bearer do localStorage/cookie. Alternativamente, usar um service account Keycloak:

```bash
# Obter token via client_credentials do Keycloak (para testes)
KEYCLOAK_TOKEN=$(curl -sk -X POST \
  "http://keycloak-keycloakx-http.staging-platform-keycloak.svc.cluster.local/auth/realms/platform/protocol/openid-connect/token" \
  -d "grant_type=client_credentials" \
  -d "client_id=backstage" \
  -d "client_secret=<KEYCLOAK_CLIENT_SECRET>" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# Verificar entidades no catalog
curl -sk -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" \
  "https://backstage.staging.internal/api/catalog/entities?filter=kind=Domain" \
  | python3 -m json.tool | grep '"name"'

curl -sk -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" \
  "https://backstage.staging.internal/api/catalog/entities?filter=kind=Template" \
  | python3 -m json.tool | grep '"name"'

curl -sk -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" \
  "https://backstage.staging.internal/api/catalog/entities?filter=kind=Component,metadata.annotations.backstage.io/kubernetes-id=hatch-etl" \
  | python3 -m json.tool | grep '"name"'
```

**Esperado:**
- 5 dominios: platform, integration, data, operations, shared-services
- 3 templates: new-service-template, etl-service-template, api-service-template
- 8 componentes ETL/Hatch: hatch-api-gateway, hatch-worker, hatch-etl-core, hatch-data-processor, hatch-scheduler, hatch-dashboard, hatch-cronjob-etl-extraction, hatch-migration-runner

### 8.7 — Verificar plugin platform:manifest:validate registrado

```bash
curl -sk -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" \
  "https://backstage.staging.internal/api/scaffolder/v2/actions" \
  | python3 -m json.tool | grep '"id"' | grep platform
```

**Esperado:** `"id": "platform:manifest:validate"` na lista de actions.

### 8.8 — Verificar logs do pod por erros criticos

```bash
kubectl logs -n staging-platform-backstage \
  $(kubectl get pod -n staging-platform-backstage -l app.kubernetes.io/name=backstage \
    -o jsonpath='{.items[0].metadata.name}') \
  --container backstage \
  --tail=100 \
  | grep -E "(ERROR|WARN|error|warn)" \
  | grep -v "Expected" \
  | head -30
```

**Criterio de validacao:** Sem erros criticos de inicializacao (erros de conexao com Keycloak/GitLab durante startup sao normais — o Backstage faz retry).

### 8.9 — Verificar ArgoCD Application em estado Synced

```bash
kubectl get application backstage -n staging-platform-argocd -o wide
```

**Esperado:** SYNC STATUS=Synced, HEALTH STATUS=Healthy. Se OutOfSync, o ArgoCD divergiu dos values aplicados — atualizar o `argocd-application.yaml` (ver secao Pos-Deploy).

---

**GATE Fase 8 (Definition of Done S6):**

| Criterio | Status |
|----------|--------|
| Pod 2/2 Running sem init container | Verificar |
| ConfigMap manifest-schema montado em /app/schemas/v1 | Verificar |
| Ingress HTTPS:443 respondendo 200/301 | Verificar |
| 5 Domains no Catalog | Verificar |
| 3 Templates visiveis em /create | Verificar |
| 8 Components ETL/Hatch com links Grafana/ArgoCD/Vault | Verificar |
| Action platform:manifest:validate registrada | Verificar |
| Sem erros criticos nos logs | Verificar |

---

## Estimativa de Tempo Total

| Fase | Descricao | Tempo Estimado | Observacao |
|------|-----------|---------------|------------|
| 1 | Validacao estado cluster | 10 min | Apenas kubectl read-only |
| 2 | Criar ConfigMap + Vault policy | 10 min | 2 comandos simples |
| 3 | Helm upgrade (dry-run + apply) | 15 min | --wait --timeout 5m |
| 4 | Publicar catalog entities no GitLab | 15 min | git + MR + merge |
| 5 | Publicar templates no GitLab | 20 min | Verificar skeletons primeiro |
| 6 | Registrar plugin (modificar index.ts) | 30 min | Depende do acesso ao codigo-fonte |
| 7 | Rebuild imagem + push + redeploy | 30-60 min | Depende do tempo de build Docker |
| 8 | Verificacao final | 15 min | curl + kubectl checks |
| **TOTAL** | | **~2h a 2h45min** | Sem blockers |

**Caminhos criticos:**
- Fase 7 (rebuild imagem) e a mais longa e tem mais dependencias externas.
- Se o codigo-fonte do Backstage nao estiver acessivel ou o Dockerfile nao estiver pronto, Fase 6+7 podem atrasar.
- Fases 3, 4 e 5 podem ser executadas em paralelo por operadores diferentes.

---

## Rollback Plan

### Rollback Helm (Fases 3 e 7)

Se o helm upgrade falhar ou o pod nao subir apos o upgrade:

```bash
# Verificar historico de releases
helm history backstage -n staging-platform-backstage

# Rollback para a versao anterior (substituir <REVISION> pela revisao anterior)
helm rollback backstage <REVISION> \
  -n staging-platform-backstage \
  --wait \
  --timeout 5m

# Verificar que o pod voltou a funcionar
kubectl rollout status deployment/backstage -n staging-platform-backstage
```

**Criterio de validacao pos-rollback:** Pod Running 2/2, Backstage acessivel em `https://backstage.staging.internal`.

### Rollback ConfigMap (Fase 2)

Se o ConfigMap `platform-manifest-schema` causar problemas (improvavel — apenas um arquivo estatico):

```bash
kubectl delete configmap platform-manifest-schema -n staging-platform-backstage
# O helm rollback acima removera a referencia do extraVolume automaticamente
```

### Rollback Catalog Entities (Fase 4)

Se as entidades causarem problemas no catalog (ex: entidades invalidas causando parse error):

```bash
# Reverter o commit no GitLab via MR de revert (via UI ou API)
# Ou deletar as entidades individualmente via API Backstage:
curl -sk -X DELETE \
  -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" \
  "https://backstage.staging.internal/api/catalog/entities/by-uid/<UID>"
```

### Rollback Imagem Docker (Fase 7)

```bash
# Voltar para a tag anterior no helm values e fazer upgrade
# Alterar tag em helm-values-staging.yaml de volta para "1.48.0-oidc"
helm upgrade backstage backstage/backstage \
  -n staging-platform-backstage \
  -f /home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/plan/backstage/helm-values-staging.yaml \
  --set backstage.image.tag="1.48.0-oidc" \
  --wait \
  --timeout 5m
```

---

## Pos-Deploy — Sincronizacao ArgoCD (Recomendado)

Apos validar que o deploy via `helm upgrade` direto esta funcionando, e necessario atualizar o `argocd-application.yaml` para refletir o novo estado. Caso contrario, o ArgoCD pode tentar reverter para o estado antigo quando a reconciliacao ocorrer.

**Acao:** Atualizar `docs/plan/backstage/argocd-application.yaml` para:
1. Remover o bloco `initContainers` (ou garantir que fique vazio — alinhado com BUG-001 fix)
2. Adicionar os `extraVolumes` para `platform-manifest-schema` e `staging-internal-ca`
3. Atualizar `listen-ports` para incluir HTTPS:443
4. Adicionar `PLATFORM_SCHEMA_PATH` env var

**Referencia:** `docs/plan/backstage/helm-values-staging.yaml` e a fonte da verdade — o ArgoCD Application deve ser atualizado para espelhar este arquivo.

```bash
# Apos atualizar o argocd-application.yaml local, aplicar:
kubectl apply -f \
  /home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/plan/backstage/argocd-application.yaml \
  -n staging-platform-argocd
```

---

## Artefatos Publicados por este Playbook

| Artefato | Localizacao Local | Destino Cluster/GitLab |
|----------|-------------------|------------------------|
| helm-values-staging.yaml (17 GAPs + S6-C + BUG-001) | `docs/plan/backstage/helm-values-staging.yaml` | Helm release `backstage` namespace `staging-platform-backstage` |
| ConfigMap platform-manifest-schema | `domains/platform-core/app-provisioning/schemas/v1/manifest-schema.json` | `staging-platform-backstage/configmap/platform-manifest-schema` |
| Vault policy backstage-scaffolder | (inline neste playbook) | `vault/auth/approle/role/app-template` + `vault/policy/backstage-scaffolder` |
| catalog-info.yaml (raiz) | `docs/plan/backstage/catalog/catalog-info.yaml` | GitLab `platform/backstage-catalog/catalog-info.yaml` |
| 5 Domain entities | `docs/plan/backstage/catalog/entities/domains/catalog-info.yaml` | GitLab `platform/backstage-catalog/entities/domains/catalog-info.yaml` |
| System data-hatch-etl | `docs/plan/backstage/catalog/entities/systems/data/catalog-info.yaml` | GitLab `platform/backstage-catalog/entities/systems/data/catalog-info.yaml` |
| 8 Component entities ETL/Hatch | `docs/plan/backstage/catalog/ETL/Hatch/catalog-info.yaml` | GitLab `platform/backstage-catalog/ETL/Hatch/catalog-info.yaml` |
| Template new-service | `docs/plan/backstage/templates/new-service/template.yaml` | GitLab `platform/backstage-catalog/templates/new-service/template.yaml` |
| Template etl-service | `docs/plan/backstage/templates/etl-service/template.yaml` | GitLab `platform/backstage-catalog/templates/etl-service/template.yaml` |
| Template api-service | `docs/plan/backstage/templates/api-service/template.yaml` | GitLab `platform/backstage-catalog/templates/api-service/template.yaml` |
| Plugin platform-scaffolder-actions | `docs/plan/backstage/plugins/platform-scaffolder-actions/` | Imagem Docker + `packages/backend/src/index.ts` |

---

*Playbook gerado em 2026-03-13 | Sprint S6-A + S6-B + S6-C + S6-D | ADR-055, ADR-102*
*Modo consultivo — nenhum comando foi executado neste documento*
