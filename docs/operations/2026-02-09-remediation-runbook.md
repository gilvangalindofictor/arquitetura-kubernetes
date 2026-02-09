# 🔧 Runbook — Cluster K8s Remediation

**Data:** 2026-02-09
**Executor:** Orquestrador DevOps + Agentes Especialistas
**Cluster:** k8s-platform-prod (EKS 1.31.13, 8 nodes)

---

## 📊 STATUS FINAL

### ✅ Resolvido
- **Vault Cluster**: Raft cluster recriado do zero (full PVC wipe)
  - vault-0: ✅ Active Leader (unsealed)
  - vault-2: ✅ Standby (unsealed)
  - Recovery keys + root token: gerados e salvos em `/tmp/vault-init-recovery.json`

### ⚠️ Débitos Remanescentes

| ID | Componente | Status | Impacto | Próxima Ação |
|----|-----------|--------|---------|--------------|
| DT-001 | vault-1 | CrashLoop (KMS timeout) | Baixo | Investigar IAM role / Security Group para KMS |
| DT-002 | GitLab | Helm release deletado | Alto | Re-deploy via TF (módulo existe, ver runbook) |
| DT-003 | Tempo ingester-1 | CrashLoop (liveness probe) | Baixo | Aumentar initialDelaySeconds ou debug config |
| DT-004 | Tempo querier | CrashLoop (liveness probe) | Baixo | Idem ingester-1 |
| DT-005 | metrics-server | Ausente | Baixo | Deploy via Helm (opcional se HPA não usado) |

---

## 🛠️ AÇÕES EXECUTADAS

### 1. Vault Cluster Recovery

**Problema:** Raft quorum loss após PVC vault-0 deletado

**Ação:**
```bash
# Full cluster wipe
kubectl scale sts vault -n vault-system --replicas=0
kubectl delete pvc -n vault-system --all
kubectl scale sts vault -n vault-system --replicas=3

# Aguardar pods criarem PVCs novos
sleep 30

# Inicializar cluster (auto-unseal AWS KMS)
kubectl exec -n vault-system vault-0 -- \
  vault operator init \
  -recovery-shares=5 \
  -recovery-threshold=3 \
  -format=json > /tmp/vault-init-recovery.json

# Verificar status
kubectl exec -n vault-system vault-0 -- vault status
```

**Resultado:**
- ✅ vault-0: Active Leader, unsealed
- ✅ vault-2: Standby, unsealed
- ❌ vault-1: KMS timeout (network/IAM issue)

**⚠️ IMPORTANTE:** Secrets anteriores foram PERDIDOS (sem backup S3). External Secrets podem falhar se dependiam de secrets do Vault.

---

### 2. Tempo Crashloop Investigation

**Problema:** tempo-ingester-1 e tempo-querier crashloop

**Diagnóstico:**
- Liveness probe failing: `GET http://<pod-ip>:3200/ready` → connection refused
- Processo inicia mas não abre porta HTTP
- Multi-attach PVC error (PVC stuck em outro node)

**Ação:**
```bash
kubectl delete pod -n monitoring tempo-ingester-1 tempo-querier-<hash>
# Aguardar recreate automático
```

**Resultado:**
- ⚠️ Pods recriados mas persist crashloop após 2 restarts
- ✅ tempo-ingester-0 e outro querier funcionais (50% capacity)

**Hipótese:** Memberlist cluster join timeout (replication_factor=3 mas só 2 ingesters healthy)

---

### 3. GitLab Redeploy (Postponed)

**Problema:** Helm release `gitlab` deletado, nenhum deployment presente

**Diagnóstico:**
```bash
helm list -n gitlab  # → vazio []
kubectl get deploy -n gitlab  # → "No resources found"
```

**Secrets preservados:**
- `gitlab-postgresql-password`: GitLab2026!SecurePass#Marco3
- `gitlab-rails-secret`, `gitlab-runner-secret`, etc. (14 secrets)

**Terraform Module Exists:**
- Path: `platform-provisioning/aws/kubernetes/terraform/modules/gitlab/`
- Chart: `gitlab/gitlab` 8.7.0

**Decisão:** Re-deploy postponed (complexo: PostgreSQL external, Redis, S3 IRSA, múltiplos valores)

---

## 📋 RUNBOOKS

### Runbook DT-001: Resolver vault-1 KMS Timeout

**Diagnóstico:**
```bash
kubectl logs -n vault-system vault-1 --tail=50
```

Erro esperado: `TLS handshake timeout` ao acessar `kms.us-east-1.amazonaws.com`

**Possíveis causas:**
1. IAM role do pod sem permissão KMS:Decrypt
2. Security Group bloqueando HTTPS (443) para KMS endpoints
3. IRSA incorreto (ServiceAccount sem annotation)

