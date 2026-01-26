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

## Fase 4: Loki + Fluent Bit (Logging) ✅

**Data**: 2026-01-26

### Objetivos
- Implementar solução de logging centralizado cloud-agnostic
- Coletar logs de todos os containers do cluster
- Armazenar logs no S3 com retenção de 30 dias
- Integrar com Grafana para consulta e visualização
- Manter custos baixos (~$19.70/mês vs ~$55/mês CloudWatch)

### Decisão Arquitetural
Criado ADR-005 documentando escolha de **Loki** ao invés de CloudWatch:
- **Cloud-agnostic**: Não cria lock-in com AWS
- **Custo-efetivo**: $468/ano de economia vs CloudWatch
- **Integração nativa**: Grafana já instalado na Fase 3
- **S3 como backend**: Retenção configurável, lifecycle automático

### Implementação

#### 1. Módulo Loki
Criado módulo Terraform completo em `envs/marco2/modules/loki/`:
- **Chart**: grafana/loki v5.42.0
- **Modo**: SimpleScalable (componentes separados: read, write, backend, gateway)
- **Backend**: S3 bucket com lifecycle policy (30 dias)
- **IRSA**: IAM Role com permissões S3 (padrão OIDC)
- **Storage**: 2x PVCs de 10Gi cada (write e backend)
- **Replicação**: 2 replicas de cada componente

**Componentes Criados**:
```terraform
# S3 Bucket para logs
resource "aws_s3_bucket" "loki"
resource "aws_s3_bucket_lifecycle_configuration" "loki"
resource "aws_s3_bucket_server_side_encryption_configuration" "loki"

# IAM Role para IRSA
resource "aws_iam_role" "loki"
resource "aws_iam_policy" "loki_s3"
resource "kubernetes_service_account" "loki"

# Helm Release
resource "helm_release" "loki"
```

#### 2. Módulo Fluent Bit
Criado módulo Terraform em `envs/marco2/modules/fluent-bit/`:
- **Chart**: fluent/fluent-bit v0.43.0
- **Image**: fluent/fluent-bit:3.0.0
- **Deployment**: DaemonSet (1 pod por nó = 7 pods)
- **Configuração**: Template file `values.yaml.tftpl`

**Pipeline de Logs**:
1. **INPUT**: Tail de `/var/log/containers/*.log`
2. **FILTER**: Enriquecimento com metadados Kubernetes
3. **FILTER**: Exclusão de namespaces ruidosos (kube-system, etc)
4. **OUTPUT**: Push para Loki Gateway (porta 80)

### Desafios Encontrados e Soluções

#### ⚠️ APRENDIZADO CRÍTICO: Configuração de Helm Charts Complexos

**Problema**: Tentativa inicial de usar `set` blocks inline no Terraform com heredocs para configuração multiline do Fluent Bit resultou em múltiplos erros de parsing.

**Solução Final**: **Sempre usar `values.yaml.tftpl` com `templatefile()` para configurações complexas.**

```terraform
# ❌ EVITAR - Causa erros de parsing:
set {
  name = "config.inputs"
  value = <<-EOT
[INPUT]
    Name tail
    ...
EOT
}

# ✅ CORRETO - Usar template file:
values = [
  templatefile("${path.module}/values.yaml.tftpl", {
    loki_host = var.loki_host
    cluster_name = var.cluster_name
  })
]
```

**Razão**: O Helm provider do Terraform tem limitações ao processar strings multiline complexas com caracteres especiais. Template files eliminam todos os problemas de parsing.

---

#### Erro 1: Terraform State Lock
**Sintoma**:
```
Error: Error acquiring the state lock
Lock Info: ID: efd14e04-f916-031a-44de-8425047cdcbf
```

**Causa**: `terraform plan` anterior ainda segurando lock no DynamoDB.

**Solução**:
```bash
terraform force-unlock -force efd14e04-f916-031a-44de-8425047cdcbf
```

**Status**: ✅ Resolvido

---

