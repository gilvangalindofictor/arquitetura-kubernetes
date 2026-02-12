# Domínio Data Services - Plataforma Corporativa Kubernetes

> **Parte da**: Plataforma Corporativa Kubernetes (6 domínios)
> **Governança**: SAD v1.2 - `/SAD/docs/sad.md`
> **Status**: 🚧 Em Construção

Este domínio fornece **serviços de dados gerenciados** (DBaaS, CacheaaS, MQaaS) com HA, backup automatizado e monitoramento.

## 🎯 Missão

Fornecer **serviços de dados como serviço** para aplicações:
- **Databases**: PostgreSQL com HA (Patroni/Zalando operator)
- **Cache**: Redis Cluster
- **Message Queue**: RabbitMQ Cluster
- **Backup**: Velero para disaster recovery

## 📦 Stack de Tecnologia

| Componente     | Ferramenta                            | Propósito                   |
| -------------- | ------------------------------------- | --------------------------- |
| **PostgreSQL** | Zalando Postgres Operator             | Databases as a Service (HA) |
| **Redis**      | Redis Cluster                         | Cache distribuído           |
| **RabbitMQ**   | RabbitMQ Cluster Operator             | Message Queue HA            |
| **Backup**     | Velero                                | Backup/restore automatizado |
| **Monitoring** | Exporters (Postgres, Redis, RabbitMQ) | Métricas para observability |

## 🏗️ Arquitetura

### Namespaces
- `data-postgres` - PostgreSQL clusters
- `data-redis` - Redis clusters
- `data-rabbitmq` - RabbitMQ clusters
- `data-backup` - Velero backups

## 📚 Contratos com Outros Domínios

### Contratos Fornecidos (Provider)
| Serviço        | API/Interface       | SLA   | Consumidores |
| -------------- | ------------------- | ----- | ------------ |
| PostgreSQL     | PostgreSQL protocol | 99.9% | Applications |
| Redis          | Redis protocol      | 99.9% | Applications |
| RabbitMQ       | AMQP/STOMP          | 99.9% | Applications |
| Backup/Restore | Velero API          | 99.9% | Operations   |

### Contratos Consumidos
| Serviço        | Provider           | Interface              |
| -------------- | ------------------ | ---------------------- |
| Monitoring     | observability      | Prometheus exporters   |
| Authentication | platform-core      | Keycloak               |
| Secrets        | secrets-management | Vault/External Secrets |

## 📖 Documentação

### Controle e Governança
- [Controle de Versões](docs/VERSION-CONTROL.md) - Status de versões e plano de atualizações
- [Validation Report](docs/VALIDATION-REPORT.md) - Relatório de validação do domínio
- [ADR-001](docs/adr/adr-001-estrutura-inicial.md) - Estrutura inicial do domínio

### Referências
- [SAD v1.2](../../../SAD/docs/sad.md)
- [Domain Contracts](../../../SAD/docs/architecture/domain-contracts.md)

---
**Status**: 🚧 Em Construção
