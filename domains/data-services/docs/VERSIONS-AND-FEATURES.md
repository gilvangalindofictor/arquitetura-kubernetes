# Versões e Features - Redis & RabbitMQ (STAGING)

**Data**: 2026-02-11
**Ambiente**: 🟡 STAGING (Terraform-driven)
**Source**: `platform-provisioning/aws/kubernetes/terraform/modules/`

---

## 📊 Versões Atuais (STAGING)

### Redis

| Componente         | Versão                          | Status    | Localização Terraform          |
| ------------------ | ------------------------------- | --------- | ------------------------------ |
| **Operator**       | SpotaHome 3.3.0                 | ✅ Live    | `modules/redis/main.tf` L118   |
| **Operator Image** | latest (v1.3.0)                 | ✅ Running | Helm release image.tag=latest  |
| **Redis Server**   | 6.2.6-alpine (default)          | ✅ Running | SpotaHome default image        |
| **Replication**    | 1 master + 2 replicas (STAGING) | ✅ Working | RedisFailover CRD              |
| **Sentinel**       | 3 sentinels                     | ✅ Running | Quorum=2 (failover automático) |

**PVC Configuration** (STAGING):
- Size: 5 GB (per pod)
- Storage Class: gp2 (EBS)
- Access Mode: ReadWriteOnce
- Persistence: RDB + AOF enabled

### RabbitMQ

| Componente          | Versão            | Status       | Localização Terraform          |
| ------------------- | ----------------- | ------------ | ------------------------------ |
| **Operator**        | Official (latest) | ✅ Live       | `modules/rabbitmq/main.tf` L52 |
| **RabbitMQ Server** | 3.13-management   | ✅ Running    | Image pull working             |
| **Nodes**           | 1 node (STAGING)  | ✅ Running    | var.replicas=1                 |
| **Plugins**         | 4 habilitados     | ✅ Configured | additionalPlugins array        |
| **Storage**         | PVC               | ✅ Configured | storageClassName=gp2           |

**Plugins Habilitados**:
```hcl
additionalPlugins = [
  "rabbitmq_management",      # Management UI + REST API
  "rabbitmq_prometheus",      # Prometheus metrics
  "rabbitmq_shovel",          # Shovel: message forwarding
  "rabbitmq_federation"       # Federation: cluster linking
]
```

**Memory Configuration** (STAGING):
```
Requests: 1 Gi (tight!)
Limits:   1 Gi (equals requests)
```

---

## ✨ Features Suportadas

### Redis 6.2.6

| Feature           | Disponível | Nível de Suporte    | Status                      |
| ----------------- | ---------- | ------------------- | --------------------------- |
| **Replication**   | ✅ Yes      | Full                | Master-Replica com Sentinel |
| **Persistence**   | ✅ Yes      | Both                | RDB + AOF configured        |
| **Pub/Sub**       | ✅ Yes      | Full                | Native Redis feature        |
| **Streams**       | ✅ Yes      | Full                | Introduced in Redis 5.0+    |
| **Lua Scripting** | ✅ Yes      | Full                | EVAL/EVALSHA                |
| **Transactions**  | ✅ Yes      | Full                | MULTI/EXEC                  |
| **Cluster Mode**  | ❌ No       | Not configured      | Single cluster, not sharded |
| **TLS**           | ⚠️ Partial  | Manual setup needed | Not auto-configured         |
| **ACL**           | ✅ Yes      | Basic (v6.0+)       | Single password for now     |

**Replication Architecture** (STAGING):
```
Master Pod (read/write) ← replicate ← Replica Pod 1 (read-only)
                         ← replicate ← Replica Pod 2 (read-only)

Sentinel 1 (monitor) ←→ Sentinel 2 (quorum) ←→ Sentinel 3 (monitor)
  Failover Policy: autoheal (if master down, promote max-offset replica)
```

---

### RabbitMQ 3.13 Features

