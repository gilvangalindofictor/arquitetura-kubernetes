# Sumário Executivo — Sessão 2026-03-02

## Demandas Executadas

| Demanda | Status | Entregáveis |
| ------- | ------ | ----------- |
| GAP-007 | ✅ COMPLETO | Kyverno enforcement mode ativado (3 policies) |
| CICD-001 | ✅ COMPLETO | Harbor Trivy blocking + SonarQube gate = 100% |
| CICD-002 | ✅ COMPLETO | Quality Gate configurado |
| CICD-004 | ✅ COMPLETO | Imutable tags + Harbor OIDC auth fixes |
| INFRA-001 | ⚠️ 4/5 STEPS | GitLab 17.7→17.11.7 (bloqueado em 18.x: PostgreSQL 16 required) |

## Bloqueadores Identificados

| ID | Tipo | Descrição | Impacto |
| -- | ---- | --------- | ------- |
| INFRA-002 | Infra | PostgreSQL 14 → 16 upgrade | Bloqueia GitLab 18.x |

## Fixes Técnicos Aplicados (6 bugs resolvidos)

1. Runner REGISTER_LOCKED: `runnerRegistrationToken: ""` nas helm values → isAuthToken=true
2. Runner CI_SERVER_URL: porta 80 → 8181 (workhorse, nginx-ingress desabilitado)
3. GitLab 8.10.x: `global.appConfig.cell.enabled=false` obrigatório
4. GitLab 8.11.x: `global.appConfig.oidcProvider.openidIdTokenExpireInSeconds=120` obrigatório
5. Upgrade-check job stale: `kubectl delete job` antes de cada retry
6. Images stuck: `--set global.gitlabVersion=X.Y.Z` explícito em cada upgrade step

## Health Check Final

- **GitLab:** v17.11.7 (chart 8.11.8) — Running ✅
- **Runner:** 1/1 Running, registrado ✅
- **Harbor Trivy:** Enabled, 5 projetos com blocking HIGH ✅
- **Kyverno:** Enforcement mode ativo (3 ClusterPolicies) ✅
- **PostgreSQL:** 14.8.0 (upgrade para 16 pendente — INFRA-002)
