# GOV-007: ArgoCD GitOps Governance & Best Practices

> **Versão**: 1.0
> **Data**: 2026-02-27
> **Status**: Ativo
> **Referências**: ADR-077, ADR-085
> **Audiência**: Desenvolvedores, Platform Team

---

## Visão Geral

ArgoCD é a plataforma GitOps para deployment contínuo. Toda aplicação é deployada via ArgoCD ApplicationSets com reconciliação automática contra o repositório Git.

**Princípio**: Git é a single source of truth. Nenhum `kubectl apply` manual é permitido.

---

## Arquitetura

```
┌────────────┐     ┌──────────────┐     ┌──────────────────┐
│ GitLab Repo│────>│ ArgoCD       │────>│ Kubernetes       │
│ (Helm/K8s) │     │ ApplicationSet│    │ Cluster (EKS)    │
│            │     │ auto-sync    │     │                  │
└────────────┘     └──────────────┘     └──────────────────┘
```

**Decisão**: ApplicationSets para automação — [ADR-077](../adr/adr-077-applicationsets-gitops-automation.md).

---

## Naming Conventions

### ArgoCD Applications

```yaml
Formato: {env}-{domain}-{produto}
Regex: ^(staging|prod)-(platform|integration|data|operations|shared-services)-[a-z0-9-]+$

Exemplos:
✅ staging-data-rpa-exemplo
✅ prod-integration-ipaas
✅ staging-platform-observability

❌ rpa-exemplo               # Falta env e domain
❌ Staging-Data-Rpa          # Uppercase proibido
```

### ArgoCD Projects

```yaml
Formato: {domain}
Exemplos:
✅ platform
✅ integration
✅ data
✅ operations
✅ shared-services
```

---

## ApplicationSet Template

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: {domain}-apps
  namespace: argocd
spec:
  generators:
    - git:
        repoURL: https://gitlab.{company}/corporate-domains/{domain}.git
        revision: HEAD
        directories:
          - path: "apps/*"
  template:
    metadata:
      name: "staging-{domain}-{{path.basename}}"
      labels:
        domain: {domain}
        managed-by: applicationset
    spec:
      project: {domain}
      source:
        repoURL: https://gitlab.{company}/corporate-domains/{domain}.git
        targetRevision: HEAD
        path: "{{path}}"
        helm:
          valueFiles:
            - values-staging.yaml
      destination:
        server: https://kubernetes.default.svc
        namespace: "staging-{domain}-{{path.basename}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
          - ApplyOutOfSyncOnly=true
```

**Referência detalhada**: [ArgoCD ApplicationSet Onboarding](./argocd-applicationset-onboarding.md)

---

## Sync Policies

### Staging

```yaml
syncPolicy:
  automated:
    prune: true       # Remove recursos deletados do Git
    selfHeal: true    # Reverte mudanças manuais
  retry:
    limit: 3
    backoff:
      duration: 5s
      maxDuration: 3m
      factor: 2
```

### Production

```yaml
syncPolicy:
  automated:
    prune: false      # Não prune automaticamente (safety)
    selfHeal: true    # Revert manual changes
  syncOptions:
    - ApplyOutOfSyncOnly=true
    - Validate=true
```

**Regra**: Production deploys requerem sync manual ou aprovação via CI/CD.

---

## Progressive Delivery (Argo Rollouts)

**Decisão**: [ADR-085: Argo Rollouts Progressive Delivery](../adr/adr-085-argo-rollouts-progressive-delivery.md)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: {produto}
spec:
  strategy:
    canary:
      steps:
        - setWeight: 10          # 10% traffic
        - pause: { duration: 5m }
        - setWeight: 30          # 30% traffic
        - pause: { duration: 5m }
        - setWeight: 60          # 60% traffic
        - pause: { duration: 5m }
```

---

## RBAC (ArgoCD)

| Role | Permissões | Atribuído Para |
|------|-----------|----------------|
| `admin` | Full access (all projects) | platform-admins (Keycloak) |
| `proj:{domain}:admin` | Full access (domain project) | {domain}-leads |
| `proj:{domain}:read-only` | View-only (domain project) | {domain}-devs |
| `read-only` | View-only (all projects) | viewers |

---

## Proibições

```yaml
NUNCA:
  - kubectl apply manual em staging/prod
  - Modificar recursos gerenciados por ArgoCD diretamente
  - Desabilitar selfHeal em production
  - Deploy sem passar pelo pipeline CI/CD
  - Usar latest tag em container images (ADR-084)

SEMPRE:
  - Git como source of truth
  - Immutable image tags (SHA ou semver)
  - Sync via ArgoCD (automated ou manual)
  - Labels obrigatórias nos manifests
```

---

## Monitoring

| Métrica | Alerta | Threshold |
|---------|--------|-----------|
| App sync status | `ArgoCDAppOutOfSync` | OutOfSync > 15min |
| App health | `ArgoCDAppDegraded` | Degraded > 5min |
| Sync failures | `ArgoCDSyncFailed` | > 3 consecutive failures |
| Controller lag | `ArgoCDControllerLag` | > 60s |

---

## Best Practices

1. **Immutable tags**: Nunca usar `latest` — usar SHA digest ou semver (ADR-084)
2. **Values por environment**: `values-staging.yaml`, `values-prod.yaml`
3. **Helm charts versionados**: Chart.yaml version semântica
4. **Wave annotations**: Usar `argocd.argoproj.io/sync-wave` para ordenar deploys
5. **Health checks**: Configurar `readinessProbe` e `livenessProbe` em todos os pods
6. **Resource limits**: Sempre definir `requests` e `limits` (CPU/memory)

---

## Referências

- [ADR-077: ApplicationSets GitOps Automation](../adr/adr-077-applicationsets-gitops-automation.md)
- [ADR-084: Immutable Image Tags](../adr/adr-084-immutable-image-tags-enforcement.md)
- [ADR-085: Argo Rollouts Progressive Delivery](../adr/adr-085-argo-rollouts-progressive-delivery.md)
- [ArgoCD ApplicationSet Onboarding](./argocd-applicationset-onboarding.md)
- [ApplicationSets QUICKSTART](../../domains/cicd-platform/infra/argocd/applicationsets/QUICKSTART.md)
