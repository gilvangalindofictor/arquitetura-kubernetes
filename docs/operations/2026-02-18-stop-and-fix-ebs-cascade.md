# STOP-AND-FIX: EBS Cascade Failure — 2026-02-18

**Data:** 2026-02-18
**Duração:** ~3h (10:00–13:30 BRT)
**Severidade:** P1 (múltiplas stacks degradadas)
**Status Final:** Parcialmente resolvido (Tempo ingester-0 + S3 VPC pendente)

---

## Resumo Executivo

Cleanup de volumes EBS órfãos de 2026-02-11 deletou 11 volumes ainda referenciados por PVs do Kubernetes. PVCs ficaram em estado `Lost` causando CrashLoopBackOff em múltiplos workloads críticos. Volumes deletados eram `available` no EC2, mas pertenciam a pods em scale-down temporário.

Adicionalmente, foram descobertos dois problemas de infraestrutura: SonarQube com init SSL timeout e TLS handshake timeout no S3 para nós específicos do nodegroup `workloads`.

---

## Timeline

### 10:00 — Detecção (STOP-AND-FIX Ativado)

Checagem pré-terraform-apply revelou:
- **4 CrashLoopBackOff**, **5 ContainerCreating**, **4 Init:0/1**

Namespaces afetadas: `default`, `monitoring`, `sonarqube`

### 10:05 — Root Cause Analysis

Volumes deletados em 2026-02-11 (orphan cleanup):

| Namespace | Workload | Volume ID | Status |
|-----------|----------|-----------|--------|
| default | rabbitmq-0 | vol-0b357582c62f6ce9c | Deletado |
| default | rabbitmq-1 | vol-0d67b50203df170d0 | Deletado |
| default | rabbitmq-2 | vol-0da55a8fba84d0a8b | Deletado |
| default | redis-master | vol-00dd3e92e5a97210b | Deletado |
| default | redis-replicas | vol-071e5453c1b3faa4d | Deletado |
| monitoring | alertmanager-0 | vol-0a4116ee02b02f30c | Deletado |
| monitoring | loki-write-0 | vol-046ddaa100a176f46 | Deletado |
| monitoring | loki-write-1 | vol-0c5a7e8d6246af0d3 | Deletado |
| monitoring | loki-backend-0 | vol-0cd00cc8868b0d8e6 | Deletado |
| monitoring | loki-backend-1 | vol-0bfd9f8aeba863ea8 | Deletado |
| monitoring | tempo-ingester-0 | vol-02c0763fa754b7b64 | Deletado |

### 10:15 — STOP-AND-FIX P1: namespace default

```bash
# RabbitMQCluster CR em default (órfão, não deveria existir)
kubectl delete rabbitmqcluster -n default $(kubectl get rabbitmqcluster -n default -o name)
# → operator cascadeou StatefulSet, pods terminados

# Redis PVCs (StatefulSet não existia — só PVCs)
kubectl delete pvc -n default redis-data-redis-master-0 redis-data-redis-replicas-0 redis-data-redis-replicas-1
```

**Resultado:** ✅ default namespace limpo — nenhum pod Running (correto)

### 10:30 — STOP-AND-FIX P2: namespace monitoring

**Padrão aplicado em cada StatefulSet:**
1. `kubectl scale sts NAME -n monitoring --replicas=0`
2. `kubectl delete pvc PVC_NAME -n monitoring`
3. `kubectl scale sts NAME -n monitoring --replicas=N`

Workloads recuperados:
- ✅ alertmanager-0: 2/2 Running
- ✅ loki-write-0,1: 1/1 Running (×2)
- ✅ loki-backend-0,1: 2/2 Running (×2)
- ✅ tempo-ingester-1: 1/1 Running

### 11:00 — STOP-AND-FIX P3: SonarQube

**Problema:** `inject-prometheus-exporter` init container falhando com curl exit code 28 (SSL timeout ao baixar JAR do repo1.maven.org)

**Root cause:** `prometheusExporter.enabled: true` no helm release em produção, apesar de `enable_prometheus_exporter = false` no TF module.

