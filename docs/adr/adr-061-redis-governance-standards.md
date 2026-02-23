# ADR-061: Redis Governance Standards

> **Status**: Proposto
> **Data**: 2026-02-23
> **Decisores**: Platform Team + Data Team
> **Contexto SAD**: Conformidade com ADR-047 (Domínios Corporativos), ADR-048 (Naming Conventions)

## Contexto

O projeto Kubernetes utiliza **Redis Operator** (Bitnami, Marco 3 operacional) para provisionamento de instâncias Redis. Atualmente **não existem padrões documentados** para:

- Nomenclatura de Redis Custom Resources (CRs), keys, namespaces
- Políticas de TTL e eviction
- Patterns de uso (cache vs queue vs session store)
- Persistence strategies (RDB vs AOF)
- Monitoring e alertas

Essa falta de padronização cria riscos:
- **Conflitos de keys** entre aplicações
- **Memory leaks** por keys sem TTL
- **Data loss** por eviction incorreta
- **Performance degradada** por configuração inadequada
- **Dificuldade de debugging** (keys não rastreáveis)

Este ADR estabelece **padrões determinísticos e automaticamente validáveis** para governança Redis.

## Decisão

### 1. Naming Conventions (Determinísticas)

#### 1.1 Redis Custom Resource Names

```yaml
Formato: {produto}-redis[-{sufixo}]
Regex: ^[a-z][a-z0-9-]{0,62}-redis(-[a-z0-9-]+)?$
Namespace: data-services (centralizado)

Exemplos Válidos:
✅ rpa-exemplo-redis              # Redis single instance
✅ hatch-redis                    # Hatch ETL
✅ ipaas-redis-cache              # iPaaS cache dedicado
✅ ipaas-redis-sessions           # iPaaS sessions dedicado

Exemplos Inválidos:
❌ RpaExemploRedis                # CamelCase não permitido
❌ rpa_exemplo_redis              # Underscore não permitido (usar hyphen)
❌ redis-rpa-exemplo              # Prefixo "redis" não permitido (sufixo obrigatório)
```

**Rationale**:
- Hyphen (kebab-case) é padrão Kubernetes
- Sufixo `-redis` facilita filtragem (`kubectl get redis -A`)
- Namespace centralizado (`data-services`) = gestão unificada

#### 1.2 Redis Key Naming (Application-Level)

```yaml
Formato: {domain}:{produto}:{resource}:{id}[:{subresource}]
Separator: : (colon)
Regex: ^[a-z]+(:[a-z0-9-]+){2,4}$

Exemplos Válidos:
✅ data:rpa-exemplo:session:user-123
✅ data:rpa-exemplo:cache:report-456
✅ data:rpa-exemplo:queue:tasks:pending
✅ integration:ipaas:lock:workflow:abc-def-123

Exemplos Inválidos:
❌ rpa_session_123                # Sem namespace (domain:produto)
❌ data|rpa|session|123           # Separator errado (usar :)
❌ DataRpaSession123              # CamelCase não permitido
```

**Hierarquia**:
```
{domain}           → Domínio corporativo (data, integration, etc)
{produto}          → Nome da aplicação (rpa-exemplo, hatch, ipaas)
{resource}         → Tipo de dado (session, cache, queue, lock)
{id}               → Identificador único (user-123, task-456)
{subresource}      → Opcional (pending, processing, completed)
```

**Benefícios**:
- **Rastreabilidade**: Keys auto-documentadas (vê domain + produto)
- **Debugging**: `KEYS data:rpa-exemplo:*` lista todas as keys da app
- **Segregação**: Namespaces lógicos por aplicação

### 2. Redis Instance Provisioning

#### 2.1 Custom Resource Definition

