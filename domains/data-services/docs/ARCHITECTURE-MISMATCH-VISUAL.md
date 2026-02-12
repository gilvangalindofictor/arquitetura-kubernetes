# Visualização das Discrepâncias

## Arquitetura Expectada vs. Real

### Documentação Esperada (K8s-Native)
```
EKS Cluster k8s-platform-prod
├─ Zalando Postgres Operator 1.10.1
│  └─ PostgreSQL databases (PVC)
├─ OT-Container-Kit Redis Operator 0.15.1
│  └─ Redis instances (PVC)
├─ RabbitMQ Cluster Operator 3.12.0
│  └─ RabbitMQ instances
└─ Velero 5.2.0
   └─ Backup to S3
```

### Realidade em Produção (Hybrid AWS + K8s)
```
┌─ AWS Account 891377105802
│  ├─ RDS PostgreSQL 16.4 (FORA do K8s)
│  ├─ S3 Buckets (Vault, Loki, Tempo)
│  └─ EBS PVCs (para K8s pods)
│
└─ EKS Cluster k8s-platform-prod v1.34
   ├─ SpotaHome Redis Operator 3.3.0 ✓
   │  └─ redis:6.2.6-alpine (PVC)
   ├─ RabbitMQ Cluster Operator 2.19.0 ✓
   │  └─ rabbitmq:3.13-management (pods)
   └─ Velero ❌ NÃO ENCONTRADO
      └─ Backup strategy DESCONHECIDA
```

## Matriz de Componentes

```
COMPONENTE          | ESPERADO (DOCS)      | REAL (PROD)          | STATUS
--------------------+---------------------+---------------------+----------
PostgreSQL Operator | Zalando 1.10.1      | AWS RDS 16.4         | 🔴 DIFF
PostgreSQL Version  | N/A (PVC)           | 16.4 (managed)       | 🔴 DIFF
Redis Operator      | OT-Container 0.15.1 | SpotaHome 3.3.0      | 🔴 DIFF
Redis Version       | N/A (operator)      | 6.2.6-alpine (2021)  | 🟡 OLD
RabbitMQ Operator   | Official 3.12.0*    | Official 2.19.0      | 🟡 CONFUSO
RabbitMQ Server     | N/A                 | 3.13-management      | ✓ OK
Velero              | VMware 5.2.0        | NÃO ENCONTRADO       | 🔴 MISSING
Backup Strategy     | Velero centralized  | ??? (unknown)        | 🔴 UNKNOWN
```

## Timeline de Descobertas

```
2026-01-28: EKS cluster criado (v1.34, ACTIVE)
2026-02-02: Redis Operator + PostgreSQL (?)
2026-02-04: Gitlab + Harbor + Keycloak deployats
2026-02-11: AUDITORIA → DESCOBERTAS CRÍTICAS
            ├─ PostgreSQL é RDS, não Operator
            ├─ Redis é SpotaHome, não OT-Container-Kit
            └─ Velero não encontrado em lugar algum
```

## Documentos Criados para Remediação

```
/domains/data-services/docs/
├─ CRITICAL-FINDINGS-SUMMARY.md (executivo)
├─ PRODUCTION-INVENTORY.md (reconciliação completa)
├─ BACKUP-STRATEGY.md (análise de gaps)
└─ VERSION-CONTROL.md (será atualizado)
```

## Próximas Ações

1. **HOJE**: Ler CRITICAL-FINDINGS-SUMMARY.md (5 min para CTO)
2. **AMANHÃ**: Decisão formal sobre Backup Strategy
3. **ESTA SEMANA**: Atualizar documentação + criar ADRs
4. **PRÓXIMAS SEMANAS**: Implementar Velero ou alternativa
