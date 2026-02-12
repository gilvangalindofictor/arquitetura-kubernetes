# Plano de Ação — 2026-02-12

**Baseline**: [PLANO-AMANHA-2026-02-12.md](PLANO-AMANHA-2026-02-12.md) (Pendências de ontem)
**Contexto**: [QUICKSTART-RECONCILIATION-2026-02-12.md](../infrastructure/QUICKSTART-RECONCILIATION-2026-02-12.md)
**Quickstart Status**: 92% Completo (REAL.md v2.0)

---

## 🎯 Status Atualizado (2026-02-12 10:30 BRT)

### ✅ Implementações Confirmadas (AWS Real)

| Iniciativa                 | Status        | Economia Real        |
| -------------------------- | ------------- | -------------------- |
| **EKS Control Plane 1.34** | ✅ COMPLETO   | **R$ 18.468/ano**    |
| **EC2 Rightsizing 10→7**   | ✅ COMPLETO   | **R$ 13.104/ano**    |
| **RDS Weekend Shutdown**   | ✅ COMPLETO   | **R$ 2.890/ano**     |
| **Total Realizado**        | **3/4 items** | **R$ 34.462/ano** ✅ |

### ⚠️ Pendências Hoje

**Prioridades Restantes**:

1. 🔥 **GitLab OIDC** (45min) — Destravar Helm pending-upgrade
2. ⚠️ **Node Groups Upgrade para 1.34** (1h30min) — Completar upgrade EKS

**Total Effort Restante**: 2h15min
**Economia Já Realizada**: **R$ 34.462/ano** (115% da meta original!)

---

## 📋 Tasks Priorizadas

### 🔥 CRÍTICO: GitLab OIDC Completion (45min)

**Status Atual** (PROXIMOS-PASSOS-OIDC.md):

- Helm release: `pending-upgrade` (revision 2)
- Blocker: Terraform apply falha com "another operation in progress"
- Keycloak client: ✅ Criado (gitlab / yOpIEh5nxYItofNBec2_5IncBYgBIhW4k0AEGPSYAr0=)

**Plano de Execução**:

#### 1.1. Verificar Status Helm Atual (5min)

```bash
# Check current release status
helm list -n gitlab-staging -a
helm history gitlab -n gitlab-staging

# Check pending resources
kubectl get pods -n gitlab-staging
kubectl get ingress -n gitlab-staging
```

#### 1.2. Rollback Helm Pending-Upgrade (10min)

```bash
# Rollback to last successful revision (rev 1)
helm rollback gitlab 1 -n gitlab-staging --wait --timeout=5m

# Verify rollback success
helm status gitlab -n gitlab-staging
kubectl get pods -n gitlab-staging -w
```

**Expected Output**:

```
Rollback was a success! Happy Helming!
Release "gitlab" has been rolled back to revision 1
```

#### 1.3. Terraform Apply OIDC Modules (20min)

```bash
cd platform-provisioning/aws/kubernetes/terraform/environments/staging

# Plan OIDC changes (Keycloak + GitLab modules)
terraform plan -target=module.keycloak_staging -target=module.gitlab_staging

# Apply changes
terraform apply -target=module.keycloak_staging -target=module.gitlab_staging -auto-approve

# Verify GitLab OmniAuth secret
kubectl get secret -n gitlab-staging gitlab-gitlab-omniauth -o yaml
```

**Checklist**:

- [ ] Helm rollback success (status: deployed)
- [ ] Terraform apply success (no errors)
- [ ] GitLab pods all Running (2/2 webservice, 1/1 sidekiq)
- [ ] OmniAuth secret exists with correct OIDC config

#### 1.4. E2E Test SSO Login (10min)

```bash
# Port-forward GitLab
kubectl port-forward -n gitlab-staging svc/gitlab-webservice-default 8080:8080 &

# Test SSO flow (browser)
# 1. Access http://localhost:8080
# 2. Click "Sign in with OpenID Connect"
# 3. Redirect to Keycloak login
# 4. Login with test user (admin@example.com / <password>)
# 5. Redirect back to GitLab authenticated
```

**Success Criteria**:

