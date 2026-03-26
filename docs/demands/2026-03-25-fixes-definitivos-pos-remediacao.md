# Fixes Definitivos Pós-Remediação 2026-03-25

**Data:** 2026-03-25 | **Status:** EM ANDAMENTO | **Cluster:** k8s-platform-prod
**Conta AWS:** 891377105802 | **Região:** us-east-1
**Origem:** Sessão de remediação 2026-03-25 — 7 incidentes com fixes temporários/manuais

---

## Sumário Executivo

13 fixes definitivos identificados. Fixes temporários (kubectl patch, manual secrets) sendo codificados em IaC (Terraform).

**Bloqueador crítico:** FIX-001 (Vault root token recovery) desbloqueia FIX-002, FIX-003, FIX-009, FIX-013.

---

## Tabela de Resumo — 13 Fixes

| FIX | Descrição | Prioridade | Status | Dependências |
|-----|-----------|------------|--------|--------------|
| FIX-001 | Vault Prod Root Token Recovery | P0 | PENDENTE (manual) | Nenhuma |
| FIX-002 | CSS vault-backend-prod SA staging→prod | P0 | PENDENTE | FIX-001 |
| FIX-003 | Keycloak TF Password Drift | P1 | PENDENTE | FIX-001 |
| FIX-004 | Harbor Prod Redis ExternalSecret | P1 | **CODIFICADO** | TF apply pendente |
| FIX-005 | ALB IngressGroup Scheme Conflict | P1 | **CODIFICADO** | TF apply pendente |
| FIX-006 | Module Parametrização secret_store_name | P1 | **CODIFICADO** | TF apply pendente |
| FIX-007 | Linkerd mTLS Expansion Prod | P1 | **CODIFICADO** | TF apply + sidecar inject |
| FIX-008 | postgresql-external Migration | P1 | **CODIFICADO** | TF apply pendente |
| FIX-009 | Vault Policy Env Isolation | P2 | DOCUMENTADO (3 fases) | FIX-001 + migration plan |
| FIX-010 | Harbor Registry PVC gp2→gp3 | P2 | **JÁ RESOLVIDO** (2026-03-23) | N/A |
| FIX-011 | Workload Node Capacity | P2 | DOCUMENTADO | Decisão de sizing |
| FIX-012 | Velero Prod Backup Schedule | P2 | GAP DOCUMENTADO | Criar schedule prod |
| FIX-013 | prod-observability-monitoring Activation | P2 | PENDENTE | FIX-001 |

---

## Grafo de Dependências

```
              FIX-001 (Vault Root Token Recovery)
             /    |       \         \
            v     v        v         v
       FIX-002  FIX-003  FIX-009  FIX-013
         |
         v
       FIX-006 (module calls prod — já codificado)
```

Independentes (já codificados, prontos para TF apply):
- FIX-004 (Harbor Redis ExternalSecret)
- FIX-005 (ALB IngressGroup)
- FIX-006 (6 modules parametrizados)
- FIX-007 (Linkerd mTLS — requer sidecar inject antes)
- FIX-008 (postgresql-external migration)

---

## Implementações Concluídas (Sessão 2026-03-25)

### FIX-004: Harbor Redis ExternalSecret — CODIFICADO
- **Arquivo:** `environments/prod/main.tf` (linhas ~1027-1083)
- Adicionado `kubectl_manifest.harbor_prod_redis_externalsecret`
- Source: `secret/data/harbor/redis` via `vault-backend-prod`
- creationPolicy: Merge / deletionPolicy: Retain
- depends_on adicionado ao helm_release.harbor_prod

### FIX-005: ALB IngressGroup Scheme Conflict — CODIFICADO
- **Arquivo:** `environments/prod/main.tf` (linha 656)
- Alterado `group.name` de `platform-prod` → `platform-prod-internal`
- Cria ALB dedicado internal para Harbor prod
- ArgoCD + Keycloak permanecem no ALB internet-facing `platform-prod`

