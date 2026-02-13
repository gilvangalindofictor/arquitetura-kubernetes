# STAGING - Verificação ao Vivo (2026-02-13)

Este arquivo registra as verificações ao vivo realizadas em 2026-02-13 para complementar `STAGING-ANALYSIS-FINDINGS.md`.

Fonte: execução de `check-versions.sh` com `AWS_PROFILE=k8s-platform-prod` e consultas `kubectl`.

- PostgreSQL (STAGING): AWS RDS `postgres` engine, version **16.4** — identifier `k8s-platform-prod-postgresql` (status: available)
- Redis (STAGING):
  - Operator: **Spotahome Redis Operator 3.3.0** (Helm chart `redis-operator-3.3.0`, appVersion `1.3.0`)
  - Server image(s): **redis:6.2.6-alpine** (namespace `data-services`)
  - ElastiCache: nenhum ReplicationGroup/CacheCluster encontrado — Redis está em-cluster no Kubernetes
- RabbitMQ (STAGING):
  - Operator: **RabbitMQ Cluster Operator 2.19.0** (`rabbitmqoperator/cluster-operator:2.19.0`)
  - Server image: **rabbitmq:3.13-management**

Observação: o RDS (PostgreSQL) foi obtido via `aws rds describe-db-instances`; não foram retornados recursos ElastiCache, confirmando que Redis está provisionado no cluster Kubernetes em vez do serviço ElastiCache.

Recomendação: incorporar estas linhas no arquivo `STAGING-ANALYSIS-FINDINGS.md` na seção de achados, e adicionar data de verificação e autor da verificação.

-- Auditoria automatizada (execução local) — 2026-02-13
