# ADR-062: RabbitMQ Governance Standards

> **Status**: Proposto
> **Data**: 2026-02-23
> **Decisores**: Platform Team + Integration Team
> **Contexto SAD**: Conformidade com ADR-047 (Domínios Corporativos), ADR-048 (Naming Conventions)

## Contexto

O projeto Kubernetes utiliza **RabbitMQ Cluster Operator** (Marco 3 operacional) para provisionamento de clusters RabbitMQ. Atualmente **não existem padrões documentados** para:

- Nomenclatura de exchanges, queues, routing keys
- Políticas de dead-letter queues (DLQ)
- Message TTL e durabilidade
- Patterns de uso (pub/sub, work queues, RPC)
- Monitoring e alertas

Essa falta de padronização cria riscos:
- **Mensagens perdidas** por configuração inadequada
- **Dead-letter loops** por DLQ mal configuradas
- **Memory leaks** por queues sem consumers
- **Debugging difícil** (mensagens não rastreáveis)
- **Dificuldade de onboarding** (padrões não documentados)

Este ADR estabelece **padrões determinísticos e automaticamente validáveis** para governança RabbitMQ.

## Decisão

### 1. Naming Conventions (Determinísticas)

#### 1.1 Exchange Names

```yaml
Formato: {domain}.{produto}.{type}
Regex: ^[a-z]+(\\.[a-z0-9-]+){2}$
Separator: . (dot)

Exemplos Válidos:
✅ data.rpa-exemplo.events         # Events topic exchange
✅ integration.ipaas.notifications # Notifications fanout
✅ data.hatch.tasks                # Tasks direct exchange

Exemplos Inválidos:
❌ DataRpaExemploEvents            # CamelCase não permitido
❌ data-rpa-exemplo-events         # Hyphen não permitido (usar dot)
❌ events                          # Sem namespace (domain.produto)
```

**Exchange Types**:
```yaml
topic:   {domain}.{produto}.events       # Pub/sub com routing patterns
fanout:  {domain}.{produto}.broadcasts   # Pub/sub sem routing (broadcast)
direct:  {domain}.{produto}.tasks        # Work queue (1-to-1 routing)
headers: {domain}.{produto}.headers      # Routing por message headers
```

#### 1.2 Queue Names

```yaml
Formato: {domain}.{produto}.{queue-name}
Regex: ^[a-z]+(\\.[a-z0-9-]+){2,}$

Exemplos Válidos:
✅ data.rpa-exemplo.tasks           # Work queue
✅ data.rpa-exemplo.tasks.dlq       # Dead-letter queue
✅ integration.ipaas.webhooks       # Webhook delivery queue
✅ integration.ipaas.webhooks.retry # Retry queue

Exemplos Inválidos:
❌ DataRpaExemploTasks              # CamelCase não permitido
❌ data_rpa_exemplo_tasks           # Underscore não permitido (usar dot)
❌ tasks                            # Sem namespace (domain.produto)
```

**Queue Suffixes** (padrões):
```yaml
.dlq        → Dead-letter queue (mensagens com falha)
.retry      → Retry queue (retry com exponential backoff)
.priority   → Priority queue (high-priority messages)
```

#### 1.3 Routing Keys

```yaml
Formato: {resource}.{action}[.{detail}]
Regex: ^[a-z]+(\\.[a-z0-9-]+){1,3}$

Exemplos (Topic Exchange):
✅ user.created                     # User created event
✅ user.updated.email               # User email updated
✅ order.completed                  # Order completed
✅ report.generated.pdf             # PDF report generated

Patterns (Consumer binding):
✅ user.*                           # All user events
✅ *.created                        # All created events
✅ user.updated.*                   # All user update events
```

### 2. RabbitMQ Cluster Provisioning

#### 2.1 Custom Resource Definition

```yaml
apiVersion: rabbitmq.com/v1beta1
kind: RabbitmqCluster
metadata:
  name: {produto}-rabbitmq
  namespace: data-services          # Centralizado
  labels:
    domain: {domain}
    product: {produto}
    owner: {domain}-team
    environment: staging             # ou prod
spec:
  replicas: 1                        # Staging: 1, Prod: 3 (HA)

  image: rabbitmq:3.12-management    # Management UI incluído

  resources:
    requests:
      cpu: 200m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 1Gi

  persistence:
    storageClassName: gp3
    storage: 10Gi                    # Staging: 10Gi, Prod: 50Gi

  rabbitmq:
    additionalConfig: |
      # Metrics
      prometheus.return_per_object_metrics = true

      # Consumer timeout (30min)
      consumer_timeout = 1800000

      # VM memory high watermark (80%)
      vm_memory_high_watermark.relative = 0.8

      # Disk free limit (2GB)
      disk_free_limit.absolute = 2GB

  override:
    service:
      spec:
        ports:
        - name: amqp
          port: 5672
          protocol: TCP
        - name: management
          port: 15672
          protocol: TCP
        - name: prometheus
          port: 15692
          protocol: TCP
```

