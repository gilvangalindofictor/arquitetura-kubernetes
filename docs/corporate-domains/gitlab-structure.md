# Estrutura GitLab - Domínios Corporativos

> **Versão**: 1.0 | **Data**: 2026-02-09 | **Referência**: ADR-047, ADR-048

## 📂 Hierarquia de Grupos

```
/corporate-domains/
│
├─ platform/
│  ├─ observability/
│  ├─ cicd/
│  ├─ security/
│  └─ infrastructure/
│
├─ integration/
│  ├─ ipaas-bff-rest
│  ├─ ipaas-bff-grpc
│  ├─ ipaas-orchestrator
│  ├─ ipaas-helm-charts
│  └─ ipaas-gitops
│
├─ data/
│  ├─ hatch/
│  │  ├─ hatch-etl
│  │  ├─ hatch-api-gateway
│  │  ├─ hatch-web
│  │  └─ hatch-gitops
│  └─ vemsoft/
│     ├─ vemsoft-etl
│     └─ vemsoft-gitops
│
├─ operations/
│  ├─ process-management/
│  └─ fulfillment/
│
└─ shared-services/
   ├─ files/
   │  ├─ bucketconnector
   │  ├─ file-generator-pdf
   │  └─ files-gitops
   ├─ notification/
   │  ├─ notification-gateway
   │  └─ notification-gitops
   └─ calendar/
      ├─ calendar-api
      └─ calendar-gitops
```

## 🔐 RBAC por Domínio

| Team | Access Level | Domains |
|------|-------------|---------|
| **integration-team** | Maintainer | `corporate-domains/integration/*` |
| **data-team** | Maintainer | `corporate-domains/data/*` |
| **operations-team** | Maintainer | `corporate-domains/operations/*` |
| **shared-services-team** | Maintainer | `corporate-domains/shared-services/*` |
| **platform-team** | Maintainer | `corporate-domains/platform/*` + Reporter (todos os demais) |

## 📛 Naming Convention

**Formato**: `corporate-domains/{domain}/{product-or-service}`

**Regex**: `^corporate-domains/(platform|integration|data|operations|shared-services)/[a-z0-9-]+(/[a-z0-9-]+)*$`

## 📚 Referências

- [Naming Conventions](../governance/naming-conventions.md)
- [RBAC Matrix](../governance/rbac-matrix.md)
