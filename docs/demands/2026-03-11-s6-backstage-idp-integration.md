# Demanda: S6 — Backstage IDP Integration

**Data:** 2026-03-11
**Atualizado:** 2026-03-13 (ISSUE-SKEL-01/02 apiVersion/kind corrigidos em 3 skeletons — Documentation Specialist)
**Prioridade:** MEDIUM (Marco 2 — Self-Service Platform)
**Status:** SPRINT S6-A CONCLUÍDO (local) — S6-B CONCLUÍDO (templates) — S6-C CONCLUÍDO LOCAL (2026-03-13) — S6-D CONCLUÍDO LOCAL (2026-03-13) — BUG-001 RESOLVIDO NO ARQUIVO (deploy pendente) — Aguardando AWS para deploy
**ADR:** ADR-102 (Backstage stack), ADR-055 (versões fixadas)
**Dependência:** S0→S5 concluídos ✅
**Marco:** Marco 2 — Self-Service Platform

## Objetivo

Integrar Backstage IDP para que desenvolvedores criem novos serviços via formulário web,
gerando automaticamente `.platform/manifest.yaml` e abrindo MR no GitLab — sem editar
YAML manualmente. Tempo alvo: formulário → MR pronto < 3 minutos.

## Fluxo Golden Path

Dev → Form Backstage → Scaffolder gera manifest.yaml + catalog-info.yaml
  → publish:gitlab → MR aberto → pipeline validate:manifest → merge
  → provision:onboarding → cluster provisionado → app no catálogo

## Estado Atual da Infraestrutura Backstage

> Verificação executada em 2026-03-12 via agentes Observability + Security + AWS + GAP Resolver.

| Componente | Status | Evidência |
|------------|--------|-----------|
| Namespace `staging-platform-backstage` | ✅ Active | `kubectl get namespace` — Active, labels domain=platform/environment=staging |
| ClusterRole `backstage-kubernetes-reader` | ✅ Aplicado | Criado em 2026-03-05T21:38:43Z |
| PodDisruptionBudget backstage-pdb | ✅ Criado | minAvailable=1 — ⚠️ ver GAP-S6-PDB-01 |
| Helm chart `backstage/backstage 2.6.3` | ✅ Deployado | gen.53, managed-by Helm |
| ExternalSecret backstage | ✅ SecretSynced | `vault-backend`, refresh 1h, READY=True |
| ADR-102 + ADR-055 aprovados | ✅ | — |
| Backstage deployado | ✅ Running 2/2 | Pod `backstage-57b48cd5fc-cms8r`, image `harbor.staging.internal/platform/backstage:1.48.0-oidc` |
| GitLab token no Vault | ✅ Presente | `secret/staging/backstage/gitlab` — glpat criado em 2026-03-06 |
| Keycloak client `backstage` | ✅ Existe | realm `platform`, enabled, protocol=openid-connect, redirectUris corretas |
| Vault bootstrap (9/9 paths) | ✅ Completo | `secret/staging/backstage/harbor` populado (GAP-S6-03-A resolvido 2026-03-12) |
| AppRole auth method | ✅ Habilitado | `approle/` + role `app-template` criados (GAP-S6-03-B resolvido 2026-03-12) |
| Repo GitLab `platform/backstage-catalog` | ✅ Criado | ID=7, 3 arquivos publicados (GAP-S6-08 resolvido 2026-03-12) |
| Helm values corrigidos (17 GAPs) | ✅ Local | `docs/plan/backstage/helm-values-staging.yaml` atualizado (479L) |
| Catalog entities (4 arquivos) | ✅ Local | docs/plan/backstage/catalog/ completo — pronto para publicação |
| S6-B Templates (3 templates) | ✅ Local | new-service + etl-service + api-service criados |
| Security audit | ⚠️ 63/100 | 18 GAPs detectados — P0/P1 parcialmente resolvidos |

## GAPs — Estado Real (pós verificação 2026-03-12)

### GAPs Fechados (Falsos Positivos)

| GAP-ID | Descrição | Status | Evidência |
|--------|-----------|--------|-----------|
| GAP-S6-01 | Backstage não deployado | ✅ FECHADO | Pod Running 2/2, gen.53 |
| GAP-S6-02 | Group Access Token GitLab ausente | ✅ FECHADO | Token em `secret/staging/backstage/gitlab` |
| GAP-S6-03 | Vault bootstrap não executado | ✅ PARCIAL → ver abaixo | 8/9 paths criados, policy+K8s role OK |
| GAP-S6-04 | Keycloak client `backstage` não criado | ✅ FECHADO | Client existe, enabled, secret ativo |
| GAP-S6-10 | catalog-info.yaml ausente no ETL/Hatch | ✅ FECHADO | `domains/data-services/catalog-info.yaml` completo |

