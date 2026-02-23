# ADR-060: PostgreSQL Governance Standards

> **Status**: Proposto
> **Data**: 2026-02-23
> **Decisores**: Platform Team + Data Team
> **Contexto SAD**: Conformidade com ADR-047 (Domínios Corporativos), ADR-048 (Naming Conventions)

## Contexto

O projeto Kubernetes utiliza PostgreSQL RDS compartilhado (Marco 3 operacional) para múltiplas aplicações. Atualmente **não existem padrões documentados** para:

- Nomenclatura de databases, schemas, users
- Processos de criação e migrations
- Políticas de backup e retention
- Connection pooling e performance tuning
- Monitoring e alertas

Essa falta de padronização cria riscos:
- **Conflitos de nomenclatura** entre aplicações
- **Migrations desorganizadas** sem rastreabilidade
- **Performance degradada** por falta de tuning
- **Perda de dados** por backups inadequados
- **Dificuldade de onboarding** de novas aplicações

Este ADR estabelece **padrões determinísticos e automaticamente validáveis** para governança PostgreSQL.

## Decisão

### 1. Naming Conventions (Determinísticas)

#### 1.1 Database Names

```yaml
Formato: {produto}
Regex: ^[a-z][a-z0-9_]{0,62}$
Encoding: UTF8
Collation: en_US.UTF-8

Exemplos Válidos:
✅ hatch_dw              # ETL Hatch (data warehouse)
✅ ipaas                 # iPaaS microservices
✅ rpa_exemplo           # RPA Exemplo
✅ sonarqube             # SonarQube (platform)

Exemplos Inválidos:
❌ HatchDW               # Uppercase não permitido
❌ hatch-dw              # Hyphen não permitido (use underscore)
❌ hatch_dw_staging      # Environment no database name (use schemas)
```

**Rationale**:
- Snake_case é padrão PostgreSQL (identifiers case-sensitive entre quotes)
- Produto único = isolamento lógico
- Sem environment suffix (usar schemas ou databases separados)

#### 1.2 Database Users

```yaml
Formato: {produto}_user | {produto}_readonly
Regex: ^[a-z][a-z0-9_]{0,62}_(user|readonly|admin)$

Exemplos:
✅ hatch_dw_user         # User aplicação (read-write)
✅ hatch_dw_readonly     # User read-only (analytics, BI)
✅ hatch_dw_admin        # User admin (migrations)

Sufixos:
- _user      → Read-write da aplicação
- _readonly  → Read-only (Power BI, Metabase, analistas)
- _admin     → Migrations e DDL (CI/CD apenas)
```

#### 1.3 Schema Names

```yaml
Formato: {produto} | {produto}_{tenant}
Regex: ^[a-z][a-z0-9_]{0,62}$

Single-tenant (padrão):
✅ rpa_exemplo           # Schema único = database name

Multi-tenant (quando necessário):
✅ hatch_dw
   ├── hatch_alvo        # Tenant: alvo
   ├── hatch_aspbras     # Tenant: aspbras
   ├── hatch_bcbr        # Tenant: bcbr
   └── ... (9 schemas)

Public schema:
⚠️ Usar apenas para extensions (não dados de aplicação)
```

**Rationale**:
- Single-tenant: 1 schema = simplicidade
- Multi-tenant: Schema-per-tenant = isolamento lógico + row-level security

### 2. Database Provisioning Workflow

#### 2.1 Staging Environment

```sql
-- 1. Criar database
CREATE DATABASE {produto}
  OWNER postgres
  ENCODING 'UTF8'
  LC_COLLATE 'en_US.UTF-8'
  LC_CTYPE 'en_US.UTF-8'
  TEMPLATE template0;

-- 2. Criar users
\c {produto};
CREATE USER {produto}_user WITH PASSWORD '${VAULT_PASSWORD}';
CREATE USER {produto}_readonly WITH PASSWORD '${VAULT_PASSWORD_RO}';

-- 3. Criar schema (se não usar public)
CREATE SCHEMA {produto} AUTHORIZATION {produto}_user;

-- 4. Grants aplicação (read-write)
GRANT CONNECT ON DATABASE {produto} TO {produto}_user;
GRANT ALL PRIVILEGES ON SCHEMA {produto} TO {produto}_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA {produto} TO {produto}_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA {produto} TO {produto}_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA {produto}
  GRANT ALL PRIVILEGES ON TABLES TO {produto}_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA {produto}
  GRANT ALL PRIVILEGES ON SEQUENCES TO {produto}_user;

-- 5. Grants read-only
GRANT CONNECT ON DATABASE {produto} TO {produto}_readonly;
GRANT USAGE ON SCHEMA {produto} TO {produto}_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA {produto} TO {produto}_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA {produto}
  GRANT SELECT ON TABLES TO {produto}_readonly;
```

