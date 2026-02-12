# 🚀 Plano de Execução — Quickstart MVP Completion

**Baseado**: [STATUS-2026-02-12.md](../STATUS-2026-02-12.md)
**Executor**: executor-terraform.md agent
**Objetivo**: Completar Quickstart MVP de 75% → 95%
**Duração Estimada**: 8h (5 tarefas)
**Padrões**: AML, STOP-AND-FIX, DocSync, Economia de Tokens

---

## 🎯 ANÁLISE INICIAL

### Identificação de Impacto

| Campo              | Valor                                                                    |
| ------------------ | ------------------------------------------------------------------------ |
| **Impacto**        | Alto (completa Quickstart MVP + valida stack E2E)                        |
| **Agentes**        | Orq, AWS, TF, Observability, FinOps, Performance                         |
| **Docs Envolvidos** | STATUS, architecture.md, costs.md, decisions.md, logbook                 |
| **Riscos**         | Node upgrade rolling replacement (1.75h), E2E app deploy (primeira vez) |
| **Rollback**       | Node: backup K8s state. GitLab: rollback Helm. E2E: delete NS           |

### Tarefas Pendentes

| #   | Task                         | Duração | Impacto   | Bloqueante | Docs Afetados                     |
| --- | ---------------------------- | ------- | --------- | ---------- | --------------------------------- |
| 1   | GitLab OIDC Integration      | 45min   | Médio     | Não        | logbook                           |
| 2   | Node Groups v1.34            | 1h30min | Alto      | Não        | architecture.md, logbook          |
| 3   | E2E Smoke Test App           | 3h      | Crítico   | Sim        | architecture.md, decisions.md     |
| 4   | FinOps Grafana Dashboards    | 2h      | Crítico   | Sim        | costs.md, decisions.md            |
| 5   | FinOps Automation Staging    | 1h      | Médio     | Não        | costs.md, architecture.md         |

**Total**: 8h5min
**MVP Completion após**: 95% (diferimento: Velero Marco 4)

---

## 📋 TASK #1 — GitLab OIDC Integration (45min)

### Objetivo
Destravar Helm release pending-upgrade + aplicar OIDC config via Terraform

### Agentes Necessários
- Orquestrador (lead)
- TF Specialist (Helm rollback + apply)
- Observability (validar pods GitLab)

### AML Configuration
```yaml
poll_interval: 15s
max_wait: 300s (Helm rollback)
recursos_relacionados: [gitlab-webservice-default, keycloak-http]
```

### Execução Detalhada

#### 1.1. Rollback Helm Pending-Upgrade (10min)

**Comando:**
```bash
helm rollback gitlab 1 -n gitlab-staging --wait --timeout=5m > /tmp/gitlab-rollback.log 2>&1 &
ROLLBACK_PID=$!
```

**AML Loop (ciclo 15s):**
```bash
while kill -0 $ROLLBACK_PID 2>/dev/null; do
  sleep 15
  # Tail log
  tail -10 /tmp/gitlab-rollback.log

  # Verificar pods
  kubectl get pods -n gitlab-staging | grep webservice

  # Events recentes
  kubectl get events -n gitlab-staging --sort-by='.lastTimestamp' | tail -5
done
```

**Validação:**
```bash
helm status gitlab -n gitlab-staging | grep -E "STATUS|REVISION"
# Expected: STATUS: deployed, REVISION: 1
```

**STOP-AND-FIX Checkpoint:**
- Se rollback falhar → investigar logs, verificar Helm lock (secret sh.helm.release)
- Se pods CrashLoop → verificar omniauth config, remover temporariamente

#### 1.2. Terraform Apply OIDC (20min)

**Comando:**
```bash
cd platform-provisioning/aws/kubernetes/terraform/environments/staging
terraform apply -target=module.keycloak_staging -target=module.gitlab_staging -auto-approve > /tmp/tf-apply-oidc.log 2>&1 &
TF_PID=$!
```

**AML Loop (ciclo 15s):**
```bash
CYCLE=0
LAST_RESOURCE=""
while kill -0 $TF_PID 2>/dev/null; do
  sleep 15
  CYCLE=$((CYCLE + 1))

  # Recurso atual TF
  CURRENT=$(tail -30 /tmp/tf-apply-oidc.log | grep -E "Creating|Modifying" | tail -1)
  if [ "$CURRENT" != "$LAST_RESOURCE" ]; then
    echo "[AML-C$CYCLE] $(date +%H:%M:%S) | TF: $CURRENT"
    LAST_RESOURCE="$CURRENT"
  fi

  # Pods GitLab
  PODS=$(kubectl get pods -n gitlab-staging | grep -c Running)
  PENDING=$(kubectl get pods -n gitlab-staging | grep -c Pending)
  ERROR=$(kubectl get pods -n gitlab-staging | grep -cE "Error|CrashLoop")
  echo "[AML-C$CYCLE] Pods: ${PODS}r/${PENDING}p/${ERROR}e"

  # Alerta se erro
  if [ $ERROR -gt 0 ]; then
    echo "⚠️ STOP-AND-FIX — Pod em erro detectado"
    kubectl get pods -n gitlab-staging --field-selector=status.phase!=Running
    break
  fi
done

wait $TF_PID
EXIT_CODE=$?
echo "TF Apply exit: $EXIT_CODE"
```

**Validação Idempotência:**
```bash
terraform plan -target=module.keycloak_staging -target=module.gitlab_staging
# Expected: "No changes. Your infrastructure matches the configuration."
```

**STOP-AND-FIX Checkpoint:**
- TF apply error → ler /tmp/tf-apply-oidc.log, identificar recurso falhando, corrigir .tf
- Pod error → kubectl logs, identificar config errada (issuer URL, client secret)

#### 1.3. E2E Test SSO (15min)

**Setup Port-Forward:**
```bash
kubectl port-forward -n gitlab-staging svc/gitlab-webservice-default 8080:8080 > /tmp/gitlab-pf.log 2>&1 &
PF_PID=$!
sleep 5
```

**Test SSO:**
```bash
# 1. Acessar http://localhost:8080
curl -I http://localhost:8080/users/sign_in | grep -E "HTTP|Location"

# 2. Verificar botão SSO presente (HTML grep)
curl -s http://localhost:8080/users/sign_in | grep -i "openid"
# Expected: "Sign in with OpenID Connect" button

# 3. Cleanup
kill $PF_PID
```

**Validação Manual:**
- Browser: http://localhost:8080 → click "Sign in with OpenID Connect"
- Redirect: http://keycloak.staging.internal/auth/realms/platform/...
- Login: test user (criar se necessário)
- Redirect back: GitLab authenticated

**Success Criteria:**
- [ ] Helm status: deployed (rev 1)
- [ ] TF apply: success, idempotent
- [ ] SSO button visible
- [ ] E2E login working

### DocSync (Obrigatório)

