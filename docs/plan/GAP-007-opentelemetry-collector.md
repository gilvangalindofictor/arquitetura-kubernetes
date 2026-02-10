# GAP-007: OpenTelemetry Collector Deployment

**Identificado em:** 2026-02-09
**Prioridade:** 🔴 Alta (antecipado para Semana 3 — synergy com VPA)
**Bloqueante:** Observabilidade completa (Marco 2 Fase 8) + FinOps rightsizing validation
**Esforço:** 6h
**Status:** 🚀 Planejado para 18-20/Fev (integrado no roadmap FinOps 90d)

---

## 📊 Contexto

### Situação Atual

**DEPLOYADO:**
- ✅ Grafana Tempo (11 pods Running)
- ✅ S3 backend para traces (`k8s-platform-tempo-891377105802`)
- ✅ Network Policies preparadas para OTel Collector
- ✅ Grafana datasource Tempo configurado

**AUSENTE:**
- ❌ OpenTelemetry Collector (Gateway de ingestão)
- ❌ Instrumentação de aplicações

**Impacto:**
- Aplicações **não conseguem enviar traces** (sem endpoint OTLP)
- Tempo operacional mas **ocioso** (sem dados)
- Observabilidade **incompleta:** Métricas ✅ + Logs ✅ + Traces ❌

---

## 🎯 Objetivo

Deployar OpenTelemetry Collector para completar a stack de observabilidade, permitindo:
1. Aplicações enviarem traces via OTLP (gRPC/HTTP)
2. Correlação traces ↔ logs ↔ metrics no Grafana
3. Distributed tracing funcional end-to-end

---

## 🏗️ Componentes

### 1. OpenTelemetry Collector (Gateway Mode)

**Helm Chart:** open-telemetry/opentelemetry-collector v0.108.x

**Configuração:**
```yaml
mode: deployment
replicas: 2
service:
  type: ClusterIP
  ports:
    - name: otlp-grpc
      port: 4317
      targetPort: 4317
      protocol: TCP
    - name: otlp-http
      port: 4318
      targetPort: 4318
      protocol: TCP

receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    send_batch_size: 1024
    timeout: 10s
  memory_limiter:
    check_interval: 5s
    limit_mib: 512

exporters:
  otlp/tempo:
    endpoint: tempo-distributor.monitoring.svc.cluster.local:4317
    tls:
      insecure: true
  prometheusremotewrite:
    endpoint: http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090/api/v1/write
  loki:
    endpoint: http://loki-gateway.monitoring.svc.cluster.local:3100/loki/api/v1/push

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [otlp/tempo]
    metrics:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [prometheusremotewrite]
    logs:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [loki]
```

**Resources:**
```yaml
requests:
  cpu: 100m
  memory: 256Mi
limits:
  cpu: 500m
  memory: 512Mi
```

**Tolerations:**
```yaml
- key: node-type
  operator: Equal
  value: system
  effect: NoSchedule
```

**ServiceMonitor:** Integração Prometheus
```yaml
enabled: true
labels:
  release: kube-prometheus-stack
interval: 30s
```

---

### 2. Network Policies (Já criadas)

✅ **allow-otel-collector-ingress** - Apps → Collector (4317, 4318)
✅ **allow-otel-to-tempo** - Collector → Tempo Distributor (3100, 4317)

---

### 3. Grafana Correlações

**Derived Fields (Loki → Tempo):**
```json
{
  "datasourceUid": "tempo",
  "matcherRegex": "trace_id=(\\w+)",
  "name": "TraceID",
  "url": "${__value.raw}"
}
```

**Exemplars (Prometheus → Tempo):**
```yaml
prometheusremotewrite:
  exemplars:
    enabled: true
```

---

## 📦 Tarefas

### Fase 1: Deploy Collector (3h)

1. **Criar módulo Terraform** `modules/opentelemetry-collector/` (1.5h)
   - Service Account (sem IRSA, usa ClusterIP interno)
   - Helm release opentelemetry-collector
   - ConfigMap para receivers/processors/exporters
   - ServiceMonitor Prometheus

2. **Deploy e validação** (1h)
   - `terraform apply -target=module.opentelemetry_collector`
   - Verificar pods 2/2 Running
   - Testar conectividade Collector → Tempo
   - Validar logs ingestão

3. **Documentação** (0.5h)
   - Atualizar [architecture.md](../context/architecture.md) - Fase 8 "Planejada" → "Deployado"
   - Criar guia instrumentação apps

---

### Fase 2: Instrumentação Apps (3h)

**Aplicações para instrumentar:**

1. **GitLab (Ruby)** (1h)
   - Gem `opentelemetry-sdk`
   - Config: `OTEL_EXPORTER_OTLP_ENDPOINT=http://opentelemetry-collector.monitoring.svc.cluster.local:4317`
   - Restart webservice/sidekiq

2. **Harbor (Golang)** (1h)
   - SDK `go.opentelemetry.io/otel`
   - Instrumentação HTTP handlers
   - Rebuild image + deploy

3. **Aplicação de teste** (1h)
   - Python Flask simples com `opentelemetry-instrumentation-flask`
   - Deploy no namespace test-apps
   - Validar trace end-to-end (app → Collector → Tempo → Grafana)

---

## 💰 Custos

| Componente | Recurso | Custo/Mês |
|------------|---------|-----------|
| OTel Collector | 2 pods (500m CPU, 512Mi RAM) | $0 (usa nodes existentes) |
| Network egress | Tempo traces (estimado 100GB/mês) | $0 (S3 transfer free within region) |
| **TOTAL** | | **$0** ✅ |

**Economia vs Jaeger:** Já contabilizada no ADR-020 ($205.55/mês saved)

---

## 🎯 Critérios de Aceitação

- [ ] OpenTelemetry Collector 2/2 pods Running
- [ ] Receivers OTLP gRPC/HTTP funcionais (ports 4317/4318)
- [ ] Exporters conectados:
  - [ ] Tempo (traces via OTLP)
  - [ ] Prometheus (metrics via remote write)
  - [ ] Loki (logs)
- [ ] ServiceMonitor integrado Prometheus
- [ ] Network Policies validadas
- [ ] App de teste enviando traces
- [ ] Trace visível no Grafana Explore (TraceQL query)
- [ ] Correlação trace_id → logs funcionando
- [ ] Documentação atualizada

---

## 🔗 Dependências

**Pré-requisitos (Completos):**
- ✅ Marco 2 Fase 8: Tempo deployado
- ✅ Network Policies criadas
- ✅ Grafana datasource Tempo configurado

**Bloqueia:**
- GAP 1: SLIs/SLOs (precisa traces para latency p95/p99)
- Marco 3: GitLab instrumentação (CI/CD tracing)

---

## 📚 Referências

- [ADR-020: Tempo vs Jaeger](../context/decisions.md#adr-020)
- [OpenTelemetry Collector Docs](https://opentelemetry.io/docs/collector/)
- [Helm Chart](https://github.com/open-telemetry/opentelemetry-helm-charts)
- [Tempo Módulo](../../platform-provisioning/aws/kubernetes/terraform/modules/tempo/main.tf)

---

**Próxima Ação:** Criar módulo Terraform `opentelemetry-collector/`
**Responsável:** SRE Specialist + Observabilidade Specialist
**Timeline:** 6h (pode ser paralelo com GAP 1 Observabilidade)
