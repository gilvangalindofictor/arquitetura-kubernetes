# 📋 Documentos de Planejamento

**Last Updated:** 2026-02-12
**Status:** Current
**Owner:** Platform Team
**Scope:** Planning & Execution Documents

Este diretório contém os planos de ação e execução para tarefas de infraestrutura.

---

## Estrutura de Documentos

### Documentos Ativos (2026-02-12)

| Documento                                   | Propósito                                          | Audiência                |
| ------------------------------------------- | -------------------------------------------------- | ------------------------ |
| **STATUS-2026-02-12.md** (raiz docs/)       | Single source of truth — estado atual cluster     | Todos                    |
| **PLANO-ACAO-2026-02-12.md**                | Resumo executivo — pendências simplificadas       | CTO, Gerentes, DevOps    |
| **EXECUCAO-QUICKSTART-MVP-2026-02-12.md** ⭐ | Plano detalhado para executor-terraform agent     | Executor, Automação      |

---

## EXECUCAO-QUICKSTART-MVP-2026-02-12.md

**Padrão**: executor-terraform.md (Active Monitoring Loop + STOP-AND-FIX)

### Conteúdo

- **Análise Inicial**: Impacto, agentes, riscos, rollback plan
- **5 Tasks Detalhadas**:
  1. GitLab OIDC Integration (45min)
  2. Node Groups v1.34 (1h30min)
  3. E2E Smoke Test App (3h)
  4. FinOps Grafana Dashboards (2h)
  5. FinOps Automation (1h)
- **AML Configuration**: poll_interval, max_wait, recursos relacionados
- **Comandos Background**: >10s em background com PID tracking
- **STOP-AND-FIX Checkpoints**: Problemas prováveis + diagnóstico + fix
- **DocSync**: architecture.md, costs.md, decisions.md, logbook updates
- **Validação Idempotência**: `terraform plan "No changes"` obrigatório

### Formato de Resposta Executor

```
TASK#1 GitLab OIDC | ✅ 42min | Helm rollback + TF apply + E2E OK
TASK#2 Nodes v1.34 | ✅ 1h27min | Rolling replace, 7 nodes, zero downtime
TASK#3 E2E App | ✅ 2h52min | FastAPI deployed, logs/traces/metrics validated
TASK#4 FinOps Dashboards | ✅ 2h5min | 3 dashboards operational
TASK#5 FinOps Automation | ✅ 58min | Lambda cleanup, tagging 100%
---
MVP Completion: 75% → 95% | Total: 7h64min
```

---

## PLANO-ACAO-2026-02-12.md

**Padrão**: Resumo executivo simplificado

### Conteúdo

- Economias já realizadas (R$ 34.462/ano)
- 2 pendências críticas hoje (GitLab OIDC + Nodes v1.34)
- Timeline hoje (2h15min)
- Critérios de sucesso
- Rollback plans
- Referência ao plano detalhado: [EXECUCAO-QUICKSTART-MVP-2026-02-12.md](EXECUCAO-QUICKSTART-MVP-2026-02-12.md)

---

## Quickstart Reference

### Fonte da Verdade

[quickstart/aws-eks-gitlab-quickstart-REAL.md](quickstart/aws-eks-gitlab-quickstart-REAL.md) — v2.0 (2026-02-10)

**Sprints:**
- Sprint 1: Infrastructure + GitLab (100% ✅)
- Sprint 2: Observability (100% ✅)
- Sprint 3: Hardening (85% ✅ — WAF/Velero diferidos)

**MVP Status**: 75% → target 95% após execução EXECUCAO-QUICKSTART-MVP

---

## Workflow de Execução

### 1. Preparação (executor-terraform agent)

```bash
# Validar estrutura
bash scripts/validate-project-structure.sh

# Ler contexto
- docs/STATUS-2026-02-12.md (estado atual)
- docs/plan/EXECUCAO-QUICKSTART-MVP-2026-02-12.md (plano detalhado)
- docs/logbook/2026-02-12-quickstart-mvp-completion.md (timeline)
```

### 2. Consenso Agentes

```
[AWS] ☁️ AWS Specialist: Avaliar impacto AWS (nodes, Lambda, EventBridge)
[TF] 🌱 Terraform Specialist: Validar módulos, state, idempotência
[Obs] 📊 Observability: Validar Grafana, Loki, Tempo, Prometheus
[FinOps] 💰 FinOps: Validar savings, dashboards, automation
[Perf] 🔬 Performance: Validar resource requests, HPA ready
```

### 3. Execução com AML

```bash
# Task#1 exemplo
terraform apply ... > /tmp/tf-apply.log 2>&1 &
TF_PID=$!

# AML Loop (ciclo 15s)
while kill -0 $TF_PID; do
  sleep 15
  tail -10 /tmp/tf-apply.log
  kubectl get pods -n gitlab-staging
  kubectl get events --sort-by='.lastTimestamp' | tail -5
done
```

### 4. STOP-AND-FIX (se problema detectado)

```
1. PARAR execução
2. CTX-COMPACT (salvar snapshot, reduzir contexto)
3. Análise paralela agentes (AWS + TF + Obs simultâneos)
4. Fix definitivo (causa raiz)
5. DocSync (risks.md + logbook)
6. CTX-RESTORE + freshness check
7. RESUME execução
```

### 5. DocSync (obrigatório pós-task)

```markdown
[HH:MM:SS] DocSync | Orq | architecture.md, costs.md, logbook | ✅
```

---

## Referências

- **Executor Pattern**: [../prompts/executor-terraform.md](../prompts/executor-terraform.md)
- **Status Atual**: [../STATUS-2026-02-12.md](../STATUS-2026-02-12.md)
- **Logbook**: [../logbook/2026-02-12-quickstart-mvp-completion.md](../logbook/2026-02-12-quickstart-mvp-completion.md)
- **Quickstart Source**: [quickstart/aws-eks-gitlab-quickstart-REAL.md](quickstart/aws-eks-gitlab-quickstart-REAL.md)

---

**Criado**: 2026-02-12 14:35 BRT
**Última Atualização**: 2026-02-12 14:35 BRT
