# 🔧 Troubleshooting: EBS CSI Driver & PVC Provisioning Failures

**Versão:** 1.0
**Data:** 2026-02-06
**Autor:** DevOps Team
**Contexto:** Runbook criado após incident Vault recovery (15h downtime)

---

## 📋 Sumário Executivo

Este runbook documenta o troubleshooting sistemático para falhas de provisionamento de PVCs (Persistent Volume Claims) no EKS, especificamente relacionadas ao EBS CSI Driver e dependências AWS (IRSA, VPC Endpoints, NetworkPolicies).

**Sintomas Comuns:**
- ✅ PVCs stuck em estado `Pending` indefinidamente
- ✅ Pods sem inicializar (waiting for volumes)
- ✅ Eventos CSI driver: `failed to provision volume with StorageClass`
- ✅ Timeouts chamando AWS STS/EC2 APIs

**Root Causes Observadas:**
1. **VPC Endpoints ausentes** (STS, EC2) → NAT Gateway timeouts
2. **IRSA misconfiguration** → NoCredentialProviders
3. **NetworkPolicies default-deny** → Bloqueio DNS/HTTPS
4. **Volume affinity mismatch** → PVC em AZ diferente do node

---

## 🚨 Incident Response (Quick Start)

### Fase 1: Diagnóstico Rápido (5 minutos)

```bash
# 1. Verificar PVCs pendentes
kubectl get pvc -A | grep Pending

# 2. Descrever PVC para ver eventos
kubectl describe pvc <pvc-name> -n <namespace>

# 3. Verificar CSI controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver \
  -c csi-provisioner --tail=100

# 4. Verificar CSI driver pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver
```

### Fase 2: Decisão Rápida

