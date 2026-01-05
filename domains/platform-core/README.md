# Domínio Platform Core - Plataforma Corporativa Kubernetes

> **Parte da**: Plataforma Corporativa Kubernetes (6 domínios)  
> **Governança**: SAD v1.2 - `/SAD/docs/sad.md`  
> **Status**: 🚧 Em Construção | 🏗️ Fundação da Plataforma

Este domínio fornece a **infraestrutura base transversal** para todos os domínios: gateway, autenticação, service mesh, certificados.

## 🎯 Missão

Fornecer **serviços fundacionais compartilhados**:
- **API Gateway**: Exposição externa via Kong
- **Autenticação**: Keycloak (OIDC/OAuth2)
- **Service Mesh**: Linkerd (mTLS, observability)
- **Certificados**: cert-manager (ACME/Let's Encrypt)
- **Ingress**: NGINX Ingress Controller

## 📦 Stack de Tecnologia

| Componente | Ferramenta | Propósito |
|------------|-----------|-----------|
| **API Gateway** | Kong | Exposição externa, rate limiting, plugins |
| **Authentication** | Keycloak | Identity Provider (OIDC/SAML) |
| **Service Mesh** | Linkerd | mTLS, traffic management, observability |
| **Certificates** | cert-manager | Automação TLS (Let's Encrypt) |
| **Ingress** | NGINX Ingress Controller | Load balancing, SSL termination |
| **DNS** | External DNS | Sincronização automática DNS |

## 🏗️ Arquitetura

### Namespaces
- `platform-kong` - Kong Gateway
- `platform-keycloak` - Keycloak, PostgreSQL
- `linkerd` - Service Mesh (control plane)
- `cert-manager` - Cert Manager
- `ingress-nginx` - NGINX Ingress

### Fluxo de Tráfego

```
Internet → NGINX Ingress → Kong Gateway → Linkerd Proxy → Services
              ↓                ↓                ↓
         cert-manager     Keycloak         mTLS Mesh
```

## 📚 Contratos com Outros Domínios

### Contratos Fornecidos (Provider) - CRÍTICO
| Serviço | API/Interface | SLA | Consumidores |
|---------|---------------|-----|--------------|
| Authentication | Keycloak OIDC/OAuth2 | 99.95% | **TODOS** |
| API Gateway | Kong REST API | 99.9% | **TODOS** |
| Service Mesh | Linkerd mTLS | 99.9% | **TODOS** |
| Certificates | cert-manager ACME | 99.9% | **TODOS** |
| Ingress | NGINX HTTP/HTTPS | 99.9% | **TODOS** |

### Dependências
- **Nenhuma**: Domínio fundacional (deve ser deployado PRIMEIRO)

## 📖 Referências
- [SAD v1.2](../../../SAD/docs/sad.md)
- [Domain Contracts](../../../SAD/docs/architecture/domain-contracts.md)
- [Platform Provisioning](../../../platform-provisioning/)

---
**Status**: 🚧 Em Construção  
**Deploy Priority**: **1º** (fundação obrigatória)
