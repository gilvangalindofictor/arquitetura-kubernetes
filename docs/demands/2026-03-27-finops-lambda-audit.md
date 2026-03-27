# FinOps Lambda Audit — Completo

**Data**: 2026-03-27
**Autor**: FinOps + Cloud Specialist (executor-terraform.md)
**Escopo**: Todas as Lambdas FinOps (UP/DOWN) staging + prod, EventBridge rules, schedules, GAPs

---

## Secao 1: Inventario Completo

### 1.1 Lambdas

| # | Nome | Runtime | Handler | Timeout | Memory | Ultima Modificacao | Estrategia |
|---|------|---------|---------|---------|--------|-------------------|------------|
| 1 | finops-scheduler-start-staging | python3.11 | lambda_start.lambda_handler | 900s (15min) | 512MB | 2026-03-24 | Node groups UP + RDS start + Health check |
| 2 | finops-scheduler-stop-staging | python3.11 | lambda_stop.lambda_handler | 900s (15min) | 512MB | 2026-03-23 | Node groups DOWN (desired=0) + RDS stop + Suspend CA |
| 3 | finops-scheduler-start-prod | python3.11 | lambda_start_prod.lambda_handler | 300s (5min) | 256MB | 2026-03-26 | Deployment/StatefulSet scale-up (restore replicas from DynamoDB) |
| 4 | finops-scheduler-stop-prod | python3.11 | lambda_stop_prod.lambda_handler | 180s (3min) | 256MB | 2026-03-26 | Deployment/StatefulSet scale-to-0 (save replicas to DynamoDB) |
| 5 | weekly-finops-report-staging | python3.11 | orphan_detector.lambda_handler | 300s | 256MB | 2026-03-27 | Orphan resource detector |
| 6 | finops-snapshot-cleanup-staging | python3.11 | snapshot_cleanup.lambda_handler | 300s | 128MB | 2026-03-27 | EBS snapshot cleanup |

### 1.2 EventBridge Rules

| # | Rule | Schedule (UTC) | Schedule (BRT) | State AWS | Target Lambda | Input |
|---|------|---------------|----------------|-----------|---------------|-------|
| 1 | finops-startup-staging | cron(30 10 ? * MON-FRI *) | 07:30 BRT Seg-Sex | ENABLED | finops-scheduler-start-staging | action=start, env=staging |
| 2 | finops-shutdown-staging | cron(0 23 ? * MON-FRI *) | 20:00 BRT Seg-Sex | **DISABLED** | finops-scheduler-stop-staging | action=stop, env=staging |
| 3 | finops-weekend-shutdown-staging | cron(0 3 ? * SAT *) | 00:00 BRT Sabado | **DISABLED** | finops-scheduler-stop-staging | action=stop, env=staging |
| 4 | finops-sunday-shutdown-staging | cron(0 23 ? * SUN *) | 20:00 BRT Domingo | **DISABLED** | finops-scheduler-stop-staging | action=stop, env=staging |
| 5 | finops-startup-prod | cron(30 10 ? * MON-FRI *) | 07:30 BRT Seg-Sex | ENABLED | finops-scheduler-start-prod | action=start, env=prod |
| 6 | finops-shutdown-prod | cron(0 23 ? * MON-FRI *) | 20:00 BRT Seg-Sex | **DISABLED** | finops-scheduler-stop-prod | action=stop, env=prod |
| 7 | finops-weekend-shutdown-prod | cron(0 3 ? * SAT *) | 00:00 BRT Sabado | **DISABLED** | finops-scheduler-stop-prod | action=stop, env=prod |
| 8 | finops-sunday-shutdown-prod | cron(0 23 ? * SUN *) | 20:00 BRT Domingo | **DISABLED** | finops-scheduler-stop-prod | action=stop, env=prod |
| 9 | finops-snapshot-cleanup-staging-schedule | cron(0 3 ? * MON *) | 00:00 BRT Segunda | ENABLED | finops-snapshot-cleanup-staging | - |
| 10 | orphan-resource-detector-staging-schedule | cron(0 12 * * ? *) | 09:00 BRT Diario | ENABLED | weekly-finops-report-staging | - |
| 11 | weekly-finops-report-staging-schedule | cron(0 12 ? * MON *) | 09:00 BRT Segunda | ENABLED | weekly-finops-report-staging | - |
| 12 | AutoScalingManagedRule | (event-based) | - | ENABLED | AutoScaling | (AWS internal) |

### 1.3 Resumo Estado Operacional

