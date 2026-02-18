# 2026-02-18 — Cluster Recovery: STOP-AND-FIX + Terraform Apply

## Contexto

Sessão de continuação do P1 Sprint. Objetivo original: `terraform apply` para CoreDNS, VPA, Snapshot Lambda.
Triggou 3 STOP-AND-FIX antes de conseguir executar o apply.

## Root Cause Principal

**Orphan EBS Volume Pattern**: Cleanup de volumes "available" em 2026-02-11 deletou 11 volumes que PVs do K8s ainda referenciavam. Padrão idêntico ao Prometheus (2026-02-13).

**Afetados**: AlertManager, Loki write/backend, Tempo ingester-0, RabbitMQ (default ns), Redis (default ns)

---

## STOP-AND-FIX #1: Default Namespace Orphans

**Problema**: RabbitMQ (3 replicas) + Redis (2 replicas) no namespace `default` referenciando volumes deletados
**Diagnóstico**: PVCs stuck em `Pending` (FailedAttachVolume)
**Causa**: Namespaces migrados para `data-services`, mas recursos antigos nunca removidos

**Fix executado:**
```bash
kubectl delete rabbitmqcluster rabbitmq-cluster -n default   # cascade deletes SS
kubectl delete pvc redis-data-redis-master-0 -n default
kubectl delete pvc redis-data-redis-replicas-0 -n default
```

**Resultado**: ✅ default namespace limpo, sem recursos órfãos

---

## STOP-AND-FIX #2: Monitoring PVCs Recuperados

**Problema**: AlertManager, Loki write-0/1/backend-0/1, Tempo ingester-0 referenciando volumes deletados
**Diagnóstico**: `vol-0a4116ee02b02f30c`, `vol-02c0763fa754b7b64` not found (deleted Feb-11)

**Fix executado (padrão):**
```bash
# Para cada StatefulSet afetado:
kubectl scale statefulset <name> --replicas=0
kubectl delete pvc <stuck-pvc>
kubectl patch pvc <stuck-pvc> -p '{"metadata":{"finalizers":null}}'  # se stuck
kubectl scale statefulset <name> --replicas=<original>
```

**Resultado**:
- AlertManager: ✅ 2/2 Running (novo PVC `pvc-863f32c9-...`)
- Loki write-0/1: ✅ 1/1 Running cada
- Loki backend-0/1: ✅ 2/2 Running cada
- Tempo ingester-0: PVC recriado (ver STOP-AND-FIX #3)

---

## STOP-AND-FIX #3: SonarQube CrashLoop + Tempo Ingester S3 Issue

### SonarQube (RESOLVIDO)

**Problema**: Init container `inject-prometheus-exporter` falhava com SSL timeout baixando JMX exporter de `repo1.maven.org`
**Causa**: NAT Gateway intermittente + repo1.maven.org instável

**Fix:**
```bash
# Release estava em pending-install - delete + reinstall
helm delete sonarqube -n sonarqube --no-hooks

# Reinstalar com prometheusExporter disabled + monitoringPasscode obrigatório
helm install sonarqube ~/.cache/helm/repository/sonarqube-10.7.0+3598.tgz \
  -n sonarqube \
  -f /tmp/sonar-values-current.yaml  # prometheusExporter.enabled=false
```

**Lição**: Chart v10.7.0 exige `monitoringPasscode` mesmo com serviceMonitor disabled.

**Resultado**: ✅ SonarQube `1/1 Running`

### Tempo Ingester S3 Intermittent (CONHECIDO / LIMITADO)

**Problema**: `tempo-ingester-0` crashloop com `TLS handshake timeout` para S3
**Diagnóstico**: 

1. Ingester-0 inicialmente em `ip-10-0-133-36.ec2.internal` (us-east-1a)
2. S3 timeout de TODOS os nós exceto `ip-10-0-151-63` (22min old, fresh node)
3. S3 funciona via Gateway endpoint (403 em 57ms) em fresh nodes
4. Nós antigos (parados/reiniciados pelo Lambda weekend shutdown) têm S3 intermitente

**Root Cause**: EC2 stop/start causa estado inconsistente no S3 VPC Gateway Endpoint routing. Calico, Security Groups, Route Tables — todos corretos. Apenas fresh nodes (nunca stopped) funcionam consistentemente.

**Fix parcial:**
```bash
# Mover ingester-0 para fresh node (us-east-1b)
kubectl scale statefulset tempo-ingester -n monitoring --replicas=0
kubectl delete pvc data-tempo-ingester-0 -n monitoring  # recria em us-east-1b
kubectl scale statefulset tempo-ingester -n monitoring --replicas=2
```

**Resultado**: Ingester-0 movido para `ip-10-0-151-63` (us-east-1b, fresh node). S3 intermitente persiste — self-resolves conforme gateways normalizam.

**Recomendação**: Atualizar Lambda de weekend shutdown para TERMINATE nodes ao invés de STOP — fresh launch resolve o routing issue.

---

## Terraform Apply (CONCLUÍDO)

### Recursos Aplicados

| Recurso | Status |
|---------|--------|
| `kubernetes_config_map_v1.coredns_split_horizon` | ✅ Criado (8 rewrite rules) |
| `helm_release.vpa` | ✅ Deployed (fairwinds/vpa v4.4.6) |
| 12× `kubectl_manifest` VPA | ✅ All in Off mode (recommendation only) |
| `module.snapshot_cleanup` | ✅ Lambda + EventBridge (weekly Mon 03:00 UTC) |

### VPA Status
```
kubectl get vpa -A
# 12 VPAs: vault, keycloak, harbor, gitlab-webservice, gitlab-sidekiq,
#           argocd, prometheus, grafana, loki, tempo, rabbitmq, redis
# Mode: Off (recommendation only, não auto-apply)
```

### CoreDNS Split-Horizon
```
kubectl get cm coredns-custom -n kube-system
# 8 rewrite rules: keycloak, gitlab, argocd, grafana, harbor, sonarqube, vault, rabbitmq
# Aguarda rollout para ativar DNS resolution
```

### Snapshot Cleanup Lambda
- `finops-snapshot-cleanup-staging`
- Schedule: weekly Monday 03:00 UTC
- Critérios: description contém migration/temp/gp2/test + >30 dias + sem AMI dep
- Safety: skip `FinOps:Keep=true`, `Lifecycle=protected`

---

## Savings Tracking

| Item | Valor | Status |
|------|-------|--------|
| VPA recommendations (30d) | R$ 8.712/ano (pending) | Aguarda 30d coleta |
| Snapshot cleanup Lambda | R$ 216/ano | Prevenção implementada ✅ |
| SonarQube prometheusExporter | Pequeno ($0/mês) | Desabilitado ✅ |

---

## Issues Conhecidas (Documentadas, Não Bloqueantes)

1. **Tempo ingester S3 intermitente**: EC2 stop/start degrada S3 Gateway Endpoint. Self-resolves. Fix: Lambda→terminate ao invés de stop.

2. **Terraform PostgreSQL timeout from WSL**: Provider tenta conectar RDS (IP privado) direto do WSL. Fix: usar TF Cloud Agent ou tunnel SSH.

3. **OTel Helm release drift**: "cannot re-use a name that is still in use" — release em Helm mas com estado drift no TF. Fix: `helm delete otel-collector -n monitoring; terraform apply`.

