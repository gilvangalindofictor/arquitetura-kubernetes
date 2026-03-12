# Demanda: S6 — Backstage IDP Integration

**Data:** 2026-03-11
**Prioridade:** MEDIUM (Marco 2 — Self-Service Platform)
**Status:** PLANEJADO — aguardando desbloqueadores
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

| Componente | Status |
|------------|--------|
| Namespace `staging-platform-backstage` | ✅ Criado |
| ClusterRole `backstage-kubernetes-reader` | ✅ Aplicado |
| PodDisruptionBudget backstage-pdb | ✅ Criado |
| Helm chart `backstage/backstage 2.6.3` | ✅ Mapeado |
| ExternalSecret backstage | ✅ Preparado |
| ADR-102 + ADR-055 aprovados | ✅ |
| Backstage deployado | ❌ PENDENTE |

## Desbloqueadores (GAPs P0)

| GAP-ID | Descrição | Ação |
|--------|-----------|------|
| GAP-S6-01 | Backstage não deployado | Executar bootstrap-vault-setup.sh + Helm install |
| GAP-S6-02 | Group Access Token GitLab ausente | Criar em GitLab Admin → armazenar no Vault |
| GAP-S6-03 | Vault bootstrap não executado | Executar bootstrap-vault-setup.sh |
| GAP-S6-04 | Keycloak client `backstage` não criado | Criar client no realm `platform` |
| GAP-S6-08 | Repo `platform/backstage-catalog` não existe | Criar repositório GitLab |
| GAP-S6-10 | catalog-info.yaml ausente no repo ETL/Hatch | Criar como parte de S6-A |

## Micro-Sprints S6

| Sprint | Título | Critério de Done |
|--------|--------|-----------------|
| S6-A | Catalog Integration | Dev vê catálogo com ETL/Hatch, 5 domínios, pods K8s em tempo real |
| S6-B | Scaffolder Template | Dev preenche form → manifest.yaml gerado e válido |
| S6-C | GitLab MR Automático | Form → repositório criado + MR aberto em < 3 min |
| S6-D | Observability Links | Grafana, ArgoCD, Vault links na página do componente |

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
