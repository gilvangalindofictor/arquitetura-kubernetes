# Tutorial: Configuração Completa do Ambiente WSL para Kubernetes/AWS

**Versão:** 1.0
**Data:** 2026-01-22
**Projeto:** Arquitetura Multi-Domínio Kubernetes
**Sistema:** Ubuntu 24.04 LTS no WSL2

---

## ✅ Ambiente Provisionado com Sucesso!

Seu ambiente WSL está configurado e pronto para uso com todas as ferramentas necessárias para o projeto.

### 🛠️ Ferramentas Instaladas

| Ferramenta | Versão | Descrição |
|------------|--------|-----------|
| **AWS CLI V2** | 2.33.4 | Interface de linha de comando para AWS |
| **kubectl** | 1.34.1 | CLI para gerenciar clusters Kubernetes |
| **Terraform** | 1.14.3 | Infrastructure as Code |
| **Helm** | 3.20.0 | Package manager para Kubernetes |
| **eksctl** | 0.221.0 | CLI para criar e gerenciar clusters EKS |
| **k9s** | 0.50.18 | Interface TUI para Kubernetes |
| **kubectx** | latest | Alternância rápida entre contextos |
| **kubens** | latest | Alternância rápida entre namespaces |

### 📝 Aliases Configurados

#### AWS
```bash
awswhoami      # Mostra identidade AWS atual
awslogin       # Login SSO
awslogout      # Logout SSO
awsregions     # Lista regiões AWS
awsprofile <nome>  # Alterar perfil AWS
```

#### Kubernetes
```bash
k              # kubectl
kgp            # kubectl get pods
kgs            # kubectl get services
kgn            # kubectl get nodes
kgd            # kubectl get deployments
kga            # kubectl get all
kgns           # kubectl get namespaces
kdp            # kubectl describe pod
kds            # kubectl describe service
kdn            # kubectl describe node
klf            # kubectl logs -f
kex            # kubectl exec -it
kctx           # kubectx (alternar contextos)
kns            # kubens (alternar namespaces)
kwatch         # watch kubectl get pods

# Funções úteis:
kpf <pod> <porta>       # Port-forward
klog <pod>              # Logs com follow
kshell <pod>            # Shell interativo
```

#### Terraform
```bash
tf             # terraform
tfi            # terraform init
tfp            # terraform plan
tfa            # terraform apply
tfd            # terraform destroy
tfv            # terraform validate
tff            # terraform fmt
tfo            # terraform output
```

#### Helm
```bash
h              # helm
hls            # helm list
hi             # helm install
hu             # helm upgrade
hd             # helm delete
```

#### Git
```bash
gs             # git status
ga             # git add
gc             # git commit -m
gp             # git push
gl             # git log --oneline --graph
gd             # git diff
```

#### Navegação
```bash
cdproj         # cd ~/projects/Arquitetura/Kubernetes
cdterraform    # cd ~/projects/Arquitetura/Kubernetes/terraform
cddocs         # cd ~/projects/Arquitetura/Kubernetes/docs
cdscripts      # cd ~/projects/Arquitetura/Kubernetes/scripts
```

---

## 🚀 Próximos Passos

### 1. Configurar Autenticação AWS SSO

```bash
# Iniciar configuração SSO
aws configure sso

# Será solicitado:
# SSO session name (Recommended): k8s-platform-sso
# SSO start URL [None]: https://sua-empresa.awsapps.com/start
# SSO region [None]: us-east-1
# SSO registration scopes [sso:account:access]: [ENTER]
```

Uma janela do navegador será aberta. Complete o login com:
- **Credenciais corporativas** (usuário + senha)
- **MFA** (autenticação de dois fatores)

Depois, selecione:
- **Account:** A conta AWS do projeto (ex: k8s-platform-prod)
- **Permission set:** PowerUserAccess ou similar
- **Region:** us-east-1
- **Profile name:** k8s-platform-prod

### 2. Fazer Login SSO

```bash
# Login (válido por 8 horas por padrão)
aws sso login --profile k8s-platform-prod

# OU definir como perfil padrão
export AWS_PROFILE=k8s-platform-prod

# Usar alias configurado
awslogin
```

### 3. Testar Conexão AWS

```bash
# Verificar identidade
awswhoami

# Ou usando comando completo:
aws sts get-caller-identity

# Saída esperada:
# {
#     "UserId": "AROAEXAMPLE",
#     "Account": "123456789012",
#     "Arn": "arn:aws:sts::123456789012:assumed-role/PowerUserAccess/email@example.com"
# }
```

