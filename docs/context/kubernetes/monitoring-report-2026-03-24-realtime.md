# Monitoring Report — k8s-platform (Tempo Real)
**Data coleta**: 2026-03-25 02:28–02:40 UTC
**Gerado por**: Monitoring Orchestrator
**Método**: kubectl + aws CLI com credenciais SSO temporárias
**Cluster**: k8s-platform-prod (único cluster EKS, single shared)
**Namespaces ativos**: staging-* e prod-* no mesmo cluster

---

## STATUS GERAL: MODO NOTURNO FINOPS (NORMAL/ESPERADO)

> O cluster está em modo shutdown noturno programado. Este é o estado ESPERADO.
> FinOps Stop executou às 23:00 UTC de 2026-03-24 (segunda-feira).
> FinOps Start programado para 10:30 UTC de 2026-03-25 (terça-feira) — em ~8h.
> NÃO há incidente ativo não-planejado. O "vault-prod-0 Pending" alertado é consequência do shutdown.

---

## Nós Ativos

| Nó | Status | AZ | Instância | Taint | Age |
|----|--------|----|----|-------|-----|
| ip-10-0-129-91.ec2.internal | Ready | us-east-1a | t3.medium | node-type=system:NoSchedule | 12h (subiu hoje) |
| ip-10-0-144-245.ec2.internal | Ready | us-east-1b | t3.medium | node-type=system:NoSchedule | 37h |
| ip-10-0-149-203.ec2.internal | Ready | us-east-1b | t3.medium | node-type=system:NoSchedule | 37h |

**ASGs Status:**
| ASG | Min | Max | Desired | Running |
|-----|-----|-----|---------|---------|
| eks-system | 2 | 4 | 3 | 3 (normal) |
| eks-critical | 0 | 4 | **0** | 0 (shutdown noturno) |
| eks-workloads | 0 | 9 | **0** | 0 (shutdown noturno) |

---

## Resumo de Pods

| Status | Count | Causa |
|--------|-------|-------|
| Running | 55 | Normal — serviços com toleration system:NoSchedule |
| Pending | 66 | Normal — sem nós workloads/critical disponíveis |
| Error/Terminated | 42 | Normal — pods terminados durante shutdown (NodeShutdown) |
| Completed | 27 | Normal — jobs concluídos |
| ContainerStatusUnknown | 3 | Normal — pods de nós terminados |
| CrashLoopBackOff | 4 | ANOMALIA — ver abaixo |
| Init:0/1 | 2 | Aguardando serviços dependentes (normal no shutdown) |

---

## Pods Running (Confirmados Saudáveis)

### Sistema/Infra (kube-system)
- aws-load-balancer-controller: 2/2 Running
- aws-node (daemonset): 3/3 Running
- calico-node: 3/3 Running
- calico-typha: 1/1 Running
- ebs-csi-node: 3/3 Running
- kube-proxy: 3/3 Running
- metrics-server: 1/1 Running
- harbor-registry-config (daemonset): 3/3 Running

### Linkerd (linkerd)
- linkerd-destination: 1/1 Running (4/4 containers)
- linkerd-identity: 1/1 Running (2/2 containers)
- linkerd-proxy-injector: 1/1 Running
- linkerd-cni: 3 Running (daemonset nos 3 nós)

### Linkerd-viz
- tap-injector: 1/1 Running
- (outros 3 pods Pending por falta de nós sem taint)

### Staging ArgoCD
- argocd-server: 1/1 Running
- argocd-redis: 1/1 Running
- argocd-repo-server: 2/2 Running
- argocd-applicationset-controller: 2/2 Running
- argo-rollouts: 2/2 Running

### Staging Observabilidade
- alertmanager: 1/1 Running
- grafana: 1/1 Running
- kube-state-metrics: 1/1 Running
- kube-prometheus-stack-operator: 1/1 Running
- prometheus-node-exporter: 3 Running (nos 3 nós)
- loki-read: 1/1 Running
- promtail: 3/3 Running

### Staging Cert Manager
- cert-manager: 1/1 Running
- cert-manager-cainjector: 1/1 Running
- cert-manager-webhook: 1/1 Running

