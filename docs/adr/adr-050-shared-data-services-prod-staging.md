# ADR-050: Shared Data Services (PostgreSQL/Redis) between Production and Staging

| Campo       | Valor                                        |
|-------------|----------------------------------------------|
| Status      | Aceito                                       |
| Data        | 2026-02-09                                   |
| Autores     | Platform Team                                |
| Revisores   | AWS Specialist, Security & Compliance        |
| Contexto    | Marco 3 - Platform Services Deployment       |

---

## Contexto

Durante o deploy dos serviços de plataforma (GitLab, SonarQube, ArgoCD, Keycloak, Harbor), identificou-se que múltiplos ambientes (PROD e STAGING) compartilham a mesma instância de data services:

- **PostgreSQL RDS:** `k8s-platform-prod-postgresql` (db.t3.medium, Multi-AZ)
- **Redis Cluster:** `rfrm-redis.data-services` (Spotahome Operator, 3 replicas)

### Estado Atual

```
┌─────────────────────────────────────────────────────────────┐
│                    EKS Cluster (Shared)                      │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  Namespace: data-services-prod                               │
│  ├─ PostgreSQL RDS: k8s-platform-prod-postgresql            │
│  │   └─ Used by: GitLab (prod + staging), SonarQube (prod) │
│  └─ Redis: rfrm-redis                                        │
│      └─ Used by: GitLab (prod + staging)                    │
│                                                               │
│  Namespace: gitlab (shared)                                  │
│  └─ GitLab instance serving PROD and STAGING via projects   │
│                                                               │
│  Namespace: gitlab-staging                                   │
│  └─ Empty (originally planned separate instance)            │
└─────────────────────────────────────────────────────────────┘
```

### Problema

Esta arquitetura viola princípios de isolamento de ambientes:

1. **Blast radius:** Falha em STAGING pode impactar PROD (ex: query lenta saturando conexões)
2. **Security:** Breach em STAGING namespace pode expor dados PROD
3. **Compliance:** LGPD/GDPR requer isolamento de dados sensíveis
4. **Drift management:** Estado dificulta rollback independente

---

## Decisão

**Aceitar temporariamente** o compartilhamento de data services entre PROD e STAGING com **mitigações obrigatórias** e **plano de migração definido**.

### Justificativa

**Pragmática:**
- Recursos já provisionados e funcionais há 7+ dias
- Redeployar = downtime desnecessário + risco operacional
- FinOps: db.t3.medium suporta ambas cargas atuais (<30% CPU/RAM)

**Técnica:**
- GitLab é **single-tenant por design** (um namespace, múltiplos projects/groups)
- Network Policies implementadas isolam traffic cross-namespace
- RDS separate databases per environment (`gitlab_prod`, `gitlab_staging`)

---

## Mitigações Implementadas

### 1. Network Isolation

```yaml
# NetworkPolicy: data-services-prod
spec:
  podSelector: {}
  policyTypes: [Ingress]
  ingress:
    # Allow PROD apps ONLY
    - from:
      - namespaceSelector:
          matchLabels:
            environment: prod
      ports: [5432, 6379, 5672]

    # Allow GitLab (shared)
    - from:
      - namespaceSelector:
          matchLabels:
            name: gitlab
      ports: [5432, 6379]
```

### 2. Database Segregation

| Service   | Database Name  | User          | Namespace Access     |
|-----------|----------------|---------------|----------------------|
| GitLab    | `gitlab`       | `gitlab_user` | gitlab (shared)      |
| SonarQube | `sonarqube`    | `sonar_user`  | sonarqube-prod ONLY  |
| Keycloak  | `keycloak`     | `kc_user`     | keycloak-prod ONLY   |

### 3. Resource Quotas

```yaml
# Namespace: gitlab
spec:
  hard:
    requests.cpu: "4"
    requests.memory: "8Gi"
    limits.cpu: "8"
    limits.memory: "16Gi"
    persistentvolumeclaims: "10"
```

### 4. Monitoring & Alerting

- **CloudWatch Alarms:**
  - RDS CPU > 70% (warning), > 85% (critical)
  - RDS connections > 80% max_connections
  - Redis memory > 75%

- **Prometheus Rules:**
  - PostgreSQL slow queries (>5s)
  - Connection pool exhaustion

### 5. Backup & Recovery

- **RDS:** Automated backups (7 days retention) + manual snapshot before migrations
- **Redis:** Bitnami sealed secrets backup to S3 (daily)

---

## Alternativas Consideradas

### A. Separate RDS per Environment

**Custo:**
- PROD: db.t3.medium ($52.56/mês)
- STAGING: db.t3.small ($26.28/mês)
- **Total:** $78.84/mês (+$26.28 vs atual)

**Prós:**
- Full isolation
- Independent scaling
- Separate backup policies

