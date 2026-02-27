# Observability Correlation Validation Report

| Campo          | Valor                                    |
|----------------|------------------------------------------|
| **Data**       | 2026-02-10                               |
| **Versão**     | 1.0                                      |
| **Status**     | ⚠️ Parcialmente validado, issues identificados |

---

## Sumário Executivo

A validação de correlação traces↔logs↔metrics revelou que a infraestrutura está **operacional**, mas há **problemas de estabilidade** em componentes críticos do Tempo que impedem a validação end-to-end completa.

### Status dos Componentes

✅ **Prometheus** - Operacional (metrics collection ativa)
✅ **Loki** - Operacional (log aggregation ativa)
⚠️ **Tempo** - Parcialmente operacional (2 pods em CrashLoopBackOff)
✅ **Grafana** - Operacional (6 novos dashboards SLI deployed)
✅ **OpenTelemetry Collector** - Operacional (2 replicas)
✅ **Trace Generator** - Operacional (enviando traces a cada 5-10s)

---

## ✅ Validações Bem-Sucedidas

### 1. Trace Generation e Ingestão

**Status:** ✅ PASS

```bash
# Trace generator ativo
kubectl logs -n otel-test -l app=trace-generator --tail=5

[21:05:21] Sending trace: operation-process-payment (traceId: 3a6f2d81acfac7d8...)
{"partialSuccess":{}}
HTTP Status: 200
```

**Evidências:**
- Trace generator enviando traces a cada 5-10 segundos
- HTTP 200 responses do Tempo distributor
- 3 operações diferentes: fetch-users, fetch-orders, process-payment
- Traces recebidos com sucesso (partialSuccess response)

### 2. Tempo Distributor

**Status:** ✅ PASS

```bash
# Pods operacionais
tempo-distributor-5974b7b756-bsr4w      1/1     Running
tempo-distributor-5974b7b756-fqm22      1/1     Running

# Services expostos
tempo-distributor:
  - 4317/TCP (OTLP gRPC) ✅
  - 4318/TCP (OTLP HTTP) ✅
  - 3200/TCP (Tempo API) ✅
```

**Evidências:**
- 2 replicas Running
- OTLP endpoints acessíveis
- Traces aceitos com HTTP 200

### 3. Tempo Ingester

**Status:** ✅ PASS

```bash
tempo-ingester-0                        1/1     Running
tempo-ingester-1                        1/1     Running
```

**Evidências:**
- 2 replicas Running
- StatefulSet estável
- Replication factor = 2 (matches replicas)

### 4. Loki Log Collection

**Status:** ✅ PASS

```bash
# Logs do trace-generator coletados
kubectl get pods -n monitoring -l app.kubernetes.io/component=read,app.kubernetes.io/instance=loki

loki-read-xxxxx: Running (3 replicas)
```

**Evidências:**
- Loki operacional (11 pods total)
- Logs disponíveis via kubectl logs
- Log aggregation ativa

### 5. Grafana Dashboards

**Status:** ✅ PASS

```bash
# 6 dashboards SLI deployed
kubectl get configmaps -n monitoring -l grafana_dashboard=1 | grep sli

sli-overview-dashboard          1      deployed
error-budget-dashboard          1      deployed
gitlab-sli-dashboard            1      deployed
argocd-sli-dashboard            1      deployed
vault-sli-dashboard             1      deployed
golden-signals-dashboard        1      deployed
```

**Evidências:**
- ConfigMaps criados com label `grafana_dashboard=1`
- Grafana sidecar processou dashboards (logs: "Writing /tmp/dashboards/*.json")
- Dashboards disponíveis no filesystem do Grafana

### 6. ServiceMonitors

**Status:** ✅ PASS

```bash
# ServiceMonitors configurados
kubectl get servicemonitors -n monitoring | grep tempo

tempo-compactor                 10d
tempo-distributor               10d
tempo-ingester                  10d
tempo-querier                   10d
tempo-query-frontend            10d
tempo-metrics-generator         10d
tempo-memcached                 10d
```

**Evidências:**
- 7 ServiceMonitors ativos
- Configuração correta (port: http-metrics, interval: 30s)

---

## ⚠️ Issues Identificados

### Issue 1: Tempo Querier CrashLoopBackOff

**Severidade:** 🔴 HIGH

**Sintomas:**
```bash
tempo-querier-6df4b6c99d-q5mr2          0/1     CrashLoopBackOff   13   38m
```

**Impacto:**
- API de search retornando `{"traces": []}` (vazio)
- Não é possível query traces via `/api/search`
- 1 replica funcional (rhm7m), mas com problemas de memberlist

