# Padrões Globais de Plataforma — Ingress e Observabilidade

**Data**: 2026-03-18
**Status**: CONCLUÍDO — 14 GAPs implementados
**Domínio**: platform-core
**Tipo**: Platform Standard
**Impacto**: Todos os projetos onboardados na plataforma (Hatch, VemSoft, iPaaS e futuros)

---

## Objetivo

Implementar padrões globais de Ingress e Observabilidade na plataforma IDP (Backstage + GitLab CI + ArgoCD + EKS) de forma que qualquer app onboardado receba esses recursos automaticamente, com sistema de tiers de custo e override por app.

**Insight chave**: Os campos `observability.metrics.enabled` e `config.ingress.enabled` já existiam no `manifest-template.yaml` e JSON Schema. O gap era de **glue code ausente** — scripts que leem esses campos e geram recursos K8s.

---

## Arquitetura Implementada — 3 Horizontes

| Horizonte | Escopo | Status |
|-----------|--------|--------|
| H1 (esta sessão) | Skeleton Backstage + CI Template include + Scripts provisioning | ✅ CONCLUÍDO |
| H2 (próxima sessão) | ArgoCD ApplicationSet de observabilidade automática | ⏳ Pendente |
| H3 (futuro) | Kustomize base library versionada | ⏳ Futuro |

---

## GAPs Implementados (14/14)

### FASE 0 — RBAC (Desbloqueador Global)

**GAP-PLAT-RBAC-01** ✅
- Arquivo: `domains/platform-core/app-provisioning/scripts/onboarding/bootstrap-provisioner.sh`
- Fix: ClusterRole `platform-provisioner` — adicionadas regras para `monitoring.coreos.com` (ServiceMonitor, PrometheusRule) e `networking.k8s.io/ingresses`
- Arquivo: `domains/platform-core/app-provisioning/templates/appproject-template.yaml`
- Fix: `namespaceResourceWhitelist` inclui `monitoring.coreos.com/ServiceMonitor` e `monitoring.coreos.com/PrometheusRule`

### FASE 1 — Schema

**GAP-PLAT-OBS-01** ✅
- Arquivos: `schemas/v1/manifest-schema.json` + `skeleton/.platform/manifest.yaml`
- Adicionados: `observability.metrics.scrapeInterval`, `observability.metrics.tier`, `observability.alerting.*`, `observability.dashboard.*`

**GAP-PLAT-ING-01** ✅
- Arquivos: `schemas/v1/manifest-schema.json` + `skeleton/.platform/manifest.yaml`
- Adicionados: `config.ingress.ingressGroup`, `config.ingress.costTier`, `config.ingress.rateLimit.*`, `config.ingress.pathPrefix`, `config.ingress.healthCheckPath`

**GAP-PLAT-ING-05** ✅
- Artefatos: `templates/ingressgroup-internal.yaml` + `templates/ingressgroup-external.yaml`
- IngressGroups criados:
  - `data-internal` — ALB internal, `*.staging.internal`
  - `data-public` — ALB internet-facing, requer aprovação
  - `platform-internal` — Backstage, ArgoCD, GitLab
  - `integration-internal` — iPaaS, conectores B2B, webhooks

### FASE 2 — Validações Schema

**GAP-PLAT-OBS-02** ✅
- Adicionado: enum `tier` (critical/standard/low), pattern `scrapeInterval` (`^[0-9]+(s|m)$`), enum `dashboard.preset`

**GAP-PLAT-ING-02** ✅
- Adicionado: enum `ingressGroup` (lista dos predefinidos), enum `costTier`, pattern `pathPrefix` (`^/`), integer min/max `rateLimit.requestsPerMinute`

### FASE 3 — Templates K8s e Formulário Backstage

**GAP-PLAT-TEMPL-01** ✅
- Criados em `domains/platform-core/app-provisioning/templates/`:
  - `servicemonitor-template.yaml` — Placeholders: APP_NAME, METRICS_PORT, METRICS_PATH, SCRAPE_INTERVAL, NAMESPACE
  - `prometheusrule-template.yaml` — Placeholders: APP_NAME, NAMESPACE, TIER, TEAM, OWNER
  - `ingress-template.yaml` — Placeholders: APP_NAME, HOST, INGRESS_CLASS, INGRESS_GROUP, TLS_ENABLED, NAMESPACE
  - `grafana-dashboard-template.yaml` — ConfigMap com 6 painéis universais, datasources Prometheus+Loki+Tempo

