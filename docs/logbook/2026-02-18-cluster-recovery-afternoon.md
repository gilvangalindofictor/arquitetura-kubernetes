# 2026-02-18 (Tarde) — Cluster Recovery: STOP-AND-FIX Completo + Monitoramento Restaurado

## Contexto

Continuação da sessão matinal (ver `2026-02-18-cluster-recovery-stop-and-fix.md`).
Estado no início: Terraform Apply concluído. Tempo ingester com S3 TLS timeout.
Sequência de eventos em cascata desencadeada durante recovery.

---

## STOP-AND-FIX #4: Tempo Ingester S3 Fix — Migração para Critical Nodegroup

**Problema**: `tempo-ingester-0` em CrashLoopBackOff. S3 TLS handshake timeout ao escrever traces.

**Root Cause**: Ingester estava em `ip-10-0-151-63` com IP `10.0.156.82` (ens6 — secondary ENI). VPC CNI cria `ip rule from POD_IP lookup 2` para IPs em ENIs secundárias, causando routing assimétrico para o S3 VPC Gateway Endpoint.

**Diagnóstico Key**:
- Ingester-1 (IP `10.0.148.68` = primary ENI): 1/1 Running, S3 OK
- Ingester-0 (IP `10.0.156.82` = ens6 secondary ENI): CrashLoop
- SNAT bypass iptables rules (sessão anterior) tornaram TCP pior: SYN-ACK parou de chegar

**Fix executado**:
```bash
# 1. Limpar SNAT bypass rules do ip-10-0-151-63 (debug pod privilégio)
kubectl apply -f /tmp/cleanup-snat-bypass.yaml  # privileged hostNetwork pod
# iptables -t nat -D AWS-SNAT-CHAIN-0 -o ens6 -j RETURN
# iptables -t nat -D AWS-SNAT-CHAIN-0 -o ens7 -j RETURN

# 2. Migrar ingesters para critical nodegroup (ip-10-0-153-218, us-east-1b)
kubectl patch statefulset tempo-ingester -n monitoring --type='json' -p='[
  {"op":"replace","path":"/spec/template/spec/nodeSelector","value":{"node-type":"critical"}},
  {"op":"add","path":"/spec/template/spec/tolerations/-","value":{"key":"workload","operator":"Equal","value":"critical","effect":"NoSchedule"}},
  {"op":"replace","path":"/spec/template/spec/affinity","value":{...nodegroup=critical, zone NotIn us-east-1a...}}
]'

# 3. Scale 0 → delete PVCs → scale 2
kubectl scale sts tempo-ingester -n monitoring --replicas=0
kubectl delete pvc data-tempo-ingester-{0,1} -n monitoring
kubectl scale sts tempo-ingester -n monitoring --replicas=2
```

**Resultado**: ✅ `tempo-ingester-0` e `tempo-ingester-1`: 1/1 Running em `ip-10-0-153-218` (critical, us-east-1b)

---

## STOP-AND-FIX #5: kube-prometheus-stack Rolling Update Blocked

**Problema**: Rollout do kube-prometheus-stack (iniciado ~3h antes) ficou stuck.
- System nodes `ip-10-0-135-130` e `ip-10-0-152-132`: ambos em 17/17 pods (limite t3.medium)
- Prometheus StatefulSet: pod antigo deletado, novo pod Pending (sem capacidade)

**Fix Prometheus**:
```bash
kubectl patch prometheus kube-prometheus-stack-prometheus -n monitoring \
  --type='json' -p='[{"op":"remove","path":"/spec/nodeSelector"}]'
# Resultado: prometheus-0 schedula em critical node → 2/2 Running
```

**Fix Grafana**:
```bash
# Init:0/1 Pending bloqueava node-exporter DaemonSet
kubectl delete pod kube-prometheus-stack-grafana-XXXX -n monitoring  # força reinício
kubectl patch deployment kube-prometheus-stack-grafana -n monitoring \
  --type='json' -p='[{"op":"remove","path":"/spec/template/spec/nodeSelector"}]'
# Resultado: grafana 3/3 Running em node disponível
```

---

## STOP-AND-FIX #6: GitLab Runner CrashLoopBackOff

**Problema**: Runner tentava conectar `gitlab.staging.internal:80` → CoreDNS rewrite para ClusterIP `172.20.156.24:80` → sem listener na porta 80.

**Fix**:
```bash
kubectl patch deployment gitlab-gitlab-runner -n gitlab-staging \
  --type='json' -p='[{
    "op":"replace",
    "path":"/spec/template/spec/containers/0/env/X/value",
    "value":"http://gitlab-webservice-default.gitlab-staging.svc.cluster.local:8080"
  }]'
```

**Resultado secundário**: Após URL fix → 500 Internal Server Error (registration token inválido — GitLab 17.x deprecou tokens de runner v15.6+). Runner escalado para 0 réplicas até admin obter novo token via GitLab UI.

---

## STOP-AND-FIX #7: SonarQube PostgreSQL Auth Failure

**Problema**: SonarQube CrashLoop com `password authentication failed for user 'sonarqube_user'`. Secret K8s continha senha diferente da do RDS.

**Fix**:
```bash
# Pod temporário com master credentials
kubectl run psql-fix --image=postgres:15 -n sonarqube --rm -it \
  --env="PGPASSWORD=<master_pass>" \
  -- psql -h k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com \
     -U postgres_admin -d postgres \
     -c "ALTER USER sonarqube_user WITH PASSWORD '<senha-do-secret>';"
```

**Resultado**: ✅ SonarQube 1/1 Running

---

## Incidente: Node ip-10-0-135-130 NotReady — Cascata de Falhas

### Timeline