- **STARTUP**: ambos ENABLED (staging + prod) -- cluster sobe todo dia 07:30 BRT
- **SHUTDOWN**: TODOS os 6 shutdown rules estao DISABLED -- cluster NAO desliga automaticamente
- **Auxiliares**: 3 ENABLED (snapshot cleanup, orphan detector, weekly report)

---

## Secao 2: Analise da Funcao START (UP)

### 2.1 START Staging (`lambda_start.py`)

**Sequencia step-by-step:**

| Step | Operacao | Blocking? | Timeout |
|------|----------|-----------|---------|
| 1 | Resume ASG processes (Launch + Terminate) | Non-blocking | - |
| 1b | Start RDS (fire-and-forget early start) | Non-blocking | - |
| 2 | Scale Cluster Autoscaler Deployment to 1 replica (K8s API PATCH) | Non-blocking | - |
| 3 | Start system node group (min=2, desired=3) | Blocking | - |
| 4 | Wait system nodes ACTIVE + Ready | **HARD GATE** | 480s (8min) |
| 4a | Rollout restart linkerd-cni DaemonSet | Non-blocking | 60s fixed wait |
| 4b | Delete CrashLoopBackOff pods in linkerd ns + Rollout restart Linkerd (identity first, then destination+proxy-injector) | Non-blocking | 120s identity wait |
| 5 | Verify Linkerd control plane Running | **SOFT GATE** (DEGRADED mode) | 480s (8min) |
| 6 | Start workloads + critical node groups (min=0/2, desired=2/2) | Error logged | - |
| 7 | Verify RDS status (retry if step 1b failed) | Error logged | - |
| 8 | Final cluster health check (CRITICAL_WORKLOADS) | **SOFT GATE** | 300s (5min) |
| 9 | Update DynamoDB + send SNS notification | Non-blocking | - |

**Node groups escalados:**

| Node Group | min | desired | max (read from AWS) |
|------------|-----|---------|---------------------|
| system | 2 | 3 | preservado do AWS (4) |
| workloads | 0 | 2 | preservado do AWS (9/12) |
| critical | 2 | 2 | preservado do AWS (4) |

**CRITICAL_WORKLOADS verificados no health check:**

| Namespace | Pod prefix | Min Running |
|-----------|-----------|-------------|
| staging-security-vault | vault-0 | 1 |
| staging-platform-gitlab | gitlab-webservice | 1 |
| linkerd | linkerd-destination | 1 |
| linkerd | linkerd-identity | 1 |
| linkerd | linkerd-proxy-injector | 1 |
| staging-observability-monitoring | alertmanager | 1 |

**Tempo total estimado de startup**: 600-720s tipico, worst case 900s (Lambda max timeout)

**Error handling**: Robusto. Non-blocking errors logados. Hard gates em system nodes + Linkerd. Soft gates em health check final. Circuit breaker threshold=3.

### 2.2 START Prod (`lambda_start_prod.py`)

**Sequencia step-by-step:**

| Step | Operacao | Blocking? |
|------|----------|-----------|
| 1 | Check circuit breaker state (informational only) | Non-blocking |
| 2 | Load previous replica state from DynamoDB | Non-blocking (falls back to defaults) |
| 3 | For each TARGET_NAMESPACE: scale deployments + statefulsets to saved counts | Error logged |
| 3b | Restore RabbitMQ via RabbitmqCluster CR PATCH (operator-controlled) | Error logged |
| 4 | Health check: verify key prod workloads Running | **SOFT GATE** (300s) |
| 5 | Update DynamoDB circuit breaker | Non-blocking |
| 6 | Send SNS notification | Non-blocking |

**TARGET_NAMESPACES (TF deployed, env var real):**

| Namespace | No TF finops-automation-prod.tf | Na env var AWS real |
|-----------|-------------------------------|---------------------|
| prod-platform-keycloak | SIM | SIM |
| prod-platform-sonarqube | NAO (removido ADR-050) | **SIM (DRIFT!)** |
| prod-platform-backstage | NAO (removido GAP-LAMBDA-002) | NAO |
| prod-platform-harbor | SIM | SIM |
| prod-platform-externaldns | SIM | SIM |
| prod-observability-monitoring | SIM | SIM |
| prod-data-hatch-etl | SIM | SIM |
| prod-data-vemsoft-etl | SIM | SIM |
| prod-data-services | SIM | SIM |
| prod-data-rabbitmq | SIM | SIM |
| prod-data-redis-operator | SIM | SIM |
| prod-data-ipaas | SIM | SIM |