### 4. Listar Recursos AWS

```bash
# Listar buckets S3
aws s3 ls

# Listar clusters EKS
aws eks list-clusters --region us-east-1

# Listar instâncias EC2
aws ec2 describe-instances --region us-east-1 --output table
```

### 5. Configurar kubectl para EKS

Depois de criar o cluster EKS (seguindo o [plano de execução](../plan/aws-console-execution-plan.md)):

```bash
# Atualizar kubeconfig para o cluster
aws eks update-kubeconfig --region us-east-1 --name k8s-platform-prod

# Verificar conexão
kubectl get nodes

# Ou usando alias:
k get nodes
kgn
```

### 6. Usar k9s (Interface Visual)

```bash
# Abrir k9s
k9s

# Comandos úteis dentro do k9s:
# :pod         - Ver pods
# :svc         - Ver services
# :deploy      - Ver deployments
# :ns          - Ver namespaces
# ctrl+a       - Listar todos os comandos
# /            - Filtrar
# d            - Descrever recurso selecionado
# l            - Ver logs
# s            - Shell no pod
# q ou ctrl+c  - Sair
```

---

## 🔐 Configuração Terraform com SSO

### Como funciona?

O Terraform **detecta automaticamente** as credenciais SSO do AWS CLI. Não é necessário configuração adicional!

### Uso no Terraform

```hcl
# provider.tf
provider "aws" {
  region  = "us-east-1"
  # Terraform usa automaticamente o perfil AWS_PROFILE ou [default]
}
```

### Workflow Típico

```bash
# 1. Login SSO
aws sso login --profile k8s-platform-prod

# 2. Definir perfil (opcional se já for default)
export AWS_PROFILE=k8s-platform-prod

# 3. Usar Terraform normalmente
cd terraform/
terraform init
terraform plan
terraform apply

# ⚠️ Se a sessão SSO expirar (8 horas):
# aws sso login --profile k8s-platform-prod
```

### Backend S3 com SSO

```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket         = "k8s-platform-terraform-state-123456789012"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
    # Não precisa especificar credenciais!
    # Terraform usa as credenciais SSO automaticamente
  }
}
```

### CI/CD com GitHub Actions

Para pipelines CI/CD, você NÃO pode usar SSO interativo. Use Access Keys ou OIDC:

**Opção 1: OIDC (Recomendado para GitHub Actions)**
```yaml
# .github/workflows/terraform.yml
- name: Configure AWS Credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::123456789012:role/GitHubActions
    aws-region: us-east-1
```

**Opção 2: Access Keys (secrets do GitHub)**
```yaml
- name: Configure AWS Credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    aws-region: us-east-1
```

---

## 📚 Comandos Úteis

### Verificar Instalações

```bash
# Verificar todas as versões
aws --version
terraform version
kubectl version --client
helm version --short
eksctl version
k9s version -s | grep Version
kubectx --version
kubens --version
```

### Gerenciar Perfis AWS

```bash
# Listar perfis configurados
aws configure list-profiles

# Verificar perfil ativo
echo $AWS_PROFILE

# Alternar perfil
export AWS_PROFILE=k8s-platform-staging

# Ou usar função customizada:
awsprofile k8s-platform-prod
```

### Gerenciar Contextos Kubernetes

```bash
# Listar contextos
kubectl config get-contexts

# Alternar contexto
kubectl config use-context nome-contexto

# Ou usando kubectx:
kubectx                    # Listar contextos
kubectx nome-contexto      # Alternar contexto
kubectx -                  # Voltar ao contexto anterior

# Alternar namespace:
kubens                     # Listar namespaces
kubens nome-namespace      # Alternar namespace
```

### Autocompleção

A autocompleção está habilitada para:
- `kubectl` (e alias `k`)
- `terraform` (e alias `tf`)
- `helm` (e alias `h`)
- `aws`
- `eksctl`

Teste digitando o comando e pressionando **TAB**:
```bash
kubectl get <TAB>
k get <TAB>
tf <TAB>
aws s3 <TAB>
```

---

## 🐛 Solução de Problemas

### Sessão SSO Expirou

```bash
# Erro: "SSO session has expired"
# Solução:
aws sso login --profile k8s-platform-prod
```

### Aliases não funcionam

