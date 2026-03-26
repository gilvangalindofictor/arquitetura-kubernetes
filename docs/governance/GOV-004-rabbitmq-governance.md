# GOV-004: RabbitMQ Governance & Best Practices

> **Versão**: 1.0
> **Data**: 2026-02-27
> **Status**: Ativo
> **Referências**: ADR-062
> **Audiência**: Desenvolvedores, Integration Team, Platform Team

---

## Visão Geral

> **Nota 2026-03-24 — Topologia 2 Clusters**: Adotada arquitetura de 2 clusters RabbitMQ independentes (DEC-2026-03-24-RABBITMQ). Esta decisão supera qualquer menção a VHosts compartilhados neste documento. Ver ADR-062 Revisão 2026-03-24 para detalhes completos da decisão.

RabbitMQ é provisionado via **RabbitMQ Cluster Operator** com 2 clusters independentes:

- `staging-data-infrastructure` (namespace: `staging-data-infrastructure`)
- `prod-data-rabbitmq` (namespace: `prod-data-infrastructure`)

Utilizado para messaging assíncrono: pub/sub, work queues, event-driven architecture.

---

## Naming Conventions

**Referência completa**: [ADR-062: RabbitMQ Governance Standards](../adr/adr-062-rabbitmq-governance-standards.md)

### Cluster Names

```yaml
Formato: {produto}-rabbitmq
Namespace: data-services (centralizado)

Exemplos:
✅ rpa-exemplo-rabbitmq
✅ ipaas-rabbitmq
```

### Exchange Names

```yaml
Formato: {domain}.{produto}.{type}
Separator: . (dot)

Exemplos:
✅ data.rpa-exemplo.events         # Topic exchange
✅ integration.ipaas.notifications # Fanout exchange
✅ data.hatch.tasks                # Direct exchange

❌ DataRpaExemploEvents            # CamelCase proibido
❌ events                          # Sem namespace
```

### Queue Names

```yaml
Formato: {domain}.{produto}.{queue-name}

Exemplos:
✅ data.rpa-exemplo.tasks           # Work queue
✅ data.rpa-exemplo.tasks.dlq       # Dead-letter queue
✅ integration.ipaas.webhooks.retry # Retry queue

Suffixes padrão:
  .dlq        → Dead-letter queue
  .retry      → Retry queue
  .priority   → Priority queue
```

### Routing Keys

```yaml
Formato: {resource}.{action}[.{detail}]

Exemplos:
✅ user.created
✅ user.updated.email
✅ order.completed
✅ report.generated.pdf

Patterns (consumer binding):
✅ user.*           # Todos eventos de user
✅ *.created        # Todos eventos created
```

---

## Provisioning

### Custom Resource (Staging)

```yaml
apiVersion: rabbitmq.com/v1beta1
kind: RabbitmqCluster
metadata:
  name: {produto}-rabbitmq
  namespace: data-services
  labels:
    domain: {domain}
    product: {produto}
    owner: {domain}-team
spec:
  replicas: 1                    # Staging: 1, Prod: 3
  image: rabbitmq:3.12-management
  resources:
    requests: { cpu: 200m, memory: 512Mi }
    limits: { cpu: 1000m, memory: 1Gi }
  persistence:
    storageClassName: gp3
    storage: 10Gi                # Staging: 10Gi, Prod: 50Gi
  rabbitmq:
    additionalConfig: |
      prometheus.return_per_object_metrics = true
      consumer_timeout = 1800000
      vm_memory_high_watermark.relative = 0.8
      disk_free_limit.absolute = 2GB
```

### Production (HA)

```yaml
spec:
  replicas: 3                    # 3 nodes (quorum)
  rabbitmq:
    additionalConfig: |
      queue_master_locator = balanced
      cluster_partition_handling = autoheal
```

---

## Exchange Types

| Type | Uso | Routing |
|------|-----|---------|
| **topic** | Pub/sub com filtering | Via routing key patterns |
| **fanout** | Broadcast (todos consumers) | Sem routing |
| **direct** | Work queue (1-to-1) | Routing key exato |
| **headers** | Routing complexo | Via message headers |

---

## Dead-Letter Queue (DLQ) Pattern

```
┌──────────┐     ┌──────────────┐     ┌─────────────┐
│ Producer  │────>│ Main Queue   │────>│ Consumer    │
└──────────┘     └──────┬───────┘     └─────────────┘
                        │ (reject/expire)
                        v
                 ┌──────────────┐
                 │ DLQ (.dlq)   │────> Manual Review / Retry
                 └──────────────┘
```

Toda queue DEVE ter DLQ configurada:

```python
channel.queue_declare(
    queue='data.rpa-exemplo.tasks',
    durable=True,
    arguments={
        'x-message-ttl': 86400000,                          # 24h
        'x-max-length': 10000,                              # Max 10k msgs
        'x-dead-letter-exchange': 'data.rpa-exemplo.dlx',
        'x-dead-letter-routing-key': 'data.rpa-exemplo.tasks.dlq'
    }
)
```

---

## Message Standards

```yaml
Properties obrigatórias:
  delivery_mode: 2              # Persistent
  content_type: "application/json"
  message_id: "<uuid>"          # Idempotency key
  timestamp: <unix_epoch>       # Audit trail
  app_id: "{produto}"           # Origem

Headers recomendados:
  x-correlation-id: "<trace-id>"  # OpenTelemetry trace
  x-retry-count: 0                # Retry tracking
```

---

## Monitoring

### Métricas Essenciais (Prometheus)

| Métrica | Alerta | Threshold |
|---------|--------|-----------|
| Queue depth | `RabbitMQQueueDepth` | > 10000 messages |
| Consumer count | `RabbitMQNoConsumers` | = 0 consumers |
| Memory usage | `RabbitMQHighMemory` | > 80% watermark |
| DLQ depth | `RabbitMQDLQDepth` | > 100 messages |

### Runbooks

- [RabbitMQ Down](../../domains/observability/docs/runbooks/dt005-rabbitmq-down.md)
- [RabbitMQ Queue Depth](../../domains/observability/docs/runbooks/dt005-rabbitmq-queue-depth.md)

---

## Best Practices

1. **Sempre usar DLQ**: Mensagens com falha vão para DLQ (nunca descartadas)
2. **Messages persistentes**: `delivery_mode: 2` para sobreviver restarts
3. **Idempotency**: Usar `message_id` (UUID) para deduplição no consumer
4. **Prefetch count**: Configurar `basic_qos(prefetch_count=10)` para flow control
5. **TTL em messages**: Evitar queues crescendo indefinidamente
6. **Monitor DLQ**: DLQ com mensagens indica bugs no consumer
7. **Connection via service DNS**: `{produto}-rabbitmq.data-services.svc.cluster.local`

---

## Referências

- [ADR-062: RabbitMQ Governance Standards](../adr/adr-062-rabbitmq-governance-standards.md)
- [Vendor: RabbitMQ](../vendor/rabbitmq.md)
