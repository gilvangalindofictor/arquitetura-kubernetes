# Logbook: FinOps Gaps Analysis — 2026-03-10

**Data:** 2026-03-10
**Tipo:** Analise FinOps / Revisao de Savings
**Status:** CONCLUIDO (analise) + TF fix em andamento (CloudWatch)
**Componentes:** FinOps Automation, ADR-094, CloudWatch Logs, EKS

---

## 1. Resumo Executivo

Dois gaps de savings identificados e analisados nesta sessao:

| Gap | Valor | Natureza | Decisao |
|-----|-------|----------|---------|
| FinOps Automation: R$ 13.597 → R$ 12.800 real | -R$ 797/ano | INTENCIONAL (ADR-094) | Manter + documentar |
| CloudWatch Logs: 5 log types vs 3 recomendados | -R$ 720-1.080/ano potential | CORRIGIVEL | TF fix em andamento |

---

## 2. Gap 1 — FinOps Automation: Savings Ajustados

### 2.1 Divergencia Identificada

| Metrica | Valor Documentado | Valor Real Confirmado | Diferenca |
|---------|------------------|-----------------------|-----------|
| FinOps Automation FASE 2 | R$ 13.597/ano | ~R$ 12.800/ano | -R$ 797/ano |

### 2.2 Root Cause: ADR-094 — Node Group Protection (INTENCIONAL)

A diferenca nao e um bug nem uma falha — e uma **decisao arquitetural documentada**.

**ADR-094** define que os node groups `system` e `critical` sao **excluidos do shutdown automatico** por razoes de confiabilidade:

```hcl
# staging/main.tf — FinOps Automation module
excluded_node_groups = ["system", "critical"]
```

**Impacto financeiro da exclusao:**
- 4 nos minimos mantidos ativos nos finais de semana (2 system + 2 critical, `min_size=2` cada)
- Custo weekend residual: ~$40-45/mes (4 nos × 48h × custo EC2)
- Saving real vs saving teorico (shutdown 100%): diferenca de ~R$ 797/ano

### 2.3 Justificativa da Exclusao (ADR-094)

| Razao | Detalhamento |
|-------|-------------|
| Vault HA | Vault precisa de nos `critical` para quorum — shutdown causaria perda de unseal |
| ESO + cert-manager | Dependem de nos `system` — sem eles, secrets nao sincronizam |
| Startup confiavel | Nos `system`+`critical` precisam estar prontos antes de `workloads` iniciarem |
| RTO | Startup de 0 nos leva 8-12 min vs 3-4 min com nos base ativos |

### 2.4 Decisao

**MANTER como esta.** O saving de R$ 12.800/ano e o valor correto considerando a protecao arquitetural. O valor R$ 13.597 era uma estimativa pre-ADR-094.

**Acao de documentacao:** Atualizar `finops-status-2026-03-10.md` com nota de savings revisados.

---

## 3. Gap 2 — CloudWatch Logs: Analise de Custos

### 3.1 Contexto

CloudWatch esta custando ~$34/mes vs $21 esperado (desvio de +$13/mes = +R$ 936/ano).

### 3.2 Root Cause Confirmado

EKS cluster com **5 log types ativos** quando apenas **3 sao necessarios**:

| Log Type | Status Atual | Recomendado | Justificativa |
|----------|-------------|-------------|---------------|
| `api` | ATIVO | MANTER | Auditoria e troubleshooting critico |
| `audit` | ATIVO | MANTER | Compliance + security events |
| `authenticator` | ATIVO | MANTER | IAM/RBAC debug |
| `controllerManager` | ATIVO | **REMOVER** | Baixo valor operacional, alto volume |
| `scheduler` | ATIVO | **REMOVER** | Baixo valor operacional, alto volume |

**Volume estimado por log type:**
- `controllerManager` + `scheduler`: ~60-70% do volume total EKS logs
- Reducao esperada: 60-70% do custo CloudWatch EKS logs

### 3.3 Acoes Identificadas

