#!/bin/bash
# Script de instalação de ferramentas - Versão simplificada
# Execute com: sudo bash scripts/install-tools.sh

set -e

echo "🚀 Instalando ferramentas Kubernetes/AWS..."

# 1. Atualizar sistema
echo "📦 Atualizando pacotes..."
apt update -qq && apt upgrade -y -qq

# 2. Instalar dependências
echo "📦 Instalando dependências..."
apt install -y -qq curl wget unzip git jq vim ca-certificates gnupg lsb-release apt-transport-https software-properties-common bash-completion

# 3. AWS CLI V2
if ! command -v aws &> /dev/null || [[ $(aws --version 2>&1) != aws-cli/2* ]]; then
    echo "☁️  Instalando AWS CLI V2..."
    cd /tmp
    curl -sS "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    ./aws/install --update
    rm -rf aws awscliv2.zip
fi

# 4. Terraform
if ! command -v terraform &> /dev/null; then
    echo "🏗️  Instalando Terraform..."
    wget -qO- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
    apt update -qq
    apt install -y terraform
fi

# 5. Helm
if ! command -v helm &> /dev/null; then
    echo "⎈ Instalando Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# 6. eksctl
if ! command -v eksctl &> /dev/null; then
    echo "🔧 Instalando eksctl..."
    ARCH=amd64
    PLATFORM=$(uname -s)_$ARCH
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp
    mv /tmp/eksctl /usr/local/bin
    rm eksctl_$PLATFORM.tar.gz
fi

# 7. k9s
if ! command -v k9s &> /dev/null; then
    echo "🖥️  Instalando k9s..."
    K9S_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | grep tag_name | cut -d '"' -f 4)
    wget -q "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz" -O /tmp/k9s.tar.gz
    tar -xzf /tmp/k9s.tar.gz -C /tmp
    mv /tmp/k9s /usr/local/bin/
    rm /tmp/k9s.tar.gz
fi

# 8. kubectx/kubens
if ! command -v kubectx &> /dev/null; then
    echo "🔄 Instalando kubectx/kubens..."
    git clone -q https://github.com/ahmetb/kubectx.git /tmp/kubectx 2>/dev/null || true
    mv /tmp/kubectx/kubectx /usr/local/bin/
    mv /tmp/kubectx/kubens /usr/local/bin/
    chmod +x /usr/local/bin/kubectx /usr/local/bin/kubens
    mkdir -p /etc/bash_completion.d
    cp /tmp/kubectx/completion/*.bash /etc/bash_completion.d/ 2>/dev/null || true
    rm -rf /tmp/kubectx
fi

echo ""
echo "✅ Ferramentas instaladas com sucesso!"
echo ""
echo "Versões instaladas:"
echo "  • AWS CLI: $(aws --version 2>&1 | awk '{print $1}')"
echo "  • Terraform: $(terraform version | head -n1 | awk '{print $2}')"
echo "  • Helm: $(helm version --short | grep -oP 'v\d+\.\d+\.\d+')"
echo "  • kubectl: $(kubectl version --client --short 2>/dev/null | grep -oP 'v\d+\.\d+\.\d+' | head -n1)"
echo "  • eksctl: $(eksctl version)"
echo "  • k9s: $(k9s version -s 2>/dev/null | grep Version | awk '{print $2}')"
echo ""
echo "⚠️  Agora execute como usuário normal:"
echo "    bash scripts/configure-aliases.sh"