**HEALTH_CHECK_CRITERIA:**

| Namespace | Pod prefix | Min Running |
|-----------|-----------|-------------|
| prod-platform-keycloak | keycloak | 1 |
| prod-platform-harbor | harbor-prod-core | 1 |
| prod-platform-argocd | argocd-prod-application-controller | 1 |
| prod-security-vault | vault-prod | 1 |
| prod-observability-monitoring | prometheus-kube-prometheus-stack-prod-prometheus | 1 |

**Fallback replicas**: Detalhado mapa DEFAULT_REPLICA_FALLBACK no codigo (20+ workloads). Usado quando DynamoDB state indisponivel.

---

## Secao 3: Analise da Funcao STOP (DOWN)

### 3.1 STOP Staging (`lambda_stop.py`)

**Sequencia step-by-step:**

| Step | Operacao |
|------|----------|
| 1 | Stop RDS (optional snapshot) |
| 2 | Suspend Cluster Autoscaler (scale CA Deployment to 0 via K8s API + suspend Launch process only) |
| 3 | For each NODE_GROUP_NAMES: scale to minSize=0, desiredSize=0, maxSize=preservado |
| 4 | Calculate estimated savings |
| 5 | Update DynamoDB state |
| 6 | Send SNS notification |

**Node groups escalados (DOWN):**

| Node Group | Target min | Target desired | max | Excluded? |
|------------|-----------|---------------|-----|-----------|
| system | 0 | 0 | preservado | SIM (via EXCLUDED_NODE_GROUPS env var = "system") |
| workloads | 0 | 0 | preservado | NAO |
| critical | 0 | 0 | preservado | NAO |

**ATENCAO**: O node group `system` esta na EXCLUDED_NODE_GROUPS, entao ele NAO sera escalado down. Somente workloads e critical sao escalados para 0.

**Protecao de servicos shared:**
- CA Deployment escalado para 0 ANTES dos node groups (impede re-escala)
- ASG Launch suspended (belt-and-suspenders)
- ASG Terminate NAO suspended (fix 2026-03-18 -- permite scale-down efetivo)

**Ordem**: RDS stop -> CA suspend -> Node groups down. Nao ha scale-down explicito de pods; os pods morrem quando os nodes sao terminados.

**Cleanup**: NAO ha cleanup explicito de CrashLoopBackOff/Evicted pods no STOP. O cleanup ocorre no START (step 4b).

### 3.2 STOP Prod (`lambda_stop_prod.py`)

**Sequencia step-by-step:**

| Step | Operacao |
|------|----------|
| 1 | For each TARGET_NAMESPACE: list deployments + statefulsets, save current replicas to previous_state, scale all to 0 |
| 2 | Scale RabbitMQ via RabbitmqCluster CR PATCH (spec.replicas=0) |
| 3 | Save previous_state to DynamoDB (previous_replicas field) |
| 4 | Update DynamoDB circuit breaker |
| 5 | Send SNS notification |

**TARGET_NAMESPACES (real deployed env var):**
```
prod-platform-keycloak
prod-platform-sonarqube       <-- DRIFT: ainda na env var, removido do TF
prod-platform-harbor
prod-platform-externaldns
prod-observability-monitoring
prod-data-hatch-etl
prod-data-vemsoft-etl
prod-data-services
prod-data-rabbitmq
prod-data-redis-operator
prod-data-ipaas
```

**EXCLUDED_NAMESPACES (real deployed env var):**
```
harbor-system
staging-platform-gitlab
staging-platform-argocd
staging-platform-keycloak
staging-platform-harbor
staging-platform-backstage
staging-platform-sonarqube
staging-platform-externaldns
staging-security-vault
staging-security-externalsecrets
staging-observability-monitoring
monitoring
kube-system
kube-public
kube-node-lease
linkerd
linkerd-cni
linkerd-viz
cert-manager
external-secrets-system
prod-security-externalsecrets
prod-security-vault
prod-platform-argocd
calico-system
calico-apiserver
velero
kyverno                         <-- DRIFT: "kyverno" na env var, TF codifica "staging-governance-kyverno"
```

**Protecao de servicos shared:**
- EXCLUDED_NAMESPACES lista 26 namespaces protected
- Safety guard duplo: TARGET_NAMESPACES (whitelist) + EXCLUDED_NAMESPACES (blacklist)
- Vault prod, ArgoCD prod, staging-* todos protegidos