| Acao | Saving Estimado | Status |
|------|----------------|--------|
| `enabled_cluster_log_types`: 5→3 (remover controllerManager+scheduler) | R$ 480-720/ano | TF fix em andamento |
| Retention 30d→7d nos log groups EKS | R$ 240-360/ano | TF fix em andamento |
| Remover custom metrics desnecessarios (se existirem) | R$ 0-100/ano | A verificar |
| **Total potencial** | **R$ 720-1.080/ano** | |

### 3.4 Fix Terraform em Andamento

```hcl
# terraform/modules/eks/main.tf (ou equivalente)
# ANTES:
enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

# DEPOIS:
enabled_cluster_log_types = ["api", "audit", "authenticator"]
```

```hcl
# Log group retention:
# ANTES: retention_in_days = 30
# DEPOIS: retention_in_days = 7
```

**Gate de conclusao:** `terraform plan` retornando "No changes" apos apply + validacao custo CloudWatch na proxima semana.

---

## 4. Impacto no Savings Total

### 4.1 Revisao da Tabela de Savings (2026-03-10)

| Item | Savings Anterior | Savings Revisado | Nota |
|------|-----------------|-----------------|------|
| FinOps FASE 2 Automation | R$ 13.597/ano | R$ 12.800/ano | ADR-094: system+critical excluidos |
| CloudWatch Logs | R$ 54/ano (retention apenas) | R$ 54 + R$ 720-1.080 potencial | Fix TF em andamento |
| **Impacto no total** | **R$ 58.258/ano** | **R$ 57.461/ano realizados + R$ 720-1.080 potencial** | |

**Nota:** O ajuste de -R$ 797 (FinOps Automation) e compensado parcialmente pelo potencial CloudWatch (+R$ 720-1.080). Net impact: -R$ 77 a +R$ 283.

### 4.2 Realizacao vs Meta

| Metrica | Valor |
|---------|-------|
| Savings realizados (ajustado) | R$ 57.461/ano |
| Meta original | R$ 62.000/ano |
| Realizacao vs meta | 92.7% |
| CloudWatch potencial adicional | R$ 720-1.080/ano |
| Savings pos-CloudWatch fix | R$ 58.181-58.541/ano (93.8-94.4%) |

---

## 5. Proximos Passos

| Acao | Responsavel | Prazo | Status |
|------|------------|-------|--------|
| Aplicar TF fix `enabled_cluster_log_types` 5→3 | TF Specialist | 2026-03-10 | EM ANDAMENTO |
| Aplicar TF fix retention 30d→7d | TF Specialist | 2026-03-10 | EM ANDAMENTO |
| `terraform plan` → "No changes" validacao | TF Specialist | Pos-apply | PENDENTE |
| Verificar custo CloudWatch no Cost Explorer | FinOps | 2026-03-17 | PENDENTE |
| Atualizar ADR-094 com nota de savings ajustados | Doc Specialist | 2026-03-10 | FEITO (este logbook) |
| Validar execucoes FinOps Automation (logs Lambda) | FinOps | 2026-03-10 | PENDENTE |

---

## 6. Artefatos Relacionados

| Artefato | Localizacao |
|----------|-------------|
| ADR-094 — Node Group Protection | `docs/adrs/ADR-094-*.md` (ou similar) |
| finops-status-2026-03-10.md | `docs/finops/finops-status-2026-03-10.md` |
| cloudwatch-cost-analysis-2026-03-10.md | `docs/finops/cloudwatch-cost-analysis-2026-03-10.md` |
| vpa-finops-automation-analysis-2026-03-10.md | `docs/finops/vpa-finops-automation-analysis-2026-03-10.md` |
| staging main.tf (excluded_node_groups) | `platform-provisioning/aws/kubernetes/terraform/staging/main.tf` |

---

**Preparado por:** Documentation Specialist
**Revisado por:** FinOps Team
**Proxima revisao:** 2026-03-17 (verificar custo CloudWatch pos-fix)