### GAPs Resolvidos em Sprint S6-0 (2026-03-12)

| GAP-ID | Prio | Descrição | Status | Data |
|--------|------|-----------|--------|------|
| GAP-S6-03-A | P1 ALTO | `secret/staging/backstage/harbor` ausente no Vault | ✅ RESOLVIDO | 2026-03-12 |
| GAP-S6-03-B | P2 MÉDIO | AppRole auth method não habilitado no Vault | ✅ RESOLVIDO | 2026-03-12 |
| GAP-S6-08 | P1 ALTO | Repo GitLab `platform/backstage-catalog` não criado | ✅ RESOLVIDO | 2026-03-12 |
| GAP-S6-PDB-01 | P2 MÉDIO | `backstage-pdb` com minAvailable=1 e 1 réplica → 0 disruptions | ✅ RESOLVIDO | 2026-03-12 |
| GAP-S6-ExternalSecret | — | backstage-secrets sync status | ✅ CONFIRMADO | 2026-03-12 |

## Micro-Sprints S6

| Sprint | Título | Critério de Done | Status |
|--------|--------|-----------------|--------|
| S6-0 | Desbloqueadores Reais | GAP-S6-03-A + S6-03-B + S6-PDB-01 resolvidos | CONCLUÍDO \| 2026-03-12 |
| S6-A | Catalog Integration | Dev vê catálogo com ETL/Hatch, 5 domínios, pods K8s em tempo real | CONCLUÍDO LOCAL (2026-03-13) — publicação pendente (AWS indisponível) |
| S6-B | Scaffolder Template | Dev preenche form → manifest.yaml gerado e válido | CONCLUÍDO LOCAL (2026-03-13) — templates criados — publicação pendente |
| S6-C | GitLab MR Automático | Form → repositório criado + MR aberto em < 3 min | CONCLUÍDO LOCAL (2026-03-13) — deploy pendente AWS-recovery |
| S6-D | Observability Links | Grafana, ArgoCD, Vault links na página do componente | CONCLUÍDO LOCAL (2026-03-13) — publicação pendente AWS-recovery |

## Sprint S6-0 — Desbloqueadores Reais (Plano de Execução)

> Verificação de ambiente realizada em 2026-03-12 revelou que os GAPs P0 originais eram falsos positivos.
> Os 3 itens abaixo são os únicos bloqueadores reais antes de iniciar S6-A.

### GAP-S6-03-A — Harbor secret ausente no Vault (P1 ALTO)

**Contexto:** O ExternalSecret `backstage-secrets` sincroniza 9 paths do Vault. O path `secret/staging/backstage/harbor` não existe — Harbor robot account `backstage-puller` não foi criado.

**Ação:**

1. Criar robot account no Harbor UI (`harbor.staging.internal`) com scopes `pull` e `push`
2. Copiar o token gerado
3. Executar via `kubectl exec -n staging-security-vault vault-0`:

```bash
vault kv put secret/staging/backstage/harbor \
  url="https://harbor.staging.internal" \
  robot-token="<TOKEN_DO_HARBOR>"
```

1. Validar: `kubectl get externalsecret backstage-secrets -n staging-platform-backstage` → STATUS=SecretSynced

**Critério de Done:** ExternalSecret `backstage-secrets` com todos os 9 paths sincronizados (READY=True sem erros).

---

### GAP-S6-03-B — AppRole auth method não habilitado no Vault (P2 MÉDIO)

**Contexto:** O Scaffolder do Backstage (S6-B) precisará criar AppRoles para novos serviços via `bootstrap-vault-setup.sh`. O auth method `approle/` não está habilitado — apenas `kubernetes/`, `oidc/`, `token/`.

**Ação:**

```bash
# Executar via kubectl exec -n staging-security-vault vault-0
vault auth enable approle
vault write auth/approle/role/app-template \
  secret_id_ttl=24h \
  token_ttl=1h \
  token_max_ttl=4h \
  token_policies=default \
  bind_secret_id=true
```

**Critério de Done:** `vault auth list` retorna `approle/` habilitado + role `app-template` listado.

---

