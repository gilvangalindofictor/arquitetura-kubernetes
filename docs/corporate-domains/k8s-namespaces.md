# Estratégia de Namespaces Kubernetes

> **Versão**: 1.0 | **Data**: 2026-02-09 | **Referência**: ADR-047, ADR-048

## 📛 Convenção de Naming

**Formato**: `{environment}-{domain}-{product}`

**Regex**: `^(dev|staging|prod|shared)-(platform|integration|data|operations|shared)(-[a-z0-9-]+)?$`

## 📊 Mapeamento GitLab → Kubernetes

| GitLab Group | Namespace (Staging) | Namespace (Prod) | Ownership |
|--------------|---------------------|------------------|-----------|
| **integration/*** | `staging-integration-ipaas` | `prod-integration-ipaas` | Integration Team |
| **data/hatch/*** | `staging-data-hatch` | `prod-data-hatch` | Data Team |
| **data/vemsoft/*** | `staging-data-vemsoft` | `prod-data-vemsoft` | Data Team |
| **shared-services/files/*** | `staging-shared-files` | `prod-shared-files` | Shared Services Team |
| **shared-services/notification/*** | `staging-shared-notification` | `prod-shared-notification` | Shared Services Team |
| **operations/process/*** | `staging-operations-process` | `prod-operations-process` | Operations Team |

## 🏗️ Estrutura de Namespace (Exemplo: Integration)

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: staging-integration-ipaas
  labels:
    name: staging-integration-ipaas
    environment: staging
    domain: integration
    owner: integration-team
    cost-center: engineering
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: staging-quota
  namespace: staging-integration-ipaas
spec:
  hard:
    requests.cpu: "8"
    requests.memory: 16Gi
    limits.cpu: "16"
    limits.memory: 32Gi
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: staging-integration-ipaas
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

## 🔐 RBAC por Namespace

**RoleBinding (namespace-admin)**:
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: integration-team-admin
  namespace: staging-integration-ipaas
subjects:
- kind: Group
  name: integration-team
roleRef:
  kind: ClusterRole
  name: namespace-admin
```

## 📚 Referências

- [RBAC Matrix](../governance/rbac-matrix.md)
- [Naming Conventions](../governance/naming-conventions.md)
- [GOVERNANCE.md](../governance/GOVERNANCE.md)