**GAP-PLAT-BACK-01** ✅
- Arquivo: `docs/plan/backstage/templates/etl-service/template.yaml`
- Passo 5 expandido: + `scrapeInterval` (select), `tier` (radio), `alertingEnabled`, `dashboardEnabled`
- Novo passo "Exposição HTTP (Ingress)": `ingressEnabled`, `ingressClass`, `ingressGroup` (enum), `ingressHost`, `rateLimitEnabled`, `rateLimitRpm`

### FASE 4 — Skeleton Backstage

**GAP-PLAT-OBS-03** ✅
- Criados em `docs/plan/backstage/templates/etl-service/skeleton/k8s/base/`:
  - `servicemonitor.yaml.njk` — condicional: `values.metricsEnabled=true`
  - `prometheusrule.yaml.njk` — condicional: `values.alertingEnabled=true`
  - `grafana-dashboard.yaml.njk` — condicional: `values.dashboardEnabled=true`
  - `kustomization.yaml` — inclui os 3 condicionalmente

**GAP-PLAT-ING-03** ✅
- Criado: `skeleton/k8s/base/ingress.yaml.njk` — condicional `ingressEnabled=true`
- Anotações ALB corretas por `ingressClass` e `ingressGroup`
- Rate limit via annotation se `rateLimitEnabled=true`

### FASE 5 — Scripts de Provisioning

**GAP-PLAT-OBS-04** ✅
- Criado: `domains/platform-core/app-provisioning/scripts/provisioning/provision-observability.sh`
  - Lê manifest: `observability.metrics`, `alerting`, `dashboard`, `tier`
  - Se `metrics.enabled=true`: aplica ServiceMonitor via sed do template
  - Se `alerting.enabled=true`: aplica PrometheusRule com thresholds do manifest
  - Se `dashboard.enabled=true`: aplica ConfigMap Grafana via template
  - Suporta `--dry-run`, `--env`, `--domain`
- Atualizado: `scripts/onboarding/create-app.sh` — STEP 9: "Observabilidade" chama `provision-observability.sh`

**GAP-PLAT-ING-04** ✅
- Criado: `domains/platform-core/app-provisioning/scripts/provisioning/provision-ingress.sh`
  - Lê manifest: `config.ingress.*`
  - Se `enabled=true`: aplica Ingress via sed do template com anotações ALB corretas
  - Garante IngressGroup predefinido (não cria ALB novo sem `costTier=dedicated`)
  - Suporta `--dry-run`, `--env`, `--domain`
- Atualizado: `scripts/onboarding/create-app.sh` — STEP 10: "Ingress" chama `provision-ingress.sh`

### FASE 6 — CI Validation

**GAP-PLAT-OBS-05** ✅
- Atualizado: `domains/platform-core/app-provisioning/templates/gitlab-ci-template.yml`
- Job `validate:observability` no stage `validate`:
  - Se `metrics.enabled=true`: verifica ServiceMonitor em `k8s/`
  - Verifica port no SM bate com `manifest.observability.metrics.port`
  - `allow_failure: true` (Phase 2 de observação)

**GAP-PLAT-CI-01** ✅
- Criado: `scripts/validation/validate-platform-artifacts.sh`
- Job `validate:platform-artifacts` no `gitlab-ci-template.yml`:
  - Verifica: `catalog-info.yaml`, `Dockerfile`, `k8s/kustomization.yaml`
  - Se `metricsEnabled`: verifica ServiceMonitor
  - Se `ingress.enabled`: verifica Ingress YAML

---

## Bugs de Segurança do Hatch — Corrigidos

### Bug 1 — Ingress scheme internet-facing em *.staging.internal ✅ CORRIGIDO
- Arquivo: `ETL/Hatch/k8s/overlays/staging/ingress.yaml`
- Fix: `scheme: internet-facing` → `scheme: internal` + `group.name: data-internal`

### Bug 2 — SSL Policy ausente ✅ CORRIGIDO
- Fix: adicionado `alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS13-1-2-2021-06`

### Bug 3 — WAF annotation ausente ⏳ PENDENTE (requer ARN do WAF via Terraform)
- Fix planejado: `alb.ingress.kubernetes.io/wafv2-acl-arn` via ConfigMap `platform-waf-config`
- Pré-requisito: provisionar WAF ACL no AWS via Terraform

