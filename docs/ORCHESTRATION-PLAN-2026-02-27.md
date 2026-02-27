# Plano de Orquestração — 8 Demandas Paralelas
**Data**: 2026-02-27 11:15 BRT
**Orquestrador**: Claude Sonnet 4.5
**Workflow**: executor-terraform.md
**Sessão AWS**: Aguardando login (polling ativo)

---

## 📋 Inventário de Demandas

### Fase 1: Ações Imediatas (3 demandas)
1. **AÇÃO-005**: Terraform Apply (Kyverno 100% compliance)
2. **AÇÃO-007**: WAF Dashboard + Alerts Deploy
3. **AÇÃO-006**: Velero Drift Detection Test

### Fase 2: CI/CD Enhancement (5 demandas)
4. **CICD-001**: SAST/DAST Security Scanning
5. **CICD-004**: Immutable Image Tags
6. **CICD-003**: Automated Secret Rotation
7. **CICD-002**: SonarQube Quality Gate
8. **CICD-005**: Argo Rollouts (deferred)

---

## 🎯 Estratégia de Execução

### Wave 1: Ações Imediatas (Paralelo 3 Agentes)

**Timing**: 15-20 minutos
**Agentes**: general-purpose (3× parallel)

| Agent | Demanda | Ações | Validação | Rollback |
|-------|---------|-------|-----------|----------|
| **A1** | AÇÃO-005 | `terraform apply` kube-prometheus-stack + loki | 49/49 pods labeled | `terraform destroy --target` |
| **A2** | AÇÃO-007 | `kubectl apply` WAF ConfigMap + PrometheusRule | Dashboard visible, 3 alerts active | `kubectl delete` |
| **A3** | AÇÃO-006 | GitLab CI trigger + CronJob logs | Drift report JSON, Slack notification | Manual cleanup |

**Paralelização**: Independentes, sem dependências cruzadas

**Comandos Preparados**:

```bash
# Agent A1 (AÇÃO-005)
cd platform-provisioning/aws/kubernetes/terraform/environments/staging
terraform plan -target=module.kube_prometheus_stack_staging -target=module.loki
terraform apply -target=module.kube_prometheus_stack_staging -target=module.loki -auto-approve
kubectl get pods -n staging-observability-monitoring -o json | jq '[.items[].metadata.labels | select(.domain=="operations")] | length'

# Agent A2 (AÇÃO-007)
kubectl apply -f domains/observability/infra/grafana/waf-dashboard-configmap.yaml
kubectl apply -f domains/observability/infra/prometheus/waf-prometheus-rules.yaml
kubectl get prometheusrule -n staging-observability-monitoring waf-security-alerts

# Agent A3 (AÇÃO-006)
# GitLab CI: Manual trigger velero:drift:pre-deploy (awaits manual action)
kubectl get cronjob -n velero velero-drift-detection
kubectl logs -n velero $(kubectl get pods -n velero -l job-name --sort-by=.metadata.creationTimestamp -o name | tail -1)
```

---

### Wave 2: CI/CD Enhancement Wave A (Paralelo 3 Agentes)

**Timing**: 2-3 dias (48h effort, paralelo)
**Agentes**: general-purpose (3× parallel)

| Agent | Demanda | Esforço | Artefatos | Status Base |
|-------|---------|---------|-----------|-------------|
| **B1** | CICD-001 | 16h (S) | ✅ 9 files criados (2026-02-26) | VALIDAR + DEPLOY |
| **B2** | CICD-004 | 16h (S) | ✅ 6 files criados (2026-02-26) | VALIDAR + DEPLOY |
| **B3** | CICD-003 | 40h (L) | ✅ 8 files criados (2026-02-26) | DEPLOY Terraform CronJob |

**Dependência**: Nenhuma (podem rodar em paralelo)

**Artefatos Base** (já criados 2026-02-26):

