# Logbook — GAP-012 Phase 2: Artifacts Created

**Date**: 2026-03-04
**Session**: Backup & DR Specialist + Terraform Specialist
**Demanda**: GAP-012 Phase 2 — DR Multi-Region (VPC + Schedules + Dashboard)
**Branch**: main
**Executor**: Claude Code (Agente DR Specialist)

---

## Contexto

GAP-012 Phase 1 foi deployado em 2026-02-26 com S3 CRR us-east-1 to us-west-2 funcionando.
Phase 2 estava bloqueada pela ausência de:

1. VPC provisionada em us-west-2 (necessária para RDS read replica)
2. BackupStorageLocations adicionais no Velero apontando para bucket replica
3. Schedules de backup (daily full + hourly incremental)
4. Dashboard de monitoramento de replicacao
5. ADR-078 desatualizado (sem status Phase 1/Phase 2)

Esta sessao criou todos os artefatos necessarios para desbloquear o deploy de Phase 2.

---

## Timeline

| Hora (UTC) | Acao | Resultado |
| ---------- | ---- | --------- |
| 00:00 | Leitura de arquivos existentes (velero-dr module, ADR-078, staging/main.tf) | Contexto completo carregado |
| 00:05 | Criacao do modulo vpc-dr (4 arquivos TF) | `modules/vpc-dr/` pronto |
| 00:12 | Criacao dos manifests Velero (4 arquivos) | `domains/backup-dr/infra/velero/` pronto |
| 00:18 | Criacao do Grafana dashboard ConfigMap (DR Multi-Region Status) | 5 panels, 2 datasources |
| 00:24 | Atualizacao ADR-078 (Phase 1 status + Phase 2 planning + deploy sequence) | ADR atualizado |
| 00:28 | Criacao deste logbook | Sessao documentada |

---

## Artefatos Criados

### Tarefa 2 — Modulo Terraform VPC DR (us-west-2)

**Diretorio**: `platform-provisioning/aws/kubernetes/terraform/modules/vpc-dr/`

| Arquivo | Linhas | Descricao |
| ------- | ------ | --------- |
| `main.tf` | ~130 | VPC 10.1.0.0/16, 2 subnets RDS, DB subnet group, SG PostgreSQL, route table |
| `variables.tf` | ~80 | vpc_cidr, rds_subnet_cidr_az_a/b, db_subnet_group_name, dr_region, tags |
| `outputs.tf` | ~65 | vpc_id, db_subnet_group_name, private_subnet_ids, rds_security_group_id |
| `versions.tf` | ~25 | terraform >= 1.5, aws ~> 5.0, alias aws.dr |

**Recursos criados pelo modulo**:

- `aws_vpc.dr` — VPC 10.1.0.0/16 (provider aws.dr)
- `aws_subnet.rds_a` — 10.1.128.0/20 em us-west-2a
- `aws_subnet.rds_b` — 10.1.144.0/20 em us-west-2b
- `aws_db_subnet_group.dr` — `k8s-platform-dr-db-subnet-group`
- `aws_security_group.rds_dr` — PostgreSQL (5432) apenas do VPC CIDR
- `aws_route_table.private_dr` + 2 associacoes de subnet

**Tags padrao**:

```hcl
{
  Project     = "k8s-platform"
  ManagedBy   = "terraform"
  Environment = "production"
  Purpose     = "dr-region"
  Module      = "vpc-dr"
  GAP         = "GAP-012"
}
```

**Como adicionar ao staging/main.tf**:

```hcl
module "vpc_dr_staging" {
  source = "../../modules/vpc-dr"
  providers = {
    aws.dr = aws.us-west-2
  }

  environment          = local.environment
  name_prefix          = local.cluster_name
  dr_region            = "us-west-2"
  vpc_cidr             = "10.1.0.0/16"
  rds_subnet_cidr_az_a = "10.1.128.0/20"
  rds_subnet_cidr_az_b = "10.1.144.0/20"
  db_subnet_group_name = "k8s-platform-dr-db-subnet-group"
  tags                 = local.common_tags
}
```

O provider `aws.us-west-2` ja existe em `environments/staging/main.tf` (linha 93).

---

### Tarefa 3 — Manifests Velero (Backup-DR Domain)

**Diretorio**: `domains/backup-dr/infra/velero/`

