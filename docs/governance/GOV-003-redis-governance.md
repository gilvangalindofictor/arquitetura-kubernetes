# GOV-003: Redis Governance & Best Practices

> **Versão**: 1.0
> **Data**: 2026-02-27
> **Status**: Ativo
> **Referências**: ADR-053, ADR-061
> **Audiência**: Desenvolvedores, Platform Team

---

## Visão Geral

Redis é provisionado via **Redis Operator** (Bitnami) no namespace `data-services`.
Utilizado para cache, sessions, queues e distributed locks.

**Decisão Arquitetural**: OT Container Kit Redis Operator — ADR-053.

---

## Naming Conventions

**Referência completa**: [ADR-061: Redis Governance Standards](../adr/adr-061-redis-governance-standards.md)

### Custom Resource Names

```yaml
Formato: {produto}-redis[-{sufixo}]
Regex: ^[a-z][a-z0-9-]{0,62}-redis(-[a-z0-9-]+)?$
Namespace: data-services (centralizado)

Exemplos:
✅ rpa-exemplo-redis              # Redis single instance
✅ ipaas-redis-cache              # iPaaS cache dedicado
✅ ipaas-redis-sessions           # iPaaS sessions dedicado

❌ RpaExemploRedis                # CamelCase proibido
❌ rpa_exemplo_redis              # Underscore proibido
❌ redis-rpa-exemplo              # Prefixo "redis" proibido
```

### Key Naming (Application-Level)

```yaml
Formato: {domain}:{produto}:{resource}:{id}[:{subresource}]
Separator: : (colon)

Exemplos:
✅ data:rpa-exemplo:session:user-123
✅ data:rpa-exemplo:cache:report-456
✅ integration:ipaas:lock:workflow:abc-def-123

❌ rpa_session_123                # Sem namespace
❌ DataRpaSession123              # CamelCase proibido
```

---

## Provisioning (Custom Resource)

```yaml
apiVersion: redis.redis.opstreelabs.in/v1beta1
kind: Redis
metadata:
  name: {produto}-redis
  namespace: data-services
  labels:
    domain: {domain}
    product: {produto}
    owner: {domain}-team
    environment: staging
spec:
  kubernetesConfig:
    image: redis:7.2-alpine
    resources:
      requests: { cpu: 100m, memory: 256Mi }
      limits: { cpu: 500m, memory: 512Mi }
  redisExporter:
    enabled: true
    image: quay.io/opstree/redis-exporter:latest
  storage:
    volumeClaimTemplate:
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: gp3
        resources:
          requests:
            storage: 5Gi    # Staging: 5Gi, Prod: 20Gi
  redisConfig:
    maxmemory: "512mb"
    maxmemory-policy: "allkeys-lru"
```

### Production (HA via Sentinel)

```yaml
apiVersion: redis.redis.opstreelabs.in/v1beta1
kind: RedisSentinel
metadata:
  name: {produto}-redis-sentinel
  namespace: data-services
spec:
  size: 3              # 3 sentinels (quorum=2)
  redisReplication:
    clusterSize: 3     # 1 master + 2 replicas
```

---

## Configuração por Tipo de Uso

| Tipo | maxmemory-policy | Persistence | TTL Default |
|------|------------------|-------------|-------------|
| **Cache** | `allkeys-lru` | Nenhuma (RDB/AOF off) | 1h |
| **Sessions** | `volatile-lru` | AOF (appendonly yes) | 24h |
| **Queue** | `noeviction` | RDB + AOF | Sem TTL |
| **Locks** | `volatile-ttl` | Nenhuma | 30s |

---

## TTL Policies (Obrigatórias)

```yaml
Sessions:    24h (86400s)
Cache:       1h (3600s)
Locks:       30s
Queues:      7d (604800s) ou sem TTL
Temporary:   5min (300s)
```

**Regra**: Toda key DEVE ter TTL. Keys sem TTL causam memory leaks.

```python
# ✅ CORRETO: Sempre com TTL
r.setex('data:rpa-exemplo:session:user-123', timedelta(hours=24), 'data')

# ❌ ERRADO: Sem TTL (memory leak!)
r.set('data:rpa-exemplo:session:user-123', 'data')
```

---

## Eviction Policies

| Policy | Uso | Comportamento |
|--------|-----|---------------|
| `allkeys-lru` | Cache genérico | Evict qualquer key (LRU) |
| `volatile-lru` | Sessions com TTL | Evict apenas keys com TTL |
| `allkeys-lfu` | Cache hot keys | Evict por frequência |
| `noeviction` | Queue, locks | Retorna erro quando full |
| `volatile-ttl` | Locks temporários | Evict keys com TTL mais próximo |

---

## Monitoring

### Métricas Essenciais (Prometheus)

| Métrica | Alerta | Threshold |
|---------|--------|-----------|
| Memory usage | `RedisHighMemory` | > 80% maxmemory |
| Connected clients | `RedisHighClients` | > 80% maxclients |
| Keys without TTL | `RedisKeysTTLMissing` | > 100 keys |
| Evictions/sec | `RedisHighEvictions` | > 50/sec |

### Runbooks

- [Redis Down](../../domains/observability/docs/runbooks/dt005-redis-down.md)
- [Redis High Memory](../../domains/observability/docs/runbooks/dt005-redis-high-memory.md)

---

## Best Practices

1. **Sempre definir TTL**: Keys sem TTL são memory leaks em potencial
2. **Usar key namespaces**: `{domain}:{produto}:{resource}:{id}` para rastreabilidade
3. **Maxmemory = memory limit**: Evitar OOMKill pelo Kubernetes
4. **Staging: single instance** para economia; **Production: Sentinel HA** para uptime
5. **Monitorar evictions**: Evictions altas indicam necessidade de mais memória
6. **Connection via service DNS**: `{produto}-redis.data-services.svc.cluster.local`

---

## Referências

- [ADR-053: Redis Operator Selection](../adr/adr-053-redis-operator-spotahome-vs-otcontainerkit.md)
- [ADR-061: Redis Governance Standards](../adr/adr-061-redis-governance-standards.md)
- [Vendor: Redis](../vendor/redis.md)
