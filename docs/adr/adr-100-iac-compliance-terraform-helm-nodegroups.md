# ADR-100: IaC Compliance Migration — Promtail, Velero, Loki, EKS Node Groups

## Status

**Implementado** (2026-03-05)

## Contexto

Cluster Audit realizado em 2026-03-05 identificou 4 componentes operacionais no cluster EKS staging que estavam fora do gerenciamento Terraform:

| Componente | Situacao Pre-Migracao | Helm Revision | Risco |
|------------|----------------------|---------------|-------|
| Promtail | `helm install` manual | Rev 8 | Drift silencioso, sem rollback TF |
| Velero (helm) | `helm install` manual | Rev 11 | Drift silencioso, sem rollback TF |
| Loki | `modules/loki` criado mas nao instanciado | Rev 18 | Modulo orfao, release nao gerenciada |
| EKS Node Groups | Criados via AWS CLI / Console | N/A | Tags autoscaler ausentes, sem IaC |

O projeto opera no Enterprise Maturity level 4.4/5.0, exigindo que **100% dos componentes de infraestrutura sejam gerenciados via IaC**. A presenca desses componentes fora do state Terraform representa violacao direta desse principio.

### Problema Especifico por Componente

**Promtail:** Instalado manualmente durante fase de bootstrap do logging stack. Nunca foi adotado pelo Terraform. Helm values customizados (tolerations, extraVolumes, daemonset config) existem apenas no cluster.

**Velero:** Instalado manualmente para atender urgencia de DR. O modulo Terraform `modules/velero-helm/` foi criado posteriormente mas o import nao foi executado. Schedules (daily + hourly) gerenciados via CRDs separadas.

**Loki:** O modulo `modules/loki` foi criado e funcional, mas a instanciacao em `staging/loki.tf` nunca foi feita. A release helm existe no cluster com 18 revisoes de historico.

**EKS Node Groups:** Os 3 grupos (system, workloads, critical) foram criados via AWS CLI durante a fase de scaling emergencial. Sem IaC, o cluster autoscaler nao possui as tags corretas (`k8s.io/cluster-autoscaler/enabled`, `k8s.io/cluster-autoscaler/<cluster-name>`) em todos os grupos.

## Decisao

Adotar os 4 componentes no Terraform state via `terraform import`, sem interrupcao de servico, seguindo o padrao:

1. Capturar estado atual via `helm get values` / `aws eks describe-nodegroup`
2. Criar recurso Terraform com configuracao identica ao estado atual
3. Executar `terraform import` para registrar o recurso no state
4. Executar `terraform plan` e confirmar zero changes
5. Adicionar `lifecycle { ignore_changes }` seletivo onde necessario

### Abordagem Multi-Agente

Executar a migracao em paralelo com 5 agentes especializados:
- Agent-Promtail: cria `modules/promtail/` + importa rev 8
- Agent-Velero: cria `modules/velero-helm/` + importa rev 11
- Agent-Loki: instancia modulo em `staging/loki.tf` + importa rev 18
- Agent-NodeGroups: cria `node-groups.tf` + importa 3 `aws_eks_node_group`
- Agent-DocSpecialist: documentacao completa da migracao

## Alternativas Consideradas

### Alternativa 1: Recriar os recursos (destroy + apply)

**Rejeitada.** Destruiria servicos operacionais com dados em producao (Loki logs historicos, Velero backups ativos). Risco de disruption inaceitavel.

### Alternativa 2: Manter fora do TF com documentacao de excecao

**Rejeitada.** Viola principio de IaC compliance. Acumula tech debt. Dificulta auditoria e onboarding.

### Alternativa 3: Import seletivo apenas dos mais criticos

**Rejeitada.** Compliance parcial nao e compliance. O Cluster Audit identificou todos os 4 como bloqueadores.

## Consequencias

### Positivas

- Zero drift Terraform pos-migracao para os 4 componentes
- Governanca completa: mudancas requerem PR + terraform apply
- Node groups com tags corretas para cluster autoscaler
- Rollback controlado via `terraform destroy` + `terraform apply`
- Enterprise Maturity mantida em 4.4/5.0 (sem regressao)
- Auditoria simplificada: `terraform state list` mostra todos os componentes

### Negativas / Restricoes

- `lifecycle { ignore_changes = [values] }` necessario em Loki e Promtail para releases com values gerenciados por operadores externos
- Node groups importados com configuracao atual — ajustes de sizing requerem `terraform apply` posterior
- Historico de helm revisions (pre-import) nao e visivel no TF; apenas revisoes pos-import sao rastreadas

### Neutrales

- Velero schedules (daily + hourly) continuam gerenciados via CRDs Kubernetes, nao via Helm values — comportamento mantido
- Nenhum pod reiniciado durante a migracao

## Implementacao

### Ordem de Execucao

Todos os imports sao independentes e podem ser executados em paralelo.

### Validacao

```bash
# Apos cada import, confirmar 0 changes:
terraform plan -target=helm_release.promtail
terraform plan -target=helm_release.velero
terraform plan -target=helm_release.loki
terraform plan -target=aws_eks_node_group.system
terraform plan -target=aws_eks_node_group.workloads
terraform plan -target=aws_eks_node_group.critical
```

### Rollback

Nao aplicavel: o `terraform import` nao modifica o estado do cluster, apenas registra o recurso existente no state file. Para reverter: `terraform state rm <resource>` remove o registro sem afetar o cluster.

## Agentes Envolvidos

- Agent-Promtail
- Agent-Velero
- Agent-Loki
- Agent-NodeGroups
- Agent-DocSpecialist (este documento)

## Referencias

- [Cluster Audit 2026-03-04](../CLUSTER-AUDIT-2026-03-04.md)
- [Logbook Migracao IaC](../logbook/2026-03-05-iac-compliance-migration.md)
- [ADR-086: Linkerd Service Mesh mTLS](adr-086-linkerd-service-mesh-mtls.md)
- [ADR-079: Velero IRSA Migration](adr-079-velero-irsa-migration.md)
