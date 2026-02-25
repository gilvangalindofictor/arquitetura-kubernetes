# Plano de Trabalho — 2026-02-12 (Quarta-feira)

## 🎯 Objetivos do Dia

1. **Finalizar GitLab OIDC Integration** (5% restante - 45min)
2. **Fechar Marco 2 Sprint 3** (2% restante - 1h)
3. **Iniciar Marco 3 Sprint 4** (Backup/DR - 2h)

**Tempo Total Estimado**: 3h45min

---

## 🔴 PRIORIDADE 1: GitLab OIDC (45min) - FINALIZAR HOJE

### Status Atual
- ✅ CoreDNS split-horizon DNS ativo
- ✅ Keycloak client criado (secret: `<STORED_IN_VAULT>`)
- ✅ K8s Secret criado
- ✅ Terraform modules atualizados
- ⚠️ Helm em pending-upgrade (bloqueio)

### Tarefas

#### 1. Resolver Helm Pending-Upgrade (5min)
```bash
# Check status
helm list -n gitlab-staging -a

# Rollback to rev 1
helm rollback gitlab 1 -n gitlab-staging --wait --timeout=5m

# Verify
helm list -n gitlab-staging
```

#### 2. AWS SSO Login (2min)
```bash
aws sso login --profile k8s-platform-prod
aws sts get-caller-identity --profile k8s-platform-prod
```

#### 3. Terraform Apply (15min)
```bash
cd platform-provisioning/aws/kubernetes/terraform/environments/staging

AWS_PROFILE=k8s-platform-prod terraform apply \
  -target=module.gitlab_staging \
  -var='vault_root_token=dummy' \
  -auto-approve

# Monitor rollout
kubectl rollout status deployment gitlab-webservice-default -n gitlab-staging --timeout=5m
```

#### 4. Verificar OmniAuth Ativo (3min)
```bash
# Check Helm values
helm get values gitlab -n gitlab-staging | grep -A 10 omniauth

# Check ConfigMap
kubectl get configmap gitlab-webservice -n gitlab-staging -o yaml | \
  grep -A 15 "omniauth:"

# Verify pods
kubectl get pods -n gitlab-staging -l app=webservice
```

#### 5. Testar OIDC Login End-to-End (20min)
```bash
# Port-forward GitLab
kubectl port-forward -n gitlab-staging svc/gitlab-webservice-default 8082:8181 &

# Browser: http://localhost:8082
# 1. Verificar botão "Keycloak SSO"
# 2. Clicar e validar redirect para keycloak.staging.internal
# 3. Login com credenciais Keycloak
# 4. Validar callback para GitLab
# 5. Confirmar user criado automaticamente

# Kill port-forward
pkill -f "port-forward.*8082"
```