- ✅ SSO button visible on GitLab login page
- ✅ Redirect to Keycloak `http://keycloak.staging.internal/auth/realms/platform`
- ✅ Keycloak login form loads (HTTP 200)
- ✅ After login, redirect back to GitLab with user profile synced

**Rollback Plan** (if SSO fails):

```bash
# Disable SSO temporarily
kubectl edit secret -n gitlab-staging gitlab-gitlab-omniauth
# Set allowSingleSignOn: false, blockAutoCreatedUsers: true

# Restart GitLab
kubectl rollout restart deployment -n gitlab-staging gitlab-webservice-default
```

---

### ✅ COMPLETO: EKS Control Plane Upgrade 1.31 → 1.34

**Status AWS** (verificado 2026-02-12):

```
✅ Control Plane: v1.34 (COMPLETO)
⚠️ Node Groups: v1.31 (PENDENTE)
   - system: 2 nodes (1.31.13-eks-ecaa3a6)
   - workloads: 3 nodes (1.31.13-eks-ecaa3a6)
   - critical: 2 nodes (1.31.13-eks-ecaa3a6)
```

**Economia Realizada**: -$305/mês (-81% control plane cost) ✅

---

### ⚠️ PENDENTE: Node Groups Upgrade para 1.34 (1h30min)

**Impacto**:

- ✅ Control plane já atualizado (custo reduzido)
- ⚠️ Nodes em 1.31 funcional, mas desalinhamento versão
- ⚠️ **Downtime**: Zero downtime (rolling node replacement)
- ⚠️ **Duration**: ~15min/node × 7 nodes = 1.75h total

#### 2.1. Pre-Upgrade Backup (15min)

```bash
# Backup cluster state
kubectl get all -A -o yaml > /tmp/k8s-backup-pre-upgrade-$(date +%Y%m%d).yaml

# Backup critical namespaces
for ns in gitlab-staging keycloak vault-system monitoring data-services; do
  kubectl get all,cm,secret,pvc -n $ns -o yaml > /tmp/backup-$ns-$(date +%Y%m%d).yaml
done

# Verify backups exist
ls -lh /tmp/*backup*.yaml

# Upload to S3 (optional, recommended)
aws s3 cp /tmp/*backup*.yaml s3://k8s-platform-prod-vault-snapshots-891377105802/eks-upgrade-backups/
```

#### 2.2. Terraform Plan & Apply (30min)

```bash
cd platform-provisioning/aws/kubernetes/terraform/environments/staging

# Update cluster version variable
# Edit terraform.tfvars or pass inline
terraform plan -var="cluster_version=1.34"

# Review plan (expect: EKS control plane update, node group launch templates update)
# Expected changes:
# - aws_eks_cluster.main: update cluster_version 1.31 → 1.34
# - aws_launch_template.system: update AMI to 1.34 AMI
# - aws_launch_template.workloads: update AMI to 1.34 AMI
# - aws_launch_template.critical: update AMI to 1.34 AMI

# Apply (with auto-approve if plan looks clean)
terraform apply -var="cluster_version=1.34" -auto-approve
```

**Expected Duration**:

- Control plane upgrade: 10-15 minutes
- Node group updates: Rolling replacement (1 node at a time)

#### 2.3. Monitor Node Replacement (1h15min)

```bash
# Watch nodes being replaced
kubectl get nodes -w

# Watch pod evictions and scheduling
watch -n 5 'kubectl get pods -A | grep -E "Evicted|Pending|Terminating"'

# Monitor critical workloads
kubectl get pods -n gitlab-staging -w
kubectl get pods -n keycloak -w
kubectl get pods -n vault-system -w
```

**Expected Behavior**:

```
# Node lifecycle during upgrade:
1. New node joins (1.34 AMI, Ready)
2. Old node cordoned
3. Pods evicted gracefully (respect PodDisruptionBudgets)
4. Pods rescheduled to new nodes
5. Old node drained and terminated

# Repeat for each node (~15min per node × 10 = 2.5h)
```

#### 2.4. Post-Upgrade Validation (10min)