---

## IngressGroups Predefinidos

| IngressGroup | Tipo ALB | Para quem | Regra de segurança |
|-------------|---------|-----------|-------------------|
| `data-internal` | internal | ETLs, workers, APIs de dados | scheme: internal OBRIGATÓRIO |
| `integration-internal` | internal | iPaaS, conectores B2B, webhooks | scheme: internal OBRIGATÓRIO |
| `platform-internal` | internal | Backstage, ArgoCD, GitLab | scheme: internal OBRIGATÓRIO |
| `data-public` | internet-facing | APIs B2C públicas | Requer aprovação explícita no pipeline |

**Regra global**: hosts `*.staging.internal` SEMPRE `scheme: internal`. `internet-facing` apenas com `ingressGroup: data-public` + aprovação.

---

## Tiers de Observabilidade

| Tier | Recursos gerados | Default para |
|------|-----------------|-------------|
| `minimal` | Apenas alert AppPodDown | CronJobs, batch, ferramentas internas |
| `standard` | ServiceMonitor + PrometheusRule (4 alertas) + Grafana (6 painéis) | **PADRÃO** — todos os projetos |
| `full` | standard + OTEL ativo + SLO dashboard | Serviços com SLA < 99.9% (ex: Gateway iPaaS) |

---

## Como Usar em Novos Projetos

```bash
# 1. Definir .platform/manifest.yaml com os campos de observabilidade e ingress
# 2. Provisionar observabilidade:
bash domains/platform-core/app-provisioning/scripts/provisioning/provision-observability.sh \
  --manifest .platform/manifest.yaml --dry-run

# 3. Provisionar ingress (se config.ingress.enabled=true):
bash domains/platform-core/app-provisioning/scripts/provisioning/provision-ingress.sh \
  --manifest .platform/manifest.yaml --dry-run

# 4. Remover --dry-run para aplicar
# 5. CI inclui template automaticamente:
#    include:
#      - project: 'platform-core/app-provisioning'
#        file: '/templates/gitlab-ci-template.yml'
```

---

## Impacto nos Projetos Ativos

| Projeto | Namespace | IngressGroup | Tier | Status |
|---------|-----------|-------------|------|--------|
| ETL/Hatch | staging-data-hatch-etl | data-internal | standard | ✅ Referência (atualizado) |
| ETL/VemSoft | staging-data-vemsoft-etl | data-internal | standard | ⏳ Pendente esteiramento |
| Arquitetura/iPaaS | staging-integration-ipaas | integration-internal | standard/full | ⏳ Pendente esteiramento |

---

## Arquivos Chave

| Arquivo | Propósito |
|---------|-----------|
| `schemas/v1/manifest-schema.json` | Schema com novos campos (tier, ingressGroup, etc.) |
| `templates/servicemonitor-template.yaml` | Template ServiceMonitor com placeholders |
| `templates/prometheusrule-template.yaml` | Template PrometheusRule com placeholders |
| `templates/ingress-template.yaml` | Template Ingress ALB com placeholders |
| `templates/grafana-dashboard-template.yaml` | Template ConfigMap Grafana (6 painéis) |
| `templates/ingressgroup-internal.yaml` | Manifests dos IngressGroups predefinidos |
| `scripts/provisioning/provision-observability.sh` | Script principal de observabilidade |
| `scripts/provisioning/provision-ingress.sh` | Script principal de ingress |
| `scripts/validation/validate-platform-artifacts.sh` | Validação CI de artefatos |
| `scripts/onboarding/create-app.sh` | Orquestrador (Steps 9+10 adicionados) |
| `scripts/onboarding/bootstrap-provisioner.sh` | ClusterRole RBAC (atualizado) |
| `templates/appproject-template.yaml` | AppProject ArgoCD (whitelist atualizado) |
| `templates/gitlab-ci-template.yml` | CI template (validate jobs adicionados) |

---

## Próximos Passos (H2 — Próxima Sessão)

- [ ] ArgoCD ApplicationSet de observabilidade — deploy automático de ServiceMonitors por label
- [ ] WAF: provisionar WAF ACL via Terraform e integrar annotation no ingress-template
- [ ] Replicar padrões no VemSoft (plano: `context/esteiramento/replication-plan/plano-vemsoft.md`)
- [ ] Replicar padrões no iPaaS (plano: `context/esteiramento/replication-plan/plano-ipaas.md`)