| Arquivo | Tipo | Descricao |
| ------- | ---- | --------- |
| `backup-storage-location-dr.yaml` | BackupStorageLocation | BSL us-west-2, ReadOnly, bucket replica CRR |
| `schedule-daily-full.yaml` | Schedule (Velero CRD) | 0 2 * * * UTC, TTL 720h, snapshotVolumes: true |
| `schedule-hourly-incremental.yaml` | Schedule (Velero CRD) | 0 * * * * UTC, TTL 24h, snapshotVolumes: false |
| `velero-values-dr-update.yaml` | Helm values patch | 2 BSLs (primary ReadWrite + DR ReadOnly) + IRSA annotation |

**Decisoes de design**:

- `accessMode: ReadOnly` no BSL dr — Velero lista/restaura do replica mas NAO escreve
  (gravacoes ocorrem apenas no BSL primary us-east-1; CRR faz a replicacao automaticamente)
- `snapshotVolumes: false` no schedule horario — apenas metadados K8s para minimizar custo
  (snapshots EBS apenas no schedule diario)
- `useOwnerReferencesInBackup: false` — evita garbage collection inadvertido em restore
- Schedules excluem `kube-system`, `kube-public`, `kube-node-lease` e `events`

**Comando de deploy**:

```bash
# BSL primeiro (Velero precisa sincronizar antes dos schedules)
kubectl apply -f domains/backup-dr/infra/velero/backup-storage-location-dr.yaml
sleep 30
velero backup-location get  # Aguardar "Available" para dr-us-west-2

# Schedules
kubectl apply -f domains/backup-dr/infra/velero/schedule-daily-full.yaml
kubectl apply -f domains/backup-dr/infra/velero/schedule-hourly-incremental.yaml
velero schedule get

# Helm upgrade (adiciona BSL no Velero deployment)
helm upgrade velero vmware-tanzu/velero \
  --namespace velero \
  --reuse-values \
  --values domains/backup-dr/infra/velero/velero-values-dr-update.yaml
```

---

### Tarefa 4 — Grafana Dashboard ConfigMap

**Arquivo**: `domains/observability/infra/grafana/dr-replication-dashboard-configmap.yaml`

**Namespace**: `staging-observability-monitoring`
**Labels**: `grafana_dashboard: "1"`, `app.kubernetes.io/part-of: kube-prometheus-stack`

**Panels**:

| Panel | Tipo | Datasource | Metrica |
| ----- | ---- | ---------- | ------- |
| 1. Pending Replication Operations | Stat | CloudWatch | `AWS/S3 ReplicationPendingOperations` (avg) |
| 2. Bytes Pending Replication | Stat | CloudWatch | `AWS/S3 BytesPendingReplication` (max) |
| 3. Failed Replication Operations (1h) | Stat | CloudWatch | `AWS/S3 OperationsFailedReplication` (sum) |
| 4. RDS Replica Lag — Gauge | Gauge | CloudWatch | `AWS/RDS ReplicaLag` us-west-2 |
| 5. RDS Replica Lag — Trend | Timeseries | CloudWatch | `AWS/RDS ReplicaLag` us-west-2 |
| 6. Time Since Last Successful Backup | Stat | Prometheus | `time() - velero_backup_last_successful_timestamp` |
| 7. Backup Failures (24h) | Stat | Prometheus | `increase(velero_backup_failure_total[24h])` |

**Thresholds**:

- Pending Operations: verde < 50, amarelo 50-200, vermelho > 200
- Bytes Pending: verde < 500 MB, amarelo 500 MB - 1 GB, vermelho > 1 GB (alinha com alarme CW)
- Failed Operations: verde = 0, vermelho >= 1
- RDS Lag: verde < 30s, amarelo 30-120s, vermelho > 120s
- Time Since Last Backup: verde < 90000s (25h), amarelo ate 172800s (48h), vermelho > 48h

**Deploy**:

```bash
kubectl apply -f domains/observability/infra/grafana/dr-replication-dashboard-configmap.yaml
# Dashboard aparece em Grafana em ~30s (sidecar auto-import)
```

---

### Tarefa 5 — ADR-078 Atualizado

**Arquivo**: `docs/adr/adr-078-velero-backup-dr-implementation.md`

**Mudancas**:

- Status atualizado: `IMPLEMENTADO — Phase 1 DEPLOYADO | Phase 2 PLANEJADO`
- Secao `Implementation Status (2026-03-04)` adicionada no topo
- Tabela Phase 1: 7 itens todos com status ATIVO/CRIADO
- Tabela Phase 2: 7 itens com status PRONTO PARA DEPLOY ou BLOQUEADO
- Deploy sequence completa com comandos bash e exemplo HCL para staging/main.tf
- Related ADRs atualizado (adicionado ADR-090)