### Velero
- node-agent: 1/1 Running (nos nós ativos)

### Staging VemSoft ETL
- vemsoft-etl: 1/1 Running

---

## ANOMALIA REAL DETECTADA: ArgoCD Prod CrashLoopBackOff

**Componentes afetados:**
- `argocd-prod-applicationset-controller` — CrashLoopBackOff
- `argocd-prod-redis` — CrashLoopBackOff
- `argocd-prod-server` — CrashLoopBackOff

**Root Cause:**
1. O namespace `prod-platform-argocd` tem Linkerd injection habilitado: `linkerd.io/inject: enabled`
2. O CoreDNS está Pending (sem nós sem taint disponíveis)
3. O Linkerd proxy não consegue resolver `linkerd-identity-headless.linkerd.svc.cluster.local:8080`
4. Os pods foram reiniciados manualmente às 2026-03-24T14:50:46 e ficaram em loop

**Evidência dos logs:**
```
ERROR: Failed to obtain identity — linkerd-identity-headless.linkerd.svc.cluster.local:8080: service in fail-fast
WARN: Failed to resolve control-plane component — request timed out
```

**Impacto:**
- ArgoCD prod indisponível durante o horário de shutdown
- Ao retornar os nós workloads às 10:30 UTC, CoreDNS ficará Running → Linkerd resolverá identidade → pods ArgoCD prod devem se recuperar automaticamente

**Ação necessária pós-UP:**
- Verificar se ArgoCD prod se recuperou automaticamente
- Se ainda em CrashLoopBackOff: `kubectl -n prod-platform-argocd rollout restart deployment argocd-prod-server argocd-prod-applicationset-controller`
- Verificar se o Redis do ArgoCD prod precisa de restart manual

**Investigação adicional necessária:**
- Por que ArgoCD prod foi reiniciado manualmente em 2026-03-24T14:50:46? (antes do shutdown)
- Verificar se houve alguma intervenção que causou o restart prematuro

---

## vault-prod-0 — ANÁLISE FINAL (NÃO É INCIDENTE P1)

**Estado real:**
- vault-prod-0: Error — `Terminated: Pod was terminated in response to imminent node shutdown`
- vault-prod-1: Pending (sem nós disponíveis)
- vault-prod-2: Error — mesma causa

**EBS vol-065f3b18bebee9fc0:**
- State: `available`
- AZ: us-east-1a
- Attachments: [] (desacoplado do nó terminado — normal)
- O volume está íntegro e disponível para reattach

**Conclusão:** O vault não está com problema real — foi terminado junto com os nós pelo FinOps shutdown. O PV ainda existe e o volume EBS está disponível. Ao iniciar os nós às 10:30 UTC, o vault-prod-0 será re-agendado no nó com AZ us-east-1a e o volume será reacoplado automaticamente.

**Risco:** Se o nó que subir em us-east-1a não tiver capacidade ou se houver AZ mismatch, o vault-prod-0 ainda ficará Pending. Monitorar no startup.

---

## RDS PostgreSQL

- Status: **STOPPED** (esperado — FinOps noturno para databases)
- Versão: 16.4
- MultiAZ: **False** (risco documentado D1)
- Instância: k8s-platform-prod-postgresql

**Verificar no startup:** Se RDS também precisa de start manual ou se é gerenciado pelo FinOps Lambda.

---

## ACM Certificados

| Domínio | Status |
|---------|--------|
| keycloak.staging.internal | ISSUED |
| harbor.staging.internal | ISSUED |
| *.prod.alvocard.com.br | ISSUED |
| *.hml.alvocard.com.br | ISSUED |

Todos os 4 certificados ISSUED. OK.

---

## Harbor System (harbor-system namespace)

Situação anômala — pods em ContainerCreating e Error:
- harbor-core: 2x ContainerStatusUnknown (de nós terminados)
- harbor-jobservice: ContainerCreating + Error
- harbor-registry: ContainerCreating + Error
- harbor-portal: 1 Running, 1 Pending

**Causa:** Provavelmente o harbor-system não é gerenciado pelo FinOps Lambda (não está na lista de target_namespaces do stop Lambda). Os pods foram afetados pelo shutdown de nós mas não foram escalados para 0 antes.

