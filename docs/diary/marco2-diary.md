# Marco 2 - Platform Services - Diary

## Visão Geral
Marco 2 adiciona serviços essenciais de plataforma sobre o cluster EKS criado no Marco 1.

**Objetivo**: Instalar e configurar serviços fundamentais para operação e gerenciamento do cluster.

---

## Fase 1: AWS Load Balancer Controller ✅

**Data**: 2026-01-26

### Objetivos
- Instalar AWS Load Balancer Controller para gerenciar ALBs e NLBs via Ingress
- Configurar IRSA (IAM Roles for Service Accounts)
- Habilitar provisionamento automático de load balancers

### Implementação
1. Criado módulo Terraform em `envs/marco2/modules/aws-load-balancer-controller/`
2. Componentes criados:
   - IAM Policy com permissões para gerenciar ELBs
   - IAM Role com trust relationship para OIDC Provider do EKS
   - Kubernetes Service Account com annotation da IAM Role
   - Helm release do AWS Load Balancer Controller v1.10.2

### Validação
```bash
# Verificar pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Verificar deployment
kubectl get deployment aws-load-balancer-controller -n kube-system

# Verificar service account
kubectl get sa aws-load-balancer-controller -n kube-system -o yaml
```

### Status
✅ **COMPLETO** - Controller instalado e operacional

---

## Fase 2: Cert-Manager ✅

**Data**: 2026-01-26

### Objetivos
- Instalar Cert-Manager para gerenciamento automático de certificados TLS
- Configurar ClusterIssuers para Let's Encrypt (staging e production)
- Criar issuer self-signed para testes internos

### Implementação
1. Criado módulo Terraform em `envs/marco2/modules/cert-manager/`
2. Helm chart v1.16.3 instalado com `installCRDs: true`
3. ClusterIssuers criados via kubectl (devido ao timing de CRDs):
   - `letsencrypt-staging`: Para testes (rate limits mais altos)
   - `letsencrypt-production`: Para produção (50 certs/semana/domínio)
   - `selfsigned-issuer`: Para certificados internos

### Desafios Encontrados

#### 1. CRD Timing Issue
**Problema**: Terraform tentava criar ClusterIssuers antes dos CRDs existirem.
```
Error: API did not recognize GroupVersionKind from manifest
no matches for kind "ClusterIssuer" in group "cert-manager.io"
```

**Solução**:
- Desabilitado `create_cluster_issuers = false` no módulo Terraform
- ClusterIssuers criados manualmente via kubectl após instalação do Helm chart

#### 2. Email Validation
**Problema**: Let's Encrypt rejeitou email example.com
```
Error validating contact :: contact email has forbidden domain "example.com"
```

**Solução**: Atualizado para email real: gilvan.galindo@fctconsig.com.br

### Validação de Certificados
Teste realizado com certificado self-signed:
```bash
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-certificate
  namespace: cert-test
spec:
  secretName: test-tls
  duration: 2160h
  renewBefore: 360h
  subject:
    organizations:
      - k8s-platform
  commonName: test.k8s-platform.local
  isCA: false
  privateKey:
    algorithm: RSA
    size: 2048
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
    group: cert-manager.io
EOF
```

**Resultado**: Certificado emitido em 12s com sucesso ✅

### Status
✅ **COMPLETO** - Cert-Manager operacional, certificados validados

---

## Fase 3: Prometheus + Grafana (kube-prometheus-stack) ✅

**Data**: 2026-01-26

### Objetivos
- Instalar stack completo de monitoramento
- Configurar coleta automática de métricas do cluster
- Provisionar armazenamento persistente para métricas
- Configurar Grafana com dashboards padrão

### Implementação
1. Criado módulo Terraform em `envs/marco2/modules/kube-prometheus-stack/`
2. Chart version: 69.4.0
3. Componentes instalados:
   - **Prometheus Operator**: Gerencia instâncias do Prometheus via CRDs
   - **Prometheus**: Coleta e armazena métricas (20Gi storage, 15d retention)
   - **Grafana**: Dashboards e visualização (5Gi storage)
   - **Alertmanager**: Gerenciamento de alertas (2Gi storage)
   - **Node Exporter**: Métricas dos nós (7 DaemonSets)
   - **Kube State Metrics**: Métricas de objetos Kubernetes

### Desafios Encontrados e Soluções

#### 1. Credenciais AWS Expiradas
**Problema**: Session AWS SSO expirou durante instalação.
```
Your session has expired. Please reauthenticate using 'aws login'
```