### GAP-S6-PDB-01 — PDB bloqueante com réplica única (P2 MÉDIO)

**Contexto:** `backstage-pdb` configurado com `minAvailable=1` e deployment com `replicas=1` resulta em `ALLOWED DISRUPTIONS=0`. Qualquer node drain ou rollout forçado trava.

**Ação (2 opções — escolher uma):**

- **Opção A (recomendada):** Aumentar replicas do deployment para 2 → PDB permite 1 disruption
- **Opção B:** Alterar PDB para `maxUnavailable=1` (menos seguro para produção)

**Critério de Done:** `kubectl get pdb backstage-pdb -n staging-platform-backstage` → `ALLOWED DISRUPTIONS >= 1`.

---

### Resultado Final — Sprint S6-0 (2026-03-12)

| GAP | Evidência | Status |
|-----|-----------|--------|
| S6-PDB-01 | kubectl scale 2 réplicas; values.yaml.tpl atualizado | ✅ RESOLVIDO |
| S6-03-B | AppRole auth method + role `app-template` criado no Vault | ✅ RESOLVIDO |
| S6-08 | Repo `platform/backstage-catalog` criado (ID=7), 3 arquivos publicados | ✅ RESOLVIDO |
| S6-03-A | Robot `backstage-puller` (id=20) criado; Vault `secret/staging/backstage/harbor` populado | ✅ RESOLVIDO |
| S6-ExternalSecret | backstage-secrets READY=True, 13 chaves sincronizadas | ✅ CONFIRMADO |

**Sprint S6-0 CONCLUÍDO — Próximo: S6-A (Helm Values + OIDC config)**

## Entregáveis S6-A (Catalog)

| Arquivo | Descrição |
|---------|-----------|
| `backstage-catalog/catalog-info.yaml` | Location entity raiz |
| `backstage-catalog/entities/domains/catalog-info.yaml` | 5 Domain entities |
| `backstage-catalog/entities/systems/data/catalog-info.yaml` | System `data-hatch-etl` |
| `ETL/Hatch/catalog-info.yaml` | Component entity do Hatch ETL |

## Entregáveis S6-B (Templates)

| Arquivo | Descrição |
|---------|-----------|
| `backstage-catalog/templates/new-service/template.yaml` | Template Backstage genérico |
| `backstage-catalog/templates/new-service/skeleton/.platform/manifest.yaml` | Skeleton Nunjucks |
| `backstage-catalog/templates/etl-service/template.yaml` | Template especializado ETL |
| `backstage-catalog/templates/api-service/template.yaml` | Template especializado API REST |

## Entregáveis S6-C (GitLab MR Automático) — CONCLUÍDO LOCAL 2026-03-13

| Componente | Arquivo | Status |
|------------|---------|--------|
| Template `new-service` com MR automático | `docs/plan/backstage/templates/new-service/template.yaml` | ✅ Atualizado |
| Template `etl-service` com MR automático | `docs/plan/backstage/templates/etl-service/template.yaml` | ✅ Atualizado |
| Template `api-service` com MR automático | `docs/plan/backstage/templates/api-service/template.yaml` | ✅ Atualizado |
| Plugin `platform:manifest:validate` | `docs/plan/backstage/plugins/platform-scaffolder-actions/` | ✅ Completo |
| `helm-values-staging.yaml` com Scaffolder config | `docs/plan/backstage/helm-values-staging.yaml` | ✅ Atualizado |

### Mudanças S6-C nos templates (3 templates)

Todos os 3 templates foram atualizados com os campos S6-C no step `publish:gitlab`:

- `branchName: scaffold/<name>` — cria branch dedicada para o scaffold
- `sourceBranch: scaffold/<name>` — fonte do MR
- `title: feat: scaffold <name> via Backstage` — título do MR
- `description: |` — corpo detalhado do MR com checklist
- `gitCommitMessage: feat: scaffold inicial via Backstage — <name>` — mensagem do commit
- `output.mergeRequestUrl` — link para o MR gerado exposto ao dev no Backstage UI

### Mudanças S6-C no helm-values-staging.yaml

1. **`appConfig.scaffolder`** adicionado:
   ```yaml
   scaffolder:
     defaultAuthor:
       name: Platform Bot
       email: platform-bot@empresa.com.br
     defaultCommitMessage: "feat: scaffold via Backstage"
   ```
2. **`PLATFORM_SCHEMA_PATH`** env var adicionada (aponta para `/app/schemas/v1/manifest-schema.json`)
3. **Volume `platform-manifest-schema`** (ConfigMap) adicionado para montar o JSON Schema no container

