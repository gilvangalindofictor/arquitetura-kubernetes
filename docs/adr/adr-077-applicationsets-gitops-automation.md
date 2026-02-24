# DEC-077 — ArgoCD ApplicationSets: GitOps Automation (GAP-006)

**Status:** Accepted  
**Date:** 2026-02-24  
**Gap:** GAP-006 — GitOps Automation Gap  
**Deciders:** Platform Team  
**Implemented by:** Agente Executor GAP-006

---

## Contexto

Applications ArgoCD eram criados manualmente via UI ou CLI (`argocd app create`), sem template
e sem automação. Problemas identificados:

- Onboarding de novos serviços: manual, lento, propenso a erros de configuração
- Ausência de padrão cross-environment (staging ≠ production em sync policy, labels, etc.)
- Impossibilidade de auditar "quem criou qual Application e quando"
- Sem capacidade de detectar drift entre Applications existentes

**ArgoCD versão:** v2.10.0  
**ApplicationSet Controller:** disponível (2 réplicas ativas)

---

## Decisão

Implementar **ArgoCD ApplicationSets** com dois generators complementares:

### 1. Git Directory Generator — `cluster-services`

**Arquivo:** `argocd/applicationsets/cluster-services.yaml`

Escaneia o repositório Git em `apps/staging/*/*/app.yaml`. Cada subdiretório com `app.yaml`
dispara a criação automática de um ArgoCD Application.

```
apps/
  staging/
    monitoring/
      grafana/        ← app.yaml → Application: staging-monitoring-grafana
      loki/           ← app.yaml → Application: staging-monitoring-loki
    security/
      vault/          ← app.yaml → Application: staging-security-vault
    platform/
      harbor/         ← app.yaml → Application: staging-platform-harbor
```

**Naming:** `staging-<domain>-<service>` (path segments [2] e [3])

**Zero-touch onboarding:**
```bash
mkdir apps/staging/platform/my-service
touch apps/staging/platform/my-service/app.yaml
git add . && git push
# ~3 minutos → Application criado automaticamente
```

### 2. Matrix Generator — `multi-env-services`

**Arquivo:** `argocd/applicationsets/multi-env-services.yaml`

Produto cartesiano de `environments × services`. Permite declarar um novo serviço uma vez
e ele é deployado em todos os environments configurados.

```yaml
environments: [staging]   # production descomentado quando cluster provisionado
services:    [grafana, vault, keycloak, harbor, kyverno, rabbitmq, redis]
# Gera: 7 Applications × 1 env = 7 Applications
```

**Nomenclatura:** `<environment>-<service>` (ex: `staging-grafana`)

---

## Estrutura de Diretórios

```
apps/
├── staging/
│   ├── monitoring/   grafana | loki | tempo
│   ├── security/     vault | keycloak
│   ├── platform/     harbor | argocd | new-service (teste)
│   ├── data/         rabbitmq | redis
│   └── governance/   kyverno
└── production/       (reservado — espelha staging quando provisionado)
    ├── monitoring/
    ├── security/
    ├── data/
    └── platform/
argocd/
└── applicationsets/
    ├── cluster-services.yaml     (Git Directory Generator)
    └── multi-env-services.yaml   (Matrix Generator)
```

---

## Convenções Obrigatórias

| Item | Convenção |
|------|-----------|
| Nome de Application | `<env>-<domain>-<service>` (cluster-services) ou `<env>-<service>` (multi-env) |
| `app.yaml` | Obrigatório em cada diretório de serviço |
| Labels | `environment`, `domain`, `service`, `app.kubernetes.io/managed-by: applicationset` |
| Sync policy | `automated: prune: true, selfHeal: true` |
| CreateNamespace | Habilitado via syncOptions |
| ServerSideApply | Habilitado — evita field manager conflicts |

---

## Consequências

**Positivas:**
- Zero-touch onboarding: `mkdir + app.yaml + git push` → Application em ~3min
- Consistência garantida por template (sync policy, labels, annotations idênticos)
- Auditoria completa via Git history
- Multi-environment trivial: adicionar `production` na lista de environments
- Elimina GAP-006 inteiramente

**Negativas / Trade-offs:**
- Equipes precisam conhecer a convenção de diretórios (`apps/<env>/<domain>/<service>`)
- Applications órfãos (se `app.yaml` removido por engano) são pruned automaticamente
- Repo Git deve estar acessível pelo ArgoCD repo-server sem credenciais (ou configurar Secret)

---

## Validação

```bash
# ApplicationSets criados
kubectl get applicationset -n argocd
# NAME                 AGE
# cluster-services     Xs
# multi-env-services   Xs

# Applications auto-gerados (multi-env-services)
kubectl get applications -n argocd -l app.kubernetes.io/managed-by=applicationset
# staging-grafana, staging-vault, staging-keycloak, staging-harbor,
# staging-kyverno, staging-rabbitmq, staging-redis → 7 Applications

# Teste auto-discovery (cluster-services)
# Após git push com apps/staging/platform/new-service/app.yaml:
kubectl get application staging-platform-new-service -n argocd
```

---

## Referências

- [ArgoCD ApplicationSet v2.10 docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/)
- [Git Generator](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Git/)
- [Matrix Generator](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Matrix/)
- GAP-006 demanda original: `docs/demands/`
- Logbook: `docs/logbooks/2026-02-24-gap006-applicationsets.md`