#### 2.2 High Availability (Production)

```yaml
spec:
  replicas: 3                        # 3 nodes (quorum)

  rabbitmq:
    additionalConfig: |
      # Quorum queues (replicated across nodes)
      queue_master_locator = balanced

      # Cluster formation
      cluster_partition_handling = autoheal
```

**Rationale**:
- Staging: 1 replica (economia)
- Production: 3 replicas (HA 99.9% uptime)

### 3. Exchange & Queue Configuration

#### 3.1 Exchange Declaration

```python
# Python exemplo (pika library)
import pika

connection = pika.BlockingConnection(
    pika.ConnectionParameters(host='rpa-exemplo-rabbitmq.data-services.svc.cluster.local')
)
channel = connection.channel()

# Declarar exchange (idempotent)
channel.exchange_declare(
    exchange='data.rpa-exemplo.events',
    exchange_type='topic',       # topic, fanout, direct, headers
    durable=True,                # Survive broker restart
    auto_delete=False            # Don't delete when unused
)
```

**Exchange Types - Quando usar**:

| Type | Uso | Routing |
|------|-----|---------|
| **topic** | Pub/sub com filtering | Via routing key patterns (`user.*`, `*.created`) |
| **fanout** | Broadcast (todos consumers) | Sem routing (broadcast total) |
| **direct** | Work queue (1-to-1) | Routing key exato |
| **headers** | Routing complexo | Via message headers (key-value) |

#### 3.2 Queue Declaration

```python
# Declarar queue
channel.queue_declare(
    queue='data.rpa-exemplo.tasks',
    durable=True,                # Survive broker restart
    exclusive=False,             # Accessible by other connections
    auto_delete=False,           # Don't delete when no consumers
    arguments={
        'x-message-ttl': 86400000,           # Message TTL 24h (ms)
        'x-max-length': 10000,               # Max 10k messages
        'x-dead-letter-exchange': 'data.rpa-exemplo.dlx',  # DLX
        'x-dead-letter-routing-key': 'data.rpa-exemplo.tasks.dlq'
    }
)
```

**Queue Arguments**:
```yaml
x-message-ttl:           Message TTL (ms)
x-max-length:            Max messages (FIFO eviction)
x-max-length-bytes:      Max queue size (bytes)
x-dead-letter-exchange:  DLX para mensagens rejeitadas
x-dead-letter-routing-key: Routing key no DLX
x-max-priority:          Enable priority (0-255)
x-queue-type:            classic | quorum (HA)
```

### 4. Dead-Letter Queue (DLQ) Pattern

#### 4.1 DLQ Configuration

```python
# 1. Criar DLX (Dead-Letter Exchange)
channel.exchange_declare(
    exchange='data.rpa-exemplo.dlx',
    exchange_type='direct',
    durable=True
)

# 2. Criar DLQ (Dead-Letter Queue)
channel.queue_declare(
    queue='data.rpa-exemplo.tasks.dlq',
    durable=True,
    arguments={
        'x-message-ttl': 604800000,  # DLQ TTL 7 dias
        'x-max-length': 1000         # Max 1k failed messages
    }
)

# 3. Bind DLQ ao DLX
channel.queue_bind(
    exchange='data.rpa-exemplo.dlx',
    queue='data.rpa-exemplo.tasks.dlq',
    routing_key='data.rpa-exemplo.tasks.dlq'
)

# 4. Main queue aponta para DLX
channel.queue_declare(
    queue='data.rpa-exemplo.tasks',
    durable=True,
    arguments={
        'x-dead-letter-exchange': 'data.rpa-exemplo.dlx',
        'x-dead-letter-routing-key': 'data.rpa-exemplo.tasks.dlq'
    }
)
```

#### 4.2 Retry Pattern (Exponential Backoff)

