# 01 - Infraestrutura Base AWS

**Épico A** | **Esforço: 20 person-hours** | **Sprint 1**

---

## Sumário

1. [Visão Geral](#1-visão-geral)
2. [Task A.1: VPC Multi-AZ (6h)](#2-task-a1-vpc-multi-az-6h)
3. [Task A.2: EKS Cluster e Node Groups (8h)](#3-task-a2-eks-cluster-e-node-groups-8h)
4. [Task A.3: StorageClass e PVC Templates (2h)](#4-task-a3-storageclass-e-pvc-templates-2h)
5. [Task A.4: IAM Roles e RBAC (4h)](#5-task-a4-iam-roles-e-rbac-4h)
6. [Validação e Definition of Done](#6-validação-e-definition-of-done)
7. [Troubleshooting](#7-troubleshooting)

---

## 1. Visão Geral

### Objetivo

Provisionar toda a infraestrutura base AWS necessária para hospedar a plataforma Kubernetes:

- **VPC** com subnets públicas, privadas e de dados em 3 AZs
- **EKS Cluster** com 3 node groups especializados
- **StorageClass** gp3 para volumes persistentes
- **IAM Roles** com princípio de menor privilégio

### Arquitetura de Rede

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           VPC: 10.0.0.0/16                                  │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    AVAILABILITY ZONE: us-east-1a                     │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐     │   │
│  │  │ Public Subnet   │  │ Private Subnet  │  │ Data Subnet     │     │   │
│  │  │ 10.0.1.0/24     │  │ 10.0.11.0/24    │  │ 10.0.21.0/24    │     │   │
│  │  │ • NAT Gateway   │  │ • EKS Nodes     │  │ • RDS           │     │   │
│  │  │ • ALB           │  │                 │  │                 │     │   │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    AVAILABILITY ZONE: us-east-1b                     │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐     │   │
│  │  │ Public Subnet   │  │ Private Subnet  │  │ Data Subnet     │     │   │
│  │  │ 10.0.2.0/24     │  │ 10.0.12.0/24    │  │ 10.0.22.0/24    │     │   │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    AVAILABILITY ZONE: us-east-1c                     │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐     │   │
│  │  │ Public Subnet   │  │ Private Subnet  │  │ Data Subnet     │     │   │
│  │  │ 10.0.3.0/24     │  │ 10.0.13.0/24    │  │ 10.0.23.0/24    │     │   │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Node Groups

| Node Group | Instance Type | vCPU | RAM | Nodes | Propósito |
|------------|--------------|------|-----|-------|-----------|
| `system` | t3.medium | 2 | 4GB | 2 (2-4) | Sistema: CoreDNS, controllers |
| `workloads` | t3.large | 2 | 8GB | 3 (2-6) | Aplicações: Redis, RabbitMQ |
| `critical` | t3.xlarge | 4 | 16GB | 2 (2-4) | Crítico: GitLab, Databases |

---

## 2. Task A.1: VPC Multi-AZ (6h)

### 2.1 Criar VPC com Wizard

**Passo a passo no Console AWS:**

1. Acesse o Console AWS: https://console.aws.amazon.com/
2. Certifique-se de estar na região **us-east-1** (N. Virginia)
3. Na barra de busca, digite `VPC` e clique em **VPC**
4. Clique em **Create VPC**
5. Selecione **VPC and more** (wizard completo)
6. Preencha os campos:

   **Name tag auto-generation:**
   | Campo | Valor |
   |-------|-------|
   | **Auto-generate** | ✅ Marcar |
   | **Name** | `k8s-platform-prod` |

   **IPv4 CIDR block:**
   | Campo | Valor |
   |-------|-------|
   | **IPv4 CIDR** | `10.0.0.0/16` |

   **IPv6 CIDR block:**
   | Campo | Valor |
   |-------|-------|
   | **IPv6 CIDR block** | No IPv6 CIDR block |

   **Tenancy:**
   | Campo | Valor |
   |-------|-------|
   | **Tenancy** | Default |

   **Number of Availability Zones:**
   | Campo | Valor |
   |-------|-------|
   | **Number of AZs** | 3 |

   **Number of public subnets:**
   | Campo | Valor |
   |-------|-------|
   | **Public subnets** | 3 |

   **Number of private subnets:**
   | Campo | Valor |
   |-------|-------|
   | **Private subnets** | 3 |

   **NAT gateways:**
   | Campo | Valor |
   |-------|-------|
   | **NAT gateways** | In 1 AZ |

   > **Nota FinOps:** Para alta disponibilidade total, use "1 per AZ" (+$80/mês)

   **VPC endpoints:**
   | Campo | Valor |
   |-------|-------|
   | **S3 Gateway** | ✅ Marcar |

   **DNS options:**
   | Campo | Valor |
   |-------|-------|
   | **Enable DNS hostnames** | ✅ Marcar |
   | **Enable DNS resolution** | ✅ Marcar |

7. Revise o diagrama gerado automaticamente
8. Clique em **Create VPC**
9. Aguarde a criação (2-3 minutos)

**Contexto:** O wizard cria automaticamente subnets, route tables, internet gateway, NAT gateway e VPC endpoint para S3.

---

### 2.2 Criar Subnets de Dados (RDS)

O wizard não cria subnets específicas para dados. Vamos criar manualmente:

**Passo a passo no Console AWS:**

1. No VPC Dashboard, menu lateral, clique em **Subnets**
2. Clique em **Create subnet**
3. Preencha:

   **VPC ID:**
   | Campo | Valor |
   |-------|-------|
   | **VPC** | Selecione `k8s-platform-prod-vpc` |

   **Subnet 1:**
   | Campo | Valor |
   |-------|-------|
   | **Subnet name** | `k8s-platform-prod-db-us-east-1a` |
   | **Availability Zone** | `us-east-1a` |
   | **IPv4 CIDR block** | `10.0.21.0/24` |

4. Clique em **Add new subnet**

   **Subnet 2:**
   | Campo | Valor |
   |-------|-------|
   | **Subnet name** | `k8s-platform-prod-db-us-east-1b` |
   | **Availability Zone** | `us-east-1b` |
   | **IPv4 CIDR block** | `10.0.22.0/24` |

5. Clique em **Add new subnet**

   **Subnet 3:**
   | Campo | Valor |
   |-------|-------|
   | **Subnet name** | `k8s-platform-prod-db-us-east-1c` |
   | **Availability Zone** | `us-east-1c` |
   | **IPv4 CIDR block** | `10.0.23.0/24` |

6. Clique em **Create subnet**

---

### 2.3 Associar Subnets de Dados à Route Table Privada

1. Selecione uma das subnets de dados criadas
2. Clique na aba **Route table**
3. Clique em **Edit route table association**
4. Selecione a route table **privada** (a que tem rota para NAT Gateway)
5. Clique em **Save**
6. Repita para as outras 2 subnets de dados

---

### 2.4 Adicionar Tags para EKS

As subnets precisam de tags específicas para o EKS criar load balancers:

**Subnets Públicas (para ALB externo):**

1. Selecione CADA subnet **pública** (uma por vez)
2. Clique na aba **Tags**
3. Clique em **Manage tags**
4. Adicione as tags:

   | Key | Value |
   |-----|-------|
   | `kubernetes.io/cluster/k8s-platform-prod` | `shared` |
   | `kubernetes.io/role/elb` | `1` |

5. Clique em **Save**

**Subnets Privadas (para nodes e ALB interno):**

1. Selecione CADA subnet **privada** (uma por vez)
2. Adicione as tags:

   | Key | Value |
   |-----|-------|
   | `kubernetes.io/cluster/k8s-platform-prod` | `shared` |
   | `kubernetes.io/role/internal-elb` | `1` |

3. Clique em **Save**

**Via CLI (mais rápido):**

```bash
# Obter IDs das subnets
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=k8s-platform-prod-vpc" --query "Vpcs[0].VpcId" --output text)

# Subnets públicas
PUBLIC_SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*public*" --query "Subnets[*].SubnetId" --output text)

for subnet in $PUBLIC_SUBNETS; do
  aws ec2 create-tags --resources $subnet --tags \
    Key=kubernetes.io/cluster/k8s-platform-prod,Value=shared \
    Key=kubernetes.io/role/elb,Value=1
  echo "Tagged public subnet: $subnet"
done

# Subnets privadas
PRIVATE_SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*private*" --query "Subnets[*].SubnetId" --output text)

for subnet in $PRIVATE_SUBNETS; do
  aws ec2 create-tags --resources $subnet --tags \
    Key=kubernetes.io/cluster/k8s-platform-prod,Value=shared \
    Key=kubernetes.io/role/internal-elb,Value=1
  echo "Tagged private subnet: $subnet"
done
```

---

### 2.5 Criar Security Groups

**Security Group para EKS Cluster:**

1. No VPC Dashboard, menu lateral, clique em **Security groups**
2. Clique em **Create security group**
3. Preencha:

   | Campo | Valor |
   |-------|-------|
   | **Security group name** | `k8s-platform-prod-eks-cluster-sg` |
   | **Description** | `Security Group para EKS Control Plane` |
   | **VPC** | Selecione `k8s-platform-prod-vpc` |

4. **Inbound rules:** Deixe vazio (será configurado pelo EKS)

5. **Outbound rules:**
   | Type | Destination | Description |
   |------|-------------|-------------|
   | All traffic | 0.0.0.0/0 | Allow all outbound |

6. **Tags:**
   | Key | Value |
   |-----|-------|
   | `Name` | `k8s-platform-prod-eks-cluster-sg` |
   | `Project` | `k8s-platform` |
   | `Environment` | `prod` |

7. Clique em **Create security group**

**Security Group para RDS:**

1. Clique em **Create security group**
2. Preencha:

   | Campo | Valor |
   |-------|-------|
   | **Security group name** | `k8s-platform-prod-rds-sg` |
   | **Description** | `Security Group para RDS PostgreSQL` |
   | **VPC** | Selecione `k8s-platform-prod-vpc` |

3. **Inbound rules:**
   | Type | Port | Source | Description |
   |------|------|--------|-------------|
   | PostgreSQL | 5432 | `k8s-platform-prod-eks-cluster-sg` | EKS to RDS |

4. **Tags:**
   | Key | Value |
   |-----|-------|
   | `Name` | `k8s-platform-prod-rds-sg` |
   | `Project` | `k8s-platform` |

5. Clique em **Create security group**

---

### 2.6 Documentar IDs Criados

Anote os seguintes IDs para uso posterior:

```bash
# Obter e salvar IDs
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=k8s-platform-prod-vpc" --query "Vpcs[0].VpcId" --output text)
echo "VPC_ID: $VPC_ID"

PRIVATE_SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*private*" --query "Subnets[*].SubnetId" --output text | tr '\t' ',')
echo "PRIVATE_SUBNETS: $PRIVATE_SUBNETS"

EKS_SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=k8s-platform-prod-eks-cluster-sg" --query "SecurityGroups[0].GroupId" --output text)
echo "EKS_SG: $EKS_SG"

RDS_SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=k8s-platform-prod-rds-sg" --query "SecurityGroups[0].GroupId" --output text)
echo "RDS_SG: $RDS_SG"
```

---

## 3. Task A.2: EKS Cluster e Node Groups (8h)

### 3.1 Criar IAM Role para EKS Cluster

**Passo a passo no Console AWS:**

1. Na barra de busca, digite `IAM` e clique em **IAM**
2. No menu lateral, clique em **Roles**
3. Clique em **Create role**
4. Preencha:

   **Step 1 - Select trusted entity:**
   | Campo | Valor |
   |-------|-------|
   | **Trusted entity type** | AWS service |
   | **Use case** | EKS |
   | **Use case (dropdown)** | EKS - Cluster |

5. Clique em **Next**

   **Step 2 - Add permissions:**
   - A policy `AmazonEKSClusterPolicy` já estará selecionada

6. Clique em **Next**

   **Step 3 - Name, review, and create:**
   | Campo | Valor |
   |-------|-------|
   | **Role name** | `k8s-platform-eks-cluster-role` |
   | **Description** | `IAM Role para EKS Control Plane` |

7. **Tags:**
   | Key | Value |
   |-----|-------|
   | `Project` | `k8s-platform` |
   | `Environment` | `prod` |

8. Clique em **Create role**

---

### 3.2 Criar IAM Role para EKS Node Group

1. Em **Roles**, clique em **Create role**
2. Preencha:

   **Step 1:**
   | Campo | Valor |
   |-------|-------|
   | **Trusted entity type** | AWS service |
   | **Use case** | EC2 |

3. Clique em **Next**

   **Step 2 - Add permissions:**
   Busque e selecione:
   - `AmazonEKSWorkerNodePolicy`
   - `AmazonEKS_CNI_Policy`
   - `AmazonEC2ContainerRegistryReadOnly`
   - `AmazonSSMManagedInstanceCore`

4. Clique em **Next**

   **Step 3:**
   | Campo | Valor |
   |-------|-------|
   | **Role name** | `k8s-platform-eks-node-role` |
   | **Description** | `IAM Role para EKS Worker Nodes` |

5. **Tags:** (mesmas do cluster role)

6. Clique em **Create role**

---

### 3.3 Criar Cluster EKS

**Passo a passo no Console AWS:**

1. Na barra de busca, digite `EKS` e clique em **Elastic Kubernetes Service**
2. Clique em **Add cluster** → **Create**
3. Preencha:

   **Step 1 - Configure cluster:**

   | Campo | Valor |
   |-------|-------|
   | **Name** | `k8s-platform-prod` |
   | **Kubernetes version** | `1.29` (ou mais recente estável) |
   | **Cluster service role** | Selecione `k8s-platform-eks-cluster-role` |

   **Secrets encryption:**
   | Campo | Valor |
   |-------|-------|
   | **Turn on envelope encryption** | ✅ Marcar |
   | **KMS key** | Criar nova ou selecionar existente |

   **Tags:**
   | Key | Value |
   |-----|-------|
   | `Project` | `k8s-platform` |
   | `Environment` | `prod` |
   | `Owner` | `devops-team` |

4. Clique em **Next**

   **Step 2 - Specify networking:**

   | Campo | Valor |
   |-------|-------|
   | **VPC** | Selecione `k8s-platform-prod-vpc` |
   | **Subnets** | Selecione TODAS as subnets **privadas** (3) |
   | **Security groups** | Selecione `k8s-platform-prod-eks-cluster-sg` |
   | **Cluster endpoint access** | Public and private |

   **Advanced settings:**
   | Campo | Valor |
   |-------|-------|
   | **Public access CIDR** | Adicione IPs permitidos (ex: `203.0.113.0/24`) |

   > **Segurança:** Restrinja o acesso público apenas aos IPs do seu escritório

5. Clique em **Next**

   **Step 3 - Configure observability:**

   | Campo | Valor |
   |-------|-------|
   | **API server** | ✅ Marcar |
   | **Audit** | ✅ Marcar |
   | **Authenticator** | ✅ Marcar |
   | **Controller manager** | ✅ Marcar |
   | **Scheduler** | ✅ Marcar |

6. Clique em **Next**

   **Step 4 - Select add-ons:**

   Selecione todos os add-ons padrão:
   - ✅ Amazon VPC CNI
   - ✅ CoreDNS
   - ✅ kube-proxy
   - ✅ Amazon EBS CSI Driver

7. Clique em **Next**

   **Step 5 - Configure selected add-ons settings:**
   - Deixe as configurações padrão
   - Selecione versões mais recentes

8. Clique em **Next** → **Create**

9. **Aguarde a criação** (15-20 minutos)

---

### 3.4 Configurar kubectl

Após o cluster estar `Active`:

```bash
# Atualizar kubeconfig
aws eks update-kubeconfig --region us-east-1 --name k8s-platform-prod

# Verificar conexão
kubectl cluster-info

# Saída esperada:
# Kubernetes control plane is running at https://xxxxx.gr7.us-east-1.eks.amazonaws.com
# CoreDNS is running at https://xxxxx.gr7.us-east-1.eks.amazonaws.com/api/v1/...

# Verificar nodes (ainda não haverá nodes)
kubectl get nodes
# No resources found
```

---

### 3.5 Criar Node Group: system

**Passo a passo no Console AWS:**

1. No EKS, clique no cluster `k8s-platform-prod`
2. Aba **Compute** → **Add node group**
3. Preencha:

   **Step 1 - Configure node group:**

   | Campo | Valor |
   |-------|-------|
   | **Name** | `system` |
   | **Node IAM role** | Selecione `k8s-platform-eks-node-role` |

   **Node group scaling configuration:**
   | Campo | Valor |
   |-------|-------|
   | **Desired size** | `2` |
   | **Minimum size** | `2` |
   | **Maximum size** | `4` |

   **Node group update configuration:**
   | Campo | Valor |
   |-------|-------|
   | **Maximum unavailable** | Number → `1` |

   **Labels:**
   | Key | Value |
   |-----|-------|
   | `node-type` | `system` |
   | `workload` | `platform` |

   **Taints:** Deixe vazio

   **Tags:**
   | Key | Value |
   |-----|-------|
   | `Project` | `k8s-platform` |
   | `NodeGroup` | `system` |

4. Clique em **Next**

   **Step 2 - Set compute and scaling configuration:**

   | Campo | Valor |
   |-------|-------|
   | **AMI type** | Amazon Linux 2 (AL2_x86_64) |
   | **Capacity type** | On-Demand |
   | **Instance types** | `t3.medium` |
   | **Disk size** | `30` GB |

5. Clique em **Next**

   **Step 3 - Specify networking:**

   | Campo | Valor |
   |-------|-------|
   | **Subnets** | Selecione as 3 subnets **privadas** |
   | **Configure remote access** | Don't allow remote access to nodes |

   > **Segurança:** Use Session Manager para acesso aos nodes se necessário

6. Clique em **Next** → **Create**

---

### 3.6 Criar Node Group: workloads

1. Em **Compute** → **Add node group**
2. Preencha:

   | Campo | Valor |
   |-------|-------|
   | **Name** | `workloads` |
   | **Node IAM role** | `k8s-platform-eks-node-role` |
   | **Desired size** | `3` |
   | **Minimum size** | `2` |
   | **Maximum size** | `6` |

   **Labels:**
   | Key | Value |
   |-----|-------|
   | `node-type` | `workloads` |
   | `workload` | `applications` |

   **Compute:**
   | Campo | Valor |
   |-------|-------|
   | **Instance types** | `t3.large` |
   | **Disk size** | `50` GB |

3. Complete os passos e clique em **Create**

---

### 3.7 Criar Node Group: critical

1. Em **Compute** → **Add node group**
2. Preencha:

   | Campo | Valor |
   |-------|-------|
   | **Name** | `critical` |
   | **Node IAM role** | `k8s-platform-eks-node-role` |
   | **Desired size** | `2` |
   | **Minimum size** | `2` |
   | **Maximum size** | `4` |

   **Labels:**
   | Key | Value |
   |-----|-------|
   | `node-type` | `critical` |
   | `workload` | `databases` |

   **Taints:**
   | Key | Value | Effect |
   |-----|-------|--------|
   | `workload` | `critical` | `NoSchedule` |

   **Compute:**
   | Campo | Valor |
   |-------|-------|
   | **Instance types** | `t3.xlarge` |
   | **Disk size** | `100` GB |

3. Complete os passos e clique em **Create**

---

### 3.8 Verificar Nodes

Aguarde os node groups ficarem `Active` (5-10 minutos cada):

```bash
# Verificar nodes
kubectl get nodes -o wide

# Saída esperada:
# NAME                             STATUS   ROLES    AGE   VERSION
# ip-10-0-11-xxx.ec2.internal     Ready    <none>   5m    v1.29.0-eks-xxxxx
# ip-10-0-12-xxx.ec2.internal     Ready    <none>   5m    v1.29.0-eks-xxxxx
# ...

# Verificar labels
kubectl get nodes --show-labels | grep node-type

# Verificar taints
kubectl describe nodes | grep -A 5 Taints
```

---

## 4. Task A.3: StorageClass e PVC Templates (2h)

### 4.1 Verificar EBS CSI Driver

```bash
# Verificar se o EBS CSI Driver está instalado
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver

# Saída esperada:
# NAME                                  READY   STATUS    RESTARTS   AGE
# ebs-csi-controller-xxxxxxxxx-xxxxx   6/6     Running   0          10m
# ebs-csi-node-xxxxx                   3/3     Running   0          10m
# ...
```

---

### 4.2 Criar StorageClass gp3

```bash
cat > storageclass-gp3.yaml <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  fsType: ext4
  encrypted: "true"
  # Performance otimizada
  iops: "3000"
  throughput: "125"
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF

kubectl apply -f storageclass-gp3.yaml

# Verificar
kubectl get storageclass
```

---

### 4.3 Remover StorageClass Padrão Anterior

```bash
# Verificar qual é a StorageClass padrão atual
kubectl get storageclass | grep "(default)"

# Se houver outra default, remover a annotation
kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

# Verificar que gp3 é a default
kubectl get storageclass
# NAME   PROVISIONER       RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
# gp2    ebs.csi.aws.com   Delete          WaitForFirstConsumer   true                   30m
# gp3 (default)   ebs.csi.aws.com   Delete   WaitForFirstConsumer   true                1m
```

---

### 4.4 Criar PVC Template de Teste

```bash
cat > test-pvc.yaml <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gp3
  resources:
    requests:
      storage: 1Gi
EOF

kubectl apply -f test-pvc.yaml

# Verificar (ficará Pending até um pod usar)
kubectl get pvc test-pvc

# Criar pod de teste para provisionar o volume
cat > test-pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
  namespace: default
spec:
  containers:
  - name: test
    image: nginx:alpine
    volumeMounts:
    - mountPath: /data
      name: test-volume
  volumes:
  - name: test-volume
    persistentVolumeClaim:
      claimName: test-pvc
EOF

kubectl apply -f test-pod.yaml

# Aguardar e verificar
kubectl get pvc test-pvc
# STATUS deve mudar para Bound

kubectl get pv
# Deve mostrar o PV provisionado

# Limpar
kubectl delete pod test-pod
kubectl delete pvc test-pvc
```

---

## 5. Task A.4: IAM Roles e RBAC (4h)

### 5.1 Criar OIDC Provider para IRSA

IRSA (IAM Roles for Service Accounts) permite que pods assumam roles IAM:

```bash
# Verificar se já existe
CLUSTER_NAME="k8s-platform-prod"
OIDC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5)
echo "OIDC ID: $OIDC_ID"

# Verificar se o provider existe
aws iam list-open-id-connect-providers | grep $OIDC_ID

# Se não existir, criar
eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --approve --region us-east-1
```

---

### 5.2 Criar Namespaces Básicos

```bash
# Criar namespaces
for ns in gitlab observability redis rabbitmq; do
  kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
  kubectl label namespace $ns project=k8s-platform environment=prod
done

# Verificar
kubectl get namespaces --show-labels | grep k8s-platform
```

---

### 5.3 Criar RBAC Básico

**ClusterRole para leitura (observadores):**

```bash
cat > clusterrole-reader.yaml <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: k8s-platform-reader
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "namespaces"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets", "daemonsets"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get", "list"]
EOF

kubectl apply -f clusterrole-reader.yaml
```

**ClusterRole para operadores:**

```bash
cat > clusterrole-operator.yaml <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: k8s-platform-operator
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets", "persistentvolumeclaims"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets", "daemonsets", "replicasets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["pods/exec", "pods/log", "pods/portforward"]
  verbs: ["get", "create"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses", "networkpolicies"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
EOF

kubectl apply -f clusterrole-operator.yaml
```

---

### 5.4 Mapear Usuários IAM para RBAC

Editar o ConfigMap `aws-auth`:

```bash
# Obter ConfigMap atual
kubectl get configmap aws-auth -n kube-system -o yaml > aws-auth-backup.yaml

# Editar para adicionar usuários
kubectl edit configmap aws-auth -n kube-system
```

Adicione na seção `mapUsers`:

```yaml
data:
  mapRoles: |
    - groups:
      - system:bootstrappers
      - system:nodes
      rolearn: arn:aws:iam::ACCOUNT_ID:role/k8s-platform-eks-node-role
      username: system:node:{{EC2PrivateDNSName}}
  mapUsers: |
    - userarn: arn:aws:iam::ACCOUNT_ID:user/admin-user
      username: admin
      groups:
        - system:masters
    - userarn: arn:aws:iam::ACCOUNT_ID:user/operator-user
      username: operator
      groups:
        - k8s-platform-operator
    - userarn: arn:aws:iam::ACCOUNT_ID:user/reader-user
      username: reader
      groups:
        - k8s-platform-reader
```

> **Substitua** `ACCOUNT_ID` pelo seu AWS Account ID

---

### 5.5 Criar RoleBindings

```bash
# Binding para readers
cat > rolebinding-reader.yaml <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: k8s-platform-readers
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: k8s-platform-reader
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: k8s-platform-reader
EOF

kubectl apply -f rolebinding-reader.yaml

# Binding para operators
cat > rolebinding-operator.yaml <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: k8s-platform-operators
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: k8s-platform-operator
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: k8s-platform-operator
EOF

kubectl apply -f rolebinding-operator.yaml
```

---

## 6. Validação e Definition of Done

### Checklist de Validação

```bash
# 1. VPC
echo "=== VPC ==="
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=k8s-platform-prod-vpc" --query "Vpcs[0].VpcId"

# 2. Subnets
echo "=== Subnets (9 esperadas) ==="
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].[SubnetId,CidrBlock,Tags[?Key=='Name'].Value|[0]]" --output table

# 3. NAT Gateway
echo "=== NAT Gateway ==="
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" --query "NatGateways[*].[NatGatewayId,State]" --output table

# 4. EKS Cluster
echo "=== EKS Cluster ==="
aws eks describe-cluster --name k8s-platform-prod --query "cluster.[name,status,version]" --output table

# 5. Node Groups
echo "=== Node Groups ==="
aws eks list-nodegroups --cluster-name k8s-platform-prod

# 6. Nodes no cluster
echo "=== Nodes (7 esperados) ==="
kubectl get nodes

# 7. StorageClass
echo "=== StorageClass (gp3 default) ==="
kubectl get storageclass

# 8. Namespaces
echo "=== Namespaces ==="
kubectl get namespaces

# 9. RBAC
echo "=== ClusterRoles ==="
kubectl get clusterroles | grep k8s-platform
```

### Definition of Done - Épico A

- [ ] **VPC e Networking**
  - [ ] VPC criada com CIDR 10.0.0.0/16
  - [ ] 9 subnets criadas (3 public + 3 private + 3 data)
  - [ ] NAT Gateway operacional
  - [ ] Internet Gateway operacional
  - [ ] S3 VPC Endpoint configurado
  - [ ] Tags de EKS nas subnets

- [ ] **EKS Cluster**
  - [ ] Cluster `k8s-platform-prod` com status `Active`
  - [ ] Versão Kubernetes 1.29+
  - [ ] Control plane logs habilitados
  - [ ] Secrets encryption habilitado
  - [ ] `kubectl cluster-info` funciona

- [ ] **Node Groups**
  - [ ] Node group `system` (2 nodes t3.medium) - Active
  - [ ] Node group `workloads` (3 nodes t3.large) - Active
  - [ ] Node group `critical` (2 nodes t3.xlarge) - Active
  - [ ] Todos os 7 nodes com status `Ready`
  - [ ] Labels corretos aplicados
  - [ ] Taints corretos aplicados (critical)

- [ ] **Storage**
  - [ ] EBS CSI Driver operacional
  - [ ] StorageClass `gp3` como default
  - [ ] PVC de teste provisionado com sucesso

- [ ] **IAM e RBAC**
  - [ ] OIDC Provider criado
  - [ ] Role para cluster funcional
  - [ ] Role para nodes funcional
  - [ ] ClusterRoles criados
  - [ ] aws-auth ConfigMap configurado

- [ ] **Documentação**
  - [ ] VPC ID documentado
  - [ ] Subnet IDs documentados
  - [ ] Security Group IDs documentados
  - [ ] Comandos de acesso documentados

---

## 7. Troubleshooting

### Problema: Nodes não aparecem

```bash
# Verificar status do node group
aws eks describe-nodegroup --cluster-name k8s-platform-prod --nodegroup-name system

# Verificar Auto Scaling Group
aws autoscaling describe-auto-scaling-groups --filters "Name=tag:eks:cluster-name,Values=k8s-platform-prod"

# Verificar instâncias EC2
aws ec2 describe-instances --filters "Name=tag:eks:cluster-name,Values=k8s-platform-prod" --query "Reservations[*].Instances[*].[InstanceId,State.Name,PrivateIpAddress]" --output table

# Causas comuns:
# - Subnet sem rota para NAT Gateway
# - Security Group muito restritivo
# - IAM Role sem permissões
```

### Problema: Nodes em NotReady

```bash
# Verificar logs do kubelet
kubectl describe node <node-name>

# Verificar eventos
kubectl get events --all-namespaces --sort-by='.lastTimestamp'

# Causas comuns:
# - CNI não instalado corretamente
# - Problema de rede (Security Group)
# - Disco cheio
```

### Problema: StorageClass não provisiona

```bash
# Verificar EBS CSI Driver
kubectl get pods -n kube-system | grep ebs

# Verificar logs do controller
kubectl logs -n kube-system -l app=ebs-csi-controller

# Causas comuns:
# - IRSA não configurado para EBS CSI
# - Zona indisponível
# - Limite de volumes EBS
```

### Problema: Acesso negado ao cluster

```bash
# Verificar identidade atual
aws sts get-caller-identity

# Verificar aws-auth ConfigMap
kubectl get configmap aws-auth -n kube-system -o yaml

# Causas comuns:
# - Usuário não mapeado no aws-auth
# - Grupo incorreto no RBAC
# - Credenciais AWS erradas
```

---

## Próximos Passos

Após concluir este documento:

1. Prosseguir para **[03-data-services-helm.md](03-data-services-helm.md)** (RDS, Redis, RabbitMQ)
2. Depois **[02-gitlab-helm-deploy.md](02-gitlab-helm-deploy.md)** (GitLab)

---

**Documento:** 01-infraestrutura-base-aws.md
**Versão:** 1.0
**Última atualização:** 2026-01-19
**Épico:** A
**Esforço:** 20 person-hours
