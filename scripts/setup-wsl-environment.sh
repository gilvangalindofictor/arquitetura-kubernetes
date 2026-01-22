#!/bin/bash
#
# Script de Provisionamento de Ambiente WSL para Kubernetes/AWS
# Projeto: Arquitetura Multi-Domínio Kubernetes
# Data: 2026-01-22
# Versão: 1.0
#

set -e  # Exit on error

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funções auxiliares
print_header() {
    echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC} $1"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

check_command() {
    if command -v "$1" &> /dev/null; then
        print_success "$1 já instalado ($(command -v $1))"
        return 0
    else
        print_info "$1 não encontrado, instalando..."
        return 1
    fi
}

# Banner
clear
echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════════════╗
║                                                                       ║
║   🚀 Provisionamento de Ambiente WSL - Kubernetes Platform           ║
║                                                                       ║
║   Ferramentas que serão instaladas:                                  ║
║   • AWS CLI V2                                                        ║
║   • Terraform                                                         ║
║   • Helm 3                                                            ║
║   • eksctl                                                            ║
║   • k9s                                                               ║
║   • kubectx/kubens                                                    ║
║   • Aliases e autocompleção avançados                                ║
║                                                                       ║
╚═══════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}\n"

print_warning "Este script requer permissões sudo para algumas instalações."
read -p "Deseja continuar? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_error "Instalação cancelada pelo usuário."
    exit 1
fi

# ============================================================================
# 1. ATUALIZAR SISTEMA E INSTALAR DEPENDÊNCIAS
# ============================================================================
print_header "1/9 Atualizando sistema e instalando dependências básicas"

print_info "Atualizando pacotes do sistema..."
sudo apt update -qq

print_info "Instalando dependências..."
sudo apt install -y -qq \
    curl \
    wget \
    unzip \
    git \
    jq \
    vim \
    ca-certificates \
    gnupg \
    lsb-release \
    apt-transport-https \
    software-properties-common \
    python3-pip \
    bash-completion

print_success "Dependências instaladas com sucesso"

# ============================================================================
# 2. INSTALAR AWS CLI V2
# ============================================================================
print_header "2/9 Instalando AWS CLI V2"

if check_command aws; then
    AWS_VERSION=$(aws --version 2>&1 | awk '{print $1}')
    print_info "Versão atual: $AWS_VERSION"

    if [[ $AWS_VERSION == aws-cli/2* ]]; then
        print_success "AWS CLI V2 já está instalado e atualizado"
    else
        print_warning "AWS CLI V1 detectado, atualizando para V2..."
        pip3 uninstall awscli -y 2>/dev/null || true
    fi
else
    print_info "Baixando AWS CLI V2..."
    cd /tmp
    curl -sS "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"

    print_info "Instalando AWS CLI V2..."
    unzip -q awscliv2.zip
    sudo ./aws/install --update
    rm -rf aws awscliv2.zip

    print_success "AWS CLI V2 instalado: $(aws --version)"
fi

# ============================================================================
# 3. INSTALAR TERRAFORM
# ============================================================================
print_header "3/9 Instalando Terraform"

if check_command terraform; then
    TF_VERSION=$(terraform version -json 2>/dev/null | jq -r '.terraform_version')
    print_info "Versão atual: $TF_VERSION"
else
    print_info "Adicionando repositório HashiCorp..."
    wget -qO- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null

    print_info "Instalando Terraform..."
    sudo apt update -qq
    sudo apt install -y terraform

    print_success "Terraform instalado: $(terraform version | head -n1)"
fi

# ============================================================================
# 4. INSTALAR HELM 3
# ============================================================================
print_header "4/9 Instalando Helm 3"

if check_command helm; then
    HELM_VERSION=$(helm version --short 2>/dev/null)
    print_info "Versão atual: $HELM_VERSION"
else
    print_info "Baixando e instalando Helm 3..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    print_success "Helm instalado: $(helm version --short)"
fi

# ============================================================================
# 5. INSTALAR EKSCTL
# ============================================================================
print_header "5/9 Instalando eksctl"

if check_command eksctl; then
    EKSCTL_VERSION=$(eksctl version)
    print_info "Versão atual: $EKSCTL_VERSION"
else
    print_info "Baixando eksctl..."
    ARCH=amd64
    PLATFORM=$(uname -s)_$ARCH
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"

    print_info "Instalando eksctl..."
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp
    sudo mv /tmp/eksctl /usr/local/bin
    rm eksctl_$PLATFORM.tar.gz

    print_success "eksctl instalado: $(eksctl version)"
fi

# ============================================================================
# 6. INSTALAR K9S
# ============================================================================
print_header "6/9 Instalando k9s"

if check_command k9s; then
    K9S_VERSION=$(k9s version -s 2>/dev/null | grep Version | awk '{print $2}')
    print_info "Versão atual: $K9S_VERSION"
