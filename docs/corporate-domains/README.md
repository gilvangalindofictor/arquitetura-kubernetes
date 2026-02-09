# Domínios Corporativos - Visão Geral

> **Versão**: 1.0 | **Data**: 2026-02-09 | **Referência**: ADR-047

## 🏢 5 Domínios Corporativos

Organização por **produtos/linhas de negócio** (Domain-Driven Design), não por categorias técnicas.

| Domínio | Produtos | Ownership | Status |
|---------|----------|-----------|--------|
| **PLATFORM** | Observability, CI/CD, Secrets, Security | Platform Team | ✅ Operacional (Camada 1) |
| **INTEGRATION** | iPaaS (9 microserviços) | Integration Team | 📋 Fase 1 (4 semanas) |
| **DATA** | Hatch ETL, VemSoft ETL, Data Platform | Data Team | 📋 Fase 2 (4 semanas) |
| **OPERATIONS** | Process Management, Fulfillment | Operations Team | 📋 Fase 3 (6 semanas) |
| **SHARED-SERVICES** | Files, Notification, Calendar, RPA | Shared Services Team | 📋 Fase 1 (4 semanas) |

## 📁 Estrutura de Diretórios (GitLab)

```
/corporate-domains/
├── platform/           # Infraestrutura (herda Camada 1)
├── integration/        # iPaaS
├── data/              # ETL Hatch, VemSoft
├── operations/        # Process, Fulfillment
└── shared-services/   # Files, Notification, Calendar, RPA
```

## 🔗 Documentação Detalhada

- [Estrutura GitLab](./gitlab-structure.md)
- [Estratégia de Namespaces Kubernetes](./k8s-namespaces.md)
- [Governança](../governance/GOVERNANCE.md)
- [ADR-047: Estrutura Corporativa](../adr/adr-047-estrutura-corporativa-dominios.md)
