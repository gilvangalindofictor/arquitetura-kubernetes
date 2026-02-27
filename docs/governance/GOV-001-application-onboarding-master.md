# GOV-001: Application Onboarding Master Guide

> **Versão**: 1.0
> **Data**: 2026-02-27
> **Status**: Ativo
> **Referências**: ADR-047, ADR-048, ADR-049, GOVERNANCE.md
> **Audiência**: Desenvolvedores, Tech Leads, Platform Team

---

## Visão Geral

Guia consolidado para **onboarding de novas aplicações** na Plataforma Kubernetes.
Unifica naming conventions, provisionamento de recursos, CI/CD, observabilidade e segurança.

**Documentos Complementares**:
- [application-onboarding.md](./application-onboarding.md) — Processo detalhado (passo a passo)
- [argocd-applicationset-onboarding.md](./argocd-applicationset-onboarding.md) — GitOps onboarding
- [naming-conventions.md](./naming-conventions.md) — Naming conventions completas
- [rbac-matrix.md](./rbac-matrix.md) — Matriz RBAC

---

## Checklist de Onboarding

### Fase 1: Planejamento

| # | Tarefa | Responsável | Referência |
|---|--------|-------------|------------|
| 1 | Definir domínio corporativo (platform/integration/data/operations/shared-services) | Product Owner | ADR-047 |
| 2 | Definir nome do produto (kebab-case) | Tech Lead | ADR-048 |
| 3 | Validar naming contra regex: `^[a-z0-9-]+$` | Automatizado | naming-conventions.md |
| 4 | Definir recursos necessários (PostgreSQL, Redis, RabbitMQ) | Tech Lead | GOV-002/003/004 |
| 5 | Definir requisitos de autenticação (Keycloak client) | Tech Lead | GOV-005 |

### Fase 2: Provisionamento de Infraestrutura

| # | Tarefa | Responsável | Referência |
|---|--------|-------------|------------|
| 6 | Criar namespace Kubernetes: `{env}-{domain}-{produto}` | Platform Team | GOVERNANCE.md |
| 7 | Provisionar database PostgreSQL (se necessário) | Platform Team | GOV-002, ADR-060 |
| 8 | Provisionar Redis instance (se necessário) | Platform Team | GOV-003, ADR-061 |
| 9 | Provisionar RabbitMQ cluster (se necessário) | Platform Team | GOV-004, ADR-062 |
| 10 | Criar secrets no Vault + ExternalSecrets | Platform Team | GOV-006 |
| 11 | Criar Keycloak client OIDC (se necessário) | Platform Team | GOV-005 |

### Fase 3: CI/CD e GitOps

| # | Tarefa | Responsável | Referência |
|---|--------|-------------|------------|
| 12 | Criar repositório GitLab: `corporate-domains/{domain}/{produto}` | Tech Lead | ADR-048 |
| 13 | Configurar `.gitlab-ci.yml` com security template | Desenvolvedor | GOV-009, CICD-001 |
| 14 | Criar Helm chart com labels obrigatórias | Desenvolvedor | GOVERNANCE.md |
| 15 | Criar ArgoCD ApplicationSet entry | Platform Team | GOV-007 |
| 16 | Validar pipeline: SAST/DAST/Trivy/TruffleHog | CI/CD | GOV-009 |

### Fase 4: Observabilidade

| # | Tarefa | Responsável | Referência |
|---|--------|-------------|------------|
| 17 | Instrumentar com OpenTelemetry (métricas, logs, traces) | Desenvolvedor | GOV-008 |
| 18 | Criar ServiceMonitor para Prometheus | Desenvolvedor | GOV-008 |
| 19 | Configurar alertas no Grafana | Platform Team | GOV-008 |
| 20 | Validar logs no Loki (formato JSON estruturado) | Desenvolvedor | GOV-008 |

### Fase 5: Segurança e Rede

| # | Tarefa | Responsável | Referência |
|---|--------|-------------|------------|
| 21 | Criar NetworkPolicies (least-privilege) | Platform Team | GOV-010 |
| 22 | Validar TLS/HTTPS em ingress | Platform Team | GOV-010 |
| 23 | Registrar no Backstage catalog | Desenvolvedor | GOV-011 |

---

## Labels Kubernetes Obrigatórias

Toda aplicação DEVE ter os seguintes labels (validados via Kyverno):

```yaml
metadata:
  labels:
    # Obrigatórias (Kyverno enforce)
    app.kubernetes.io/name: "{produto}"
    app.kubernetes.io/part-of: "{domain}-{produto}"
    app.kubernetes.io/managed-by: "argocd"
    domain: "{domain}"
    owner: "{domain}-team"

    # Recomendadas (FinOps)
    app.kubernetes.io/version: "v1.0.0"
    cost-center: "{domain}"

  annotations:
    # Backstage integration
    backstage.io/kubernetes-id: "{domain}-{produto}"
    backstage.io/domain: "{domain}"
```

**Validação**:
```bash
# Verificar labels obrigatórias
kubectl get pods -n {namespace} -o jsonpath='{.items[*].metadata.labels}' | jq
```

---

## Namespace Naming

```yaml
Formato: {env}-{domain}-{produto}
Regex: ^(staging|prod)-(platform|integration|data|operations|shared-services)-[a-z0-9-]+$

Exemplos Válidos:
✅ staging-data-rpa-exemplo
✅ prod-integration-ipaas
✅ staging-shared-services-files

Exemplos Inválidos:
❌ rpa-exemplo              # Falta env e domain
❌ staging-rpa-exemplo      # Falta domain
❌ Staging-Data-Rpa         # Uppercase não permitido
```

---

## Quick Reference: Naming por Recurso

| Recurso | Formato | Exemplo |
|---------|---------|---------|
| **Namespace** | `{env}-{domain}-{produto}` | `staging-data-rpa-exemplo` |
| **GitLab Repo** | `corporate-domains/{domain}/{produto}` | `corporate-domains/data/rpa-exemplo` |
| **Helm Release** | `{produto}` | `rpa-exemplo` |
| **PostgreSQL DB** | `{produto}` (snake_case) | `rpa_exemplo` |
| **Redis CR** | `{produto}-redis` | `rpa-exemplo-redis` |
| **RabbitMQ CR** | `{produto}-rabbitmq` | `rpa-exemplo-rabbitmq` |
| **Vault Path** | `secret/{domain}/{produto}/*` | `secret/data/rpa-exemplo/db-password` |
| **Backstage Component** | `{produto}` | `rpa-exemplo` |

---

## Referências

- [application-onboarding.md](./application-onboarding.md) — Processo detalhado
- [GOVERNANCE.md](./GOVERNANCE.md) — Governança geral
- [naming-conventions.md](./naming-conventions.md) — Naming conventions completas
- [ADR-047: Estrutura Corporativa](../adr/adr-047-estrutura-corporativa-dominios.md)
- [ADR-048: Naming Conventions](../adr/adr-048-naming-conventions-deterministicas.md)
- [ADR-049: RBAC Governança](../adr/adr-049-governanca-rbac-dominios-corporativos.md)