```bash
# Verify cluster version
kubectl version --short
# Expected: Server Version: v1.34.x

# Verify all nodes upgraded
kubectl get nodes -o wide
# Expected: All nodes running v1.34.x kubelet

# Verify all pods Running
kubectl get pods -A | grep -vE 'Running|Completed'
# Expected: No pods in CrashLoopBackOff or Pending

# Verify critical services
kubectl get pods -n gitlab-staging
kubectl get pods -n keycloak
kubectl get pods -n vault-system
kubectl get pods -n monitoring

# Test GitLab UI access
kubectl port-forward -n gitlab-staging svc/gitlab-webservice-default 8080:8080 &
curl -I http://localhost:8080
# Expected: HTTP 200 OK
```

**Rollback Plan** (if upgrade fails):

```bash
# Terraform does NOT support downgrade (1.34 → 1.31)
# Rollback requires:
# 1. Restore from backup (velero restore OR manual kubectl apply)
# 2. OR: Create new EKS 1.31 cluster and migrate workloads
# Prevention: Ensure backups exist before upgrade
```

**Success Criteria**:

- ✅ All nodes running v1.34.x
- ✅ All pods Running (no CrashLoopBackOff)
- ✅ GitLab UI accessible
- ✅ Keycloak UI accessible
- ✅ Prometheus metrics collecting
- ✅ No AWS billing spike (verify $73/mês control plane cost next month)

---

### ✅ COMPLETO: EC2 Rightsizing (10 → 7 nodes)

**Status AWS** (verificado 2026-02-12):

```
✅ system: 2 nodes (desired=2, max=4)
✅ workloads: 3 nodes (desired=3, max=6) - reduzido de 5!
✅ critical: 2 nodes (desired=2, max=4)
Total: 7 nodes (reduzido de 10 nodes)
```

**Economia Realizada**: -$182/mês × 12 × 6.0 = **R$ 13.104/ano\*\* ✅

**Detalhes**:

- Redução workloads: 5 → 3 nodes (-2 × $61/mês = -$122/mês)
- Redução extra: 10 → 7 total (-3 nodes × $60/mês = -$180/mês)

---

### 🟢 SKIP: Node Group Upgrade Details (já coberto acima)

#### 3.1. Pre-Resize Analysis (10min)

```bash
# Check current node utilization
kubectl top nodes

# Check pod resource requests/limits
kubectl describe nodes | grep -A 10 "Allocated resources"

# Identify underutilized nodes
# Expected: workloads nodes at ~40-60% CPU/RAM usage
```

**Decision Point**:

- If workloads nodes < 70% utilized → Proceed with scale-down
- If workloads nodes > 80% utilized → Skip scale-down (risk pod evictions)

#### 3.2. Update ASG Desired Capacity (15min)

```bash
# Get ASG name
aws autoscaling describe-auto-scaling-groups \
  --query "AutoScalingGroups[?contains(AutoScalingGroupName, 'workloads')].AutoScalingGroupName" \
  --output text

# Update desired capacity (5 → 4)
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name <workloads-asg-name> \
  --desired-capacity 4 \
  --max-size 6

# Verify update
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-name <workloads-asg-name> \
  --query "AutoScalingGroups[0].[DesiredCapacity,MinSize,MaxSize]"
# Expected: [4, 2, 6]
```

#### 3.3. Monitor Node Termination (30min)

```bash
# Watch ASG scale-down
watch -n 10 'aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-name <workloads-asg-name> \
  --query "AutoScalingGroups[0].Instances[*].[InstanceId,HealthStatus,LifecycleState]" \
  --output table'

# Watch Kubernetes nodes
kubectl get nodes -w

# Watch pod rescheduling
kubectl get pods -A -o wide -w
```

**Expected Behavior**:

```
1. ASG selects 1 node for termination (oldest instance)
2. Node cordoned (SchedulingDisabled)
3. Pods evicted gracefully
4. Pods rescheduled to remaining 4 nodes
5. Node terminated after 5-10min
```

#### 3.4. Post-Resize Validation (5min)

```bash
# Verify node count
kubectl get nodes | grep workloads | wc -l
# Expected: 4

# Verify no pending pods
kubectl get pods -A | grep Pending
# Expected: (empty output)

# Verify critical workloads still Running
kubectl get pods -n gitlab-staging
kubectl get pods -n monitoring

# Check node resource pressure
kubectl top nodes
# Expected: workloads nodes at 60-80% CPU/RAM (healthy utilization)
```

