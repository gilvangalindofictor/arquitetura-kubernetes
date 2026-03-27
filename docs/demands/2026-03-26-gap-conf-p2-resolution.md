# GAP-CONF P2/P3 Resolution — 2026-03-26

## Resumo

Resolucao de 9 GAPs de conformidade priorizados como P2/P3 pelo IaC Conformance Audit.

## Status: CODIFICADO (terraform apply pendente)

---

## GAP-CONF-016 (P2): EKS Cluster nao no TF state

- **Arquivo**: `staging/eks-cluster-import.tf`
- **Solucao**: Import block + resource `aws_eks_cluster.main` (comentado)
- **Procedimento**:
  1. Descomentar import block e resource em `eks-cluster-import.tf`
  2. `terraform plan` — verificar "will be imported"
  3. `terraform apply` — importa cluster para o state
  4. Remover `null_resource.eks_auth_mode_api_and_configmap` de `node-groups.tf`
  5. `terraform plan` — deve retornar "No changes"
- **Comando alternativo**: `terraform import aws_eks_cluster.main k8s-platform-prod`
- **Risco**: BAIXO (import nao altera infraestrutura)

---

## GAP-CONF-017 (P2): VPA sem ciclo de aplicacao

- **Arquivo**: `staging/vpa-apply-cycle.tf`
- **Solucao**: CronJob diario (08:00 UTC) que coleta recomendacoes VPA
- **Componentes criados**:
  - ConfigMap `vpa-collector-script` (shell script)
  - CronJob `vpa-recommendations-collector`
  - ServiceAccount + ClusterRole + ClusterRoleBinding (read-only)
- **Ciclo recomendado**:
  1. CronJob coleta recomendacoes diariamente
  2. Consultar: `kubectl get configmap vpa-recommendations -n staging-observability-monitoring`
  3. Ou: `kubectl logs job/vpa-recommendations-collector-<id> -n staging-observability-monitoring`
  4. Revisao semanal (segunda-feira)
  5. Aplicacao manual via `kubectl patch` ou PR no TF
- **NAO aplica automaticamente** — apenas reporta

---

## GAP-CONF-018 (P2): 100% On-Demand sem Spot

- **Arquivo**: `staging/spot-node-group.tf`
- **Solucao**: Node group `workloads-spot` com `capacity_type = "SPOT"`
- **Instance diversification**: t3.large, t3a.large, m5.large, m5a.large
- **Taint**: `capacity=spot:PreferNoSchedule` (soft preference)
- **Scaling**: desired=0, min=0, max=4 (conservador)
- **Economia estimada**: ~R$2.520/mes com 2 nodes Spot
- **NUNCA Spot em**: system, critical (ON_DEMAND obrigatorio)
- **Pre-requisito**: AWS Node Termination Handler (verificar se DaemonSet existe)

---

## GAP-CONF-019 (P2): PDB ausente na maioria dos workloads

- **Arquivos**: `staging/pdb-platform.tf`, `prod/pdb-platform.tf`
- **Solucao**: PDBs minAvailable=1 para todos os componentes criticos
- **Componentes staging**: ArgoCD (server, repo-server, app-controller), Keycloak, Harbor (core, registry), GitLab (webservice, sidekiq), Backstage
- **Componentes prod**: ArgoCD (server, repo-server, app-controller), Keycloak, Harbor (core, registry), Backstage (preventivo)
- **NOTA**: GitLab e shared (staging namespace) — PDB em staging cobre ambos

---

## GAP-CONF-020 (P2): Grafana dashboards customizados ausentes

- **Arquivo**: `staging/grafana-dashboards.tf`
- **Solucao**: ConfigMaps com label `grafana_dashboard: "1"` (auto-discovery pelo sidecar)
- **Dashboards criados**:
  1. **Harbor** — HTTP request rate, blob upload/download, project count, storage used
  2. **GitLab** — HTTP request rate, Sidekiq queue, CI pipeline duration, active sessions
  3. **Vault** — Seal status, token count, request rate, secret operations, HA active node
  4. **Keycloak** — Login events, failed logins, active sessions, token requests, JVM memory, response time
- **Namespace**: staging-observability-monitoring

---

## GAP-CONF-021 (P2): SonarQube prod nao deployado

