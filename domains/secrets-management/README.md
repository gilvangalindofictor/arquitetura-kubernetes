# Domínio Secrets Management - Plataforma Corporativa Kubernetes

> **Parte da**: Plataforma Corporativa Kubernetes (6 domínios)  
> **Governança**: SAD v1.2 - `/SAD/docs/sad.md`  
> **Status**: 🚧 Em Construção | 🔐 Cofre Centralizado

Este domínio fornece **cofre de senhas centralizado** com integração CI/CD, rotação automática e auditoria completa.

## 🎯 Missão

Fornecer **gestão segura de secrets** para toda a plataforma:
- **Cofre Centralizado**: HashiCorp Vault ou External Secrets Operator
- **Integração CI/CD**: Secrets injection em pipelines
- **Rotação Automática**: Passwords, API keys, certificados
- **Auditoria**: Logs de acessos para compliance

## 📦 Stack de Tecnologia (Decisão Pendente ADR)

### Opção 1: HashiCorp Vault (Preferencial)
| Componente | Ferramenta | Propósito |
|------------|-----------|-----------|
| **Vault** | HashiCorp Vault | Cofre de secrets, dynamic secrets |
| **Injector** | Vault Agent Injector | Sidecar injection |
| **Backend** | Raft Storage | HA storage backend |

### Opção 2: External Secrets Operator + Cloud KMS
| Componente | Ferramenta | Propósito |
|------------|-----------|-----------|
| **ESO** | External Secrets Operator | Sync secrets de cloud providers |
| **KMS** | AWS KMS / Azure Key Vault / GCP Secret Manager | Backend nativo |

## 🏗️ Arquitetura

### Namespaces
- `secrets-vault` - Vault cluster (se Opção 1)
- `secrets-eso` - External Secrets Operator (se Opção 2)

### Fluxo de Secrets

```
Vault/KMS → External Secrets Operator → Kubernetes Secrets → Pods
    ↓                                           ↓
  Audit                                    Encryption at rest
```

## 📚 Contratos com Outros Domínios

### Contratos Fornecidos (Provider) - CRÍTICO
| Serviço | API/Interface | SLA | Consumidores |
|---------|---------------|-----|--------------|
| Secrets Injection | External Secrets API | 99.9% | **TODOS** |
| Dynamic Secrets | Vault API | 99.9% | Applications |
| Audit Logs | Syslog/File | 99.9% | Compliance |

### Contratos Consumidos
| Serviço | Provider | Interface |
|---------|----------|-----------|
| Authentication | platform-core | Keycloak OIDC |
| Monitoring | observability | Prometheus metrics |

## 🔐 Segurança

- **Encryption at Rest**: Secrets encrypted no etcd
- **Encryption in Transit**: mTLS (Linkerd)
- **RBAC**: Granular por namespace/ServiceAccount
- **Audit**: Todos os acessos logados

## 📖 Referências
- [SAD v1.2](../../../SAD/docs/sad.md)
- [ADR-005: Segurança Sistêmica](../../../SAD/docs/adrs/adr-005-seguranca-sistemica.md)

---
**Status**: 🚧 Em Construção  
**ADR Pendente**: Escolha Vault vs External Secrets Operator