**Logbook Entry:**
```markdown
[HH:MM:SS] Task#1 Start | Orq | GitLab OIDC Integration | 45min estimado
[HH:MM:SS] Rollback Helm | TF | gitlab rev 1 | ✅ 8min
[HH:MM:SS] TF Apply | TF | OIDC modules | 🔄 PID=$TF_PID
[HH:MM:SS] AML-C1 | TF | module.gitlab_staging updating | ok
[HH:MM:SS] AML-C3 | TF | helm_release.gitlab modifying | Pods: 5r/0p/0e | ok
[HH:MM:SS] TF Apply Done | TF | 2 modified, exit 0 | ✅ 17min
[HH:MM:SS] Idempotence Check | TF | terraform plan "No changes" | ✅
[HH:MM:SS] E2E SSO Test | Orq | port-forward + curl | ✅ SSO button visible
[HH:MM:SS] DocSync | Orq | logbook | ✅
[HH:MM:SS] Task#1 Complete | ✅ 42min real
```

---

## 📋 TASK #2 — Node Groups Upgrade v1.34 (1h30min)

### Objetivo
Upgrade nodes de v1.31 → v1.34 (zero downtime, rolling replacement)

### Agentes Necessários
- Orquestrador (lead)
- AWS Specialist (node groups, ASG)
- TF Specialist (apply + AML)
- Observability (monitorar pods durante rolling)

### AML Configuration
```yaml
poll_interval: 20s (nodes upgrade is slow)
max_wait: 7200s (2h — 7 nodes × 15min each)
recursos_relacionados: [nodes, pods critical namespaces]
```

### Execução Detalhada

#### 2.1. Backup Pré-Upgrade (15min)

**Comando:**
```bash
DATE=$(date +%Y%m%d-%H%M%S)
mkdir -p /tmp/k8s-backup-$DATE

# Backup all resources
kubectl get all -A -o yaml > /tmp/k8s-backup-$DATE/all-resources.yaml

# Backup critical namespaces
for ns in gitlab-staging keycloak vault-system monitoring data-services; do
  kubectl get all,cm,secret,pvc -n $ns -o yaml > /tmp/k8s-backup-$DATE/ns-$ns.yaml
done

# Backup CRDs
kubectl get crd -o yaml > /tmp/k8s-backup-$DATE/crds.yaml

echo "Backup completo: /tmp/k8s-backup-$DATE/"
ls -lh /tmp/k8s-backup-$DATE/
```

**Success Criteria:**
- [ ] All backups criados (7 arquivos mínimo)
- [ ] Tamanho total >1MB (indicador de backup não vazio)

#### 2.2. Terraform Plan (10min)

**Comando:**
```bash
cd platform-provisioning/aws/kubernetes/terraform/environments/staging
terraform plan -var="cluster_version=1.34" -out=tfplan-node-upgrade
```

**Validação:**
```bash
# Expected: ~7 resources to modify (node group launch templates)
grep -E "modify|change" tfplan-node-upgrade
```

**STOP-AND-FIX Checkpoint:**
- Plan mostra destroy de node groups → BLOQUEIO (incorreto, deve ser modify)
- Plan mostra >10 resources → investigar drift, validar .tf

#### 2.3. Terraform Apply + Rolling Replacement (75min)

**Comando:**
```bash
terraform apply tfplan-node-upgrade > /tmp/tf-apply-nodes.log 2>&1 &
TF_PID=$!
START_TIME=$(date +%s)
```

**AML Loop Avançado (ciclo 20s):**
```bash
CYCLE=0
NODES_INITIAL=$(kubectl get nodes --no-headers | wc -l)

while kill -0 $TF_PID 2>/dev/null; do
  sleep 20
  CYCLE=$((CYCLE + 1))
  ELAPSED=$(($(date +%s) - START_TIME))

  # TF Progress
  TF_LATEST=$(tail -20 /tmp/tf-apply-nodes.log | grep -E "Creating|Modifying|Still" | tail -1)

  # Nodes status
  NODES_READY=$(kubectl get nodes --no-headers | grep -c Ready)
  NODES_NOTREADY=$(kubectl get nodes --no-headers | grep -vc Ready)
  NODES_V134=$(kubectl get nodes -o wide | grep -c v1.34)

  # Pods critical
  PODS_GITLAB=$(kubectl get pods -n gitlab-staging --no-headers | grep -c Running)
  PODS_KEYCLOAK=$(kubectl get pods -n keycloak --no-headers | grep -c Running)
  PODS_MONITORING=$(kubectl get pods -n monitoring --no-headers | grep -c Running)

  # Report compacto
  echo "[AML-C$CYCLE] ${ELAPSED}s | Nodes: ${NODES_READY}/${NODES_INITIAL} (v1.34: $NODES_V134) | Pods: GL=$PODS_GITLAB KC=$PODS_KEYCLOAK MON=$PODS_MONITORING"

  # Alerta se pods críticos caíram
  if [ $PODS_GITLAB -lt 3 ] || [ $PODS_KEYCLOAK -lt 1 ]; then
    echo "⚠️ WARNING — Pods críticos degradados"
    kubectl get pods -n gitlab-staging -n keycloak --field-selector=status.phase!=Running
  fi

  # Alerta stale (sem progresso por 5 ciclos = 100s)
  if [ $((CYCLE % 5)) -eq 0 ]; then
    if [ $NODES_V134 -eq $LAST_V134 ]; then
      echo "⚠️ STALE — Sem progresso em upgrade (v1.34 count: $NODES_V134)"
    fi
    LAST_V134=$NODES_V134
  fi
done

wait $TF_PID
EXIT_CODE=$?
TOTAL_TIME=$(($(date +%s) - START_TIME))
echo "TF Apply finalizado: exit $EXIT_CODE | ${TOTAL_TIME}s ($(($TOTAL_TIME/60))min)"
```

**STOP-AND-FIX Checkpoints:**

| Problema Detectado             | Diagnóstico                                          | Fix                                          |
| ------------------------------ | ---------------------------------------------------- | -------------------------------------------- |
| Node NotReady >5min            | kubectl describe node, verificar kubelet logs        | Cordon + drain + replace                     |
| Pod Pending >3min              | kubectl describe pod, verificar events               | Verificar resource requests vs node capacity |
| PVC multi-attach error         | Force delete pod anterior, aguardar PV detach        | kubectl delete pod --force --grace-period=0  |
| Node upgrade stuck             | ASG health check failing, verificar launch template  | AWS console: force instance replacement      |

#### 2.4. Validação Pós-Upgrade (10min)

**Comandos:**
```bash
# 1. Versão nodes
kubectl get nodes -o wide | awk '{print $1, $5}'
# Expected: All nodes v1.34.x-eks-*

# 2. Pods status (nenhum erro)
kubectl get pods -A | grep -vE "Running|Completed" | wc -l
# Expected: 0

# 3. GitLab accessible
kubectl port-forward -n gitlab-staging svc/gitlab-webservice-default 8080:8080 &
sleep 3
curl -I http://localhost:8080 | grep "HTTP/1.1 200"
pkill -f "port-forward.*gitlab"

# 4. Keycloak accessible
kubectl port-forward -n keycloak svc/keycloak-http 8081:80 &
sleep 3
curl -I http://localhost:8081/auth/ | grep "HTTP/1.1 200"
pkill -f "port-forward.*keycloak"

# 5. Idempotência TF
terraform plan -var="cluster_version=1.34"
# Expected: "No changes"
```

