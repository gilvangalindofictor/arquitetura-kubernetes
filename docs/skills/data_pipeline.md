# Skill: Data Pipeline

**Nota**: Aplicável a futuras implementações de pipelines de dados na plataforma (ETL, stream processing, etc.).

## Patterns

**Batch Processing**:
- Apache Airflow (DAGs)
- Kubernetes CronJobs

**Stream Processing**:
- Apache Kafka
- Apache Flink / Spark Streaming

**Storage**:
- Data Lake (S3 / MinIO)
- Data Warehouse (Snowflake, BigQuery, or self-hosted ClickHouse)

## Principles

1. **Idempotency**: pipelines podem re-run sem efeitos colaterais
2. **Monitoring**: logs + metrics de cada step
3. **Error Handling**: retry logic, dead letter queues
4. **Versioning**: schemas versionados (Avro, Protobuf)

---

_Skill v1.0 - Para futuras implementações_
