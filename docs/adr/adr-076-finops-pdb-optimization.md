# ADR-076: FinOps PDB Optimization — Critical Workloads (minAvailable=0)

**Data:** 2026-02-24
**Status:** Accepted
**Autor:** DevOps Platform Team
**Contexto:** FinOps — Node Drain Optimization e Cluster Autoscaler Scale-Down

---

## Contexto

### Problema

Node drains demoram >30min devido a pods únicos (replicas=1) sem PDB configurado, causando:

1. **Cluster Autoscaler bloqueado:** CA não consegue executar scale-down de nodes ociosos pois pods sem PDB ficam impedindo eviction
2. **Custos de nodes ociosos:** Cada node t3.large ocioso custa ~R$ 365/mês (R$ 4.380/ano)
3. **Incidentes durante upgrades:** Operações de manutenção como upgrade EKS ficam bloqueadas aguardando drains manuais
4. **FinOps Lambda ineficiente (ADR-063):** Shutdown automation afetada por drains lentos

### Solução

Criar PodDisruptionBudgets com `minAvailable: 0` para 9 workloads críticos, permitindo que o Kubernetes evict todos os pods do workload durante operações de manutenção programada.

**Decisão de design:** `minAvailable: 0` (e não `maxUnavailable: 1`) porque:
- Workloads são todos single-replica em staging
- `maxUnavailable: 1` em single-replica = 0 pods disponíveis durante drain (mesmo efeito)
- `minAvailable: 0` é semanticamente mais claro: "aceito zero disponibilidade temporária"

---

## Workloads Cobertos

| Workload | Namespace | Tipo | Replicas | Selector Principal |
|----------|-----------|------|----------|-------------------|
| Grafana | monitoring | Deployment | 1 | `app.kubernetes.io/name=grafana` |
| ArgoCD Server | argocd | Deployment | 2 | `app.kubernetes.io/name=argocd-server` |
| Harbor Core | harbor-system | Deployment | 2 | `app=harbor,component=core` |
| GitLab Webservice | gitlab-staging | Deployment | 2 | `app=webservice,release=gitlab` |
| Keycloak | keycloak | StatefulSet | 1 | `app.kubernetes.io/name=keycloakx` |
| SonarQube | sonarqube | StatefulSet | 1 | `app=sonarqube` |
| Vault | staging-security-vault | StatefulSet | 1 | `app.kubernetes.io/name=vault` |
| Prometheus | monitoring | StatefulSet | 1 | `app.kubernetes.io/name=prometheus` |
| Loki Backend | monitoring | StatefulSet | 2 | `app.kubernetes.io/name=loki,component=backend` |

---

## Descobertas Críticas na Validação de Labels (2026-02-24)

### 1. Keycloak: label name é `keycloakx`, não `keycloak`

```bash
# Label real do pod (StatefulSet keycloak-keycloakx-0):
app.kubernetes.io/name=keycloakx    # chart keycloakx
app.kubernetes.io/instance=keycloak # release helm
```

Selector correto: `app.kubernetes.io/name=keycloakx`

### 2. GitLab Webservice: deployment nome é `gitlab-webservice-default`

```bash
# Nome real do deployment:
gitlab-webservice-default    # não "gitlab-webservice"

# Selector correto:
app=webservice
release=gitlab
```

### 3. Prometheus: instance label inclui nome do stack

```bash
# Label real:
app.kubernetes.io/instance=kube-prometheus-stack-prometheus
# não apenas "kube-prometheus-stack"
```

---

## Implementação

### Módulo Terraform

- **Módulo:** `modules/finops-pdb-optimization/`
- **Configuração:** `environments/staging/finops-pdb-optimization.tf`
- **Recurso:** `kubernetes_pod_disruption_budget_v1` (for_each sobre workloads map)

### Labels de Governança

Todos os PDBs criados com labels padrão:

```yaml
labels:
  managed-by: terraform
  finops.k8s.io/pdb: optimized
  finops.k8s.io/phase: drain-optimization
annotations:
  finops.k8s.io/adr: DEC-076
  finops.k8s.io/savings: "Indirect: ~R$ 4380/ano via -1 node t3.large"
```

---

## Trade-offs

### Prós

- Node drain passa de ~30min para <5min
- Cluster Autoscaler pode executar scale-down automático
- Savings indireto potencial: R$ 4.380/ano (-1 node t3.large)
- Zero impacto em produção (staging apenas)

### Contras e Mitigações

| Risco | Workload Afetado | Mitigação |
|-------|-----------------|-----------|
| Vault unseal manual após restart | Vault | Auto-unseal via KMS configurado |
| Gap de métricas TSDB durante drain | Prometheus | Gap de ~5min tolerável em staging |
| GitLab CI jobs interrompidos durante drain | GitLab Webservice | Drain agendado fora de horário de CI |

---

## Savings Calculados

| Tipo | Valor | Cálculo |
|------|-------|---------|
| Direto (redução downtime drain) | ~R$ 25/ano | 25min economizados × 4 drains/mês × R$ 0,0832/h × 3 nodes |
| Indireto (CA scale-down eficiente) | ~R$ 4.380/ano | 1 node t3.large × R$ 365/mês × 12 meses |
| **Total estimado** | **~R$ 4.405/ano** | |

---

## Relacionamentos

- **ADR-063:** PDB Graceful Drain para FinOps Lambda (CoreDNS + Calico tolerations)
- **ADR-068:** GitLab multi-container resource order pattern
- **ADR-069:** RabbitMQ Cluster Operator CRD patch pattern
- **Logbook:** `2026-02-24-finops-pdb-optimization.md`

---

## Validação

```bash
# Verificar PDBs criados
kubectl get pdb -A | grep -E "(grafana|argocd|harbor|gitlab|keycloak|sonarqube|vault|prometheus|loki)"

# Descrever PDB individual
kubectl describe pdb grafana-pdb -n monitoring

# Teste de drain (node não-crítico)
NODE=$(kubectl get nodes -l "eks.amazonaws.com/nodegroup=workloads" -o jsonpath='{.items[0].metadata.name}')
kubectl cordon $NODE
time kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data --timeout=5m
kubectl uncordon $NODE
```

**Critérios de sucesso:**
- 9 PDBs criados com `ALLOWED DISRUPTIONS: 1`
- Drain time < 5min (vs baseline 30min)
- Zero erros de disruption budget violations

---

**Status Final:** Implementado via Terraform — 2026-02-24
