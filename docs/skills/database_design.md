# Skill: Database Design

## Aplicabilidade

Este projeto usa bancos de dados gerenciados (PostgreSQL, Redis, RabbitMQ) para aplicações da plataforma (GitLab, Harbor, Keycloak).

## Princípios

### PostgreSQL (Atual: RDS, Futuro: CloudNativePG Operator)

**Design Decisions**:
- Single-AZ staging (custo), Multi-AZ production (HA)
- db.t3.medium para staging (ajustar conforme carga)
- 500GB storage com autoscaling
- Backups automáticos (7 dias retention staging)

**Schema Management**:
- Migrations via aplicação (GitLab, Harbor, Keycloak gerenciam próprios schemas)
- NUNCA modificar schema manualmente via SQL
- Cada aplicação tem database próprio (isolamento)

**Security**:
- Security group restritivo (apenas EKS nodes + Lambda unseal)
- Passwords via Vault (migração em andamento)
- SSL/TLS obrigatório

**Monitoring**:
- CloudWatch metrics (CPU, connections, storage)
- Alertas: connection pool exhaustion, disk space < 20%

### Redis (Operator-based)

**Topology**:
- Sentinel mode: 3 sentinels + 1 master
- AOF persistence habilitado
- Replication automática

**Usage**:
- Cache para GitLab
- Session storage para aplicações

### RabbitMQ (Operator-based)

**Topology**:
- 1 replica staging, 3 replicas production
- Quorum queues para durabilidade
- Management UI habilitado

## Regras Invioláveis

1. **NUNCA compartilhar database entre aplicações não relacionadas**
2. **NUNCA migration destrutiva sem backup verificado**
3. **NUNCA query em campo de busca sem índice** (performance)
4 **NUNCA expor dados sensíveis em logs**

---

_Skill v1.0 - Focado em gerenciamento de databases da plataforma_