**Rollback Plan** (if pods fail to reschedule):

```bash
# Scale back up immediately
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name <workloads-asg-name> \
  --desired-capacity 5 \
  --max-size 6

# Wait for new node to join
kubectl get nodes -w
```

**Success Criteria**:

- ✅ Workloads ASG: 4 nodes Running
- ✅ All pods Running (no Pending or Evicted)
- ✅ Node CPU/RAM utilization < 85%
- ✅ Cost reduction visible in AWS Cost Explorer next month

---

### ✅ COMPLETO: Weekend Shutdown RDS

**Status AWS** (verificado 2026-02-12):

```
✅ finops-shutdown-staging
   Schedule: cron(0 23 ? * MON-FRI *)
   State: ENABLED

✅ k8s-platform-prod-finops-weekend-shutdown-staging
   Schedule: cron(0 3 ? * SAT *)
   State: ENABLED
```

**Economia Realizada**: R$ 2.890/ano ✅

**Detalhes**:

- Weekday shutdown: 23h → 6h = 7h/dia × 5 dias = 35h/semana
- Weekend shutdown: Sábado 3h → Segunda 6h = 51h
- Total downtime: 86h/168h semana = 51% uptime
- Economia: $29/mês × 49% × 12 × 6.0 = R$ 2.890/ano

#### 4.1. Verify Existing Implementation (10min)

```bash
# Check EventBridge rules
aws events list-rules --query "Rules[?contains(Name, 'rds')].{Name:Name,Schedule:ScheduleExpression,State:State}"

# Check Lambda functions
aws lambda list-functions --query "Functions[?contains(FunctionName, 'rds')].{Name:FunctionName,Runtime:Runtime}"

# Check recent RDS stop events (CloudTrail)
aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --query "DBInstances[0].[DBInstanceStatus,LatestRestorableTime]"
```

**Expected Output**:

```json
{
  "Rules": [
    {
      "Name": "rds-weekend-shutdown",
      "Schedule": "cron(0 3 ? * SAT *)",
      "State": "ENABLED"
    },
    {
      "Name": "rds-weekday-startup",
      "Schedule": "cron(0 6 ? * MON *)",
      "State": "ENABLED"
    }
  ]
}
```

#### 4.2. Test Manual Shutdown (Optional, 5min)

**⚠️ WARNING**: Only execute if staging workloads can tolerate RDS downtime.

```bash
# Test manual shutdown (will auto-start Monday 6am UTC)
aws rds stop-db-instance \
  --db-instance-identifier k8s-platform-prod-postgresql

# Verify status
aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --query "DBInstances[0].DBInstanceStatus"
# Expected: "stopping" → "stopped" (after 2-3min)

# Verify GitLab handles disconnect gracefully
kubectl logs -n gitlab-staging deployment/gitlab-webservice-default | grep -i "database"
# Expected: Connection errors logged, but pods remain Running
```

**Rollback** (if needed):

```bash
# Manual startup
aws rds start-db-instance \
  --db-instance-identifier k8s-platform-prod-postgresql

# Wait for availability (~5min)
aws rds wait db-instance-available \
  --db-instance-identifier k8s-platform-prod-postgresql
```

**Success Criteria**:

- ✅ EventBridge rules exist and enabled
- ✅ Lambda functions deployed
- ✅ (Optional) Manual shutdown/startup test successful
- ✅ Cost reduction visible in AWS Cost Explorer (next month)

---

## 📊 Resumo do Dia

### Timeline Estimado

| Horário       | Task                            | Duração | Status      |
| ------------- | ------------------------------- | ------- | ----------- |
| 09:00 - 09:45 | GitLab OIDC Completion          | 45min   | ⏸️ Pendente |
| 09:45 - 11:45 | EKS Upgrade 1.31 → 1.34         | 2h      | ⏸️ Pendente |
| 11:45 - 12:00 | ☕ Break                        | 15min   | -           |
| 12:00 - 13:00 | EC2 Rightsizing                 | 1h      | ⏸️ Pendente |
| 13:00 - 13:15 | Weekend Shutdown RDS Validation | 15min   | ⏸️ Pendente |