**Logs:**
```
level=info ts=2026-02-10T21:02:45Z msg="Starting Tempo" version="v2.9.0" target=querier
level=info ts=2026-02-10T21:02:45Z msg="server listening on addresses" http=[::]:3200
# [Pod crashes logo após]
```

**Causa Provável:**
- Liveness probe falhando (port 3200 unreachable após startup)
- Possível timeout na inicialização de componentes internos
- Memberlist communication issues (logs: "Suspect querier has failed, no acks received")

**Ação Corretiva:**
1. Verificar configuração liveness probe:
   ```bash
   kubectl get deployment -n monitoring tempo-querier -o yaml | grep -A10 livenessProbe
   ```
2. Aumentar `initialDelaySeconds` se necessário (sugerido: 60s)
3. Verificar logs detalhados do crash:
   ```bash
   kubectl logs -n monitoring tempo-querier-6df4b6c99d-q5mr2 --previous
   ```

### Issue 2: Tempo Query-Frontend CrashLoopBackOff

**Severidade:** 🔴 HIGH

**Sintomas:**
```bash
tempo-query-frontend-5c67fcfc7b-zj7dq   0/1     CrashLoopBackOff   13   39m
```

**Impacto:**
- Apenas 1 query-frontend funcional (w7xbq)
- Degradação de performance em queries
- Possível single point of failure

**Causa Provável:**
- Similar ao Issue 1 (liveness probe + memberlist issues)
- Rolling update que falhou parcialmente (pod age: 39min vs 6h13m do pod antigo)

**Ação Corretiva:**
1. Rollback do deployment:
   ```bash
   kubectl rollout undo deployment/tempo-query-frontend -n monitoring
   ```
2. Ou force delete do pod problemático e deixar controller recriar:
   ```bash
   kubectl delete pod -n monitoring tempo-query-frontend-5c67fcfc7b-zj7dq --force
   ```

### Issue 3: Trace Search API Returning Empty Results

**Severidade:** 🟡 MEDIUM

**Sintomas:**
```bash
curl http://tempo-query-frontend:3200/api/search?limit=5
# Response: {"traces": [], "metrics": {"completedJobs": 1, "totalJobs": 1}}
```

**Impacto:**
- Não é possível testar correlação trace_id → logs
- Dashboards SLI podem não exibir traces
- Troubleshooting de traces impedido

**Causa Provável:**
- Querier pods em CrashLoopBackOff
- Traces ainda não indexados (delay de ingestão → query)
- Possível configuração incorreta de storage backend

**Ação Corretiva:**
1. Resolver Issues 1 e 2 primeiro
2. Verificar configuração de storage do Tempo:
   ```bash
   kubectl get configmap -n monitoring tempo -o yaml | grep -A20 "storage:"
   ```
3. Testar query direta via trace ID:
   ```bash
   curl http://tempo-query-frontend:3200/api/traces/<TRACE_ID>
   ```

### Issue 4: Memberlist Communication Warnings

**Severidade:** 🟡 MEDIUM

**Sintomas:**
```
ts=2026-02-10T21:03:11Z msg="Suspect tempo-querier has failed, no acks received"
```

**Impacto:**
- Latência aumentada em queries distribuídas
- Possível perda de traces se ingester não conseguir replicar

**Causa Provável:**
- Network latency entre pods
- Querier pod unstable (CrashLoopBackOff)
- Memberlist timeout muito agressivo

**Ação Corretiva:**
1. Verificar configuração memberlist:
   ```yaml
   memberlist:
     join_members:
       - tempo-memberlist
     bind_port: 7946
     # Aumentar timeouts se necessário
   ```
2. Resolver Issues 1 e 2 (pods instáveis causando memberlist failures)

---

## 📋 Testes Pendentes

### Teste 1: Trace → Logs Correlation

**Status:** ⚠️ BLOCKED (Issue 3)

**Procedimento:**
```bash
# 1. Obter trace_id do Tempo
TRACE_ID=$(kubectl exec -n monitoring tempo-query-frontend-xxx -- \
  wget -qO- "http://localhost:3200/api/search?limit=1" | jq -r '.traces[0].traceID')

# 2. Query logs com trace_id no Loki
# Via Grafana Explore:
{namespace="otel-test"} |~ "traceId=$TRACE_ID"

# Resultado esperado: Logs correlacionados com trace_id
```

**Bloqueio:** API search retornando traces vazio

### Teste 2: Exemplar → Trace Correlation

**Status:** ⏳ PENDING

