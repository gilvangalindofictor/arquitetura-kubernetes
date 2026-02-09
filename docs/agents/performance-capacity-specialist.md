# 🔬 Agente Performance & Capacity Specialist

**Função:** Load testing, benchmarking, capacity planning, HPA/VPA tuning
**Expertise:** K6, Locust, JMeter, Karpenter, HPA, VPA, Resource Quotas, Right-Sizing

---

## 🎯 Responsabilidades

1. **Load Testing & Benchmarking**
   - Load tests pré-deploy (baseline de performance)
   - Stress tests (identificar breaking points)
   - Soak tests (detectar memory leaks, degradação temporal)
   - Benchmarking contínuo (track regressions)

2. **Capacity Planning**
   - Right-sizing baseado em métricas reais (não chute)
   - Node count optimization (consolidar vs espalhar)
   - Resource requests/limits tuning (CPU/memory)
   - PVC sizing (evitar resize disruptivo)

3. **Auto-Scaling**
   - HPA (Horizontal Pod Autoscaler) - configuração + validação
   - VPA (Vertical Pod Autoscaler) - recomendações automáticas
   - Karpenter - node provisioning dinâmico (pré-requisito: HPA)
   - Cluster Autoscaler - fallback se Karpenter não aplicável

4. **Performance Tuning**
   - JVM heap sizing (Java workloads)
   - DB connection pools (PostgreSQL, MySQL)
   - Cache hit ratio optimization (Redis)
   - Network latency reduction (Service Mesh, CDN)

5. **Validação Pré e Pós Execução**
   - PRE: HPA/VPA configurados antes de Spot/Karpenter
   - POST: Validar scaling events, métricas de performance

---

## 📋 Checklist PRE-HOOK Performance

- [ ] HPA configurado para workloads críticos (min/max replicas, target CPU/memory)
- [ ] Resource requests/limits baseados em dados reais (não defaults)
- [ ] PodDisruptionBudget (PDB) criado (evitar downtime durante scale-in)
- [ ] Load test executado (baseline de latência, throughput)
- [ ] Bottlenecks identificados (CPU-bound, memory-bound, I/O-bound)
- [ ] QoS class adequada (Guaranteed para critical, Burstable para best-effort)

---

## 📋 Checklist POST-HOOK Performance

- [ ] HPA scaling events funcionais (kubectl get hpa -w)
- [ ] Métricas de performance dentro do SLO (p95 latency, error rate)
- [ ] Resource utilization saudável (CPU 60-80%, memory 70-85%)
- [ ] Sem OOMKills pós-deploy (kubectl get events | grep OOMKilled)
- [ ] VPA recommendations aplicadas se necessário
- [ ] Load test pós-deploy confirma capacidade

---

## 🔍 Análise Performance STAGING

### Workloads Atuais (Validar Configuração)

| Workload | HPA | VPA | Resource Limits | Status |
|----------|-----|-----|-----------------|--------|
| **GitLab Webservice** | ❌ Ausente | ❌ Ausente | Default (?) | 🔴 CRÍTICO |
| **GitLab Sidekiq** | ❌ Ausente | ❌ Ausente | Default (?) | 🔴 CRÍTICO |
| **Redis (Operator)** | N/A (StatefulSet) | ⚠️ Manual | 2 vCPU, 4GB | 🟡 OK |
| **RabbitMQ (Operator)** | N/A (StatefulSet) | ⚠️ Manual | 1 vCPU, 2GB | 🟡 OK |
| **PostgreSQL** | N/A (RDS) | N/A | db.t3.medium | ✅ OK |
| **Harbor** | ❌ Ausente | ❌ Ausent | Default (?) | 🟠 MÉDIO |

### Gaps Críticos Identificados

#### 1. HPA Ausente (BLOQUEADOR para Node Optimization)

**Impacto:**
- Node optimization 7→5 é **CHUTE** sem HPA
- Karpenter deployment **BLOQUEADO** (pré-requisito não atendido)
- Spot Instances **ARRISCADO** (sem auto-scaling para compensar eviction)

**Ação Obrigatória:**
```yaml
# GitLab Webservice HPA (exemplo)
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: gitlab-webservice-hpa
  namespace: gitlab
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: gitlab-webservice
  minReplicas: 2  # staging
  maxReplicas: 6
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300  # evita flapping
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
```

#### 2. Resource Limits Não Otimizados

**Problema:** Defaults genéricos → overprovisioning OR underprovisionining

**Solução:**
1. Coletar métricas reais (7 dias):
   ```bash
   kubectl top pods -n gitlab --sort-by=cpu
   kubectl top pods -n gitlab --sort-by=memory
   ```
2. Usar VPA em modo `RecommendationOnly`:
   ```yaml
   apiVersion: autoscaling.k8s.io/v1
   kind: VerticalPodAutoscaler
   metadata:
     name: gitlab-webservice-vpa
   spec:
     targetRef:
       apiVersion: apps/v1
       kind: Deployment
       name: gitlab-webservice
     updateMode: "Off"  # apenas recomendações
   ```
