# Configuração VS Code - Desenvolvimento Local

## Extensões Recomendadas

### Essenciais para Observabilidade

```json
{
  "recommendations": [
    // Docker & Containers
    "ms-azuretools.vscode-docker",
    "ms-vscode-remote.remote-containers",
    
    // YAML & Config Files
    "redhat.vscode-yaml",
    "tamasfe.even-better-toml",
    
    // Prometheus & Grafana
    "joaompinto.vscode-graphviz",
    "wholroyd.jinja",
    
    // Logs & Observability
    "emilast.logfilehighlighter",
    
    // Git & Version Control
    "eamodio.gitlens",
    
    // Markdown
    "yzhang.markdown-all-in-one",
    "bierner.markdown-mermaid",
    
    // Python (para apps exemplo)
    "ms-python.python",
    "ms-python.vscode-pylance",
    
    // Infrastructure as Code
    "hashicorp.terraform",
    "ms-kubernetes-tools.vscode-kubernetes-tools"
  ]
}
```

## Configurações do Workspace

### `.vscode/settings.json`

```json
{
  // Editor
  "editor.formatOnSave": true,
  "editor.rulers": [80, 120],
  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true,
  
  // YAML
  "yaml.schemas": {
    "https://json.schemastore.org/prometheus.json": [
      "**/prometheus*.yml",
      "**/prometheus*.yaml"
    ],
    "https://json.schemastore.org/docker-compose.json": [
      "**/docker-compose*.yml"
    ]
  },
  "yaml.format.enable": true,
  "yaml.validate": true,
  
  // Docker
  "docker.containers.sortBy": "Status",
  "docker.showStartPage": false,
  
  // Files to exclude from search
  "search.exclude": {
    "**/node_modules": true,
    "**/volumes": true,
    "**/.terraform": true,
    "**/vendor": true
  },
  
  // Files to exclude from file tree
  "files.exclude": {
    "**/.git": true,
    "**/.DS_Store": true,
    "**/volumes": true
  },
  
  // Terminal
  "terminal.integrated.defaultProfile.linux": "bash",
  "terminal.integrated.fontSize": 13,
  
  // Python (for example apps)
  "python.linting.enabled": true,
  "python.linting.pylintEnabled": true,
  "python.formatting.provider": "black",
  
  // Terraform
  "terraform.experimentalFeatures.validateOnSave": true,
  "terraform.languageServer.enable": true
}
```

## Tarefas do VS Code (Tasks)

