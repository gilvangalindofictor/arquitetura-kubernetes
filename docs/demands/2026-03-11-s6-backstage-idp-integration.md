# Demanda: S6 — Backstage IDP Integration

**Data:** 2026-03-11
**Atualizado:** 2026-03-12 (verificação de ambiente — agentes Observability + Security + AWS + GAP Resolver)
**Prioridade:** MEDIUM (Marco 2 — Self-Service Platform)
**Status:** SPRINT S6-A EM ANDAMENTO (2026-03-12)
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
| S6-A | Catalog Integration | Dev vê catálogo com ETL/Hatch, 5 domínios, pods K8s em tempo real | EM ANDAMENTO \| 2026-03-12 |
| S6-B | Scaffolder Template | Dev preenche form → manifest.yaml gerado e válido | PENDENTE |
| S6-C | GitLab MR Automático | Form → repositório criado + MR aberto em < 3 min | PENDENTE |
| S6-D | Observability Links | Grafana, ArgoCD, Vault links na página do componente | PENDENTE |

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

## Entregáveis S6-C (GitLab)

| Componente | Descrição |
|------------|-----------|
| `publish:gitlab` action | Nativa do plugin-scaffolder-backend-module-gitlab |
| `gitlab:repo:create` action | Cria repo no grupo correto |
| Custom action `platform:manifest:validate` | Validação pré-MR |

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
