# Índice de Documentação - Desenvolvimento Local

Documentação completa para desenvolvimento local da plataforma de observabilidade.

## 📚 Documentos Principais

### 1. [README - Visão Geral](./README.md)
Introdução ao ambiente de desenvolvimento local, objetivos e estrutura.

**Leia primeiro**: Conceitos básicos, requisitos de hardware, comparação com AWS.

### 2. [Estimativa de Recursos](./resource-estimation.md) ⭐
Análise detalhada de viabilidade técnica e requisitos de hardware.

**Conteúdo**:
- ✅ Análise de viabilidade por perfil de hardware
- 📊 Consumo detalhado por componente
- 💰 Comparação de custos: Local vs AWS
- 🎯 Recomendações por tamanho de time

**Use para**: Validar se seu hardware suporta o ambiente local.

### 3. [Configuração VS Code](./vscode-setup.md)
Setup completo do VS Code para máxima produtividade.

**Conteúdo**:
- 🔌 Extensões recomendadas
- ⚙️ Configurações do workspace
- ⌨️ Atalhos de teclado
- 📝 Snippets úteis
- 🎯 Tasks automatizadas

**Use para**: Configurar ambiente de desenvolvimento otimizado.

### 4. [Workflow de Desenvolvimento](./development-workflow.md)
Fluxo completo: do desenvolvimento local até deploy na AWS.

**Conteúdo**:
- 🔄 Ciclo de desenvolvimento
- 🧪 Estratégias de teste
- 🐛 Debug e troubleshooting
- 🚀 Migração para AWS
- ✅ Boas práticas

**Use para**: Entender como trabalhar no dia-a-dia.

## 🗂️ Documentos por Categoria

### Setup Inicial
1. [README](./README.md) - Visão geral
2. [Estimativa de Recursos](./resource-estimation.md) - Viabilidade
3. [Configuração VS Code](./vscode-setup.md) - Ferramentas

### Desenvolvimento Diário
1. [Workflow de Desenvolvimento](./development-workflow.md) - Processos
2. [Setup Guide](./setup-guide.md) - Instalação passo-a-passo *(em breve)*
3. [Docker Compose Guide](./docker-compose-guide.md) - Referência detalhada *(em breve)*

### Instrumentação
1. [Instrumentação Python](../instrumentation/instrumentation-python.md) - Apps Python
2. [Instrumentação Guide](./instrumentation-guide.md) - Outras linguagens *(em breve)*

### Troubleshooting
1. [Troubleshooting Guide](./troubleshooting.md) - Problemas comuns *(em breve)*
2. [FAQ](./faq.md) - Perguntas frequentes *(em breve)*

## 🎯 Guias Rápidos (Quick Start)

### Para Iniciantes
1. ✅ Leia [README](./README.md) para contexto
2. ✅ Valide hardware em [Estimativa de Recursos](./resource-estimation.md)
3. ✅ Configure [VS Code](./vscode-setup.md)
4. ✅ Siga [Workflow - Setup Inicial](./development-workflow.md#1-setup-inicial)

### Para Desenvolvedores Experientes
1. ✅ [Estimativa de Recursos](./resource-estimation.md) - Requisitos
2. ✅ `cd local-dev && docker-compose up -d` - Iniciar
3. ✅ [Workflow](./development-workflow.md) - Referência rápida

## 📖 Documentação Relacionada

### Contexto do Projeto
- [Contexto Completo](../context/context-generator.md)
- [ADRs](../adr/)
- [Arquitetura Lógica](../infra/arquitetura-logica.md)

### Infraestrutura
- [Terraform README](../../infra/terraform/README.md)
- [Helm Charts](../../infra/helm/)
- [Grafana Dashboards](../../infra/grafana/dashboards/)

### Operação
- [Runbooks](../runbooks/)
- [Plano de Execução](../plan/execution-plan.md)

## 🔍 Navegação por Tópico

### Hardware & Recursos
- Requisitos mínimos → [Resource Estimation § Mínimos](./resource-estimation.md#-resumo-executivo)
- Requisitos recomendados → [Resource Estimation § Recomendados](./resource-estimation.md#profile-2-recomendado-desenvolvimento-full)
- Otimizações → [Resource Estimation § Otimizações](./resource-estimation.md#-otimizações-possíveis)

### Setup & Configuração
- Primeira instalação → [Workflow § Setup Inicial](./development-workflow.md#1-setup-inicial)
- Configurar VS Code → [VS Code Setup](./vscode-setup.md)
- Validar instalação → [Workflow § Validação](./development-workflow.md#validação-do-setup)

### Desenvolvimento
- Modificar configs → [Workflow § Modificar Configurações](./development-workflow.md#modificar-configurações)
- Criar dashboards → [Workflow § Criar Dashboards](./development-workflow.md#criar-dashboards)
- Definir alertas → [Workflow § Definir Alertas](./development-workflow.md#definir-alertas)
- Instrumentar apps → [Workflow § Instrumentar Aplicação](./development-workflow.md#instrumentar-aplicação)

### Testes
- Smoke tests → [Workflow § Smoke Tests](./development-workflow.md#smoke-tests)
- Load tests → [Workflow § Load Tests](./development-workflow.md#load-tests)
- Testar alertas → [Workflow § Teste de Alertas](./development-workflow.md#teste-de-alertas)

### Troubleshooting
- Problemas comuns → [Workflow § Troubleshooting](./development-workflow.md#4-debug-e-troubleshooting)
- Logs e debug → [Workflow § Logs Estruturados](./development-workflow.md#logs-estruturados)

### Migração AWS
- Checklist pré-migração → [Workflow § Checklist](./development-workflow.md#checklist-pré-migração)
- Processo de migração → [Workflow § Migração](./development-workflow.md#processo-de-migração)

## 📊 Matriz de Decisão

| Se você quer... | Leia este documento |
|-----------------|---------------------|
| Saber se seu PC aguenta | [Resource Estimation](./resource-estimation.md) |
| Instalar pela primeira vez | [Workflow § Setup Inicial](./development-workflow.md#1-setup-inicial) |
| Configurar editor de código | [VS Code Setup](./vscode-setup.md) |
| Entender o dia-a-dia | [Workflow](./development-workflow.md) |
| Criar um dashboard | [Workflow § Dashboards](./development-workflow.md#criar-dashboards) |
| Instrumentar uma app | [Instrumentation Python](../instrumentation/instrumentation-python.md) |
| Debugar um problema | [Workflow § Debug](./development-workflow.md#4-debug-e-troubleshooting) |
| Fazer deploy na AWS | [Workflow § Migração](./development-workflow.md#5-migração-para-aws) |

## 🆘 Ajuda

### Encontrou um problema?
1. Consulte [Workflow § Troubleshooting](./development-workflow.md#4-debug-e-troubleshooting)
2. Verifique logs: `docker-compose logs -f`
3. Execute health checks: `curl http://localhost:9090/-/healthy`

### Quer contribuir?
1. Leia [Workflow § Boas Práticas](./development-workflow.md#boas-práticas)
2. Teste localmente antes de commitar
3. Atualize documentação se necessário

### Tem dúvidas?
- Abra uma issue no repositório
- Consulte os [ADRs](../adr/) para decisões de arquitetura
- Leia o [Contexto do Projeto](../context/context-generator.md)

---

**Última atualização**: Dezembro 2025  
**Mantenedores**: Time de Observabilidade