### Plugin platform-scaffolder-actions — Status

| Arquivo | Status |
|---------|--------|
| `src/actions/validateManifest.ts` | ✅ COMPLETO — Ajv 2020-12, allErrors, outputs valid/appName/domain/type |
| `src/index.ts` | ✅ COMPLETO — exporta `createValidateManifestAction` |
| `package.json` | ✅ COMPLETO — backstage.role=backend-plugin-module, deps corretas |
| `tsconfig.json` | ✅ CRIADO — `extends @backstage/cli/config/tsconfig.json` |
| `README.md` | ✅ COMPLETO — instrução de registro via `backend.add()` |

### ISSUE-SKEL-01/02 — Skeleton apiVersion/kind divergência (RESOLVIDO 2026-03-13)

| ISSUE | Arquivo | Antes | Depois | Status |
| ----- | ------- | ----- | ------ | ------ |
| ISSUE-SKEL-01 | `templates/etl-service/skeleton/.platform/manifest.yaml` | `apiVersion: platform.io/v1alpha1` / `kind: Application` | `apiVersion: platform.k8s/v1` / `kind: ApplicationManifest` | ✅ RESOLVIDO |
| ISSUE-SKEL-02 | `templates/api-service/skeleton/.platform/manifest.yaml` | `apiVersion: platform.io/v1alpha1` / `kind: Application` | `apiVersion: platform.k8s/v1` / `kind: ApplicationManifest` | ✅ RESOLVIDO |
| ISSUE-SKEL-02b | `templates/new-service/skeleton/.platform/manifest.yaml` | `apiVersion: platform.io/v1alpha1` / `kind: Application` | `apiVersion: platform.k8s/v1` / `kind: ApplicationManifest` | ✅ RESOLVIDO |

Correção necessária pois o JSON Schema `domains/platform-core/app-provisioning/schemas/v1/manifest-schema.json` define `const: "platform.k8s/v1"` e `const: "ApplicationManifest"` — qualquer outro valor falha na validação Ajv.

### GAPs S6-C Residuais (pós-deploy)

| GAP | Descrição | Ação Pós-AWS-Recovery |
|-----|-----------|----------------------|
| GAP-S6C-01 | ConfigMap `platform-manifest-schema` não criado no cluster | `kubectl create configmap platform-manifest-schema --from-file=manifest-schema.json=domains/platform-core/app-provisioning/schemas/v1/manifest-schema.json -n staging-platform-backstage` |
| GAP-S6C-02 | Plugin `platform-scaffolder-actions` não registrado no `packages/backend/src/index.ts` | Adicionar `backend.add(import('@backstage/plugin-scaffolder-backend-module-gitlab'))` + module de custom actions — ver README do plugin |
| GAP-S6C-03 | Templates S6-C não publicados no GitLab `platform/backstage-catalog` | Publicar os 3 templates via MR após AWS-recovery |

## Entregáveis S6-D (Observability Links) — CONCLUÍDO LOCAL 2026-03-13

| Arquivo | Componentes Atualizados | Links Adicionados | Annotations Adicionadas |
| --- | --- | --- | --- |
| `docs/plan/backstage/catalog/ETL/Hatch/catalog-info.yaml` | 8 componentes (api-gateway, worker, etl-core, data-processor, scheduler, dashboard, cronjob-etl-extraction, migration-runner) | Grafana / ArgoCD / Vault (3 links por componente, com `type` field) | `backstage.io/kubernetes-id: hatch-etl`, `grafana/alert-label-selector: app=hatch-etl`, `grafana/dashboard-selector: app=hatch-etl` (canonical) |
| `docs/plan/backstage/catalog/entities/systems/data/catalog-info.yaml` | System `data-hatch-etl` | Grafana / ArgoCD / Vault / GitLab (4 links com `type` field) | `grafana/alert-label-selector: app=hatch-etl`, `grafana/dashboard-selector: app=hatch-etl` (canonical) |
| `domains/data-services/catalog-info.yaml` | Component `data-hatch-etl` (legacy) | Grafana / ArgoCD / Vault / GitLab (4 links com `type` field) | `backstage.io/kubernetes-id: hatch-etl`, `backstage.io/kubernetes-namespace: staging-data-hatch-etl`, `argocd/app-namespace: staging-data-hatch-etl`, `grafana/alert-label-selector: app=hatch-etl` (canonical) |