### FIX-006: Module Parametrização — CODIFICADO
- **6 modules** parametrizados (13 ocorrências substituídas):
  - `modules/harbor/` (5 refs), `modules/backstage/` (1), `modules/sonarqube/` (1)
  - `modules/argocd/` (2), `modules/kube-prometheus-stack/` (2), `modules/secret-rotation/` (2)
- Variable `secret_store_name` adicionada em cada `variables.tf` com default `"vault-backend"`
- Prod inline resources já usam `vault-backend-prod` — zero mudança necessária em prod/main.tf

### FIX-007: Linkerd mTLS Expansion — CODIFICADO
- **Arquivo:** `environments/prod/linkerd-mtls.tf`
- 3 namespaces adicionados: harbor, keycloak, rabbitmq
- HOLD: vault (chicken-and-egg), monitoring (0/0 replicas), externaldns, data-infra
- **PRÉ-REQUISITO:** Inject sidecars nos 3 namespaces ANTES do TF apply

### FIX-008: postgresql-external Migration — CODIFICADO
- **Arquivo:** `environments/staging/main.tf` (6 referências migradas)
- Substituído `postgresql-external.default.svc.cluster.local` por `module.postgresql_staging.rds_address`
- **Arquivo:** `modules/vault-config/variables.tf` (4 defaults removidos)
- **PÓS-APPLY:** Deletar `kubectl delete svc postgresql-external -n default`

### FIX-009: Vault Policy Isolation — DOCUMENTADO (não implementado)
- **Motivo:** 3 bloqueadores (paths não env-prefixed, OIDC role rebind, Keycloak group split)
- **Plano:** 3 fases documentadas em comentários nos .hcl
- Risco contido: oidc_enabled=false em prod

### FIX-010: Harbor PVC gp3 — JÁ RESOLVIDO
- Default `gp3` desde 2026-03-23

### FIX-011: Node Capacity — DOCUMENTADO
- 3 node groups: system (t3.medium x4), workloads (t3.large x6), critical (t3.xlarge x2)
- workloads max_size=9, pode aumentar para 11
- Recomendação: migrar para t3.xlarge ou aumentar min_size

### FIX-012: Velero Prod Schedule — GAP DOCUMENTADO
- Velero gerenciado apenas em staging TF (cluster shared)
- Prod namespaces NÃO cobertos por backup schedules
- Necessário: criar Schedule dedicado com `prod-*` namespaces

---

## Pendências para Próxima Sessão

### Ações Manuais (P0)
1. **FIX-001:** Localizar recovery keys Vault prod (init 2026-03-19) → vault operator generate-root
2. Após FIX-001: Atualizar `secret/keycloak/postgresql` + re-criar ExternalSecret prod

### Terraform Applies Pendentes
1. `terraform plan` completo em prod/ (validar todas as mudanças codificadas)
2. `terraform apply -target` sequencial: FIX-005 → FIX-004 → FIX-006 → FIX-008
3. FIX-007: Inject sidecars PRIMEIRO, depois `terraform apply` linkerd-mtls

### Decisões Pendentes do Usuário
- FIX-011: Aumentar max_size (simples) vs migrar instance type (disruptivo)
- FIX-012: Definir RPO/RTO para namespaces prod
- FIX-013: Quando ativar observability prod (resource planning ~4-6 vCPU, 8-12 GiB RAM)

---

## Lições Aprendidas

- **L29:** Vault recovery keys são single point of failure. NUNCA revogar root token sem recovery keys armazenadas.
- **L30:** Fixes manuais via kubectl patch são TEMPORÁRIOS. Todo fix manual DEVE ter issue TF com prazo < 1 sprint.
- **L31:** CSS serviceAccountRef.namespace cria acoplamento invisível entre ambientes.
- **L32:** ALB IngressGroup com scheme conflitante gera FailedBuildModel silencioso.
- **L33:** PVC StorageClass é imutável. Migração gp2→gp3 requer novo PVC + cópia + downtime.