```bash
# Recarregar .bashrc
source ~/.bashrc

# Ou verificar se o arquivo existe:
cat ~/.k8s_aws_aliases
```

### kubectl não conecta ao cluster

```bash
# Verificar kubeconfig
cat ~/.kube/config

# Reconfigurar
aws eks update-kubeconfig --region us-east-1 --name k8s-platform-prod

# Verificar contexto
kubectl config get-contexts
```

### Terraform não encontra credenciais

```bash
# Verificar se SSO está ativo
aws sts get-caller-identity

# Se expirou, fazer login novamente
aws sso login --profile k8s-platform-prod

# Verificar perfil
echo $AWS_PROFILE
```

### Permissões negadas (UnauthorizedOperation)

```bash
# Verificar qual usuário/role você está usando
aws sts get-caller-identity

# Verificar políticas IAM no console AWS
# ou pedir ao administrador para adicionar permissões
```

---

## 📖 Próximos Tutoriais

1. **[Instalação do AWS CLI V2](./aws-cli-v2-installation.md)** ✅ (já instalado)
2. **[Plano de Execução AWS](../plan/aws-console-execution-plan.md)** - Provisionar infraestrutura
3. **Terraform AWS EKS** (próximo)
4. **Deploy dos Domínios Kubernetes** (próximo)

---

## 🔗 Links Úteis

### Documentação Oficial
- [AWS CLI V2 Documentation](https://docs.aws.amazon.com/cli/latest/userguide/)
- [AWS SSO Configuration](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html)
- [kubectl Documentation](https://kubernetes.io/docs/reference/kubectl/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [eksctl Documentation](https://eksctl.io/)
- [Helm Documentation](https://helm.sh/docs/)

### Ferramentas
- [k9s GitHub](https://github.com/derailed/k9s)
- [kubectx/kubens GitHub](https://github.com/ahmetb/kubectx)

### AWS
- [AWS Console](https://console.aws.amazon.com/)
- [AWS Service Health Dashboard](https://health.aws.amazon.com/health/status)
- [AWS Pricing Calculator](https://calculator.aws/)

---

## 📝 Arquivos de Configuração

### ~/.aws/config (exemplo)

```ini
[profile k8s-platform-prod]
sso_session = k8s-platform-sso
sso_account_id = 123456789012
sso_role_name = PowerUserAccess
region = us-east-1
output = json

[sso-session k8s-platform-sso]
sso_start_url = https://sua-empresa.awsapps.com/start
sso_region = us-east-1
sso_registration_scopes = sso:account:access
```

### ~/.aws/credentials

**Não é necessário** com SSO! As credenciais são temporárias e gerenciadas automaticamente.

### ~/.kube/config

```yaml
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: LS0t...
    server: https://XXXXX.gr7.us-east-1.eks.amazonaws.com
  name: arn:aws:eks:us-east-1:123456789012:cluster/k8s-platform-prod
contexts:
- context:
    cluster: arn:aws:eks:us-east-1:123456789012:cluster/k8s-platform-prod
    user: arn:aws:eks:us-east-1:123456789012:cluster/k8s-platform-prod
  name: arn:aws:eks:us-east-1:123456789012:cluster/k8s-platform-prod
current-context: arn:aws:eks:us-east-1:123456789012:cluster/k8s-platform-prod
kind: Config
users:
- name: arn:aws:eks:us-east-1:123456789012:cluster/k8s-platform-prod
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      args:
      - --region
      - us-east-1
      - eks
      - get-token
      - --cluster-name
      - k8s-platform-prod
      command: aws
```

---

## ✅ Checklist de Verificação

- [x] Ubuntu 24.04 LTS no WSL2 instalado
- [x] Todas as ferramentas instaladas (AWS CLI, kubectl, Terraform, Helm, eksctl, k9s, kubectx/kubens)
- [x] Aliases e autocompleção configurados
- [ ] **AWS SSO configurado** ← Próximo passo!
- [ ] **Login SSO realizado**
- [ ] **kubectl conectado ao cluster EKS**
- [ ] **Terraform testado**

---

**Documento gerado em:** 2026-01-22
**Autor:** DevOps Team
**Versão:** 1.0
**Próxima revisão:** Após configuração AWS

---

## 🎉 Parabéns!

Seu ambiente WSL está 100% pronto para começar a trabalhar com Kubernetes e AWS!

**Próximo passo:** Configure a autenticação AWS SSO seguindo a seção "Próximos Passos" acima.