**Nao toca em:**
- Node groups (cluster compartilhado)
- RDS (compartilhado entre staging e prod)
- Servicos shared (harbor-system, staging-*, linkerd, etc.)

---

## Secao 4: GAPs e Recomendacoes

### 4.1 GAP-FINOPS-AUDIT-001 (P1): Drift env var TARGET_NAMESPACES prod vs TF

**Descricao**: A env var `TARGET_NAMESPACES` deployed na AWS para as Lambdas prod START/STOP contem `prod-platform-sonarqube`, mas o TF (`finops-automation-prod.tf`) ja removeu esse namespace (ADR-050, 2026-03-27). O TF apply ainda nao foi executado para sincronizar.

**AWS env var real**:
```
prod-platform-keycloak,prod-platform-sonarqube,prod-platform-harbor,...
```

**TF codificado (finops-automation-prod.tf L52-67)**:
```
prod-platform-keycloak,prod-platform-harbor,...
```
(sem prod-platform-sonarqube)

**Impacto**: Baixo -- Lambda tenta escalar/desescalar pods em namespace vazio (sonarqube reclassificado). Resultara em log "No state found" ou "0 deployments found", sem erro critico. Mas gera ruido nos logs e no SNS report.

**Fix**: TF apply pendente -- sera resolvido no proximo apply cycle.

### 4.2 GAP-FINOPS-AUDIT-002 (P2): Drift env var EXCLUDED_NAMESPACES "kyverno" vs "staging-governance-kyverno"

**Descricao**: A env var `EXCLUDED_NAMESPACES` deployed na AWS contem `kyverno` (que nunca existiu como namespace -- o namespace real e `staging-governance-kyverno`). O TF ja corrigiu para `staging-governance-kyverno`, mas o apply nao foi executado.

**AWS env var real**: `...velero,kyverno`
**TF codificado**: `...velero,staging-governance-kyverno`

**Impacto**: Baixo -- `kyverno` nunca foi um TARGET_NAMESPACE, entao a EXCLUDED_NAMESPACES entry nunca seria atingida. O namespace real `staging-governance-kyverno` tambem nao esta em TARGET_NAMESPACES (prod Lambdas so tocam `prod-*` namespaces). Guard cosmetic, mas correto corrigir.

**Fix**: TF apply pendente.

### 4.3 GAP-FINOPS-AUDIT-003 (P2): Ausencia staging-security-certmanager na EXCLUDED deployed

**Descricao**: O TF codifica tanto `cert-manager` (legacy) quanto `staging-security-certmanager` (ativo) na EXCLUDED list. Porem, a env var deployed so contem `cert-manager`. O `staging-security-certmanager` esta ausente.

**Impacto**: Baixo -- prod Lambdas so tocam `prod-*` namespaces, entao `staging-security-certmanager` nunca seria atingido. Guard cosmetic.

**Fix**: TF apply pendente.

### 4.4 GAP-FINOPS-AUDIT-004 (P1): TODOS os shutdown rules DISABLED

**Descricao**: Todos os 6 EventBridge shutdown rules estao DISABLED na AWS:
- finops-shutdown-staging (Mon-Fri 20:00 BRT)
- finops-shutdown-prod (Mon-Fri 20:00 BRT)
- finops-weekend-shutdown-staging (Sat 00:00 BRT)
- finops-weekend-shutdown-prod (Sat 00:00 BRT)
- finops-sunday-shutdown-staging (Sun 20:00 BRT)
- finops-sunday-shutdown-prod (Sun 20:00 BRT)

**Impacto**: ALTO -- o cluster NAO esta desligando automaticamente. Os startup rules estao ENABLED, entao o cluster sobe todo dia as 07:30 BRT mas nunca desliga. Custo: o cluster roda 24/7 em vez de 12.5h/dia.

**Savings perdidos (estimativa)**:
- Staging: ~$9.72/dia x 22 dias uteis + ~$19.44/fim de semana x 4 = ~$291/mes
- Prod: menor (somente pods scaled) -- ~$30-50/mes em resource reservation

**Causa provavel**: Desabilitado intencionalmente durante sessao D40 (diagnostico/remediacao). Nao reabilitado apos resolucao.

**Status TF**: O TF para staging define `enable_automation = true`, que deveria resultar em ENABLED. O TF para prod define `state = "ENABLED"` hardcoded. Isso indica que os rules foram desabilitados MANUALMENTE na AWS (drift do TF).