| Hora (aprox) | Evento |
|---|---|
| ~15:30 | Node `ip-10-0-135-130` (system, us-east-1a, i-03ff24910ba442563) — kubelet para |
| ~15:31 | Condições do node: todas `Unknown` ("Kubelet stopped posting node status") |
| ~15:32 | EBS volumes `vol-0dc9ca15fceb206b6` (redis-0) e `vol-0f30bbee1de9871ac` (sonarqube) stuck attached |
| ~15:33 | redis-0: `Multi-Attach error` — pod evicted mas volume não desanexado |
| ~15:34 | harbor-core, harbor-jobservice, gitlab-kas falham (Redis indisponível) |
| ~15:35 | Cluster Autoscaler provisiona 2 novos nodes: `ip-10-0-135-134` e `ip-10-0-159-233` (workloads) |
| ~15:40 | EBS force-detach + VolumeAttachment cleanup → redis-0 volta |
| ~15:45 | Harbor e gitlab-kas recuperam |
| ~16:48 | helm upgrade: nodeSelectors removidos (alertmanager + operator) |
| ~17:00 | Todos os pods Running |

### Fix: EBS Multi-Attach (dead node)

```bash
# Force-detach volumes do node morto
aws ec2 detach-volume --volume-id vol-0dc9ca15fceb206b6 --instance-id i-03ff24910ba442563 --force
aws ec2 detach-volume --volume-id vol-0f30bbee1de9871ac --instance-id i-03ff24910ba442563 --force

# Deletar VolumeAttachments stale no K8s
kubectl delete volumeattachment csi-350b3b7a341483...  # redis
kubectl delete volumeattachment csi-4399d029da9d...    # prometheus
kubectl delete volumeattachment csi-60a486ee94ae...    # sonarqube
```

**Resultado**: ✅ redis-0: 2/2 Running, harbor-core: 1/1, harbor-jobservice: 1/1, gitlab-kas: 1/1

---

## Fix Final: kube-prometheus-stack nodeSelector (Alertmanager + Operator)

**Problema**: `--set 'nodeSelector={}'` no helm interpretado como array vazio, não map vazio.

**Erro**:
```
cannot unmarshal array into Go struct field PodSpec.spec.template.spec.nodeSelector
of type map[string]string
```

**Fix correto — values file**:
```bash
cat > /tmp/monitoring-no-nodesel.yaml << 'EOF'
prometheusOperator:
  nodeSelector: {}
prometheus:
  prometheusSpec:
    nodeSelector: {}
alertmanager:
  alertmanagerSpec:
    nodeSelector: {}
EOF

helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --version 81.4.2 \
  --reuse-values \
  --values /tmp/monitoring-no-nodesel.yaml
```

**Resultado**:
- alertmanager-0: 2/2 Running ✅
- kube-prometheus-stack-operator: 1/1 Running ✅
- prometheus-0: 2/2 Running ✅

> **Lição crítica**: `helm upgrade --set 'key={}'` produz array. Para empty map usar `--values` com YAML.

---

## Terminação do Node Morto

```bash
# Remover do K8s primeiro
kubectl delete node ip-10-0-135-130.ec2.internal

# Terminar instância EC2 (NOT stop — terminate força fresh hypervisor/ENI)
aws ec2 terminate-instances --instance-ids i-03ff24910ba442563
# → shutting-down
```

O ASG do nodegroup `system` irá provisionar um novo node para substituição.

---

## Estado Final (2026-02-18 ~17:00)

```bash
kubectl get pods -A | grep -v -E "Running|Completed"
# NAMESPACE   NAME   READY   STATUS   ... → apenas cabeçalho (ZERO pods unhealthy)

kubectl get nodes
# 7 nodes Ready (ip-10-0-135-130 terminado, ASG provisiona substituto)
```

| Componente | Status Final |
|---|---|
| tempo-ingester-0 | 1/1 Running (critical nodegroup, us-east-1b) |
| tempo-ingester-1 | 1/1 Running (critical nodegroup, us-east-1b) |
| prometheus-0 | 2/2 Running |
| alertmanager-0 | 2/2 Running |
| kube-prometheus-stack-operator | 1/1 Running |
| grafana | 3/3 Running |
| redis-0 | 2/2 Running |
| harbor-core | 1/1 Running |
| gitlab-kas | 1/1 Running |
| sonarqube | 1/1 Running |
| gitlab-runner | 0/1 (scaled to 0 — token fix pendente) |

---

## Pendências Identificadas

1. **GitLab runner token**: Obter novo token via GitLab 17.x admin UI → escalar runner de volta para 1
2. **Persist monitoring fix**: Adicionar `nodeSelector: {}` no Helm values Terraform para prometheus/alertmanager/operator
3. **Persist tempo fix**: Codificar nodeSelector=critical + toleration + GODEBUG em Terraform/Helm values
4. **Lambda weekend shutdown**: Alterar de STOP para TERMINATE nodes para evitar S3 Gateway Endpoint routing degradation
5. **Novo system node**: Verificar que ASG provisionou substituto para ip-10-0-135-130

---

## Lessons Learned

| # | Lição |
|---|---|
| 1 | `helm --set 'key={}'` = array vazio. Para map vazio usar `--values file.yaml` |
| 2 | EBS Multi-Attach em K8s requer DOIS passos: `aws ec2 detach-volume --force` + `kubectl delete volumeattachment` |
| 3 | Prometheus Operator reconcilia nodeSelector do CR baseado em Helm chart values; patch direto no CR é revertido |
| 4 | System nodes t3.medium atingem 17 pods rapidamente — rolling updates bloqueiam se não há capacidade spare |
| 5 | EC2 STOP (não TERMINATE) degrada S3 VPC Gateway Endpoint routing no hypervisor layer |