3. Aplicar recommendations manualmente (evitar restarts automáticos)

#### 3. PDB Ausente (Risco em Scale-Down)

**Problema:** ASG scale-in pode matar pods sem graceful shutdown

**Solução:**
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: gitlab-webservice-pdb
  namespace: gitlab
spec:
  minAvailable: 1  # sempre 1 pod rodando
  selector:
    matchLabels:
      app: gitlab-webservice
```

---

## 📊 Load Testing Strategy (Staging)

### Baseline Test (Pré-Optimization)

**Tool:** K6 (open-source, scriptable)

```javascript
// k6-baseline.js
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  stages: [
    { duration: '2m', target: 50 },  // ramp-up
    { duration: '5m', target: 50 },  // sustain
    { duration: '2m', target: 0 },   // ramp-down
  ],
  thresholds: {
    http_req_duration: ['p(95)<2000'],  // 95% < 2s
    http_req_failed: ['rate<0.01'],     // error rate < 1%
  },
};

export default function () {
  let res = http.get('https://gitlab-staging.example.com');
  check(res, { 'status 200': (r) => r.status === 200 });
  sleep(1);
}
```

**Execução:**
```bash
k6 run --out prometheus=http://prometheus:9090 k6-baseline.js
```

**Métricas Coletadas:**
- p50, p95, p99 latency
- Throughput (req/s)
- Error rate
- Resource utilization (via Prometheus durante test)

### Stress Test (Breaking Point)

```javascript
// k6-stress.js
export let options = {
  stages: [
    { duration: '2m', target: 100 },
    { duration: '5m', target: 200 },
    { duration: '5m', target: 300 },  // até quebrar
    { duration: '2m', target: 0 },
  ],
};
```

**Objetivo:** Identificar gargalos (CPU saturation, memory exhaustion, DB connections)

---

## 🎯 Capacity Planning - Node Optimization

### Situação Atual

- **Nodes:** 7 (over-provisioned segundo melhorias priorizadas)
- **Target:** 5 nodes + Karpenter
- **Bloqueador:** HPA ausente = otimização é chute

### Fluxo Correto (Data-Driven)

```
1. Deploy HPA + PDB (todas workloads críticas)
   └─ GitLab, Harbor, custom apps

2. Coletar métricas (14 dias)
   └─ kubectl top nodes
   └─ Prometheus: node_cpu_usage, node_memory_usage

3. Analisar utilization patterns
   ├─ Peak hours (GitLab CI jobs)
   ├─ Off-hours (mínimo necessário)
   └─ Burst capacity (deploy spikes)

4. Calcular node count necessário
   └─ Formula: (peak_workload_requests × 1.2) / node_capacity
   └─ Exemplo: (50 vCPU × 1.2) / 16 vCPU/node = 3.75 → 4 nodes base

5. Deploy Karpenter
   ├─ Provisioner: burst workloads (CI jobs)
   ├─ Node template: Spot instances (30% economia)
   └─ Consolidation: auto-remove idle nodes (60s threshold)

6. Validar com load test
   └─ Simular peak + burst → HPA scale → Karpenter provision → latency OK
```

### Decisão

⛔ **BLOQUEAR Node Optimization ATÉ:**
1. HPA configurado (GitLab, Harbor) ✅
2. Métricas 7 dias coletadas ✅
3. Load test baseline executado ✅

**Prazo:** Marco 4 (após Observability stack deploy)

---

## 🔄 Integração com AML

Durante execução via AML, Performance Specialist monitora:

```bash
# Ciclo AML - Verificações Adicionais
├─ HPA events: kubectl get hpa -A -w
├─ Resource usage: kubectl top pods -A --sort-by=memory
├─ OOMKills: kubectl get events -A | grep OOMKilled
├─ PDB status: kubectl get pdb -A
└─ Latency (se load test rodando): k6 metrics
```

**Report AML Compacto:**
```
[AML-C8] 120s | Perf | HPA: webservice 2→4 replicas | CPU 45% | Mem 68% | No OOM | ✅
```

---

## 💰 Custo Load Testing (Staging)

| Item | Custo |
|------|-------|
| K6 Cloud (opcional, 1000 VUs) | $50/mês OR self-hosted $0 |
| EC2 load generator (spot t3.medium) | ~$10/mês (ocasional) |
| **Total** | **~$10/mês** (self-hosted) |

**Economia vs Guesswork:**
- Node over-provisioning: ~$100/mês desperdiçado
- Load testing previne: rightsizing saves $100/mês
- **ROI:** 10x

---

**Criado em:** 2026-02-09
**Próxima Revisão:** Pós-deploy HPA (validar scaling events, metrics)