### `.vscode/tasks.json`

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Start Observability Stack",
      "type": "shell",
      "command": "docker-compose up -d",
      "options": {
        "cwd": "${workspaceFolder}/local-dev"
      },
      "group": {
        "kind": "build",
        "isDefault": true
      },
      "presentation": {
        "reveal": "always",
        "panel": "new"
      },
      "problemMatcher": []
    },
    {
      "label": "Stop Observability Stack",
      "type": "shell",
      "command": "docker-compose down",
      "options": {
        "cwd": "${workspaceFolder}/local-dev"
      },
      "presentation": {
        "reveal": "always",
        "panel": "new"
      },
      "problemMatcher": []
    },
    {
      "label": "Restart Observability Stack",
      "type": "shell",
      "command": "docker-compose restart",
      "options": {
        "cwd": "${workspaceFolder}/local-dev"
      },
      "presentation": {
        "reveal": "always",
        "panel": "new"
      },
      "problemMatcher": []
    },
    {
      "label": "View Logs - All Services",
      "type": "shell",
      "command": "docker-compose logs -f",
      "options": {
        "cwd": "${workspaceFolder}/local-dev"
      },
      "presentation": {
        "reveal": "always",
        "panel": "dedicated"
      },
      "problemMatcher": [],
      "isBackground": true
    },
    {
      "label": "View Logs - Prometheus",
      "type": "shell",
      "command": "docker-compose logs -f prometheus",
      "options": {
        "cwd": "${workspaceFolder}/local-dev"
      },
      "presentation": {
        "reveal": "always",
        "panel": "dedicated"
      },
      "problemMatcher": [],
      "isBackground": true
    },
    {
      "label": "View Logs - Grafana",
      "type": "shell",
      "command": "docker-compose logs -f grafana",
      "options": {
        "cwd": "${workspaceFolder}/local-dev"
      },
      "presentation": {
        "reveal": "always",
        "panel": "dedicated"
      },
      "problemMatcher": [],
      "isBackground": true
    },
    {
      "label": "Check Stack Health",
      "type": "shell",
      "command": "docker-compose ps && docker stats --no-stream",
      "options": {
        "cwd": "${workspaceFolder}/local-dev"
      },
      "presentation": {
        "reveal": "always",
        "panel": "new"
      },
      "problemMatcher": []
    },
    {
      "label": "Reset Environment (Clean Volumes)",
      "type": "shell",
      "command": "docker-compose down -v && docker system prune -f",
      "options": {
        "cwd": "${workspaceFolder}/local-dev"
      },
      "presentation": {
        "reveal": "always",
        "panel": "new"
      },
      "problemMatcher": []
    },
    {
      "label": "Run Example App",
      "type": "shell",
      "command": "docker-compose --profile with-app up -d",
      "options": {
        "cwd": "${workspaceFolder}/local-dev"
      },
      "presentation": {
        "reveal": "always",
        "panel": "new"
      },
      "problemMatcher": []
    },
    {
      "label": "Run Load Test",
      "type": "shell",
      "command": "docker-compose --profile load-test up",
      "options": {
        "cwd": "${workspaceFolder}/local-dev"
      },
      "presentation": {
        "reveal": "always",
        "panel": "new"
      },
      "problemMatcher": []
    }
  ]
}
```

## Snippets Úteis

### `.vscode/prometheus.code-snippets`

```json
{
  "Prometheus Query": {
    "prefix": "promql",
    "body": [
      "${1:metric_name}{${2:label}=\"${3:value}\"}[${4:5m}]"
    ],
    "description": "Prometheus query template"
  },
  "Recording Rule": {
    "prefix": "prom-record",
    "body": [
      "- record: ${1:rule_name}",
      "  expr: ${2:expression}",
      "  labels:",
      "    ${3:label}: ${4:value}"
    ],
    "description": "Prometheus recording rule"
  },
  "Alert Rule": {
    "prefix": "prom-alert",
    "body": [
      "- alert: ${1:AlertName}",
      "  expr: ${2:expression}",
      "  for: ${3:5m}",
      "  labels:",
      "    severity: ${4|critical,warning,info|}",
      "  annotations:",
      "    summary: \"${5:Alert summary}\"",
      "    description: \"${6:Alert description}\""
    ],
    "description": "Prometheus alert rule"
  }
}
```

### `.vscode/docker-compose.code-snippets`

```json
{
  "Docker Compose Service": {
    "prefix": "dc-service",
    "body": [
      "${1:service_name}:",
      "  image: ${2:image:tag}",
      "  container_name: ${3:container_name}",
      "  ports:",
      "    - \"${4:host_port}:${5:container_port}\"",
      "  environment:",
      "    - ${6:ENV_VAR}=${7:value}",
      "  networks:",
      "    - observability",
      "  depends_on:",
      "    - ${8:dependency}",
      "  healthcheck:",
      "    test: [\"CMD\", \"${9:command}\"]",
      "    interval: 30s",
      "    timeout: 10s",
      "    retries: 3"
    ],
    "description": "Docker Compose service template"
  }
}
```

## Atalhos de Teclado Customizados

### `.vscode/keybindings.json`

```json
[
  {
    "key": "ctrl+shift+d s",
    "command": "workbench.action.tasks.runTask",
    "args": "Start Observability Stack"
  },
  {
    "key": "ctrl+shift+d q",
    "command": "workbench.action.tasks.runTask",
    "args": "Stop Observability Stack"
  },
  {
    "key": "ctrl+shift+d l",
    "command": "workbench.action.tasks.runTask",
    "args": "View Logs - All Services"
  },
  {
    "key": "ctrl+shift+d h",
    "command": "workbench.action.tasks.runTask",
    "args": "Check Stack Health"
  }
]
```

## Dicas de Produtividade

### 1. Terminal Integrado Multi-Split

Configure splits para monitorar múltiplos logs simultaneamente:

```bash
# Terminal 1: Logs gerais
docker-compose logs -f

# Terminal 2: Métricas de recursos
watch -n 2 'docker stats --no-stream'

# Terminal 3: Health checks
watch -n 5 'docker-compose ps'
```

### 2. Bookmarks do Browser

Salve estes bookmarks para acesso rápido:

- [Grafana](http://localhost:3000)
- [Prometheus](http://localhost:9090)
- [Prometheus Targets](http://localhost:9090/targets)
- [Alertmanager](http://localhost:9093)
- [MinIO Console](http://localhost:9001)

### 3. Docker Extension Features

Use a extensão Docker do VS Code para:

- ✅ Ver logs de containers em real-time
- ✅ Inspecionar variáveis de ambiente
- ✅ Executar comandos dentro dos containers
- ✅ Monitorar uso de recursos
- ✅ Acessar shell dos containers

### 4. Workspace Multi-root

Configure um workspace multi-root para separar:

```json
{
  "folders": [
    {
      "name": "Observability - Main",
      "path": "."
    },
    {
      "name": "Local Dev",
      "path": "./local-dev"
    },
    {
      "name": "Infrastructure",
      "path": "./infra"
    },
    {
      "name": "Documentation",
      "path": "./docs"
    }
  ],
  "settings": {
    // Workspace-wide settings
  }
}
```

## Troubleshooting no VS Code

### Problema: Container não inicia

1. Abra o painel Docker (Ctrl+Shift+D)
2. Clique com botão direito no container
3. Selecione "View Logs"
4. Analise os erros

### Problema: Porta já em uso

```bash
# Terminal do VS Code
sudo netstat -tulpn | grep :3000
# Ou
sudo lsof -i :3000
```

### Problema: Volumes com permissões incorretas

```bash
# Terminal do VS Code
cd local-dev
sudo chown -R $USER:$USER volumes/
```

## Próximos Passos

1. Instale as extensões recomendadas
2. Copie os arquivos de configuração para `.vscode/`
3. Teste os atalhos de teclado
4. Configure seu terminal integrado
5. Inicie a stack usando Ctrl+Shift+D S

---

**Documento relacionado**: [Workflow de Desenvolvimento](./development-workflow.md)
