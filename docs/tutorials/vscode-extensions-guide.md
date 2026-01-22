# Guia de Extensões VSCode - Kubernetes Platform

**Versão:** 1.0
**Data:** 2026-01-22
**Projeto:** Arquitetura Multi-Domínio Kubernetes
**Autor:** DevOps Team

---

## 📋 Índice

1. [Extensões Essenciais](#extensões-essenciais-obrigatórias)
2. [Extensões de Produtividade](#extensões-de-produtividade)
3. [Extensões de Linguagens](#extensões-de-linguagens)
4. [Extensões de Qualidade](#extensões-de-qualidade)
5. [Extensões Opcionais](#extensões-opcionais)
6. [Configurações Recomendadas](#configurações-recomendadas)
7. [Instalação Automatizada](#instalação-automatizada)

---

## 🎯 Extensões Essenciais (Obrigatórias)

### 1. Remote - WSL
**ID:** `ms-vscode-remote.remote-wsl`
**Publisher:** Microsoft

**Por que é essencial:**
- ✅ Permite abrir projetos diretamente no WSL
- ✅ Terminal integrado roda bash nativamente
- ✅ Extensions funcionam no contexto WSL
- ✅ Zero friction entre Windows e Linux

**Instalação:**
```bash
code --install-extension ms-vscode-remote.remote-wsl
```

**Uso:**
```bash
# Abrir projeto no WSL
cd ~/projects/Arquitetura/Kubernetes
code .

# Verificar que está no WSL (canto inferior esquerdo deve mostrar "WSL: Ubuntu")
```

---

### 2. Kubernetes
**ID:** `ms-kubernetes-tools.vscode-kubernetes-tools`
**Publisher:** Microsoft

**Recursos:**
- ✅ Explorar clusters, pods, services, deployments
- ✅ Visualizar e editar manifestos YAML
- ✅ Aplicar recursos diretamente no cluster
- ✅ Ver logs de pods
- ✅ Port-forward interativo
- ✅ Helm chart support

**Instalação:**
```bash
code --install-extension ms-kubernetes-tools.vscode-kubernetes-tools
```

**Atalhos:**
- `Ctrl+Shift+P` → `Kubernetes: Get` → Ver recursos
- `Ctrl+Shift+P` → `Kubernetes: Logs` → Ver logs de pod
- Clique direito em YAML → `Kubernetes: Apply`

---

### 3. YAML
**ID:** `redhat.vscode-yaml`
**Publisher:** Red Hat

**Recursos:**
- ✅ Syntax highlighting para YAML
- ✅ Validação de schema (Kubernetes, Docker Compose, GitHub Actions)
- ✅ Autocompleção inteligente
- ✅ Detecção de erros em tempo real

**Instalação:**
```bash
code --install-extension redhat.vscode-yaml
```

**Configuração para Kubernetes:**
```json
{
  "yaml.schemas": {
    "kubernetes": "*.yaml"
  }
}
```

---

### 4. Terraform
**ID:** `hashicorp.terraform`
**Publisher:** HashiCorp

**Recursos:**
- ✅ Syntax highlighting para `.tf` files
- ✅ Autocompleção de recursos e providers
- ✅ Validação de sintaxe
- ✅ Formatting automático
- ✅ Integração com Terraform Language Server

**Instalação:**
```bash
code --install-extension hashicorp.terraform
```

**Atalhos:**
- `Ctrl+Shift+I` → Format document
- `F12` → Go to definition

---

### 5. Docker
**ID:** `ms-azuretools.vscode-docker`
**Publisher:** Microsoft

**Recursos:**
- ✅ Gerenciar containers e images
- ✅ Editar Dockerfiles com IntelliSense
- ✅ Build, run, debug containers
- ✅ Docker Compose support
- ✅ Integração com registries (DockerHub, ECR, Harbor)

**Instalação:**
```bash
code --install-extension ms-azuretools.vscode-docker
```

---

### 6. GitLens
**ID:** `eamodio.gitlens`
**Publisher:** GitKraken

**Recursos:**
- ✅ Blame annotations inline
- ✅ Histórico de commits por linha
- ✅ Compare branches/commits
- ✅ Navegação de histórico Git
- ✅ Insights de contribuidores

**Instalação:**
```bash
code --install-extension eamodio.gitlens
```

**Atalhos:**
- `Alt+B` → Toggle blame annotations
- `Ctrl+Shift+G` → Open GitLens

---

## 🚀 Extensões de Produtividade

### 7. Better Comments
**ID:** `aaron-bond.better-comments`

**Recursos:**
- Comentários coloridos por tipo (TODO, FIXME, NOTE, etc.)
- Melhora legibilidade do código

**Instalação:**
```bash
code --install-extension aaron-bond.better-comments
```

**Exemplos:**
```javascript
// ! CRITICAL: This is a critical issue
// ? QUESTION: Should we refactor this?
// TODO: Implement feature X
// * IMPORTANT: Pay attention here
```

---

### 8. Path Intellisense
**ID:** `christian-kohler.path-intellisense`

**Recursos:**
- Autocompleção de caminhos de arquivos
- Suporta paths relativos e absolutos

**Instalação:**
```bash
code --install-extension christian-kohler.path-intellisense
```

---

### 9. Error Lens
**ID:** `usernamehw.errorlens`

**Recursos:**
- Exibe erros inline no código
- Highlights problemas imediatamente
- Melhora identificação de issues

**Instalação:**
```bash
code --install-extension usernamehw.errorlens
```

---

### 10. Indent Rainbow
**ID:** `oderwat.indent-rainbow`

**Recursos:**
- Coloriza indentação
- Útil para YAML/Python
- Detecta problemas de indentação

**Instalação:**
```bash
code --install-extension oderwat.indent-rainbow
```

---

## 💻 Extensões de Linguagens

### 11. Python
**ID:** `ms-python.python`
**Publisher:** Microsoft

**Recursos:**
- ✅ IntelliSense e autocompleção
- ✅ Linting (pylint, flake8)
- ✅ Debugging
- ✅ Testing (pytest, unittest)
- ✅ Jupyter support

**Instalação:**
```bash
code --install-extension ms-python.python
```

---

### 12. Go
**ID:** `golang.go`
**Publisher:** Go Team

**Recursos:**
- ✅ IntelliSense para Go
- ✅ Debugging com delve
- ✅ Testing support
- ✅ Auto-import de packages

**Instalação:**
```bash
code --install-extension golang.go
```

---

### 13. Markdown All in One
**ID:** `yzhang.markdown-all-in-one`

**Recursos:**
- ✅ Preview markdown
- ✅ Atalhos de teclado
- ✅ Table of contents automático
- ✅ Auto-numbering de seções

**Instalação:**
```bash
code --install-extension yzhang.markdown-all-in-one
```

**Atalhos:**
- `Ctrl+Shift+V` → Preview markdown
- `Ctrl+B` → Bold
- `Ctrl+I` → Italic

---

### 14. ShellCheck
**ID:** `timonwong.shellcheck`

**Recursos:**
- ✅ Linting para shell scripts
- ✅ Detecta erros comuns em bash
- ✅ Sugestões de boas práticas

**Instalação:**
```bash
# Instalar shellcheck no sistema
sudo apt install shellcheck -y

# Instalar extensão
code --install-extension timonwong.shellcheck
```

---

## 🔍 Extensões de Qualidade

### 15. SonarLint
**ID:** `sonarsource.sonarlint-vscode`

**Recursos:**
- ✅ Detecção de bugs e vulnerabilidades
- ✅ Code smells
- ✅ Security hotspots
- ✅ Suporte a múltiplas linguagens

**Instalação:**
```bash
code --install-extension sonarsource.sonarlint-vscode
```

---

### 16. EditorConfig
**ID:** `editorconfig.editorconfig`

**Recursos:**
- ✅ Consistência de formatação
- ✅ Configuração compartilhada no projeto
- ✅ Suporta múltiplos editores

**Instalação:**
```bash
code --install-extension editorconfig.editorconfig
```

**Exemplo `.editorconfig`:**
```ini
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true

[*.{yaml,yml}]
indent_style = space
indent_size = 2

[*.{tf,hcl}]
indent_style = space
indent_size = 2

[*.sh]
indent_style = space
indent_size = 2
```

---

### 17. Prettier - Code Formatter
**ID:** `esbenp.prettier-vscode`

**Recursos:**
- ✅ Formatação automática
- ✅ Suporte a YAML, JSON, Markdown, JavaScript, TypeScript
- ✅ Consistência de código

**Instalação:**
```bash
code --install-extension esbenp.prettier-vscode
```

**Configuração:**
```json
{
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "editor.formatOnSave": true
}
```

---

## 🎨 Extensões Opcionais (Recomendadas)

### 18. Peacock
**ID:** `johnpapa.vscode-peacock`

**Recursos:**
- Colorizar workspaces diferentes
- Útil para distinguir ambientes (dev, staging, prod)

**Instalação:**
```bash
code --install-extension johnpapa.vscode-peacock
```

---

### 19. Todo Tree
**ID:** `gruntfuggly.todo-tree`

**Recursos:**
- Visualizar todos os TODOs no projeto
- Navegação rápida
- Customização de tags

**Instalação:**
```bash
code --install-extension gruntfuggly.todo-tree
```

---

### 20. Remote - SSH
**ID:** `ms-vscode-remote.remote-ssh`

**Recursos:**
- Conectar a servidores remotos via SSH
- Editar arquivos remotos diretamente
- Terminal remoto integrado

**Instalação:**
```bash
code --install-extension ms-vscode-remote.remote-ssh
```

---

### 21. REST Client
**ID:** `humao.rest-client`

**Recursos:**
- Testar APIs HTTP diretamente no VSCode
- Salvar requisições em arquivos `.http`
- Substituir Postman/Insomnia

**Instalação:**
```bash
code --install-extension humao.rest-client
```

**Exemplo de uso:**
```http
### Testar API AWS
GET https://sts.us-east-1.amazonaws.com?Action=GetCallerIdentity
Authorization: AWS4-HMAC-SHA256 ...

### Testar Kubernetes API
GET https://kubernetes.default.svc/api/v1/namespaces
Authorization: Bearer {{token}}
```

---

### 22. Thunder Client
**ID:** `rangav.vscode-thunder-client`

**Recursos:**
- Cliente REST/GraphQL integrado
- Interface gráfica como Postman
- Collections e environments

**Instalação:**
```bash
code --install-extension rangav.vscode-thunder-client
```

---

### 23. Helm Intellisense
**ID:** `tim-koehler.helm-intellisense`

**Recursos:**
- Autocompleção para Helm charts
- Validação de templates
- Preview de valores

**Instalação:**
```bash
code --install-extension tim-koehler.helm-intellisense
```

---

### 24. Draw.io Integration
**ID:** `hediet.vscode-drawio`

**Recursos:**
- Criar diagramas diretamente no VSCode
- Formato `.drawio` ou `.drawio.svg`
- Útil para arquitetura e documentação

**Instalação:**
```bash
code --install-extension hediet.vscode-drawio
```

---

### 25. Live Share
**ID:** `ms-vsliveshare.vsliveshare`

**Recursos:**
- Colaboração em tempo real
- Compartilhar sessão de edição
- Pair programming remoto

**Instalação:**
```bash
code --install-extension ms-vsliveshare.vsliveshare
```

---

## ⚙️ Configurações Recomendadas

Adicione ao seu `settings.json` (`.vscode/settings.json` no projeto):

```json
{
  // ==================== GERAL ====================
  "editor.fontSize": 14,
  "editor.fontFamily": "'JetBrains Mono', 'Fira Code', Consolas, monospace",
  "editor.fontLigatures": true,
  "editor.tabSize": 2,
  "editor.insertSpaces": true,
  "editor.detectIndentation": true,
  "editor.formatOnSave": true,
  "editor.rulers": [80, 120],
  "editor.minimap.enabled": true,
  "editor.bracketPairColorization.enabled": true,
  "editor.guides.bracketPairs": true,
  "files.eol": "\n",
  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true,

  // ==================== GIT ====================
  "git.autofetch": true,
  "git.confirmSync": false,
  "git.enableSmartCommit": true,
  "gitlens.codeLens.enabled": true,
  "gitlens.currentLine.enabled": true,

  // ==================== KUBERNETES ====================
  "vs-kubernetes": {
    "vs-kubernetes.helm-path": "/usr/local/bin/helm",
    "vs-kubernetes.kubectl-path": "/usr/local/bin/kubectl"
  },
  "[yaml]": {
    "editor.defaultFormatter": "redhat.vscode-yaml",
    "editor.formatOnSave": true,
    "editor.autoIndent": "advanced"
  },

  // ==================== TERRAFORM ====================
  "terraform.languageServer.enable": true,
  "terraform.experimentalFeatures.prefillRequiredFields": true,
  "[terraform]": {
    "editor.defaultFormatter": "hashicorp.terraform",
    "editor.formatOnSave": true
  },
  "[terraform-vars]": {
    "editor.defaultFormatter": "hashicorp.terraform",
    "editor.formatOnSave": true
  },

  // ==================== SHELL ====================
  "[shellscript]": {
    "editor.defaultFormatter": "foxundermoon.shell-format",
    "files.eol": "\n"
  },
  "shellcheck.enable": true,
  "shellcheck.run": "onSave",

  // ==================== PYTHON ====================
  "python.linting.enabled": true,
  "python.linting.pylintEnabled": true,
  "python.formatting.provider": "black",
  "[python]": {
    "editor.defaultFormatter": "ms-python.python",
    "editor.formatOnSave": true
  },

  // ==================== MARKDOWN ====================
  "[markdown]": {
    "editor.defaultFormatter": "yzhang.markdown-all-in-one",
    "editor.wordWrap": "on",
    "editor.quickSuggestions": {
      "comments": "on",
      "strings": "on",
      "other": "on"
    }
  },

  // ==================== JSON ====================
  "[json]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode",
    "editor.formatOnSave": true
  },
  "[jsonc]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode",
    "editor.formatOnSave": true
  },

  // ==================== DOCKER ====================
  "docker.languageserver.formatter.ignoreMultilineInstructions": true,

  // ==================== TERMINAL ====================
  "terminal.integrated.defaultProfile.linux": "bash",
  "terminal.integrated.fontSize": 13,
  "terminal.integrated.scrollback": 10000,
  "terminal.integrated.shell.linux": "/bin/bash",

  // ==================== WORKBENCH ====================
  "workbench.colorTheme": "Default Dark+",
  "workbench.iconTheme": "material-icon-theme",
  "workbench.startupEditor": "none",
  "workbench.editor.enablePreview": false,

  // ==================== EXTENSÕES ====================
  "errorLens.enabledDiagnosticLevels": [
    "error",
    "warning"
  ],
  "todo-tree.general.tags": [
    "TODO",
    "FIXME",
    "BUG",
    "HACK",
    "XXX",
    "NOTE"
  ],
  "better-comments.tags": [
    {
      "tag": "!",
      "color": "#FF2D00",
      "strikethrough": false,
      "underline": false,
      "backgroundColor": "transparent",
      "bold": false,
      "italic": false
    },
    {
      "tag": "?",
      "color": "#3498DB",
      "strikethrough": false,
      "underline": false,
      "backgroundColor": "transparent",
      "bold": false,
      "italic": false
    },
    {
      "tag": "TODO",
      "color": "#FF8C00",
      "strikethrough": false,
      "underline": false,
      "backgroundColor": "transparent",
      "bold": false,
      "italic": false
    },
    {
      "tag": "*",
      "color": "#98C379",
      "strikethrough": false,
      "underline": false,
      "backgroundColor": "transparent",
      "bold": false,
      "italic": false
    }
  ]
}
```

---

## 🚀 Instalação Automatizada

### Script de Instalação

Crie um script para instalar todas as extensões de uma vez:

```bash
#!/bin/bash
# install-vscode-extensions.sh

echo "🚀 Instalando extensões VSCode para Kubernetes Platform..."

# Extensões Essenciais
code --install-extension ms-vscode-remote.remote-wsl
code --install-extension ms-kubernetes-tools.vscode-kubernetes-tools
code --install-extension redhat.vscode-yaml
code --install-extension hashicorp.terraform
code --install-extension ms-azuretools.vscode-docker
code --install-extension eamodio.gitlens

# Produtividade
code --install-extension aaron-bond.better-comments
code --install-extension christian-kohler.path-intellisense
code --install-extension usernamehw.errorlens
code --install-extension oderwat.indent-rainbow

# Linguagens
code --install-extension ms-python.python
code --install-extension golang.go
code --install-extension yzhang.markdown-all-in-one
code --install-extension timonwong.shellcheck

# Qualidade
code --install-extension sonarsource.sonarlint-vscode
code --install-extension editorconfig.editorconfig
code --install-extension esbenp.prettier-vscode

# Opcionais
code --install-extension johnpapa.vscode-peacock
code --install-extension gruntfuggly.todo-tree
code --install-extension humao.rest-client
code --install-extension tim-koehler.helm-intellisense
code --install-extension hediet.vscode-drawio

echo "✅ Instalação concluída!"
echo "🔄 Recarregue o VSCode para ativar todas as extensões"
```

**Uso:**
```bash
chmod +x scripts/install-vscode-extensions.sh
bash scripts/install-vscode-extensions.sh
```

---

### Via extensions.json

Ou crie `.vscode/extensions.json` no projeto:

```json
{
  "recommendations": [
    "ms-vscode-remote.remote-wsl",
    "ms-kubernetes-tools.vscode-kubernetes-tools",
    "redhat.vscode-yaml",
    "hashicorp.terraform",
    "ms-azuretools.vscode-docker",
    "eamodio.gitlens",
    "aaron-bond.better-comments",
    "christian-kohler.path-intellisense",
    "usernamehw.errorlens",
    "oderwat.indent-rainbow",
    "ms-python.python",
    "golang.go",
    "yzhang.markdown-all-in-one",
    "timonwong.shellcheck",
    "sonarsource.sonarlint-vscode",
    "editorconfig.editorconfig",
    "esbenp.prettier-vscode",
    "johnpapa.vscode-peacock",
    "gruntfuggly.todo-tree",
    "humao.rest-client",
    "tim-koehler.helm-intellisense",
    "hediet.vscode-drawio"
  ]
}
```

O VSCode sugerirá automaticamente instalar essas extensões ao abrir o projeto.

---

## 🎨 Temas Recomendados (Opcional)

### Material Icon Theme
**ID:** `pkief.material-icon-theme`

Ícones modernos para arquivos e pastas.

```bash
code --install-extension pkief.material-icon-theme
```

### One Dark Pro
**ID:** `zhuangtongfa.material-theme`

Tema escuro popular e agradável aos olhos.

```bash
code --install-extension zhuangtongfa.material-theme
```

### Dracula Official
**ID:** `dracula-theme.theme-dracula`

Tema escuro clássico.

```bash
code --install-extension dracula-theme.theme-dracula
```

---

## 📚 Recursos Adicionais

### Atalhos Úteis do VSCode

```
Ctrl+Shift+P        Comando palette
Ctrl+P              Buscar arquivos
Ctrl+Shift+F        Buscar no projeto
Ctrl+`              Toggle terminal
Ctrl+B              Toggle sidebar
Ctrl+Shift+E        Explorer
Ctrl+Shift+G        Source Control
F12                 Go to definition
Alt+F12             Peek definition
Ctrl+Shift+O        Go to symbol
Ctrl+T              Go to symbol in workspace
Ctrl+K Ctrl+S       Keyboard shortcuts
```

### Snippets Customizados

Crie `.vscode/kubernetes.code-snippets`:

```json
{
  "Kubernetes Deployment": {
    "prefix": "k8s-deployment",
    "body": [
      "apiVersion: apps/v1",
      "kind: Deployment",
      "metadata:",
      "  name: ${1:app-name}",
      "  namespace: ${2:default}",
      "spec:",
      "  replicas: ${3:3}",
      "  selector:",
      "    matchLabels:",
      "      app: ${1:app-name}",
      "  template:",
      "    metadata:",
      "      labels:",
      "        app: ${1:app-name}",
      "    spec:",
      "      containers:",
      "      - name: ${1:app-name}",
      "        image: ${4:nginx:latest}",
      "        ports:",
      "        - containerPort: ${5:80}"
    ]
  }
}
```

---

## 🔍 Verificação

Para verificar extensões instaladas:

```bash
# Listar todas as extensões instaladas
code --list-extensions

# Verificar se extensão específica está instalada
code --list-extensions | grep ms-kubernetes-tools
```

---

## 🐛 Troubleshooting

### Extensões não funcionam no WSL

**Problema:** Extensões instaladas no Windows não aparecem no WSL.

**Solução:**
1. Abra o VSCode dentro do WSL: `code .`
2. Instale as extensões novamente (elas precisam estar instaladas no WSL)
3. Ou use o comando `Install in WSL` na aba de extensões

### Performance lenta

**Solução:**
```json
{
  "files.watcherExclude": {
    "**/.git/objects/**": true,
    "**/node_modules/**": true,
    "**/terraform/.terraform/**": true
  }
}
```

### ShellCheck não funciona

**Solução:**
```bash
# Instalar shellcheck no WSL
sudo apt install shellcheck -y

# Verificar instalação
shellcheck --version
```

---

## 📝 Checklist de Extensões

- [ ] Remote - WSL (OBRIGATÓRIO)
- [ ] Kubernetes (OBRIGATÓRIO)
- [ ] YAML (OBRIGATÓRIO)
- [ ] Terraform (OBRIGATÓRIO)
- [ ] Docker (OBRIGATÓRIO)
- [ ] GitLens (OBRIGATÓRIO)
- [ ] Better Comments
- [ ] Path Intellisense
- [ ] Error Lens
- [ ] Indent Rainbow
- [ ] Python
- [ ] Markdown All in One
- [ ] ShellCheck
- [ ] SonarLint
- [ ] EditorConfig
- [ ] Prettier
- [ ] Helm Intellisense
- [ ] REST Client
- [ ] Todo Tree

---

**Documento gerado em:** 2026-01-22
**Autor:** DevOps Team
**Versão:** 1.0
**Próxima revisão:** Mensal

---

## 🎉 Conclusão

Com essas extensões configuradas, você terá:
- ✅ Ambiente completo para Kubernetes
- ✅ Suporte a Terraform/IaC
- ✅ Linting e formatação automática
- ✅ Produtividade maximizada
- ✅ Integração perfeita com WSL

**Próximo passo:** Instale as extensões e configure o VSCode seguindo este guia!