CICD-001:
- `domains/cicd-platform/infra/gitlab-ci/templates/.gitlab-ci-security-template.yml`
- `domains/observability/infra/prometheus/cicd-sast-dast-alerts.yaml`
- `domains/observability/infra/grafana/dashboards/cicd-security-dashboard.json`
- `docs/adr/adr-081-sast-dast-security-scanning.md`

CICD-004:
- `scripts/harbor/configure-immutable-tags.sh`
- `domains/cicd-platform/infra/gitlab-ci/templates/.gitlab-ci-image-tagging.yml`
- `docs/adr/adr-084-immutable-image-tags.md`

CICD-003:
- `domains/security/terraform/cronjob-secret-rotation.tf` (Terraform module)
- `scripts/vault/rotate-secrets.sh` (690 lines)
- `docs/adr/adr-083-automated-secret-rotation.md`

**Ações Wave B1/B2/B3**:
1. **Validation**: Verificar artefatos existentes (git status, file existence)
2. **Deployment**: Aplicar configurações (kubectl apply, terraform apply, scripts)
3. **Testing**: Validar funcionamento (trigger manual, check logs, verify alerts)
4. **Documentation**: Atualizar demands-backlog.md (PENDENTE → DEPLOYED)

---

### Wave 3: CI/CD Enhancement Wave B (Sequencial após CICD-001)

**Timing**: 2 dias (16h effort)
**Agentes**: general-purpose (1× after CICD-001)

| Agent | Demanda | Esforço | Dependência | Status Base |
|-------|---------|---------|-------------|-------------|
| **C1** | CICD-002 | 16h (S) | **AFTER CICD-001** ✅ | ✅ 8 files criados (2026-02-26) |

**Artefatos Base**:
- `scripts/sonarqube/configure-quality-gate.sh`
- `domains/cicd-platform/infra/gitlab-ci/templates/.gitlab-ci-quality-gate.yml`
- `docs/adr/adr-082-sonarqube-quality-gate.md`

---

### Wave 4: Argo Rollouts (Deferred)

**Timing**: 8 dias (64h effort)
**Agentes**: 1× general-purpose
**Status**: **DEFERRED** — aguardar apps instrumentadas com Prometheus metrics

| Agent | Demanda | Esforço | Blocker | ETA |
|-------|---------|---------|---------|-----|
| **D1** | CICD-005 | 64h (XL) | Apps sem Prometheus metrics | TBD (Week 5-6) |

**Artefatos Base**:
- ✅ Terraform module criado: `modules/argo-rollouts/`
- ✅ AnalysisTemplates: `domains/apps/manifests/analysis-templates/` (4 files)
- ✅ Rollout examples: `domains/apps/manifests/rollouts/`
- ✅ ADR-085 criado

**Próximos Passos**:
1. Instrumentar apps com Prometheus metrics (http_requests_total, http_request_duration_seconds)
2. Deploy Argo Rollouts Terraform module
3. Test canary deployment (20% → 100%)
4. Validate automated rollback on metric failure

---

## 📊 Métricas de Execução

### Esforço Total
- **Fase 1**: 30 min (3 agentes × 10 min avg)
- **Fase 2 Wave A**: 72h effort → ~24h real (3 agentes paralelos)
- **Fase 2 Wave B**: 16h effort → ~16h real (1 agente)
- **Fase 2 Wave C**: 64h effort → ~64h real (deferred)

**Total Real Time**: ~3 dias (Fase 1 + 2A + 2B)
**Total Effort**: 88h (excluindo CICD-005)

### Token Budget
- **Fase 1**: ~30K tokens (3 agentes × 10K)
- **Fase 2**: ~120K tokens (4 agentes × 30K)
- **Total**: ~150K tokens (within 200K limit)

### Commits Esperados
- Fase 1: 3 commits (1 por agent)
- Fase 2: 4 commits (1 por demanda)
- **Total**: 7 commits

---

## 🔧 Comandos de Orquestração

### Pré-Requisitos
```bash
# 1. Sessão AWS ativa
aws sts get-caller-identity --profile k8s-platform-prod

# 2. Cluster acessível
kubectl cluster-info

# 3. Terraform inicializado
cd platform-provisioning/aws/kubernetes/terraform/environments/staging
terraform init

# 4. Git branch limpa
git status
```