**Contras:**
- FinOps: overprovisioning para carga STAGING (~5 queries/min)
- Operational overhead (2 RDS instances to manage)
- Migration downtime (GitLab data export/import)

**Decisão:** Rejected — custo/benefício desfavorável no curto prazo

### B. CloudNativePG Operator (K8s-native)

**Prós:**
- No RDS cost
- Full GitOps integration
- Faster provisioning

**Contras:**
- Operational burden (gerenciar PostgreSQL in-cluster)
- Backup complexity (PVC snapshots vs RDS automated)
- No Multi-AZ HA out-of-the-box (requires PV replication)

**Decisão:** Rejected — priorizar simplicidade operacional (RDS managed)

### C. Separate GitLab Instances

**Prós:**
- True environment isolation
- Separate RBAC/SSO configs

**Contras:**
- Double licensing cost (GitLab CE = free, mas infrastructure cost)
- User management overhead (sync users across instances)
- CI/CD complexity (runners per instance)

**Decisão:** Rejected — GitLab design nativo é multi-tenant via projects

---

## Plano de Migração (Marco 4 - Q2 2026)

### Fase 1: Preparação (Semana 1-2)

1. **Provisionar RDS STAGING separado**
   ```hcl
   module "postgresql_staging" {
     source = "../../modules/postgresql"
     cluster_name = "k8s-platform-staging"
     instance_class = "db.t3.small"
     multi_az = false  # Single-AZ para staging
   }
   ```

2. **Snapshot RDS PROD**
   ```bash
   aws rds create-db-snapshot \
     --db-instance-identifier k8s-platform-prod-postgresql \
     --db-snapshot-identifier gitlab-pre-migration-$(date +%Y%m%d)
   ```

### Fase 2: Migração (Janela de Manutenção - Sábado 3AM-6AM)

1. **Export GitLab staging data**
   ```bash
   kubectl exec -n gitlab gitlab-task-runner -- \
     gitlab-rake gitlab:backup:create SKIP=uploads,artifacts
   ```

2. **Restore to STAGING RDS**
   ```bash
   # Adjust backup and restore to new RDS endpoint
   # Update gitlab-staging ConfigMap with new psql host
   ```

3. **Update Terraform**
   ```hcl
   # environments/staging/main.tf
   module "gitlab_staging" {
     postgresql_host = module.postgresql_staging.endpoint
   }
   ```

4. **Validation**
   - [ ] GitLab STAGING login functional
   - [ ] Projects accessible
   - [ ] CI/CD pipelines running
   - [ ] No errors in logs

### Fase 3: Rollback Plan

Se migração falhar:

```bash
# Restore original connection
kubectl edit configmap -n gitlab gitlab-webservice
# Revert psql host to PROD RDS
# Restart GitLab pods
kubectl rollout restart deploy -n gitlab gitlab-webservice
```

**RTO:** < 15 minutos
**RPO:** 0 (snapshot pré-migração)

---

## Consequências

### Positivas

- ✅ Deployment atual não requer retrabalho
- ✅ FinOps: saving $26.28/mês no curto prazo
- ✅ GitLab operational desde 2026-02-09
- ✅ Network Policies implementadas (defense-in-depth)

### Negativas

- ⚠️ Blast radius compartilhado (mitigado por alertas)
- ⚠️ Compliance risk (mitigado por database segregation)
- ⚠️ Technical debt (migração obrigatória Marco 4)

### Riscos Aceitos

| Risco                               | Probabilidade | Impacto | Mitigação                          |
|-------------------------------------|---------------|---------|-------------------------------------|
| STAGING query lenta afeta PROD      | Média         | Alto    | CloudWatch alarm + query monitoring |
| Breach em STAGING expõe PROD data   | Baixa         | Crítico | NetworkPolicy + RBAC strict         |
| RDS scale-up impacta ambos ambientes| Baixa         | Médio   | Scale window fora horário comercial |

---

## Validação

- [x] AWS Specialist: Aprovado (com alertas CloudWatch)
- [x] Security: Aprovado (condicional: NetworkPolicy + separate DBs)
- [x] FinOps: Aprovado (saving documentado)
- [x] Platform Team: Implementado e funcionando há 7 dias

---

## Referências

- [NetworkPolicy Implementation](/home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/environments/prod/main.tf#L260-L313)
- [GitLab RDS Connection Config](/home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/modules/gitlab/values.yaml.tpl#L41-L50)
- [Logbook: Cluster Remediation 2026-02-09](/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/logbook/2026-02-09-cluster-remediation.md)
- [ADR-023: Migration from Bitnami to K8s Operators](adr-023-bitnami-to-k8s-operators.md)

---

## Histórico de Revisões

| Data       | Autor          | Mudança                              |
|------------|----------------|--------------------------------------|
| 2026-02-09 | Platform Team  | Criação inicial (aceito)             |
