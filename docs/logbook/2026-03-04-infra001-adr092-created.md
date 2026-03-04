# Logbook — INFRA-001: ADR-092 Criado (Documentation Closure)

**Data:** 2026-03-04
**Agente:** Documentation Specialist
**Demanda:** INFRA-001 — GitLab Helm Chart Upgrade
**Duracao estimada:** ~30min
**Status:** INFRA-001 100% COMPLETO

---

## Contexto

INFRA-001 estava com 9/9 steps de upgrade completos (v17.7.0 → v18.9.1, Rev 36, 11/11 pods Running)
desde 2026-03-03, porem com um item pendente de documentacao:

```
- [ ] ADR-092: GitLab Version Upgrade Strategy (documentacao pendente)
```

Esta sessao encerra o INFRA-001 com a criacao do ADR-092.

---

## Artefatos Criados/Modificados

### Criados

| Arquivo | Conteudo | Linhas |
|---------|----------|--------|
| `docs/adr/adr-092-gitlab-version-upgrade-strategy.md` | ADR completo com 9 breaking changes, 3 runner fixes, upgrade path, procedimento padrao | ~270 |
| `docs/logbook/2026-03-04-infra001-adr092-created.md` | Este arquivo | ~80 |

### Modificados

| Arquivo | Mudanca |
|---------|---------|
| `docs/demands-backlog.md` | ADR-092 marcado como `[x]` (linha 1884) |

---

## Conteudo do ADR-092

**Secoes documentadas:**

1. **Contexto** — Motivacao do upgrade (14 meses defasado, security patches, PG16 prerequisite)
2. **Constraint** — Sequential upgrade obrigatorio (impossivel pular minor versions)
3. **Decisao** — Helm Sequential Upgrade com Breaking Change Registry
4. **Upgrade Path** — 9 steps executados (table completa com revisions, status, observacoes)
5. **Breaking Changes Registry** — 9 BCs com sintoma, root cause, fix aplicado, versao afetada:
   - BC-001: `relativeUrlRoot` nil → `%!s(<nil>)` em KAS URI (chart 9.5.x)
   - BC-002: `global.openbao.enabled` — HashiCorp Vault substituido por OpenBao (18.x)
   - BC-003: `global.workspaces.enabled` — novo subchart (18.x)
   - BC-004: `global.gatewayApi.enabled` — nil pointer httproute.yaml (chart 9.8.x)
   - BC-005: `gatewayRef.name/namespace` — obrigatorio mesmo disabled (chart 9.9.x)
   - BC-006: `gatewayApi.class.name` — template requer valor (chart 9.9.x)
   - BC-007: `appConfig.cell.enabled` — chart 8.10.x (17.10.x)
   - BC-008: `appConfig.oidcProvider.*` — obrigatorio no chart 8.11.x (17.11.x)
   - BC-009: `appConfig.ciIdTokens.issuerUrl` — explicito no 18.x
6. **Runner Configuration** — 3 root causes (isAuthToken, porta 8181, gitlabVersion stuck)
7. **Incidentes** — 3 incidentes durante o upgrade com resolucao documentada
8. **Procedimento Padrao** — Checklist pre-upgrade, comando template, validacao, rollback
9. **Licoes Aprendidas** — 8 aprendizados criticos para proximos upgrades
10. **Consequencias** — Positivas, negativas, riscos residuais

---

## Estado Final INFRA-001

```
INFRA-001: GitLab Helm Chart Upgrade
Status: 100% COMPLETO

Upgrade: v17.7.0 (chart 8.7.0) → v18.9.1 (chart 9.9.1)
Steps: 9/9 executados (1 skip confirmado: chart 9.8.x bug)
Breaking Changes: 9/9 descobertos e resolvidos
Revision: 36
Pods: 11/11 Running (2026-03-03)

Documentacao:
- [x] Logbook upgrade: docs/logbook/2026-03-02-infra-001-gitlab-upgrade.md
- [x] ADR-092: docs/adr/adr-092-gitlab-version-upgrade-strategy.md
- [x] demands-backlog.md: INFRA-001 secao 100% completa
```

---

## Verificacao

```bash
# Confirmar estado atual do GitLab
helm list -n gitlab-staging
# Expected: gitlab | gitlab-staging | 36 | deployed | gitlab-9.9.1 | v18.9.1

kubectl get pods -n gitlab-staging
# Expected: 11/11 Running
```

---

## Referencias

- ADR criado: `docs/adr/adr-092-gitlab-version-upgrade-strategy.md`
- Logbook completo: `docs/logbook/2026-03-02-infra-001-gitlab-upgrade.md`
- Demanda: `docs/demands-backlog.md` — secao INFRA-001 (linha ~1795)
- Values file: `platform-provisioning/aws/kubernetes/terraform/modules/gitlab/values-staging-working.yaml`
