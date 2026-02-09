# Matriz de RBAC - Domínios Corporativos

> **Versão**: 1.0
> **Data**: 2026-02-09
> **Referência**: ADR-049, GOVERNANCE.md

---

## 📋 Visão Geral

Este documento define a **matriz de RBAC** (Role-Based Access Control) para domínios corporativos, cobrindo GitLab, Kubernetes e Backstage.

**Princípio**: Cada time tem **ownership completo** do seu domínio, **read-only** nos demais (troubleshooting cross-domain).

---

## 🔐 GitLab RBAC

### Níveis de Acesso

| Nível | Permissões | Atribuído Para |
|-------|------------|----------------|
| **Owner** | Full control (manage members, delete group) | Você (Marco 0), CTO (futuro) |
| **Maintainer** | Merge, deploy, manage repo | Tech Leads de cada domínio |
| **Developer** | Push, create MR, run pipelines | Desenvolvedores |
| **Reporter** | Read-only, create issues | QA, Support, cross-domain troubleshooting |

### Matriz de Permissões GitLab

| GitLab Group | platform-team | integration-team | data-team | operations-team | shared-services-team |
|--------------|---------------|------------------|-----------|-----------------|----------------------|
| **corporate-domains/platform** | **Maintainer** | Reporter | Reporter | Reporter | Reporter |
| **corporate-domains/integration** | Reporter | **Maintainer** | Reporter | Reporter | Reporter |
| **corporate-domains/data** | Reporter | Reporter | **Maintainer** | Reporter | Reporter |
| **corporate-domains/operations** | Reporter | Reporter | Reporter | **Maintainer** | Reporter |
| **corporate-domains/shared-services** | Reporter | Reporter | Reporter | Reporter | **Maintainer** |

**Legenda**:
- **Maintainer**: Full access ao domínio (merge, deploy, manage)
- **Reporter**: Read-only (troubleshooting, learning, auditoria)

**Exceção**: `platform-team` tem **Reporter** em todos os domínios corporativos para troubleshooting de infraestrutura

---

## ☸️ Kubernetes RBAC

### ClusterRoles Definidos

```yaml
cluster-admin:
  description: Full control do cluster
  permissions: * (all verbs, all resources)
  assigned_to: platform-team APENAS

namespace-admin:
  description: Admin de namespace específico
  permissions: get, list, watch, create, update, patch, delete (all resources no namespace)
  assigned_to: Tech Leads de cada domínio

developer:
  description: Deploy, debug, logs no namespace
  permissions:
    - get, list, watch (all resources)
    - create, update, patch, delete (Deployments, Services, ConfigMaps, Secrets)
    - logs, exec (Pods)
  assigned_to: Desenvolvedores de cada domínio

viewer:
  description: Read-only no namespace
  permissions: get, list, watch (all resources)
  assigned_to: QA, Support, Management, cross-domain troubleshooting
```

### Matriz de Permissões Kubernetes

**Namespaces de Platform (Camada 1)**:

| Namespace | platform-team | integration-team | data-team | operations-team | shared-services-team |
|-----------|---------------|------------------|-----------|-----------------|----------------------|
| **shared-observability** | **namespace-admin** | viewer | viewer | viewer | viewer |
| **staging-platform-cicd** | **namespace-admin** | viewer | viewer | viewer | viewer |
| **prod-platform-cicd** | **namespace-admin** | viewer | viewer | viewer | viewer |
| **shared-secrets** | **namespace-admin** | viewer | viewer | viewer | viewer |
| **shared-security** | **namespace-admin** | viewer | viewer | viewer | viewer |

**Namespaces de Integration**:

| Namespace | platform-team | integration-team | data-team | operations-team | shared-services-team |
|-----------|---------------|------------------|-----------|-----------------|----------------------|
| **staging-integration-ipaas** | viewer | **namespace-admin** | viewer | viewer | viewer |
| **prod-integration-ipaas** | viewer | **namespace-admin** | viewer | viewer | viewer |

**Namespaces de Data**:

| Namespace | platform-team | integration-team | data-team | operations-team | shared-services-team |
|-----------|---------------|------------------|-----------|-----------------|----------------------|
| **staging-data-hatch** | viewer | viewer | **namespace-admin** | viewer | viewer |
| **prod-data-hatch** | viewer | viewer | **namespace-admin** | viewer | viewer |
| **staging-data-vemsoft** | viewer | viewer | **namespace-admin** | viewer | viewer |
| **prod-data-vemsoft** | viewer | viewer | **namespace-admin** | viewer | viewer |

**Namespaces de Operations**:

| Namespace | platform-team | integration-team | data-team | operations-team | shared-services-team |
|-----------|---------------|------------------|-----------|-----------------|----------------------|
| **staging-operations-process** | viewer | viewer | viewer | **namespace-admin** | viewer |
| **prod-operations-process** | viewer | viewer | viewer | **namespace-admin** | viewer |
| **staging-operations-fulfillment** | viewer | viewer | viewer | **namespace-admin** | viewer |
| **prod-operations-fulfillment** | viewer | viewer | viewer | **namespace-admin** | viewer |

**Namespaces de Shared Services**:

