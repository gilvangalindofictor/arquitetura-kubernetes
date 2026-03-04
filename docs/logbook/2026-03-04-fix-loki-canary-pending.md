# Fix: loki-canary + promtail + loki-write-1 Pending — 2026-03-04

## Contexto

Pods Pending detectados em `staging-observability-monitoring`:

- `loki-canary-lpdtm` (Pending 15h)
- `loki-canary-vdmcp` (Pending 15h)
- `promtail-dsw82` (Pending 15h)
- `promtail-n9cf5` (Pending 15h)
- `promtail-xhc2f` (Pending 4h)
- `loki-write-1` (Pending 15h, StatefulSet)

Event do scheduler: `0/10 nodes are available: 1 Too many pods, 9 node(s) didn't satisfy plugin(s) [NodeAffinity]`

## Root Cause

**Cenário: "Too many pods" em nodes com capacidade esgotada (maxPods=17 por ENI limit EKS)**

O Kubernetes DaemonSet controller injeta automaticamente `requiredDuringSchedulingIgnoredDuringExecution` com `matchFields: metadata.name` em cada pod de DaemonSet, travando-o a um node específico. O erro "NodeAffinity" no evento vem desse mecanismo interno — não de affinity configurada pelo usuário (o DaemonSet tem `affinity: {}`).

### Nodes afetados e causa raiz por pod

| Pod | Node Alvo | Problema |
|-----|-----------|---------|
| `loki-canary-lpdtm` | `ip-10-0-159-141` (system, us-east-1b) | 20/17 pods — 3 pods Completed (gitlab-migrations) consumindo slots |
| `loki-canary-vdmcp` | `ip-10-0-147-71` (system, us-east-1b) | 17/17 pods — node cheio |
| `promtail-dsw82` | `ip-10-0-147-71` (system, us-east-1b) | 17/17 pods — node cheio |
| `promtail-n9cf5` | `ip-10-0-132-9` (system, us-east-1a) | 17/17 pods — node cheio |
| `promtail-xhc2f` | `ip-10-0-134-234` (workloads, us-east-1a) | 17/17 pods — node cheio |
| `loki-write-1` | `ip-10-0-147-71` (único node system us-east-1b disponível) | PVC zona-locked em us-east-1b + anti-affinity com loki-write-0 em ip-10-0-159-141 |

### Por que `ip-10-0-159-141` tinha 20 pods (acima do limite 17)?

3 pods Completed da instalação do GitLab permaneceram no node após conclusão:
- `gitlab-migrations-028d96d-qbwns` (Completed)
- `gitlab-migrations-50affb2-sdncm` (Completed)
- `gitlab-minio-create-buckets-6b9104a-47vt2` (Completed)

Pods Completed **contam para o limite de pods por node** no Kubernetes.

### Topologia de nodes (t3.medium = maxPods 17 via VPC CNI ENI limits)

```
ip-10-0-129-44   system    t3.medium  maxPods=17  us-east-1a
ip-10-0-132-9    system    t3.medium  maxPods=17  us-east-1a
ip-10-0-147-71   system    t3.medium  maxPods=17  us-east-1b
ip-10-0-159-141  system    t3.medium  maxPods=17  us-east-1b
ip-10-0-134-234  workloads t3.large   maxPods=35  us-east-1a
ip-10-0-143-191  workloads t3.large   maxPods=35  us-east-1a
ip-10-0-145-199  workloads t3.large   maxPods=35  us-east-1b
ip-10-0-152-207  workloads t3.large   maxPods=35  us-east-1b
ip-10-0-130-167  critical  t3.xlarge  maxPods=58  us-east-1a  (taint: workload=critical:NoSchedule)
ip-10-0-148-204  critical  t3.xlarge  maxPods=58  us-east-1b  (taint: workload=critical:NoSchedule)
```

## Fix Aplicado

### Passo 1: Deletar pods Completed em ip-10-0-159-141 (liberar 3 slots)

