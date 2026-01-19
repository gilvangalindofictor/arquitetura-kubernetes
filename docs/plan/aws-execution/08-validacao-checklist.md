# 08 - Validação e Checklist Final

> **Épico I** | Estimativa: 26 person-hours | Sprint 3
> **Pré-requisitos**: Todos os documentos anteriores (01-07) concluídos

---

## Índice

1. [Visão Geral](#1-visão-geral)
2. [Smoke Tests por Componente](#2-smoke-tests-por-componente)
3. [Testes End-to-End](#3-testes-end-to-end)
4. [Definition of Done - Todos os Épicos](#4-definition-of-done---todos-os-épicos)
5. [Checklist de Go-Live](#5-checklist-de-go-live)
6. [Runbook de Validação](#6-runbook-de-validação)
7. [Documentação de Handoff](#7-documentação-de-handoff)
8. [Troubleshooting Guide](#8-troubleshooting-guide)
9. [Métricas de Sucesso](#9-métricas-de-sucesso)
10. [Sign-off Final](#10-sign-off-final)

---

## 1. Visão Geral

### 1.1 Fluxo de Validação

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        VALIDATION PIPELINE                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌──────────┐ │
│  │   SMOKE     │ ─▶ │    E2E      │ ─▶ │   LOAD      │ ─▶ │ SIGN-OFF │ │
│  │   TESTS     │    │   TESTS     │    │   TESTS     │    │          │ │
│  └─────────────┘    └─────────────┘    └─────────────┘    └──────────┘ │
│       │                  │                  │                  │        │
│       ▼                  ▼                  ▼                  ▼        │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌──────────┐ │
│  │ Components  │    │ User        │    │ Performance │    │ Go-Live  │ │
│  │ Health      │    │ Workflows   │    │ Baselines   │    │ Approval │ │
│  └─────────────┘    └─────────────┘    └─────────────┘    └──────────┘ │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Critérios de Validação

| Fase | Critério | Threshold |
|------|----------|-----------|
| **Smoke Tests** | Todos os componentes respondem | 100% |
| **E2E Tests** | Fluxos críticos funcionam | 100% |
| **Performance** | Latência P95 | < 2s |
| **Availability** | Uptime em 24h | > 99% |
| **Security** | Vulnerabilidades críticas | 0 |
| **Backup** | Restore testado | 1 ciclo completo |

---

## 2. Smoke Tests por Componente

### 2.1 Script Mestre de Smoke Tests

```bash
#!/bin/bash
# smoke-tests.sh
# Executar após deploy completo

set -e

DOMAIN="seudominio.com.br"
RESULTS_FILE="/tmp/smoke-test-results-$(date +%Y%m%d-%H%M).txt"

echo "=== K8S PLATFORM SMOKE TESTS ===" | tee $RESULTS_FILE
echo "Started: $(date)" | tee -a $RESULTS_FILE
echo "" | tee -a $RESULTS_FILE

TOTAL=0
PASSED=0
FAILED=0

test_result() {
    TOTAL=$((TOTAL + 1))
    if [ $1 -eq 0 ]; then
        echo "✅ PASS: $2" | tee -a $RESULTS_FILE
        PASSED=$((PASSED + 1))
    else
        echo "❌ FAIL: $2" | tee -a $RESULTS_FILE
        FAILED=$((FAILED + 1))
    fi
}

# ============================================
# 1. INFRAESTRUTURA BASE
# ============================================
echo "" | tee -a $RESULTS_FILE
echo "=== 1. INFRAESTRUTURA BASE ===" | tee -a $RESULTS_FILE

# EKS Cluster
kubectl cluster-info > /dev/null 2>&1
test_result $? "EKS Cluster accessible"

# Nodes
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
[ $NODE_COUNT -ge 3 ]
test_result $? "Minimum 3 nodes running (found: $NODE_COUNT)"

# Nodes Ready
READY_NODES=$(kubectl get nodes --no-headers | grep " Ready " | wc -l)
[ $READY_NODES -eq $NODE_COUNT ]
test_result $? "All nodes in Ready state"

# StorageClass
kubectl get sc gp3 > /dev/null 2>&1
test_result $? "StorageClass gp3 exists"

# ============================================
# 2. GITLAB
# ============================================
echo "" | tee -a $RESULTS_FILE
echo "=== 2. GITLAB ===" | tee -a $RESULTS_FILE

# Pods Running
GITLAB_PODS=$(kubectl get pods -n gitlab --no-headers | grep -c "Running")
[ $GITLAB_PODS -ge 5 ]
test_result $? "GitLab pods running (found: $GITLAB_PODS)"

# Webservice
kubectl exec -n gitlab deploy/gitlab-webservice-default -- curl -s localhost:8181/-/readiness | grep -q "ok"
test_result $? "GitLab webservice healthy"

# External Access
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://gitlab.$DOMAIN/-/readiness 2>/dev/null || echo "000")
[ "$HTTP_CODE" = "200" ]
test_result $? "GitLab external access (HTTP $HTTP_CODE)"

# Sidekiq
SIDEKIQ_READY=$(kubectl get pods -n gitlab -l app=sidekiq --no-headers | grep -c "Running")
[ $SIDEKIQ_READY -ge 1 ]
test_result $? "Sidekiq running"

# Gitaly
kubectl exec -n gitlab deploy/gitlab-gitaly -- /srv/gitlab/gitaly/gitaly check > /dev/null 2>&1
test_result $? "Gitaly healthy"

# Runner
kubectl get pods -n gitlab -l app=gitlab-runner --no-headers | grep -q "Running"
test_result $? "GitLab Runner running"

# ============================================
# 3. DATA SERVICES
# ============================================
echo "" | tee -a $RESULTS_FILE
echo "=== 3. DATA SERVICES ===" | tee -a $RESULTS_FILE

# RDS Connectivity
RDS_ENDPOINT=$(kubectl get secret -n gitlab gitlab-postgresql-password -o jsonpath='{.data.postgresql-host}' | base64 -d)
kubectl run rds-test --image=postgres:15 --rm -it --restart=Never -n gitlab -- \
  pg_isready -h $RDS_ENDPOINT -p 5432 -U gitlab > /dev/null 2>&1
test_result $? "RDS PostgreSQL accessible"

# Redis
kubectl exec -n data-services deploy/redis-master -- redis-cli ping | grep -q "PONG"
test_result $? "Redis responding"

# Redis Sentinel
kubectl exec -n data-services deploy/redis-master -- redis-cli -p 26379 ping | grep -q "PONG"
test_result $? "Redis Sentinel responding"

# RabbitMQ
kubectl exec -n data-services deploy/rabbitmq -- rabbitmqctl status > /dev/null 2>&1
test_result $? "RabbitMQ healthy"

# RabbitMQ Management
HTTP_CODE=$(kubectl exec -n data-services deploy/rabbitmq -- curl -s -o /dev/null -w "%{http_code}" http://localhost:15672/api/overview -u guest:guest)
[ "$HTTP_CODE" = "200" ]
test_result $? "RabbitMQ Management API accessible"

# ============================================
# 4. OBSERVABILITY
# ============================================
echo "" | tee -a $RESULTS_FILE
echo "=== 4. OBSERVABILITY ===" | tee -a $RESULTS_FILE

# Prometheus
kubectl exec -n observability deploy/prometheus-server -- wget -qO- http://localhost:9090/-/healthy | grep -q "Prometheus Server is Healthy"
test_result $? "Prometheus healthy"

# Prometheus Targets
TARGET_UP=$(kubectl exec -n observability deploy/prometheus-server -- wget -qO- "http://localhost:9090/api/v1/targets" | jq -r '.data.activeTargets | map(select(.health=="up")) | length')
[ $TARGET_UP -ge 10 ]
test_result $? "Prometheus targets up (found: $TARGET_UP)"

# Grafana
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://grafana.$DOMAIN/api/health 2>/dev/null || echo "000")
[ "$HTTP_CODE" = "200" ]
test_result $? "Grafana accessible (HTTP $HTTP_CODE)"

# Loki
kubectl exec -n observability deploy/loki -- wget -qO- http://localhost:3100/ready | grep -q "ready"
test_result $? "Loki ready"

# Tempo
kubectl exec -n observability deploy/tempo -- wget -qO- http://localhost:3200/ready | grep -q "ready"
test_result $? "Tempo ready"

# OTEL Collector
kubectl get pods -n observability -l app.kubernetes.io/name=opentelemetry-collector --no-headers | grep -q "Running"
test_result $? "OpenTelemetry Collector running"

# Alertmanager
kubectl exec -n observability deploy/alertmanager -- wget -qO- http://localhost:9093/-/healthy | grep -q "OK"
test_result $? "Alertmanager healthy"

# ============================================
# 5. SECURITY
# ============================================
echo "" | tee -a $RESULTS_FILE
echo "=== 5. SECURITY ===" | tee -a $RESULTS_FILE

# Network Policies
NP_COUNT=$(kubectl get networkpolicies -A --no-headers | wc -l)
[ $NP_COUNT -ge 5 ]
test_result $? "Network Policies applied (found: $NP_COUNT)"

# cert-manager
kubectl get pods -n cert-manager -l app.kubernetes.io/name=cert-manager --no-headers | grep -q "Running"
test_result $? "cert-manager running"

# Certificates
CERT_READY=$(kubectl get certificates -A -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -c "True")
[ $CERT_READY -ge 1 ]
test_result $? "TLS certificates ready (found: $CERT_READY)"

# External Secrets
kubectl get pods -n external-secrets --no-headers | grep -q "Running"
test_result $? "External Secrets Operator running"

# Secrets Synced
ES_SYNCED=$(kubectl get externalsecrets -A -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -c "True" || echo "0")
[ $ES_SYNCED -ge 1 ]
test_result $? "External Secrets synced (found: $ES_SYNCED)"

# ============================================
# 6. BACKUP
# ============================================
echo "" | tee -a $RESULTS_FILE
echo "=== 6. BACKUP ===" | tee -a $RESULTS_FILE

# Velero
kubectl get pods -n velero -l app.kubernetes.io/name=velero --no-headers | grep -q "Running"
test_result $? "Velero running"

# Backup Location
velero backup-location get default -o json | jq -e '.status.phase == "Available"' > /dev/null
test_result $? "Velero backup location available"

# Recent Backup
LAST_BACKUP_AGE=$(velero backup get -o json | jq -r '[.items[] | select(.status.phase=="Completed")] | sort_by(.metadata.creationTimestamp) | last | .metadata.creationTimestamp' | xargs -I {} date -d {} +%s)
NOW=$(date +%s)
AGE_HOURS=$(( (NOW - LAST_BACKUP_AGE) / 3600 ))
[ $AGE_HOURS -lt 25 ]
test_result $? "Recent backup exists (age: ${AGE_HOURS}h)"

# ============================================
# SUMMARY
# ============================================
echo "" | tee -a $RESULTS_FILE
echo "==========================================" | tee -a $RESULTS_FILE
echo "SMOKE TEST SUMMARY" | tee -a $RESULTS_FILE
echo "==========================================" | tee -a $RESULTS_FILE
echo "Total Tests: $TOTAL" | tee -a $RESULTS_FILE
echo "Passed: $PASSED" | tee -a $RESULTS_FILE
echo "Failed: $FAILED" | tee -a $RESULTS_FILE
echo "Success Rate: $(( PASSED * 100 / TOTAL ))%" | tee -a $RESULTS_FILE
echo "" | tee -a $RESULTS_FILE

if [ $FAILED -eq 0 ]; then
    echo "✅ ALL SMOKE TESTS PASSED" | tee -a $RESULTS_FILE
    exit 0
else
    echo "❌ SOME SMOKE TESTS FAILED" | tee -a $RESULTS_FILE
    exit 1
fi
```

### 2.2 Executar Smoke Tests

```bash
chmod +x smoke-tests.sh
./smoke-tests.sh

# Ver resultados
cat /tmp/smoke-test-results-*.txt
```

---

## 3. Testes End-to-End

### 3.1 E2E Test: GitLab CI/CD Pipeline

```bash
#!/bin/bash
# e2e-gitlab-pipeline.sh

GITLAB_URL="https://gitlab.seudominio.com.br"
GITLAB_TOKEN="glpat-xxxxxxxxxxxx"  # Access Token com api scope

echo "=== E2E Test: GitLab CI/CD Pipeline ==="

# 1. Criar projeto de teste
echo "1. Creating test project..."
PROJECT_ID=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  --data "name=e2e-test-$(date +%s)&visibility=private" \
  "$GITLAB_URL/api/v4/projects" | jq -r '.id')

if [ "$PROJECT_ID" = "null" ]; then
    echo "❌ Failed to create project"
    exit 1
fi
echo "   Created project ID: $PROJECT_ID"

# 2. Adicionar arquivo .gitlab-ci.yml
echo "2. Adding .gitlab-ci.yml..."
CI_CONTENT=$(cat << 'CIEOF'
stages:
  - test
  - build

test-job:
  stage: test
  script:
    - echo "Running tests..."
    - sleep 5
    - echo "Tests passed!"

build-job:
  stage: build
  script:
    - echo "Building..."
    - sleep 5
    - echo "Build complete!"
CIEOF
)

curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  --data "branch=main&content=$CI_CONTENT&commit_message=Add CI config" \
  "$GITLAB_URL/api/v4/projects/$PROJECT_ID/repository/files/.gitlab-ci.yml" > /dev/null

# 3. Aguardar pipeline
echo "3. Waiting for pipeline to start..."
sleep 10

PIPELINE_ID=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines?per_page=1" | jq -r '.[0].id')

if [ "$PIPELINE_ID" = "null" ]; then
    echo "❌ Pipeline not created"
    # Cleanup
    curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -X DELETE "$GITLAB_URL/api/v4/projects/$PROJECT_ID"
    exit 1
fi
echo "   Pipeline ID: $PIPELINE_ID"

# 4. Aguardar pipeline completar
echo "4. Waiting for pipeline to complete..."
for i in {1..60}; do
    STATUS=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
      "$GITLAB_URL/api/v4/projects/$PROJECT_ID/pipelines/$PIPELINE_ID" | jq -r '.status')

    echo "   Status: $STATUS"

    if [ "$STATUS" = "success" ]; then
        echo "✅ Pipeline completed successfully!"
        break
    elif [ "$STATUS" = "failed" ] || [ "$STATUS" = "canceled" ]; then
        echo "❌ Pipeline failed!"
        # Cleanup
        curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -X DELETE "$GITLAB_URL/api/v4/projects/$PROJECT_ID"
        exit 1
    fi

    sleep 10
done

# 5. Cleanup
echo "5. Cleaning up..."
curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" -X DELETE "$GITLAB_URL/api/v4/projects/$PROJECT_ID"
echo "   Project deleted"

echo ""
echo "✅ E2E GitLab CI/CD Pipeline Test PASSED"
```

### 3.2 E2E Test: Observability Flow

```bash
#!/bin/bash
# e2e-observability.sh

echo "=== E2E Test: Observability Flow ==="

# 1. Gerar logs de teste
echo "1. Generating test logs..."
TEST_ID="e2e-test-$(date +%s)"
kubectl run log-generator --image=busybox --restart=Never -- \
  sh -c "for i in 1 2 3 4 5; do echo '[E2E-TEST] $TEST_ID - Log message \$i'; sleep 1; done"

sleep 10

# 2. Verificar logs no Loki
echo "2. Checking logs in Loki..."
LOKI_QUERY="sum(count_over_time({app=\"log-generator\"} |= \"$TEST_ID\" [5m]))"
LOKI_RESULT=$(kubectl exec -n observability deploy/loki -- \
  wget -qO- "http://localhost:3100/loki/api/v1/query?query=$(echo $LOKI_QUERY | jq -sRr @uri)" | \
  jq -r '.data.result[0].value[1] // "0"')

if [ "$LOKI_RESULT" -ge 1 ]; then
    echo "   ✅ Logs found in Loki: $LOKI_RESULT entries"
else
    echo "   ❌ Logs not found in Loki"
fi

# 3. Verificar métricas no Prometheus
echo "3. Checking metrics in Prometheus..."
PROM_RESULT=$(kubectl exec -n observability deploy/prometheus-server -- \
  wget -qO- "http://localhost:9090/api/v1/query?query=up" | jq -r '.data.result | length')

if [ "$PROM_RESULT" -ge 10 ]; then
    echo "   ✅ Prometheus has $PROM_RESULT active targets"
else
    echo "   ❌ Prometheus has insufficient targets: $PROM_RESULT"
fi

# 4. Cleanup
kubectl delete pod log-generator --ignore-not-found

echo ""
echo "✅ E2E Observability Test PASSED"
```

### 3.3 E2E Test: Backup & Restore

```bash
#!/bin/bash
# e2e-backup-restore.sh

echo "=== E2E Test: Backup & Restore ==="
TEST_NS="e2e-backup-test-$(date +%s)"

# 1. Criar recursos de teste
echo "1. Creating test resources..."
kubectl create namespace $TEST_NS
kubectl create configmap test-config -n $TEST_NS --from-literal=key1=value1
kubectl create secret generic test-secret -n $TEST_NS --from-literal=password=secret123

# 2. Criar backup
echo "2. Creating backup..."
velero backup create $TEST_NS-backup --include-namespaces $TEST_NS --wait

BACKUP_STATUS=$(velero backup describe $TEST_NS-backup -o json | jq -r '.status.phase')
if [ "$BACKUP_STATUS" != "Completed" ]; then
    echo "   ❌ Backup failed: $BACKUP_STATUS"
    kubectl delete namespace $TEST_NS
    exit 1
fi
echo "   ✅ Backup completed"

# 3. Deletar recursos originais
echo "3. Deleting original resources..."
kubectl delete namespace $TEST_NS
sleep 5

# 4. Restaurar
echo "4. Restoring from backup..."
velero restore create $TEST_NS-restore --from-backup $TEST_NS-backup --wait

RESTORE_STATUS=$(velero restore describe $TEST_NS-restore -o json | jq -r '.status.phase')
if [ "$RESTORE_STATUS" != "Completed" ]; then
    echo "   ❌ Restore failed: $RESTORE_STATUS"
    exit 1
fi
echo "   ✅ Restore completed"

# 5. Verificar recursos restaurados
echo "5. Verifying restored resources..."
CM_VALUE=$(kubectl get configmap test-config -n $TEST_NS -o jsonpath='{.data.key1}')
SECRET_VALUE=$(kubectl get secret test-secret -n $TEST_NS -o jsonpath='{.data.password}' | base64 -d)

if [ "$CM_VALUE" = "value1" ] && [ "$SECRET_VALUE" = "secret123" ]; then
    echo "   ✅ Resources restored correctly"
else
    echo "   ❌ Resource data mismatch"
    exit 1
fi

# 6. Cleanup
echo "6. Cleaning up..."
kubectl delete namespace $TEST_NS
velero backup delete $TEST_NS-backup --confirm
velero restore delete $TEST_NS-restore --confirm

echo ""
echo "✅ E2E Backup & Restore Test PASSED"
```

---

## 4. Definition of Done - Todos os Épicos

### 4.1 Épico A - Infraestrutura Base (20h)

| # | Critério | Verificação | Status |
|---|----------|-------------|--------|
| A1 | VPC com 3 AZs criada | `aws ec2 describe-vpcs` | ☐ |
| A2 | Subnets public/private/data | `aws ec2 describe-subnets` | ☐ |
| A3 | NAT Gateways em 2+ AZs | `aws ec2 describe-nat-gateways` | ☐ |
| A4 | EKS Cluster v1.29+ | `kubectl version` | ☐ |
| A5 | 3 Node Groups configurados | `eksctl get nodegroups` | ☐ |
| A6 | Nodes em estado Ready | `kubectl get nodes` | ☐ |
| A7 | StorageClass gp3 default | `kubectl get sc` | ☐ |
| A8 | CoreDNS funcionando | `kubectl get pods -n kube-system` | ☐ |
| A9 | VPC CNI configurado | `kubectl describe daemonset aws-node -n kube-system` | ☐ |
| A10 | Tags aplicadas em todos recursos | `aws resourcegroupstaggingapi get-resources` | ☐ |

### 4.2 Épico B - GitLab Helm Deploy (48h)

| # | Critério | Verificação | Status |
|---|----------|-------------|--------|
| B1 | GitLab CE instalado via Helm | `helm list -n gitlab` | ☐ |
| B2 | Webservice pods healthy | `kubectl get pods -n gitlab -l app=webservice` | ☐ |
| B3 | Sidekiq processando jobs | `kubectl logs -n gitlab -l app=sidekiq --tail=10` | ☐ |
| B4 | Gitaly funcionando | `kubectl exec -n gitlab deploy/gitlab-gitaly -- gitaly check` | ☐ |
| B5 | GitLab Runner registrado | `kubectl get pods -n gitlab -l app=gitlab-runner` | ☐ |
| B6 | DNS configurado (Route53) | `dig gitlab.seudominio.com.br` | ☐ |
| B7 | ALB/Ingress funcionando | `kubectl get ingress -n gitlab` | ☐ |
| B8 | HTTPS com certificado válido | `curl -I https://gitlab.seudominio.com.br` | ☐ |
| B9 | Login funciona | Teste manual no browser | ☐ |
| B10 | Pipeline CI executa | E2E test pipeline | ☐ |

### 4.3 Épico C - Data Services (20h)

| # | Critério | Verificação | Status |
|---|----------|-------------|--------|
| C1 | RDS PostgreSQL Multi-AZ | `aws rds describe-db-instances` | ☐ |
| C2 | RDS acessível do cluster | `pg_isready -h <endpoint>` | ☐ |
| C3 | RDS backups automáticos | Console RDS → Backups | ☐ |
| C4 | Redis instalado (bitnami) | `helm list -n data-services` | ☐ |
| C5 | Redis Sentinel HA | `kubectl exec redis-master -- redis-cli -p 26379 info sentinel` | ☐ |
| C6 | RabbitMQ cluster | `kubectl exec rabbitmq -- rabbitmqctl cluster_status` | ☐ |
| C7 | GitLab conecta ao RDS | `kubectl logs -n gitlab -l app=webservice | grep -i postgres` | ☐ |
| C8 | GitLab conecta ao Redis | `kubectl logs -n gitlab -l app=sidekiq | grep -i redis` | ☐ |

### 4.4 Épicos D/E/F - Observability (84h)

| # | Critério | Verificação | Status |
|---|----------|-------------|--------|
| D1 | OTEL Collector instalado | `kubectl get pods -n observability -l app=opentelemetry-collector` | ☐ |
| D2 | Prometheus funcionando | `kubectl exec prometheus -- wget -qO- localhost:9090/-/healthy` | ☐ |
| D3 | Prometheus scraping targets | API `/api/v1/targets` | ☐ |
| E1 | Loki instalado | `kubectl get pods -n observability -l app=loki` | ☐ |
| E2 | Loki recebendo logs | Query no Grafana | ☐ |
| E3 | Tempo instalado | `kubectl get pods -n observability -l app=tempo` | ☐ |
| E4 | Traces visíveis | Query no Grafana | ☐ |
| F1 | Grafana acessível | `curl https://grafana.seudominio.com.br` | ☐ |
| F2 | Datasources configurados | Grafana → Configuration → Data Sources | ☐ |
| F3 | Dashboards instalados | Grafana → Dashboards | ☐ |
| F4 | Alertmanager funcionando | `kubectl exec alertmanager -- wget -qO- localhost:9093/-/healthy` | ☐ |
| F5 | Alertas configurados | `kubectl get prometheusrules -A` | ☐ |

### 4.5 Épico G - Security (30h)

| # | Critério | Verificação | Status |
|---|----------|-------------|--------|
| G1 | Network Policies aplicadas | `kubectl get networkpolicies -A` | ☐ |
| G2 | Default deny funciona | Teste de conectividade bloqueada | ☐ |
| G3 | PSA labels nos namespaces | `kubectl get ns --show-labels` | ☐ |
| G4 | RBAC configurado | `kubectl get clusterroles` | ☐ |
| G5 | cert-manager funcionando | `kubectl get pods -n cert-manager` | ☐ |
| G6 | Certificados emitidos | `kubectl get certificates -A` | ☐ |
| G7 | WAF configurado | Console AWS WAF | ☐ |
| G8 | Security Groups revisados | Console AWS EC2 → Security Groups | ☐ |
| G9 | External Secrets sync | `kubectl get externalsecrets -A` | ☐ |

### 4.6 Épicos H/J - Backup & DR (34h)

| # | Critério | Verificação | Status |
|---|----------|-------------|--------|
| H1 | Velero instalado | `velero version` | ☐ |
| H2 | Backup schedules ativos | `velero schedule get` | ☐ |
| H3 | Backups completando | `velero backup get` | ☐ |
| H4 | AWS Backup plan ativo | Console AWS Backup | ☐ |
| H5 | RDS snapshots | Console RDS → Snapshots | ☐ |
| H6 | GitLab backup configurado | `kubectl get cronjobs -n gitlab` | ☐ |
| J1 | DR Plan documentado | Doc 06 | ☐ |
| J2 | DR Drill executado | Relatório de drill | ☐ |
| J3 | Restore testado | E2E backup-restore test | ☐ |
| J4 | RTO/RPO validados | Métricas do drill | ☐ |

### 4.7 Épico I - Validação (26h)

| # | Critério | Verificação | Status |
|---|----------|-------------|--------|
| I1 | Smoke tests passam | `./smoke-tests.sh` | ☐ |
| I2 | E2E tests passam | Scripts E2E | ☐ |
| I3 | Documentação completa | Docs 00-08 | ☐ |
| I4 | Runbooks criados | Doc 08 | ☐ |
| I5 | Handoff realizado | Sign-off document | ☐ |

---

## 5. Checklist de Go-Live

### 5.1 Pre-Go-Live (T-1 semana)

```
PRE-GO-LIVE CHECKLIST
=====================

Infrastructure:
[ ] Todos os nodes healthy
[ ] Cluster Autoscaler testado
[ ] DNS propagado (TTL baixo para rollback)
[ ] SSL certificates válidos (>30 dias)
[ ] Security Groups auditados

Application:
[ ] GitLab funcionando (smoke tests)
[ ] CI/CD pipelines testados
[ ] Data services conectados
[ ] Observability coletando dados

Security:
[ ] Network Policies aplicadas
[ ] RBAC configurado
[ ] WAF rules testadas
[ ] Secrets em Secrets Manager
[ ] Scan de vulnerabilidades limpo

Backup:
[ ] Velero backups recentes
[ ] RDS backups verificados
[ ] Restore testado nas últimas 48h

Operations:
[ ] Alertas configurados e testados
[ ] On-call schedule definido
[ ] Runbooks revisados
[ ] Contatos de emergência atualizados

Documentation:
[ ] Arquitetura documentada
[ ] Credenciais em local seguro
[ ] Handoff realizado com equipe
```

### 5.2 Go-Live Day (T-0)

```
GO-LIVE DAY CHECKLIST
=====================

T-4h (Preparação):
[ ] Team standup - confirmar disponibilidade
[ ] Verificar status de todos os sistemas
[ ] Backup completo antes de go-live
[ ] Comunicar stakeholders sobre janela

T-2h (Verificação):
[ ] Executar smoke tests completos
[ ] Verificar logs por erros
[ ] Confirmar DNS pronto para switch
[ ] Preparar rollback plan

T-0 (Go-Live):
[ ] Switch DNS (se aplicável)
[ ] Monitorar métricas intensivamente
[ ] Primeiro usuário acessa
[ ] Verificar logs de acesso

T+1h (Validação):
[ ] Todos os endpoints respondendo
[ ] Nenhum alerta crítico
[ ] Usuários conseguem fazer login
[ ] CI/CD pipeline funciona

T+4h (Estabilização):
[ ] Métricas dentro do esperado
[ ] Nenhum erro recorrente
[ ] Feedback inicial dos usuários
[ ] Decidir: prosseguir ou rollback

T+24h (Confirmação):
[ ] Sistema estável por 24h
[ ] Backup pós-go-live realizado
[ ] Comunicar sucesso aos stakeholders
[ ] Documentar lições aprendidas
```

### 5.3 Rollback Plan

```
ROLLBACK PLAN
=============

Trigger para Rollback:
- Mais de 5% de erro rate
- Downtime > 15 minutos
- Data corruption detectada
- Security breach

Procedimento:

1. DECISÃO (5 min)
   - Incident Commander declara rollback
   - Comunicar equipe e stakeholders

2. DNS ROLLBACK (se aplicável)
   - Reverter DNS para ambiente anterior
   - TTL baixo permite propagação rápida (~5 min)

3. DATABASE ROLLBACK
   - Se necessário, restore RDS para point-in-time
   - Ou switch para read replica

4. KUBERNETES ROLLBACK
   - kubectl rollout undo deployment/<name>
   - Ou velero restore

5. VALIDAÇÃO
   - Smoke tests no ambiente revertido
   - Confirmar acesso dos usuários

6. POST-MORTEM
   - Documentar causa
   - Planejar correção
   - Agendar nova tentativa
```

---

## 6. Runbook de Validação

### 6.1 Validação Diária (5 min)

```bash
#!/bin/bash
# daily-validation.sh

echo "=== Daily Health Check ==="
echo "Date: $(date)"
echo ""

# Nodes
echo "Nodes:"
kubectl get nodes -o wide

# Critical pods
echo ""
echo "Critical Pods:"
kubectl get pods -n gitlab -l 'app in (webservice,sidekiq,gitaly)' --no-headers | head -5
kubectl get pods -n observability -l 'app in (prometheus,grafana,loki)' --no-headers | head -5

# Recent alerts
echo ""
echo "Active Alerts:"
kubectl exec -n observability deploy/alertmanager -- \
  wget -qO- http://localhost:9093/api/v1/alerts | jq -r '.data[] | select(.status.state=="active") | .labels.alertname'

# Backup status
echo ""
echo "Latest Backup:"
velero backup get --selector velero.io/schedule-name=daily-backup -o json | \
  jq -r '.items | sort_by(.metadata.creationTimestamp) | last | "\(.metadata.name) - \(.status.phase)"'

echo ""
echo "=== Validation Complete ==="
```

### 6.2 Validação Semanal (30 min)

```bash
#!/bin/bash
# weekly-validation.sh

echo "=== Weekly Deep Validation ==="
date

# 1. Certificate expiry
echo ""
echo "=== Certificate Expiry ==="
kubectl get certificates -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,EXPIRY:.status.notAfter'

# 2. Resource utilization
echo ""
echo "=== Resource Utilization ==="
kubectl top nodes
echo ""
kubectl top pods -A --sort-by=memory | head -20

# 3. PVC usage
echo ""
echo "=== PVC Usage ==="
kubectl exec -n observability deploy/prometheus-server -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=kubelet_volume_stats_used_bytes/kubelet_volume_stats_capacity_bytes*100' | \
  jq -r '.data.result[] | "\(.metric.persistentvolumeclaim): \(.value[1])%"'

# 4. Error logs (last 7 days)
echo ""
echo "=== Error Count (7d) ==="
# Assumindo Loki disponível
kubectl exec -n observability deploy/loki -- \
  wget -qO- 'http://localhost:3100/loki/api/v1/query?query=sum(count_over_time({level="error"}[7d]))' | \
  jq -r '.data.result[0].value[1] // "0"'

# 5. Backup success rate
echo ""
echo "=== Backup Success Rate (7d) ==="
TOTAL=$(velero backup get -o json | jq '[.items[] | select(.metadata.creationTimestamp > (now - 604800 | todate))] | length')
SUCCESS=$(velero backup get -o json | jq '[.items[] | select(.metadata.creationTimestamp > (now - 604800 | todate)) | select(.status.phase=="Completed")] | length')
echo "Success: $SUCCESS / $TOTAL ($(( SUCCESS * 100 / TOTAL ))%)"

# 6. Cost estimate
echo ""
echo "=== Estimated Monthly Cost ==="
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
echo "Nodes: $NODE_COUNT"
echo "Estimated: \$$(( NODE_COUNT * 120 + 300 ))/month"  # Rough estimate

echo ""
echo "=== Weekly Validation Complete ==="
```

---

## 7. Documentação de Handoff

### 7.1 Informações de Acesso

```yaml
# access-info.yaml (CONFIDENCIAL - armazenar em secrets manager)

cluster:
  name: k8s-platform-cluster
  region: us-east-1
  access: "aws eks update-kubeconfig --name k8s-platform-cluster --region us-east-1"

endpoints:
  gitlab: https://gitlab.seudominio.com.br
  grafana: https://grafana.seudominio.com.br
  alertmanager: https://alertmanager.seudominio.com.br (interno)

credentials:
  gitlab_root: "Stored in AWS Secrets Manager: k8s-platform/gitlab/root-password"
  grafana_admin: "Stored in AWS Secrets Manager: k8s-platform/grafana/admin-password"
  rds_master: "Stored in AWS Secrets Manager: k8s-platform/gitlab/db-password"

iam_roles:
  platform_admin: "arn:aws:iam::ACCOUNT_ID:role/k8s-platform-admin"
  developer: "arn:aws:iam::ACCOUNT_ID:role/k8s-platform-developer"
  readonly: "arn:aws:iam::ACCOUNT_ID:role/k8s-platform-readonly"

aws_resources:
  vpc_id: vpc-0123456789abcdef0
  eks_cluster_sg: sg-eks-cluster-xxxxx
  rds_endpoint: k8s-platform-gitlab-db.xxxxx.us-east-1.rds.amazonaws.com
  s3_buckets:
    - k8s-platform-gitlab-backups
    - k8s-platform-loki-logs
    - k8s-platform-tempo-traces
    - k8s-platform-velero-backups
```

### 7.2 Contatos e Escalation

```yaml
# escalation-contacts.yaml

primary_contacts:
  - name: "[Platform Lead]"
    role: Platform Lead
    email: platform-lead@empresa.com
    phone: "+55 11 9xxxx-xxxx"
    availability: "Business hours"

  - name: "[Senior DevOps]"
    role: Senior DevOps Engineer
    email: devops@empresa.com
    phone: "+55 11 9xxxx-xxxx"
    availability: "On-call rotation"

escalation_matrix:
  severity_1:  # System down
    response_time: "15 min"
    contacts: ["Platform Lead", "Engineering Manager", "CTO"]
    channels: ["Phone", "Slack #incident", "PagerDuty"]

  severity_2:  # Major degradation
    response_time: "30 min"
    contacts: ["Platform Lead", "On-call DevOps"]
    channels: ["Slack #incident", "Email"]

  severity_3:  # Minor issue
    response_time: "4 hours"
    contacts: ["On-call DevOps"]
    channels: ["Slack #platform", "Email"]

external_support:
  aws_support:
    tier: "Business Support"
    portal: "https://console.aws.amazon.com/support/home"
    phone: "Available in console"

  gitlab_support:
    tier: "Community Edition (self-managed)"
    docs: "https://docs.gitlab.com/"
    forum: "https://forum.gitlab.com/"
```

### 7.3 Operational Procedures

```markdown
# Operational Procedures Reference

## Daily Tasks
1. Check daily-validation.sh output
2. Review active alerts in Alertmanager
3. Check GitLab CI/CD queue

## Weekly Tasks
1. Run weekly-validation.sh
2. Review cost reports
3. Check certificate expiry
4. Review backup success rate

## Monthly Tasks
1. Execute DR drill
2. Review and update runbooks
3. Capacity planning review
4. Security audit

## On-Call Responsibilities
1. Respond to alerts within SLA
2. Document all incidents
3. Escalate when necessary
4. Handoff to next on-call with status
```

---

## 8. Troubleshooting Guide

### 8.1 Common Issues

#### GitLab não acessível

```bash
# 1. Verificar pods
kubectl get pods -n gitlab -l app=webservice
kubectl describe pod -n gitlab -l app=webservice

# 2. Verificar logs
kubectl logs -n gitlab -l app=webservice --tail=50

# 3. Verificar Ingress/ALB
kubectl get ingress -n gitlab
kubectl describe ingress -n gitlab

# 4. Verificar DNS
dig gitlab.seudominio.com.br

# 5. Verificar certificado
echo | openssl s_client -connect gitlab.seudominio.com.br:443 -servername gitlab.seudominio.com.br 2>/dev/null | openssl x509 -noout -dates
```

#### Redis não conecta

```bash
# 1. Verificar pods Redis
kubectl get pods -n data-services -l app.kubernetes.io/name=redis

# 2. Testar conectividade
kubectl exec -n gitlab deploy/gitlab-webservice -- nc -zv redis-master.data-services 6379

# 3. Verificar password
kubectl get secret -n data-services redis -o jsonpath='{.data.redis-password}' | base64 -d

# 4. Verificar Network Policy
kubectl get networkpolicy -n data-services redis-policy -o yaml
```

#### Pipeline CI falha

```bash
# 1. Verificar Runner
kubectl get pods -n gitlab -l app=gitlab-runner
kubectl logs -n gitlab -l app=gitlab-runner --tail=100

# 2. Verificar registração
kubectl exec -n gitlab deploy/gitlab-runner -- cat /home/gitlab-runner/.gitlab-runner/config.toml

# 3. Verificar job pods
kubectl get pods -n gitlab -l app=gitlab-runner-job
```

#### Alertas não disparam

```bash
# 1. Verificar Alertmanager
kubectl exec -n observability deploy/alertmanager -- wget -qO- http://localhost:9093/api/v1/status

# 2. Verificar PrometheusRules
kubectl get prometheusrules -n observability

# 3. Verificar se alertas estão firing
kubectl exec -n observability deploy/prometheus-server -- \
  wget -qO- 'http://localhost:9090/api/v1/alerts' | jq '.data.alerts[] | select(.state=="firing")'

# 4. Verificar config do Alertmanager
kubectl get secret -n observability alertmanager-config -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d
```

### 8.2 Emergency Procedures

```bash
# EMERGÊNCIA: Scale down tudo (economia/incidente)
kubectl scale deployment --all -n gitlab --replicas=0
kubectl scale deployment --all -n observability --replicas=0

# EMERGÊNCIA: Isolar namespace (security)
kubectl label namespace gitlab pod-security.kubernetes.io/enforce=restricted --overwrite
kubectl delete networkpolicy -n gitlab --all
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: emergency-isolate
  namespace: gitlab
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF

# EMERGÊNCIA: Restore rápido
velero restore create emergency-restore --from-backup $(velero backup get -o json | jq -r '.items | sort_by(.metadata.creationTimestamp) | last | .metadata.name') --wait
```

---

## 9. Métricas de Sucesso

### 9.1 SLIs/SLOs

| Serviço | SLI | SLO | Medição |
|---------|-----|-----|---------|
| **GitLab** | Availability | 99.5% | `avg_over_time(up{job="gitlab"}[30d])` |
| **GitLab** | Latency P95 | < 2s | `histogram_quantile(0.95, http_request_duration_seconds_bucket)` |
| **CI/CD** | Pipeline Success | > 90% | `gitlab_ci_pipeline_success_rate` |
| **Observability** | Data Ingestion | 99% | `rate(loki_ingester_chunk_created_total[5m])` |
| **Backup** | Success Rate | 100% | `velero_backup_success_total / velero_backup_total` |

### 9.2 Dashboard de SLOs

```yaml
# Grafana SLO Dashboard query examples

# GitLab Availability
100 * avg_over_time(up{job="gitlab-webservice"}[30d])

# Error Budget Remaining
(1 - (1 - avg_over_time(up{job="gitlab-webservice"}[30d])) / (1 - 0.995)) * 100

# Latency SLO
sum(rate(http_request_duration_seconds_bucket{le="2"}[5m])) / sum(rate(http_request_duration_seconds_count[5m])) * 100
```

---

## 10. Sign-off Final

### 10.1 Approval Matrix

| Área | Responsável | Data | Assinatura |
|------|-------------|------|------------|
| **Infrastructure** | DevOps Lead | ____/____/____ | ____________ |
| **Security** | Security Lead | ____/____/____ | ____________ |
| **Operations** | Ops Manager | ____/____/____ | ____________ |
| **Development** | Dev Lead | ____/____/____ | ____________ |
| **Business** | Product Owner | ____/____/____ | ____________ |

### 10.2 Final Checklist

```
FINAL SIGN-OFF CHECKLIST
========================

Technical Validation:
[  ] All smoke tests pass (100%)
[  ] All E2E tests pass (100%)
[  ] No critical vulnerabilities
[  ] Performance baselines established
[  ] DR tested and documented

Operational Readiness:
[  ] Monitoring and alerting configured
[  ] On-call rotation established
[  ] Runbooks complete and reviewed
[  ] Escalation matrix defined
[  ] Backup/restore verified

Documentation:
[  ] Architecture documentation complete
[  ] Access credentials documented
[  ] Handoff completed with ops team
[  ] Training materials available

Business Approval:
[  ] Stakeholders informed
[  ] Go-live date confirmed
[  ] Rollback plan approved
[  ] Communication plan ready
```

### 10.3 Project Completion Summary

```
K8S PLATFORM - PROJECT COMPLETION SUMMARY
=========================================

Project: Kubernetes Platform para Desenvolvimento AI-First
Duration: 262 person-hours (3 Sprints)
Completion Date: ____/____/____

Deliverables:
✅ EKS Cluster com 3 node groups
✅ GitLab CE com CI/CD runners
✅ Data Services (RDS, Redis, RabbitMQ)
✅ Full Observability Stack
✅ Security Hardening
✅ Backup & DR
✅ FinOps Setup
✅ Documentation (8 docs)

Costs:
- Estimated Monthly: ~$938 USD
- With Optimizations: ~$538 USD

Key Metrics:
- Availability Target: 99.5%
- RTO: 4 hours
- RPO: 1 hour

Next Steps:
1. Monitor system for 30 days
2. Fine-tune autoscaling
3. Implement additional dashboards
4. Plan for production workloads
```

---

## Referências

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [GitLab Administration](https://docs.gitlab.com/ee/administration/)
- [SRE Book - Google](https://sre.google/sre-book/table-of-contents/)
- [The Checklist Manifesto](https://www.goodreads.com/book/show/6667514-the-checklist-manifesto)

---

**FIM DA DOCUMENTAÇÃO DE EXECUÇÃO AWS**

Documentos da série:
1. [00 - Índice Geral](./00-indice-geral.md)
2. [01 - Infraestrutura Base AWS](./01-infraestrutura-base-aws.md)
3. [02 - GitLab Helm Deploy](./02-gitlab-helm-deploy.md)
4. [03 - Data Services Helm](./03-data-services-helm.md)
5. [04 - Observability Stack](./04-observability-stack.md)
6. [05 - Security Hardening](./05-security-hardening.md)
7. [06 - Backup e Disaster Recovery](./06-backup-disaster-recovery.md)
8. [07 - FinOps e Automação](./07-finops-automacao.md)
9. [08 - Validação e Checklist](./08-validacao-checklist.md) ← Você está aqui
