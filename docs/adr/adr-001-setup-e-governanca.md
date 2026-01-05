# ADR 001 — Setup, Governança e Método

## Data
2025-12-30

## Status
Aprovado ✅

## Contexto
Define as regras fundamentais de governança e método de trabalho para o projeto Kubernetes multi-domínio, estabelecendo a fundação para desenvolvimento AI-First com rastreabilidade total.

Este projeto segue a metodologia AI-First estabelecida no projeto iPaaS, adaptada para gerenciar múltiplos domínios de infraestrutura Kubernetes.

## Decisões

### 1. Uso de Fases Incrementais
O projeto seguirá o modelo de fases obrigatório:
- **FASE 0**: Setup do sistema (estrutura /docs, /SAD, /domains, agentes, skills, prompts)
- **FASE 1**: Concepção do SAD (decisões arquiteturais sistêmicas)
- **FASE 2**: Criação dos Domínios (estrutura base, herança do SAD)
- **FASE 3**: Execução por Domínio (evolução isolada com governança central)

⚠️ Nenhuma fase pode ser pulada sem aprovação explícita.

### 2. Uso de ADRs Obrigatórios
Todo decisão arquitetural significativa deve ser documentada via ADR:
- ADRs globais em `/docs/adr/` (governança e processo)
- ADRs sistêmicos em `/SAD/docs/adrs/` (decisões arquiteturais)
- ADRs de domínio em `/domains/{domain}/docs/adr/` (decisões locais)

### 3. Hooks Obrigatórios (Pre/Post)
Toda ação deve seguir o fluxo:
- **PRE-HOOK**: Declarar intenção, ler contexto, validar pré-condições
- **EXEC**: Executar ação
- **POST-HOOK**: Atualizar contexto, logs, planos, documentação
- **VALIDAR**: Architect Guardian valida aderência ao SAD
- **PERSISTIR**: Commit estruturado

### 4. SAD como Fonte Suprema
O SAD congelado é a autoridade máxima:
- Decisões sistêmicas APENAS no SAD
- Domínios herdam obrigatoriamente padrões do SAD
- Mudanças ao SAD exigem ADR + aprovação + novo freeze
- Architect Guardian garante aderência absoluta

### 5. Estrutura de Domínios Isolados
Múltiplos domínios em `/domains`:
- Cada domínio opera de forma independente
- Comunicação entre domínios via contratos documentados
- Namespaces Kubernetes isolados por domínio
- RBAC e Network Policies por domínio
- Infraestrutura (Terraform/Helm) por domínio

### 6. Rastreabilidade Total
- Toda ação gera log em `/docs/logs/log-de-progresso.md`
- Logs de domínio em `/domains/{domain}/docs/logs/`
- Commits estruturados: `[type](domain): description`
- Sem commit = ação inexistente

### 7. Agente Architect Guardian
Agente especial com autoridade para:
- Bloquear execuções que violem SAD
- Validar criação de novos domínios
- Detectar drift arquitetural
- Exigir ADRs corretivos

## Observação Importante
Este ADR **NÃO contém decisões arquiteturais sistêmicas** (Kubernetes, IaC, cloud, etc.).

Essas decisões só são permitidas na **FASE 1 (SAD)**.

## Consequências

### Positivas
- Governança clara e rastreável
- Autonomia de domínios com coordenação central
- IA opera com contexto completo e validação constante
- Decisões documentadas e auditáveis

### Negativas
- Overhead inicial para setup
- Exige disciplina rigorosa
- Não permite atalhos ou improvisações

### Riscos
- Equipe precisa se adaptar ao método
- Pode parecer burocrático inicialmente

## Regra de Ouro
**Se uma ação não puder ser rastreada em documentos, logs ou commits, ela NÃO deve ser executada.**

## Aprovações
- [x] Usuário (gilvangalindo)
- [x] Architect Guardian (validado via framework iPaaS)
- [x] Copilot (executando)