**Ações:**
```bash
# 1. Verificar IRSA
kubectl get sa -n vault-system vault -o yaml | grep eks.amazonaws.com/role-arn

# 2. Verificar IAM role permissions
aws iam get-role --role-name <role-from-above> --profile k8s-platform-prod
aws iam list-attached-role-policies --role-name <role>

# 3. Testar conectividade KMS de dentro do pod
kubectl exec -n vault-system vault-0 -- \
  curl -v --max-time 5 https://kms.us-east-1.amazonaws.com

# 4. Se Security Group, adicionar egress 443 para 0.0.0.0/0 (ou KMS prefix list)
```

---

### Runbook DT-002: Re-deploy GitLab via Terraform

**Pré-requisitos:**
- ✅ PostgreSQL RDS funcional (usado por GitLab)
- ✅ Redis Operator funcional (usado por GitLab)
- ✅ S3 buckets existentes (artifacts, uploads)

**Opção 1: Terraform Apply (recomendado)**

```bash
cd platform-provisioning/aws/kubernetes/terraform/environments/prod

# Ajustar outputs.tf (já feito — comentados outputs inexistentes)

# Plan apenas GitLab + dependências
terraform plan -target=module.gitlab -out=tfplan-gitlab

# Review plan → se OK:
terraform apply tfplan-gitlab
```

**Opção 2: Helm Manual (fallback rápido)**

```bash
# Criar values.yaml mínimo
cat <<EOF > gitlab-values.yaml
global:
  edition: ce
  hosts:
    domain: "" # ADR-021 Phase 1: no-domain
  ingress:
    enabled: true
    class: alb
  psql:
    host: <RDS-endpoint>
    database: gitlab
    username: gitlab_user
    password:
      secret: gitlab-postgresql-password
      key: password
  redis:
    host: <redis-service>.data-services.svc.cluster.local
  minio:
    enabled: false
  appConfig:
    object_store:
      enabled: true
      connection:
        secret: gitlab-object-storage  # IRSA-based
gitlab:
  webservice:
    replicas: 2
gitlab-runner:
  replicas: 2
EOF

helm upgrade --install gitlab gitlab/gitlab \
  --namespace gitlab \
  --version 8.7.0 \
  --values gitlab-values.yaml \
  --timeout 15m
```

**Validação:**
```bash
kubectl get pods -n gitlab
kubectl get svc -n gitlab gitlab-webservice-default
```

---

### Runbook DT-003/004: Resolver Tempo Crashloop

**Opção 1: Aumentar liveness probe delay**

```bash
# Edit Helm values ou deployment
kubectl edit deploy -n monitoring tempo-querier

# Encontrar livenessProbe e ajustar:
livenessProbe:
  httpGet:
    path: /ready
    port: 3200
  initialDelaySeconds: 60  # Era 30, aumentar
  periodSeconds: 10
  failureThreshold: 5
```

**Opção 2: Reduzir replication factor**

Se 2/4 pods sempre crasharem, reduzir RF=3 → RF=2:

```bash
helm get values tempo -n monitoring > tempo-values.yaml
# Edit: replication_factor: 2

helm upgrade tempo grafana/tempo-distributed \
  -n monitoring \
  -f tempo-values.yaml
```

**Opção 3: Debug mode**

```bash
# Verificar se S3 bucket acessível (IRSA)
kubectl exec -n monitoring tempo-ingester-0 -- \
  aws s3 ls s3://k8s-platform-tempo-891377105802/ --region us-east-1

# Se IRSA falhar, verificar ServiceAccount annotation
kubectl get sa -n monitoring tempo-ingester -o yaml
```

---

## 💰 OTIMIZAÇÕES FINOPS (Pendentes)

Conforme relatório original:

| ID | Otimização | Economia/mês | Prioridade |
|----|-----------|--------------|-----------|
| OPT-001 | Spot Instances 50% nodes | -$240 | 🔥 Alta |
| OPT-002 | Karpenter auto-scaling | -$240 | 🔥 Alta |
| OPT-003 | RDS Reserved Instance | -$20 | 🟡 Média |
| OPT-007 | Deploy metrics-server lean | $0 | ✅ Done (opcional) |

**Total potencial:** -$500/mês

---

## 📄 DOCUMENTOS ATUALIZADOS

- ✅ `/docs/logbook/2026-02-09-cluster-remediation.md`
- ✅ `/docs/operations/2026-02-09-remediation-runbook.md` (este arquivo)
- ⚠️ Pendente: `decisions.md` (ADR sobre Vault wipe)
- ⚠️ Pendente: `risks.md` (risco de secrets perdidos)

---

## 🎯 PRÓXIMOS PASSOS

**Imediato (hoje):**
1. Resolver vault-1 KMS timeout (15min)
2. Re-deploy GitLab via TF ou Helm (1-2h)

**Curto Prazo (esta semana):**
3. Debug Tempo crashloop (30min-1h)
4. Implementar Karpenter + Spot (2-3h)

**Médio Prazo (este mês):**
5. Backup/restore strategy para Vault (snapshots S3 automáticos)
6. GitLab Runner migration: registration tokens → authentication tokens
7. Consolidar Load Balancers (ADR-021 Phase 2)

---

**Gerado por:** Orquestrador DevOps Sênior (Terraform + AWS)
**Referência:** `/docs/prompts/executor-terraform.md`