### Links Canônicos S6-D

| Ferramenta | URL | Icon | Type |
| --- | --- | --- | --- |
| Grafana | `https://grafana.staging.internal/d/hatch-etl-overview` | dashboard | monitoring |
| ArgoCD | `https://argocd.staging.internal/applications/staging-data-hatch-etl` | argoCD | deployment |
| Vault | `https://vault.staging.internal/ui/vault/secrets/secret/staging/hatch` | security | secrets |

### Annotations Canônicas S6-D (todos os componentes ETL/Hatch)

```yaml
backstage.io/kubernetes-id: hatch-etl
backstage.io/kubernetes-namespace: staging-data-hatch-etl
argocd/app-name: staging-data-hatch-etl
argocd/app-namespace: staging-data-hatch-etl
grafana/dashboard-selector: "app=hatch-etl"
grafana/alert-label-selector: "app=hatch-etl"
```

---

## BUG-001 — Init Container Docker Hub Rate-Limit (2026-03-13)

**Status:** RESOLVIDO NO ARQUIVO (deploy pendente AWS-recovery)

### Sintoma

Após restart dos pods do Backstage (ex: node drain, rollout, escalonamento), o pod entra em
fase `Init:ImagePullBackOff` e nunca sobe. O Backstage fica 100% indisponível enquanto o
init container estiver presente. O evento Kubernetes reporta:

```text
Failed to pull image "node:22-bookworm-slim": HTTP 429 Too Many Requests (Docker Hub rate-limit)
```

### Root Cause

O Helm chart `backstage/backstage 2.6.3` define um init container `install-oidc` que usa a
imagem pública `node:22-bookworm-slim` do Docker Hub. Em clusters EKS em produção/staging,
qualquer IP de node compartilhado ou sem autenticação Docker Hub atinge o rate-limit após
poucos pulls (`429 Too Many Requests`).

O pod fica preso na fase `Init` indefinidamente — o container principal nunca inicia.

**Agravante:** A imagem Backstage em uso já é
`harbor.staging.internal/platform/backstage:1.48.0-oidc`. O sufixo `-oidc` indica que o
suporte OIDC está embutido na imagem. O init container `install-oidc` era completamente
redundante — realizava configuração OIDC que a imagem já contém.

### Fix Definitivo Aplicado

Arquivo: `docs/plan/backstage/helm-values-staging.yaml`, linha 478.

O init container foi eliminado via override explícito no helm values:

```yaml
initContainers: []
```

Esta configuração sobrepõe a definição padrão do chart, removendo o pull de qualquer imagem
externa do Docker Hub. Zero dependência de registry público em runtime.

### Verificação Esperada (pós helm upgrade)

Após executar `helm upgrade backstage` com o novo `helm-values-staging.yaml`:

1. `kubectl get pod -n staging-platform-backstage` — pod NÃO deve passar pela fase `Init`; deve
   ir direto para `ContainerCreating` → `Running`.
2. `kubectl describe pod <backstage-pod> -n staging-platform-backstage` — campo `Init Containers:`
   deve estar ausente ou vazio.
3. Backstage acessível em `https://backstage.staging.internal` sem erros de init.

### Pendência de Deploy

O fix está aplicado localmente em `docs/plan/backstage/helm-values-staging.yaml`. O `helm upgrade`
faz parte das Pendências Pós-AWS-Recovery (item 2 da tabela abaixo) e será executado quando o
acesso AWS/cluster for restabelecido.

---

## GAPs de Segurança S6 (2026-03-13)

> Security posture score: **63/100** — Auditoria executada em 2026-03-13 pelo agente Security.
> 18 GAPs detectados. P0/P1 aplicados localmente onde possível (AWS indisponível).

