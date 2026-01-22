# Tutorial: Instalação do AWS CLI V2

**Versão:** 1.0
**Data:** 2026-01-22
**Projeto:** Arquitetura Multi-Domínio Kubernetes
**Autor:** DevOps Team

---

## Índice

1. [Introdução](#1-introdução)
2. [Pré-requisitos](#2-pré-requisitos)
3. [Instalação por Sistema Operacional](#3-instalação-por-sistema-operacional)
4. [Configuração Inicial](#4-configuração-inicial)
5. [Métodos de Autenticação](#5-métodos-de-autenticação)
6. [Verificação e Testes](#6-verificação-e-testes)
7. [Solução de Problemas](#7-solução-de-problemas)
8. [Comandos Úteis](#8-comandos-úteis)

---

## 1. Introdução

O **AWS CLI V2** é a interface de linha de comando oficial da Amazon Web Services, que permite interagir com os serviços AWS diretamente do terminal. A versão 2 traz melhorias significativas em relação à V1, incluindo:

- ✅ Melhor performance e menor uso de memória
- ✅ Suporte nativo a AWS SSO (IAM Identity Center)
- ✅ Autocompleção melhorada
- ✅ Novas features como `aws configure sso`, `aws s3 sync` otimizado
- ✅ Instalador standalone (não requer Python)

### Por que AWS CLI V2?

| Característica | AWS CLI V1 | AWS CLI V2 |
|----------------|------------|------------|
| **Instalação** | Via pip (Python) | Instalador nativo |
| **AWS SSO** | Não suportado | ✅ Suportado |
| **Performance** | Normal | Otimizada |
| **Python necessário** | Sim | Não |
| **Autocompleção** | Básica | Avançada |
| **Status** | Manutenção | Desenvolvimento ativo |

---

## 2. Pré-requisitos

### Requisitos Mínimos

- **Sistema Operacional:**
  - Linux (64-bit) - kernel 2.6.18+
  - macOS 10.14+ (Mojave)
  - Windows 10/11 (64-bit)
- **Espaço em disco:** 500 MB
- **Permissões:** Acesso administrativo (sudo/admin) para instalação global

### Verificar Instalação Existente

Antes de instalar, verifique se já possui o AWS CLI instalado:

```bash
# Verificar versão instalada
aws --version

# Saída esperada (se instalado):
# aws-cli/2.15.0 Python/3.11.6 Linux/5.15.0-91-generic exe/x86_64.ubuntu.22
```

Se a versão for **1.x.x**, recomendamos desinstalar antes de prosseguir:

```bash
# Desinstalar AWS CLI V1 (Python/pip)
pip uninstall awscli -y
# ou
pip3 uninstall awscli -y
```

---

## 3. Instalação por Sistema Operacional

> **💡 RECOMENDAÇÃO IMPORTANTE:** Se você está usando **Windows**, recomendamos FORTEMENTE usar **WSL (Windows Subsystem for Linux)** ao invés do PowerShell nativo. Veja a seção [WSL (Windows Subsystem for Linux)](#-wsl-windows-subsystem-for-linux---recomendado) abaixo.

### 🐧 WSL (Windows Subsystem for Linux) - RECOMENDADO

**✅ Por que usar WSL ao invés de PowerShell?**

| Aspecto                 | Windows PowerShell          | WSL (Ubuntu)            |
| ----------------------- | --------------------------- | ----------------------- |
| **Scripts do projeto**  | ❌ Precisa adaptar sintaxe  | ✅ Roda direto          |
| **Ferramentas DevOps**  | ⚠️ Híbridas                 | ✅ Todas nativas        |
| **Compatibilidade**     | ⚠️ Requer adaptações        | ✅ 100% compatível      |
| **Experiência**         | ⚠️ Diferente de produção    | ✅ Igual ambiente cloud |
| **Docker/Kubernetes**   | ⚠️ Docker Desktop           | ✅ Integração nativa    |

**Instalação do WSL 2 (se ainda não tiver):**

```powershell
# No PowerShell como Administrador (Windows):
wsl --install -d Ubuntu-22.04

# Ou atualizar para WSL 2:
wsl --set-default-version 2
wsl --set-version Ubuntu-22.04 2
```

**Depois de instalar o WSL, siga as instruções de instalação para Linux abaixo.**

**💡 Tutorial completo:** Veja [Configuração de Ambiente WSL](./wsl-environment-setup.md) para setup automatizado.

---

### 🐧 Linux (Ubuntu/Debian/Red Hat/Amazon Linux)

#### Método 1: Instalação via Script (Recomendado)

```bash
# 1. Baixar o instalador
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"

# 2. Instalar unzip (se necessário)
# Ubuntu/Debian:
sudo apt update && sudo apt install unzip -y
# Red Hat/CentOS/Amazon Linux:
sudo yum install unzip -y

# 3. Descompactar o instalador
unzip awscliv2.zip

# 4. Executar o instalador
sudo ./aws/install

# 5. Verificar instalação
aws --version
```

#### Método 2: Instalação em Diretório Customizado

Se não tiver permissões sudo ou quiser instalar em local específico:

```bash
# Baixar e descompactar (passos 1-3 acima)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip

# Instalar em diretório local
./aws/install -i ~/aws-cli -b ~/bin

# Adicionar ao PATH
echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
source ~/.bashrc

# Verificar
aws --version
```

#### Método 3: Instalação via Snap (Ubuntu)

```bash
# Instalar via snap
sudo snap install aws-cli --classic

# Verificar
aws --version
```

---

### 🍎 macOS

#### Método 1: Instalação via PKG (Recomendado)

```bash
# 1. Baixar o instalador PKG
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"

# 2. Instalar
sudo installer -pkg AWSCLIV2.pkg -target /

# 3. Verificar instalação
aws --version
```

#### Método 2: Instalação via Homebrew

```bash
# Instalar Homebrew (se não tiver)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Instalar AWS CLI V2
brew install awscli

# Verificar
aws --version
```

#### Método 3: Instalação Manual

```bash
# 1. Baixar o pacote
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"

# 2. Abrir o pacote manualmente
open AWSCLIV2.pkg

# 3. Seguir wizard de instalação

# 4. Verificar
aws --version
```

---

### 🪟 Windows

#### Método 1: Instalação via MSI (Recomendado)

1. Baixe o instalador MSI:
   - [AWS CLI V2 para Windows 64-bit](https://awscli.amazonaws.com/AWSCLIV2.msi)

2. Execute o instalador `AWSCLIV2.msi`

3. Siga o wizard de instalação:
   - Aceite os termos de licença
   - Escolha "Install for all users"
   - Mantenha o caminho padrão: `C:\Program Files\Amazon\AWSCLIV2\`

4. Verifique a instalação:

```powershell
# Abrir PowerShell ou CMD
aws --version
```

#### Método 2: Instalação via PowerShell

```powershell
# 1. Baixar o instalador
Invoke-WebRequest -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" -OutFile "$env:TEMP\AWSCLIV2.msi"

# 2. Instalar silenciosamente
Start-Process msiexec.exe -ArgumentList "/i $env:TEMP\AWSCLIV2.msi /quiet" -Wait

# 3. Atualizar PATH (fechar e reabrir PowerShell)
# Ou adicionar manualmente:
$env:Path += ";C:\Program Files\Amazon\AWSCLIV2\"

# 4. Verificar
aws --version
```

#### Método 3: Instalação via Chocolatey

```powershell
# Instalar Chocolatey (se não tiver)
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Instalar AWS CLI V2
choco install awscli -y

# Verificar
aws --version
```

---

### 🐳 Docker (Qualquer plataforma)

Se você trabalha com Docker, pode usar a imagem oficial:

```bash
# Usar imagem oficial AWS CLI
docker pull amazon/aws-cli

# Executar comandos
docker run --rm -it amazon/aws-cli --version

# Criar alias para facilitar uso
alias aws='docker run --rm -it -v ~/.aws:/root/.aws amazon/aws-cli'

# Agora pode usar normalmente
aws s3 ls
```

---

## 4. Configuração Inicial

Após instalar o AWS CLI V2, você precisa configurá-lo para acessar sua conta AWS.

### Estrutura de Arquivos de Configuração

O AWS CLI armazena configurações em:

```
~/.aws/
├── config       # Configurações gerais (região, output format)
└── credentials  # Credenciais de acesso (Access Keys)
```

### Configuração Básica (Primeira Execução)

```bash
# Configurar credenciais e região
aws configure

# O comando solicitará:
AWS Access Key ID [None]: AKIAIOSFODNN7EXAMPLE
AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
Default region name [None]: us-east-1
Default output format [None]: json
```

Isso criará os arquivos:

**~/.aws/credentials:**
```ini
[default]
aws_access_key_id = AKIAIOSFODNN7EXAMPLE
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

**~/.aws/config:**
```ini
[default]
region = us-east-1
output = json
```

---

## 5. Métodos de Autenticação

Existem várias formas de autenticar com a AWS. Escolha o método adequado ao seu caso de uso.

### 🔹 Método 1: AWS CloudShell (Sem instalação local)

**✅ Melhor para:** Testes rápidos, uso ocasional

**Vantagens:**
- Zero configuração necessária
- Credenciais automáticas do console AWS
- Sem risco de vazamento de Access Keys
- Ambiente pré-configurado com ferramentas

**Como usar:**

1. Acesse o Console AWS: https://console.aws.amazon.com/
2. Clique no ícone `>_` (CloudShell) no canto superior direito
3. Aguarde inicialização (10-30 segundos)
4. Comece a usar:

```bash
# Verificar identidade
aws sts get-caller-identity

# Listar buckets S3
aws s3 ls

# Listar clusters EKS
aws eks list-clusters --region us-east-1
```

---

### 🔹 Método 2: IAM Identity Center (AWS SSO)

**✅ Melhor para:** Uso diário por desenvolvedores/administradores

**Vantagens:**
- Integração com Azure AD/Okta/Google Workspace
- MFA obrigatório
- Credenciais temporárias (renovação automática)
- Múltiplas contas AWS centralizadas
- Auditoria completa

**Pré-requisito:** IAM Identity Center configurado na organização

#### Configuração Inicial

```bash
# 1. Configurar SSO
aws configure sso

# O comando solicitará:
SSO session name (Recommended): k8s-platform-sso
SSO start URL [None]: https://sua-empresa.awsapps.com/start
SSO region [None]: us-east-1
SSO registration scopes [sso:account:access]:

# 2. Uma janela do browser abrirá para login
# Complete o login com suas credenciais corporativas + MFA

# 3. Selecione a conta AWS e permission set
AWS Account: 123456789012 (k8s-platform-prod)
Permission set: PowerUserAccess

# 4. Configure região e output
CLI default client Region [us-east-1]: us-east-1
CLI default output format [json]: json
CLI profile name [PowerUserAccess-123456789012]: k8s-platform-prod

# 5. Verificar configuração
aws sts get-caller-identity --profile k8s-platform-prod
```

#### Arquivo de Configuração Resultante

**~/.aws/config:**
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

#### Uso Diário

```bash
# Login SSO (válido por 8 horas por padrão)
aws sso login --profile k8s-platform-prod

# Usar comandos normalmente
aws s3 ls --profile k8s-platform-prod

# OU definir perfil como padrão
export AWS_PROFILE=k8s-platform-prod
aws s3 ls

# Verificar status da sessão
aws sts get-caller-identity

# Logout
aws sso logout
```

---

### 🔹 Método 3: Access Keys (IAM User)

**⚠️ Use apenas para:** CI/CD pipelines, Terraform automatizado, scripts

**Desvantagens:**
- Credenciais permanentes (risco de segurança)
- Rotação manual obrigatória
- Não suporta MFA de forma prática

#### Criar Access Keys no Console AWS

1. Acesse **IAM** → **Users**
2. Clique no usuário (ou crie um novo para automação)
3. Aba **Security credentials**
4. **Create access key**
5. Selecione **Command Line Interface (CLI)**
6. Marque o checkbox de confirmação
7. **Download .csv** ou copie manualmente

#### Configurar Localmente

**Opção A: Via comando `aws configure`**

```bash
# Configurar perfil com Access Keys
aws configure --profile k8s-platform-terraform

AWS Access Key ID [None]: AKIAIOSFODNN7EXAMPLE
AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
Default region name [None]: us-east-1
Default output format [None]: json
```

**Opção B: Editar manualmente**

```bash
# Editar arquivo de credenciais
nano ~/.aws/credentials
```

**~/.aws/credentials:**
```ini
[k8s-platform-terraform]
aws_access_key_id = AKIAIOSFODNN7EXAMPLE
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

**~/.aws/config:**
```ini
[profile k8s-platform-terraform]
region = us-east-1
output = json
```

#### Uso

```bash
# Usar perfil específico
aws s3 ls --profile k8s-platform-terraform

# Ou definir como padrão
export AWS_PROFILE=k8s-platform-terraform
aws s3 ls

# Ou via variáveis de ambiente (CI/CD)
export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
export AWS_DEFAULT_REGION="us-east-1"
aws s3 ls
```

#### ⚠️ Rotação de Access Keys (Obrigatório a cada 90 dias)

```bash
# 1. Criar nova Access Key
aws iam create-access-key --user-name terraform-k8s-platform

# 2. Atualizar ~/.aws/credentials com a nova key

# 3. Testar nova key
aws sts get-caller-identity

# 4. Deletar key antiga
aws iam delete-access-key \
    --user-name terraform-k8s-platform \
    --access-key-id AKIAOLDKEYEXAMPLE
```

---

### 🔹 Método 4: IAM Roles (EC2/Lambda/ECS)

**✅ Melhor para:** Aplicações rodando dentro da AWS

Quando você executa aplicações em EC2, Lambda, ECS ou EKS, não precisa configurar credenciais manualmente. Basta associar uma IAM Role à instância/função.

#### EC2 Instance Profile

```bash
# Nenhuma configuração necessária!
# O AWS CLI detecta automaticamente a role da instância

# Dentro da instância EC2:
aws sts get-caller-identity
# Retorna a role associada à instância
```

#### Lambda

```python
# lambda_function.py
import boto3

def lambda_handler(event, context):
    # SDK usa automaticamente a role da Lambda
    s3 = boto3.client('s3')
    buckets = s3.list_buckets()
    return buckets
```

---

### 🔹 Método 5: Assume Role (Cross-Account)

**✅ Melhor para:** Acesso a múltiplas contas AWS a partir de uma conta central

```bash
# Configurar role assumida
nano ~/.aws/config
```

**~/.aws/config:**
```ini
[profile prod-account]
role_arn = arn:aws:iam::123456789012:role/ProdAdminRole
source_profile = default
region = us-east-1
```

```bash
# Usar a role
aws s3 ls --profile prod-account
```

---

## 6. Verificação e Testes

### Verificar Instalação

```bash
# Versão do AWS CLI
aws --version
# Saída esperada: aws-cli/2.15.0 ...

# Verificar identidade (quem sou eu?)
aws sts get-caller-identity
# Retorna: UserId, Account, Arn

# Verificar região configurada
aws configure get region

# Verificar output format
aws configure get output
```

### Testes de Conectividade

```bash
# Listar regiões disponíveis
aws ec2 describe-regions --output table

# Listar buckets S3
aws s3 ls

# Listar clusters EKS
aws eks list-clusters --region us-east-1

# Listar instâncias EC2
aws ec2 describe-instances --region us-east-1 --output table

# Verificar limites da conta (Service Quotas)
aws service-quotas get-service-quota \
    --service-code ec2 \
    --quota-code L-1216C47A
```

### Teste de Autocompleção

```bash
# Habilitar autocompleção (Bash)
echo "complete -C aws_completer aws" >> ~/.bashrc
source ~/.bashrc

# Habilitar autocompleção (Zsh)
echo "autoload bashcompinit && bashcompinit" >> ~/.zshrc
echo "complete -C aws_completer aws" >> ~/.zshrc
source ~/.zshrc

# Testar (digite aws s3 e pressione TAB)
aws s3 <TAB>
# Deve sugerir: cp, ls, mb, mv, rb, rm, sync, etc.
```

---

## 7. Solução de Problemas

### Problema: "aws: command not found"

**Causa:** AWS CLI não está no PATH

**Solução:**

```bash
# Linux/macOS - Adicionar ao PATH
echo 'export PATH=/usr/local/bin:$PATH' >> ~/.bashrc
source ~/.bashrc

# Verificar onde o aws está instalado
which aws
# Ou
find / -name aws 2>/dev/null

# Se encontrar, adicione o diretório ao PATH
export PATH=/caminho/do/aws:$PATH
```

**Windows:**

1. Abrir "Variáveis de Ambiente"
2. Em "Variáveis do Sistema", editar `Path`
3. Adicionar: `C:\Program Files\Amazon\AWSCLIV2\`
4. Reiniciar PowerShell/CMD

---

### Problema: "Unable to locate credentials"

**Causa:** Credenciais não configuradas

**Solução:**

```bash
# Verificar se credenciais existem
cat ~/.aws/credentials

# Reconfigurar
aws configure

# Ou usar variáveis de ambiente
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
```

---

### Problema: "An error occurred (UnauthorizedOperation)"

**Causa:** IAM user/role não tem permissões necessárias

**Solução:**

1. Verifique as políticas IAM associadas ao usuário
2. Adicione as permissões necessárias no Console IAM
3. Teste com um usuário com `AdministratorAccess` temporariamente

```bash
# Verificar quem você é
aws sts get-caller-identity

# Verificar políticas anexadas
aws iam list-attached-user-policies --user-name seu-usuario
```

---

### Problema: "SSO session has expired"

**Causa:** Sessão SSO expirou (padrão: 8 horas)

**Solução:**

```bash
# Fazer login novamente
aws sso login --profile k8s-platform-prod

# Verificar status
aws sts get-caller-identity --profile k8s-platform-prod
```

---

### Problema: "SSL certificate verify failed"

**Causa:** Certificado SSL inválido ou proxy corporativo

**Solução:**

```bash
# Opção 1: Desabilitar verificação SSL (NÃO recomendado para produção)
export AWS_CA_BUNDLE=""

# Opção 2: Configurar certificado corporativo
export AWS_CA_BUNDLE=/caminho/para/certificado-corporativo.pem

# Opção 3: Configurar proxy
export HTTP_PROXY=http://proxy.empresa.com:8080
export HTTPS_PROXY=http://proxy.empresa.com:8080
export NO_PROXY=169.254.169.254  # Metadata service
```

---

### Problema: "Rate exceeded" (ThrottlingException)

**Causa:** Muitas requisições à API AWS

**Solução:**

```bash
# Usar paginação
aws s3api list-objects-v2 --bucket meu-bucket --max-items 100

# Adicionar delays entre comandos
for i in {1..10}; do
  aws ec2 describe-instances --region us-east-1
  sleep 2
done

# Usar AWS CLI V2 com rate limiting automático
aws s3 sync . s3://meu-bucket --cli-read-timeout 30
```

---

## 8. Comandos Úteis

### Gerenciamento de Perfis

```bash
# Listar perfis configurados
aws configure list-profiles

# Alternar entre perfis
export AWS_PROFILE=k8s-platform-prod

# Verificar perfil ativo
echo $AWS_PROFILE

# Remover perfil
aws configure --profile nome-perfil
# Edite ~/.aws/credentials e ~/.aws/config manualmente
```

### Comandos Essenciais

```bash
# S3
aws s3 ls                           # Listar buckets
aws s3 ls s3://meu-bucket           # Listar objetos
aws s3 cp arquivo.txt s3://bucket/  # Upload
aws s3 sync . s3://bucket/          # Sincronizar diretório

# EC2
aws ec2 describe-instances          # Listar instâncias
aws ec2 start-instances --instance-ids i-1234567890abcdef0
aws ec2 stop-instances --instance-ids i-1234567890abcdef0

# EKS
aws eks list-clusters               # Listar clusters
aws eks describe-cluster --name meu-cluster
aws eks update-kubeconfig --name meu-cluster --region us-east-1

# IAM
aws iam list-users                  # Listar usuários
aws iam get-user --user-name joao   # Detalhes do usuário
aws iam create-access-key --user-name joao

# RDS
aws rds describe-db-instances       # Listar instâncias RDS
aws rds start-db-instance --db-instance-identifier mydb
aws rds stop-db-instance --db-instance-identifier mydb

# Lambda
aws lambda list-functions           # Listar funções Lambda
aws lambda invoke --function-name myFunction output.txt

# CloudWatch Logs
aws logs describe-log-groups        # Listar log groups
aws logs tail /aws/eks/cluster-prod --follow
```

### Formatação de Output

```bash
# JSON (padrão)
aws ec2 describe-instances --output json

# Tabela
aws ec2 describe-instances --output table

# Texto puro
aws ec2 describe-instances --output text

# YAML
aws ec2 describe-instances --output yaml

# JMESPath query (filtrar resultados)
aws ec2 describe-instances \
    --query 'Reservations[*].Instances[*].[InstanceId,State.Name,InstanceType]' \
    --output table
```

### Configuração Avançada

```bash
# Definir timeout de comandos
aws configure set cli_read_timeout 30
aws configure set cli_connect_timeout 10

# Habilitar paginação automática
aws configure set cli_pager ''  # Desabilitar pager
# Ou
export AWS_PAGER=""

# Configurar região padrão
aws configure set region us-east-1

# Configurar output format
aws configure set output json
```

---

## Próximos Passos

Agora que você tem o AWS CLI V2 configurado, você pode:

1. **Explorar a documentação oficial:**
   - [AWS CLI Command Reference](https://awscli.amazonaws.com/v2/documentation/api/latest/index.html)

2. **Configurar kubectl para EKS:**
   ```bash
   aws eks update-kubeconfig --region us-east-1 --name k8s-platform-prod
   ```

3. **Automatizar com scripts:**
   ```bash
   #!/bin/bash
   # backup-s3.sh
   aws s3 sync /dados s3://backup-bucket/ --delete
   ```

4. **Integrar com CI/CD:**
   - GitHub Actions: `aws-actions/configure-aws-credentials@v4`
   - GitLab CI: Variáveis `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`

5. **Explorar AWS SDKs para programação:**
   - Python: Boto3
   - Node.js: AWS SDK for JavaScript
   - Go: AWS SDK for Go

---

## Referências

- [AWS CLI V2 Documentation](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-welcome.html)
- [AWS CLI V2 Installation Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [AWS SSO Configuration](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html)
- [AWS CLI Command Reference](https://awscli.amazonaws.com/v2/documentation/api/latest/index.html)
- [IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)

---

**Documento gerado em:** 2026-01-22
**Autor:** DevOps Team
**Versão:** 1.0
**Próxima revisão:** Mensal