**Success Criteria:**
- [ ] Backup completo criado
- [ ] TF apply success (exit 0)
- [ ] All nodes v1.34.x
- [ ] All pods Running (0 errors)
- [ ] GitLab + Keycloak UI accessible
- [ ] TF plan idempotent

### DocSync (Obrigatório)

**architecture.md Update:**
```markdown
## EKS Cluster — k8s-platform-prod

| Campo           | Valor Anterior  | Valor Atual     | Atualizado    |
| --------------- | --------------- | --------------- | ------------- |
| Control Plane   | v1.34           | v1.34           | 2026-01-28    |
| Node Groups     | v1.31.13        | v1.34.x         | 2026-02-12    |
| Upgrade Method  | -               | Rolling replace | TF apply      |
| Downtime        | -               | Zero            | Validated E2E |
```

**Logbook Entry:**
```markdown
[HH:MM:SS] Task#2 Start | Orq | Node Groups v1.34 Upgrade | 1h30min estimado
[HH:MM:SS] Backup | Orq | K8s state all namespaces | ✅ 7 arquivos, 15MB total
[HH:MM:SS] TF Plan | TF | cluster_version=1.34 | ✅ 7 modify
[HH:MM:SS] TF Apply | TF | Iniciado PID=$TF_PID | 🔄
[HH:MM:SS] AML-C1 | AWS | Nodes: 7/7 (v1.34: 0) | Pods: GL=5 KC=1 MON=8 | ok
[HH:MM:SS] AML-C5 | AWS | Nodes: 6/7 (v1.34: 1) | system-0 replaced | ✅
[HH:MM:SS] AML-C12 | AWS | Nodes: 7/7 (v1.34: 3) | workloads-1 replacing | ok
[HH:MM:SS] AML-C25 | AWS | Nodes: 7/7 (v1.34: 7) | All upgraded | ✅
[HH:MM:SS] TF Apply Done | TF | 7 modified, exit 0 | ✅ 72min
[HH:MM:SS] Validation | Orq | Nodes + Pods + GitLab UI | ✅
[HH:MM:SS] DocSync | Orq | architecture.md, logbook | ✅
[HH:MM:SS] Task#2 Complete | ✅ 1h27min real
```

---

## 📋 TASK #3 — E2E Smoke Test App (3h)

### Objetivo
Deployar Python FastAPI app via GitLab CI/CD integrando PostgreSQL RDS, Redis, RabbitMQ, Loki, Tempo, Prometheus

### Agentes Necessários
- Orquestrador (lead)
- TF Specialist (infra app: namespace, secrets)
- Observability (validar logs→Loki, traces→Tempo, metrics→Prometheus)
- Performance (validar resource usage)

### AML Configuration
```yaml
poll_interval: 15s
max_wait: 600s (pipeline CI/CD)
recursos_relacionados: [app pods, GitLab pipeline, logs, traces, metrics]
```

### Execução Detalhada

#### 3.1. App Design (15min)

**Stack Validation App:**
```python
# app/main.py
from fastapi import FastAPI
import psycopg2, redis, pika, logging, random
from opentelemetry import trace, metrics
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

app = FastAPI()
FastAPIInstrumentor.instrument_app(app)
tracer = trace.get_tracer(__name__)
logger = logging.getLogger(__name__)

@app.get("/health")
def health():
    return {"status": "healthy"}

@app.get("/postgres")
def test_postgres():
    with tracer.start_as_current_span("postgres-query"):
        conn = psycopg2.connect(os.getenv("DATABASE_URL"))
        cur = conn.execute("SELECT version()")
        version = cur.fetchone()[0]
        logger.info(f"PostgreSQL version: {version}")
        return {"postgres": version}

@app.get("/redis")
def test_redis():
    with tracer.start_as_current_span("redis-cache"):
        r = redis.Redis.from_url(os.getenv("REDIS_URL"))
        key = f"test-{random.randint(1,1000)}"
        r.set(key, "value", ex=60)
        value = r.get(key)
        logger.info(f"Redis get: {key}={value}")
        return {"redis": key, "value": value.decode()}

@app.get("/rabbitmq")
def test_rabbitmq():
    with tracer.start_as_current_span("rabbitmq-publish"):
        conn = pika.BlockingConnection(pika.URLParameters(os.getenv("RABBITMQ_URL")))
        channel = conn.channel()
        channel.queue_declare("test-queue")
        channel.basic_publish("", "test-queue", f"msg-{random.randint(1,1000)}")
        logger.info("RabbitMQ message published")
        return {"rabbitmq": "message published"}

@app.get("/full-stack")
def test_full_stack():
    """Test all services + generate logs/traces/metrics"""
    results = {
        "postgres": test_postgres(),
        "redis": test_redis(),
        "rabbitmq": test_rabbitmq()
    }
    logger.info("Full stack test completed", extra={"results": results})
    return results
```

**GitLab CI Pipeline:**
```yaml
# .gitlab-ci.yml
stages:
  - build
  - deploy

build:
  stage: build
  image: docker:latest
  script:
    - docker build -t harbor.staging.internal/smoke-test/app:$CI_COMMIT_SHA .
    - docker push harbor.staging.internal/smoke-test/app:$CI_COMMIT_SHA

deploy:
  stage: deploy
  image: bitnami/kubectl:latest
  script:
    - kubectl set image deployment/smoke-test-app app=harbor.staging.internal/smoke-test/app:$CI_COMMIT_SHA -n smoke-test
    - kubectl rollout status deployment/smoke-test-app -n smoke-test --timeout=5m
```

**K8s Manifests:**
```yaml
# manifests/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: smoke-test-app
  namespace: smoke-test
  labels:
    app: smoke-test
spec:
  replicas: 2
  selector:
    matchLabels:
      app: smoke-test
  template:
    metadata:
      labels:
        app: smoke-test
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8000"
    spec:
      containers:
      - name: app
        image: harbor.staging.internal/smoke-test/app:latest
        ports:
        - containerPort: 8000
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: smoke-test-secrets
              key: database_url
        - name: REDIS_URL
          value: "redis://redis-rfr.data-services:6379/0"
        - name: RABBITMQ_URL
          valueFrom:
            secretKeyRef:
              name: smoke-test-secrets
              key: rabbitmq_url
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: "http://tempo-gateway.monitoring:4317"
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
---
apiVersion: v1
kind: Service
metadata:
  name: smoke-test-app
  namespace: smoke-test
spec:
  selector:
    app: smoke-test
  ports:
  - port: 80
    targetPort: 8000
```

#### 3.2. Terraform Infra Setup (30min)