| Namespace | platform-team | integration-team | data-team | operations-team | shared-services-team |
|-----------|---------------|------------------|-----------|-----------------|----------------------|
| **staging-shared-files** | viewer | viewer | viewer | viewer | **namespace-admin** |
| **prod-shared-files** | viewer | viewer | viewer | viewer | **namespace-admin** |
| **staging-shared-notification** | viewer | viewer | viewer | viewer | **namespace-admin** |
| **prod-shared-notification** | viewer | viewer | viewer | viewer | **namespace-admin** |
| **staging-shared-calendar** | viewer | viewer | viewer | viewer | **namespace-admin** |
| **prod-shared-calendar** | viewer | viewer | viewer | viewer | **namespace-admin** |

**Legenda**:
- **namespace-admin**: Full control do namespace (create, update, delete resources)
- **viewer**: Read-only (get, list, watch)

**Exceção**: `platform-team` tem **cluster-admin** para provisionamento, upgrades e troubleshooting crítico de infraestrutura

---

## 🎭 Backstage Teams

### Teams Definidos

```yaml
platform-team:
  type: team
  profile:
    displayName: Platform Team
    description: Infraestrutura, Observabilidade, CI/CD, Security
  memberOf: [engineering]

integration-team:
  type: team
  profile:
    displayName: Integration Team
    description: iPaaS, Integrações SaaS
  memberOf: [engineering]

data-team:
  type: team
  profile:
    displayName: Data Team
    description: ETL, Data Warehouse, Analytics, Governança de Dados
  memberOf: [engineering]

operations-team:
  type: team
  profile:
    displayName: Operations Team
    description: Process Management, Fulfillment, Monitoring Operacional
  memberOf: [engineering]

shared-services-team:
  type: team
  profile:
    displayName: Shared Services Team
    description: Files, Notification, Calendar, Automation (RPA)
  memberOf: [engineering]
```

### Ownership Mapping

| Backstage Domain | Owner Team | Systems |
|------------------|------------|---------|
| **platform** | platform-team | observability, cicd, security |
| **integration** | integration-team | integration-ipaas |
| **data** | data-team | data-hatch, data-vemsoft, data-platform |
| **operations** | operations-team | operations-process, operations-fulfillment |
| **shared-services** | shared-services-team | shared-files, shared-notification, shared-calendar, shared-automation |

---

## 🔗 Integração GitLab ↔ Kubernetes via OIDC

**Fase 4**: Keycloak como Identity Provider

```yaml
Keycloak:
  realm: company-realm
  groups:
    - platform-team
    - integration-team
    - data-team
    - operations-team
    - shared-services-team

GitLab → Keycloak:
  - GitLab Groups espelhados em Keycloak Groups
  - SSO para GitLab via Keycloak

Kubernetes → Keycloak:
  - kube-apiserver configurado com OIDC
  - Groups mapeados para Kubernetes Groups
  - RoleBindings referenciam Keycloak Groups
```

**kube-apiserver OIDC Config**:
```yaml
apiServer:
  oidc:
    issuerURL: https://keycloak.company.com/realms/company-realm
    clientID: kubernetes
    usernameClaim: preferred_username
    groupsClaim: groups
    groupsPrefix: "keycloak:"
```

**RoleBinding com Keycloak Groups**:
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: integration-team-admin
  namespace: staging-integration-ipaas
subjects:
- kind: Group
  name: keycloak:integration-team
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: namespace-admin
  apiGroup: rbac.authorization.k8s.io
```

---

## 📊 Validação de RBAC

### Script de Auditoria

```bash
#!/bin/bash
# /scripts/governance/audit-rbac.sh

echo "=== Auditoria de RBAC ==="

# 1. GitLab: Listar permissões por grupo
echo "## GitLab RBAC:"
for domain in platform integration data operations shared-services; do
  echo "Grupo: corporate-domains/$domain"
  gitlab group members list --group-id "corporate-domains/$domain" --format table
done

# 2. Kubernetes: Listar RoleBindings por namespace
echo "## Kubernetes RBAC:"
for ns in $(kubectl get ns -o name | grep -E 'staging-|prod-|shared-'); do
  echo "Namespace: $ns"
  kubectl get rolebinding -n $ns -o json | jq -r '.items[] | "\(.metadata.name): \(.subjects[].name) -> \(.roleRef.name)"'
done

# 3. Validar que cada namespace tem owner label
echo "## Namespaces sem owner label:"
kubectl get ns -o json | jq -r '.items[] | select(.metadata.labels.owner == null) | .metadata.name'
```

### Métricas de Conformidade

- ✅ 100% dos grupos GitLab com RBAC configurado
- ✅ 100% dos namespaces com RoleBindings
- ✅ 100% dos namespaces com label `owner`
- ✅ 0 violações de princípio "1 time = 1 domínio"

---

## 📚 Referências

- [ADR-049: Governança e RBAC](../adr/adr-049-governanca-rbac-dominios-corporativos.md)
- [GOVERNANCE.md](./GOVERNANCE.md)
- [Kubernetes RBAC Documentation](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [GitLab Permissions](https://docs.gitlab.com/ee/user/permissions.html)