```yaml
apiVersion: redis.redis.opstreelabs.in/v1beta1
kind: Redis
metadata:
  name: {produto}-redis
  namespace: data-services
  labels:
    domain: {domain}              # data, integration, etc
    product: {produto}            # rpa-exemplo, hatch
    owner: {domain}-team          # data-team
    environment: staging          # ou prod
spec:
  kubernetesConfig:
    image: redis:7.2-alpine       # Versão estável
    imagePullPolicy: IfNotPresent
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi

  # Exporter para Prometheus
  redisExporter:
    enabled: true
    image: quay.io/opstree/redis-exporter:latest

  # Storage
  storage:
    volumeClaimTemplate:
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: gp3
        resources:
          requests:
            storage: 5Gi            # Staging: 5Gi, Prod: 20Gi

  # Configuração Redis
  redisConfig:
    maxmemory: "512mb"              # Match memory limit
    maxmemory-policy: "allkeys-lru" # Cache mode (eviction)
    save: ""                        # Disable RDB snapshots (cache)
    appendonly: "no"                # Disable AOF (cache)
```

**Configurações por Tipo de Uso**:

| Tipo | maxmemory-policy | Persistence | TTL Default |
|------|------------------|-------------|-------------|
| **Cache** | `allkeys-lru` | Nenhuma (RDB/AOF off) | 1h |
| **Sessions** | `volatile-lru` | AOF (appendonly yes) | 24h |
| **Queue** | `noeviction` | RDB + AOF | Sem TTL |
| **Locks** | `volatile-ttl` | Nenhuma | 30s |

#### 2.2 High Availability (Production)

```yaml
# Production: Redis Sentinel (HA)
apiVersion: redis.redis.opstreelabs.in/v1beta1
kind: RedisSentinel
metadata:
  name: {produto}-redis-sentinel
  namespace: data-services
spec:
  size: 3                           # 3 sentinels (quorum=2)
  redisReplication:
    clusterSize: 3                  # 1 master + 2 replicas
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
```

**Rationale**:
- Staging: Single instance (economia)
- Production: Sentinel HA (99.9% uptime)

### 3. TTL Policies (Obrigatórias)

#### 3.1 TTL por Tipo de Key

```yaml
Sessions:    24h (86400s)
Cache:       1h (3600s)
Locks:       30s
Queues:      7d (604800s) - ou sem TTL
Temporary:   5min (300s)
```

#### 3.2 Enforcement

**Application-level** (código da aplicação):

```python
# Python exemplo (redis-py)
import redis
from datetime import timedelta

r = redis.Redis(host='rpa-exemplo-redis.data-services.svc.cluster.local', port=6379)

# ✅ CORRETO: Sempre com TTL
r.setex('data:rpa-exemplo:session:user-123', timedelta(hours=24), 'session_data')

# ❌ ERRADO: Sem TTL (memory leak!)
r.set('data:rpa-exemplo:session:user-123', 'session_data')
```

**Validação** (monitoring):
```bash
# Script de auditoria: /scripts/governance/redis-ttl-audit.sh
# Lista keys sem TTL (TTL=-1)
redis-cli -h $REDIS_HOST SCAN 0 MATCH "data:rpa-exemplo:*" | \
  xargs -I {} redis-cli -h $REDIS_HOST TTL {} | \
  grep -E "^-1$" | wc -l

# Alerta se >100 keys sem TTL
```

### 4. Eviction Policies

#### 4.1 Maxmemory Policies

| Policy | Uso | Comportamento |
|--------|-----|---------------|
| **allkeys-lru** | Cache genérico | Evict qualquer key (LRU) |
| **volatile-lru** | Sessions com TTL | Evict apenas keys com TTL (LRU) |
| **allkeys-lfu** | Cache hot keys | Evict por frequência (LFU) |
| **noeviction** | Queue, locks | Retorna erro quando full |
| **volatile-ttl** | Locks temporários | Evict keys com TTL mais próximo |

**Configuração**:
```bash
# Via Redis CR
spec:
  redisConfig:
    maxmemory-policy: "allkeys-lru"  # Para cache
```

#### 4.2 Memory Limits