**Module: smoke-test-app**
```hcl
# modules/smoke-test/main.tf
resource "kubernetes_namespace" "smoke_test" {
  metadata {
    name = "smoke-test"
    labels = {
      app = "smoke-test"
      monitoring = "enabled"
    }
  }
}

resource "kubernetes_secret" "smoke_test" {
  metadata {
    name      = "smoke-test-secrets"
    namespace = kubernetes_namespace.smoke_test.metadata[0].name
  }
  data = {
    database_url = "postgresql://${var.db_user}:${var.db_password}@${var.rds_endpoint}/smoke_test"
    rabbitmq_url = "amqp://${var.rabbitmq_user}:${var.rabbitmq_password}@rabbitmq.data-services:5672/"
  }
}

resource "kubectl_manifest" "smoke_test_deployment" {
  yaml_body = file("${path.module}/manifests/deployment.yaml")
  depends_on = [kubernetes_secret.smoke_test]
}

resource "kubectl_manifest" "servicemonitor" {
  yaml_body = <<-EOT
    apiVersion: monitoring.coreos.com/v1
    kind: ServiceMonitor
    metadata:
      name: smoke-test-app
      namespace: smoke-test
    spec:
      selector:
        matchLabels:
          app: smoke-test
      endpoints:
      - port: http
        interval: 30s
  EOT
}
```

**Comando TF Apply:**
```bash
cd platform-provisioning/aws/kubernetes/terraform/environments/staging
terraform apply -target=module.smoke_test_app -auto-approve > /tmp/tf-apply-smoke-test.log 2>&1 &
TF_PID=$!
```

**AML Loop:**
```bash
while kill -0 $TF_PID 2>/dev/null; do
  sleep 15
  tail -10 /tmp/tf-apply-smoke-test.log
  kubectl get all -n smoke-test
  kubectl get events -n smoke-test --sort-by='.lastTimestamp' | tail -5
done
```

**STOP-AND-FIX Checkpoint:**
- Namespace creation error → verificar RBAC TF provider
- Secret creation error → validar RDS/RabbitMQ credentials

#### 3.3. GitLab CI/CD Pipeline (60min)

**Create GitLab Project:**
```bash
# Via GitLab UI: Projects → New → smoke-test-app
# Push código:
git init
git remote add origin http://gitlab.staging.internal/platform/smoke-test-app.git
git add .
git commit -m "feat: initial smoke test app"
git push -u origin main
```

**Monitor Pipeline:**
```bash
# Port-forward GitLab
kubectl port-forward -n gitlab-staging svc/gitlab-webservice-default 8080:8080 &

# Watch pipeline via UI: http://localhost:8080/platform/smoke-test-app/-/pipelines

# Via CLI (alternativa):
gitlab-ci-multi-runner exec docker build
```

**STOP-AND-FIX Checkpoints:**

| Problema                   | Diagnóstico                       | Fix                                         |
| -------------------------- | --------------------------------- | ------------------------------------------- |
| Docker build error         | GitLab Runner logs                | Corrigir Dockerfile, verificar base image   |
| Harbor push unauthorized   | Registry credentials              | Configurar GitLab CI_REGISTRY_* vars        |
| Kubectl deploy permission  | Runner ServiceAccount RBAC        | Adicionar ClusterRole edit ao SA            |

#### 3.4. Validação Observability (45min)

**Logs → Loki:**
```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 &

# Query Loki via Grafana UI
# http://localhost:3000 → Explore → Loki
# Query: {namespace="smoke-test", app="smoke-test"}
# Expected: Ver logs "PostgreSQL version", "Redis get", "RabbitMQ message published"
```

**Traces → Tempo:**
```bash
# Grafana UI → Explore → Tempo
# Query: service.name="smoke-test-app"
# Expected: Ver traces postgres-query, redis-cache, rabbitmq-publish
# Latency: <100ms per span
```

**Metrics → Prometheus:**
```bash
# Grafana UI → Explore → Prometheus
# Query: rate(http_requests_total{namespace="smoke-test"}[5m])
# Expected: Ver métricas HTTP, CPU, memory
```

**Validação E2E:**
```bash
# Test endpoints
kubectl port-forward -n smoke-test svc/smoke-test-app 8000:80 &
sleep 3

curl http://localhost:8000/health
# Expected: {"status":"healthy"}

curl http://localhost:8000/postgres
# Expected: {"postgres":"PostgreSQL 16.4..."}

curl http://localhost:8000/redis
# Expected: {"redis":"test-123","value":"value"}

curl http://localhost:8000/rabbitmq
# Expected: {"rabbitmq":"message published"}

curl http://localhost:8000/full-stack
# Expected: JSON com results de todos os services

pkill -f "port-forward.*smoke-test"
```

#### 3.5. CoreDNS Split-Horizon Validation (30min)

**Test from Pod:**
```bash
# DNS resolution interno
kubectl run dns-test --image=nicolaka/netshoot --rm -it -- nslookup keycloak.staging.internal
# Expected: Resolve to ClusterIP 10.100.x.x

kubectl run dns-test --image=nicolaka/netshoot --rm -it -- nslookup gitlab.staging.internal
# Expected: Resolve to ClusterIP 10.100.x.x
```

**Test from Local Machine (requires split-horizon DNS):**
```bash
# Adicionar entries em /etc/hosts (workaround sem DNS público)
echo "10.100.150.200  keycloak.staging.internal" | sudo tee -a /etc/hosts
echo "10.100.180.50   gitlab.staging.internal" | sudo tee -a /etc/hosts

# Port-forward para simular DNS resolve
kubectl port-forward -n keycloak svc/keycloak-http 80:80 &
kubectl port-forward -n gitlab-staging svc/gitlab-webservice-default 8080:8080 &

# Test
curl http://keycloak.staging.internal/auth/
curl http://gitlab.staging.internal:8080/
```

**Success Criteria:**
- [ ] TF apply success (namespace + secrets + deployment)
- [ ] GitLab pipeline success (build + deploy)
- [ ] Pods Running (2 replicas smoke-test-app)
- [ ] All endpoints working (health, postgres, redis, rabbitmq, full-stack)
- [ ] Logs visible in Loki
- [ ] Traces visible in Tempo
- [ ] Metrics visible in Prometheus
- [ ] CoreDNS resolving *.staging.internal

### DocSync (Obrigatório)

**architecture.md Update:**
```markdown
## Smoke Test App — E2E Stack Validation

| Campo             | Valor                                                     |
| ----------------- | --------------------------------------------------------- |
| Adicionado        | 2026-02-12                                                |
| Namespace         | smoke-test                                                |
| Replicas          | 2                                                         |
| Integrations      | PostgreSQL RDS, Redis, RabbitMQ, Loki, Tempo, Prometheus |
| GitLab CI/CD      | Enabled (build + deploy)                                  |
| Observability     | Full (logs + traces + metrics)                            |
| Purpose           | Validate entire stack E2E                                 |
```

**decisions.md Update:**
```markdown
## ADR-054 — E2E Smoke Test App Design

| Campo        | Valor                                                                 |
| ------------ | --------------------------------------------------------------------- |
| Data         | 2026-02-12                                                            |
| Status       | executada                                                             |
| Contexto     | Necessário validar stack completo E2E (Quickstart MVP completion)     |
| Decisão      | Python FastAPI com integrações PostgreSQL/Redis/RabbitMQ + OTEL       |
| Alternativas | Go app (mais complexo), Node.js (menos usado no projeto)              |
| Resultado    | Validado: GitLab CI/CD, data services, observability full stack       |
```

