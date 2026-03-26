# Prompt de Continuação — RabbitMQ Prod Migration Fase 2
# Gerado em: 2026-03-23

## CONTEXTO OPERACIONAL

Você é o **Orquestrador DevOps Sênior** retomando a migração do RabbitMQ prod.
Siga o protocolo `CLAUDE.md` — despachar Task agents para execução, nunca executar diretamente.

---

## ESTADO ATUAL (snapshot 2026-03-23 noite)

### Fase 1 — CONCLUÍDA (executada nesta sessão)

| Passo | Ação | Status |
|-------|------|--------|
| PV ReclaimPolicy | `pvc-b609fb15` → Retain (era Delete) | ✅ |
| Operator | `rabbitmq-cluster-operator` escalado de 0→1 réplica | ✅ |
| Namespace | `prod-data-rabbitmq` criado com labels ADR-048 (`environment=prod`) | ✅ |
| TF code | `prod/main.tf`: `namespace = "prod-data-rabbitmq"` + NetworkPolicy separada | ✅ |
| Script | `MIGRATION-rabbitmq-state.sh`: NEW_NS=prod-data-rabbitmq | ✅ |

### Problema detectado (background task pós-Fase 1)

O RabbitmqCluster criado em `prod-data-rabbitmq` está com:
```
ALLREPLICASREADY=Unknown  RECONCILESUCCESS=False  AGE=4m
No pods, PVCs ou Services criados no namespace prod-data-rabbitmq
```

**Causa provável:** Kyverno policy de corporate labels bloqueando recursos gerados pelo operator
(mesmo problema que ocorreu durante a criação — o `spec.override` pode não ter sido suficiente).

**Ação antes do switchover:** Diagnosticar e corrigir o RabbitmqCluster em `prod-data-rabbitmq`.

### Cluster antigo — intacto e saudável
- `data-services/k8s-platform-prod-rabbitmq-server-0`: 1/1 Running
- PVC: gp2/5Gi, PV=**Retain** (protegido)
- Estado: **IDLE** — 0 conexões, 0 filas, 0 mensagens (confirmado por assessment)

---

## ARQUIVOS TF RELEVANTES

```
platform-provisioning/aws/kubernetes/terraform/environments/prod/main.tf
  → module.rabbitmq_prod: namespace = "prod-data-rabbitmq"
  → kubectl_manifest.netpol_deny_staging_access: data-services-prod (Redis only)
  → kubectl_manifest.netpol_deny_staging_access_rabbitmq: prod-data-rabbitmq (RabbitMQ)

platform-provisioning/aws/kubernetes/terraform/environments/prod/MIGRATION-rabbitmq-state.sh
  → Script TF state rm + import para usar APÓS migração kubectl completa
  → NEW_NS="prod-data-rabbitmq"
```

---

## FASE 2 — RUNBOOK COMPLETO

### PRÉ-REQUISITO: Diagnosticar RabbitmqCluster em prod-data-rabbitmq

```bash
# Verificar eventos do operador
kubectl describe rabbitmqcluster k8s-platform-prod-rabbitmq -n prod-data-rabbitmq 2>&1 | tail -30

# Verificar logs do operator
kubectl logs -n rabbitmq-system deployment/rabbitmq-cluster-operator --tail=50 2>&1 | grep -i "prod-data-rabbitmq\|error\|failed"

# Verificar se Kyverno bloqueou algum recurso
kubectl get events -n prod-data-rabbitmq --sort-by='.lastTimestamp' 2>&1 | tail -20

# Verificar PolicyReports do Kyverno
kubectl get policyreport -n prod-data-rabbitmq 2>&1
```

Se Kyverno estiver bloqueando: adicionar labels ausentes via `spec.override` no CR.
Se outro erro: analisar os logs do operator e corrigir.

---

### FASE 2A — Aguardar healthcheck do novo cluster

```bash
kubectl wait --for=condition=Ready pod \
  -l app.kubernetes.io/name=k8s-platform-prod-rabbitmq \
  -n prod-data-rabbitmq --timeout=300s

kubectl get rabbitmqcluster k8s-platform-prod-rabbitmq -n prod-data-rabbitmq
kubectl get pods,pvc,svc -n prod-data-rabbitmq
```

**Gate:** `ALLREPLICASREADY=True`, `RECONCILESUCCESS=True`, pod 1/1 Running

---

### FASE 2B — Switchover (janela ~5 min, cluster idle = zero impacto)

