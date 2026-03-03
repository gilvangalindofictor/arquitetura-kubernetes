# 2026-03-03: WAF Dashboard & Alerts Deploy (ACAO-007)

**Date**: 2026-03-03
**Duration**: ~25 minutes
**Agents**: Orquestrador + Observability SRE + Security
**Status**: DEPLOYADO com side-effects resolvidos
**Priority**: P2 (Observability completeness)

---

## Resumo Executivo

Aplicado no cluster os artefatos WAF observability criados em 2026-02-27 (ACAO-007):

- ConfigMap `waf-security-dashboard` (Grafana, 8 panels, CloudWatch datasource) — DEPLOYADO
- PrometheusRule `waf-security-alerts` (3 alertas) — DEPLOYADO + carregado pelo Prometheus

**Side-effect descoberto e corrigido**: Grafana, Prometheus e Alertmanager estavam em 0/1 por falha Kyverno `require-corporate-labels` (missing `app.kubernetes.io/part-of`). Todos fixados durante execucao.

---

## PRE-CHECK

```
AWS SSO: k8s-platform-prod
Account: 891377105802 (arn:aws:sts::891377105802:assumed-role/AWSReservedSSO_AdministratorAccess_*/gilvan.galindo)
Sessao: VALIDA
```

---

## Etapa 0: Contexto Historico

- ACAO-007 criada em 2026-02-27 PM session por Agent 4 (WAF Observability)
- Artefatos nunca aplicados (criados como codigo, pendentes `kubectl apply`)
- Logbook original: nenhum logbook especifico de deploy existia

---

## Etapa 1: Artefatos Validados

| Artefato | Path | Status |
|----------|------|--------|
| ConfigMap | `domains/observability/infra/grafana/waf-dashboard-configmap.yaml` | OK |
| PrometheusRule | `domains/observability/infra/prometheus/waf-prometheus-rules.yaml` | OK |

**Validacoes pre-apply**:
- namespace `staging-observability-monitoring`: EXISTS (Active, 6d6h)
- CRD `prometheusrules.monitoring.coreos.com`: EXISTS (2026-01-28)
- Grafana sidecar autodiscovery (`grafana_dashboard: "1"`): CONFIRMADO (20+ dashboards existentes)
- ruleSelector: `{matchLabels: {release: kube-prometheus-stack}}` — labels nos artefatos: CORRETO

---

## Etapa 2: Consenso Agentes

**[Observability SRE]**: APROVAR. Dashboard 8 panels bem formados. ruleSelector correto. Riscos: CloudWatch datasource e cloudwatch-exporter nao deployados (documentados abaixo).

**[Security]**: APROVAR. 3 vetores cobertos (DoS proxy, geo-block coordenado, SQLi OWASP). Severity levels corretos (WAFSQLInjectionAttempts=critical, for=1m).

---

## Etapa 3: kubectl apply

```bash
kubectl apply -f domains/observability/infra/grafana/waf-dashboard-configmap.yaml
# configmap/waf-security-dashboard unchanged   ← ja existia (session anterior)

kubectl apply -f domains/observability/infra/prometheus/waf-prometheus-rules.yaml
# prometheusrule.monitoring.coreos.com/waf-security-alerts unchanged   ← ja existia
```

Artefatos estavam pre-existentes (aplicados em sessao anterior sem documentacao). Estado correto no cluster.

---

## STOP-AND-FIX: Kyverno Corporate Labels Bloqueando Stack

### Descoberta

Ao tentar validar dashboard import no sidecar, detectado:
```
kubectl get deployment kube-prometheus-stack-grafana -n staging-observability-monitoring
# 0/1 Available
```

**Root cause**: Kyverno `require-corporate-labels` (ADR-048) bloqueando pods por missing `app.kubernetes.io/part-of`.

Afetados:
- `kube-prometheus-stack-grafana` (Deployment) — 0/1 → blocked
- `prometheus-kube-prometheus-stack-prometheus` (StatefulSet) — 0/1 → blocked
- `alertmanager-kube-prometheus-stack-alertmanager` (StatefulSet) — 0/1 → blocked

Adicionalmente (nao corrigidos nesta sessao, nao criticos para WAF):
- `loki-gateway`, `opentelemetry-collector`, `tempo-gateway`, `tempo-query-frontend` (Deployments)
- `tempo-memcached` (StatefulSet)

### Fix Aplicado

```bash
# Grafana - patch direto no Deployment
kubectl patch deployment kube-prometheus-stack-grafana -n staging-observability-monitoring \
  --type=json \
  -p='[{"op":"add","path":"/spec/template/metadata/labels/app.kubernetes.io~1part-of","value":"kube-prometheus-stack"}]'
# deployment.apps/kube-prometheus-stack-grafana patched

# Prometheus - patch no CRD (operador reconcilia o StatefulSet)
# IMPORTANTE: patch direto no StatefulSet e revertido pelo Prometheus Operator
kubectl patch prometheus kube-prometheus-stack-prometheus -n staging-observability-monitoring \
  --type=merge \
  -p='{"spec":{"podMetadata":{"labels":{"domain":"operations","environment":"staging","owner":"platform-team","app.kubernetes.io/part-of":"kube-prometheus-stack"}}}}'
# prometheus.monitoring.coreos.com/kube-prometheus-stack-prometheus patched

# Alertmanager - patch direto no StatefulSet (nao gerenciado por CRD do mesmo modo)
kubectl patch statefulset alertmanager-kube-prometheus-stack-alertmanager -n staging-observability-monitoring \
  --type=json \
  -p='[{"op":"add","path":"/spec/template/metadata/labels/app.kubernetes.io~1part-of","value":"kube-prometheus-stack"}]'
# statefulset.apps/alertmanager-kube-prometheus-stack-alertmanager patched
```