**Logbook Entry:**
```markdown
[HH:MM:SS] Task#3 Start | Orq | E2E Smoke Test App | 3h estimado
[HH:MM:SS] App Design | Orq | FastAPI + PostgreSQL/Redis/RabbitMQ/OTEL | ✅ 15min
[HH:MM:SS] TF Infra | TF | NS + Secrets + Deployment | 🔄 PID=$TF_PID
[HH:MM:SS] TF Apply Done | TF | 4 added | ✅ 28min
[HH:MM:SS] GitLab Project | Orq | smoke-test-app created + push | ✅
[HH:MM:SS] GitLab Pipeline | Orq | build + deploy stages | 🔄 job-12345
[HH:MM:SS] Pipeline Build | CI | Docker image built + pushed Harbor | ✅ 8min
[HH:MM:SS] Pipeline Deploy | CI | kubectl rollout smoke-test-app | ✅ 3min
[HH:MM:SS] Validation Logs | Obs | Loki query namespace=smoke-test | ✅ logs flowing
[HH:MM:SS] Validation Traces | Obs | Tempo service=smoke-test-app | ✅ traces visible
[HH:MM:SS] Validation Metrics | Obs | Prometheus http_requests_total | ✅ metrics scraped
[HH:MM:SS] E2E Test | Orq | curl all endpoints | ✅ all working
[HH:MM:SS] DNS Test | Orq | nslookup *.staging.internal | ✅ resolving
[HH:MM:SS] DocSync | Orq | architecture.md, decisions.md, logbook | ✅
[HH:MM:SS] Task#3 Complete | ✅ 2h52min real
```

---

## 📋 TASK #4 — FinOps Grafana Dashboards (2h)

### Objetivo
Criar 3 dashboards Grafana: AWS Costs Overview, Resource Utilization, FinOps Alerts

### Agentes Necessários
- Orquestrador (lead)
- FinOps Specialist (métricas custo, alertas)
- Observability (Grafana datasources, queries)

### AML Configuration
```yaml
poll_interval: N/A (manual dashboard creation via UI)
recursos_relacionados: [Grafana ConfigMaps, dashboards JSON]
```

### Execução Detalhada

#### 4.1. Dashboard #1: AWS Costs Overview (45min)

**Datasource**: CloudWatch (AWS Billing metrics)

**Panels:**
1. **Monthly Cost Trend** (Graph)
   - Query: `sum by (ServiceName) (aws_billing_estimated_charges)`
   - Visualization: Time series stacked
   - Period: Last 3 months

2. **Cost Breakdown by Service** (Pie Chart)
   - Query: `aws_billing_estimated_charges{ServiceName!=""}`
   - Top 10 services

3. **Daily Cost** (Stat)
   - Query: `aws_billing_estimated_charges{Period="Daily"}`
   - Thresholds: <$30 green, $30-$50 yellow, >$50 red

4. **Savings Realized** (Table)
   - Manual entries (from costs.md):
     - EKS Upgrade: R$ 18.468/ano
     - EC2 Rightsizing: R$ 13.104/ano
     - RDS Shutdown: R$ 2.890/ano
     - **Total: R$ 34.462/ano**

5. **Cost Forecast** (Graph)
   - Linear regression baseado em últimos 30 dias
   - Projeção próximos 90 dias

**Export JSON:**
```bash
# Via Grafana API
curl -X GET "http://admin:prom-operator@localhost:3000/api/dashboards/uid/aws-costs-overview" > dashboards/aws-costs-overview.json
```

#### 4.2. Dashboard #2: Resource Utilization (45min)

**Datasource**: Prometheus

**Panels:**
1. **CPU Usage by Node** (Graph)
   - Query: `100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)`
   - Thresholds: >80% alert

2. **Memory Usage by Node** (Graph)
   - Query: `(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100`

3. **EBS Volumes Usage** (Table)
   - Query: `kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes * 100`
   - Sort by usage desc

4. **Pod CPU/Memory Requests vs Limits** (Graph)
   - Query: `sum(kube_pod_container_resource_requests{resource="cpu"}) / sum(kube_node_status_allocatable{resource="cpu"}) * 100`

5. **Network Throughput** (Graph)
   - Query: `rate(node_network_transmit_bytes_total[5m])`

6. **Overprovisioning Ratio** (Stat)
   - Query: `(sum(kube_pod_container_resource_requests) - sum(container_memory_usage_bytes)) / sum(kube_pod_container_resource_requests) * 100`

**Export JSON:**
```bash
curl -X GET "http://admin:prom-operator@localhost:3000/api/dashboards/uid/resource-utilization" > dashboards/resource-utilization.json
```

#### 4.3. Dashboard #3: FinOps Alerts (30min)

**Datasource**: Prometheus + CloudWatch

**Panels:**
1. **Budget Threshold** (Gauge)
   - Query: `aws_billing_estimated_charges{ServiceName="AmazonEKS"} / 896 * 100` (monthly budget $896)
   - Thresholds: <80% green, 80-95% yellow, >95% red

2. **Cost Spike Detection** (Graph)
   - Query: `increase(aws_billing_estimated_charges[1h]) > 5`

3. **Orphan Resources** (Table)
   - EBS volumes available >7d (manual query AWS CLI + import)
   - Load Balancers sem target groups

4. **Idle Resources** (Table)
   - Pods CPU <5% por >24h
   - PVCs not mounted >7d

5. **Active Alerts** (Alert List)
   - From Prometheus AlertManager
   - Filter: severity=~"warning|critical", alertname=~".*Cost.*"

**Export JSON:**
```bash
curl -X GET "http://admin:prom-operator@localhost:3000/api/dashboards/uid/finops-alerts" > dashboards/finops-alerts.json
```

#### 4.4. Terraform Codify Dashboards (30min)

**ConfigMap per Dashboard:**
```hcl
# modules/observability/dashboards.tf
resource "kubernetes_config_map" "grafana_dashboard_aws_costs" {
  metadata {
    name      = "grafana-dashboard-aws-costs"
    namespace = "monitoring"
    labels = {
      grafana_dashboard = "1"
    }
  }
  data = {
    "aws-costs-overview.json" = file("${path.module}/dashboards/aws-costs-overview.json")
  }
}

resource "kubernetes_config_map" "grafana_dashboard_resource_util" {
  metadata {
    name      = "grafana-dashboard-resource-utilization"
    namespace = "monitoring"
    labels = {
      grafana_dashboard = "1"
    }
  }
  data = {
    "resource-utilization.json" = file("${path.module}/dashboards/resource-utilization.json")
  }
}

resource "kubernetes_config_map" "grafana_dashboard_finops_alerts" {
  metadata {
    name      = "grafana-dashboard-finops-alerts"
    namespace = "monitoring"
    labels = {
      grafana_dashboard = "1"
    }
  }
  data = {
    "finops-alerts.json" = file("${path.module}/dashboards/finops-alerts.json")
  }
}
```

**Apply:**
```bash
terraform apply -target=module.observability.kubernetes_config_map.grafana_dashboard_aws_costs \
                -target=module.observability.kubernetes_config_map.grafana_dashboard_resource_util \
                -target=module.observability.kubernetes_config_map.grafana_dashboard_finops_alerts
```

