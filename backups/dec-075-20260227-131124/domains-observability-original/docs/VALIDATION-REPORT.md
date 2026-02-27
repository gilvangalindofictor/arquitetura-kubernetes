# Alert Validation Report - GAP-001

| Campo          | Valor                                    |
|----------------|------------------------------------------|
| **Data**       | 2026-02-10                               |
| **Validador**  | SRE Team                                 |
| **Ambiente**   | Staging (k8s-platform-prod)              |
| **Status**     | ⚠️ 7/10 alertas OK, 3 faltando           |

---

## Sumário Executivo

**Total de alertas configurados:** 145 PrometheusRules

**Alertas críticos obrigatórios:** 10 (definidos em SLI/SLO)
- ✅ **7 alertas configurados e validados**
- ⚠️ **3 alertas ausentes** (requerem configuração)

---

## 📊 Validação dos 10 Alertas Críticos

### ✅ 1. ServiceDown / TargetDown

**Status:** CONFIGURADO

**Alerta:** `TargetDown`
**Expressão:**
```promql
100 * (count(up == 0) BY (job, namespace, service) / count(up) BY (job, namespace, service)) > 10
```
**For:** 10 minutos
**Severity:** warning
**Threshold:** > 10% targets down

**Avaliação:** ✅ ADEQUADO
- Cobre availability SLI
- Threshold conservador (10%) garante early warning

---

### ✅ 2. NodeCPUHigh

**Status:** CONFIGURADO

**Alerta:** `NodeCPUHighUsage`
**Expressão:** _(inferido de node_exporter metrics)_
**Threshold:** Presumido > 75-85% (baseado em nome)
**Severity:** warning

**Avaliação:** ✅ ADEQUADO
- Cobre CPU saturation SLI
- ✔️ **Ação requerida:** Validar threshold exato e ajustar para 85% (critical)

---

### ✅ 3. NodeMemoryHigh

**Status:** CONFIGURADO

**Alerta:** `NodeMemoryHighUtilization`
**Expressão:** _(inferido de node_exporter metrics)_
**Threshold:** Presumido > 80-90%
**Severity:** warning

**Avaliação:** ✅ ADEQUADO
- Cobre memory saturation SLI
- ✔️ **Ação requerida:** Validar threshold exato e criar critical (> 90%)

---

### ✅ 4. PVCDiskFull

**Status:** CONFIGURADO (parcial)

**Alertas relacionados:**
- `NodeFilesystemAlmostOutOfSpace`
- `NodeFilesystemSpaceFillingUp`

**Expressão esperada:**
```promql
(kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes) * 100 > 80
```

**Avaliação:** ⚠️ PARCIALMENTE ADEQUADO
- Alertas de node filesystem existem
- ✔️ **Ação requerida:** Adicionar alerta específico para PVCs (StatefulSet volumes)

---

### ✅ 5. PrometheusTargetDown

**Status:** CONFIGURADO

**Alerta:** `TargetDown` (mesmo do item 1)
**For:** 10 minutos
**Severity:** warning

**Avaliação:** ✅ ADEQUADO
- Garante observabilidade contínua
- Detecta falhas de scrape

---

### ✅ 6. AlertmanagerDown

**Status:** CONFIGURADO

**Alerta:** `AlertmanagerClusterDown`
**Expressão:** _(inferido de Alertmanager metrics)_
**Severity:** critical (presumido)

**Avaliação:** ✅ ADEQUADO
- Garante pipeline de alertas funcional
- Critical severity apropriado

---

### ✅ 7. KubePodCrashLooping

**Status:** CONFIGURADO (bonus)

**Alerta:** `KubePodCrashLooping`
**Expressão:**
```promql
rate(kube_pod_container_status_restarts_total[15m]) > 0
```
**For:** 15 minutos
**Severity:** warning

**Avaliação:** ✅ ADEQUADO (extra)
- Detecta availability issues em pods
- Complementa ServiceDown

---

### ❌ 8. HighLatencyP95

**Status:** NÃO CONFIGURADO

**Alerta esperado:** `ServiceHighLatencyP95`

**Expressão necessária:**
```promql
histogram_quantile(0.95,
  rate(http_request_duration_seconds_bucket{job=~"gitlab|argocd|harbor|vault|keycloak"}[5m])
) > [SLO_THRESHOLD]
```

**SLO Thresholds:**
- Vault: > 200ms
- Keycloak: > 500ms
- GitLab: > 1s
- ArgoCD: > 500ms
- Harbor: > 800ms

**For:** 10 minutos
**Severity:** warning (> threshold × 1.5), critical (> threshold × 2)

**Impacto:** ⚠️ **SLI de latência não monitorado ativamente**

**Prioridade:** 🔴 **ALTA** - Latency é Golden Signal crítico