```python
# Retry queue com TTL escalável
def create_retry_queue(retry_count: int):
    ttl_ms = 1000 * (2 ** retry_count)  # 1s, 2s, 4s, 8s, 16s, ...
    max_ttl_ms = 300000  # Max 5min

    channel.queue_declare(
        queue=f'data.rpa-exemplo.tasks.retry.{retry_count}',
        durable=True,
        arguments={
            'x-message-ttl': min(ttl_ms, max_ttl_ms),
            'x-dead-letter-exchange': 'data.rpa-exemplo.events',  # Back to main exchange
            'x-dead-letter-routing-key': 'task.retry'
        }
    )
```

**Retry Workflow**:
```
1. Consumer processa mensagem → FAIL
2. Reject message (requeue=False) → vai para DLX
3. DLX roteia para retry queue (TTL 2s)
4. Após TTL → volta para main exchange
5. Consumer tenta novamente
6. Se falhar 3x → vai para DLQ final
```

### 5. Message TTL & Durability

#### 5.1 TTL Policies

```yaml
Work Queues:    24h (86400000ms)    # Tasks devem ser processadas em 24h
Events:         7d (604800000ms)    # Events podem ser reprocessados até 7 dias
DLQ:            30d (2592000000ms)  # DLQ mantém falhas por 30 dias
Notifications:  1h (3600000ms)      # Notificações expiram rápido
```

#### 5.2 Message Durability

```python
# Publisher: Persistent messages
channel.basic_publish(
    exchange='data.rpa-exemplo.events',
    routing_key='task.created',
    body=json.dumps(task),
    properties=pika.BasicProperties(
        delivery_mode=2,             # 2 = persistent (disk)
        content_type='application/json',
        timestamp=int(time.time())
    )
)
```

**delivery_mode**:
```yaml
1: Non-persistent (memory only) → Mais rápido, mas perde mensagens em crash
2: Persistent (disk)            → Mais lento, mas sobrevive a restart
```

**Quando usar cada modo**:
- **Persistent**: Tasks críticas, events importantes
- **Non-persistent**: Logs, métricas, notificações não-críticas

### 6. Consumer Patterns

#### 6.1 Work Queue (Competing Consumers)

```python
# Multiple consumers processam 1 queue (load balancing)
def callback(ch, method, properties, body):
    task = json.loads(body)
    try:
        process_task(task)
        ch.basic_ack(delivery_tag=method.delivery_tag)  # ACK success
    except Exception as e:
        logger.error(f"Task failed: {e}")
        ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)  # NACK → DLQ

# Consumer com prefetch (QoS)
channel.basic_qos(prefetch_count=10)  # Max 10 unacked messages

channel.basic_consume(
    queue='data.rpa-exemplo.tasks',
    on_message_callback=callback,
    auto_ack=False  # Manual ACK (recommended)
)

channel.start_consuming()
```

#### 6.2 Pub/Sub (Topic Exchange)

```python
# Publisher
channel.basic_publish(
    exchange='data.rpa-exemplo.events',
    routing_key='user.created',
    body=json.dumps(event)
)

# Subscriber 1: All user events
channel.queue_bind(
    exchange='data.rpa-exemplo.events',
    queue='data.rpa-exemplo.user-sync',
    routing_key='user.*'
)

# Subscriber 2: All created events
channel.queue_bind(
    exchange='data.rpa-exemplo.events',
    queue='data.rpa-exemplo.audit-log',
    routing_key='*.created'
)
```

### 7. Security

#### 7.1 Authentication

```bash
# RabbitMQ Operator gera Secret automaticamente
kubectl get secret rpa-exemplo-rabbitmq-default-user -n data-services

# Extrair credenciais
RABBITMQ_USER=$(kubectl get secret rpa-exemplo-rabbitmq-default-user -n data-services \
  -o jsonpath='{.data.username}' | base64 -d)

RABBITMQ_PASSWORD=$(kubectl get secret rpa-exemplo-rabbitmq-default-user -n data-services \
  -o jsonpath='{.data.password}' | base64 -d)

# Armazenar no Vault
vault kv put secret/data/rpa-exemplo/rabbitmq \
  host="rpa-exemplo-rabbitmq.data-services.svc.cluster.local" \
  port="5672" \
  username="$RABBITMQ_USER" \
  password="$RABBITMQ_PASSWORD" \
  vhost="/"
```

**Rotação de senha**: 90 dias (conforme ADR-063)

#### 7.2 Virtual Hosts (vHosts)