```yaml
Staging:
  maxmemory: 512MB
  Kubernetes limit: 512Mi (match)

Production:
  maxmemory: 2GB
  Kubernetes limit: 2Gi (match)
```

**Regra**: `maxmemory` Redis = Kubernetes `memory.limits` (evita OOMKilled)

### 5. Persistence Strategies

#### 5.1 RDB (Redis Database Snapshots)

```yaml
# Desabilitado para cache (data ephemeral)
redisConfig:
  save: ""  # Disable snapshots

# Habilitado para queue/sessions (data crítica)
redisConfig:
  save: "900 1 300 10 60 10000"  # Every 15min if 1 key changed, etc
```

**Quando usar RDB**:
- ✅ Queues (tasks podem ser recriadas, mas loss >5min é ruim)
- ✅ Sessions (perder sessões = UX ruim, mas não crítico)
- ❌ Cache (rebuild do cache é esperado)

#### 5.2 AOF (Append-Only File)

```yaml
# Habilitado apenas para data crítica
redisConfig:
  appendonly: "yes"
  appendfsync: "everysec"  # Fsync every second (balance performance/durability)
```

**Quando usar AOF**:
- ✅ Queues críticas (tasks não podem ser perdidas)
- ✅ Distributed locks (evitar race conditions)
- ❌ Cache (overhead não justifica)
- ❌ Sessions (TTL 24h, loss aceitável)

**Staging vs Production**:
- Staging: Persistence desabilitada (economia I/O)
- Production: RDB + AOF para data crítica

### 6. Connection Configuration

#### 6.1 Service Discovery

```yaml
Redis Service DNS:
  {produto}-redis.data-services.svc.cluster.local:6379

Exemplo:
  rpa-exemplo-redis.data-services.svc.cluster.local:6379
```

#### 6.2 Connection String

```python
# Via Environment Variables (ExternalSecret do Vault)
REDIS_HOST = os.getenv("REDIS_HOST")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD", "")  # Optional

# Python redis-py
import redis
r = redis.Redis(
    host=REDIS_HOST,
    port=REDIS_PORT,
    password=REDIS_PASSWORD,
    decode_responses=True,   # Auto-decode bytes to strings
    socket_timeout=5,        # Connection timeout 5s
    socket_keepalive=True    # TCP keepalive
)
```

### 7. Security

#### 7.1 Authentication

**Redis Operator gera password automaticamente**:

```bash
# 1. Redis Operator cria Secret
kubectl get secret rpa-exemplo-redis -n data-services

# 2. Extrair password
REDIS_PASSWORD=$(kubectl get secret rpa-exemplo-redis -n data-services \
  -o jsonpath='{.data.password}' | base64 -d)

# 3. Armazenar no Vault
vault kv put secret/data/rpa-exemplo/redis \
  host="rpa-exemplo-redis.data-services.svc.cluster.local" \
  port="6379" \
  password="$REDIS_PASSWORD"

# 4. ExternalSecret synca para aplicação
# App lê via env vars (REDIS_HOST, REDIS_PORT, REDIS_PASSWORD)
```

**Rotação de senha**: 90 dias (conforme ADR-063)

#### 7.2 Network Isolation

```yaml
# NetworkPolicy: Apenas namespaces autorizados
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: redis-access
  namespace: data-services
spec:
  podSelector:
    matchLabels:
      app: rpa-exemplo-redis
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          domain: data              # Apenas domínio DATA acessa
    ports:
    - protocol: TCP
      port: 6379
```

### 8. Monitoring & Alerting

#### 8.1 Métricas Obrigatórias (Prometheus)