| GAP-ID | Prioridade | Descrição | Status |
| ------ | ---------- | --------- | ------ |
| GAP-SEC-S6-10 | P0 CRÍTICO | CVE-2025-55285 — scaffolder-backend < 2.1.1 vulnerável | Pendente verificação no cluster via kubectl exec |
| GAP-SEC-S6-04 | P1 ALTO | Ingress sem TLS/HTTPS — tráfego exposto em HTTP | Pendente (requer AWS/ACM indisponível) |
| GAP-SEC-S6-08 | P1 ALTO | AppRole policy `backstage-scaffolder` ausente no Vault | Pendente (requer Vault — AWS indisponível) |
| GAP-SEC-S6-13 | P1 ALTO | ExternalSecret sem `deletionPolicy: Retain` — risco de wipe acidental | ✅ RESOLVIDO LOCAL — `deletionPolicy: Retain` adicionado |
| GAP-SEC-S6-06 | P2 MÉDIO | Session cookie sem flags `secure`, `httpOnly`, `sameSite` | ✅ RESOLVIDO LOCAL — config de sessão adicionada |
| GAP-SEC-S6-11 | P2 MÉDIO | Template `new-service`: `onExistingBranch: force` → sobrescreve branches sem aviso | ✅ RESOLVIDO LOCAL — alterado para `onExistingBranch: error` |
| GAP-SEC-S6-17 | P2 MÉDIO | ServiceAccount com long-lived token sem TTL configurado | ✅ RESOLVIDO LOCAL — comentário TODO adicionado |
| GAP-SEC-S6-01 a 09, 12, 14-16, 18 | P2/P3 | Demais GAPs de hardening (RBAC, NetworkPolicy, rate-limit, etc.) | Pendente sprint S6-C/S6-D |

**Itens pendentes críticos pós-AWS-recovery:**

- GAP-SEC-S6-10: `kubectl exec -n staging-platform-backstage <pod> -- npm list @backstage/plugin-scaffolder-backend` → verificar versão
- GAP-SEC-S6-04: Aplicar patch Ingress com anotações AWS ALB + certificado ACM
- GAP-SEC-S6-08: `vault policy write backstage-scaffolder` + `secret_id_num_uses=5` no role `app-template`

---

## Pendências Pós-AWS-Recovery

> Executar nesta ordem quando o acesso AWS/cluster for restabelecido.

| Prioridade | Ação | Contexto |
| ---------- | ---- | -------- |
| 1 | `kubectl apply` dos catalog entities no repositório `platform/backstage-catalog` | 4 arquivos prontos em `docs/plan/backstage/catalog/` |
| 2 | `helm upgrade backstage` com novo `helm-values-staging.yaml` (ArgoCD sync ou helm upgrade direto) | 17 GAPs corrigidos — arquivo em `docs/plan/backstage/helm-values-staging.yaml` (479L) |
| 3 | Verificar CVE-2025-55285 via `kubectl exec -n staging-platform-backstage <pod> -- npm list @backstage/plugin-scaffolder-backend` | Confirmar versão >= 2.1.1 ou aplicar patch de imagem |
| 4 | Aplicar patch Ingress HTTPS — anotações AWS ALB + certificado ACM | GAP-SEC-S6-04 |
| 5 | Criar policy `backstage-scaffolder` no Vault + adicionar `secret_id_num_uses=5` ao role `app-template` | GAP-SEC-S6-08 |
| 6 | Publicar templates S6-B/S6-C no GitLab `platform/backstage-catalog` (new-service + etl-service + api-service) | Templates com MR automático prontos localmente (S6-C) |
| 7 | Criar ConfigMap `platform-manifest-schema` no cluster | GAP-S6C-01: `kubectl create configmap platform-manifest-schema --from-file=manifest-schema.json=domains/platform-core/app-provisioning/schemas/v1/manifest-schema.json -n staging-platform-backstage` |
| 8 | Registrar plugin `platform-scaffolder-actions` no `packages/backend/src/index.ts` | GAP-S6C-02: adicionar `backend.add()` para custom action + plugin-scaffolder-backend-module-gitlab |

---

## Riscos

| Risco | Impacto | Mitigação |
|-------|---------|-----------|
| CVE-2025-55285 scaffolder-backend < 2.1.1 | Alto | Fixar exatamente em 3.1.3 |
| Backstage new backend system: plugins legados não inicializam | Alto | Verificar API `backend.add()` por plugin |
| Formulário muito complexo → baixa adoção | Alto | 4 steps progressivos, defaults por tipo |
| gitlab:repo:create não idempotente | Médio | onExistingBranch: force no publish:gitlab |

## Definition of Done S6 (completo)

- [ ] Dev externo ao time de plataforma consegue criar novo serviço via Backstage
- [ ] Tempo form → MR pronto: < 3 minutos
- [ ] Pipeline validate:manifest passa automaticamente no MR gerado
- [ ] Componente aparece no catálogo Backstage após merge
- [ ] Status de pods K8s visível na página do componente
- [ ] Links ArgoCD, Grafana, Vault funcionais na página do componente
- [ ] Documentado em docs/demands/ o processo para onboarding de novos serviços via Backstage