```bash
# 1. Confirmar zero mensagens no cluster antigo
kubectl port-forward -n data-services svc/k8s-platform-prod-rabbitmq 15672:15672 &
OLD_USER=$(kubectl get secret k8s-platform-prod-rabbitmq-default-user -n data-services -o jsonpath='{.data.username}' | base64 -d)
OLD_PASS=$(kubectl get secret k8s-platform-prod-rabbitmq-default-user -n data-services -o jsonpath='{.data.password}' | base64 -d)
curl -s -u "$OLD_USER:$OLD_PASS" http://localhost:15672/api/overview | python3 -c "
import json,sys; d=json.load(sys.stdin)
msgs = d.get('queue_totals',{}).get('messages',0)
conns = d.get('object_totals',{}).get('connections',0)
print(f'Messages: {msgs} | Connections: {conns}')
print('SAFE TO SWITCHOVER' if msgs==0 and conns==0 else 'WARNING: pending messages or connections!')
"

# 2. Deletar RabbitmqCluster antigo (operator remove StatefulSet + Services, NÃO remove PVC)
kubectl delete rabbitmqcluster k8s-platform-prod-rabbitmq -n data-services

# 3. Verificar que apenas Redis restou em data-services
kubectl get all,pvc -n data-services

# 4. Confirmar novo cluster OK
kubectl get rabbitmqcluster k8s-platform-prod-rabbitmq -n prod-data-rabbitmq
kubectl get pods,pvc,svc -n prod-data-rabbitmq
```

---

### FASE 2C — TF State manipulation

```bash
cd platform-provisioning/aws/kubernetes/terraform/environments/prod

# Ativar credenciais AWS
eval $(aws configure export-credentials --profile k8s-platform-staging --format env)
unset AWS_PROFILE && export AWS_DEFAULT_REGION=us-east-1

# Executar script de migração de state
bash MIGRATION-rabbitmq-state.sh prod

# Resultado esperado:
# kubernetes_manifest.rabbitmq_cluster:              no changes
# kubernetes_service.rabbitmq_management_internal:   no changes
# null_resource.rabbitmq_operator:                   1 to add (idempotente — OK)
```

---

### FASE 2D — Aplicar NetworkPolicy para prod-data-rabbitmq

```bash
# A NetworkPolicy para prod-data-rabbitmq está no TF mas ainda não foi aplicada
terraform plan \
  -target=kubectl_manifest.netpol_deny_staging_access_rabbitmq \
  -var-file=secrets.auto.tfvars

terraform apply \
  -target=kubectl_manifest.netpol_deny_staging_access_rabbitmq \
  -var-file=secrets.auto.tfvars
```

---

### FASE 2E — Limpeza PV antigo (gp2)

```bash
# PV antigo em Released state (ReclaimPolicy=Retain, PVC deletada pelo delete do CR)
PV_OLD="pvc-b609fb15-2dd2-4369-9223-56940be3bb70"
kubectl get pv $PV_OLD -o jsonpath='{.status.phase}' 2>&1  # Deve ser: Released

# Deletar PV (libera EBS gp2 — saving ~$0.50/mês)
kubectl delete pv $PV_OLD
```

---

### FASE 2F — Verificar ZERO DRIFT

```bash
terraform plan \
  -target=module.rabbitmq_prod \
  -target=kubectl_manifest.netpol_deny_staging_access \
  -target=kubectl_manifest.netpol_deny_staging_access_rabbitmq \
  -var-file=secrets.auto.tfvars

# Gate: "No changes. Your infrastructure matches the configuration."
```

---

## GAPS ADICIONAIS DETECTADOS (documentar no logbook)

| GAP | Descrição | Fix |
|-----|-----------|-----|
| GAP-RABBITMQ-REPLICAS-001 | CR prod tem 1 réplica, TF tem `rabbitmq_replicas=3`. Sem quorum HA em prod. | Aumentar para 3 após migração estável |
| GAP-RABBITMQ-LABEL-001 | Labels `Environment=staging` no cluster antigo | Corrigido no novo CR (`Environment=production`) |
| GAP-RABBITMQ-PVC-001 | PVC antigo: gp2/5Gi. Novo: gp3/10Gi | Corrigido automaticamente na criação |

---

## CRITÉRIO DE SUCESSO (ZERO DRIFT)

```
✅ RabbitmqCluster em prod-data-rabbitmq: AllReplicasReady=True
✅ NetworkPolicy deny-access-from-staging em prod-data-rabbitmq: aplicada
✅ terraform plan -target=module.rabbitmq_prod: No changes
✅ namespace data-services: apenas Redis (sem RabbitMQ residual)
✅ PV antigo (gp2): deletado
✅ Logbook atualizado com GAP-RABBITMQ-NS-001 resolvido
```

---

## REFERÊNCIAS

- TF code: `platform-provisioning/aws/kubernetes/terraform/environments/prod/main.tf`
- Migration script: `platform-provisioning/aws/kubernetes/terraform/environments/prod/MIGRATION-rabbitmq-state.sh`
- Protocolo: `docs/prompts/executor-terraform.md`
- Memória: `/home/gilvangalindo/.claude/projects/.../memory/MEMORY.md`