**Solução**:
- Reautenticação via `aws login`
- Configuração de `AWS_PROFILE=k8s-platform-prod` para Terraform e kubectl

#### 2. StorageClass gp3 Inexistente
**Problema**: PVCs ficaram Pending esperando StorageClass "gp3" que não existia.
```
Warning ProvisioningFailed: storageclass.storage.k8s.io "gp3" not found
```

**Solução**: Criada StorageClass gp3 com EBS CSI Driver:
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Delete
```

#### 3. EBS CSI Driver Sem Permissões IAM (CRÍTICO)
**Problema**: EBS CSI Driver instalado mas sem IAM Role, não conseguia provisionar volumes.
```
failed to provision volume: could not create volume in EC2:
operation error EC2: CreateVolume, get identity: get credentials:
failed to refresh cached credentials, no EC2 IMDS role found
```

**Análise**:
- Marco 1 instalou EBS CSI Driver addon sem configurar `service_account_role_arn`
- Service Account `ebs-csi-controller-sa` sem annotation `eks.amazonaws.com/role-arn`

**Solução Aplicada**:
1. Criada IAM Role para EBS CSI Driver:
```bash
# Trust policy com OIDC Provider
aws iam create-role \
  --role-name AmazonEKS_EBS_CSI_DriverRole-k8s-platform-prod \
  --assume-role-policy-document file://ebs-csi-trust-policy.json

# Attach managed policy da AWS
aws iam attach-role-policy \
  --role-name AmazonEKS_EBS_CSI_DriverRole-k8s-platform-prod \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy
```

2. Anotada Service Account:
```bash
kubectl annotate serviceaccount ebs-csi-controller-sa -n kube-system \
  eks.amazonaws.com/role-arn=arn:aws:iam::891377105802:role/AmazonEKS_EBS_CSI_DriverRole-k8s-platform-prod
```

3. Reiniciado deployment para aplicar mudanças:
```bash
kubectl rollout restart deployment ebs-csi-controller -n kube-system
```

**Resultado**: PVCs provisionados imediatamente após restart ✅

#### 4. Terraform Timeout
**Problema**: Terraform deu timeout após 12min esperando pods ficarem prontos (devido ao problema de PVC).

**Solução**:
- Resolvidos problemas de IAM e StorageClass
- Reexecutado Terraform que recriou o release com sucesso em 4m37s

### Configuração Final

**Recursos Alocados**:
- Prometheus:
  - CPU: 100m request, 500m limit
  - Memory: 512Mi request, 2Gi limit
  - Storage: 20Gi (gp3)
  - Retention: 15 days

- Grafana:
  - CPU: 50m request, 200m limit
  - Memory: 128Mi request, 256Mi limit
  - Storage: 5Gi (gp3)
  - Password: K8sPlatform2026!

- Alertmanager:
  - CPU: 10m request, 50m limit
  - Memory: 32Mi request, 64Mi limit
  - Storage: 2Gi (gp3)

**Node Scheduling**:
- Todos os componentes com `nodeSelector: node-type=system`
- Tolerations para `node-type=system:NoSchedule`
- Garante execução nos nós de sistema

### ServiceMonitors Criados
O Prometheus está coletando métricas de:
1. kube-prometheus-stack-alertmanager
2. kube-prometheus-stack-apiserver
3. kube-prometheus-stack-coredns
4. kube-prometheus-stack-grafana
5. kube-prometheus-stack-kube-controller-manager
6. kube-prometheus-stack-kube-etcd
7. kube-prometheus-stack-kube-proxy
8. kube-prometheus-stack-kube-scheduler
9. kube-prometheus-stack-kube-state-metrics
10. kube-prometheus-stack-kubelet
11. kube-prometheus-stack-operator
12. kube-prometheus-stack-prometheus
13. kube-prometheus-stack-prometheus-node-exporter

### Acesso ao Grafana
```bash
# Port-forward para acesso local
export AWS_PROFILE=k8s-platform-prod
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Acessar em: http://localhost:3000
# Usuário: admin
# Senha: K8sPlatform2026!
```

### Validação
```bash
# Verificar pods
kubectl get pods -n monitoring

# Verificar PVCs
kubectl get pvc -n monitoring

# Verificar ServiceMonitors
kubectl get servicemonitors -n monitoring

