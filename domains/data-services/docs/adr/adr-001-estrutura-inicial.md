# ADR-001: Estrutura Inicial do Domínio Data Services

**Status**: ✅ Aceito  
**Data**: 2026-01-05  

---

## Contexto

O domínio **data-services** fornece serviços de dados gerenciados (DBaaS, CacheaaS, MQaaS) com HA, backup e monitoramento.

## Decisão

### Stack
1. **Zalando Postgres Operator** - PostgreSQL HA
2. **Redis Cluster** - Cache distribuído
3. **RabbitMQ Cluster Operator** - Message Queue HA
4. **Velero** - Backup/restore

## Referências
- [SAD v1.2](../../../../SAD/docs/sad.md)

---
**Versão**: 1.0