- **Arquivo**: `prod/sonarqube-prod.tf`
- **Solucao**: Invocacao `module "sonarqube_prod"` usando modulo existente
- **BLOQUEADORES**:
  1. Database "sonarqube" deve existir no RDS prod
  2. Vault secret `secret/sonarqube/postgresql` deve estar populado
  3. SAML desabilitado (requer Keycloak prod realm)
- **Pre-apply**:
  1. `CREATE DATABASE sonarqube;` no RDS prod
  2. Vault KV: `vault kv put secret/sonarqube/postgresql password=... username=sonarqube host=<rds> port=5432 database=sonarqube`

---

## GAP-CONF-022 (P2): NAT Gateway Single-AZ

- **Arquivo**: `prod/nat-multi-az.tf`
- **Solucao**: Segundo NAT Gateway em us-east-1b (complementar ao existente em us-east-1a)
- **Componentes**: EIP + NAT Gateway
- **Custo adicional**: ~$40-50/mes
- **Staging**: permanece Single-AZ (custo aceitavel para non-prod)
- **Pos-apply**: Atualizar route table da subnet us-east-1b (manual ou via TF import)

---

## GAP-CONF-023 (P2): VPN inexistente

- **Arquivo**: `prod/vpn.tf` (ja existe, COMENTADO)
- **Status**: **BLOQUEADO** — IP do FortiGate nao disponivel
- **Parametros faltantes**:
  1. `customer_gateway_ip` — IP publico do FortiGate (campo X.X.X.X)
  2. `customer_gateway_asn` — BGP ASN (default 65000)
  3. `destination_cidrs` — CIDR exato da rede do escritorio (placeholder 10.100.0.0/16)
- **Acao necessaria**: Obter IP do FortiGate com a equipe de rede
- **Quando desbloqueado**: Descomentar module em vpn.tf + outputs + terraform apply
- **Nenhuma alteracao feita** — arquivo permanece como esta

---

## GAP-CONF-026 (P3): Budget alerts

- **Arquivo**: `prod/budget-alerts.tf`
- **Solucao**: AWS Budgets ($500/mes) com SNS notifications
- **Alertas**: 80% actual, 100% actual, 100% forecasted
- **Filtro**: Tag `Project=k8s-platform`
- **SNS**: Topic + email subscription (var.finops_alert_email)
- **Custo**: $0 (primeiros 2 budgets gratuitos)

---

## GAP-CONF-027 (P3): Kyverno policy spam

- **Arquivo**: `staging/kyverno-policy-exceptions.tf`
- **Solucao**: PolicyException excluindo `prometheus-operated` e `alertmanager-operated`
  da policy `validate-service-naming`
- **Escopo**: staging-observability-monitoring + prod-observability-monitoring
- **NOTA**: A policy validate-service-naming nao e gerenciada por TF (manual apply).
  PolicyException e a abordagem mais segura para nao causar drift.

---

## Arquivos Criados

| Arquivo | GAP | Ambiente |
|---------|-----|----------|
| `staging/eks-cluster-import.tf` | CONF-016 | staging |
| `staging/vpa-apply-cycle.tf` | CONF-017 | staging |
| `staging/spot-node-group.tf` | CONF-018 | staging |
| `staging/pdb-platform.tf` | CONF-019 | staging |
| `staging/grafana-dashboards.tf` | CONF-020 | staging |
| `staging/kyverno-policy-exceptions.tf` | CONF-027 | staging |
| `prod/pdb-platform.tf` | CONF-019 | prod |
| `prod/sonarqube-prod.tf` | CONF-021 | prod |
| `prod/nat-multi-az.tf` | CONF-022 | prod |
| `prod/budget-alerts.tf` | CONF-026 | prod |

## Nao Alterados

| Arquivo | GAP | Motivo |
|---------|-----|--------|
| `prod/vpn.tf` | CONF-023 | BLOQUEADO — IP FortiGate nao disponivel |

## Proximos Passos

1. `terraform plan` em staging — verificar resources criados
2. `terraform plan` em prod — verificar resources criados
3. Revisar plan outputs antes de apply
4. Obter IP FortiGate para desbloquear GAP-CONF-023
5. Criar database sonarqube no RDS prod para desbloquear GAP-CONF-021
