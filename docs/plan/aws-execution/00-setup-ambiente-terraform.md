# Setup do Ambiente de Desenvolvimento - Terraform + AWS

**Versão:** 1.1
**Data:** 2026-01-20
**Pré-requisito para:** Todos os documentos de execução AWS
**Tempo estimado:** 45-60 minutos
**Inclui:** Guia visual de navegação no Console AWS (Seção 8)

---

## Sumário

1. [Visão Geral](#1-visão-geral)
2. [Instalação do WSL2](#2-instalação-do-wsl2)
3. [Configuração do VSCode](#3-configuração-do-vscode)
4. [Instalação do Terraform](#4-instalação-do-terraform)
5. [Instalação do AWS CLI](#5-instalação-do-aws-cli)
6. [Ferramentas Kubernetes](#6-ferramentas-kubernetes)
7. [Configuração de Credenciais AWS](#7-configuração-de-credenciais-aws)
8. [Informações AWS - Como Obter no Console (UI)](#8-informações-aws---como-obter-no-console-ui)
9. [Estrutura do Projeto Terraform](#9-estrutura-do-projeto-terraform)
10. [Configuração do Backend S3](#10-configuração-do-backend-s3)
11. [Validação do Ambiente](#11-validação-do-ambiente)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. Visão Geral

### 1.1 Arquitetura do Ambiente

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              WINDOWS HOST                                    │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │                         VSCode (Windows)                               │ │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐       │ │
│  │  │ Remote - WSL    │  │ HashiCorp       │  │ AWS Toolkit     │       │ │
│  │  │ Extension       │  │ Terraform Ext   │  │ Extension       │       │ │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘       │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                    │                                        │
│                                    ▼                                        │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │                         WSL2 (Ubuntu 22.04)                           │ │
│  │                                                                        │ │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐     │ │
│  │  │ Terraform   │ │ AWS CLI v2  │ │ kubectl     │ │ helm        │     │ │
│  │  │ >= 1.5.0    │ │ >= 2.0      │ │ >= 1.28     │ │ >= 3.0      │     │ │
│  │  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘     │ │
│  │                                                                        │ │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                     │ │
│  │  │ eksctl      │ │ jq          │ │ git         │                     │ │
│  │  │ >= 0.160    │ │ >= 1.6      │ │ >= 2.0      │                     │ │
│  │  └─────────────┘ └─────────────┘ └─────────────┘                     │ │
│  │                                                                        │ │
│  │  ~/.aws/                                                               │ │
│  │  ├── config         (perfis e região)                                 │ │
│  │  └── credentials    (access keys)                                     │ │
│  │                                                                        │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                    │                                        │
└────────────────────────────────────┼────────────────────────────────────────┘
                                     │
                                     ▼
                          ┌─────────────────────┐
                          │      AWS Cloud      │
                          │  ┌───────────────┐  │
                          │  │ S3 (tfstate)  │  │
                          │  │ EKS, VPC, RDS │  │
                          │  └───────────────┘  │
                          └─────────────────────┘
```

### 1.2 Versões Requeridas

| Ferramenta | Versão Mínima | Verificar Comando |
|------------|---------------|-------------------|
| WSL2 | 2.0 | `wsl --version` |
| Ubuntu | 22.04 LTS | `lsb_release -a` |
| Terraform | 1.5.0 | `terraform version` |
| AWS CLI | 2.0 | `aws --version` |
| kubectl | 1.28 | `kubectl version --client` |
| helm | 3.0 | `helm version` |
| eksctl | 0.160 | `eksctl version` |
| git | 2.0 | `git --version` |
| jq | 1.6 | `jq --version` |

---

## 2. Instalação do WSL2

### 2.1 Habilitar WSL2 no Windows

Abra o **PowerShell como Administrador** e execute:

```powershell
# Habilitar WSL
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart

# Habilitar Virtual Machine Platform
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart

# Reiniciar o computador
Restart-Computer
```

### 2.2 Instalar WSL2 e Ubuntu

Após reiniciar, abra o **PowerShell como Administrador**:

```powershell
# Definir WSL2 como padrão
wsl --set-default-version 2

# Instalar Ubuntu 22.04
wsl --install -d Ubuntu-22.04

# Verificar instalação
wsl --list --verbose
```

**Saída esperada:**
```
  NAME            STATE           VERSION
* Ubuntu-22.04    Running         2
```

### 2.3 Configuração Inicial do Ubuntu

Ao abrir o Ubuntu pela primeira vez, configure usuário e senha:

```bash
# Atualizar sistema
sudo apt update && sudo apt upgrade -y

# Instalar dependências básicas
sudo apt install -y \
    curl \
    wget \
    unzip \
    gnupg \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    lsb-release \
    jq \
    git \
    make \
    build-essential

# Verificar
echo "✅ Dependências básicas instaladas"
```

### 2.4 Configurar Git

```bash
# Configurar identidade
git config --global user.name "Seu Nome"
git config --global user.email "seu.email@empresa.com"

# Configurar editor padrão (VSCode)
git config --global core.editor "code --wait"

# Configurar line endings (importante para WSL)
git config --global core.autocrlf input

# Verificar
git config --list
```

---

## 3. Configuração do VSCode

### 3.1 Instalar VSCode no Windows

1. Baixe o instalador em: https://code.visualstudio.com/download
2. Execute o instalador
3. Marque as opções:
   - ✅ Add "Open with Code" action to Windows Explorer file context menu
   - ✅ Add "Open with Code" action to Windows Explorer directory context menu
   - ✅ Add to PATH

### 3.2 Instalar Extensões Essenciais

Abra o VSCode e instale as seguintes extensões (Ctrl+Shift+X):

#### Extensões Obrigatórias

| Extensão | ID | Descrição |
|----------|-----|-----------|
| **Remote - WSL** | `ms-vscode-remote.remote-wsl` | Desenvolver no WSL |
| **HashiCorp Terraform** | `hashicorp.terraform` | Syntax, autocomplete, format |
| **AWS Toolkit** | `amazonwebservices.aws-toolkit-vscode` | Integração AWS |

#### Extensões Recomendadas

| Extensão | ID | Descrição |
|----------|-----|-----------|
| YAML | `redhat.vscode-yaml` | Syntax para YAML/Helm |
| Kubernetes | `ms-kubernetes-tools.vscode-kubernetes-tools` | Gerenciar K8s |
| GitLens | `eamodio.gitlens` | Git avançado |
| Error Lens | `usernamehw.errorlens` | Erros inline |
| indent-rainbow | `oderwat.indent-rainbow` | Visualizar indentação |
| Bracket Pair Colorizer | Nativo no VSCode | Colorir brackets |

**Instalação via CLI:**

```powershell
# No PowerShell do Windows
code --install-extension ms-vscode-remote.remote-wsl
code --install-extension hashicorp.terraform
code --install-extension amazonwebservices.aws-toolkit-vscode
code --install-extension redhat.vscode-yaml
code --install-extension ms-kubernetes-tools.vscode-kubernetes-tools
code --install-extension eamodio.gitlens
code --install-extension usernamehw.errorlens
code --install-extension oderwat.indent-rainbow
```

### 3.3 Conectar VSCode ao WSL

1. Abra o terminal Ubuntu (WSL)
2. Navegue até o diretório do projeto:
   ```bash
   cd ~/projects/k8s-platform
   ```
3. Abra o VSCode conectado ao WSL:
   ```bash
   code .
   ```
4. O VSCode abrirá com o indicador **WSL: Ubuntu-22.04** no canto inferior esquerdo

### 3.4 Configurações do VSCode para Terraform

Crie/edite o arquivo `.vscode/settings.json` no seu projeto:

```json
{
  // Terraform
  "[terraform]": {
    "editor.defaultFormatter": "hashicorp.terraform",
    "editor.formatOnSave": true,
    "editor.formatOnSaveMode": "file"
  },
  "[terraform-vars]": {
    "editor.defaultFormatter": "hashicorp.terraform",
    "editor.formatOnSave": true
  },
  "terraform.languageServer.enable": true,
  "terraform.languageServer.args": ["serve"],
  "terraform.codelens.referenceCount": true,

  // YAML (Helm, K8s)
  "[yaml]": {
    "editor.defaultFormatter": "redhat.vscode-yaml",
    "editor.formatOnSave": true
  },
  "yaml.schemas": {
    "kubernetes": "/*.yaml"
  },

  // Geral
  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true,
  "editor.rulers": [80, 120],

  // Terminal
  "terminal.integrated.defaultProfile.linux": "bash",

  // Exclude
  "files.exclude": {
    "**/.terraform": true,
    "**/*.tfstate": true,
    "**/*.tfstate.*": true
  }
}
```

---

## 4. Instalação do Terraform

### 4.1 Adicionar Repositório HashiCorp

```bash
# Adicionar chave GPG
wget -O- https://apt.releases.hashicorp.com/gpg | \
  gpg --dearmor | \
  sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null

# Verificar fingerprint
gpg --no-default-keyring \
  --keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg \
  --fingerprint

# Adicionar repositório
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
```

### 4.2 Instalar Terraform

```bash
# Atualizar e instalar
sudo apt update
sudo apt install -y terraform

# Verificar instalação
terraform version

# Saída esperada:
# Terraform v1.7.x
# on linux_amd64
```

### 4.3 Habilitar Autocomplete

```bash
# Habilitar autocomplete no bash
terraform -install-autocomplete

# Recarregar shell
source ~/.bashrc

# Testar (digite 'terraform ' e pressione TAB duas vezes)
terraform <TAB><TAB>
```

### 4.4 Configurar Terraform CLI

Crie o arquivo de configuração do Terraform:

```bash
# Criar diretório de configuração
mkdir -p ~/.terraform.d

# Criar arquivo de configuração
cat > ~/.terraform.d/terraformrc << 'EOF'
# Configuração global do Terraform CLI

# Cache de plugins (economiza banda e tempo)
plugin_cache_dir = "$HOME/.terraform.d/plugin-cache"

# Desabilitar checkpoint (telemetria)
disable_checkpoint = true
EOF

# Criar diretório de cache
mkdir -p ~/.terraform.d/plugin-cache

# Verificar
cat ~/.terraform.d/terraformrc
```

---

## 5. Instalação do AWS CLI

### 5.1 Instalar AWS CLI v2

```bash
# Baixar instalador
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"

# Descompactar
unzip awscliv2.zip

# Instalar
sudo ./aws/install

# Limpar
rm -rf awscliv2.zip aws/

# Verificar
aws --version

# Saída esperada:
# aws-cli/2.x.x Python/3.x.x Linux/x.x.x botocore/2.x.x
```

### 5.2 Instalar Session Manager Plugin (Opcional)

O Session Manager permite acesso SSH sem abrir portas:

```bash
# Baixar plugin
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" \
  -o "session-manager-plugin.deb"

# Instalar
sudo dpkg -i session-manager-plugin.deb

# Limpar
rm session-manager-plugin.deb

# Verificar
session-manager-plugin --version
```

---

## 6. Ferramentas Kubernetes

### 6.1 Instalar kubectl

```bash
# Baixar versão estável mais recente
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

# Verificar checksum (opcional mas recomendado)
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check

# Instalar
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Limpar
rm kubectl kubectl.sha256

# Verificar
kubectl version --client

# Habilitar autocomplete
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'alias k=kubectl' >> ~/.bashrc
echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
source ~/.bashrc
```

### 6.2 Instalar Helm

```bash
# Adicionar repositório Helm
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | \
  sudo tee /etc/apt/sources.list.d/helm-stable-debian.list

# Instalar
sudo apt update
sudo apt install -y helm

# Verificar
helm version

# Habilitar autocomplete
echo 'source <(helm completion bash)' >> ~/.bashrc
source ~/.bashrc
```

### 6.3 Instalar eksctl

```bash
# Baixar e instalar eksctl
ARCH=amd64
PLATFORM=$(uname -s)_$ARCH

curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"

# Verificar checksum (opcional)
curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_checksums.txt" | grep $PLATFORM | sha256sum --check

# Instalar
tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
sudo mv /tmp/eksctl /usr/local/bin

# Verificar
eksctl version

# Habilitar autocomplete
echo 'source <(eksctl completion bash)' >> ~/.bashrc
source ~/.bashrc
```

---

## 7. Configuração de Credenciais AWS

### 7.1 Criar Usuário IAM (Console AWS)

> ⚠️ **Segurança:** Para produção, use AWS SSO ou IAM Identity Center em vez de Access Keys.

1. Acesse o Console AWS → IAM → Users → Create user
2. Nome: `terraform-admin`
3. Marque: **Provide user access to the AWS Management Console** (opcional)
4. Permissions: Attach policies directly → **AdministratorAccess** (ou políticas específicas)
5. Após criar, vá em **Security credentials** → **Create access key**
6. Use case: **Command Line Interface (CLI)**
7. Salve o **Access Key ID** e **Secret Access Key**

### 7.2 Configurar AWS CLI

```bash
# Configurar credenciais (método interativo)
aws configure

# Preencha:
# AWS Access Key ID [None]: AKIAIOSFODNN7EXAMPLE
# AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
# Default region name [None]: us-east-1
# Default output format [None]: json
```

### 7.3 Configurar Múltiplos Perfis (Recomendado)

Edite `~/.aws/config`:

```bash
cat > ~/.aws/config << 'EOF'
[default]
region = us-east-1
output = json

[profile k8s-platform-dev]
region = us-east-1
output = json

[profile k8s-platform-prod]
region = us-east-1
output = json
EOF
```

Edite `~/.aws/credentials`:

```bash
cat > ~/.aws/credentials << 'EOF'
[default]
aws_access_key_id = AKIAIOSFODNN7EXAMPLE
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

[k8s-platform-dev]
aws_access_key_id = AKIAIOSFODNN7EXAMPLE_DEV
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY_DEV

[k8s-platform-prod]
aws_access_key_id = AKIAIOSFODNN7EXAMPLE_PROD
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY_PROD
EOF

# Proteger arquivo de credenciais
chmod 600 ~/.aws/credentials
```

### 7.4 Usar Perfil Específico

```bash
# Opção 1: Variável de ambiente (sessão atual)
export AWS_PROFILE=k8s-platform-prod

# Opção 2: Por comando
aws s3 ls --profile k8s-platform-prod

# Opção 3: No Terraform (provider)
# provider "aws" {
#   profile = "k8s-platform-prod"
# }

# Verificar perfil ativo
aws sts get-caller-identity
```

### 7.5 Adicionar Alias Úteis

```bash
cat >> ~/.bashrc << 'EOF'

# AWS Aliases
alias aws-whoami='aws sts get-caller-identity'
alias aws-dev='export AWS_PROFILE=k8s-platform-dev && aws-whoami'
alias aws-prod='export AWS_PROFILE=k8s-platform-prod && aws-whoami'

# Terraform Aliases
alias tf='terraform'
alias tfi='terraform init'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfd='terraform destroy'
alias tfv='terraform validate'
alias tff='terraform fmt -recursive'
alias tfo='terraform output'

# Kubernetes Aliases
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get services'
alias kgn='kubectl get nodes'
alias kga='kubectl get all'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias kex='kubectl exec -it'
EOF

source ~/.bashrc
```

---

## 8. Informações AWS - Como Obter no Console (UI)

Esta seção detalha todas as informações necessárias da AWS e exatamente onde encontrá-las no Console (Painel AWS).

### 8.1 Visão Geral das Informações Necessárias

| Informação | Onde Usar | Obrigatório |
|------------|-----------|-------------|
| Account ID | Backend S3, IAM policies | ✅ Sim |
| Access Key ID | AWS CLI, Terraform | ✅ Sim |
| Secret Access Key | AWS CLI, Terraform | ✅ Sim |
| Região (Region) | Todos os recursos | ✅ Sim |
| VPC ID | Referências de rede | Após criar |
| Subnet IDs | EKS, RDS | Após criar |
| Security Group IDs | EKS, RDS, EC2 | Após criar |
| ARNs | IAM, políticas | Conforme necessário |

### 8.2 Obter Account ID (ID da Conta)

**Método 1: Menu Superior Direito**

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  [AWS Logo]  Services ▼    Search                    [User] ▼   Region ▼   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                              ┌──────────────────────────┐   │
│                                              │ Account ID: 123456789012 │◄──│
│                                              │ ─────────────────────────│   │
│                                              │ Account                  │   │
│                                              │ Organization             │   │
│                                              │ Service Quotas           │   │
│                                              │ Billing Dashboard        │   │
│                                              │ Security Credentials     │   │
│                                              │ Sign Out                 │   │
│                                              └──────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Navegação:**
1. Faça login no Console AWS: https://console.aws.amazon.com
2. Clique no seu **nome de usuário** no canto superior direito
3. O **Account ID** aparece no topo do menu dropdown (12 dígitos)
4. Clique para copiar

**Método 2: Via AWS CLI (após configurar)**
```bash
aws sts get-caller-identity --query "Account" --output text
```

### 8.3 Criar e Obter Access Keys (Chaves de Acesso)

> ⚠️ **IMPORTANTE:** Access Keys são credenciais sensíveis. Nunca compartilhe ou commit em repositórios.

**Navegação no Console:**

```
Console AWS → IAM → Users → [Seu Usuário] → Security credentials → Access keys
```

**Passo a Passo Detalhado:**

**Passo 1: Acessar IAM**
```
┌─────────────────────────────────────────────────────────────────────────────┐
│  [AWS Logo]  Services ▼    [ Buscar: IAM                              🔍 ] │
│                            ┌─────────────────────────────────────────┐     │
│                            │ IAM                                     │◄────│
│                            │ Identity and Access Management          │     │
│                            │ Manage access to AWS resources          │     │
│                            └─────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Passo 2: Navegar até Users**
```
┌────────────────────┬────────────────────────────────────────────────────────┐
│                    │                                                        │
│  IAM Dashboard     │                   IAM Dashboard                        │
│                    │                                                        │
│  ┌──────────────┐  │   ┌─────────────────────────────────────────────────┐  │
│  │ Dashboard    │  │   │                                                 │  │
│  │              │  │   │  IAM resources                                  │  │
│  │ Access       │  │   │                                                 │  │
│  │ management   │  │   │  Users: 5    User groups: 3    Roles: 12       │  │
│  │ ├─ Users ◄───┼──┼───┼─ Policies: 25                                  │  │
│  │ ├─ Groups    │  │   │                                                 │  │
│  │ ├─ Roles     │  │   └─────────────────────────────────────────────────┘  │
│  │ └─ Policies  │  │                                                        │
│  └──────────────┘  │                                                        │
└────────────────────┴────────────────────────────────────────────────────────┘
```

**Passo 3: Selecionar ou Criar Usuário**
```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Users                                                    [Create user]    │
├─────────────────────────────────────────────────────────────────────────────┤
│  🔍 Search users                                                            │
├───────────────────────────┬─────────────────────┬───────────────────────────┤
│  User name                │  Access key age     │  Last activity            │
├───────────────────────────┼─────────────────────┼───────────────────────────┤
│  ☐ admin                  │  45 days            │  Today                    │
│  ☐ terraform-admin ◄──────│  None               │  Never                    │
│  ☐ developer              │  30 days            │  Yesterday                │
└───────────────────────────┴─────────────────────┴───────────────────────────┘
```

**Passo 4: Security Credentials**
```
┌─────────────────────────────────────────────────────────────────────────────┐
│  terraform-admin                                                            │
├─────────────────────────────────────────────────────────────────────────────┤
│  [Permissions]  [Groups]  [Tags]  [Security credentials] ◄─── Clique aqui  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Console sign-in                                                            │
│  ├─ Console password: Disabled                                              │
│  └─ [Enable console access]                                                 │
│                                                                             │
│  Multi-factor authentication (MFA)                                          │
│  └─ [Assign MFA device]                                                     │
│                                                                             │
│  Access keys                                             [Create access key]│
│  ┌─────────────────┬────────────┬─────────────┬─────────────────┐          │
│  │ Access key ID   │ Status     │ Created     │ Last used       │          │
│  ├─────────────────┼────────────┼─────────────┼─────────────────┤          │
│  │ (nenhuma)       │            │             │                 │          │
│  └─────────────────┴────────────┴─────────────┴─────────────────┘          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Passo 5: Criar Access Key**
```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Create access key - Step 1                                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Access key best practices & alternatives                                   │
│                                                                             │
│  Use case                                                                   │
│                                                                             │
│  ○ Command Line Interface (CLI) ◄─────────────────── Selecione esta opção  │
│    You plan to use this access key to enable the AWS CLI                    │
│    to access your AWS account.                                              │
│                                                                             │
│  ○ Local code                                                               │
│  ○ Application running on an AWS compute service                            │
│  ○ Third-party service                                                      │
│  ○ Application running outside AWS                                          │
│  ○ Other                                                                    │
│                                                                             │
│                                                          [Next]             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Passo 6: Confirmar e Criar**
```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Create access key - Step 2                                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ☑ I understand the above recommendation and want to proceed                │
│    to create an access key.                                                 │
│                                                                             │
│  Description tag - optional                                                 │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ terraform-admin-key                                                 │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│                                                      [Create access key]    │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Passo 7: Copiar Credenciais (ÚNICO MOMENTO!)**
```
┌─────────────────────────────────────────────────────────────────────────────┐
│  ✅ Access key created                                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ⚠️ This is the only time that the secret access key can be viewed          │
│     or downloaded. You cannot recover it later.                             │
│                                                                             │
│  Access key                                                                 │
│  ┌───────────────────────────────────────────────┬──────────┐              │
│  │ AKIAIOSFODNN7EXAMPLE                          │ [Copy]   │◄─── Copie   │
│  └───────────────────────────────────────────────┴──────────┘              │
│                                                                             │
│  Secret access key                                          [Show]          │
│  ┌───────────────────────────────────────────────┬──────────┐              │
│  │ wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY      │ [Copy]   │◄─── Copie   │
│  └───────────────────────────────────────────────┴──────────┘              │
│                                                                             │
│                          [Download .csv file]   [Done]                      │
│                                                                             │
│  💡 Recomendação: Baixe o arquivo CSV como backup seguro                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

> ⚠️ **ATENÇÃO:** Este é o **ÚNICO momento** em que você verá a Secret Access Key. Salve-a em local seguro!

### 8.4 Selecionar e Verificar Região (Region)

**Navegação:**
```
┌─────────────────────────────────────────────────────────────────────────────┐
│  [AWS Logo]  Services ▼    Search                    User ▼   [Region ▼]   │
│                                                              │             │
│                                              ┌───────────────┴────────────┐│
│                                              │  US East (N. Virginia) ◄───┼┤
│                                              │  us-east-1                 ││
│                                              │  ─────────────────────────  ││
│                                              │  US East (Ohio)             ││
│                                              │  us-east-2                  ││
│                                              │  ─────────────────────────  ││
│                                              │  US West (Oregon)           ││
│                                              │  us-west-2                  ││
│                                              │  ─────────────────────────  ││
│                                              │  South America (São Paulo)  ││
│                                              │  sa-east-1                  ││
│                                              └─────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────┘
```

**Regiões Recomendadas para Brasil:**

| Região | Código | Latência para Brasil | Recomendação |
|--------|--------|----------------------|--------------|
| São Paulo | `sa-east-1` | ~20-50ms | Produção Brasil |
| N. Virginia | `us-east-1` | ~120-180ms | Dev/Teste, mais serviços |
| Ohio | `us-east-2` | ~130-190ms | Alternativa US |

### 8.5 Obter VPC ID e Subnet IDs (Após Criar)

**Navegação:**
```
Console AWS → VPC → Your VPCs (ou Subnets)
```

**Tela de VPCs:**
```
┌────────────────────┬────────────────────────────────────────────────────────┐
│                    │                                                        │
│  VPC Dashboard     │              Your VPCs                                 │
│                    │                                                        │
│  ┌──────────────┐  │  [Create VPC]                                         │
│  │ Your VPCs ◄──┼──┼──                                                     │
│  │ Subnets      │  │  ┌──────────────┬─────────────────┬──────────────────┐│
│  │ Route tables │  │  │ VPC ID       │ Name            │ IPv4 CIDR        ││
│  │ Internet GW  │  │  ├──────────────┼─────────────────┼──────────────────┤│
│  │ NAT gateways │  │  │ vpc-0abc123◄─│ k8s-platform    │ 10.0.0.0/16      ││
│  │ Endpoints    │  │  │ vpc-0def456  │ default         │ 172.31.0.0/16    ││
│  └──────────────┘  │  └──────────────┴─────────────────┴──────────────────┘│
│                    │                                                        │
│  SECURITY          │  💡 Clique no VPC ID para ver detalhes                 │
│  ┌──────────────┐  │                                                        │
│  │ Security     │  │                                                        │
│  │ groups       │  │                                                        │
│  │ Network ACLs │  │                                                        │
│  └──────────────┘  │                                                        │
└────────────────────┴────────────────────────────────────────────────────────┘
```

**Tela de Subnets:**
```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Subnets                                                   [Create subnet] │
├─────────────────────────────────────────────────────────────────────────────┤
│  🔍 Filter by VPC: vpc-0abc123 (k8s-platform)                              │
├──────────────────┬───────────────────┬──────────┬──────────────────────────┤
│  Subnet ID       │  Name             │  AZ      │  IPv4 CIDR               │
├──────────────────┼───────────────────┼──────────┼──────────────────────────┤
│  subnet-priv1a ◄─│  private-1a       │  us-e-1a │  10.0.1.0/24             │
│  subnet-priv1b ◄─│  private-1b       │  us-e-1b │  10.0.2.0/24             │
│  subnet-pub1a  ◄─│  public-1a        │  us-e-1a │  10.0.101.0/24           │
│  subnet-pub1b  ◄─│  public-1b        │  us-e-1b │  10.0.102.0/24           │
└──────────────────┴───────────────────┴──────────┴──────────────────────────┘
```

**Via AWS CLI:**
```bash
# Listar VPCs
aws ec2 describe-vpcs --query "Vpcs[*].[VpcId,Tags[?Key=='Name'].Value|[0],CidrBlock]" --output table

# Listar Subnets de uma VPC
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-0abc123" \
  --query "Subnets[*].[SubnetId,Tags[?Key=='Name'].Value|[0],AvailabilityZone,CidrBlock]" --output table
```

### 8.6 Obter Security Group IDs

**Navegação:**
```
Console AWS → VPC → Security groups (ou EC2 → Security Groups)
```

**Tela de Security Groups:**
```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Security groups                                    [Create security group]│
├─────────────────────────────────────────────────────────────────────────────┤
│  🔍 Filter by VPC: vpc-0abc123                                             │
├───────────────────┬───────────────────────────┬───────────────────────────┤
│  Security group   │  Name                     │  Description              │
├───────────────────┼───────────────────────────┼───────────────────────────┤
│  sg-eks123    ◄───│  k8s-eks-cluster-sg       │  EKS cluster SG           │
│  sg-rds456    ◄───│  k8s-rds-sg               │  RDS PostgreSQL SG        │
│  sg-alb789    ◄───│  k8s-alb-sg               │  ALB ingress SG           │
│  sg-default       │  default                  │  default VPC SG           │
└───────────────────┴───────────────────────────┴───────────────────────────┘
```

**Via AWS CLI:**
```bash
# Listar Security Groups
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=vpc-0abc123" \
  --query "SecurityGroups[*].[GroupId,GroupName,Description]" --output table
```

### 8.7 Obter ARNs de Recursos

Os ARNs (Amazon Resource Names) seguem o padrão:
```
arn:aws:<service>:<region>:<account-id>:<resource-type>/<resource-id>
```

**Onde Encontrar ARNs:**

| Recurso | Navegação no Console |
|---------|---------------------|
| IAM User | IAM → Users → [usuário] → Summary → User ARN |
| IAM Role | IAM → Roles → [role] → Summary → ARN |
| IAM Policy | IAM → Policies → [policy] → Summary → ARN |
| S3 Bucket | S3 → [bucket] → Properties → ARN |
| EKS Cluster | EKS → Clusters → [cluster] → Configuration → ARN |
| RDS Database | RDS → Databases → [db] → Configuration → ARN |
| Lambda Function | Lambda → Functions → [function] → ARN (no topo) |

**Exemplo - ARN de IAM Role:**
```
┌─────────────────────────────────────────────────────────────────────────────┐
│  eks-cluster-role                                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Summary                                                                    │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ ARN: arn:aws:iam::123456789012:role/eks-cluster-role              [📋] ││
│  │ ─────────────────────────────────────────────────────────────────       ││
│  │ Creation time: 2026-01-15 10:30:00 UTC                                  ││
│  │ Last activity: 2026-01-20 08:45:00 UTC                                  ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Via AWS CLI:**
```bash
# ARN do usuário atual
aws sts get-caller-identity --query "Arn" --output text

# ARN de uma role
aws iam get-role --role-name eks-cluster-role --query "Role.Arn" --output text

# ARN de um bucket S3
echo "arn:aws:s3:::nome-do-bucket"  # S3 não tem região no ARN
```

### 8.8 Verificar Quotas de Serviço

Antes de provisionar, verifique os limites da sua conta:

**Navegação:**
```
Console AWS → Service Quotas → AWS Services → [Serviço]
```

**Quotas Importantes para Kubernetes:**

| Serviço | Quota | Limite Default | Verificar em |
|---------|-------|----------------|--------------|
| VPC | VPCs por região | 5 | Service Quotas → VPC |
| VPC | Subnets por VPC | 200 | Service Quotas → VPC |
| EC2 | Running On-Demand | Varia por tipo | Service Quotas → EC2 |
| EKS | Clusters por região | 100 | Service Quotas → EKS |
| RDS | DB instances | 40 | Service Quotas → RDS |
| ELB | Load Balancers | 50 | Service Quotas → ELB |

**Via AWS CLI:**
```bash
# Verificar quota específica
aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-1216C47A \
  --query "Quota.[QuotaName,Value]" --output table

# Listar quotas de EKS
aws service-quotas list-service-quotas --service-code eks
```

### 8.9 Verificar Billing e Custos

**Navegação:**
```
Console AWS → Billing and Cost Management (menu superior direito → Billing Dashboard)
```

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Billing and Cost Management                                               │
├────────────────────┬────────────────────────────────────────────────────────┤
│                    │                                                        │
│  ┌──────────────┐  │  Month-to-date costs                                  │
│  │ Home         │  │  ┌─────────────────────────────────────────────────┐  │
│  │ Bills        │  │  │  $142.50                            (estimate)  │  │
│  │ Cost Explorer│  │  └─────────────────────────────────────────────────┘  │
│  │ Budgets  ◄───┼──┼──                                                     │
│  │ Cost Alloc.  │  │  Top services                                         │
│  │ Free Tier    │  │  ├─ EC2: $85.00                                       │
│  └──────────────┘  │  ├─ RDS: $45.00                                       │
│                    │  └─ S3: $12.50                                        │
└────────────────────┴────────────────────────────────────────────────────────┘
```

> 💡 **Dica:** Configure alertas de billing em Budgets para evitar surpresas!

### 8.10 Checklist de Informações para Terraform

Use esta checklist antes de iniciar o Terraform:

```markdown
## Checklist - Informações AWS Coletadas

### Obrigatórias (antes de começar)
- [ ] Account ID: _______________
- [ ] Access Key ID: _______________
- [ ] Secret Access Key: _______________ (armazenada em local seguro)
- [ ] Região escolhida: _______________

### Verificações de Quota
- [ ] VPCs disponíveis na região
- [ ] Subnets disponíveis
- [ ] Limite de instâncias EC2
- [ ] Limite de clusters EKS

### Após criar infraestrutura base
- [ ] VPC ID: _______________
- [ ] Subnet IDs (private): _______________
- [ ] Subnet IDs (public): _______________
- [ ] Security Group IDs: _______________
- [ ] EKS Cluster ARN: _______________

### Configuração de Billing
- [ ] Budget de alerta configurado
- [ ] Free tier verificado
```

---

## 9. Estrutura do Projeto Terraform

### 9.1 Criar Estrutura de Diretórios

```bash
# Criar diretório do projeto
mkdir -p ~/projects/k8s-platform-infra
cd ~/projects/k8s-platform-infra

# Criar estrutura
mkdir -p {terraform/{01-vpc-eks,03-rds,05-waf,modules},scripts,docs}

# Criar arquivos base
touch terraform/01-vpc-eks/{main.tf,variables.tf,outputs.tf,terraform.tfvars}
touch terraform/03-rds/{main.tf,variables.tf,outputs.tf,terraform.tfvars}
touch terraform/05-waf/{main.tf,variables.tf,outputs.tf,terraform.tfvars}
touch scripts/{validate-infra.sh,create-backend.sh}
touch .gitignore README.md

# Visualizar estrutura
tree -a
```

**Estrutura esperada:**

```
k8s-platform-infra/
├── .gitignore
├── README.md
├── docs/
├── scripts/
│   ├── create-backend.sh
│   └── validate-infra.sh
└── terraform/
    ├── 01-vpc-eks/
    │   ├── main.tf
    │   ├── outputs.tf
    │   ├── terraform.tfvars
    │   └── variables.tf
    ├── 03-rds/
    │   ├── main.tf
    │   ├── outputs.tf
    │   ├── terraform.tfvars
    │   └── variables.tf
    ├── 05-waf/
    │   ├── main.tf
    │   ├── outputs.tf
    │   ├── terraform.tfvars
    │   └── variables.tf
    └── modules/
```

### 9.2 Criar .gitignore

```bash
cat > .gitignore << 'EOF'
# Terraform
.terraform/
*.tfstate
*.tfstate.*
*.tfplan
*.tfvars.json
crash.log
crash.*.log
override.tf
override.tf.json
*_override.tf
*_override.tf.json
.terraformrc
terraform.rc

# Sensitive files
*.pem
*.key
*credentials*
*secret*

# IDE
.vscode/
.idea/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Logs
*.log

# Local tfvars (may contain secrets)
*.auto.tfvars
local.tfvars
EOF
```

### 9.3 Criar README Base

```bash
cat > README.md << 'EOF'
# K8s Platform Infrastructure

Infraestrutura como código para a plataforma Kubernetes na AWS.

## Pré-requisitos

- Terraform >= 1.5.0
- AWS CLI >= 2.0
- kubectl >= 1.28
- helm >= 3.0

## Estrutura

```
terraform/
├── 01-vpc-eks/    # VPC + EKS Cluster
├── 03-rds/        # RDS PostgreSQL
├── 05-waf/        # WAF Web ACL
└── modules/       # Módulos reutilizáveis
```

## Quick Start

```bash
# 1. Configurar credenciais AWS
export AWS_PROFILE=k8s-platform-prod

# 2. Criar backend S3
./scripts/create-backend.sh

# 3. Provisionar VPC + EKS
cd terraform/01-vpc-eks
terraform init
terraform plan
terraform apply
```

## Documentação

Veja `docs/` para documentação detalhada.
EOF
```

---

## 10. Configuração do Backend S3

### 10.1 Script para Criar Backend

O Terraform precisa de um backend para armazenar o estado. Criamos um bucket S3 com versionamento e criptografia:

```bash
cat > scripts/create-backend.sh << 'EOF'
#!/bin/bash
#
# Script para criar o backend S3 do Terraform
# Executa apenas uma vez, antes do primeiro terraform init
#

set -euo pipefail

# Configurações
BUCKET_NAME="k8s-platform-terraform-state"
DYNAMODB_TABLE="terraform-state-lock"
REGION="us-east-1"
AWS_PROFILE="${AWS_PROFILE:-default}"

echo "🚀 Criando backend Terraform..."
echo "   Bucket: $BUCKET_NAME"
echo "   Region: $REGION"
echo "   Profile: $AWS_PROFILE"
echo ""

# 1. Criar bucket S3
echo "📦 Criando bucket S3..."
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    echo "   Bucket já existe"
else
    aws s3api create-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$REGION" \
        --profile "$AWS_PROFILE"
    echo "   ✅ Bucket criado"
fi

# 2. Habilitar versionamento
echo "📝 Habilitando versionamento..."
aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled \
    --profile "$AWS_PROFILE"
echo "   ✅ Versionamento habilitado"

# 3. Habilitar criptografia
echo "🔐 Habilitando criptografia..."
aws s3api put-bucket-encryption \
    --bucket "$BUCKET_NAME" \
    --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            },
            "BucketKeyEnabled": true
        }]
    }' \
    --profile "$AWS_PROFILE"
echo "   ✅ Criptografia habilitada"

# 4. Bloquear acesso público
echo "🔒 Bloqueando acesso público..."
aws s3api put-public-access-block \
    --bucket "$BUCKET_NAME" \
    --public-access-block-configuration '{
        "BlockPublicAcls": true,
        "IgnorePublicAcls": true,
        "BlockPublicPolicy": true,
        "RestrictPublicBuckets": true
    }' \
    --profile "$AWS_PROFILE"
echo "   ✅ Acesso público bloqueado"

# 5. Criar tabela DynamoDB para locking
echo "🔄 Criando tabela DynamoDB para locking..."
if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$REGION" --profile "$AWS_PROFILE" 2>/dev/null; then
    echo "   Tabela já existe"
else
    aws dynamodb create-table \
        --table-name "$DYNAMODB_TABLE" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$REGION" \
        --profile "$AWS_PROFILE"

    echo "   ⏳ Aguardando tabela ficar ativa..."
    aws dynamodb wait table-exists \
        --table-name "$DYNAMODB_TABLE" \
        --region "$REGION" \
        --profile "$AWS_PROFILE"
    echo "   ✅ Tabela DynamoDB criada"
fi

# 6. Adicionar tags
echo "🏷️ Adicionando tags..."
aws s3api put-bucket-tagging \
    --bucket "$BUCKET_NAME" \
    --tagging 'TagSet=[{Key=Project,Value=k8s-platform},{Key=ManagedBy,Value=terraform},{Key=Purpose,Value=terraform-state}]' \
    --profile "$AWS_PROFILE"

aws dynamodb tag-resource \
    --resource-arn "arn:aws:dynamodb:${REGION}:$(aws sts get-caller-identity --query Account --output text --profile $AWS_PROFILE):table/${DYNAMODB_TABLE}" \
    --tags Key=Project,Value=k8s-platform Key=ManagedBy,Value=terraform Key=Purpose,Value=terraform-state-lock \
    --region "$REGION" \
    --profile "$AWS_PROFILE"
echo "   ✅ Tags adicionadas"

echo ""
echo "🎉 Backend criado com sucesso!"
echo ""
echo "📋 Adicione este bloco no seu main.tf:"
echo ""
cat << TERRAFORM
terraform {
  backend "s3" {
    bucket         = "$BUCKET_NAME"
    key            = "vpc-eks/terraform.tfstate"  # Altere conforme o módulo
    region         = "$REGION"
    dynamodb_table = "$DYNAMODB_TABLE"
    encrypt        = true
  }
}
TERRAFORM
EOF

chmod +x scripts/create-backend.sh
```

### 10.2 Executar Script de Backend

```bash
# Definir perfil (se necessário)
export AWS_PROFILE=k8s-platform-prod

# Executar script
./scripts/create-backend.sh
```

---

## 11. Validação do Ambiente

### 11.1 Script de Validação Completo

```bash
cat > scripts/validate-environment.sh << 'EOF'
#!/bin/bash
#
# Valida se todas as ferramentas estão instaladas e configuradas
#

set -euo pipefail

echo "🔍 Validando ambiente de desenvolvimento..."
echo ""

ERRORS=0

# Função de verificação
check_command() {
    local cmd=$1
    local min_version=$2
    local version_cmd=$3

    if command -v "$cmd" &> /dev/null; then
        version=$(eval "$version_cmd" 2>/dev/null | head -1)
        echo "✅ $cmd: $version"
    else
        echo "❌ $cmd: NÃO INSTALADO"
        ERRORS=$((ERRORS + 1))
    fi
}

echo "=== Ferramentas CLI ==="
check_command "terraform" "1.5.0" "terraform version | head -1"
check_command "aws" "2.0" "aws --version"
check_command "kubectl" "1.28" "kubectl version --client --short 2>/dev/null || kubectl version --client"
check_command "helm" "3.0" "helm version --short"
check_command "eksctl" "0.160" "eksctl version"
check_command "git" "2.0" "git --version"
check_command "jq" "1.6" "jq --version"

echo ""
echo "=== Configuração AWS ==="

# Verificar credenciais AWS
if aws sts get-caller-identity &> /dev/null; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
    USER_ARN=$(aws sts get-caller-identity --query "Arn" --output text)
    echo "✅ AWS Credentials: Configuradas"
    echo "   Account: $ACCOUNT_ID"
    echo "   User/Role: $USER_ARN"
else
    echo "❌ AWS Credentials: NÃO CONFIGURADAS"
    ERRORS=$((ERRORS + 1))
fi

# Verificar região
if [ -n "${AWS_DEFAULT_REGION:-}" ] || [ -n "${AWS_REGION:-}" ]; then
    echo "✅ AWS Region: ${AWS_DEFAULT_REGION:-${AWS_REGION:-us-east-1}}"
else
    REGION=$(aws configure get region 2>/dev/null || echo "não configurada")
    if [ "$REGION" != "não configurada" ]; then
        echo "✅ AWS Region: $REGION"
    else
        echo "⚠️ AWS Region: Não definida (usando us-east-1 como padrão)"
    fi
fi

# Verificar perfil
echo "   Profile: ${AWS_PROFILE:-default}"

echo ""
echo "=== Terraform Backend ==="

BUCKET_NAME="k8s-platform-terraform-state"
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    echo "✅ S3 Backend: $BUCKET_NAME (existe)"
else
    echo "⚠️ S3 Backend: $BUCKET_NAME (não existe - execute ./scripts/create-backend.sh)"
fi

DYNAMODB_TABLE="terraform-state-lock"
if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" &>/dev/null; then
    echo "✅ DynamoDB Lock: $DYNAMODB_TABLE (existe)"
else
    echo "⚠️ DynamoDB Lock: $DYNAMODB_TABLE (não existe)"
fi

echo ""
echo "=== VSCode Extensions ==="
if command -v code &> /dev/null; then
    EXTENSIONS=$(code --list-extensions 2>/dev/null)
    for ext in "ms-vscode-remote.remote-wsl" "hashicorp.terraform" "amazonwebservices.aws-toolkit-vscode"; do
        if echo "$EXTENSIONS" | grep -q "$ext"; then
            echo "✅ $ext"
        else
            echo "⚠️ $ext (não instalada)"
        fi
    done
else
    echo "⚠️ VSCode CLI não disponível no PATH"
fi

echo ""
echo "=================================="
if [ $ERRORS -eq 0 ]; then
    echo "🎉 Ambiente validado com sucesso!"
    exit 0
else
    echo "❌ Encontrados $ERRORS erros. Corrija antes de continuar."
    exit 1
fi
EOF

chmod +x scripts/validate-environment.sh
```

### 11.2 Executar Validação

```bash
./scripts/validate-environment.sh
```

**Saída esperada:**

```
🔍 Validando ambiente de desenvolvimento...

=== Ferramentas CLI ===
✅ terraform: Terraform v1.7.0
✅ aws: aws-cli/2.15.0 Python/3.11.6 Linux/5.15.0
✅ kubectl: v1.29.0
✅ helm: v3.14.0
✅ eksctl: 0.169.0
✅ git: git version 2.34.1
✅ jq: jq-1.6

=== Configuração AWS ===
✅ AWS Credentials: Configuradas
   Account: 123456789012
   User/Role: arn:aws:iam::123456789012:user/terraform-admin
✅ AWS Region: us-east-1
   Profile: k8s-platform-prod

=== Terraform Backend ===
✅ S3 Backend: k8s-platform-terraform-state (existe)
✅ DynamoDB Lock: terraform-state-lock (existe)

=== VSCode Extensions ===
✅ ms-vscode-remote.remote-wsl
✅ hashicorp.terraform
✅ amazonwebservices.aws-toolkit-vscode

==================================
🎉 Ambiente validado com sucesso!
```

---

## 12. Troubleshooting

### 12.1 WSL não inicia

```powershell
# Verificar status do WSL
wsl --status

# Atualizar WSL
wsl --update

# Reiniciar WSL
wsl --shutdown
wsl
```

### 12.2 VSCode não conecta ao WSL

```bash
# No WSL, reinstalar o servidor VSCode
rm -rf ~/.vscode-server

# Abrir novamente
code .
```

### 12.3 Terraform não encontra provider

```bash
# Limpar cache e reinicializar
rm -rf .terraform .terraform.lock.hcl
terraform init -upgrade
```

### 12.4 AWS CLI sem credenciais

```bash
# Verificar arquivos
cat ~/.aws/credentials
cat ~/.aws/config

# Testar conectividade
aws sts get-caller-identity --debug

# Verificar variáveis de ambiente
env | grep AWS
```

### 12.5 kubectl não conecta ao cluster

```bash
# Atualizar kubeconfig
aws eks update-kubeconfig --region us-east-1 --name k8s-platform-prod

# Verificar contexto
kubectl config current-context
kubectl config get-contexts

# Testar conexão
kubectl cluster-info
```

### 12.6 Permissão negada no WSL

```bash
# Corrigir permissões de credenciais AWS
chmod 600 ~/.aws/credentials
chmod 600 ~/.aws/config

# Verificar ownership
ls -la ~/.aws/
```

### 12.7 Terraform state lock

```bash
# Se o lock ficou "travado" após erro:
terraform force-unlock <LOCK_ID>

# O LOCK_ID aparece na mensagem de erro
```

---

## Próximos Passos

Após configurar o ambiente:

1. Clone/crie o projeto de infraestrutura
2. Execute `./scripts/create-backend.sh` (uma vez)
3. Siga o documento **[01-infraestrutura-base-aws.md](01-infraestrutura-base-aws.md)**

---

**Documento:** 00-setup-ambiente-terraform.md
**Versão:** 1.0
**Última atualização:** 2026-01-20