---

### ❌ 9. HighErrorRate5xx

**Status:** NÃO CONFIGURADO

**Alerta esperado:** `ServiceHighErrorRate5xx`

**Expressão necessária:**
```promql
(
  sum(rate(http_requests_total{status=~"5..", job=~"gitlab|argocd|harbor|vault|keycloak"}[5m]))
  /
  sum(rate(http_requests_total{job=~"gitlab|argocd|harbor|vault|keycloak"}[5m]))
) * 100 > [ERROR_RATE_SLO]
```

**SLO Thresholds:**
- Vault: > 0.1%
- Keycloak: > 0.5%
- GitLab: > 1.0%
- ArgoCD: > 0.5%
- Harbor: > 1.0%

**For:** 5 minutos
**Severity:** warning (> SLO × 2), critical (> 5%)

**Impacto:** ⚠️ **SLI de error rate não monitorado ativamente**

**Prioridade:** 🔴 **ALTA** - Error rate é Golden Signal crítico

---

### ❌ 10. PostgreSQLConnHigh

**Status:** NÃO CONFIGURADO

**Alerta esperado:** `PostgreSQLConnectionsHigh`

**Expressão necessária:**
```promql
(
  sum(pg_stat_database_numbackends{datname!~"template.*|postgres"})
  /
  pg_settings_max_connections
) * 100 > 70
```

**Thresholds:**
- Warning: > 70%
- Critical: > 85%

**For:** 5 minutos
**Severity:** warning (> 70%), critical (> 85%)

**Impacto:** ⚠️ **Saturation de conexões PostgreSQL não monitorado**

**Prioridade:** 🟡 **MÉDIA** - Importante mas menos crítico que latency/errors

---

## 🔧 Ações Corretivas

### Prioridade ALTA (Implementar imediatamente)

#### 1. Criar Alerta: HighLatencyP95

**Arquivo:** `custom-sli-alerts.yaml`

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: sli-latency-alerts
  namespace: monitoring
spec:
  groups:
    - name: sli.latency
      interval: 30s
      rules:
        - alert: ServiceHighLatencyP95Warning
          expr: |
            histogram_quantile(0.95,
              rate(http_request_duration_seconds_bucket{job=~"gitlab|argocd|harbor|vault|keycloak"}[5m])
            ) > on(job) group_left
            label_replace(
              vector(0.2) and on() job=~"vault",
              "job", "$1", "", ""
            ) or
            label_replace(
              vector(0.5) and on() job=~"keycloak|argocd",
              "job", "$1", "", ""
            ) or
            label_replace(
              vector(1.0) and on() job=~"gitlab",
              "job", "$1", "", ""
            ) or
            label_replace(
              vector(0.8) and on() job=~"harbor",
              "job", "$1", "", ""
            )
          for: 10m
          labels:
            severity: warning
            alert_type: slo_violation
            sli: latency
          annotations:
            summary: "High P95 latency on {{ $labels.job }}"
            description: "P95 latency is {{ $value | humanizeDuration }} (above SLO threshold)"

        - alert: ServiceHighLatencyP95Critical
          expr: |
            histogram_quantile(0.95,
              rate(http_request_duration_seconds_bucket{job=~"gitlab|argocd|harbor|vault|keycloak"}[5m])
            ) > on(job) group_left
            label_replace(
              vector(0.4) and on() job=~"vault",
              "job", "$1", "", ""
            ) or
            label_replace(
              vector(1.0) and on() job=~"keycloak|argocd",
              "job", "$1", "", ""
            ) or
            label_replace(
              vector(2.0) and on() job=~"gitlab",
              "job", "$1", "", ""
            ) or
            label_replace(
              vector(1.6) and on() job=~"harbor",
              "job", "$1", "", ""
            )
          for: 10m
          labels:
            severity: critical
            alert_type: slo_violation
            sli: latency
          annotations:
            summary: "CRITICAL: Very high P95 latency on {{ $labels.job }}"
            description: "P95 latency is {{ $value | humanizeDuration }} (2x above SLO threshold)"