else
    print_info "Baixando k9s..."
    K9S_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | jq -r '.tag_name')
    wget -q "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz" -O /tmp/k9s.tar.gz

    print_info "Instalando k9s..."
    tar -xzf /tmp/k9s.tar.gz -C /tmp
    sudo mv /tmp/k9s /usr/local/bin/
    rm /tmp/k9s.tar.gz

    print_success "k9s instalado: $(k9s version -s | grep Version | awk '{print $2}')"
fi

# ============================================================================
# 7. INSTALAR KUBECTX E KUBENS
# ============================================================================
print_header "7/9 Instalando kubectx e kubens"

if check_command kubectx && check_command kubens; then
    print_success "kubectx e kubens já instalados"
else
    print_info "Clonando repositório kubectx..."
    git clone -q https://github.com/ahmetb/kubectx.git /tmp/kubectx 2>/dev/null || true

    print_info "Instalando kubectx e kubens..."
    sudo mv /tmp/kubectx/kubectx /usr/local/bin/
    sudo mv /tmp/kubectx/kubens /usr/local/bin/
    sudo chmod +x /usr/local/bin/kubectx /usr/local/bin/kubens

    # Instalar autocompleção
    sudo mkdir -p /etc/bash_completion.d
    sudo cp /tmp/kubectx/completion/*.bash /etc/bash_completion.d/ 2>/dev/null || true

    rm -rf /tmp/kubectx

    print_success "kubectx e kubens instalados"
fi

# ============================================================================
# 8. CONFIGURAR KUBECTL (verificar instalação existente)
# ============================================================================
print_header "8/9 Verificando kubectl"

if check_command kubectl; then
    KUBECTL_VERSION=$(kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.gitVersion')
    print_info "kubectl já instalado: $KUBECTL_VERSION"
    print_success "kubectl está pronto para uso"
else
    print_info "Instalando kubectl..."
    KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
    print_success "kubectl instalado: $(kubectl version --client --short)"
fi

# ============================================================================
# 9. CONFIGURAR ALIASES E AUTOCOMPLEÇÃO
# ============================================================================
print_header "9/9 Configurando aliases e autocompleção"

BASHRC="$HOME/.bashrc"
BACKUP_BASHRC="$HOME/.bashrc.backup-$(date +%Y%m%d-%H%M%S)"

# Backup do .bashrc
print_info "Criando backup do .bashrc em $BACKUP_BASHRC"
cp "$BASHRC" "$BACKUP_BASHRC"

# Criar arquivo de aliases customizados
ALIAS_FILE="$HOME/.k8s_aws_aliases"

cat > "$ALIAS_FILE" << 'ALIASES_EOF'
# ============================================================================
# Aliases e Configurações - Kubernetes Platform
# Gerado automaticamente pelo script de provisionamento
# Data: $(date +%Y-%m-%d)
# ============================================================================

# AWS Aliases
alias awswhoami='aws sts get-caller-identity'
alias awslogin='aws sso login'
alias awslogout='aws sso logout'
alias awsregions='aws ec2 describe-regions --output table'
alias awscost='aws ce get-cost-and-usage --time-period Start=$(date -d "1 month ago" +%Y-%m-%d),End=$(date +%Y-%m-%d) --granularity MONTHLY --metrics BlendedCost'

# Kubernetes Aliases
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get services'
alias kgn='kubectl get nodes'
alias kgd='kubectl get deployments'
alias kga='kubectl get all'
alias kgns='kubectl get namespaces'
alias kdp='kubectl describe pod'
alias kds='kubectl describe service'
alias kdn='kubectl describe node'
alias klf='kubectl logs -f'
alias kex='kubectl exec -it'
alias kctx='kubectx'
alias kns='kubens'
alias kwatch='watch -n 2 kubectl get pods'

# Terraform Aliases
alias tf='terraform'
alias tfi='terraform init'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfd='terraform destroy'
alias tfv='terraform validate'
alias tff='terraform fmt'
alias tfo='terraform output'
alias tfs='terraform state list'
alias tfsh='terraform show'

# Helm Aliases
alias h='helm'
alias hls='helm list'
alias hi='helm install'
alias hu='helm upgrade'
alias hd='helm delete'
alias hs='helm search'
alias hh='helm history'

# Git Aliases (úteis para o projeto)
alias gs='git status'
alias ga='git add'
alias gc='git commit -m'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'
alias gd='git diff'

# Docker Aliases (se usar Docker)
alias d='docker'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'
alias drm='docker rm'
alias drmi='docker rmi'
alias dexec='docker exec -it'
alias dlogs='docker logs -f'

# Navegação rápida do projeto
alias cdproj='cd ~/projects/Arquitetura/Kubernetes'
alias cdterraform='cd ~/projects/Arquitetura/Kubernetes/terraform'
alias cddocs='cd ~/projects/Arquitetura/Kubernetes/docs'
alias cdscripts='cd ~/projects/Arquitetura/Kubernetes/scripts'

# Funções úteis
kpf() {
    # Port-forward rápido
    # Uso: kpf <pod-name> <local-port>:<remote-port>
    kubectl port-forward "$1" "$2"
}

klog() {
    # Logs com follow de um pod específico
    # Uso: klog <pod-name>
    kubectl logs -f "$1"
}

kshell() {
    # Shell interativo em um pod
    # Uso: kshell <pod-name>
    kubectl exec -it "$1" -- /bin/bash
}

awsprofile() {
    # Alternar perfil AWS
    # Uso: awsprofile <profile-name>
    export AWS_PROFILE="$1"
    echo "AWS Profile alterado para: $AWS_PROFILE"
    aws sts get-caller-identity
}

# Autocompleção
if [ -f /etc/bash_completion ] && ! shopt -oq posix; then
    . /etc/bash_completion
fi

# kubectl autocompleção
if command -v kubectl &> /dev/null; then
    source <(kubectl completion bash)
    complete -F __start_kubectl k
fi

# terraform autocompleção
if command -v terraform &> /dev/null; then
    complete -C /usr/bin/terraform terraform
    complete -C /usr/bin/terraform tf
fi

# helm autocompleção
if command -v helm &> /dev/null; then
    source <(helm completion bash)
    complete -F __start_helm h
fi

# eksctl autocompleção
if command -v eksctl &> /dev/null; then
    source <(eksctl completion bash)
fi

# aws autocompleção
if command -v aws_completer &> /dev/null; then
    complete -C aws_completer aws
fi

# Prompt customizado (opcional - descomente se quiser)
# export PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

# Variáveis de ambiente úteis
export EDITOR=vim
export KUBE_EDITOR=vim

# AWS CLI pager (desabilitar para outputs mais limpos)
export AWS_PAGER=""

echo "✅ Aliases e funções K8s/AWS carregados!"
ALIASES_EOF

# Adicionar source do arquivo de aliases no .bashrc
if ! grep -q "source $ALIAS_FILE" "$BASHRC"; then
    print_info "Adicionando aliases ao .bashrc..."
    echo "" >> "$BASHRC"
    echo "# Aliases Kubernetes Platform (adicionado pelo script de provisionamento)" >> "$BASHRC"
    echo "if [ -f $ALIAS_FILE ]; then" >> "$BASHRC"
    echo "    source $ALIAS_FILE" >> "$BASHRC"
    echo "fi" >> "$BASHRC"
    print_success "Aliases adicionados ao .bashrc"
else
    print_info "Aliases já configurados no .bashrc"
fi

print_success "Aliases e autocompleção configurados em: $ALIAS_FILE"

# ============================================================================
# RESUMO FINAL
# ============================================================================
print_header "✅ PROVISIONAMENTO CONCLUÍDO COM SUCESSO!"

echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════════════╗
║                                                                       ║
║   🎉 Ambiente WSL provisionado com sucesso!                          ║
║                                                                       ║
╚═══════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}\n"

print_info "Ferramentas instaladas:"
echo "  • AWS CLI V2:     $(aws --version 2>&1 | awk '{print $1}')"
echo "  • kubectl:        $(kubectl version --client --short 2>/dev/null | grep -oP 'v\d+\.\d+\.\d+' | head -n1)"
echo "  • Terraform:      $(terraform version | head -n1 | awk '{print $2}')"
echo "  • Helm:           $(helm version --short | grep -oP 'v\d+\.\d+\.\d+')"
echo "  • eksctl:         $(eksctl version)"
echo "  • k9s:            $(k9s version -s 2>/dev/null | grep Version | awk '{print $2}')"
echo "  • kubectx/kubens: instalados"

echo -e "\n${YELLOW}⚠️  PRÓXIMOS PASSOS:${NC}\n"

echo "1. Recarregar o shell para ativar aliases:"
echo -e "   ${BLUE}source ~/.bashrc${NC}\n"

echo "2. Configurar autenticação AWS SSO:"
echo -e "   ${BLUE}aws configure sso${NC}"
echo "   - SSO start URL: (forneça o URL da sua organização)"
echo "   - SSO region: us-east-1"
echo "   - Profile name: k8s-platform-prod"
echo ""

echo "3. Fazer login no AWS SSO:"
echo -e "   ${BLUE}aws sso login --profile k8s-platform-prod${NC}\n"

echo "4. Configurar kubectl para acessar o cluster EKS:"
echo -e "   ${BLUE}aws eks update-kubeconfig --region us-east-1 --name k8s-platform-prod${NC}\n"

echo "5. Testar conectividade:"
echo -e "   ${BLUE}aws sts get-caller-identity${NC}"
echo -e "   ${BLUE}kubectl get nodes${NC}\n"

echo -e "${GREEN}📚 Aliases disponíveis:${NC}"
echo "  • awswhoami, awslogin, awslogout"
echo "  • k (kubectl), kgp, kgs, kgn, kga"
echo "  • tf (terraform), tfi, tfp, tfa"
echo "  • h (helm), hls, hi, hu"
echo "  • kctx (kubectx), kns (kubens)"
echo ""
echo -e "Para ver todos os aliases: ${BLUE}cat ~/.k8s_aws_aliases${NC}\n"

print_success "Ambiente pronto para uso! 🚀"
print_info "Backup do .bashrc original salvo em: $BACKUP_BASHRC"

echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════════════${NC}\n"