**Validation:**
```bash
# Grafana auto-detect dashboards via sidecar
kubectl logs -n monitoring kube-prometheus-stack-grafana-0 -c grafana-sc-dashboard | grep -i "dashboard.*added"

# Access Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 &
# http://localhost:3000 → Dashboards → AWS Costs Overview, Resource Utilization, FinOps Alerts
```

**Success Criteria:**
- [ ] Dashboard AWS Costs Overview criado (5 panels)
- [ ] Dashboard Resource Utilization criado (6 panels)
- [ ] Dashboard FinOps Alerts criado (5 panels)
- [ ] Dashboards exportados JSON
- [ ] Terraform ConfigMaps aplicados
- [ ] Dashboards visíveis in Grafana UI

### DocSync (Obrigatório)

**costs.md Update:**
```markdown
## FinOps Grafana Dashboards

| Dashboard             | URL                                            | Panels | Adicionado |
| --------------------- | ---------------------------------------------- | ------ | ---------- |
| AWS Costs Overview    | /d/aws-costs-overview                          | 5      | 2026-02-12 |
| Resource Utilization  | /d/resource-utilization                        | 6      | 2026-02-12 |
| FinOps Alerts         | /d/finops-alerts                               | 5      | 2026-02-12 |

**Métricas Monitoradas:**
- Monthly AWS costs (billing)
- Cost breakdown by service
- Savings realized (R$ 34.462/ano)
- CPU/Memory utilization per node
- Overprovisioning ratio
- Budget threshold alerts
- Orphan/idle resource detection
```

**decisions.md Update:**
```markdown
## ADR-055 — FinOps Observability via Grafana

| Campo        | Valor                                                                |
| ------------ | -------------------------------------------------------------------- |
| Data         | 2026-02-12                                                           |
| Status       | executada                                                            |
| Contexto     | Necessário visibilidade de custos AWS em tempo real (FinOps MVP)     |
| Decisão      | 3 dashboards Grafana: AWS Costs, Resource Util, FinOps Alerts        |
| Datasources  | CloudWatch (billing) + Prometheus (resource metrics)                 |
| Alternativa  | AWS Cost Explorer (limitado), Kubecost (licença), CloudHealth ($$$)  |
| Resultado    | Dashboards operacionais, economia R$ 34k/ano visível, alerts ativos  |
```

**Logbook Entry:**
```markdown
[HH:MM:SS] Task#4 Start | Orq + FinOps | Grafana FinOps Dashboards | 2h estimado
[HH:MM:SS] Dashboard#1 | FinOps | AWS Costs Overview (5 panels) | ✅ 42min
[HH:MM:SS] Dashboard#2 | FinOps | Resource Utilization (6 panels) | ✅ 48min
[HH:MM:SS] Dashboard#3 | FinOps | FinOps Alerts (5 panels) | ✅ 28min
[HH:MM:SS] Export JSON | Orq | 3 dashboards exported | ✅
[HH:MM:SS] TF ConfigMaps | TF | 3 ConfigMaps created | ✅ 12min
[HH:MM:SS] Validation | Obs | Dashboards visible Grafana UI | ✅
[HH:MM:SS] DocSync | Orq | costs.md, decisions.md, logbook | ✅
[HH:MM:SS] Task#4 Complete | ✅ 2h5min real
```

---

## 📋 TASK #5 — FinOps Automation Staging (1h)

### Objetivo
Implementar automação FinOps: cleanup orphan resources, cost reporting, resource tagging

### Agentes Necessários
- Orquestrador (lead)
- FinOps Specialist (scripts cleanup, tagging strategy)
- AWS Specialist (IAM permissions, Lambda/EventBridge)

### AML Configuration
```yaml
poll_interval: N/A (scripts execution + TF apply)
recursos_relacionados: [Lambda functions, EventBridge rules, S3 buckets]
```

### Execução Detalhada

#### 5.1. Cleanup Automation (30min)

**Script: cleanup-orphan-resources.sh**
```bash
#!/bin/bash
# scripts/finops/cleanup-orphan-resources.sh

set -euo pipefail

REGION="us-east-1"
DRY_RUN="${DRY_RUN:-true}"

echo "🔍 Scanning orphan resources (region: $REGION, dry-run: $DRY_RUN)"

# 1. EBS volumes available >7d
echo "=== EBS Volumes Available >7d ==="
ORPHAN_VOLUMES=$(aws ec2 describe-volumes --region $REGION \
  --filters "Name=status,Values=available" \
  --query "Volumes[?CreateTime<='$(date -d '7 days ago' --iso-8601)'].{ID:VolumeId,Size:Size,Created:CreateTime}" \
  --output json)

COUNT=$(echo $ORPHAN_VOLUMES | jq '. | length')
echo "Found: $COUNT volumes"

if [ "$DRY_RUN" = "false" ] && [ $COUNT -gt 0 ]; then
  echo $ORPHAN_VOLUMES | jq -r '.[].ID' | while read VOL; do
    echo "Deleting volume: $VOL"
    aws ec2 delete-volume --volume-id $VOL --region $REGION
  done
fi

# 2. Snapshots >30d sem AMI associado
echo "=== EBS Snapshots Old (>30d) ==="
ORPHAN_SNAPSHOTS=$(aws ec2 describe-snapshots --owner-ids self --region $REGION \
  --query "Snapshots[?StartTime<='$(date -d '30 days ago' --iso-8601)' && !Description~='Created by CreateImage'].{ID:SnapshotId,Size:VolumeSize,Created:StartTime}" \
  --output json)

COUNT=$(echo $ORPHAN_SNAPSHOTS | jq '. | length')
echo "Found: $COUNT snapshots"

if [ "$DRY_RUN" = "false" ] && [ $COUNT -gt 0 ]; then
  echo $ORPHAN_SNAPSHOTS | jq -r '.[].ID' | while read SNAP; do
    echo "Deleting snapshot: $SNAP"
    aws ec2 delete-snapshot --snapshot-id $SNAP --region $REGION
  done
fi

# 3. Load Balancers sem target groups
echo "=== Load Balancers sem targets ==="
aws elbv2 describe-load-balancers --region $REGION --query "LoadBalancers[*].LoadBalancerArn" --output text | while read LB_ARN; do
  TARGETS=$(aws elbv2 describe-target-groups --load-balancer-arn $LB_ARN --query "TargetGroups | length(@)" --output text 2>/dev/null || echo 0)
  if [ "$TARGETS" = "0" ]; then
    echo "LB sem targets: $LB_ARN"
    if [ "$DRY_RUN" = "false" ]; then
      aws elbv2 delete-load-balancer --load-balancer-arn $LB_ARN --region $REGION
    fi
  fi
done

echo "✅ Cleanup scan complete (dry-run: $DRY_RUN)"
```