| Feature                 | Disponível | Nível de Suporte | Notes                            |
| ----------------------- | ---------- | ---------------- | -------------------------------- |
| **Quorum Queues**       | ✅ Yes      | Full             | ⭐ NEW - Replicated by default    |
| **Streams**             | ✅ Yes      | Full             | ⭐ NEW - Similar to Redis Streams |
| **Classic Queues**      | ✅ Yes      | Full             | Legacy (not durable by default)  |
| **Message Persistence** | ✅ Yes      | Full             | PVC configured                   |
| **Management UI**       | ✅ Yes      | Full             | Port 15672 (LoadBalancer)        |
| **Clustering**          | ✅ Yes      | Partial          | STAGING: 1 node (no cluster yet) |
| **TLS/SSL**             | ✅ Yes      | Partial          | Auto TLS via Operator            |
| **AMQP 1.0**            | ✅ Yes      | Full             | Via plugin                       |
| **MQTT**                | ✅ Yes      | Full             | Via plugin (not enabled)         |
| **STOMP**               | ✅ Yes      | Full             | Via plugin (not enabled)         |
| **HTTP API**            | ✅ Yes      | Full             | Management REST API              |

**Key New Features in RabbitMQ 3.13**:
- ✅ Quorum Queues: Leader + 2 followers (automatic replication)
- ✅ Streams: Append-only log (like Redis Streams, but message-oriented)
- ✅ Feature Flags: Auto-enable progressive features (`feature_flags`)
- ✅ Internal cluster communication: More efficient (mDNS replaced with DNS)

---

## 🎯 Quorum Queues vs Classic Queues

### What's Activated Now?

**Classic Queues** (Legacy):
- Default when declaring queue without type
- **NOT durable** by default (master node down = data loss)
- Faster (replication = async, no quorum required)
- Use case: Non-critical messaging (logs, events that can be lost)

**Quorum Queues** (New, Recommended):
- Explicitly declare: `arguments = {"x-queue-type": "quorum", "x-quorum-initial-group-size": 3}`
- **Durable by default** (2 of 3 nodes must acknowledge)
- Slower (all writes require quorum agreement)
- Use case: Critical messaging (transactions, confirmations, orders)

### Current STAGING Configuration

```ruby
# RabbitMQ 3.13-management supports BOTH types

# To create Quorum Queue (recommended for critical data):
Channel.queue_declare(
  :queue => "my_queue",
  :arguments => {
    "x-queue-type" => "quorum",           # Enable Quorum mode
    "x-quorum-initial-group-size" => 1    # STAGING: 1 node (no replication)
  }
)

# To create Classic Queue (legacy):
Channel.queue_declare(
  :queue => "my_queue",
  :durable => true  # Make persistent, but NOT replicated
)
```

**Limitation in STAGING**: Quorum queues need **minimum 3 nodes** to vote on replication. Since we have **1 node**, quorum mode works but provides **zero replication protection** (single node failure = data loss).

---

## 🚀 Streams in RabbitMQ 3.13

**New Feature**: RabbitMQ Streams (similar to Redis Streams)

### What Are Streams?

```ruby
# Producer: Append message to stream
channel.stream_insert(
  stream: "my_stream",
  messages: [
    { body: "Message 1", timestamp: Time.now },
    { body: "Message 2", timestamp: Time.now }
  ]
)

# Consumer: Read from offset (replay capability)
consumer = channel.stream_subscribe(
  stream: "my_stream",
  offset_specification: "first"  # Can replay from start
)

consumer.each do |msg|
  puts "Received: #{msg.body}"
  channel.ack(msg)  # Manual ack
end
```

### Comparison: Redis Streams vs RabbitMQ Streams

| Feature             | Redis Streams         | RabbitMQ Streams                   |
| ------------------- | --------------------- | ---------------------------------- |
| **Type**            | Data structure        | Message queue                      |
| **Persistence**     | In-memory (RDB/AOF)   | PVC-backed (durable)               |
| **Replication**     | Via master-replica    | Via Quorum (cluster)               |
| **Consumer Groups** | Yes                   | Yes (consumer offset tracking)     |
| **Retention**       | Min/Max entries       | TTL + Size policies                |
| **Multi-subject**   | Single stream per key | Single stream per name             |
| **Use Case**        | Event log, metrics    | Message processing, event sourcing |
| **Latency**         | microseconds          | milliseconds                       |

**Current STAGING Status**:
- ✅ RabbitMQ Streams available (3.13+)
- ⚠️ Not explicitly tested yet
- 🚫 Single node = no replication advantage

