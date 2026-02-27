# GOV-002: PostgreSQL Governance & Best Practices

> **Versão**: 1.0
> **Data**: 2026-02-27
> **Status**: Ativo
> **Referências**: ADR-051, ADR-054, ADR-060
> **Audiência**: Desenvolvedores, DBAs, Platform Team

---

## Visão Geral

PostgreSQL RDS é o banco relacional da plataforma. Este guia consolida padrões de nomenclatura, provisionamento, performance, backup e monitoring.

**Decisão Arquitetural**: AWS RDS (não Kubernetes Operator) — ADR-051.

---

## Naming Conventions

**Referência completa**: [ADR-060: PostgreSQL Governance Standards](../adr/adr-060-postgresql-governance-standards.md)

### Database Names

```yaml
Formato: {produto}
Regex: ^[a-z][a-z0-9_]{0,62}$
Encoding: UTF8 | Collation: en_US.UTF-8

Exemplos:
✅ hatch_dw              # ETL Hatch (data warehouse)
✅ ipaas                 # iPaaS microservices
✅ rpa_exemplo           # RPA Exemplo

❌ HatchDW               # Uppercase proibido
❌ hatch-dw              # Hyphen proibido (use underscore)
❌ hatch_dw_staging      # Environment no nome proibido
```

### Database Users

```yaml
Formato: {produto}_user | {produto}_readonly | {produto}_admin
Regex: ^[a-z][a-z0-9_]{0,62}_(user|readonly|admin)$

Sufixos:
  _user      → Read-write da aplicação
  _readonly  → Read-only (BI, analytics)
  _admin     → Migrations e DDL (CI/CD apenas)
```

### Schemas

```yaml
Formato: {produto} | {produto}_{tenant}
Regex: ^[a-z][a-z0-9_]{0,62}$

Single-tenant: 1 schema = nome do database
Multi-tenant: schema-per-tenant (ex: hatch_alvo, hatch_aspbras)
Public schema: Apenas para extensions (nunca dados de aplicação)
```

---

## Provisionamento

### Staging

```sql
-- 1. Criar database
CREATE DATABASE {produto}
  OWNER postgres ENCODING 'UTF8'
  LC_COLLATE 'en_US.UTF-8' LC_CTYPE 'en_US.UTF-8'
  TEMPLATE template0;

-- 2. Criar users
\c {produto};
CREATE USER {produto}_user WITH PASSWORD '${VAULT_PASSWORD}';
CREATE USER {produto}_readonly WITH PASSWORD '${VAULT_PASSWORD_RO}';

-- 3. Criar schema
CREATE SCHEMA {produto} AUTHORIZATION {produto}_user;

-- 4. Grants read-write
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

### Connection String Pattern

```
postgresql://{produto}_user:{VAULT_PASSWORD}@{RDS_ENDPOINT}:5432/{produto}?sslmode=require
```

Secrets via Vault + ExternalSecrets (GOV-006).

---

## Connection Pooling

```yaml
Pool Mode: transaction (stateless apps, recomendado)
Pool Size:
  Staging:    10 connections
  Production: 25 connections (auto-scale até 100)

Formula: pool_size = max_concurrent_requests / avg_request_duration_seconds

Timeouts:
  idle_transaction_timeout: 60s
  statement_timeout: 30s
```

---

## Migrations

### Tools por Linguagem

| Linguagem | Tool | Naming Pattern |
|-----------|------|----------------|
| Python | Alembic | `YYYY-MM-DD_HHmm_{description}.py` |
| Go | golang-migrate | `YYYYMMDDHHMMSS_{description}.up.sql` |
| Java | Flyway | `V{version}__{description}.sql` |
| .NET | Entity Framework | `{timestamp}_{description}.cs` |

### Workflow

1. **Dev**: Criar migration (`alembic revision --autogenerate -m "add users table"`)
2. **Review**: PR/MR com validação de DDL, indexes, constraints
3. **Staging**: Dry-run via CI/CD
4. **Production**: Deploy via CI/CD (manual trigger, approval required)

**Regra**: Toda migration UP deve ter DOWN. Migrations destrutivas (DROP TABLE) requerem aprovação manual.

---

## Backup & Recovery

| Environment | Automated Backup | Manual Snapshots | Retention |
|-------------|-----------------|------------------|-----------|
| Staging | Daily 3AM UTC | Weekly (Sunday) | 7 dias |
| Production | Daily 3AM UTC | Pre-deploy + Weekly | 30 dias |

**DR Adicional**: Velero backups para manifests Kubernetes — [ADR-078](../adr/adr-078-velero-backup-dr-implementation.md).

---

## Monitoring

### Métricas Essenciais (Prometheus)

| Métrica | Alerta | Threshold |
|---------|--------|-----------|
| Active connections | `PostgreSQLConnectionsHigh` | > 80% max_connections |
| Replication lag | `PostgreSQLReplicationLag` | > 30s |
| Disk usage | `PostgreSQLDiskUsage` | > 80% |
| Slow queries | `PostgreSQLSlowQueries` | > 10/min |

### Runbooks

- [PostgreSQL Connections High](../../domains/observability/docs/runbooks/dt005-postgresql-connections-high.md)
- [PostgreSQL Down](../../domains/observability/docs/runbooks/dt005-postgresql-down.md)

---

## Best Practices

1. **Sempre usar SSL**: `sslmode=require` em todas as connection strings
2. **Nunca hardcode passwords**: Usar Vault + ExternalSecrets (GOV-006)
3. **Indexes**: Criar indexes para queries frequentes; monitorar via `pg_stat_user_indexes`
4. **VACUUM**: RDS auto-vacuum habilitado; monitorar bloat via `pg_stat_user_tables`
5. **Extensions**: Instalar no schema `public` (não no schema de dados)

---

## Referências

- [ADR-051: PostgreSQL RDS vs Operator](../adr/adr-051-postgresql-rds-vs-operator.md)
- [ADR-054: PostgreSQL Provisioning Automation](../adr/adr-054-postgresql-database-provisioning-automation.md)
- [ADR-060: PostgreSQL Governance Standards](../adr/adr-060-postgresql-governance-standards.md)