```bash
kubectl delete pod gitlab-migrations-028d96d-qbwns -n gitlab-staging
kubectl delete pod gitlab-migrations-50affb2-sdncm -n gitlab-staging
kubectl delete pod gitlab-minio-create-buckets-6b9104a-47vt2 -n gitlab-staging
```

**Resultado:** 1 slot liberado em ip-10-0-159-141 → loki-canary-lpdtm scheduled.

### Passo 2: Liberar slot em ip-10-0-147-71 para loki-canary-vdmcp

```bash
kubectl delete pod nginx-canary-test-5bb8597557-bpjc8 -n rollouts-test
```

Pod de ReplicaSet de teste (3 réplicas no cluster) — reschedulado para outro node.
**Resultado:** loki-canary-vdmcp scheduled em ip-10-0-147-71.

### Passo 3: Liberar slot em ip-10-0-132-9 para promtail-n9cf5

```bash
kubectl delete pod trace-generator-7cfd775486-6svt4 -n otel-test
```

Pod de teste com ReplicaSet — reschedulado.
**Resultado:** promtail-n9cf5 scheduled em ip-10-0-132-9.

### Passo 4: Liberar slot em ip-10-0-134-234 para promtail-xhc2f

```bash
kubectl delete pod tracing-test-app-6f9c57c77b-ddbhk -n tracing-test
```

Pod de teste — reschedulado.
**Resultado:** promtail-xhc2f scheduled em ip-10-0-134-234.

### Passo 5: Liberar slots em ip-10-0-147-71 para promtail-dsw82 e loki-write-1

```bash
kubectl delete pod nginx-blue-green-test-6dcd5988db-bfsdp -n rollouts-test
kubectl delete pod nginx-blue-green-test-b849bf79-d2xxp -n rollouts-test
```

Cada deleção liberou 1 slot — primeiro ocupado por promtail-dsw82, segundo por loki-write-1.

**Critério de segurança:** todos os pods deletados tinham segundas réplicas em outros nodes (ReplicaSets com desired >= 2) ou eram pods de teste (namespaces `rollouts-test`, `otel-test`, `tracing-test`).

### Bonus: Cluster Autoscaler provisioning

Durante o processo, o Cluster Autoscaler detectou a demanda e provisionou um novo node:
- `ip-10-0-130-141` (workloads, t3.large, us-east-1a, maxPods=35)

Este node recebeu: `loki-canary-g9cn4` e `promtail-vzz6p` (novos pods do DaemonSet para o novo node).

## Estado Final

```
DaemonSet loki-canary:   DESIRED=9  CURRENT=9  READY=9  (0 Pending)
DaemonSet promtail:      DESIRED=9  CURRENT=9  READY=9  (0 Pending)
StatefulSet loki-write:  2/2 Running                    (0 Pending)
```

**Total pods staging-observability-monitoring:** 59 Running, 0 Pending, 0 CrashLoop

## Lição Aprendida / Preventivo

1. **Pods Completed devem ser limpos regularmente** — não são limpos automaticamente por padrão no Kubernetes. Usar TTL para Jobs ou configurar `ttlSecondsAfterFinished` em Jobs do GitLab.

2. **t3.medium nodes têm maxPods=17 (ENI limit VPC CNI)** — nodes do grupo `system` chegam ao limite facilmente. Considerar:
   - Aumentar grupo `system` para t3.large (maxPods=35) na próxima janela
   - Ou habilitar `prefix delegation` no aws-node DaemonSet para aumentar ENI pod capacity

3. **DaemonSet pods ficam "stuck" em nodes cheios** — o DaemonSet controller não realoca automaticamente. O fix requer liberar o slot no node alvo específico.

4. **loki-write PVC é zone-locked** — o volume EBS gp3 da us-east-1b só pode ser montado por nodes nessa zona. Com apenas 2 system nodes em us-east-1b (ip-10-0-147-71 e ip-10-0-159-141), a capacidade de failover é limitada.

## Arquivos Relacionados

- `domains/observability/infra/helm/loki/` — Helm values do Loki
- `docs/adr/adr-078-velero-backup-dr-implementation.md` — DR context
