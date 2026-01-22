#!/bin/bash
# Script de Instalação de Extensões VSCode
# Projeto: Kubernetes Platform
# Data: 2026-01-22

echo "🚀 Instalando extensões VSCode para Kubernetes Platform..."
echo ""

# Função para instalar e verificar
install_extension() {
    local ext_id=$1
    local ext_name=$2

    echo "📦 Instalando: $ext_name"
    code --install-extension "$ext_id" > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo "   ✅ $ext_name instalado"
    else
        echo "   ⚠️  Erro ao instalar $ext_name"
    fi
}

echo "═══════════════════════════════════════════════════════════"
echo "EXTENSÕES ESSENCIAIS"
echo "═══════════════════════════════════════════════════════════"

install_extension "ms-vscode-remote.remote-wsl" "Remote - WSL"
install_extension "ms-kubernetes-tools.vscode-kubernetes-tools" "Kubernetes"
install_extension "redhat.vscode-yaml" "YAML"
install_extension "hashicorp.terraform" "Terraform"
install_extension "ms-azuretools.vscode-docker" "Docker"
install_extension "eamodio.gitlens" "GitLens"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "PRODUTIVIDADE"
echo "═══════════════════════════════════════════════════════════"

install_extension "aaron-bond.better-comments" "Better Comments"
install_extension "christian-kohler.path-intellisense" "Path Intellisense"
install_extension "usernamehw.errorlens" "Error Lens"
install_extension "oderwat.indent-rainbow" "Indent Rainbow"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "LINGUAGENS"
echo "═══════════════════════════════════════════════════════════"

install_extension "ms-python.python" "Python"
install_extension "golang.go" "Go"
install_extension "yzhang.markdown-all-in-one" "Markdown All in One"
install_extension "timonwong.shellcheck" "ShellCheck"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "QUALIDADE DE CÓDIGO"
echo "═══════════════════════════════════════════════════════════"

install_extension "sonarsource.sonarlint-vscode" "SonarLint"
install_extension "editorconfig.editorconfig" "EditorConfig"
install_extension "esbenp.prettier-vscode" "Prettier"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "EXTENSÕES OPCIONAIS"
echo "═══════════════════════════════════════════════════════════"

install_extension "johnpapa.vscode-peacock" "Peacock"
install_extension "gruntfuggly.todo-tree" "Todo Tree"
install_extension "humao.rest-client" "REST Client"
install_extension "tim-koehler.helm-intellisense" "Helm Intellisense"
install_extension "hediet.vscode-drawio" "Draw.io Integration"
install_extension "pkief.material-icon-theme" "Material Icon Theme"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "✅ INSTALAÇÃO CONCLUÍDA!"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "📋 Extensões instaladas:"
code --list-extensions | wc -l
echo ""
echo "⚠️  IMPORTANTE:"
echo "   1. Recarregue o VSCode para ativar todas as extensões"
echo "   2. Configure o settings.json conforme documentação"
echo "   3. Veja: docs/tutorials/vscode-extensions-guide.md"
echo ""
