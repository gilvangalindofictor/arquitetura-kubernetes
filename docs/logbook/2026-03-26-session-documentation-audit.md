# Logbook — Sessao 2026-03-26

**Data**: 2026-03-26
**Tipo**: Health Audit + ETL Compliance + IaC Conformance Audit
**Cluster**: k8s-platform-prod (EKS v1.34.2-eks-ecaa3a6, 14 nodes, 305 pods)
**Account**: 891377105802 (us-east-1)

---

## Resumo Executivo

Sessao completa com 3 demandas principais executadas em paralelo:

| Demanda | Score Inicial | Score Final | GAPs Resolvidos |
|---------|--------------|-------------|-----------------|
| Health Audit (D4) | N/A | 8/10 | 6 P1 |
| ETL Compliance (D5) | Hatch 62%, VemSoft 82% | Hatch 100%, VemSoft 100% | 10+ |
| IaC Conformance (D7) | N/A | 61/100 (target 78) | 26/27 codificados |

---

## 1. Health Audit (D4)

**Score**: 8/10 | 14 nodes Ready | 305 pods | 54/54 ExternalSecrets Synced

### P1 Issues Encontrados e Resolvidos

| GAP | Descricao | Status |
|-----|-----------|--------|
| HEALTH-001 | Prometheus memory — node system 99% | CODIFICADO (move to workloads + retention 7d) |
| HEALTH-002 | Keycloak ingress prod placeholder host | CODIFICADO (fix host + cert ARN) |
| HEALTH-003 | ALB group prod poisoned por Keycloak | CODIFICADO (ingress_group_name desbloqueado) |
| HEALTH-004 | OTel HPA scaleTargetRef errado | PATCHED + IaC fix (modules/opentelemetry-collector/hpa.yaml) |
| HEALTH-005 | Keycloak backup CronJob prod nunca executou | Root cause: password drift (Vault v2 != DB). startingDeadlineSeconds codificado. FIX PENDENTE: reset admin password |
| HEALTH-006 | Promtail prod ausente | CODIFICADO (prod/promtail.tf) |

### Arquivos Criados/Modificados (Health)

- `docs/demands/2026-03-26-health-audit-report.md` (CRIADO)
- `docs/demands/2026-03-26-health-gaps-p1-fix.md` (CRIADO)
- `environments/prod/main.tf` (Keycloak cert ARN + ingress_group_name)
- `modules/opentelemetry-collector/hpa.yaml` (scaleTargetRef fix)
- `modules/kube-prometheus-stack/` (Prometheus move to workloads + right-size)
- `environments/prod/promtail.tf` (CRIADO)

---

## 2. ETL Compliance (D5)

### Hatch ETL: 62% -> 76% -> 100% (21/21 checks)

**Fixes aplicados:**
- Linkerd injection (annotation, nao label) + rollout restart — 3/3 pods 2/2
- 3 NetworkPolicies (default-deny-ingress, allow-same-namespace, allow-ingress-controller)
- 2 HPA (api-gateway min=1/max=3/cpu=70%, web min=1/max=2/cpu=80%)
- 2 PDB (api-gateway minAvailable=1, web minAvailable=1)
- 5 novos deployments codificados: worker, dashboard, poller, anexos-service, prometheus-exporter
- Commands corrigidos (PYTHONPATH, Streamlit port 8501, entrypoints reais)
- securityContext PSA-restricted em todos os 6 workloads
- GAP-HATCH-IMAGE-001: CrashLoop por entrypoints corrigido
- 6 ExternalSecrets consolidados em TF

### VemSoft ETL: 82% -> 91% -> 100% (11/11 checks)

**Fixes aplicados:**
- Linkerd injection (label + annotation + rollout restart) — 1/1 pod 2/2
- HPA (min=1, max=2, cpu=70%)
- PDB (minAvailable=1)
- harbor-registry-secret-sync e RDS ExternalName documentados

### IaC Coverage

- 27 kubectl_manifest resources em staging/main.tf (linhas 3068-4300+)

### Arquivos Criados/Modificados (ETL)

- `docs/demands/2026-03-26-etl-staging-compliance-report.md` (CRIADO)
- `environments/staging/main.tf` (27 kubectl_manifest resources: NetworkPolicies, HPAs, PDBs, ExternalSecrets, deployments)

---

## 3. IaC Conformance Audit (D7)

**Score**: 61/100 (benchmark enterprise: 82/100)
**Score projetado pos-apply**: ~78/100
**GAPs**: 27 total (2 P0, 13 P1, 9 P2, 3 P3) — 26/27 CODIFICADOS

### GAPs Codificados (nao aplicados — terraform apply pendente)