**Fix:** Helm release deletado (lado negativo: helm upgrade falhou por DNS WSL2) → helm reinstalou com valores corretos automaticamente → `prometheusExporter.enabled: false` ✅

**Resultado:** sonarqube-sonarqube-0: 1/1 Running ✅

### 11:30 — Descoberta: S3 VPC Gateway Endpoint (R-044)

**Sintoma:** `tempo-ingester-0` e `tempo-query-frontend-595bf5545b-sfj77` crashando:
```
"TLS handshake timeout" → k8s-platform-tempo-891377105802.s3.us-east-1.amazonaws.com
```

**Padrão identificado:**
| Node | AZ | S3 Works? |
|------|-----|-----------|
| ip-10-0-133-36 | us-east-1a t3.large | ❌ TLS timeout |
| ip-10-0-149-75 | us-east-1b t3.large | ❌ TLS timeout |
| ip-10-0-151-63 | us-east-1b t3.large | ✅ |
| ip-10-0-143-82 | us-east-1a t3.xlarge | ✅ |

**Hipótese:** Subnets dos pods EKS custom networking nos nós t3.large não têm a route do S3 VPC Gateway Endpoint no route table (pl-63a5400a).

**Status:** Pendente AWS auth para investigar e corrigir route tables.

---

## Estado Final

### Resolvido ✅
- default namespace: limpo (RabbitMQ + Redis órfãos removidos)
- AlertManager: 2/2 Running
- Loki: todos os pods Running
- Tempo ingester-1: 1/1 Running
- Tempo query-frontend: 1/2 Running (1 pod estável)
- SonarQube: 1/1 Running com prometheusExporter.enabled=false

### Pendente ⚠️
- **R-044**: Tempo ingester-0 e 1 query-frontend crasham por S3 TLS timeout
  - Fix: Adicionar S3 prefix list (pl-63a5400a) às route tables das subnets workloads
  - Requer: AWS Console/CLI com auth
- **Terraform apply**: Bloqueado por AWS SSO session expirada
  - Fix: `aws sso login --profile k8s-platform-staging`

---

## Lições Aprendidas

### L1: Cross-check PVs ANTES de deletar EBS (CRÍTICO)

```bash
# Volumes "available" no EC2 podem ter PVs K8s no estado Released/Retain
kubectl get pv -o jsonpath='{.items[*].spec.awsElasticBlockStore.volumeID}' | tr ' ' '\n' | sort > /tmp/k8s-pvs.txt
aws ec2 describe-volumes --filters "Name=status,Values=available" | jq -r '.Volumes[].VolumeId' | sort > /tmp/ec2-available.txt
comm -23 /tmp/ec2-available.txt /tmp/k8s-pvs.txt  # APENAS estes são safe to delete
```

### L2: RabbitMQCluster CR cascade

Deletar `RabbitMQCluster` CR faz o operator cascadear StatefulSet + Services. PVCs NÃO são deletados automaticamente — precisam de limpeza manual.

### L3: SonarQube prometheusExporter

O init container `inject-prometheus-exporter` faz curl para `repo1.maven.org`. Em ambientes com DNS restrito ou latência alta, sempre setar `prometheusExporter.enabled=false`.

### L4: EKS custom networking + S3 Gateway Endpoint

Em clusters com `ENABLE_PREFIX_DELEGATION=true` e múltiplas subnets por AZ, verificar que TODAS as route tables das subnets de pods têm a route do S3 Gateway Endpoint. Não apenas as subnets dos nós.

---

## Comandos de Diagnóstico Usados

```bash
# Pod health snapshot
kubectl get pods -A | grep -v "Running\|Completed\|NAMESPACE"

# Identificar volumes missing
kubectl get pvc -A -o yaml | grep -A5 "Lost\|vol-"

# Recuperar StatefulSet com PVC perdido
kubectl scale sts NAME -n NS --replicas=0
kubectl delete pvc PVC_NAME -n NS
kubectl scale sts NAME -n NS --replicas=ORIG

# Verificar conectividade S3 por nó
kubectl run s3-test --image=amazon/aws-cli --restart=Never --rm \
  --overrides='{"spec":{"nodeName":"NODE_NAME"}}' \
  -- s3 ls s3://BUCKET --no-cli-pager
```
