# 2026-03-04 — GAP-010 WAF Observability Complete

**Demand**: GAP-010
**Session type**: Infrastructure + Observability
**Agent**: Observability & SRE Specialist + AWS Specialist
**Duration**: ~45 minutes
**Status**: Artefatos criados, aguardando deploy manual

---

## Summary

Completou os 4 itens pendentes do GAP-010 (WAF Observability):

1. YACE CloudWatch Exporter configurado (aguardando deploy)
2. CloudWatch datasource provisionado (aguardando kubectl apply)
3. IAM roles Terraform criados (aguardando terraform apply)
4. Scripts de validação criados
5. ADR-099 criado

---

## Artifacts Created (this session)

### YACE CloudWatch Exporter
| File | Lines | Description |
|------|-------|-------------|
| `domains/observability/infra/yace-cloudwatch-exporter/values.yaml` | ~165 | Helm values: IRSA, ServiceMonitor, WAF/WAFV2 discovery jobs |
| `domains/observability/infra/yace-cloudwatch-exporter/helmrelease.yaml` | ~48 | ArgoCD Application manifest + helm CLI install command |
| `domains/observability/infra/yace-cloudwatch-exporter/iam-policy.json` | ~38 | IAM policy: cloudwatch:GetMetricData + wafv2:List*/Get* |
| `domains/observability/infra/yace-cloudwatch-exporter/terraform-yace-iam.tf` | ~100 | Terraform IRSA role for YACE ServiceAccount |
| `domains/observability/infra/yace-cloudwatch-exporter/terraform-grafana-iam.tf` | ~105 | Terraform IRSA role for Grafana ServiceAccount |

### Grafana CloudWatch Datasource
| File | Lines | Description |
|------|-------|-------------|
| `domains/observability/infra/grafana/cloudwatch-datasource-configmap.yaml` | ~75 | ConfigMap with grafana_datasource="1" label for sidecar auto-import |
| `domains/observability/infra/grafana/grafana-sa-irsa-patch.yaml` | ~40 | Patch para IRSA annotation na SA do Grafana |

### WAF Validation Script
| File | Lines | Description |
|------|-------|-------------|
| `scripts/waf/validate-waf-rules.sh` | ~310 | 8 testes: SQLi, XSS, bad inputs, rate limit, geo block, CloudWatch metrics |

### Documentation
| File | Lines | Description |
|------|-------|-------------|
| `docs/adr/adr-099-waf-strategy-ipaas-public.md` | ~215 | ADR completo: contexto, decision, alternativas, consequências, deploy sequence |

**Total**: 9 arquivos, ~1096 linhas

---

## Pre-existing Artifacts (reviewed)

| File | Status |
|------|--------|
| `domains/observability/infra/grafana/waf-dashboard-configmap.yaml` | OK — 8 panels, CloudWatch datasource, correto |
| `domains/observability/infra/prometheus/waf-prometheus-rules.yaml` | OK — 3 alertas (WAFHighBlockRate, WAFGeoBlockSpike, WAFSQLInjectionAttempts) |
| `docs/runbooks/waf-incident-response.md` | OK — runbook completo |
| `platform-provisioning/aws/kubernetes/terraform/modules/waf/main.tf` | OK — 5 regras, S3 logging, ALB association |

---

## Root Cause of "nodata" Alerts

The 3 PrometheusRule alerts (WAFHighBlockRate, WAFGeoBlockSpike, WAFSQLInjectionAttempts) use PromQL metrics like `aws_wafv2_blocked_requests_sum`. These metrics are produced by YACE CloudWatch Exporter, which was not deployed.

**Fix**: Deploy YACE (`helm upgrade --install yace-cloudwatch-exporter ...`) after applying Terraform IAM roles. Once YACE is running and Prometheus scrapes it, the alerts will transition from `nodata` to `inactive` (normal) or `firing` (if WAF is blocking).

---

## Deploy Checklist (Post-Session)

### Step 1: Terraform (IAM Roles)
```bash
cd domains/observability/infra/yace-cloudwatch-exporter/
terraform init
terraform apply \
  -target=aws_iam_role.yace_cloudwatch \
  -target=aws_iam_role.yace_cloudwatch_policy_attachment \
  -target=aws_iam_role.grafana_cloudwatch \
  -target=aws_iam_role.grafana_cloudwatch_policy_attachment
```

### Step 2: YACE Deploy
```bash
helm repo add nerdswords https://nerdswords.github.io/yet-another-cloudwatch-exporter
helm repo update
helm upgrade --install yace-cloudwatch-exporter \
  nerdswords/yet-another-cloudwatch-exporter \
  --namespace staging-observability-monitoring \
  --version 0.37.0 \
  -f domains/observability/infra/yace-cloudwatch-exporter/values.yaml
```

### Step 3: Grafana CloudWatch Datasource
```bash
kubectl apply -f domains/observability/infra/grafana/cloudwatch-datasource-configmap.yaml
```

### Step 4: Grafana IRSA
```bash
kubectl patch serviceaccount kube-prometheus-stack-grafana \
  -n staging-observability-monitoring \
  --patch-file domains/observability/infra/grafana/grafana-sa-irsa-patch.yaml
kubectl rollout restart deployment/kube-prometheus-stack-grafana \
  -n staging-observability-monitoring
```

### Step 5: Validation
```bash
export WAF_ALB_DNS="k8s-platformstaging-00e0ecf3b4.us-east-1.elb.amazonaws.com"
export AWS_PROFILE="k8s-platform-prod"
bash scripts/waf/validate-waf-rules.sh
```

### Step 6: Verify alerts resolve
```bash
# Check YACE is exporting WAF metrics
kubectl exec -n staging-observability-monitoring \
  $(kubectl get pods -n staging-observability-monitoring \
    -l app.kubernetes.io/name=yet-another-cloudwatch-exporter \
    -o jsonpath='{.items[0].metadata.name}') \
  -- wget -qO- http://localhost:5000/metrics | grep aws_wafv2 | head -20

# Check Prometheus sees the metrics
# Prometheus UI: http://prometheus.staging.internal/graph
# Query: aws_wafv2_blocked_requests_sum
```

---

## Cost Impact

| Component | Monthly Cost |
|-----------|-------------|
| WAF WebACL | ~$5 |
| WAF Managed Rules (5 × $1/M) | ~$1-3 |
| S3 WAF Logs (90-day retention) | ~$2-5 |
| YACE pod (CPU/memory in EKS) | negligible |
| **Total** | **~$8-13/mês (~R$ 45-70/mês)** |

**Security ROI**: Protection against DDoS, SQLi, XSS, Log4Shell with $10/mês vs Cloudflare Business at $200/mês (20x cheaper).

---

## Next Steps

- [ ] Deploy Terraform IAM roles (Step 1 above)
- [ ] Deploy YACE helm chart (Step 2 above)
- [ ] Apply CloudWatch datasource ConfigMap (Step 3 above)
- [ ] Patch Grafana SA for IRSA (Step 4 above)
- [ ] Run validation script (Step 5 above)
- [ ] Confirm WAF alerts leave "nodata" state in Prometheus
- [ ] Confirm Grafana dashboard "AWS WAF Security Dashboard - GAP-010" populates data
- [ ] Consider WAF for production promotion (ADR-099 references Shield Advanced for prod)
