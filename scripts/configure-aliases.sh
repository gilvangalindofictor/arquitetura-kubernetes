#!/bin/bash
# Configurar aliases e autocompleção

BASHRC="$HOME/.bashrc"
BACKUP_BASHRC="$HOME/.bashrc.backup-$(date +%Y%m%d-%H%M%S)"
ALIAS_FILE="$HOME/.k8s_aws_aliases"

echo "⚙️  Configurando aliases e autocompleção..."

# Backup do .bashrc
echo "📝 Criando backup do .bashrc em $BACKUP_BASHRC"
cp "$BASHRC" "$BACKUP_BASHRC"

# Criar arquivo de aliases
cat > "$ALIAS_FILE" << 'EOF'
# ============================================================================
# Aliases e Configurações - Kubernetes Platform
# Gerado automaticamente - $(date +%Y-%m-%d)
# ============================================================================

# AWS Aliases
alias awswhoami='aws sts get-caller-identity'
alias awslogin='aws sso login'
alias awslogout='aws sso logout'
alias awsregions='aws ec2 describe-regions --output table'

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

# Helm Aliases
alias h='helm'
alias hls='helm list'
alias hi='helm install'
alias hu='helm upgrade'
alias hd='helm delete'

# Git Aliases
alias gs='git status'
alias ga='git add'
alias gc='git commit -m'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'
alias gd='git diff'

# Navegação rápida
alias cdproj='cd ~/projects/Arquitetura/Kubernetes'
alias cdterraform='cd ~/projects/Arquitetura/Kubernetes/terraform'
alias cddocs='cd ~/projects/Arquitetura/Kubernetes/docs'
alias cdscripts='cd ~/projects/Arquitetura/Kubernetes/scripts'

# Funções úteis
kpf() {
    kubectl port-forward "$1" "$2"
}

klog() {
    kubectl logs -f "$1"
}

kshell() {
    kubectl exec -it "$1" -- /bin/bash
}

awsprofile() {
    export AWS_PROFILE="$1"
    echo "AWS Profile alterado para: $AWS_PROFILE"
    aws sts get-caller-identity
}

# Autocompleção kubectl
if command -v kubectl &> /dev/null; then
    source <(kubectl completion bash)
    complete -F __start_kubectl k
fi

# Autocompleção terraform
if command -v terraform &> /dev/null; then
    complete -C /usr/bin/terraform terraform
    complete -C /usr/bin/terraform tf
fi

# Autocompleção helm
if command -v helm &> /dev/null; then
    source <(helm completion bash)
    complete -F __start_helm h
fi

# Autocompleção eksctl
if command -v eksctl &> /dev/null; then
    source <(eksctl completion bash)
fi

# Autocompleção aws
if command -v aws_completer &> /dev/null; then
    complete -C aws_completer aws
fi

# Variáveis de ambiente
export EDITOR=vim
export KUBE_EDITOR=vim
export AWS_PAGER=""

echo "✅ Aliases K8s/AWS carregados!"
EOF

# Adicionar source ao .bashrc
if ! grep -q "source $ALIAS_FILE" "$BASHRC"; then
    echo "" >> "$BASHRC"
    echo "# Aliases Kubernetes Platform" >> "$BASHRC"
    echo "if [ -f $ALIAS_FILE ]; then" >> "$BASHRC"
    echo "    source $ALIAS_FILE" >> "$BASHRC"
    echo "fi" >> "$BASHRC"
    echo "✅ Aliases adicionados ao .bashrc"
else
    echo "ℹ️  Aliases já configurados no .bashrc"
fi

echo ""
echo "✅ Configuração concluída!"
echo ""
echo "Para ativar agora, execute:"
echo "    source ~/.bashrc"