```yaml
Métricas (via redis-exporter):
  - redis_up                                # Redis online?
  - redis_connected_clients                 # Conexões ativas
  - redis_memory_used_bytes                 # Memória utilizada
  - redis_memory_max_bytes                  # Memória máxima
  - redis_evicted_keys_total                # Keys evictadas (>0 = memory pressure)
  - redis_keyspace_hits_total               # Cache hits
  - redis_keyspace_misses_total             # Cache misses
  - redis_commands_processed_total          # Throughput (ops/s)

Alertas:
  - RedisDown: redis_up == 0
  - RedisMemoryHigh: redis_memory_used / redis_memory_max > 0.85
  - RedisEvictionHigh: rate(redis_evicted_keys_total[5m]) > 100
  - RedisCacheHitRateLow: redis_keyspace_hits / (hits + misses) < 0.80
```

#### 8.2 Grafana Dashboard

Dashboard obrigatório: **"Redis Overview"**
- Memory usage (used, max, evicted keys)
- Throughput (commands/s, connections)
- Cache hit rate (hits / (hits + misses))
- Key TTL distribution (histogram)
- Persistence status (RDB last save, AOF rewrite)

**Localização**: `/domains/observability/infra/grafana/dashboards/redis-overview.json`

### 9. Common Patterns

#### 9.1 Cache Pattern

```python
# Pattern: Cache-aside (lazy loading)
def get_report(report_id: str):
    # 1. Try cache
    cache_key = f"data:rpa-exemplo:cache:report:{report_id}"
    cached = r.get(cache_key)
    if cached:
        return json.loads(cached)

    # 2. Cache miss → fetch from DB
    report = db.query(f"SELECT * FROM reports WHERE id = {report_id}")

    # 3. Store in cache (TTL 1h)
    r.setex(cache_key, 3600, json.dumps(report))
    return report
```

#### 9.2 Session Store Pattern

```python
# Pattern: Session storage (web apps)
def create_session(user_id: str, session_data: dict):
    session_id = str(uuid.uuid4())
    session_key = f"data:rpa-exemplo:session:{session_id}"

    # Store session (TTL 24h)
    r.setex(session_key, 86400, json.dumps(session_data))
    return session_id

def get_session(session_id: str):
    session_key = f"data:rpa-exemplo:session:{session_id}"
    data = r.get(session_key)
    return json.loads(data) if data else None
```

#### 9.3 Queue Pattern (List-based)

```python
# Pattern: Simple queue (FIFO)
def enqueue_task(task: dict):
    queue_key = "data:rpa-exemplo:queue:tasks"
    r.lpush(queue_key, json.dumps(task))  # Push left (producer)

def dequeue_task():
    queue_key = "data:rpa-exemplo:queue:tasks"
    task = r.brpop(queue_key, timeout=5)  # Block pop right (consumer)
    return json.loads(task[1]) if task else None
```

#### 9.4 Distributed Lock Pattern

```python
# Pattern: Distributed lock (RedLock algorithm simplificado)
def acquire_lock(resource: str, ttl: int = 30):
    lock_key = f"data:rpa-exemplo:lock:{resource}"
    lock_id = str(uuid.uuid4())

    # SET NX (only if not exists) + EX (expire)
    acquired = r.set(lock_key, lock_id, nx=True, ex=ttl)
    return (lock_id if acquired else None)

def release_lock(resource: str, lock_id: str):
    lock_key = f"data:rpa-exemplo:lock:{resource}"
    # Lua script: delete only if value matches (atomic)
    script = """
    if redis.call("get", KEYS[1]) == ARGV[1] then
        return redis.call("del", KEYS[1])
    else
        return 0
    end
    """
    r.eval(script, 1, lock_key, lock_id)
```

## Consequências

### Positivas

- ✅ **Nomenclatura determinística**: Keys rastreáveis por domínio/produto
- ✅ **TTL obrigatório**: Previne memory leaks
- ✅ **Eviction policies claras**: Cache vs Queue comportamentos distintos
- ✅ **HA em produção**: Sentinel (99.9% uptime)
- ✅ **Observabilidade**: Métricas + alertas + dashboards padronizados
- ✅ **Security**: Passwords no Vault, NetworkPolicies

### Negativas