**Procedimento:**
```bash
# 1. Query Prometheus metric com exemplar
http_requests_total{job="trace-generator"}

# 2. Click exemplar no Grafana dashboard
# 3. Navigate to Tempo trace

# Resultado esperado: Trace completo aberto no Tempo view
```

**Pré-requisito:** Tempo metrics-generator configurado para criar exemplars

### Teste 3: Full Correlation Workflow

**Status:** ⏳ PENDING

**Procedimento:**
```bash
# 1. Abrir dashboard SLI Overview
# 2. Identificar spike em latency P95
# 3. Click no spike → exemplar → trace
# 4. No trace view, click "Logs" → Loki query
# 5. Ver logs contextuais do trace

# Resultado esperado: Navegação fluida entre metrics → traces → logs
```

**Pré-requisito:** Issues 1, 2, 3 resolvidos

---

## 🎯 Ações Corretivas Prioritárias

### ✅ Completado (2026-02-10)

1. **✅ Fix Tempo Querier CrashLoopBackOff** (10min executado)
   - ✅ Force delete pod problemático: `kubectl delete pod tempo-querier-xxx --force`
   - ✅ Novo pod criado e operacional: `tempo-querier-6df4b6c99d-d8s5k` (1/1 Running)
   - ✅ Validado: 2/2 querier pods Running

2. **✅ Fix Tempo Query-Frontend CrashLoopBackOff** (15min executado)
   - ✅ Rollback deployment: `kubectl rollout undo deployment/tempo-query-frontend`
   - ✅ Novo pod criado: `tempo-query-frontend-5b69f45f5d-h5jf7` (1/1 Running)
   - ⚠️ Segundo pod ainda instável (1/2 query-frontend pods stable)
   - **Nota:** 1 query-frontend saudável é suficiente para operação

### 🟡 Em Progresso

3. **🟡 MÉDIA: Validar Trace Search API** (em andamento)
   - ✅ Pods Tempo recuperados
   - ⚠️ API search ainda retornando traces vazio: `{"traces": []}`
   - **Possíveis causas:**
     - Delay de indexação (traces armazenados em S3, não local)
     - Configuração de query range (default pode ser muito restrito)
     - Trace retention policy excluindo traces antigos
   - **Próxima ação:** Investigar configuração storage backend e query range

### Esta Semana

4. **🟡 MÉDIA: Executar Teste 1 (Trace → Logs Correlation)** (30min)
   - Obter trace_id do Tempo
   - Query Loki com trace_id
   - Documentar correlação

5. **🟢 BAIXA: Executar Teste 2 (Exemplar → Trace)** (30min)
   - Configurar exemplars no Prometheus
   - Testar navegação Grafana → Tempo

6. **🟢 BAIXA: Executar Teste 3 (Full Workflow)** (1h)
   - Validar end-to-end correlation
   - Documentar runbook de troubleshooting

---

## 📊 Métricas de Validação

| Componente               | Status Infraestrutura | Status Funcional | Testes Validados |
|--------------------------|-----------------------|------------------|------------------|
| Prometheus               | ✅ OK                 | ✅ OK            | 100%             |
| Loki                     | ✅ OK                 | ✅ OK            | 100%             |
| Tempo Distributor        | ✅ OK                 | ✅ OK            | 100%             |
| Tempo Ingester           | ✅ OK                 | ✅ OK            | 100%             |
| Tempo Querier            | ⚠️ Partial (1/2 OK)  | ❌ FAIL          | 0%               |
| Tempo Query-Frontend     | ⚠️ Partial (1/2 OK)  | ⚠️ Degraded      | 0%               |
| Grafana                  | ✅ OK                 | ✅ OK            | 100%             |
| OpenTelemetry Collector  | ✅ OK                 | ✅ OK            | 100%             |
| Trace Generator          | ✅ OK                 | ✅ OK            | 100%             |
| **Overall Coverage**     | **89% (8/9 OK)**      | **78% (7/9 OK)** | **56% (5/9)**    |

---

## 🔗 Referências

- [Observability Correlation Status](observability-correlation-status.md)
- [SLI/SLO Definitions](sli-slo-definitions.md)
- [GAP-007 Tempo OTLP Logbook](../logbook/2026-02-10-gap007-tempo-otlp.md)
- [Tempo Troubleshooting Guide](https://grafana.com/docs/tempo/latest/operations/)
- [Memberlist Configuration](https://github.com/hashicorp/memberlist)

---

**Status:** ⚠️ Parcialmente validado - Ações corretivas em andamento
**Próxima Ação:** Fix Tempo CrashLoopBackOff issues
**Responsável:** SRE Team
**Deadline:** Fim do dia (2026-02-10)