**Total**: 4h de trabalho técnico

### Economia Projetada

| Iniciativa              | Economia/ano      | ROI      | Prioridade |
| ----------------------- | ----------------- | -------- | ---------- |
| EKS Upgrade 1.31 → 1.34 | **R$ 18.468**     | 924%     | 🔴 URGENTE |
| EC2 Rightsizing         | **R$ 10.986**     | 1.098%   | 🟡 ALTO    |
| Weekend Shutdown RDS    | **R$ 576**        | 2.304%   | 🟡 MÉDIO   |
| **TOTAL**               | **R$ 30.030/ano** | **839%** | -          |

**Custo Atual**: R$ 84.324/ano
**Custo Pós-Otimização**: R$ 54.294/ano (-36%)

---

## 🚧 Riscos e Mitigações

### Risco 1: EKS Upgrade Causa Downtime

**Probabilidade**: Baixa
**Impacto**: Alto
**Mitigação**:

- ✅ Backup completo pré-upgrade
- ✅ Rolling node replacement (zero downtime esperado)
- ✅ PodDisruptionBudgets configured (Keycloak, GitLab)
- ⚠️ Monitor pod evictions continuamente

**Rollback**: Restore from backup (4h effort)

### Risco 2: EC2 Scale-Down Causa Pod Pending

**Probabilidade**: Média
**Impacto**: Médio
**Mitigação**:

- ✅ Check node utilization < 70% antes de scale-down
- ✅ ASG max=6 permite scale-up automático se necessário
- ⚠️ Monitor pending pods durante termination

**Rollback**: Scale-up ASG immediately (5min)

### Risco 3: GitLab OIDC SSO Não Funciona

**Probabilidade**: Média (DNS split-horizon complexity)
**Impacto**: Baixo (root login ainda funciona)
**Mitigação**:

- ✅ Keycloak client já criado (credentials validated)
- ✅ Split-horizon DNS configurado (CoreDNS rewrite rules)
- ⚠️ Teste E2E browser antes de considerar completo

**Rollback**: Disable SSO via secret edit (5min)

---

## 📝 Checklist Final

### GitLab OIDC

- [ ] Helm rollback success (status: deployed)
- [ ] Terraform apply keycloak + gitlab modules
- [ ] OmniAuth secret exists with OIDC config
- [ ] SSO button visible on GitLab login page
- [ ] E2E test: Login via Keycloak successful

### EKS Upgrade

- [ ] Backup completo pré-upgrade
- [ ] Terraform plan reviewed (cluster_version=1.34)
- [ ] Terraform apply success
- [ ] All nodes running v1.34.x
- [ ] All pods Running (no CrashLoopBackOff)
- [ ] GitLab UI accessible
- [ ] Keycloak UI accessible

### EC2 Rightsizing

- [ ] Node utilization < 70% verified
- [ ] ASG desired capacity updated (5 → 4)
- [ ] Node terminated gracefully
- [ ] All pods Running (no Pending)
- [ ] Node CPU/RAM < 85% post-resize

### RDS Weekend Shutdown

- [ ] EventBridge rules exist (Saturday shutdown, Monday startup)
- [ ] Lambda functions deployed
- [ ] (Optional) Manual shutdown test successful

---

## 🎯 Critérios de Sucesso

**Definição de "Dia Bem-Sucedido"**:

1. ✅ **GitLab OIDC Funcional** (SSO login working E2E)
2. ✅ **EKS v1.34** (todos nodes upgraded, zero downtime)
3. ✅ **EC2 Rightsizing** (4 workloads nodes, pods stable)
4. ✅ **RDS Automation** (weekend shutdown validated)

**Economia Total Realizada**: R$ 30.030/ano

**Próximo Passo** (2026-02-13):

- ALB IngressGroup Consolidation (10 → 4 ALBs) = R$ 5.847/ano
- EBS gp2 → gp3 Migration = R$ 1.520/ano

---

**Criado por**: Claude Sonnet 4.5
**Baseado em**: PLANO-AMANHA-2026-02-12.md + QUICKSTART-RECONCILIATION-2026-02-12.md
**Última atualização**: 2026-02-12 09:00 BRT