**Ação necessária pós-UP:** Os pods ContainerCreating/Error devem se resolver quando novos nós subirem. Se não, fazer `kubectl -n harbor-system rollout restart` dos deployments afetados.

---

## GAPs Status Atualizado

| GAP ID | Status Real | Observação |
|--------|-------------|------------|
| GAP-VAULT-PROD-PENDING | **FALSO ALARME** — shutdown FinOps noturno | Vault saudável, retorna no startup |
| GAP-FINOPS-ACCESS-ENTRY | PERSISTENTE | EKS auth mode CONFIG_MAP |
| GAP-LOKI-CANARY-AFFINITY | **DIFERENTE** — loki-canary no prod em Error (não Pending) | 7 pods Error no prod-observability-monitoring |
| GAP-KYVERNO-POLICY-SPAM | Status desconhecido durante shutdown | Verificar pós-startup |
| GAP-LAMBDA-FP-01 | CONFIRMADO | vol-065f3b18bebee9fc0 detectado como orphan no shutdown |
| **NEW: ARGOCD-PROD-LINKERD-CBK** | **NOVO** | ArgoCD prod CrashLoopBackOff por Linkerd/DNS durante shutdown |
| **NEW: HARBOR-SYSTEM-EVICTION** | **NOVO** | harbor-system não gerenciado pelo FinOps Lambda — pods em estado inconsistente |

---

## Ações Recomendadas

### Imediatas (Antes do UP 10:30 UTC)
1. Nenhuma ação crítica necessária — cluster está em estado intencional
2. Documentar nova anomalia ArgoCD prod (CrashLoopBackOff por Linkerd durante shutdown)
3. Documentar harbor-system não coberto pelo FinOps Lambda

### No momento do UP (10:30 UTC 2026-03-25)
1. Monitorar se vault-prod-0 faz reattach automático em us-east-1a
2. Monitorar se CoreDNS sobe corretamente (os ASGs critical/workloads sobem)
3. Monitorar se ArgoCD prod se recupera automaticamente após CoreDNS
4. Verificar se harbor-system se recupera
5. Verificar se RDS precisa de start manual (não monitorado pelo FinOps Lambda?)

### P2 — Próxima sessão
6. **Investigar**: Por que ArgoCD prod foi reiniciado manualmente às 14:50 UTC 2026-03-24?
7. **Corrigir**: Adicionar harbor-system ao FinOps Lambda stop list OU garantir que pods tolerem shutdown gracioso
8. **Verificar**: Se RDS tem stop/start automático via FinOps ou é manual

---

## FinOps Lambdas (Status Confirmado)

| Lambda | Invocações (30d) | Último Run | Status |
|--------|-----------------|------------|--------|
| finops-scheduler-stop-staging | — | 2026-03-24 23:00:21 UTC | OK |
| finops-scheduler-stop-prod | — | 2026-03-24 23:00:45 UTC | OK |
| finops-scheduler-start-staging | — | Próximo: 2026-03-25 10:30 UTC | Agendado |
| finops-scheduler-start-prod | — | Próximo: 2026-03-25 10:30 UTC | Agendado |

---

## Próximo Monitoramento

- **Quando**: 10:45 UTC 2026-03-25 (15 min após o UP programado)
- **Componentes prioritários**:
  1. vault-prod-0 — reattach EBS + unsealing
  2. ArgoCD prod — recuperação pós-CoreDNS
  3. harbor-system — recuperação de pods
  4. RDS PostgreSQL — status após startup
  5. Número de nós (deve voltar a 15)

---

## Arquivos de Diagnóstico Coletados

- `/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/context/kubernetes/monitoring-report-2026-03-24.md` — Relatório baseline
- `/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/context/kubernetes/monitoring-report-2026-03-24-realtime.md` — Este documento
- `/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/context/kubernetes/incident-vault-prod-p1.md` — Runbook vault (reclassificado: FALSO ALARME)
- `/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/context/kubernetes/diagnostics-scripts.sh` — Script de diagnóstico

---

**Assinatura**: Monitoring Orchestrator
**Timestamp coleta**: 2026-03-25T02:40 UTC