| Sintoma Observado | Provável Root Cause | Jump To |
|-------------------|---------------------|---------|
| `TLS handshake timeout` nos logs CSI | VPC Endpoints ausentes | [Seção 3.1](#31-vpc-endpoints-missing) |
| `NoCredentialProviders` nos logs | IRSA misconfiguration | [Seção 3.2](#32-irsa-misconfiguration) |
| `i/o timeout` chamando AWS APIs | NetworkPolicy bloqueando | [Seção 3.3](#33-networkpolicies-blocking-aws-apis) |
| `VolumeBindingMode: WaitForFirstConsumer` | Volume affinity issue | [Seção 3.4](#34-volume-affinity-mismatch) |

---

## 🔍 Diagnóstico Detalhado

### 1. Verificar Status Geral

#### 1.1 PVCs Status

```bash
# Listar TODOS os PVCs no cluster
kubectl get pvc -A

# Output esperado (healthy):
# NAMESPACE   NAME        STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS
# vault       data-vault-0   Bound    pvc-abc123...   10Gi       RWO            gp3

# Output problemático:
# vault       data-vault-0   Pending                                                                   gp3
```

#### 1.2 StorageClass Configuração

```bash
# Verificar StorageClasses disponíveis
kubectl get storageclass

# Descrever gp3 StorageClass
kubectl describe storageclass gp3

# Validar provisioner
# Expected: provisioner: ebs.csi.aws.com
```

#### 1.3 CSI Driver Health

```bash
# Verificar CSI controller deployment
kubectl get deployment -n kube-system ebs-csi-controller

# Expected: READY 2/2, STATUS Running

# Verificar CSI node DaemonSet
kubectl get daemonset -n kube-system ebs-csi-node

# Expected: DESIRED = NUMBER_OF_NODES, CURRENT = NUMBER_OF_NODES
```

### 2. Logs Analysis

#### 2.1 CSI Controller Logs

```bash
# Logs do csi-provisioner container
kubectl logs -n kube-system \
  $(kubectl get pods -n kube-system -l app=ebs-csi-controller -o name | head -1) \
  -c csi-provisioner --tail=50

# Patterns para procurar:
# ✅ "successfully created volume pvc-xyz" → SUCCESS
# ❌ "failed to create volume" → FAILURE
# ❌ "context deadline exceeded" → TIMEOUT
# ❌ "TLS handshake timeout" → VPC/Network issue
# ❌ "NoCredentialProviders" → IRSA issue
```

#### 2.2 CSI Attacher Logs

```bash
# Logs do ebs-plugin container
kubectl logs -n kube-system \
  $(kubectl get pods -n kube-system -l app=ebs-csi-controller -o name | head -1) \
  -c ebs-plugin --tail=50

# Patterns:
# ✅ "ControllerPublishVolume: called" → Attach iniciou
# ❌ "rpc error" → AWS API failure
```

### 3. Root Causes Específicas

#### 3.1 VPC Endpoints Missing

**Sintoma:**
```
TLS handshake timeout
timeout calling STS AssumeRoleWithWebIdentity
timeout calling EC2 DescribeVolumes
```

**Diagnóstico:**

```bash
# 1. Testar latência STS API (de dentro do pod CSI)
kubectl exec -n kube-system \
  $(kubectl get pods -n kube-system -l app=ebs-csi-controller -o name | head -1) \
  -c ebs-plugin -- time curl -s https://sts.us-east-1.amazonaws.com

# Expected com VPC Endpoint: < 0.1s
# Problemático via NAT: > 5s ou timeout

# 2. Verificar VPC Endpoints existentes
aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=<VPC_ID>" \
  --query 'VpcEndpoints[*].[ServiceName,State,VpcEndpointId]' \
  --output table

# Expected:
# com.amazonaws.us-east-1.sts    | available | vpce-xxx
# com.amazonaws.us-east-1.ec2    | available | vpce-yyy
```

**Fix:**

```bash
# Criar VPC Endpoint STS
aws ec2 create-vpc-endpoint \
  --vpc-id <VPC_ID> \
  --service-name com.amazonaws.us-east-1.sts \
  --vpc-endpoint-type Interface \
  --subnet-ids <SUBNET_1> <SUBNET_2> \
  --security-group-ids <SG_ID> \
  --private-dns-enabled

# Criar VPC Endpoint EC2
aws ec2 create-vpc-endpoint \
  --vpc-id <VPC_ID> \
  --service-name com.amazonaws.us-east-1.ec2 \
  --vpc-endpoint-type Interface \
  --subnet-ids <SUBNET_1> <SUBNET_2> \
  --security-group-ids <SG_ID> \
  --private-dns-enabled

# Aguardar endpoints ficarem "available" (120-180s)
aws ec2 describe-vpc-endpoints \
  --vpc-endpoint-ids <ENDPOINT_ID> \
  --query 'VpcEndpoints[0].State'
```

**Validação:**

```bash
# Re-test latência (deve cair para <5ms)
kubectl exec -n kube-system <CSI_POD> -c ebs-plugin -- \
  time curl -s https://sts.us-east-1.amazonaws.com

# Forçar reprovisioning PVC
kubectl delete pvc <PENDING_PVC> -n <NAMESPACE>
# Re-criar PVC (StatefulSet recria automaticamente)
```

**ROI:** $28.90/mês vs 15h downtime evitado ($1,000-$3,000 eng time)

---

#### 3.2 IRSA Misconfiguration

**Sintoma:**
```
NoCredentialProviders: no valid providers in chain
WebIdentityErr: failed to retrieve credentials
```

**Diagnóstico:**

```bash
# 1. Verificar ServiceAccount annotation
kubectl get sa ebs-csi-controller-sa -n kube-system -o yaml | grep eks.amazonaws.com/role-arn

# Expected:
# eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/eks-ebs-csi-driver-role

# 2. Verificar token montado no pod
kubectl exec -n kube-system <CSI_POD> -c ebs-plugin -- \
  ls -la /var/run/secrets/eks.amazonaws.com/serviceaccount/

# Expected: token file presente

# 3. Testar AssumeRoleWithWebIdentity manualmente
kubectl exec -n kube-system <CSI_POD> -c ebs-plugin -- \
  aws sts get-caller-identity

# Expected: retornar assumed-role/eks-ebs-csi-driver-role
```

**Fix:**

```bash
# 1. Verificar IAM Role trust policy
aws iam get-role --role-name eks-ebs-csi-driver-role \
  --query 'Role.AssumeRolePolicyDocument'

# Expected:
# {
#   "Version": "2012-10-17",
#   "Statement": [{
#     "Effect": "Allow",
#     "Principal": {
#       "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/oidc.eks.REGION.amazonaws.com/id/OIDC_ID"
#     },
#     "Action": "sts:AssumeRoleWithWebIdentity",
#     "Condition": {
#       "StringEquals": {
#         "oidc.eks.REGION.amazonaws.com/id/OIDC_ID:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
#       }
#     }
#   }]
# }

# 2. Re-anotar ServiceAccount se necessário
kubectl annotate sa ebs-csi-controller-sa -n kube-system \
  eks.amazonaws.com/role-arn=arn:aws:iam::ACCOUNT:role/eks-ebs-csi-driver-role \
  --overwrite

# 3. Restart CSI controller para pegar novo token
kubectl rollout restart deployment ebs-csi-controller -n kube-system
```

---

#### 3.3 NetworkPolicies Blocking AWS APIs

**Sintoma:**
```
i/o timeout
dial tcp: lookup sts.us-east-1.amazonaws.com: no such host
connection refused
```

**Diagnóstico:**

```bash
# 1. Verificar NetworkPolicies aplicadas ao namespace kube-system
kubectl get networkpolicy -n kube-system

# 2. Descrever policy que pode estar bloqueando
kubectl describe networkpolicy <POLICY_NAME> -n kube-system

# 3. Testar DNS resolution de dentro do pod
kubectl exec -n kube-system <CSI_POD> -c ebs-plugin -- \
  nslookup sts.us-east-1.amazonaws.com

# 4. Testar conectividade HTTPS
kubectl exec -n kube-system <CSI_POD> -c ebs-plugin -- \
  curl -v https://sts.us-east-1.amazonaws.com --max-time 5
```

**Fix:**

Criar NetworkPolicy permitindo DNS + HTTPS para AWS APIs:

```yaml
# allow-ebs-csi-aws-api.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ebs-csi-aws-api
  namespace: kube-system
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: aws-ebs-csi-driver
  policyTypes:
  - Egress
  egress:
  # Allow DNS
  - ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
    to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
  # Allow AWS APIs (STS, EC2, etc) via HTTPS
  - ports:
    - protocol: TCP
      port: 443
    to:
    - ipBlock:
        cidr: 0.0.0.0/0
        except:
        - 10.0.0.0/8  # Exclude internal VPC
```

```bash
kubectl apply -f allow-ebs-csi-aws-api.yaml
```

**Validação:**

```bash
# Re-test DNS + HTTPS
kubectl exec -n kube-system <CSI_POD> -c ebs-plugin -- \
  curl -v https://sts.us-east-1.amazonaws.com --max-time 5
```

---

#### 3.4 Volume Affinity Mismatch

**Sintoma:**
```
PVC permanece Pending com VolumeBindingMode: WaitForFirstConsumer
Pod não consegue agendar em nenhum node (no nodes match topology)
```

**Diagnóstico:**

```bash
# 1. Verificar eventos do PVC
kubectl describe pvc <PVC_NAME> -n <NAMESPACE>

# Look for:
# Warning  VolumeBindingFailed  volume.kubernetes.io/provisioner "ebs.csi.aws.com" not found

# 2. Verificar pod que usa o PVC
kubectl describe pod <POD_NAME> -n <NAMESPACE>

# Look for:
# Warning  FailedScheduling  no nodes match topology

# 3. Listar volumes existentes e suas zones
kubectl get pv -o custom-columns=NAME:.metadata.name,ZONE:.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]

# 4. Listar nodes disponíveis e suas zones
kubectl get nodes -o custom-columns=NAME:.metadata.name,ZONE:.metadata.labels.topology\.kubernetes\.io/zone
```

**Root Cause:**
EBS volumes são zonais (tied to specific AZ). Se PVC foi criado em us-east-1a, mas todos nodes estão em us-east-1b, volume não pode ser attached.

**Fix Scenario 1: Volume Órfão (Vault nunca inicializou)**

```bash
# SAFE: Se aplicação NUNCA rodou (Vault nunca inicializado)
# Delete PVC e PV para forçar recriação na zona correta

# 1. Delete PVC
kubectl delete pvc <PVC_NAME> -n <NAMESPACE>

# 2. Delete PV órfão (se existir)
kubectl delete pv <PV_NAME>

# 3. StatefulSet recria PVC automaticamente
# Novo volume será criado na mesma AZ do node disponível
```

**Fix Scenario 2: Volume com Dados (PERIGOSO)**

```bash
# DANGER: Se volume contém dados importantes

# Opção A: Escalar NodeGroup na AZ do volume
# 1. Identificar AZ do volume
kubectl get pv <PV_NAME> -o jsonpath='{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}'

# 2. Adicionar node na AZ correta via Terraform/Console
# terraform apply com desired_size aumentado

# Opção B: Snapshot + Restore em nova AZ (complexo, ver AWS docs)
```

---

## 📊 Métricas de Monitoramento

### Prometheus Alerts

```yaml
# PVC stuck Pending alert
groups:
- name: storage
  rules:
  - alert: PVCPendingTooLong
    expr: kube_persistentvolumeclaim_status_phase{phase="Pending"} > 0
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "PVC {{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} stuck Pending"

  - alert: CSIDriverDown
    expr: up{job="ebs-csi-controller"} == 0
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "EBS CSI Driver controller is down"

  - alert: VPCEndpointDown
    expr: aws_vpc_endpoint_state{endpoint_type="Interface"} != 1
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "VPC Endpoint {{ $labels.endpoint_id }} not available"
```

### Key Metrics

| Métrica | Threshold | Ação |
|---------|-----------|------|
| **PVC Provisioning Time** | P95 < 60s | Normal |
| **PVC Provisioning Time** | P95 > 120s | Investigate CSI/AWS API latency |
| **CSI Error Rate** | < 1% | Normal |
| **CSI Error Rate** | > 5% | Check VPC Endpoints, IRSA, NetworkPolicies |
| **STS API Latency** | P95 < 10ms | Normal (com VPC Endpoint) |
| **STS API Latency** | P95 > 100ms | Missing VPC Endpoint ou NAT congestion |

---

## 🎯 Checklist Preventivo

### Before Deploy

- [ ] VPC Endpoints criados (STS, EC2)
- [ ] IRSA configurado para CSI driver ServiceAccount
- [ ] NetworkPolicies permitem DNS + HTTPS para AWS APIs
- [ ] StorageClass `gp3` configurada com `volumeBindingMode: WaitForFirstConsumer`
- [ ] Nodes distribuídos em múltiplas AZs (se HA necessário)

### After Incident

- [ ] Logs CSI driver salvos para post-mortem
- [ ] Métricas Prometheus/Grafana analisadas
- [ ] Root cause documentado em logbook
- [ ] Runbook atualizado com novo cenário (se aplicável)
- [ ] ADR criado se decisão arquitetural necessária

---

## 📚 Referências

- [AWS EBS CSI Driver Docs](https://github.com/kubernetes-sigs/aws-ebs-csi-driver)
- [VPC Endpoints Pricing](https://aws.amazon.com/privatelink/pricing/)
- [IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [Logbook: 2026-02-06 Vault Recovery](../logbook/2026-02-06-vault-recovery-vpc-endpoints.md)
- [ADR-046: VPC Endpoints for EKS](../context/decisions.md#adr-046-vpc-endpoints-for-eks-critical-infrastructure)
- [R-030: Missing VPC Endpoints](../context/risks.md#r-030-missing-vpc-endpoints-ebs-csi-driver-blocked--resolvido)

---

## 🔄 Histórico de Mudanças

| Data | Versão | Mudança | Autor |
|------|--------|---------|-------|
| 2026-02-06 | 1.0 | Criação inicial pós-incident Vault recovery | DevOps Team |
