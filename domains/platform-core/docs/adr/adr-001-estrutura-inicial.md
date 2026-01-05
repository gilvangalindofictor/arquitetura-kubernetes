# ADR-001: Estrutura Inicial do Domínio Platform Core

**Status**: ✅ Aceito  
**Data**: 2026-01-05  
**Contexto**: Criação do domínio platform-core conforme SAD v1.2  

---

## Contexto

O domínio **platform-core** é a **fundação** da plataforma, fornecendo serviços transversais críticos: gateway, autenticação, service mesh, certificados. Deve ser deployado **PRIMEIRO** pois todos os outros domínios dependem dele.

## Decisão

Criar estrutura base seguindo padrão cloud-agnostic.

### Stack
1. **Kong** - API Gateway
2. **Keycloak** - Identity Provider (OIDC/OAuth2)
3. **Linkerd** - Service Mesh (mTLS)
4. **cert-manager** - Automação TLS
5. **NGINX Ingress Controller** - Load balancing

### Prioridade
- **Deploy Priority**: **1º** (fundação obrigatória)
- **SLA**: 99.95% (crítico para todos os domínios)

## Referências
- [SAD v1.2](../../../../SAD/docs/sad.md)
- [Domain Contracts](../../../../SAD/docs/architecture/domain-contracts.md)

---
**Versão**: 1.0