#### 2.2 Production Environment

**Diferenças vs Staging**:
- Database separado: `{produto}_prod` (ou usar mesmo database com schemas `{produto}_prod`)
- Connection limits mais altos
- Backup retention: 30 dias (vs 7 dias staging)

**Recomendação**: Manter mesmo database name, segregar por RDS instance (staging RDS vs prod RDS).

### 3. Connection Configuration

#### 3.1 Connection Pooling (PgBouncer Pattern)

```yaml
Pool Mode: transaction           # Stateless apps (recomendado)
Pool Size:
  Staging:    10 connections
  Production: 25 connections (auto-scale até 100)

Formula:
  pool_size = max_expected_concurrent_requests / avg_request_duration_seconds

Exemplo: 100 req/s × 0.1s avg = 10 connections

Timeouts:
  idle_transaction_timeout: 60s  # Kill idle transactions
  statement_timeout: 30s         # Kill slow queries
```

**Implementação**:
- Apps não usam PgBouncer diretamente (overhead)
- Kubernetes connection via RDS endpoint direto
- RDS max_connections: 100 (db.t3.medium) → 500 (db.m5.large)

#### 3.2 Connection String Pattern

```python
# Via Environment Variables (ExternalSecret do Vault)
DATABASE_URL = "postgresql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

# Exemplo
DATABASE_URL = "postgresql://rpa_exemplo_user:***@k8s-platform-prod-postgresql.xyz.rds.amazonaws.com:5432/rpa_exemplo"

# SSL obrigatório (production)
DATABASE_URL += "?sslmode=require"
```

### 4. Migrations

#### 4.1 Migration Tools (por Linguagem)

| Linguagem | Tool | Naming Pattern | Location |
|-----------|------|----------------|----------|
| **Python** | Alembic | `YYYY-MM-DD_HHmm_{description}.py` | `/migrations/versions/` |
| **Go** | golang-migrate | `YYYYMMDDHHMMSS_{description}.up.sql` | `/migrations/` |
| **Java** | Flyway | `V{version}__{description}.sql` | `/db/migration/` |
| **.NET** | Entity Framework | `{timestamp}_{description}.cs` | `/Migrations/` |

**Exemplo Alembic (Python)**:
```
migrations/versions/
├── 2026-02-23_1030_initial_schema.py
├── 2026-02-24_1500_add_users_table.py
└── 2026-02-25_0900_add_index_users_email.py
```

#### 4.2 Migration Workflow

```bash
# 1. Dev: Criar migration
alembic revision --autogenerate -m "add users table"

# 2. Review migration (PR/MR)
# Validar DDL, indexes, constraints

# 3. CI/CD: Dry-run (staging)
alembic upgrade head --sql > migration.sql
psql -h $STAGING_DB -U {produto}_admin -d {produto} < migration.sql

# 4. Production: Deploy via CI/CD
# GitLab CI job: db-migrate (manual trigger, approval required)
```

**Reversibilidade**:
- Toda migration UP deve ter DOWN
- Migrations destrutivas (DROP TABLE) requerem aprovação manual

### 5. Backup & Recovery

#### 5.1 Backup Strategy

| Environment | RDS Automated Backup | Manual Snapshots | Retention |
|-------------|---------------------|------------------|-----------|
| **Staging** | Daily (3AM UTC) | Weekly (Sunday) | 7 dias |
| **Production** | Daily (3AM UTC) | Daily + Quarterly | 30 dias (daily), 7 anos (quarterly) |

**Backup Window**: 03:00-04:00 UTC (00:00-01:00 BRT - low traffic)

#### 5.2 Recovery Testing

```bash
# Mensal: Restore backup em ambiente isolado
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier test-restore-{YYYYMMDD} \
  --db-snapshot-identifier {snapshot-id}

# Validar:
# 1. Database conecta
# 2. Tables existem
# 3. Row count correto
# 4. Queries funcionam
```

**RTO/RPO**:
- Staging: RTO 4h, RPO 24h (aceitável)
- Production: RTO 1h, RPO 5min (via PITR - Point-in-Time Recovery)