**Lambda Function:**
```python
# lambda/finops-cleanup.py
import boto3, os, json
from datetime import datetime, timedelta

def lambda_handler(event, context):
    ec2 = boto3.client('ec2', region_name='us-east-1')

    # EBS volumes available >7d
    cutoff = (datetime.now() - timedelta(days=7)).isoformat()
    volumes = ec2.describe_volumes(
        Filters=[{'Name': 'status', 'Values': ['available']}]
    )['Volumes']

    orphans = [v for v in volumes if v['CreateTime'].isoformat() <= cutoff]

    for vol in orphans:
        print(f"Deleting orphan volume: {vol['VolumeId']}")
        ec2.delete_volume(VolumeId=vol['VolumeId'])

    return {
        'statusCode': 200,
        'body': json.dumps({
            'deleted_volumes': len(orphans),
            'savings_monthly': len(orphans) * 8  # gp3 $0.08/GB
        })
    }
```

**Terraform Deploy:**
```hcl
# modules/finops/cleanup-automation.tf
resource "aws_lambda_function" "finops_cleanup" {
  filename      = "${path.module}/lambda/finops-cleanup.zip"
  function_name = "finops-cleanup-orphan-resources"
  role          = aws_iam_role.finops_cleanup.arn
  handler       = "finops-cleanup.lambda_handler"
  runtime       = "python3.11"
  timeout       = 300

  environment {
    variables = {
      DRY_RUN = "false"
      REGION  = "us-east-1"
    }
  }
}

resource "aws_cloudwatch_event_rule" "finops_cleanup_daily" {
  name                = "finops-cleanup-daily"
  description         = "Run finops cleanup daily 2am UTC"
  schedule_expression = "cron(0 2 * * ? *)"
}

resource "aws_cloudwatch_event_target" "finops_cleanup" {
  rule      = aws_cloudwatch_event_rule.finops_cleanup_daily.name
  target_id = "FinOpsCleanupLambda"
  arn       = aws_lambda_function.finops_cleanup.arn
}
```

#### 5.2. Cost Reporting (15min)

**Script: weekly-cost-report.sh**
```bash
#!/bin/bash
# scripts/finops/weekly-cost-report.sh

REGION="us-east-1"
START_DATE=$(date -d '7 days ago' +%Y-%m-%d)
END_DATE=$(date +%Y-%m-%d)
OUTPUT="reports/aws-costs/weekly-$(date +%Y-%m-%d).json"

echo "📊 Generating weekly cost report ($START_DATE to $END_DATE)"

aws ce get-cost-and-usage --region us-east-1 \
  --time-period Start=$START_DATE,End=$END_DATE \
  --granularity DAILY \
  --metrics "UnblendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE \
  --output json > $OUTPUT

# Summary
TOTAL=$(jq '.ResultsByTime[].Total.UnblendedCost.Amount | tonumber' $OUTPUT | awk '{s+=$1} END {print s}')
echo "Total week cost: \$$TOTAL"

# Top 5 services
echo "Top 5 services:"
jq -r '.ResultsByTime[].Groups[] | "\(.Keys[0]): $\(.Metrics.UnblendedCost.Amount)"' $OUTPUT \
  | awk '{arr[$1]+=$2} END {for (i in arr) print i, arr[i]}' \
  | sort -t$ -k2 -nr \
  | head -5
```

#### 5.3. Resource Tagging (15min)

**Tagging Strategy:**
```hcl
# modules/common/tags.tf
locals {
  common_tags = {
    Environment  = var.environment
    ManagedBy    = "Terraform"
    Project      = "K8s-Platform"
    CostCenter   = "Engineering"
    Owner        = "Platform-Team"
    Backup       = var.backup_enabled ? "true" : "false"
  }
}

# Apply to all resources
resource "aws_eks_cluster" "main" {
  # ...
  tags = merge(local.common_tags, {
    Component = "EKS-Control-Plane"
  })
}
```

**Retroactive Tagging Script:**
```bash
#!/bin/bash
# scripts/finops/apply-tags.sh

REGION="us-east-1"

# Tag all EBS volumes
aws ec2 describe-volumes --region $REGION --query "Volumes[*].VolumeId" --output text | while read VOL; do
  aws ec2 create-tags --resources $VOL --region $REGION \
    --tags Key=Environment,Value=staging Key=ManagedBy,Value=Terraform Key=CostCenter,Value=Engineering
done

# Tag all EKS node groups
aws eks list-nodegroups --cluster-name k8s-platform-prod --region $REGION --query "nodegroups" --output text | while read NG; do
  aws eks tag-resource --resource-arn $(aws eks describe-nodegroup --cluster-name k8s-platform-prod --nodegroup-name $NG --query "nodegroup.nodegroupArn" --output text) \
    --tags Environment=staging,ManagedBy=Terraform,CostCenter=Engineering
done
```

**Success Criteria:**
- [ ] Lambda finops-cleanup deployed
- [ ] EventBridge rule daily 2am configured
- [ ] Weekly cost report script executado
- [ ] Resource tagging script executado
- [ ] 100% recursos critical tags (Environment, ManagedBy, CostCenter)

### DocSync (Obrigatório)

**costs.md Update:**
```markdown
## FinOps Automation

| Automation              | Frequency | Savings/ano | Status     |
| ----------------------- | --------- | ----------- | ---------- |
| Orphan EBS cleanup      | Daily 2am | R$ 2.106    | ✅ Ativo   |
| Old snapshots cleanup   | Daily 2am | R$ 800      | ✅ Ativo   |
| Idle LB cleanup         | Weekly    | R$ 1.952    | ✅ Ativo   |
| Weekly cost report      | Monday 9am| -           | ✅ Ativo   |
| Resource tagging        | On-demand | -           | ✅ 100%    |

**Total Savings Automation:** R$ 4.858/ano
```

**architecture.md Update:**
```markdown
## FinOps Automation Components

| Component                  | Type              | Schedule    | Purpose                        |
| -------------------------- | ----------------- | ----------- | ------------------------------ |
| finops-cleanup Lambda      | AWS Lambda Python | Daily 2am   | Delete orphan EBS, snapshots, LBs |
| weekly-cost-report script  | Bash + AWS CLI    | Monday 9am  | Generate cost report JSON      |
| apply-tags script          | Bash + AWS CLI    | On-demand   | Retroactive resource tagging   |
```

**Logbook Entry:**
```markdown
[HH:MM:SS] Task#5 Start | Orq + FinOps | FinOps Automation Staging | 1h estimado
[HH:MM:SS] Script Cleanup | FinOps | cleanup-orphan-resources.sh | ✅ created
[HH:MM:SS] Lambda Deploy | TF | finops-cleanup function | 🔄 PID=$TF_PID
[HH:MM:SS] TF Apply Done | TF | Lambda + EventBridge rule | ✅ 18min
[HH:MM:SS] Test Lambda | FinOps | Manual invoke test | ✅ 3 volumes deleted
[HH:MM:SS] Script Report | FinOps | weekly-cost-report.sh | ✅ generated
[HH:MM:SS] Script Tagging | FinOps | apply-tags.sh dry-run | ✅ 127 resources
[HH:MM:SS] Tagging Apply | FinOps | apply-tags.sh execute | ✅ 127 tagged
[HH:MM:SS] DocSync | Orq | costs.md, architecture.md, logbook | ✅
[HH:MM:SS] Task#5 Complete | ✅ 58min real
```

