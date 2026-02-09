# Backstage Standards - Domínios Corporativos

> **Versão**: 1.0 | **Data**: 2026-02-09 | **Fase**: 4 (Preparação desde Marco 0)

## 📋 Estrutura de catalog-info.yaml

### Template Completo (Domain + System + Component)

```yaml
# /corporate-domains/integration/ipaas-bff-rest/catalog-info.yaml

apiVersion: backstage.io/v1alpha1
kind: Domain
metadata:
  name: integration
  description: Domínio de Integrações - iPaaS
  tags: [integration, ipaas, saas]
spec:
  owner: integration-team

---
apiVersion: backstage.io/v1alpha1
kind: System
metadata:
  name: integration-ipaas
  description: iPaaS - Integration Platform as a Service
  tags: [integration, microservices]
  annotations:
    backstage.io/source-location: url:https://gitlab.company.com/corporate-domains/integration
spec:
  owner: integration-team
  domain: integration

---
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: ipaas-bff-rest
  description: iPaaS REST BFF
  tags: [api, rest, golang]
  annotations:
    backstage.io/kubernetes-label-selector: "app.kubernetes.io/name=ipaas-bff-rest"
    backstage.io/source-location: url:https://gitlab.company.com/corporate-domains/integration/ipaas-bff-rest
spec:
  type: service
  lifecycle: production
  owner: integration-team
  system: integration-ipaas
  providesApis: [ipaas-rest-api]
  dependsOn: [component:ipaas-orchestrator, resource:postgres-ipaas]
```

### Naming Standards

| Entity | Naming Pattern | Exemplo |
|--------|----------------|---------|
| **Domain** | `^(platform\|integration\|data\|operations\|shared-services)$` | `integration` |
| **System** | `^[a-z0-9-]+-[a-z0-9-]+$` | `integration-ipaas` |
| **Component** | `^[a-z0-9-]+$` | `ipaas-bff-rest` |
| **API** | `^[a-z0-9-]+-api$` | `ipaas-rest-api` |
| **Resource** | `^(postgres\|redis\|rabbitmq)-[a-z0-9-]+$` | `postgres-ipaas` |

### Labels Obrigatórias em Kubernetes (Backstage-Compatible)

```yaml
labels:
  app.kubernetes.io/part-of: integration-ipaas   # System
  domain: integration                             # Domain
  owner: integration-team                         # Ownership

annotations:
  backstage.io/kubernetes-id: integration-ipaas
  backstage.io/domain: integration
```

## 📚 Referências

- [GOVERNANCE.md](./GOVERNANCE.md)
- [Backstage System Model](https://backstage.io/docs/features/software-catalog/system-model)