**ATENCAO**: Antes de reabilitar, verificar se o startup esta funcional (pois startup ENABLED + shutdown DISABLED = cluster sobe mas nao desce = custo maximo).

### 4.5 GAP-FINOPS-AUDIT-005 (P2): DLQ nao configurado em nenhuma Lambda

**Descricao**: Nenhuma das 6 Lambda functions tem Dead Letter Queue (DLQ) configurado. Se uma Lambda falha silenciosamente (ex: timeout sem log), o evento e perdido.

**Impacto**: Medio -- o circuit breaker em DynamoDB mitiga parcialmente (threshold=3), e CloudWatch Alarms monitoram Errors. Mas sem DLQ, eventos perdidos nao sao retried.

**Recomendacao**: Adicionar SQS DLQ a cada Lambda via TF. Prioridade: P2 (CloudWatch Alarms ja cobrem erros visibles).

### 4.6 GAP-FINOPS-AUDIT-006 (P3): Codigo legacy `finops_handler.py` sem uso

**Descricao**: O arquivo `finops_handler.py` no modulo finops-automation e uma versao legacy que usa `import requests` (nao disponivel no Lambda runtime padrao) e referencia env vars que nao existem nos deployments atuais (ASG_NAMES, CIRCUIT_BREAKER_TABLE, RDS_STATE_TABLE). Nao e referenciado por nenhum `aws_lambda_function` resource no TF.

**Impacto**: Nenhum (morto). Confusao potencial para novos engenheiros.

**Recomendacao**: Mover para `archive/` ou deletar. Prioridade: P3.

### 4.7 GAP-FINOPS-AUDIT-007 (P1): CLUSTER_NAME mismatch start_prod defaults

**Descricao**: O default de `CLUSTER_NAME` no codigo Python de `lambda_start_prod.py` e `k8s-platform-prod`, enquanto o default no `lambda_start.py` (staging) e `k8s-platform-cluster`. Na env var deployada, AMBOS usam `k8s-platform-prod` (correto). O default nao importa porque a env var esta setada. Porem, se a env var for removida acidentalmente, staging usaria `k8s-platform-cluster` (cluster incorreto).

**Impacto**: Baixo -- env var sempre setada pelo TF.

**Recomendacao**: Alinhar defaults no codigo. Prioridade: P3.

### 4.8 GAP-FINOPS-AUDIT-008 (P2): Lambda prod START RBAC ClusterRole falta verbo "patch" em rabbitmq.com

**Descricao**: O ClusterRole `finops-automation-prod` (definido em `finops-automation-prod.tf` L710-729) concede apenas `get, list, watch` para `rabbitmq.com/rabbitmqclusters`. Porem, `lambda_start_prod.py` executa PATCH no RabbitmqCluster CR (funcao `restore_rabbitmq_cluster()`). Sem o verbo `patch`, a Lambda retorna HTTP 403 Forbidden ao tentar restaurar RabbitMQ.

**IaC codificado** (L728):
```yaml
      - apiGroups: ["rabbitmq.com"]
        resources: ["rabbitmqclusters"]
        verbs: ["get", "list", "watch"]   # <-- FALTA "patch"
```

**Necessario**:
```yaml
        verbs: ["get", "list", "watch", "patch"]
```

**Impacto**: MEDIO -- Lambda start prod falha silenciosamente ao restaurar RabbitMQ (log error, nao hard failure). RabbitMQ permanece com replicas=0 apos startup. Fix manual necessario.

**Fix**: Adicionar `"patch"` ao verbo list do ClusterRole para `rabbitmq.com`.

### 4.9 GAP-FINOPS-AUDIT-009 (P3): TF staging `enable_automation = true` vs AWS reality (shutdown DISABLED)

**Descricao**: O TF staging define `enable_automation = true`, que deveria resultar em TODOS os EventBridge rules (startup + shutdown + weekend + sunday) como ENABLED. Porem, na AWS, apenas startup esta ENABLED e todos shutdown estao DISABLED.

**Causa**: Rules foram desabilitados manualmente na AWS. Isso cria drift. O proximo `terraform apply` reabilitaria todos os shutdown rules.

**Impacto**: Drift TF/AWS. O apply corrigiria, mas deve ser intencional.

**Recomendacao**: Se a intencao e manter shutdown desabilitado, alterar TF para `enable_automation = false` ou split em variaveis separadas (`enable_startup_automation`, `enable_shutdown_automation`). Se a intencao e reabilitar, basta fazer TF apply.