---

## 🎯 CRITÉRIOS DE SUCESSO GLOBAL

### MVP Completion Target: 95%

| Critério                                | Status | Validação                                      |
| --------------------------------------- | ------ | ---------------------------------------------- |
| GitLab OIDC SSO funcional               | ⏸️     | E2E login test via browser                     |
| Nodes all v1.34.x                       | ⏸️     | kubectl get nodes -o wide                      |
| E2E app deployed via GitLab CI/CD       | ⏸️     | Pipeline success + pods Running                |
| Logs flowing to Loki                    | ⏸️     | Grafana Explore query namespace=smoke-test     |
| Traces flowing to Tempo                 | ⏸️     | Grafana Explore service=smoke-test-app         |
| Metrics scraped by Prometheus           | ⏸️     | Prometheus targets smoke-test-app UP           |
| FinOps dashboards operational           | ⏸️     | 3 dashboards visible in Grafana                |
| FinOps automation active                | ⏸️     | Lambda triggered daily, weekly report generated |
| CoreDNS split-horizon working           | ⏸️     | nslookup *.staging.internal from pod           |
| All docs synchronized                   | ⏸️     | architecture.md + costs.md + decisions.md updated |

### Rollback Plan Global

| Task                      | Rollback Command                                                          | Duration |
| ------------------------- | ------------------------------------------------------------------------- | -------- |
| GitLab OIDC               | `helm rollback gitlab 1 -n gitlab-staging`                                | 5min     |
| Node Groups v1.34         | Restore from backup: `kubectl apply -f /tmp/k8s-backup-*/`                | 30min    |
| E2E App                   | `kubectl delete ns smoke-test`                                            | 2min     |
| FinOps Dashboards         | `kubectl delete cm -n monitoring -l grafana_dashboard=1`                  | 1min     |
| FinOps Automation         | `terraform destroy -target=module.finops.aws_lambda_function.finops_cleanup` | 5min     |

---

## 📊 ECONOMIA DE TOKENS — FORMATO RESPOSTA EXECUTOR

### Report Compacto por Task (máx 10 linhas/task)

```
TASK#1 GitLab OIDC | ✅ 42min | Helm rollback rev1 + TF apply OIDC + E2E test OK
TASK#2 Nodes v1.34 | ✅ 1h27min | TF apply rolling replace, 7 nodes upgraded, zero downtime
TASK#3 E2E App | ✅ 2h52min | FastAPI deployed GitLab CI/CD, logs/traces/metrics validated
TASK#4 FinOps Dashboards | ✅ 2h5min | 3 dashboards (costs, utilization, alerts) operational
TASK#5 FinOps Automation | ✅ 58min | Lambda cleanup daily, tagging 100%, weekly report active
---
MVP Completion: 75% → 95% | Total: 7h64min | Quickstart COMPLETO (Velero diferido Marco4)
DocSync: ✅ architecture.md, costs.md, decisions.md, logbook (5 tasks)
```

### Logbook Consolidado (append ao arquivo existente)

```markdown
# 📓 Diário de Bordo — Quickstart MVP Completion

| Campo       | Valor                                  |
| ----------- | -------------------------------------- |
| **Data**    | 2026-02-12                             |
| **Demanda** | Completar Quickstart MVP 75% → 95%     |
| **Impacto** | Alto (valida stack completo E2E)       |
| **Agentes** | Orq, AWS, TF, Obs, FinOps, Performance |
| **Status**  | Concluído ✅                           |

---

## Timeline

[13:00:00] Análise | Orq | Quickstart MVP Completion (5 tasks, 8h) | impacto: alto
[13:00:30] Consenso | Orq,AWS,TF,Obs,FinOps | Aprovado | ✅
[13:01:00] Task#1 Start | GitLab OIDC Integration
[13:43:00] Task#1 Complete | ✅ 42min
[13:43:30] Task#2 Start | Node Groups v1.34 Upgrade
[15:10:30] Task#2 Complete | ✅ 1h27min
[15:11:00] Task#3 Start | E2E Smoke Test App
[18:03:00] Task#3 Complete | ✅ 2h52min
[18:03:30] Task#4 Start | FinOps Grafana Dashboards
[20:08:30] Task#4 Complete | ✅ 2h5min
[20:09:00] Task#5 Start | FinOps Automation Staging
[21:07:00] Task#5 Complete | ✅ 58min
[21:07:30] DocSync Final | Orq | architecture.md, costs.md, decisions.md | ✅
[21:08:00] MVP Complete | 95% | Quickstart MVP COMPLETO | ✅ 8h8min total
```

---

## 🛑 STOP-AND-FIX PROTOCOL — PRINCIPAIS CHECKPOINTS

### Problemas Prováveis por Task

| Task                      | Problema Provável                   | Diagnóstico                          | Fix                                   |
| ------------------------- | ----------------------------------- | ------------------------------------ | ------------------------------------- |
| GitLab OIDC               | Helm pending-upgrade travado        | helm history gitlab                  | helm rollback ou delete secret        |
| Node v1.34                | Node NotReady pós-replace           | kubectl describe node                | Cordon + drain + replace instance     |
| E2E App                   | Pipeline build fail                 | GitLab Runner logs                   | Corrigir Dockerfile                   |
| E2E App                   | Pod CrashLoop                       | kubectl logs smoke-test-app          | Fix env vars (DATABASE_URL, etc)      |
| E2E Observability         | Logs não aparecem Loki              | kubectl logs fluent-bit              | Verificar Loki endpoint, auth         |
| E2E Observability         | Traces não aparecem Tempo           | curl OTLP endpoint                   | Verificar OTEL_EXPORTER_OTLP_ENDPOINT |
| FinOps Dashboards         | Dashboard não carrega               | kubectl logs grafana sidecar         | Verificar ConfigMap label             |
| FinOps Automation         | Lambda permission denied            | CloudWatch Logs                      | Ajustar IAM role policy               |

### Compactação de Contexto (CTX-COMPACT)

Quando STOP-AND-FIX ativado:
1. Salvar snapshot: task atual, recursos criados, plano restante
2. Reduzir contexto: só arquivos/módulos do problema
3. Análise paralela agentes (AWS + TF + Obs simultaneamente)
4. Fix definitivo (causa raiz, não sintoma)
5. DocSync obrigatório (risks.md + logbook)
6. CTX-RESTORE: re-ler docs, freshness check, retomar

---

## 📂 VALIDAÇÃO ESTRUTURA (Obrigatório Pré-Execução)

```bash
# Antes de iniciar Task#1
bash scripts/validate-project-structure.sh
# Expected: 0 violações

# Se violações → corrigir antes de prosseguir
# Registrar: [HH:MM:SS] Validação | Orq | Estrutura validada | ✅
```

---

**Criado**: 2026-02-12 14:30 BRT
**Baseado**: executor-terraform.md v1.0 + STATUS-2026-02-12.md
**Executor**: Orquestrador DevOps Sênior (executor-terraform agent)
**Próxima Ação**: Executar Task#1 (GitLab OIDC Integration)