---

## 📈 Recommended Upgrades (Future)

### For Production (Est. Q2 2026)

**Redis Options**:
- Current: 6.2.6-alpine (2021, stable, security updates)
- Available: 7.x (2023, new features: functions, ACL improvements, JSON support)
- Recommendation: **Stay on 6.2.x for STAGING**, upgrade to 7.x for Production

**RabbitMQ Options**:
- Current: 3.13-management (latest, 2024)
- Latest: 3.13.x patch versions
- Recommendation: **Monitor 3.14 RC** (when released Q3 2026)

### Migration Path (Quorum Queues)

**STAGING → Production**:
```hcl
# environments/staging/main.tf (CURRENT - 1 replica)
rabbitmq_replicas = 1

# environments/production/main.tf (FUTURE - 3 replicas)
rabbitmq_replicas = 3

# Apps will auto-declare Quorum queues with:
"x-quorum-initial-group-size" = 3  # 2-of-3 quorum voting
```

---

## ⚠️ Current Limitations (STAGING)

### Redis 6.2.6
1. ❌ **Cluster Mode NOT enabled** (no sharding)
   - Single instance scales to ~50GB (depends on node memory)
   - For larger datasets, need Redis Cluster or multiple instances

2. ⚠️ **TLS not auto-configured**
   - Connections within cluster unencrypted
   - Plan TLS setup for Production

3. 🟡 **ACL is basic** (Redis 6.0 ACL can only assign 1 password)
   - Production should implement users + permissions

### RabbitMQ 3.13
1. 🟡 **Single node ≠ Quorum protection**
   - Quorum queues require 3+ nodes to provide durable voting
   - STAGING Quorum mode: survives zero failures (2/1 impossible)

2. ⚠️ **Memory tight** (1 Gi limit)
   - Safe for ~10K queued messages
   - Production needs 4-8 Gi per node

3. 🚫 **Streams not battle-tested** (new feature in 3.13)
   - Recommend 3 months of Production testing before depending on Streams

---

## 📚 Version Tracking

### Current Versions Table

```
Component                  | STAGING    | Latest Avail | Lag   | Action
───────────────────────────────────────────────────────────────────────
Redis Operator             | 3.3.0      | 3.4.0        | 1     | Monitor
Redis Server               | 6.2.6      | 7.2.x        | Major | Defer to Prod
RabbitMQ Operator          | latest     | latest       | 0     | Current
RabbitMQ Server            | 3.13       | 3.13.x       | 0-1   | Monitor patches
SpotaHome Redis Op App     | v1.3.0     | v1.3.5       | 0-1   | Minor
Official RMQ Operator      | 2.x        | 2.19.1       | 0     | At latest
```

---

## 🔄 Next Steps

### This Week
- ✅ Confirm Quorum Queue requirements with apps team
- ✅ Plan Stream usage (if needed for event sourcing)
- ✅ Document STAGING limitations in ADR

### Next Month (March 2026)
- ⏳ Load test: Can STAGING Redis handle expected traffic?
- ⏳ Test RabbitMQ Streams with sample producer/consumer
- ⏳ Plan upgrade path to Production (3 replicas, Quorum queues mandatory)

### Q2 2026 (Production Setup)
- 📋 Scale RabbitMQ to 3 nodes (unlock Quorum benefits)
- 📋 Implement Quorum queues as default
- 📋 Test failover scenarios (node down, recovery)
- 📋 Decide: Upgrade to Redis 7.x or stay with 6.2.6?

---

## 📖 Documentation References

- **[VERSION-CONTROL.md](./VERSION-CONTROL.md)** - Version history + upgrade planning
- **[STAGING-INVENTORY.md](./STAGING-INVENTORY.md)** - Current component inventory
- **[ADR-053: Redis Operator Decision](../adr/adr-053-redis-operator-spotahome-vs-otcontainerkit.md)** - Why SpotaHome 3.3.0?
- **[Terraform Redis Module](../../platform-provisioning/aws/kubernetes/terraform/modules/redis/)** - Live declarations

---

**Last Updated**: 2026-02-11
**Environment**: STAGING (Marco 3 MVP)
**Prepared by**: Platform Architecture