### 6. Performance Tuning

#### 6.1 Query Performance

```sql
-- Obrigatório: pg_stat_statements extension
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Slow query log (>5s)
ALTER DATABASE {produto} SET log_min_duration_statement = '5000'; -- 5s

-- Monitoring queries
SELECT
  query,
  calls,
  total_exec_time,
  mean_exec_time,
  max_exec_time
FROM pg_stat_statements
WHERE mean_exec_time > 1000  -- >1s
ORDER BY total_exec_time DESC
LIMIT 20;
```

#### 6.2 Index Strategy

```sql
-- Regra: WHERE/JOIN columns devem ter indexes
-- Exceção: Tabelas pequenas (<1000 rows)

-- Índices obrigatórios
CREATE INDEX idx_{table}_{column} ON {table}({column});

-- Índices compostos (multi-column WHERE)
CREATE INDEX idx_{table}_{col1}_{col2} ON {table}({col1}, {col2});

-- Índices parciais (filtered rows)
CREATE INDEX idx_{table}_{column}_active
  ON {table}({column})
  WHERE status = 'active';
```

**Index Naming Convention**:
```
idx_{table}_{columns}[_{filter}]

Exemplos:
✅ idx_users_email
✅ idx_orders_user_id_created_at
✅ idx_users_email_active
```

### 7. Monitoring & Alerting

#### 7.1 Métricas Obrigatórias (Prometheus/CloudWatch)

```yaml
Métricas:
  - postgresql_connections_active
  - postgresql_connections_max
  - postgresql_queries_duration_seconds (p95, p99)
  - postgresql_slow_queries_total (>5s)
  - postgresql_database_size_bytes
  - postgresql_deadlocks_total

Alertas (via Prometheus):
  - ConnectionsHigh: >80% max_connections
  - SlowQueriesHigh: >10 queries/min >5s
  - DiskSpaceHigh: >80% disk usage
  - ReplicationLag: >60s (se Multi-AZ)
```

#### 7.2 Grafana Dashboard

Dashboard obrigatório: **"PostgreSQL RDS Overview"**
- Connections (active, idle, waiting)
- Query performance (QPS, latency p95/p99)
- Database size growth
- Top 10 slow queries (pg_stat_statements)
- Locks e deadlocks

**Localização**: `/domains/observability/infra/grafana/dashboards/postgresql-rds.json`

### 8. Security

#### 8.1 Passwords (Vault Management)

```bash
# 1. Gerar senha segura (32 chars)
PASSWORD=$(openssl rand -base64 32)

# 2. Criar user no PostgreSQL
psql -h $RDS_ENDPOINT -U postgres -c \
  "CREATE USER {produto}_user WITH PASSWORD '$PASSWORD';"

# 3. Armazenar no Vault
vault kv put secret/data/{produto}/postgresql \
  username="{produto}_user" \
  password="$PASSWORD" \
  database="{produto}" \
  host="$RDS_ENDPOINT" \
  port="5432"

# 4. ExternalSecret synca para K8s Secret
# Aplicação lê via env vars (DB_HOST, DB_USER, DB_PASSWORD)
```

**Rotação de senhas**: 90 dias (conforme ADR-063)

#### 8.2 SSL/TLS Obrigatório

```python
# Production: sslmode=require
DATABASE_URL = "postgresql://user:pass@host:5432/db?sslmode=require"

# RDS Certificate
# https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html
```

### 9. Multi-Tenancy Patterns

#### 9.1 Quando usar Schema-per-Tenant

**Usar quando**:
- <50 tenants (ex: Hatch com 9 tenants)
- Cada tenant tem schema similar
- Queries cross-tenant necessárias (analytics)

**Exemplo**:
```sql
-- Database: hatch_dw
CREATE SCHEMA hatch_alvo;
CREATE SCHEMA hatch_aspbras;
-- ... (9 schemas)

-- Aplicação conecta no schema via search_path
SET search_path TO hatch_alvo, public;
SELECT * FROM propostas;  -- hatch_alvo.propostas
```

#### 9.2 Quando usar Database-per-Tenant

**Usar quando**:
- >50 tenants
- Isolamento total necessário (compliance, LGPD)
- Backups independentes por tenant

**Exemplo**:
```sql
CREATE DATABASE tenant_cliente_a;
CREATE DATABASE tenant_cliente_b;
-- ... (N databases)
```