| Arquivo TF | Conteudo |
|-----------|----------|
| `prod/main.tf` | RDS multi_az=true, Keycloak cert ARN + ingress_group_name |
| `modules/eks/main.tf` | EKS logging 5/5 tipos |
| `staging/network-policies.tf` + `prod/network-policies.tf` | 39 NetworkPolicies (13 ns x 3) |
| `staging/psa-labels.tf` + `prod/psa-labels.tf` | PSA labels 28 namespaces |
| `modules/vault-config/` | FIX-009 Phase 1 (path isolation, 4 HCL policies) |
| `staging/cluster-autoscaler-helm.tf` | CA helm release (import necessario) |
| `prod/kube-prometheus-stack-helm.tf` | kube-prom prod (import necessario) |
| `prod/argocd-applications.tf` | 4 Applications prod (Harbor, Keycloak, Obs, Vault) |
| `prod/backstage-prod.tf` | Modulo comentado (7 secrets pendentes) |
| `staging/dead-mans-switch.tf` + `prod/dead-mans-switch.tf` | Watchdog + DeadMansSwitch |
| `staging/hpa-platform.tf` + `prod/hpa-platform.tf` | 9 HPAs platform |
| `modules/waf` | COUNT -> BLOCK staging |
| `prod/linkerd-mtls.tf` | 4 namespaces adicionados |
| `staging/spot-node-group.tf` | Node group Spot workloads |
| `staging/pdb-platform.tf` + `prod/pdb-platform.tf` | 16 PDBs |
| `staging/grafana-dashboards.tf` | 4 dashboards customizados |
| `prod/sonarqube-prod.tf` | SonarQube prod |
| `prod/nat-multi-az.tf` | Segundo NAT Gateway |
| `prod/budget-alerts.tf` | AWS Budget $500/mes |
| `staging/kyverno-policy-exceptions.tf` | Exclude prometheus-operated |

### GAP Bloqueado

- GAP-CONF-023 (VPN): Bloqueado por IP FortiGate pendente

### Arquivos Criados/Modificados (Conformance)

- `docs/demands/2026-03-26-iac-conformance-audit.md` (CRIADO)
- `docs/demands/2026-03-26-gap-conf-p2-resolution.md` (CRIADO)
- Todos os arquivos .tf listados acima

---

## 4. Fixes Definitivos (Atualizacao da D3 de 2026-03-25)

### Status Atualizado dos FIX-*

| FIX | Status Anterior | Status 2026-03-26 |
|-----|----------------|-------------------|
| FIX-001 | PENDENTE | RESOLVIDO (2026-03-26 — novo root token gerado) |
| FIX-002 | PENDENTE (dep FIX-001) | PENDENTE (CSS SA staging->prod) |
| FIX-003 | PENDENTE (dep FIX-001) | PENDENTE (password drift confirmado por HEALTH-005) |
| FIX-004 | CODIFICADO | CODIFICADO (apply pendente) |
| FIX-005 | CODIFICADO | CODIFICADO (apply pendente) |
| FIX-006 | CODIFICADO | CODIFICADO (apply pendente) |
| FIX-007 | CODIFICADO | CODIFICADO (apply pendente) |
| FIX-008 | CODIFICADO | CODIFICADO (apply pendente) |
| FIX-009 | DOCUMENTADO | CODIFICADO Phase 1 (vault-config policies HCL) |
| FIX-010 | JA RESOLVIDO | JA RESOLVIDO |
| FIX-011 | DOCUMENTADO | RESOLVIDO (2026-03-27 max_size=5) |
| FIX-012 | GAP DOCUMENTADO | RESOLVIDO (schedules cobrem *) |
| FIX-013 | PENDENTE | PARCIALMENTE ATIVO (30+ pods Running) |

---

## 5. Pendencias para Proxima Sessao

### Terraform Apply (prioridade)
1. `terraform plan` completo staging + prod (validar todas as mudancas codificadas)
2. Apply sequencial P0: RDS multi_az=true (janela manutencao)
3. Apply P1: Network Policies, PSA labels, EKS logging, HPAs, PDBs, Dead Man's Switch
4. Import: Cluster Autoscaler helm + kube-prometheus-stack helm

### Acoes Manuais
1. FIX-003: Reset Keycloak admin password prod (password drift Vault v2 != DB)
2. FIX-002: CSS vault-backend-prod SA migration
3. Backstage prod: 7 secrets Vault pendentes antes de uncomment modulo

### Decisoes Pendentes
1. VPN: IP FortiGate para GAP-CONF-023
2. Savings Plans: Compute 1yr No-Upfront decision
3. FIX-013: Resource planning para full prod-observability activation

---

## 6. Credenciais

### Alteracoes nesta sessao
- Vault prod root token: `VAULT_TOKEN_PROD_REDACTED` (gerado 2026-03-26 via generate-root)
- HEALTH-005 confirmou password drift: Vault `secret/keycloak/postgresql` v2 != DB password real. Reset pendente.

### Sem alteracao
- Todas as demais credenciais staging/prod permanecem inalteradas conforme CREDENTIALS.md