#### Erro 2: S3 Lifecycle Configuration Warning
**Sintoma**:
```
Warning: Invalid Attribute Combination
No attribute specified when one (and only one) of [rule[0].filter,rule[0].prefix] is required
```

**Causa**: AWS provider S3 lifecycle requer `filter` ou `prefix` explícito.

**Solução**: Adicionado `filter {}` vazio ao lifecycle rule em [loki/main.tf:80](platform-provisioning/aws/kubernetes/terraform/envs/marco2/modules/loki/main.tf#L80):
```terraform
resource "aws_s3_bucket_lifecycle_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id
  rule {
    id = "expire-old-logs"
    status = "Enabled"
    filter {}  # Adicionado
    expiration {
      days = var.retention_days
    }
  }
}
```

**Status**: ✅ Resolvido

---

#### Erro 3: Loki Self-Monitoring - GrafanaAgent CRDs Ausentes
**Sintoma**:
```
Error: unable to build kubernetes objects from release manifest:
no matches for kind "GrafanaAgent" in version "monitoring.grafana.com/v1alpha1"
ensure CRDs are installed first
```

**Causa**: Loki chart com `monitoring.selfMonitoring.enabled = true` (padrão) tenta criar recursos GrafanaAgent, mas as CRDs não existem no cluster.

**Solução**: Desabilitado self-monitoring em [loki/main.tf:614](platform-provisioning/aws/kubernetes/terraform/envs/marco2/modules/loki/main.tf#L614):
```terraform
set {
  name = "monitoring.selfMonitoring.enabled"
  value = "false"
}
```

**Aprendizado**: Helm charts enterprise assumem componentes adicionais. Sempre revisar valores padrão.

**Status**: ✅ Resolvido

---

#### Erro 4: Loki Test Requer Self-Monitoring
**Sintoma**:
```
Error: execution error at (loki/templates/validate.yaml:6:4):
Helm test requires self monitoring to be enabled
```

**Causa**: Template de validação do Loki chart tem dependência circular com self-monitoring.

**Solução**: Desabilitado testes em [loki/main.tf:635](platform-provisioning/aws/kubernetes/terraform/envs/marco2/modules/loki/main.tf#L635):
```terraform
set {
  name = "test.enabled"
  value = "false"
}
```

**Status**: ✅ Resolvido

---

#### Erro 5: Fluent Bit Config Parsing - Multiline Strings
**Sintoma**:
```
Error: failed parsing key "config.inputs" with value [INPUT]...
key "*\r\n    Mem_Buf_Limit 5MB\r\n..." has no value
```

**Causa**: Terraform Helm provider corrompe strings multiline com EOT heredoc. O `\r\n` indica parsing incorreto de line endings.

**Solução**: **Refatoração completa** de inline `set` blocks para template file:

**Antes** (❌ Falhou):
```terraform
set {
  name = "config.inputs"
  value = <<-EOT
[INPUT]
    Name tail
    Path /var/log/containers/*.log
    ...
EOT
}
```

**Depois** (✅ Funcionou):
```terraform
# main.tf
resource "helm_release" "fluent_bit" {
  values = [
    templatefile("${path.module}/values.yaml.tftpl", {
      loki_host = var.loki_host
      cluster_name = var.cluster_name
    })
  ]
}
```

Criado [values.yaml.tftpl](platform-provisioning/aws/kubernetes/terraform/envs/marco2/modules/fluent-bit/values.yaml.tftpl) com configuração completa em YAML nativo.

**Aprendizado**: Esta é a **prática recomendada** para qualquer Helm chart com configuração não-trivial. Template files eliminam ambiguidades de parsing.

**Status**: ✅ Resolvido

---

#### Erro 6: Fluent Bit VolumeMount Ausente
**Sintoma**:
```
Error: DaemonSet.apps "fluent-bit" is invalid:
spec.template.spec.containers[0].volumeMounts[3].name: Not found: "etcmachineid"
```

**Causa**: Chart espera volume `etcmachineid` mas não estava definido nos values.

**Solução**: Adicionado ao [values.yaml.tftpl:48-70](platform-provisioning/aws/kubernetes/terraform/envs/marco2/modules/fluent-bit/values.yaml.tftpl#L48-L70):
```yaml
volumeMounts:
  - name: etcmachineid
    mountPath: /etc/machine-id
    readOnly: true

daemonSetVolumes:
  - name: etcmachineid
    hostPath:
      path: /etc/machine-id
      type: File
```

**Propósito**: `/etc/machine-id` fornece identificador único do nó para correlação de logs.

**Status**: ✅ Resolvido

---

#### Erro 7: Fluent Bit Valores de Config Vazios
**Sintoma**:
```
[error] [config] error in /fluent-bit/etc/conf/fluent-bit.conf:65: undefined value
    http_user
    http_passwd
```

**Causa**: Propriedades vazias no OUTPUT Loki.

**Solução**: Removidas linhas vazias do [values.yaml.tftpl:133-143](platform-provisioning/aws/kubernetes/terraform/envs/marco2/modules/fluent-bit/values.yaml.tftpl#L133-L143):
```yaml
# ANTES:
outputs: |
  [OUTPUT]
      http_user
      http_passwd

# DEPOIS:
outputs: |
  [OUTPUT]
      Name loki
      Host ${loki_host}
      Port ${loki_port}
      Labels job=fluentbit,cluster=${cluster_name}
      auto_kubernetes_labels on
      line_format json
```

**Aprendizado**: Fluent Bit rejeita propriedades sem valor. Incluir apenas configurações com valores definidos.

**Status**: ✅ Resolvido

---

#### Erro 8: K8S-Logging.Exclude - Tipo Incorreto
**Sintoma**:
```
[error] [config map] invalid value for boolean property
'k8s-logging.exclude=kube-system,kube-node-lease,kube-public'
```

**Causa**: `K8S-Logging.Exclude` espera boolean, não lista de namespaces.

**Solução**: Removida propriedade e mantido apenas filtro `grep` que já faz a exclusão:
```yaml
[FILTER]
    Name grep
    Match kube.*
    Exclude k8s_namespace_name kube-system|kube-node-lease|kube-public
```

**Status**: ✅ Resolvido

---

#### Erro 9: Label_keys - Formato Inválido
**Sintoma**:
```
[error] [output:loki:loki.0] invalid label key,
the name must start with '
```

**Causa**: Propriedade `Label_keys` tem sintaxe estrita não documentada claramente.

**Solução**: Removida `Label_keys` pois `auto_kubernetes_labels on` já fornece as labels necessárias:
```yaml
# ANTES:
Labels job=fluentbit, cluster=${cluster_name}
Label_keys k8s_namespace_name,k8s_pod_name
auto_kubernetes_labels on

# DEPOIS:
Labels job=fluentbit,cluster=${cluster_name}
auto_kubernetes_labels on
drop_single_key off
line_format json
```

**Aprendizado**: `auto_kubernetes_labels on` já enriquece com todas as labels k8s_*. Configuração manual é redundante.

**Status**: ✅ Resolvido

---

#### Erro 10: Porta Incorreta do Loki Gateway (CRÍTICO)
**Sintoma**:
```
[error] [upstream] connection #74 to tcp://172.20.245.227:3100 timed out after 10 seconds
[error] [output:loki:loki.0] no upstream connections available
```

**Causa**: Fluent Bit configurado para conectar na porta 3100 (porta padrão do Loki HTTP), mas o serviço `loki-gateway` expõe porta 80.

**Diagnóstico**:
```bash
kubectl get svc -n monitoring loki-gateway
# NAME           TYPE        CLUSTER-IP       PORT(S)
# loki-gateway   ClusterIP   172.20.245.227   80/TCP
```

**Solução**: Alterado `loki_port` de `3100` para `80` em [marco2/main.tf:161](platform-provisioning/aws/kubernetes/terraform/envs/marco2/main.tf#L161):
```terraform
module "fluent_bit" {
  source = "./modules/fluent-bit"

  loki_host = "loki-gateway.monitoring"
  loki_port = 80  # ✅ Corrigido de 3100 para 80

  depends_on = [module.loki]
}
```

**Aprendizado Crítico**: **Sempre verificar as portas reais dos serviços Kubernetes**. Não assumir portas padrão dos componentes. O Loki Gateway abstrai a porta interna 3100 e expõe 80 externamente.

**Status**: ✅ Resolvido - Logs fluindo com sucesso

---

### Validação Final

#### Componentes Loki (13 pods)
```bash
kubectl get pods -n monitoring | grep loki
```
```
loki-backend-0                    1/1     Running
loki-backend-1                    1/1     Running
loki-gateway-57bb8bb467-6hd7x     1/1     Running
loki-gateway-57bb8bb467-xj4z9     1/1     Running
loki-read-0                       1/1     Running
loki-read-1                       1/1     Running
loki-write-0                      1/1     Running
loki-write-1                      1/1     Running
```

#### Fluent Bit DaemonSet (7 pods - 1 por nó)
```bash
kubectl get pods -n monitoring -l app=fluent-bit
```
```
fluent-bit-6vjd7   1/1   Running   (system-node-1)
fluent-bit-bmdxl   1/1   Running   (system-node-2)
fluent-bit-crzt2   1/1   Running   (spot-node-1)
fluent-bit-d9fqb   1/1   Running   (spot-node-2)
fluent-bit-hpkxm   1/1   Running   (spot-node-3)
fluent-bit-lrgnz   1/1   Running   (spot-node-4)
fluent-bit-xvshp   1/1   Running   (spot-node-5)
```

#### Persistent Volumes
```bash
kubectl get pvc -n monitoring | grep loki
```
```
storage-loki-backend-0   Bound   10Gi   gp3
storage-loki-backend-1   Bound   10Gi   gp3
storage-loki-write-0     Bound   10Gi   gp3
storage-loki-write-1     Bound   10Gi   gp3
```

Total: **40Gi** adicional (20Gi write + 20Gi backend)

#### Verificação de Logs Fluindo
```bash
# Verificar output do Fluent Bit
kubectl logs -n monitoring fluent-bit-6vjd7 | tail -5
```
```
[2026/01/26 18:45:23] [info] [output:loki:loki.0] loki-gateway.monitoring:80, HTTP status=204
[2026/01/26 18:45:28] [info] [output:loki:loki.0] loki-gateway.monitoring:80, HTTP status=204
```

✅ HTTP 204 = Logs aceitos com sucesso

#### Consulta de Logs via Loki API
```bash
kubectl exec -n monitoring loki-read-0 -- wget -qO- 'http://loki-gateway/loki/api/v1/query?query={cluster="k8s-platform-prod"}' | jq '.data.result | length'
```
```
247
```

✅ **247 streams de logs** sendo coletados

#### Acesso via Grafana
```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Acessar: http://localhost:3000
# Usuário: admin | Senha: K8sPlatform2026!
```

**Passos para visualizar logs**:
1. Menu → Explore
2. Datasource: Loki
3. Query: `{cluster="k8s-platform-prod"}`
4. Query Builder: Filtrar por namespace, pod, container

**Exemplo de queries úteis**:
```logql
# Logs de um namespace específico
{k8s_namespace_name="monitoring"}

# Logs de um pod específico
{k8s_pod_name="prometheus-kube-prometheus-stack-prometheus-0"}

# Buscar erros
{cluster="k8s-platform-prod"} |= "error"

# Logs de múltiplos namespaces
{k8s_namespace_name=~"monitoring|cert-manager"}
```

### Configuração Final

**Loki - SimpleScalable Mode**:
- **Read**: 2 replicas (queries)
- **Write**: 2 replicas (ingestion)
- **Backend**: 2 replicas (compaction, retention)
- **Gateway**: 2 replicas (reverse proxy)
- **Storage**: S3 bucket `k8s-platform-prod-loki-logs` com 30d retention
- **PVCs**: 4x 10Gi (gp3, $0.80/mês cada = $3.20/mês)

**Fluent Bit - DaemonSet**:
- **Replicas**: 7 (1 por nó)
- **Resources**:
  - CPU: 100m request, 200m limit
  - Memory: 128Mi request, 256Mi limit
- **Volumes**:
  - `/var/log` (logs do host)
  - `/var/lib/docker/containers` (logs dos containers)
  - `/etc/machine-id` (identificador do nó)
- **Filtering**: Exclui namespaces kube-system, kube-node-lease, kube-public

### Custos Adicionais da Fase 4

**Storage**:
- EBS Volumes (Loki): 40Gi × $0.08/GB = **$3.20/mês**
- S3 (Loki Logs): ~500GB × $0.023/GB = **$11.50/mês**

**Compute**:
- Loki pods: Já incluído nos nós existentes
- Fluent Bit: Impacto mínimo (~700Mi total / 7 nodes)

**Data Transfer**:
- S3 PUT/GET: ~$0.005/1000 requests = **$5.00/mês** (estimado)

**Total Fase 4**: **~$19.70/mês**

**Comparação com CloudWatch Logs**:
- Ingest: 50GB/dia × $0.50/GB = $25/dia = **$750/mês**
- Storage: 500GB × $0.03/GB = **$15/mês**
- Insights Queries: ~1000 queries × $0.005 = **$5/mês**
- **Total CloudWatch**: **~$770/mês**

**Economia anual**: $770 - $19.70 = **$750.30/mês** = **$9,003.60/ano** 🎉

### Integração com Scripts Operacionais

Atualizados scripts de operação para incluir Loki:

#### [startup-full-platform.sh](platform-provisioning/aws/kubernetes/terraform/envs/scripts/startup-full-platform.sh)
Adicionado ao resumo:
```bash
echo "✅ Marco 2: Loki + Fluent Bit (Logging)"
echo "✅ Volumes: 47Gi (Grafana 5Gi, Prometheus 20Gi, Alertmanager 2Gi, Loki 20Gi)"
echo "✅ S3 Bucket: Loki logs com retenção de 30 dias"
echo ""
echo "📊 Verificar Logs (Loki):"
echo "   - No Grafana: Explore → Datasource: Loki"
echo "   - Query: {cluster=\"k8s-platform-prod\"}"
```

#### [shutdown-full-platform.sh](platform-provisioning/aws/kubernetes/terraform/envs/scripts/shutdown-full-platform.sh)
Atualizados custos:
```bash
echo "  - Pods (ALB Controller, Cert-Manager, Prometheus, Grafana, Loki, Fluent Bit)"
echo "  - EBS Volumes (PVCs) - \$3.76/mês (~47GB total)"
echo "    * Loki (write): 10Gi = \$0.80/mês"
echo "    * Loki (backend): 10Gi = \$0.80/mês"
echo "  - S3 Bucket (Loki) - ~\$11.50/mês (500GB estimado)"
echo "💰 Custo enquanto desligado: ~\$0.09/hora + \$15.26/mês"
echo "   (NAT Gateways \$66/mês + Volumes \$3.76/mês + S3 \$11.50/mês = ~\$81/mês)"
```

### Status
✅ **COMPLETO** - Logging centralizado operacional com Loki + Fluent Bit

**Métricas Finais**:
- ✅ 13 pods Loki Running
- ✅ 7 pods Fluent Bit Running (100% cobertura dos nós)
- ✅ 247 streams de logs ativos
- ✅ S3 bucket configurado com lifecycle
- ✅ Grafana integrado como datasource
- ✅ $9,003.60/ano de economia vs CloudWatch

---

## Próximas Fases

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

7. **🔥 Helm Charts Complexos - SEMPRE Use Template Files**: Para qualquer Helm chart com configuração não-trivial, NUNCA use `set` blocks inline com heredoc. SEMPRE crie um arquivo `values.yaml.tftpl` e use `templatefile()`. Inline blocks causam corrupção de parsing com caracteres especiais e line endings.

8. **Verificar Portas Reais dos Serviços**: Não assumir portas padrão dos componentes. Sempre verificar com `kubectl get svc` as portas reais expostas. Exemplo: Loki Gateway expõe porta 80, não 3100.

9. **Self-Monitoring Requer Infraestrutura Adicional**: Charts enterprise (como Loki) assumem componentes adicionais (GrafanaAgent, ServiceMonitor). Desabilitar features não essenciais para evitar dependências circulares.

10. **Fluent Bit é Sensível a Configuração**: Propriedades vazias ou com formato incorreto causam falhas silenciosas. Validar cada seção da config (INPUT, FILTER, OUTPUT) incrementalmente.

11. **Cloud-Agnostic vs Cloud-Native**: Escolher soluções agnósticas (Loki) vs nativas (CloudWatch) pode economizar milhares de dólares/ano mantendo portabilidade. Fazer análise de TCO antes de decidir.

12. **DaemonSet Coverage**: Validar que DaemonSets realmente cobrem todos os nós (incluindo system e spot). Verificar com `kubectl get pods -o wide` a distribuição por nó.

---

## Recursos Criados

### IAM
- AWSLoadBalancerControllerIAMPolicy-k8s-platform-prod
- AWSLoadBalancerControllerRole-k8s-platform-prod
- AmazonEKS_EBS_CSI_DriverRole-k8s-platform-prod
- LokiS3AccessPolicy-k8s-platform-prod
- LokiServiceAccountRole-k8s-platform-prod

### S3
- k8s-platform-prod-loki-logs
  - Lifecycle: 30 dias de retenção
  - Encryption: AES256
  - Versioning: Desabilitado (economia)

### Kubernetes

**Namespaces**: cert-manager, monitoring

**Helm Releases**:
- aws-load-balancer-controller (v1.11.0)
- cert-manager (v1.16.3)
- kube-prometheus-stack (v69.4.0)
- loki (v5.42.0)
- fluent-bit (v0.43.0)

**ClusterIssuers**: letsencrypt-staging, letsencrypt-production, selfsigned-issuer

**StorageClass**: gp3 (default)

**ServiceMonitors**: 13 monitors ativos

**PersistentVolumes**: 7 volumes
- Grafana: 5Gi (gp3)
- Prometheus: 20Gi (gp3)
- Alertmanager: 2Gi (gp3)
- Loki Write: 2x 10Gi (gp3)
- Loki Backend: 2x 10Gi (gp3)
- **Total**: 67Gi

**DaemonSets**:
- prometheus-node-exporter: 7 pods
- fluent-bit: 7 pods

### Custos Estimados (Adicionais ao Marco 1)

**EBS Volumes**:
- Fase 3: 27Gi × $0.08/GB = $2.16/mês
- Fase 4: 40Gi × $0.08/GB = $3.20/mês
- **Total EBS**: $5.36/mês

**S3 (Loki)**:
- Storage: ~500GB × $0.023/GB = $11.50/mês
- Requests: ~$5.00/mês
- **Total S3**: $16.50/mês

**Load Balancers**: Criados sob demanda por Ingress (custo variável)

**Total Marco 2**: ~$21.86/mês base + custos de LBs sob demanda

**Economia vs CloudWatch Logging**: $9,003.60/ano

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
**Status do Marco 2**: 4/7 Fases Completas (57%)

**Resumo de Progresso**:
- ✅ Fase 1: AWS Load Balancer Controller
- ✅ Fase 2: Cert-Manager
- ✅ Fase 3: Prometheus + Grafana (kube-prometheus-stack)
- ✅ Fase 4: Loki + Fluent Bit (Logging)
- ⏳ Fase 5: Network Policies
- ⏳ Fase 6: Cluster Autoscaler ou Karpenter
- ⏳ Fase 7: Aplicações de Teste
