# ADR-015: Multi-Tenancy

## Status
Aceito

## Contexto
Suporte a múltiplas equipes/tenants dentro da plataforma, com isolamento adequado sem comprometer eficiência.

## Decisão
Implementamos multi-tenancy via namespaces por equipe, com resource quotas, network isolation e RBAC granular.

## Consequências
- **Positivo**: Suporte a múltiplas equipes, governança clara
- **Negativo**: Complexidade de gerenciamento
- **Riscos**: Resource contention, security breaches
- **Mitigação**: Quotas enforcement, monitoring contínuo

## Implementação
- **Namespaces**: Por equipe/projeto
- **Resource Quotas**: CPU/memory/storage limits
- **Network Policies**: Isolation entre tenants
- **RBAC**: Roles por tenant, cluster-wide controls
- **Cost Allocation**: Tags para FinOps

## Estrutura de Tenant
```
k8s-team-{team-name}/
├── apps/          # Aplicações do tenant
├── config/        # ConfigMaps/Secrets
├── policies/      # Network/RBAC policies
└── monitoring/    # Dashboards específicos
```

## Validação
- Resource usage per tenant
- Security isolation testing
- Cost allocation accuracy

## Referências
- [Kubernetes Multi-Tenancy](https://kubernetes.io/docs/concepts/security/multi-tenancy/)
- [Resource Quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/)

Data: 2025-12-30</content>
<parameter name="filePath">\\wsl.localhost\Ubuntu\home\gilvangalindo\projects\Arquitetura\Kubernetes\SAD\docs\adrs\adr-015-multi-tenancy.md