- ⚠️ **Key naming verboso**: `data:rpa-exemplo:cache:report:123` vs `report:123`
  - **Rationale**: Rastreabilidade > brevidade
- ⚠️ **Persistence overhead**: RDB/AOF em produção = I/O adicional
  - **Rationale**: Durabilidade > performance (para queue/sessions)

### Riscos

- 🟡 **Eviction inesperada**: Cache hit rate baixo se maxmemory muito baixo
  - **Mitigação**: Alertas + autoscaling (aumentar memory se eviction >100/min)
- 🟡 **TTL esquecido**: Devs esquecem de setar TTL → memory leak
  - **Mitigação**: Auditoria semanal (script `redis-ttl-audit.sh`) + code review

## Alternatives Consideradas

### Alternativa 1: Redis single-node sem Operator

**Pros**: Simplicidade (StatefulSet + Service)
**Cons**: Sem HA, sem monitoring auto, gestão manual
**Decisão**: ❌ Rejeitado - Operator provê HA + monitoring + automação

### Alternativa 2: Prefixo produto sem domain (`rpa-exemplo:cache:*`)

**Pros**: Keys mais curtas
**Cons**: Não rastreável por domínio (analytics cross-domain impossível)
**Decisão**: ❌ Rejeitado - Domain prefix essencial para governança

### Alternativa 3: Redis Cluster (sharding)

**Pros**: Horizontal scaling (>20GB data)
**Cons**: Complexidade, overhead, aplicações atuais <5GB
**Decisão**: ❌ Rejeitado - Sentinel suficiente (vertical scaling até 64GB)

## Implementação

### Scripts de Automação

```bash
# /scripts/onboarding/provision-redis.sh
# Cria Redis CR + ExternalSecret automaticamente

./provision-redis.sh \
  --produto rpa-exemplo \
  --environment staging \
  --type cache \
  --memory 512Mi
```

### Validação

```bash
# 1. Verificar Redis CR criado
kubectl get redis rpa-exemplo-redis -n data-services

# 2. Verificar pods Running
kubectl get pods -n data-services -l app=rpa-exemplo-redis

# 3. Verificar Service DNS
nslookup rpa-exemplo-redis.data-services.svc.cluster.local

# 4. Testar conexão
redis-cli -h rpa-exemplo-redis.data-services.svc.cluster.local \
  -a $REDIS_PASSWORD \
  PING
# Esperado: PONG

# 5. Verificar exporter (Prometheus metrics)
kubectl port-forward -n data-services svc/rpa-exemplo-redis 9121:9121
curl http://localhost:9121/metrics | grep redis_up
# Esperado: redis_up 1
```

### Kyverno Policy (Redis CR Validation)

```yaml
# Validar nomenclatura Redis CR
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: validate-redis-cr-naming
spec:
  validationFailureAction: audit
  rules:
  - name: check-redis-cr-name
    match:
      any:
      - resources:
          kinds:
          - Redis
          namespaces:
          - data-services
    validate:
      message: "Redis CR name deve seguir padrão: {produto}-redis"
      pattern:
        metadata:
          name: "*-redis"
```

## Referências

- [Redis Best Practices](https://redis.io/docs/management/optimization/)
- [Redis Eviction Policies](https://redis.io/docs/reference/eviction/)
- [Redis Operator (OpsTree)](https://ot-redis-operator.netlify.app/)
- [ADR-047: Estrutura Corporativa de Domínios](adr-047-estrutura-corporativa-dominios.md)
- [ADR-048: Naming Conventions Determinísticas](adr-048-naming-conventions-deterministicas.md)
- [ADR-060: PostgreSQL Governance Standards](adr-060-postgresql-governance-standards.md)
- [ADR-063: Secrets Management Lifecycle](adr-063-secrets-management-lifecycle.md) (planejado)

---

**Próximos ADRs Relacionados**:
- ADR-062: RabbitMQ Governance Standards
- ADR-063: Secrets Management Lifecycle