```bash
# Multi-tenancy via vHosts (opcional)
# vHost pattern: /{domain}/{produto}

Exemplos:
✅ /data/rpa-exemplo              # RPA Exemplo vhost
✅ /integration/ipaas             # iPaaS vhost
✅ /                               # Default vhost (single-tenant)
```

**Quando usar vHosts**:
- ✅ Multi-tenant (isolar exchanges/queues entre tenants)
- ❌ Single-tenant (use default `/` vhost)

#### 7.3 Network Isolation

```yaml
# NetworkPolicy: Apenas namespaces autorizados
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: rabbitmq-access
  namespace: data-services
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: rpa-exemplo-rabbitmq
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          domain: data              # Apenas domínio DATA acessa
    ports:
    - protocol: TCP
      port: 5672                    # AMQP
    - protocol: TCP
      port: 15672                   # Management UI (staging apenas)
```

### 8. Monitoring & Alerting

#### 8.1 Métricas Obrigatórias (Prometheus)

```yaml
Métricas (via rabbitmq_prometheus plugin):
  - rabbitmq_up                                 # RabbitMQ online?
  - rabbitmq_connections                        # Conexões ativas
  - rabbitmq_queue_messages_ready               # Mensagens prontas (backlog)
  - rabbitmq_queue_messages_unacknowledged      # Mensagens processando
  - rabbitmq_queue_consumers                    # Consumers ativos
  - rabbitmq_channel_messages_published_total   # Throughput (msg/s)
  - rabbitmq_queue_messages_delivered_total     # Delivery rate
  - rabbitmq_queue_messages_redelivered_total   # Redeliveries (retries)

Alertas:
  - RabbitMQDown: rabbitmq_up == 0
  - QueueBacklogHigh: rabbitmq_queue_messages_ready > 1000
  - NoConsumers: rabbitmq_queue_consumers == 0 (queue sem consumers)
  - HighRedeliveryRate: rate(rabbitmq_queue_messages_redelivered_total[5m]) > 10
  - DLQGrowing: rate(rabbitmq_queue_messages{queue="*.dlq"}[5m]) > 5
```

#### 8.2 Grafana Dashboard

Dashboard obrigatório: **"RabbitMQ Overview"**
- Connections, channels, consumers
- Queue depth (ready, unacked)
- Throughput (publish rate, delivery rate)
- Redelivery rate (indica failures)
- DLQ size (mensagens falhadas)

**Localização**: `/domains/observability/infra/grafana/dashboards/rabbitmq-overview.json`

### 9. Best Practices

#### 9.1 Queue Design

```yaml
✅ DO:
- Use durable queues (survive restart)
- Set message TTL (prevent memory leaks)
- Configure DLQ (capture failures)
- Use prefetch (QoS) para load balancing
- Manual ACK (não auto_ack)

❌ DON'T:
- Auto-delete queues (data loss risk)
- Infinite TTL (memory leak)
- Auto-ACK (acknowledgment antes de processar = data loss)
- Requeue=True em NACK (pode causar loops infinitos)
```

#### 9.2 Performance

```yaml
Throughput:
  - Publisher confirms (garantia de delivery)
  - Batch publishing (>1 message por publish)
  - Prefetch count (QoS) = CPU cores × 2

Durability vs Speed:
  - Persistent messages: ~1k msg/s (disk I/O)
  - Non-persistent: ~50k msg/s (memory only)
  - Lazy queues: Disk-first (memória baixa)
```

#### 9.3 Consumer Idempotency

```python
# Consumer deve ser idempotente (redelivery pode ocorrer)
def process_task(task):
    task_id = task['id']

    # Check if already processed (idempotency key)
    if db.exists(f"processed_task:{task_id}"):
        logger.info(f"Task {task_id} already processed, skipping")
        return

    # Process task
    result = do_work(task)

    # Mark as processed
    db.set(f"processed_task:{task_id}", result, ex=86400)  # TTL 24h
```

## Consequências

### Positivas

- ✅ **Nomenclatura determinística**: Exchanges/queues rastreáveis por domínio
- ✅ **DLQ pattern**: Mensagens falhadas capturadas (não perdidas)
- ✅ **Retry pattern**: Exponential backoff automático
- ✅ **HA em produção**: 3-node cluster (99.9% uptime)
- ✅ **Observabilidade**: Métricas + alertas + dashboards
- ✅ **Security**: Passwords no Vault, NetworkPolicies

### Negativas

