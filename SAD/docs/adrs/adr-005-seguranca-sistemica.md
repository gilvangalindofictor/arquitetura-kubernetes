# ADR-005: Segurança Sistêmica

## Status
Aceito

## Contexto
Segurança deve ser incorporada desde o início, com isolamento rigoroso, RBAC granular e network policies. Zero-trust networking obrigatório para compliance.

## Decisão
- **RBAC**: ServiceAccounts dedicadas por domínio
- **Network Policies**: Deny-all por padrão, allow específicos
- **Service Mesh**: Sidecar isolation obrigatória
- **Pod Security**: Standards enforced via admission controllers

## Consequências
- **Positivo**: Segurança robusta, compliance facilitada
- **Negativo**: Complexidade operacional, overhead de performance
- **Riscos**: Bloqueio de funcionalidades legítimas
- **Mitigação**: Policies testadas, exceptions via ADR

## Implementação
- **RBAC**: ClusterRoles por domínio, RoleBindings por namespace
- **Network Policies**: Calico/Cilium policies
- **Service Mesh**: Linkerd/Istio com mTLS
- **Admission Controllers**: OPA/Kyverno para policies customizadas

## Validação
- Penetration testing
- Compliance audits (GDPR/HIPAA)
- Performance impact measurement

## Referências
- [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

Data: 2025-12-30</content>
<parameter name="filePath">\\wsl.localhost\Ubuntu\home\gilvangalindo\projects\Arquitetura\Kubernetes\SAD\docs\adrs\adr-005-seguranca-sistemica.md