### 4.10 GAP-FINOPS-AUDIT-010 (P2): Staging STOP nao limpa pods antes de desligar nodes

**Descricao**: O `lambda_stop.py` (staging) escala node groups para desired=0 sem primeiro escalar deployments/statefulsets para 0. Os pods morrem abruptamente quando os nodes sao terminados. Isso e diferente do prod approach (que escala pods primeiro, gracefully).

**Impacto**: Baixo para staging (ambiente nao-produtivo). PVCs nao sao afetados (nodes terminados, PVCs persistem). Porem, pods nao recebem SIGTERM graceful (preStop hooks, connection draining), podem deixar state inconsistente em bancos de dados (ex: Vault seal state, GitLab jobs in-progress).

**Recomendacao**: Considerar adicionar graceful drain (scale deployments/statefulsets para 0 antes de desligar nodes). Prioridade: P3 (staging somente).

---

## Secao 5: Schedules Recomendados

### 5.1 Estado Atual vs Desejado

| Rule | Schedule (UTC) | Schedule (BRT) | Dias | AWS State | TF State | Target |
|------|---------------|----------------|------|-----------|----------|--------|
| finops-startup-staging | cron(30 10 ? * MON-FRI *) | 07:30 BRT | Seg-Sex | ENABLED | ENABLED | Lambda start staging |
| finops-shutdown-staging | cron(0 23 ? * MON-FRI *) | 20:00 BRT | Seg-Sex | **DISABLED** | ENABLED | Lambda stop staging |
| finops-weekend-shutdown-staging | cron(0 3 ? * SAT *) | 00:00 BRT Sab | Sab | **DISABLED** | ENABLED | Lambda stop staging |
| finops-sunday-shutdown-staging | cron(0 23 ? * SUN *) | 20:00 BRT Dom | Dom | **DISABLED** | ENABLED | Lambda stop staging |
| finops-startup-prod | cron(30 10 ? * MON-FRI *) | 07:30 BRT | Seg-Sex | ENABLED | ENABLED | Lambda start prod |
| finops-shutdown-prod | cron(0 23 ? * MON-FRI *) | 20:00 BRT | Seg-Sex | **DISABLED** | ENABLED | Lambda stop prod |
| finops-weekend-shutdown-prod | cron(0 3 ? * SAT *) | 00:00 BRT Sab | Sab | **DISABLED** | ENABLED | Lambda stop prod |
| finops-sunday-shutdown-prod | cron(0 23 ? * SUN *) | 20:00 BRT Dom | Dom | **DISABLED** | ENABLED | Lambda stop prod |

### 5.2 Schedules Recomendados (alinhados ao horario comercial)

| Rule | Schedule (UTC) | Schedule (BRT) | Dias | Objetivo |
|------|---------------|----------------|------|----------|
| finops-startup-staging | cron(30 10 ? * MON-FRI *) | 07:30 BRT | Seg-Sex | Cluster UP 30min antes do expediente (08:00 BRT) |
| finops-shutdown-staging | cron(0 23 ? * MON-FRI *) | 20:00 BRT | Seg-Sex | Cluster DOWN apos expediente + buffer |
| finops-weekend-shutdown-staging | cron(0 3 ? * SAT *) | 00:00 BRT Sab | Sab | Guarantee shutdown sexta-noite |
| finops-sunday-shutdown-staging | cron(0 23 ? * SUN *) | 20:00 BRT Dom | Dom | Prevent manual-start residual billing |
| finops-startup-prod | cron(30 10 ? * MON-FRI *) | 07:30 BRT | Seg-Sex | Prod workloads UP para expediente |
| finops-shutdown-prod | cron(0 23 ? * MON-FRI *) | 20:00 BRT | Seg-Sex | Prod workloads DOWN apos expediente |
| finops-weekend-shutdown-prod | cron(0 3 ? * SAT *) | 00:00 BRT Sab | Sab | Prod pods scaled down weekend |
| finops-sunday-shutdown-prod | cron(0 23 ? * SUN *) | 20:00 BRT Dom | Dom | Safety net domingo |

**Os schedules atuais ja estao corretos.** O problema e que os shutdown rules estao DISABLED.

### 5.3 Janela Operacional