- ⚠️ **Complexidade**: DLQ + retry queues = configuração verbosa
  - **Rationale**: Confiabilidade > simplicidade
- ⚠️ **Overhead**: Persistent messages = I/O adicional (~50x mais lento)
  - **Rationale**: Durabilidade > performance (para tasks críticas)

### Riscos

- 🟡 **Queue sem consumers**: Mensagens acumulam infinitamente
  - **Mitigação**: Alerta `NoConsumers` + max-length nas queues
- 🟡 **DLQ loop**: Mensagem vai DLQ → retry → DLQ → infinito
  - **Mitigação**: Max retry count (3x), depois DLQ final sem requeue

## Alternatives Consideradas

### Alternativa 1: Kafka ao invés de RabbitMQ

**Pros**: Maior throughput (100k+ msg/s), log-based (replay)
**Cons**: Complexidade maior, overhead (ZooKeeper), aplicações atuais <10k msg/s
**Decisão**: ❌ Rejeitado - RabbitMQ suficiente para workload atual

### Alternativa 2: Prefixo produto sem domain (`rpa-exemplo.tasks`)

**Pros**: Exchanges mais curtas
**Cons**: Não rastreável por domínio (analytics cross-domain impossível)
**Decisão**: ❌ Rejeitado - Domain prefix essencial para governança

### Alternativa 3: Auto-ACK (simplifica consumer)

**Pros**: Código mais simples
**Cons**: Mensagem pode ser perdida (ACK antes de processar)
**Decisão**: ❌ Rejeitado - Manual ACK é best practice (confiabilidade)

## Implementação

### Scripts de Automação

```bash
# /scripts/onboarding/provision-rabbitmq.sh
# Cria RabbitMQ Cluster + ExternalSecret automaticamente

./provision-rabbitmq.sh \
  --produto rpa-exemplo \
  --environment staging \
  --replicas 1
```

### Validação

```bash
# 1. Verificar RabbitMQ Cluster
kubectl get rabbitmqcluster rpa-exemplo-rabbitmq -n data-services

# 2. Verificar pods Running
kubectl get pods -n data-services -l app.kubernetes.io/name=rpa-exemplo-rabbitmq

# 3. Verificar Service DNS
nslookup rpa-exemplo-rabbitmq.data-services.svc.cluster.local

# 4. Testar conexão AMQP
python -c "import pika; \
  conn = pika.BlockingConnection(pika.ConnectionParameters('rpa-exemplo-rabbitmq.data-services.svc.cluster.local')); \
  print('Connected'); \
  conn.close()"

# 5. Verificar Management UI (port-forward)
kubectl port-forward -n data-services svc/rpa-exemplo-rabbitmq 15672:15672
# Acessar: http://localhost:15672 (user/pass do Secret)

# 6. Verificar Prometheus metrics
kubectl port-forward -n data-services svc/rpa-exemplo-rabbitmq 15692:15692
curl http://localhost:15692/metrics | grep rabbitmq_up
# Esperado: rabbitmq_up 1
```

### Kyverno Policy (RabbitMQ CR Validation)

```yaml
# Validar nomenclatura RabbitMQ Cluster
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: validate-rabbitmq-cr-naming
spec:
  validationFailureAction: audit
  rules:
  - name: check-rabbitmq-cr-name
    match:
      any:
      - resources:
          kinds:
          - RabbitmqCluster
          namespaces:
          - data-services
    validate:
      message: "RabbitMQ Cluster name deve seguir padrão: {produto}-rabbitmq"
      pattern:
        metadata:
          name: "*-rabbitmq"
```

## Referências

- [RabbitMQ Best Practices](https://www.rabbitmq.com/best-practices.html)
- [RabbitMQ Reliability Guide](https://www.rabbitmq.com/reliability.html)
- [RabbitMQ Cluster Operator](https://www.rabbitmq.com/kubernetes/operator/operator-overview.html)
- [ADR-047: Estrutura Corporativa de Domínios](adr-047-estrutura-corporativa-dominios.md)
- [ADR-048: Naming Conventions Determinísticas](adr-048-naming-conventions-deterministicas.md)
- [ADR-060: PostgreSQL Governance Standards](adr-060-postgresql-governance-standards.md)
- [ADR-061: Redis Governance Standards](adr-061-redis-governance-standards.md)

---

**Próximos ADRs Relacionados**:
- ADR-063: Secrets Management Lifecycle
- ADR-064: Configuration Management Patterns