**Trade-off**: Mais databases = mais overhead (connections, backups, migrations).

## Consequências

### Positivas

- ✅ **Nomenclatura determinística**: Zero ambiguidade, validável via regex
- ✅ **Onboarding padronizado**: Scripts automatizam criação de databases
- ✅ **Rastreabilidade**: Migrations versionadas, backups automatizados
- ✅ **Performance**: Query tuning + indexes obrigatórios
- ✅ **Segurança**: Passwords no Vault, SSL obrigatório, least-privilege users
- ✅ **Observabilidade**: Métricas + alertas + dashboards padronizados

### Negativas

- ⚠️ **Rigidez**: Naming conventions rígidas podem frustrar devs habituados a outros padrões
- ⚠️ **Overhead**: Provisioning manual inicial (mitigado por scripts de automação)
- ⚠️ **Single RDS**: Compartilhamento pode causar contenção (mitigado por monitoring + scaling)

### Riscos

- 🔴 **RDS Shared**: Aplicação mal comportada pode afetar outras
  - **Mitigação**: Connection limits per-user, slow query killing, monitoring
- 🟡 **Migrations breaking**: Migration mal escrita pode travar database
  - **Mitigação**: Dry-run obrigatório em staging, review de migrations

## Alternatives Consideradas

### Alternativa 1: Database-per-App com RDS separados

**Pros**: Isolamento total, sem contenção
**Cons**: Custo 5x maior (~$250/mês vs $50/mês shared)
**Decisão**: ❌ Rejeitado - Custo não justifica (staging aceita shared RDS)

### Alternativa 2: Usar Public Schema (sem schemas customizados)

**Pros**: Simplicidade
**Cons**: Conflitos de nomenclatura (tabelas de apps diferentes no mesmo schema)
**Decisão**: ❌ Rejeitado - Schema-per-app é mais seguro

### Alternativa 3: CamelCase para database names

**Pros**: Legibilidade (HatchDW)
**Cons**: Case-sensitivity issues no PostgreSQL (precisa quotes sempre)
**Decisão**: ❌ Rejeitado - Snake_case é padrão PostgreSQL

## Implementação

### Scripts de Automação

```bash
# /scripts/onboarding/provision-database.sh
# Cria database + users + grants automaticamente

./provision-database.sh \
  --produto rpa-exemplo \
  --environment staging \
  --multi-tenant false
```

### Validação

```bash
# Validar nomenclatura
psql -h $RDS_ENDPOINT -U postgres -c "\l" | grep -E '^[a-z][a-z0-9_]{0,62}$'

# Validar users
psql -h $RDS_ENDPOINT -U postgres -c "\du" | grep -E '_user$|_readonly$|_admin$'

# Validar slow queries
SELECT COUNT(*) FROM pg_stat_statements WHERE mean_exec_time > 5000;
# Esperado: <10 queries
```

### Kyverno Policy (ExternalSecret Validation)

```yaml
# Validar que secrets PostgreSQL seguem padrão
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: validate-postgresql-externalsecret
spec:
  validationFailureAction: audit
  rules:
  - name: check-postgresql-secret-keys
    match:
      any:
      - resources:
          kinds:
          - ExternalSecret
          names:
          - "*-postgresql-credentials"
    validate:
      message: "PostgreSQL ExternalSecret deve ter keys: username, password, host, port, database"
      pattern:
        spec:
          data:
          - secretKey: "DB_USER"
          - secretKey: "DB_PASSWORD"
          - secretKey: "DB_HOST"
          - secretKey: "DB_PORT"
          - secretKey: "DB_NAME"
```

## Referências

- [PostgreSQL Naming Conventions](https://wiki.postgresql.org/wiki/Don%27t_Do_This#Don.27t_use_upper_case_table_or_column_names)
- [Alembic Migrations](https://alembic.sqlalchemy.org/en/latest/)
- [AWS RDS Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_BestPractices.html)
- [ADR-047: Estrutura Corporativa de Domínios](adr-047-estrutura-corporativa-dominios.md)
- [ADR-048: Naming Conventions Determinísticas](adr-048-naming-conventions-deterministicas.md)
- [ADR-063: Secrets Management Lifecycle](adr-063-secrets-management-lifecycle.md) (planejado)

---

**Próximos ADRs Relacionados**:
- ADR-061: Redis Governance Standards
- ADR-062: RabbitMQ Governance Standards
- ADR-063: Secrets Management Lifecycle