```
                    MON-FRI                    SAT            SUN
07:30 BRT  [startup-staging] [startup-prod]
           ├── Cluster UP ────────────────┤
20:00 BRT  [shutdown-staging] [shutdown-prod]
                                           00:00 BRT
                                           [weekend-shutdown]
                                                              20:00 BRT
                                                              [sunday-shutdown]

Horas UP: 12.5h/dia (07:30 - 20:00)
Horas DOWN: 11.5h/dia (20:00 - 07:30)
Savings window: 11.5h/dia x 5 + 48h weekend = 105.5h/semana (62.8% do tempo)
```

---

## Secao 6: Arquitetura e Fluxo de Dados

### 6.1 Staging Strategy: NODE GROUP scale

```
                EventBridge (cron)
                      |
               +------+------+
               |             |
          Lambda START   Lambda STOP
               |             |
    +----------+----------+  +----------+----------+
    | 1. Resume ASG       |  | 1. Stop RDS         |
    | 2. Scale CA to 1    |  | 2. Scale CA to 0    |
    | 3. Start system NG  |  | 3. Suspend ASG      |
    | 4. Wait nodes Ready |  | 4. Scale NGs to 0   |
    | 5. Verify Linkerd   |  | 5. DynamoDB update  |
    | 6. Start wkld/crit  |  | 6. SNS notify       |
    | 7. Verify RDS       |  +---------------------+
    | 8. Health check     |
    | 9. DynamoDB + SNS   |
    +---------------------+
```

### 6.2 Prod Strategy: DEPLOYMENT/STATEFULSET scale

```
                EventBridge (cron)
                      |
               +------+------+
               |             |
          Lambda START   Lambda STOP
               |             |
    +----------+----------+  +----------+----------+
    | 1. Check CB state   |  | 1. For each ns:     |
    | 2. Load DynamoDB    |  |    - List deploy/sts |
    |    previous_replicas|  |    - Save replicas   |
    | 3. Scale UP each ns |  |    - Scale to 0     |
    |    (deploy + sts)   |  | 2. RabbitMQ CR=0    |
    | 4. Restore RabbitMQ |  | 3. Save DynamoDB    |
    |    via CR PATCH     |  | 4. CB update        |
    | 5. Health check     |  | 5. SNS notify       |
    | 6. DynamoDB update  |  +---------------------+
    | 7. SNS notify       |
    +---------------------+
```

### 6.3 Circuit Breaker Pattern (ambos ambientes)

```
CLOSED (normal) ──failures >= 3──> OPEN (alarm)
      ^                                |
      |                                |
  success resets to 0        (informational only,
  startup_failures=0          does NOT block execution)
```

**Nota**: O circuit breaker em OPEN nao bloqueia execucao. Ele loga warning e persiste no DynamoDB. A intencao e alertar (via SNS) e registrar, nao impedir.

---

## Secao 7: Resumo de GAPs

| # | GAP ID | Prioridade | Descricao | Status | Fix |
|---|--------|-----------|-----------|--------|-----|
| 1 | GAP-FINOPS-AUDIT-001 | P1 | TARGET_NAMESPACES drift prod (sonarqube) | TF codificado, apply pendente | TF apply |
| 2 | GAP-FINOPS-AUDIT-002 | P2 | EXCLUDED_NAMESPACES "kyverno" vs "staging-governance-kyverno" | TF codificado, apply pendente | TF apply |
| 3 | GAP-FINOPS-AUDIT-003 | P2 | staging-security-certmanager ausente na EXCLUDED deployed | TF codificado, apply pendente | TF apply |
| 4 | GAP-FINOPS-AUDIT-004 | **P0** | TODOS os 6 shutdown rules DISABLED (~$291/mes perdido) | Drift manual | Reabilitar via TF apply ou AWS Console |
| 5 | GAP-FINOPS-AUDIT-005 | P2 | Nenhum DLQ configurado em Lambdas | Nao codificado | Adicionar SQS DLQ no modulo TF |
| 6 | GAP-FINOPS-AUDIT-006 | P3 | Codigo legacy finops_handler.py | Morto | Mover para archive/ |
| 7 | GAP-FINOPS-AUDIT-007 | P3 | CLUSTER_NAME default mismatch staging vs prod | Cosmetic | Alinhar defaults |
| 8 | GAP-FINOPS-AUDIT-008 | **P1** | ClusterRole prod falta "patch" para rabbitmq.com | Nao codificado | Adicionar verbo no TF |
| 9 | GAP-FINOPS-AUDIT-009 | P2 | TF enable_automation=true vs AWS DISABLED (drift) | Drift manual | TF apply ou split variaveis |
| 10 | GAP-FINOPS-AUDIT-010 | P3 | Staging STOP nao faz graceful drain de pods | By design | Avaliar se necessario |