---

## Status por Item

| Item | Status | Gate |
| ---- | ------ | ---- |
| VPC DR module (TF) | PRONTO — aguardando terraform apply | DevOps + aprovacao |
| BSL dr-us-west-2 | PRONTO — aguardando VPC DR deploy | Depends on VPC |
| Schedule daily-full | PRONTO — pode aplicar independente do VPC | Nenhum |
| Schedule hourly-incremental | PRONTO — pode aplicar independente do VPC | Nenhum |
| Velero Helm values patch | PRONTO — requer IRSA role existente (ja existe) | Nenhum |
| Grafana dashboard | PRONTO — pode aplicar imediatamente | Nenhum (CW datasource configurado) |
| RDS Replica (count=1) | BLOQUEADO — aguarda VPC DR + aprovacao liderança | Lideranca + VPC deploy |

---

## Proximos Passos (Deploy Manual)

### Immediato (sem gate):

```bash
# 1. Grafana Dashboard (sem dependencias)
kubectl apply -f domains/observability/infra/grafana/dr-replication-dashboard-configmap.yaml

# 2. Velero schedules (sem dependencias de VPC)
kubectl apply -f domains/backup-dr/infra/velero/schedule-daily-full.yaml
kubectl apply -f domains/backup-dr/infra/velero/schedule-hourly-incremental.yaml

# 3. Velero Helm upgrade (BSL dr-us-west-2 ficara em "Unavailable" ate o VPC existir)
helm upgrade velero vmware-tanzu/velero \
  --namespace velero \
  --reuse-values \
  --values domains/backup-dr/infra/velero/velero-values-dr-update.yaml
```

### Apos aprovacao VPC DR:

```bash
# 4. Terraform — adicionar module vpc_dr_staging em staging/main.tf
terraform plan -target=module.vpc_dr_staging
terraform apply -target=module.vpc_dr_staging

# 5. BSL DR (agora o bucket us-west-2 esta acessivel e o BSL ficara Available)
kubectl apply -f domains/backup-dr/infra/velero/backup-storage-location-dr.yaml
velero backup-location get  # Aguardar status Available

# 6. (Gate lideranca) Ativar RDS replica
# No environments/staging/main.tf, alterar count de 0 para 1 no module rds_replica_staging
terraform plan -target=module.rds_replica_staging
terraform apply -target=module.rds_replica_staging
```

---

## Riscos Identificados

| Risco | Probabilidade | Impacto | Mitigacao |
| ----- | ------------- | ------- | --------- |
| BSL dr-us-west-2 fica `Unavailable` se VPC nao existir | Alta | Baixo (apenas ReadOnly) | Esperado; BSL ficara Available apos VPC deploy |
| RDS Replica Lag > 120s em pico de escrita | Media | Medio | Monitorar via dashboard Panel 4/5; alertar se > 120s |
| Custo adicional S3 CRR RTC (~$0.015/GB) | Media | Baixo | Ja projetado em GAP-012 Phase 1 cost analysis |
| Schedule diario com EBS snapshot aumenta custo AWS | Media | Medio | Lifecycle da snapshot gerida pelo Velero TTL (720h) |
| VPC CIDR 10.1.0.0/16 conflito futuro | Baixa | Alto | CIDR reservado e documentado; nao usar em prod sem revisao |

---

## Artefatos por Responsabilidade

| Responsavel | Acao |
| ----------- | ---- |
| DevOps (deploy imediato) | `kubectl apply` schedules + dashboard + helm upgrade |
| DevOps (apos aprovacao) | `terraform apply` vpc-dr module |
| Lideranca | Gate para ativar RDS replica (custo + SLA) |
| Platform Team | Validar BSL status Available apos VPC deploy |
| Platform Team | Verificar primeiro backup daily-full-backup (proximo 02:00 UTC) |

---

## Referencias

- GAP-012 Phase 1 Commit: referencia nos commits anteriores (2026-02-26)
- ADR-078: `docs/adr/adr-078-velero-backup-dr-implementation.md`
- ADR-090: `docs/adr/adr-090-dr-multi-region-strategy.md`
- Modulo velero-dr: `platform-provisioning/aws/kubernetes/terraform/modules/velero-dr/`
- Modulo rds-replica: `platform-provisioning/aws/kubernetes/terraform/modules/rds-replica/`
- Modulo vpc-dr (NOVO): `platform-provisioning/aws/kubernetes/terraform/modules/vpc-dr/`
