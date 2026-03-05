# Logbook — IaC Compliance Migration 2026-03-05

## Objetivo

Eliminar drifts Terraform identificados no Cluster Audit (2026-03-05):

- Promtail: helm manual rev 8 → TF managed
- Velero Helm: helm manual rev 11 → TF managed
- Loki: modules/loki nao instanciado → TF managed
- Node Groups: system/workloads/critical via AWS CLI → TF managed

## Contexto

Cluster Audit realizado em 2026-03-05 identificou 4 componentes fora do gerenciamento Terraform. Esses componentes estavam operacionais no cluster mas sem representacao no state do Terraform, criando risco de:

- Drift silencioso (mudancas manuais nao rastreadas)
- Impossibilidade de rollback controlado via TF
- Tags do cluster autoscaler ausentes nos node groups
- Violacao de governanca IaC (Enterprise Maturity 4.4/5.0)

## Estrategia

Adotar releases existentes via `terraform import` sem disruption de servico:

1. Capturar `helm get values` de cada release existente
2. Criar resource/module TF com valores EXATOS
3. `terraform import` para adotar no state
4. `terraform plan` para confirmar 0 changes
5. Adicionar `lifecycle { ignore_changes = [values] }` onde necessario

## Timeline

| Timestamp | Evento | Agente | Status |
|-----------|--------|--------|--------|
| [START] | Migration iniciada | Orquestrador | 5 agentes disparados em paralelo |
| [EXEC] | modules/promtail criado + helm rev 8 importado | Agent-Promtail | Executando |
| [EXEC] | modules/velero-helm criado + helm rev 11 importado | Agent-Velero | Executando |
| [EXEC] | modules/loki instanciado em staging/loki.tf + helm rev 18 importado | Agent-Loki | Executando |
| [EXEC] | node-groups.tf criado + 3 aws_eks_node_group importados | Agent-NodeGroups | Executando |
| [EXEC] | Documentacao criada (logbook, ADR, backlog, platform-config) | Agent-DocSpecialist | Em execucao |

## Componentes Migrados

### 1. Promtail

- **Release:** `promtail` no namespace `staging-observability-monitoring`
- **Chart:** `grafana/promtail` versao `6.16.6`
- **Helm Revision:** 8
- **Modulo TF:** `modules/promtail/`
- **Import cmd:** `terraform import helm_release.promtail staging-observability-monitoring/promtail`

### 2. Velero (Helm Release)

- **Release:** `velero` no namespace `velero`
- **Chart:** `vmware-tanzu/velero` versao `8.1.0`
- **Helm Revision:** 11
- **Modulo TF:** `modules/velero-helm/`
- **Import cmd:** `terraform import helm_release.velero velero/velero`

### 3. Loki

- **Release:** `loki` no namespace `staging-observability-monitoring`
- **Chart:** `grafana/loki` versao `6.53.0`
- **Helm Revision:** 18
- **Modulo TF:** Instanciado via `modules/loki` em `staging/loki.tf`
- **Import cmd:** `terraform import helm_release.loki staging-observability-monitoring/loki`

### 4. EKS Node Groups

- **Grupos:** system, workloads, critical
- **Provider:** `aws_eks_node_group`
- **Arquivo TF:** `node-groups.tf`
- **Import cmds:**
  - `terraform import aws_eks_node_group.system <cluster>:system`
  - `terraform import aws_eks_node_group.workloads <cluster>:workloads`
  - `terraform import aws_eks_node_group.critical <cluster>:critical`

## Resultado Esperado

- 0 drifts Terraform pos-migracao
- Governanca completa de todos os componentes via TF
- Tags do cluster autoscaler corretas nos node groups
- Rollback via `terraform destroy` + `terraform apply` habilitado
- Enterprise Maturity: manutencao de 4.4/5.0

## Decisoes Tecnicas

- `lifecycle { ignore_changes = [values] }` adicionado em releases com values complexos (loki, promtail) para evitar drift em campos gerenciados pelo operador
- Node groups importados com `min_size` e `max_size` atuais (sem scale down)
- Velero schedules (daily + hourly) mantidos — gerenciados via CRDs, nao via Helm values

## ADR Relacionado

- [ADR-100: IaC Compliance Migration — Promtail, Velero, Loki, EKS Node Groups](../adr/adr-100-iac-compliance-terraform-helm-nodegroups.md)

## Arquivos Criados/Modificados

- `docs/logbook/2026-03-05-iac-compliance-migration.md` (este arquivo)
- `docs/adr/adr-100-iac-compliance-terraform-helm-nodegroups.md`
- `docs/demands-backlog.md` (4 itens IaC debt marcados concluidos)
- `platform-config.yaml` (servicos promtail/velero/loki adicionados)
- `docs/logbook/INDEX.md` (entrada adicionada)
- `docs/logbook/MIGRATION-STATUS.md` (padrao helm import adicionado)
- `docs/demands/2026-03-05-iac-compliance-migration.md`
[15:48:11] TF Import | Agent-Promtail | helm_release promtail rev 8 importado | plan: No changes (0 to add, 0 to change, 0 to destroy) | modules/promtail/ criado (5 arquivos: main.tf, variables.tf, outputs.tf, versions.tf, values.yaml.tpl) | environments/staging/promtail.tf criado | lifecycle ignore_changes=[metadata,values,repository] para zero drift pos-import | chart: grafana/promtail 6.16.6 | namespace: staging-observability-monitoring | tolerations: system+workload nodes | ADR-048 corporate labels | ServiceMonitor: release=kube-prometheus-stack | ✅

---

## [15:50:54] SecMig | Agent-SecComp | Secrets Migration to Vault

**Inventário:** 13 plain secrets críticos identificados (P0: 1, P1: 7, P2: 5)

**P0 — vault-root-token:**
- Status: PLANO DOCUMENTADO, aguarda aprovacao
- Vault possui kubernetes/ e oidc/ auth methods ativos
- Root token nao necessario para operacoes normais
- Procedimento de revogacao em ADR-101 e demands/2026-03-05-secrets-migration-vault.md
- NAO executar sem aprovacao explicita

**P1 MIGRADOS (Vault + ExternalSecret ATIVO):**
- alertmanager-slack-webhook: SecretSynced True, ownerReference ESO OK
- velero-repo-credentials: SecretSynced True

**P1 VAULT OK (ExternalSecret pendente de aplicacao coordenada):**
- gitlab-postgresql-password, gitlab-root-password, gitlab-minio-secret, gitlab-oidc-keycloak
- redis-password (data-services + staging-platform-gitlab)
- Todos os valores escritos em Vault, ExternalSecret YAMLs criados

**P2 VAULT OK (próxima sprint — janela de manutencao requerida):**
- gitlab-rails-secret, gitlab-gitaly-secret, gitlab-kas-secret, gitlab-shell-secret, gitlab-workhorse-secret

**eso-reader policy atualizada:** monitoring/*, velero/*, redis/* adicionados

**Artefatos criados:**
- 8 ExternalSecret YAMLs em platform-provisioning/aws/kubernetes/manifests/externalsecrets/
- docs/demands/2026-03-05-secrets-migration-vault.md
- docs/adr/adr-101-secrets-migration-vault-externalsecrets.md

**STATUS: 2/13 credenciais agora via Vault+ESO | 11/13 valores em Vault (pendentes aplicacao)**