#### Validações Finais
- [ ] Botão "Keycloak SSO" visível
- [ ] Redirect funciona (http://keycloak.staging.internal/auth/...)
- [ ] Login no Keycloak bem-sucedido
- [ ] Callback para GitLab funciona
- [ ] User criado automaticamente no GitLab
- [ ] Email/profile mapeados corretamente

**✅ CRITÉRIO DE SUCESSO**: Login OIDC funcional end-to-end

---

## 🟡 PRIORIDADE 2: Fechar Marco 2 Sprint 3 (1h) - OBSERVABILIDADE

### GAP-001: Observabilidade/SRE (2% restante)

**Status**: 98% completo (10/10 alertas ✅, 6 dashboards ✅, SLIs ✅)

#### Tarefas Pendentes

##### 1. Validar Correlação Traces ↔ Logs (30min)

```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 &

# Browser: http://localhost:3000
# User: admin / Password: prom-operator

# Testes:
# 1. Explore → Tempo → Buscar traces
# 2. Click em trace → Verificar se abre logs correlacionados no Loki
# 3. Testar filtro trace_id → logs
# 4. Validar exemplars em métricas → traces
```

**Validações**:
- [ ] Trace ID visível nos logs (via Loki)
- [ ] Click em trace abre logs automaticamente
- [ ] Exemplars em métricas apontam para traces
- [ ] Navegação traces → logs → metrics funcional

##### 2. Criar Dashboard Específico: GitLab Workload (30min)

```bash
# Template: Copy dashboard "Kubernetes / Workloads"
# Customizar para GitLab:
# - Namespace filter: gitlab-staging
# - Metrics: gitlab_* + gitaly_* + postgresql_*
# - Panels:
#   - Request rate por endpoint
#   - Latency P50/P95/P99
#   - Error rate (4xx/5xx)
#   - Resource usage (CPU/Memory/Disk)
#   - Database connections
```

**Deliverable**: Dashboard salvo em Grafana com nome "GitLab Workload - Staging"

#### Documentação Final
```bash
# Atualizar GAP-001 status
vim docs/plan/gaps-execution-roadmap.md
# Mudar: 98% → 100% ✅ COMPLETO
```

**✅ CRITÉRIO DE SUCESSO**: Marco 2 Sprint 3 fechado (100%)

---

## 🟢 PRIORIDADE 3: Iniciar Marco 3 Sprint 4 (2h) - BACKUP/DR

### GAP-003: Backup/DR Specialist

**Meta do Dia**: Instalar Velero com S3 backend (50% do GAP)

#### Tarefa 1: Preparação (15min)

```bash
# Verificar S3 bucket para backups
aws s3 ls s3://k8s-platform-backups-891377105802/ --profile k8s-platform-prod

# Se não existir, criar
aws s3 mb s3://k8s-platform-backups-891377105802 \
  --region us-east-1 \
  --profile k8s-platform-prod

# Criar IAM policy para Velero (se não existir)
# docs/plan/templates/velero-iam-policy.json
```

#### Tarefa 2: Deploy Velero (1h)

```bash
# Add Velero Helm repo
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update

# Create namespace
kubectl create namespace velero

# Install Velero with S3
helm install velero vmware-tanzu/velero \
  --namespace velero \
  --set configuration.provider=aws \
  --set configuration.backupStorageLocation.bucket=k8s-platform-backups-891377105802 \
  --set configuration.backupStorageLocation.config.region=us-east-1 \
  --set configuration.volumeSnapshotLocation.config.region=us-east-1 \
  --set initContainers[0].name=velero-plugin-for-aws \
  --set initContainers[0].image=velero/velero-plugin-for-aws:v1.9.0 \
  --set initContainers[0].volumeMounts[0].mountPath=/target \
  --set initContainers[0].volumeMounts[0].name=plugins \
  --set credentials.useSecret=true \
  --set credentials.secretContents.cloud="[default]\naws_access_key_id=...\naws_secret_access_key=..."

# Verify installation
kubectl get pods -n velero
velero version
```

#### Tarefa 3: Teste Básico de Backup (30min)

```bash
# Create test namespace
kubectl create namespace backup-test
kubectl run nginx --image=nginx -n backup-test

# Create backup
velero backup create test-backup --include-namespaces backup-test

# Check backup status
velero backup describe test-backup
velero backup logs test-backup

# Verify in S3
aws s3 ls s3://k8s-platform-backups-891377105802/backups/ \
  --profile k8s-platform-prod

# Test restore (simulate disaster)
kubectl delete namespace backup-test
velero restore create --from-backup test-backup

# Verify restore
kubectl get pods -n backup-test
```

#### Tarefa 4: Schedule Backups Automáticos (15min)

```bash
# Daily backup at 2AM UTC
velero schedule create daily-backup \
  --schedule="0 2 * * *" \
  --include-namespaces="gitlab-staging,data-services,keycloak,argocd" \
  --ttl 168h  # 7 days retention

# Weekly full cluster backup (Sunday 3AM)
velero schedule create weekly-full \
  --schedule="0 3 * * 0" \
  --ttl 720h  # 30 days retention

# List schedules
velero schedule get
```

**✅ CRITÉRIO DE SUCESSO**: Velero instalado, teste de backup/restore OK, schedules configurados

---

## 📊 Métricas de Progresso

### Antes do Dia (2026-02-11 EOD)
- Marco 2 Sprint 3: 98% ✅
- Marco 3 Sprint 4: 0% ⏳
- GitLab OIDC: 95% ✅

### Meta do Dia (2026-02-12 EOD)
- Marco 2 Sprint 3: **100% ✅ COMPLETO**
- Marco 3 Sprint 4: **50% 🟡 EM PROGRESSO**
- GitLab OIDC: **100% ✅ COMPLETO**

### Roadmap Geral
```
Semana 1-2: Marco 1 ✅ 100% COMPLETO
Semana 3-4: Marco 2 ✅ 98% → 100% (FECHAR HOJE)
Semana 5-6: Marco 3 ⏳ 0% → 50% (INICIAR HOJE)
```

---

## 🚨 Troubleshooting Rápido

### Se Helm Rollback Falhar
```bash
kubectl delete secret -n gitlab-staging sh.helm.release.v1.gitlab.v2
helm list -n gitlab-staging
```

### Se Terraform Lock
```bash
terraform plan 2>&1 | grep "Lock ID"
AWS_PROFILE=k8s-platform-prod terraform force-unlock -force <LOCK_ID>
```

### Se OIDC Login Falhar
```bash
# Check DNS resolution
kubectl run dns-test --image=nicolaka/netshoot --rm --restart=Never -- \
  nslookup keycloak.staging.internal

# Check secret
kubectl get secret -n gitlab-staging gitlab-oidc-keycloak -o yaml

# Check Keycloak client
kubectl exec -n keycloak <create-job-pod> -- \
  psql -U postgres -d keycloak \
  -c "SELECT client_id, enabled FROM client WHERE client_id='gitlab';"
```

### Se Velero Backup Falhar
```bash
# Check logs
kubectl logs -n velero deployment/velero --tail=100

# Check IAM permissions
aws sts get-caller-identity --profile k8s-platform-prod

# Verify S3 access
aws s3 ls s3://k8s-platform-backups-891377105802/ --profile k8s-platform-prod
```

---

## 📁 Arquivos de Referência

- **OIDC**: `/home/gilvangalindo/projects/Arquitetura/Kubernetes/PROXIMOS-PASSOS-OIDC.md`
- **Logbook**: `docs/logbook/2026-02-11-gitlab-oidc-integration.md`
- **Roadmap**: `docs/plan/gaps-execution-roadmap.md`
- **MEMORY**: `~/.claude/projects/.../memory/MEMORY.md`

---

## 🎯 Checklist Final do Dia

**GitLab OIDC (45min)**:
- [ ] Helm rollback executado
- [ ] Terraform apply concluído
- [ ] OmniAuth ativo verificado
- [ ] Login OIDC testado e funcional
- [ ] Documentação atualizada

**Marco 2 Sprint 3 (1h)**:
- [ ] Correlação traces↔logs validada
- [ ] Dashboard GitLab criado
- [ ] GAP-001 marcado 100% completo

**Marco 3 Sprint 4 (2h)**:
- [ ] Velero instalado
- [ ] Backup de teste executado
- [ ] Restore testado com sucesso
- [ ] Schedules automáticos configurados
- [ ] GAP-003 marcado 50% completo

**Total**: 3h45min de trabalho focado

---

**Última Atualização**: 2026-02-11 22:50 BRT
**Próxima Revisão**: 2026-02-12 EOD
**Status**: 📋 READY TO EXECUTE