---

## Secao 8: Validacoes Realizadas

### 8.1 NodeAffinity nao e revertida pela Lambda

**Confirmado**: As Lambdas de START NAO alteram nodeAffinity, tolerations, ou qualquer spec dos pods/deployments alem de `spec.replicas`. A Lambda prod faz somente PATCH com `{"spec": {"replicas": N}}`. A Lambda staging faz somente EKS `update_nodegroup_config` (scaling params). Nenhuma reverte patches de nodeAffinity aplicados por D65b.

### 8.2 Servicos shared protegidos

**Confirmado**: A EXCLUDED_NAMESPACES list protege:
- ESO: `external-secrets-system`, `prod-security-externalsecrets`, `staging-security-externalsecrets`
- Kyverno: `staging-governance-kyverno` (no TF; `kyverno` na env var -- drift P2)
- GitLab: `staging-platform-gitlab`
- Vault: `staging-security-vault`, `prod-security-vault`
- Linkerd: `linkerd`, `linkerd-cni`, `linkerd-viz`
- Harbor shared: `harbor-system`
- ArgoCD: `staging-platform-argocd`, `prod-platform-argocd`

### 8.3 Schedules BRT -> UTC conversion

**Confirmado**: Todas as conversoes estao corretas:
- 07:30 BRT = 10:30 UTC (UTC-3)
- 20:00 BRT = 23:00 UTC (UTC-3)
- 00:00 BRT = 03:00 UTC (UTC-3)

### 8.4 Error handling adequado

**Staging START**: Excepcional. 8-step sequence com gates, circuit breaker, SNS, DynamoDB tracking, graceful degradation (DEGRADED mode ao inves de hard fail). Non-blocking errors em steps nao-criticos. Timeout maximo 900s adequado para worst case.

**Staging STOP**: Adequado. Non-blocking errors em cada step. Circuit breaker tracking. Timeout 900s excessivo para STOP (tipicamente < 60s), mas nao causa problemas.

**Prod START**: Bom. Circuit breaker, DynamoDB state restore, health check, SNS. Timeout 300s adequado (somente K8s API calls, sem node provisioning).

**Prod STOP**: Bom. Previous state persisted to DynamoDB. Circuit breaker. SNS. Timeout 180s adequado.

### 8.5 CloudWatch Alarms

**Staging**: 3 alarms definidos no modulo TF (startup duration high, startup failures, shutdown failures). Dependem de `enable_cloudwatch_alarms` var.

**Prod**: 2 alarms definidos (startup failures, shutdown failures). Ambos com `alarm_actions` + `ok_actions` para SNS topic.

---

## Secao 9: Acao Recomendada Imediata

### Decisao do Usuario Necessaria

1. **REABILITAR shutdown rules?** (GAP-FINOPS-AUDIT-004, P0)
   - Se SIM: TF apply resolvera (TF ja codifica ENABLED)
   - Se NAO: codificar DISABLED no TF para zero drift
   - Savings estimados ao reabilitar: ~$291/mes staging + ~$40/mes prod = ~$331/mes

2. **TF apply ciclo?** (GAP-001, 002, 003, 009)
   - Um TF apply resolvera todos os drifts de env var pendentes
   - Pre-requisito: validar plan, confirmar zero drift pos-apply

3. **ClusterRole patch rabbitmq.com?** (GAP-FINOPS-AUDIT-008, P1)
   - Adicionar `"patch"` ao verbo list para rabbitmq.com no ClusterRole
   - Fix em `finops-automation-prod.tf` L728

---

## Anexo A: Arquivos Fonte Auditados

| Arquivo | Linhas | Tipo |
|---------|--------|------|
| modules/finops-automation/lambda/lambda_start.py | 1699 | START staging |
| modules/finops-automation/lambda/lambda_stop.py | 652 | STOP staging |
| modules/finops-automation/lambda/lambda_start_prod.py | 1076 | START prod |
| modules/finops-automation/lambda/lambda_stop_prod.py | 836 | STOP prod |
| modules/finops-automation/lambda/finops_handler.py | ~200 | LEGACY (nao usado) |
| modules/finops-automation/main.tf | 347 | Modulo TF staging |
| modules/finops-automation/variables.tf | 373 | Variaveis TF |
| environments/staging/main.tf (L1359-1419) | 60 | Invocacao modulo staging |
| environments/prod/finops-automation-prod.tf | 752 | Invocacao + recursos prod |