# Verificar status do Prometheus
kubectl describe prometheus kube-prometheus-stack-prometheus -n monitoring
```

**Status de todos os componentes:**
```
NAME                                                        READY   STATUS
alertmanager-kube-prometheus-stack-alertmanager-0           2/2     Running
kube-prometheus-stack-grafana-77ffd8f54b-zv9pj              3/3     Running
kube-prometheus-stack-kube-state-metrics-7f89494fcf-fz7wc   1/1     Running
kube-prometheus-stack-operator-85965cf847-s8h8z             1/1     Running
kube-prometheus-stack-prometheus-node-exporter-*            1/1     Running (7 pods)
prometheus-kube-prometheus-stack-prometheus-0               2/2     Running
```

### Melhorias Necessárias no Marco 1
Durante esta fase, identificamos que o Marco 1 precisa ser atualizado para incluir a configuração da IAM Role do EBS CSI Driver. Isso deve ser adicionado ao addon configuration:

```terraform
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = "v1.37.0-eksbuild.1"
  service_account_role_arn = aws_iam_role.ebs_csi_driver.arn  # ADICIONAR
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [
    aws_eks_node_group.system,
    aws_iam_role.ebs_csi_driver  # ADICIONAR
  ]
}
```

### Status
✅ **COMPLETO** - Stack de monitoramento totalmente operacional

---

## Próximas Fases

### Fase 4: Fluent Bit + CloudWatch (Logging)
- Coletar logs de containers
- Enviar logs para CloudWatch Logs
- Configurar log groups e retention

### Fase 5: Network Policies
- Implementar políticas de rede
- Isolar namespaces
- Controlar tráfego entre pods

### Fase 6: Cluster Autoscaler ou Karpenter
- Autoscaling de nós do cluster
- Otimização de custos
- Provisionamento inteligente

### Fase 7: Aplicações de Teste
- Deploys de exemplo
- Validação de Ingress + TLS
- Testes de monitoramento

---

## Lições Aprendidas

1. **CRD Timing**: Sempre considerar a ordem de criação de CRDs vs Custom Resources no Terraform

2. **IRSA é Essencial**: Componentes que interagem com AWS APIs precisam de IAM Roles configuradas corretamente via IRSA

3. **StorageClass Default**: Importante ter StorageClass padrão configurada desde o início

4. **Validação Incremental**: Validar cada componente individualmente antes de prosseguir evita problemas complexos

5. **Terraform Timeouts**: Para instalações complexas com Helm, considerar aumentar timeouts ou usar wait = false

6. **Documentação é Crucial**: Manter diário detalhado facilita troubleshooting e conhecimento do time

---

## Recursos Criados

### IAM
- AWSLoadBalancerControllerIAMPolicy-k8s-platform-prod
- AWSLoadBalancerControllerRole-k8s-platform-prod
- AmazonEKS_EBS_CSI_DriverRole-k8s-platform-prod

### Kubernetes
- Namespaces: cert-manager, monitoring
- Helm Releases: aws-load-balancer-controller, cert-manager, kube-prometheus-stack
- ClusterIssuers: letsencrypt-staging, letsencrypt-production, selfsigned-issuer
- StorageClass: gp3
- ServiceMonitors: 13 monitors ativos
- PersistentVolumes: 3 volumes (Grafana 5Gi, Prometheus 20Gi, Alertmanager 2Gi)

### Custos Estimados (Adicionais ao Marco 1)
- **EBS Volumes**: ~$0.08/GB/mês × 27GB = ~$2.16/mês
- **Load Balancers**: Criados sob demanda por Ingress (custo variável)
- **Total Adicional**: ~$2-5/mês base + custos de LBs sob demanda

---

## Comandos Úteis

### Verificar Status Geral
```bash
export AWS_PROFILE=k8s-platform-prod

# Marco 2 status
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl get pods -n cert-manager
kubectl get pods -n monitoring

# Verificar PVCs
kubectl get pvc -A

# Verificar ClusterIssuers
kubectl get clusterissuers
```

### Acessar Dashboards
```bash
# Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Alertmanager
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
```

### Troubleshooting
```bash
# Logs do ALB Controller
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# Logs do Cert-Manager
kubectl logs -n cert-manager deployment/cert-manager

# Logs do Prometheus Operator
kubectl logs -n monitoring deployment/kube-prometheus-stack-operator

# Verificar eventos
kubectl get events -n monitoring --sort-by='.lastTimestamp'
```

---

**Última Atualização**: 2026-01-26
**Status do Marco 2**: 3/7 Fases Completas (43%)
