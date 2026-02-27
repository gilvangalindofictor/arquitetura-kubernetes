# Observability Platform - Terraform Infrastructure

Infrastructure as Code para a plataforma de observabilidade usando Terraform.

## Arquitetura

Baseado em **ADR-002** (Mesa Técnica 08/12/2025):
- **VPC**: 3 AZs com subnets públicas e privadas
- **EKS**: Cluster Kubernetes único com isolamento por namespace
- **S3**: Buckets para long-term storage (métricas, logs, traces, backups)
- **IAM**: Roles IRSA (IAM Roles for Service Accounts) por namespace

## Estrutura de Diretórios

```
infra/terraform/
├── main.tf                    # Configuração principal
├── variables.tf               # Variáveis de entrada
├── outputs.tf                 # Outputs
├── terraform.tfvars.example   # Exemplo de valores
├── modules/
│   ├── vpc/                   # Módulo VPC
│   ├── eks/                   # Módulo EKS
│   ├── s3/                    # Módulo S3
│   └── iam/                   # Módulo IAM
```

## Pré-requisitos

1. **Terraform** >= 1.5
2. **AWS CLI** configurado com credenciais
3. **kubectl** para gerenciar cluster Kubernetes
4. Permissões AWS para criar: VPC, EKS, S3, IAM

## Uso

### 1. Inicializar Terraform

```bash
cd infra/terraform
terraform init
```

### 2. Configurar variáveis

Copie o arquivo de exemplo e ajuste conforme necessário:

```bash
cp terraform.tfvars.example terraform.tfvars
# Edite terraform.tfvars com seus valores
```

### 3. Planejar mudanças

```bash
terraform plan -out=tfplan
```

### 4. Aplicar infraestrutura

```bash
terraform apply tfplan
```

**Tempo estimado**: 15-20 minutos para criação completa.

### 5. Configurar kubectl

Após a criação do cluster EKS:

```bash
aws eks update-kubeconfig --region us-east-1 --name observability-cluster
kubectl get nodes
```

### 6. Criar namespaces Kubernetes

```bash
kubectl create namespace observability-dev
kubectl create namespace observability-hml
kubectl create namespace observability-prd
```

## Custos Estimados

Com configuração padrão (3 nodes t3.large ON_DEMAND):
- **EKS Control Plane**: ~$73/mês
- **EC2 Nodes**: ~$150/mês (3x t3.large)
- **S3 Storage**: ~$25/mês (~100GB)
- **Data Transfer**: ~$20/mês
- **Total**: ~$268/mês

### Otimizações de Custo

1. **Usar SPOT instances** para ambientes dev/hml:
   ```hcl
   capacity_type = "SPOT"  # Reduz ~50% do custo de compute
   ```

2. **Reduzir número de nodes** para PoC:
   ```hcl
   desired_size = 2
   min_size     = 1
   ```

3. **Configurar AWS Budget**:
   ```bash
   # Criar alerta de budget via Console AWS ou CLI
   ```

## Outputs Importantes

Após o `terraform apply`, você terá acesso a:

- `eks_cluster_endpoint`: Endpoint do cluster EKS
- `s3_bucket_arns`: ARNs dos buckets S3
- `iam_namespace_role_arns`: Roles IAM para service accounts
- `kubeconfig_command`: Comando para configurar kubectl

## Próximos Passos

Após provisionar a infraestrutura:

1. **Deploy do stack de observabilidade** (Fase 2):
   - Prometheus via kube-prometheus-stack
   - Loki para logs
   - Tempo para traces
   - Grafana para visualização

2. **Configurar IRSA** (IAM Roles for Service Accounts):
   - Anotar service accounts com ARNs dos roles criados

3. **Configurar Network Policies**:
   - Isolar namespaces dev/hml/prd

## Rollback

Para destruir toda a infraestrutura:

```bash
terraform destroy
```

**Atenção**: Isso removerá todos os recursos, incluindo dados em S3 (se não houver proteção de deleção).

## Troubleshooting

### EKS nodes não aparecem

```bash
# Verificar node groups
aws eks list-nodegroups --cluster-name observability-cluster --region us-east-1

# Verificar eventos
kubectl get events --all-namespaces
```

### Erros de permissão IAM

Verifique se sua conta AWS tem as seguintes permissões:
- `ec2:*`
- `eks:*`
- `s3:*`
- `iam:CreateRole`, `iam:AttachRolePolicy`

### S3 bucket já existe

Se o bucket name colidir, ajuste o sufixo em `modules/s3/main.tf` ou use workspace Terraform separado.

## Referências

- [Documentação ADR-002](../../docs/adr/adr-002-mesa-tecnica.md)
- [Arquitetura Lógica](../../docs/infra/arquitetura-logica.md)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