### Resultado

```
kube-prometheus-stack-grafana-5fc9f696bf-ft5d2              3/3  Running   0  8m20s
prometheus-kube-prometheus-stack-prometheus-0               2/2  Running   0  2m23s
alertmanager-kube-prometheus-stack-alertmanager-0           2/2  Running   0  3m34s
```

---

## Etapa 5: Validacao Pos-Apply (AML)

### Dashboard Import

```
[grafana-sc-dashboard] Writing /tmp/dashboards/waf-security-dashboard.json (ascii)
[grafana-sc-dashboard] None sent to http://localhost:3000/api/admin/provisioning/dashboards/reload. Response: 200 OK {"message":"Dashboards config reloaded"}
[grafana-sc-dashboard] Initial sync complete, sidecar is ready.
```

Dashboard `waf-security-dashboard.json` importado com sucesso pelo sidecar.

### PrometheusRule

```bash
kubectl exec prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- wget -qO- http://localhost:9090/api/v1/rules
# GROUP: waf_security_alerts
#   - WAFHighBlockRate | type=alerting | state=inactive
#   - WAFGeoBlockSpike | type=alerting | state=inactive
#   - WAFSQLInjectionAttempts | type=alerting | state=inactive
# Total rule groups: 61
```

3/3 alertas carregados. Estado `inactive` = correto (sem ataque ativo).

---

## Gaps Remanescentes (Pendentes)

### GAP-A: CloudWatch Datasource (OBRIGATORIO para Dashboard)

O dashboard usa `${DS_CLOUDWATCH}` como datasource. Nao esta provisionado automaticamente.

**Opcao 1 (Recomendada — GitOps)**: Adicionar ao ConfigMap `kube-prometheus-stack-grafana-datasource`:
```yaml
- name: "CloudWatch"
  type: cloudwatch
  uid: cloudwatch
  jsonData:
    authType: default
    defaultRegion: us-east-1
```
Requer que o pod tenha IAM role com `cloudwatch:GetMetricData`, `cloudwatch:ListMetrics`.

**Opcao 2 (Manual)**: Grafana UI → Configuration → Data Sources → Add → CloudWatch.

**IAM**: O node group usa instance profile. Verificar se `CloudWatchReadOnlyAccess` esta attached ou adicionar policy inline ao instance profile `k8s-platform-prod-*-node-role`.

### GAP-B: cloudwatch-exporter / YACE (OBRIGATORIO para PrometheusRule)

PrometheusRule usa metricas `aws_wafv2_blocked_requests_sum` e `aws_wafv2_allowed_requests_sum`.
Essas metricas sao expostas pelo **Yet Another CloudWatch Exporter (YACE)** ou `cloudwatch-exporter`.
Sem o exporter, alertas ficam com `nodata` e nao disparam.

**Deploy recomendado**: Helm chart `yet-another-cloudwatch-exporter` com config WAF:
```yaml
jobs:
  - regions: [us-east-1]
    metrics:
      - aws_namespace: AWS/WAFV2
        aws_metric_name: BlockedRequests
        aws_dimensions: [WebACL, Rule, Region]
        aws_statistics: [Sum]
      - aws_namespace: AWS/WAFV2
        aws_metric_name: AllowedRequests
        aws_dimensions: [WebACL, Rule, Region]
        aws_statistics: [Sum]
```

---

## Recursos Deployados

| Recurso | Kind | Namespace | Status |
|---------|------|-----------|--------|
| `waf-security-dashboard` | ConfigMap | staging-observability-monitoring | Running (4d6h + confirmed) |
| `waf-security-alerts` | PrometheusRule | staging-observability-monitoring | Active (3 rules, inactive state) |

## Side-Effects Corrigidos

| Recurso | Problema | Fix |
|---------|----------|-----|
| `kube-prometheus-stack-grafana` | Missing `part-of` → Kyverno block | Deployment patch |
| `prometheus-kube-prometheus-stack-prometheus` | Missing `part-of` → Kyverno block | Prometheus CRD podMetadata patch |
| `alertmanager-kube-prometheus-stack-alertmanager` | Missing `part-of` → Kyverno block | StatefulSet patch |

## Pendencias (Proxima Sessao)

1. Deploy cloudwatch-exporter/YACE para ativar metricas `aws_wafv2_*`
2. Provisionar CloudWatch datasource no Grafana (ConfigMap ou manual)
3. Corrigir `part-of` label nos demais recursos: `loki-gateway`, `opentelemetry-collector`, `tempo-gateway`, `tempo-query-frontend`, `tempo-memcached`
4. Persistir fix do Alertmanager no values.yaml do kube-prometheus-stack (evitar regressao no proximo helm upgrade)