### Lançamento Fase 1 (3 Agentes Paralelos)
```bash
# Lançar em uma única mensagem com 3 Task tool calls
Task(subagent_type="general-purpose", description="Apply Terraform AÇÃO-005", prompt="...")
Task(subagent_type="general-purpose", description="Deploy WAF dashboard AÇÃO-007", prompt="...")
Task(subagent_type="general-purpose", description="Test Velero drift AÇÃO-006", prompt="...")
```

### Lançamento Fase 2 Wave A (3 Agentes Paralelos)
```bash
# Após Fase 1 completa
Task(subagent_type="general-purpose", description="Validate+Deploy CICD-001", prompt="...")
Task(subagent_type="general-purpose", description="Validate+Deploy CICD-004", prompt="...")
Task(subagent_type="general-purpose", description="Deploy CICD-003 Terraform", prompt="...")
```

### Lançamento Fase 2 Wave B (1 Agente Sequencial)
```bash
# Após CICD-001 completo
Task(subagent_type="general-purpose", description="Validate+Deploy CICD-002", prompt="...")
```

---

## ✅ Critérios de Sucesso

### Fase 1
- [ ] Terraform apply: 0 errors, 49/49 pods labeled (domain=operations)
- [ ] WAF dashboard: visible in Grafana UI, 3 PrometheusRule alerts active
- [ ] Velero drift: CronJob logs accessible, GitLab CI job triggered

### Fase 2 Wave A
- [ ] CICD-001: GitLab CI security template functional, Trivy/Semgrep scans pass
- [ ] CICD-004: Harbor immutable tags enforced, GitLab CI tagging (sha-*, v*, env)
- [ ] CICD-003: Vault secret rotation CronJob deployed, 90-day rotation active

### Fase 2 Wave B
- [ ] CICD-002: SonarQube quality gate enforced, GitLab CI fails on coverage <80%

---

## 🚨 Rollback Plan

### Terraform (AÇÃO-005)
```bash
terraform destroy -target=module.kube_prometheus_stack_staging -target=module.loki -auto-approve
git revert <commit-hash>
```

### Kubernetes (AÇÃO-007)
```bash
kubectl delete -f domains/observability/infra/grafana/waf-dashboard-configmap.yaml
kubectl delete -f domains/observability/infra/prometheus/waf-prometheus-rules.yaml
```

### CI/CD Artifacts
```bash
# Remove GitLab CI templates from repos
# Disable Harbor immutable tags via Harbor UI
# Delete Vault secret rotation CronJob
kubectl delete cronjob -n vault vault-secret-rotation
```

---

## 📝 Logging & Auditoria

### Formato Logbook
```
[HH:MM:SS] <Etapa> | <Agente> | <Ação> | <Resultado>

Exemplos:
[11:15:00] Pre-check | Orq | Sessão AWS validada | ✅
[11:16:30] TF Plan | A1 | terraform plan (AÇÃO-005) | 27 changes
[11:18:45] TF Apply | A1 | terraform apply (AÇÃO-005) | ✅ 0 errors
[11:20:00] K8s Deploy | A2 | kubectl apply WAF dashboard | ✅ ConfigMap created
[11:22:15] Validation | A1 | Kyverno compliance check | ✅ 49/49 (100%)
```

### Arquivos de Log
- `docs/logbook/2026-02-27-orchestration-phase1.md` (Fase 1)
- `docs/logbook/2026-02-27-orchestration-phase2-waveA.md` (Fase 2A)
- `docs/logbook/2026-02-27-orchestration-phase2-waveB.md` (Fase 2B)

---

**Status**: ⏳ Aguardando login AWS
**Próximo Passo**: Lançar Fase 1 (3 agentes paralelos) após sessão confirmada
**ETA Fase 1**: 15-20 minutos após login

**Orquestrador**: Claude Sonnet 4.5
**Workflow**: executor-terraform.md