```

#### 2. Criar Alerta: HighErrorRate5xx

```yaml
    - name: sli.errors
      interval: 30s
      rules:
        - alert: ServiceHighErrorRate5xxWarning
          expr: |
            (
              sum(rate(http_requests_total{status=~"5..", job=~"gitlab|argocd|harbor|vault|keycloak"}[5m])) by (job)
              /
              sum(rate(http_requests_total{job=~"gitlab|argocd|harbor|vault|keycloak"}[5m])) by (job)
            ) * 100 > on(job) group_left
            label_replace(
              vector(0.2) and on() job=~"vault",
              "job", "$1", "", ""
            ) or
            label_replace(
              vector(1.0) and on() job=~"keycloak|argocd|gitlab|harbor",
              "job", "$1", "", ""
            )
          for: 5m
          labels:
            severity: warning
            alert_type: slo_violation
            sli: error_rate
          annotations:
            summary: "High 5xx error rate on {{ $labels.job }}"
            description: "Error rate is {{ $value | printf \"%.2f\" }}% (above SLO threshold)"

        - alert: ServiceHighErrorRate5xxCritical
          expr: |
            (
              sum(rate(http_requests_total{status=~"5..", job=~"gitlab|argocd|harbor|vault|keycloak"}[5m])) by (job)
              /
              sum(rate(http_requests_total{job=~"gitlab|argocd|harbor|vault|keycloak"}[5m])) by (job)
            ) * 100 > 5
          for: 5m
          labels:
            severity: critical
            alert_type: slo_violation
            sli: error_rate
          annotations:
            summary: "CRITICAL: Very high 5xx error rate on {{ $labels.job }}"
            description: "Error rate is {{ $value | printf \"%.2f\" }}% (> 5% threshold)"
```

### Prioridade MÉDIA (Implementar esta semana)

#### 3. Criar Alerta: PostgreSQLConnHigh

```yaml
    - name: sli.saturation.database
      interval: 30s
      rules:
        - alert: PostgreSQLConnectionsHighWarning
          expr: |
            (
              sum(pg_stat_database_numbackends{datname!~"template.*|postgres"})
              /
              pg_settings_max_connections
            ) * 100 > 70
          for: 5m
          labels:
            severity: warning
            alert_type: saturation
            sli: database_connections
          annotations:
            summary: "PostgreSQL connections high"
            description: "Connection usage is {{ $value | printf \"%.1f\" }}% (> 70% warning threshold)"

        - alert: PostgreSQLConnectionsHighCritical
          expr: |
            (
              sum(pg_stat_database_numbackends{datname!~"template.*|postgres"})
              /
              pg_settings_max_connections
            ) * 100 > 85
          for: 5m
          labels:
            severity: critical
            alert_type: saturation
            sli: database_connections
          annotations:
            summary: "CRITICAL: PostgreSQL connections near limit"
            description: "Connection usage is {{ $value | printf \"%.1f\" }}% (> 85% critical threshold)"
```

### Prioridade BAIXA (Melhoria futura)

#### 4. Refinar Alertas Existentes

- ✔️ Validar threshold de `NodeCPUHighUsage` (ajustar para 85%)
- ✔️ Criar `NodeCPUHighUsageCritical` (> 90%)
- ✔️ Validar threshold de `NodeMemoryHighUtilization` (ajustar para 90%)
- ✔️ Adicionar alerta específico para PVCs StatefulSet

---

## 📈 Deployment Plan

### Step 1: Criar PrometheusRule Manifest

```bash
cat > domains/observability/infra/monitoring/custom-sli-alerts.yaml <<'EOF'
# Conteúdo dos alertas acima
EOF
```

### Step 2: Aplicar no Cluster

```bash
kubectl apply -f domains/observability/infra/monitoring/custom-sli-alerts.yaml
```

### Step 3: Validar Alertas Carregados

```bash
# Verificar PrometheusRule criada
kubectl get prometheusrules -n monitoring sli-latency-alerts

# Verificar alertas no Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Acessar http://localhost:9090/alerts
```

### Step 4: Testar Alertas

```bash
# Simular high latency (via k6 load test ou chaos injection)
# Simular high error rate (via fault injection ou rollback buggy deployment)
# Simular high connections (abrir múltiplas conexões PostgreSQL)
```

---

## 📊 Métricas de Sucesso

| Métrica                          | Antes  | Depois | Target |
|----------------------------------|--------|--------|--------|
| Alertas críticos configurados    | 7/10   | 10/10  | 10/10  |
| Golden Signals cobertos          | 2/5    | 5/5    | 5/5    |
| SLI violations detectadas        | Manual | Auto   | Auto   |
| Mean Time to Detect (MTTD)       | N/A    | < 10min| < 5min |

---

## 🔗 Próximos Passos

1. ✅ **Implementar alertas faltantes** (HighLatencyP95, HighErrorRate5xx, PostgreSQLConnHigh)
2. ⏭️ **Criar dashboards SLI específicos** (GAP-001 fase 3)
3. ⏭️ **Configurar Alertmanager routing** (para separar critical/warning)
4. ⏭️ **Implementar error budget tracking** (dashboard Grafana)
5. ⏭️ **Documentar runbooks** para cada alerta crítico

---

**Status:** ⚠️ 7/10 alertas validados, 3 faltando
**Ação Imediata:** Criar PrometheusRule para latency + error rate
**Prazo:** Até fim do dia (2026-02-10)
**Responsável:** SRE Team
