# Copilot Context - Projeto Kubernetes

> **Última Atualização**: 2026-03-03
> **Fase Atual**: 3 (Execução e Hardening)
> **Status SAD**: v1.2 🔒 CONGELADO (Freeze #3)
> **Governança**: AI-First com rastreabilidade obrigatória + **STRICT-RULES** ⚠️
> **Orquestrador**: Kubernetes (ADR-021)
> **🎉 Novidade**: GitLab v18.9.1 + Linkerd DEPLOYED + PostgreSQL 16 + Kyverno ENFORCE (2026-03-03)

> 📘 **NOTA**: Este arquivo mantém compatibilidade legado. Ver [/PROJECT-CONTEXT.md](../PROJECT-CONTEXT.md) para contexto consolidado completo.

> 🚨 **REGRAS ANTI-ALUCINAÇÃO**: ANTES de criar QUALQUER documento `.md`, consulte [/docs/governance/STRICT-RULES.md](../docs/governance/STRICT-RULES.md) - Aprovação do usuário é **OBRIGATÓRIA**

---

## 1. VISÃO GERAL DO PROJETO

### O que é o Projeto Kubernetes?
**Projeto Kubernetes** é uma **plataforma corporativa de engenharia robusta e escalável** usando Kubernetes como base de articulação tecnológica do departamento, gerenciando **6 domínios especializados**:

1. **platform-core**: Fundação (Kong, Keycloak, Service Mesh)
2. **cicd-platform**: Esteira CI/CD (GitLab, SonarQube, ArgoCD, Backstage)
3. **observability**: Monitoramento full-stack (OpenTelemetry, Prometheus, Grafana, Loki, Tempo, Kiali)
4. **data-services**: DBaaS, CacheaaS, MQaaS (PostgreSQL, Redis, RabbitMQ)
5. **secrets-management**: Cofre centralizado (Vault)
6. **security**: Policies, runtime, compliance (OPA/Kyverno, Falco, Trivy)

**Características**:
- **Orquestrador: Kubernetes** (ADR-021) - Escolhido por cloud-agnostic + ecossistema maduro
- **Cloud-Agnostic OBRIGATÓRIO**: Sem recursos nativos de cloud
- **Escalabilidade Multi-Domínio**: Cada domínio evolui de forma independente
- **Governança Centralizada**: SAD como fonte suprema, ADRs obrigatórios
- **Rastreabilidade Total**: Hooks, logs, commits estruturados
- **Isolamento**: Namespaces, RBAC, Network Policies, Service Mesh por domínio

### Missão
Estabelecer uma **plataforma corporativa de engenharia robusta e escalável** usando Kubernetes como base de articulação tecnológica, fornecendo:
- Esteira CI/CD completa (primeiro objetivo)
- Observabilidade full-stack
- Serviços de dados gerenciados (HA, backup, alarmes)
- Governança via Backstage (catálogo + criação automatizada de apps)
- Segurança desde o início (service mesh, API gateway, autenticação centralizada)

---

## 2. ARQUITETURA

### Estilo Arquitetural
- **Padrão Principal**: Multi-domínio com isolamento e governança centralizada
- **Estrutura**: `/domains` contém domínios independentes
- **Infraestrutura**: Kubernetes + Terraform (IaC) + Helm (CD)
- **Governança**: SAD congelado + ADRs + Architect Guardian

### Domínios

| Domínio                | Status                                                      | Responsabilidade                                     | Stack Principal                                            |
| ---------------------- | ----------------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------------- |
| **platform-core**      | ✅ DEPLOYED                                                 | Fundação (gateway, auth, service mesh, certificados) | Kong, Keycloak, Linkerd ✅, cert-manager, ALB              |
| **cicd-platform**      | ✅ DEPLOYED (GitLab v18.9.1, ArgoCD v2.10.0)               | Esteira CI/CD + governança via Backstage             | GitLab CE 9.9.1, SonarQube, ArgoCD, Harbor                |
| **observability**      | ✅ Validado (APROVADO)                                      | Métricas, logs, traces, visualização                 | OpenTelemetry, Prometheus, Grafana, Loki, Tempo, Kiali    |
| **data-services**      | ✅ DEPLOYED                                                 | DBaaS, CacheaaS, MQaaS (HA + backup)                | PostgreSQL RDS 16.4, Redis 8.4.1, RabbitMQ, Velero        |
| **secrets-management** | 🔄 Planejado                                                | Cofre integrado com CI/CD                            | HashiCorp Vault ou External Secrets Operator               |
| **security**           | ✅ DEPLOYED (Kyverno ENFORCE)                               | Policies, runtime security, compliance               | Kyverno (3 policies), Falco, Trivy, RBAC, Network Policies |

### Estrutura do Projeto

#### /platform-provisioning/ (CLOUD-SPECIFIC)
```
/platform-provisioning/{cloud}/
├── kubernetes/
│   ├── terraform/      # IaC cloud-specific (azurerm, aws, google)
│   │   ├── cluster.tf  # EKS, AKS, GKE
│   │   ├── networking.tf # VPC, VNet, Subnets
│   │   ├── storage.tf  # Storage classes, object storage
│   │   └── outputs.tf  # Outputs para domínios
│   └── docs/
│       ├── architecture.md
│       └── runbook.md
└── README.md
```

**Responsabilidade**: Provisionar cluster Kubernetes e infraestrutura base da cloud

#### /domains/ (CLOUD-AGNOSTIC)
```
/domains/{domain-name}/
├── docs/               # Documentação do domínio
│   ├── context/        # Contexto e missão
│   ├── adr/            # ADRs locais
│   ├── plan/           # Plano de execução
│   ├── runbooks/       # Runbooks operacionais
│   └── logs/           # Logs do domínio
├── infra/              # Infraestrutura como Código
│   ├── terraform/      # Terraform cloud-agnostic (kubernetes, helm)
│   ├── helm/           # Helm charts
│   └── configs/        # Configs adicionais
├── local-dev/          # Ambiente local Docker
│   ├── docker-compose.yml
│   └── README.md
└── contexts/           # Contextos para AI
    └── copilot-context.md
```

**Responsabilidade**: Deploy de aplicações em cluster existente (cloud-agnostic)

**Separação** (ADR-020):
- **`/platform-provisioning/`**: Provisiona cluster (**pode** usar recursos cloud-specific)
- **`/domains/`**: Deploy aplicações (**deve** ser cloud-agnostic)

---

## 3. STACK TECNOLÓGICA

### Core
- **Orquestração**: Kubernetes (EKS/GKE/AKS/on-prem) — **Cloud-agnostic OBRIGATÓRIO**
- **IaC**: Terraform (módulos cloud-agnostic reutilizáveis)
- **CD**: Helm, ArgoCD
- **Containers**: Docker, containerd

### Por Domínio

#### platform-core (Fundação)
- Kong (API Gateway)
- Keycloak (Autenticação e Autorização centralizada)
- Istio ou Linkerd (Service Mesh com sidecar isolation)
- cert-manager (Certificados TLS automatizados)
- NGINX (Ingress Controller)

#### cicd-platform (Esteira DevOps) — **Primeiro Objetivo**
- GitLab (Git self-hosted + CI pipelines)
- SonarQube (Qualidade de código)
- ArgoCD (Continuous Deployment) — ✅ v2.10.0 com PKCE ativo
- Backstage Spotify (Developer Portal + Catálogo + Governança)
- Tekton (Pipelines avançados - futuro)
- **Stacks Suportadas**: Go, .NET, Python, Node.js (polyglot)

#### observability (Monitoramento Full-Stack)
- OpenTelemetry Collector (coletor central)
- Prometheus (métricas + Alertmanager)
- Grafana (visualização)
- Loki (logs)
- Tempo (traces distribuídos)
- Kiali (observabilidade de service mesh)

#### data-services (DBaaS, CacheaaS, MQaaS)
- PostgreSQL (HA com replicação + backup automatizado)
- Redis (cluster mode para cache e sessões)
- RabbitMQ (cluster HA para mensageria)
- Velero (backup/restore automatizado)
- Prometheus Exporters (observabilidade de databases)
- Alertmanager (alarmística)

#### secrets-management (Cofre de Senhas)
- HashiCorp Vault ou External Secrets Operator
- Integração automática com CI/CD
- Rotação automática de credenciais
- Auditoria de acessos
- **Decisão Pendente**: Mesa técnica sobre armazenar secrets na imagem vs external

#### security (Segurança e Compliance)
- OPA ou Kyverno (policy engine)
- Falco (runtime security)
- Trivy (scan de vulnerabilidades integrado ao CI/CD)
- RBAC centralizado por namespace
- Network Policies rigorosas
- Pod Security Standards

---

## 4. DECISÕES ARQUITETURAIS (ADRs)

### ADRs Globais (/docs/adr)
- **ADR-001**: Setup, Governança e Método
- **ADR-002**: Estrutura de Domínios Multi-Kubernetes

### ADRs Sistêmicos (/SAD/docs/adrs) - v1.1 🔒
Total: **12 ADRs**

**Fundamentais**:
- **ADR-003**: Cloud-Agnostic e Portabilidade (v1.1 - atualizado)
- **ADR-004**: IaC e GitOps (v1.1 - atualizado)
- **ADR-020**: Provisionamento de Clusters e Escopo de Domínios ✨ **NOVO**

**Arquiteturais**:
- **ADR-005**: Segurança Sistêmica
- **ADR-006**: Observabilidade Transversal
- **ADR-007**: Service Mesh
- **ADR-008**: Escalabilidade e Performance
- **ADR-013**: Disaster Recovery
- **ADR-014**: Compliance Regulatória
- **ADR-015**: Multi-Tenancy
- **ADR-016**: Escalabilidade Vertical
- **ADR-017**: Integrações Externas
- **ADR-018**: Treinamento e Capacitação
- **ADR-019**: FinOps e Otimização de Custos

**Mudanças Principais v1.0 → v1.1**:
- ✅ ADR-020 criado: Separação `/platform-provisioning` vs `/domains`
- ✅ Storage classes parametrizadas obrigatórias
- ✅ Object storage S3-compatible como padrão
- ✅ Terraform nos domínios: apenas providers K8s
- ✅ Clusters provisionados EXTERNAMENTE aos domínios

### ADRs de Domínio (/domains/{domain}/docs/adr)
*Cada domínio pode ter ADRs locais para decisões específicas*

**Observability**:
- ADR-001: Decisões Iniciais (superseded by SAD)
- ADR-002: Mesa Técnica (superseded by SAD)
- ADR-003: Validação contra SAD v1.0 (VIOLAÇÃO CRÍTICA identificada)
- ADR-004: Re-validação contra SAD v1.1 (APROVADO)

---

## 5. METODOLOGIA AI-FIRST

### Fases do Projeto

**🔹 FASE 0 — SETUP DO SISTEMA** ✅ COMPLETA
- Estrutura /docs criada
- Estrutura /SAD criada
- Estrutura /domains criada
- Agentes e Skills copiados
- Prompts especializados criados
- ADRs de governança criados

**🔹 FASE 1 — CONCEPÇÃO DO SAD** ✅ COMPLETA
- ✅ SAD v1.0 criado (Freeze #1 - 2025-12-30)
- ✅ SAD v1.1 atualizado (Freeze #2 - 2026-01-05)
- ✅ 12 ADRs sistêmicos criados
- ✅ Regras de herança definidas
- ✅ Contratos entre domínios estabelecidos
- ✅ ADR-020: Diretrizes práticas cloud-agnostic

**🔹 FASE 2 — CRIAÇÃO DOS DOMÍNIOS** 🔄 EM PROGRESSO
- ✅ Task 2.1: Domínio Observability validado e APROVADO
- 🔄 Task 2.2: Criar domínio platform-core (Próximo)
- 🔄 Task 2.3: Criar domínio cicd-platform (🎯 Primeiro Objetivo)
- 🔄 Task 2.4-2.6: Criar demais domínios

**🔹 FASE 3 — EXECUÇÃO POR DOMÍNIO**
- Evolução isolada por domínio
- Governança pelo SAD v1.1
- Validação via Architect Guardian

### Agentes Especializados

| Agente                     | Responsabilidade                    |
| -------------------------- | ----------------------------------- |
| **Gestor**                 | Coordenação geral, priorização      |
| **Arquiteto**              | Decisões arquiteturais, ADRs        |
| **Architect Guardian**     | Validação absoluta contra SAD       |
| **SRE**                    | Operações, runbooks, monitoramento  |
| **Facilitador Brainstorm** | Ideação e solução de problemas      |
| **Revisor**                | Code review, validação de qualidade |
| **Executor MCP**           | Execução de tarefas via MCP         |

### Prompts Especializados

| Prompt                 | Uso                            |
| ---------------------- | ------------------------------ |
| **orchestrator-guide** | Setup completo do projeto      |
| **develop-feature**    | Desenvolver feature em domínio |
| **bugfix**             | Corrigir bugs em domínio       |
| **refactoring**        | Refatorar infraestrutura       |
| **domain-creation**    | Criar novo domínio             |
| **automatic-audit**    | Auditar consistência e drift   |

---

## 6. REGRAS PERMANENTES

### Governança
- **Sempre consultar ADRs** antes de mudanças
- **Nunca agir sem contexto** validado
- **Nunca extrapolar escopo** sem aprovação
- **Decisões exigem rastreabilidade** (ADR + commit + log)

### Isolamento de Domínios
- Domínios não podem ter dependências diretas
- Comunicação via contratos documentados
- Namespaces Kubernetes isolados
- RBAC e Network Policies por domínio

### Hooks Obrigatórios
**PRE → EXEC → POST → VALIDAR → PERSISTIR**

### Política de Commit
```
[type](domain): descrição

Contexto:
Domínio: {{domain}}
Artefatos: {{arquivos}}
Resultado: {{entregue}}
```

Tipos: `feat | fix | docs | adr | refactor | chore | domain`

---

## 7. COMANDOS ÚTEIS

### Terraform
```bash
terraform init
terraform plan
terraform apply
```

### Helm
```bash
helm repo add <repo> <url>
helm install <release> <chart> -f values.yaml
helm upgrade <release> <chart> -f values.yaml
helm diff upgrade <release> <chart> -f values.yaml
```

### Kubernetes
```bash
kubectl get pods -n <namespace>
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
kubectl apply -f manifest.yaml
kubectl diff -f manifest.yaml
```

---

## 8. FRASE DE CONTROLE GLOBAL

**Se uma ação não puder ser rastreada em documentos, logs ou commits, ela NÃO deve ser executada.**

---

## 9. PRÓXIMOS PASSOS

1. ✅ **FASE 0-1**: Setup + SAD v1.2 COMPLETO
2. ✅ **FASE 2**: Domínios implementados (5/6 — 83%)
3. ✅ **GitLab v18.9.1**: Upgrade chain completa (9 steps, 9 breaking changes)
4. ✅ **Linkerd Service Mesh**: mTLS end-to-end DEPLOYED
5. ✅ **Kyverno**: 3 ClusterPolicies em ENFORCE mode
6. 🔄 **Marco 5**: Production Readiness (Enterprise Assessment 4.2/5.0)

---

## 10. Lacunas Identificadas na Mesa Técnica (DevOps/DevSecOps/SRE)
Após mesa técnica com especialistas, foram identificadas as seguintes lacunas críticas (considerando marco zero sem legado):

1. **Compliance Regulatória**: Adicionar auditoria automática, data residency e zero-trust networking para GDPR/HIPAA.
2. **Testes de Carga e Performance**: Incluir na FASE 4, com ferramentas como K6 ou Locust para validar escalabilidade.
3. **Disaster Recovery**: Procedures para backup cross-region e failover automático (Velero + multi-region).
4. **Multi-Cloud Deployment**: Estratégia para portabilidade e alta disponibilidade entre clouds.
5. **FinOps (Gestão de Custos)**: Estratégia dedicada para orçamento, monitoramento e otimização de custos.
6. **Multi-Tenancy para Equipes**: Isolamento por equipe dentro de domínios (namespaces, quotas).
7. **Escalabilidade Vertical**: Estratégia para vertical scaling (CPU/memory limits, HPA vertical).
8. **Integração com Ferramentas Externas**: Integração com Jira (tickets), Slack (notificações), etc.
9. **Treinamento de Equipes**: Capacitação em Kubernetes, IaC, observabilidade.
10. **Governança de Mudanças**: Processo para mudanças manuais ou emergenciais.

## 11. ADRs Sugeridos

- **ADR-007**: Service Mesh (Linkerd recomendado por custo e simplicidade).
- **ADR-013**: Disaster Recovery (Velero + multi-region backup).
- **ADR-014**: Compliance Regulatória (auditoria e zero-trust).
- **ADR-015**: Multi-Tenancy (isolamento por equipe).
- **ADR-016**: Escalabilidade Vertical.
- **ADR-017**: Integrações Externas (Jira, Slack).
- **ADR-018**: Treinamento e Capacitação.

---

## 12. GOVERNANÇA DOCUMENTAL (2026-01-22) 🚨

### Regras Rígidas Anti-Alucinação

**Documento de Referência**: [/docs/governance/STRICT-RULES.md](../docs/governance/STRICT-RULES.md)

#### ⚠️ OBRIGATÓRIO ANTES DE CRIAR QUALQUER ARQUIVO `.md`

**Checklist de 6 Perguntas**:

1. ❓ **Este documento JÁ EXISTE?** → SE SIM: **PARE! ATUALIZE O EXISTENTE**
2. ❓ **Está na lista PROIBIDA?** → SE SIM: **PARE! NÃO CRIE**
3. ❓ **Localização está APROVADA?** → SE NÃO: **PARE! PEÇA APROVAÇÃO**
4. ❓ **Há documento SIMILAR?** → SE SIM: **PARE! ATUALIZE**
5. ❓ **Nomenclatura CORRETA?** → SE NÃO: **PARE! CORRIJA**
6. ❓ **Usuário APROVOU?** → SE NÃO: **PARE! PEÇA APROVAÇÃO**

#### 🚫 NUNCA CRIAR (Lista de Proibições)

```yaml
ABSOLUTAMENTE PROIBIDO:
  # Documentos duplicados
  - README-v2.md, README-new.md, README-updated.md
  - execution-plan-new.md, plan-v2.md
  - sad-updated.md, sad-new.md

  # Reports temporários
  - report-*.md, REPORT-*.md
  - analysis-*.md, summary-*.md
  - validation-*.md (usar VALIDATION-REPORT.md)
  - notes-*.md, draft-*.md

  # Logs duplicados
  - changelog.md, history.md
  - activity-log.md

  # Contextos duplicados
  - claude-context.md, chatgpt-context.md
  - (usar APENAS copilot-context.md)

  # Diretórios temporários
  - tmp/, temp/, drafts/, backup/, scratch/
```

#### ✅ Documentos ÚNICOS (Atualizar, NUNCA Duplicar)

| Documento                | Localização               | Regra                 |
| ------------------------ | ------------------------- | --------------------- |
| **README.md**            | `/`                       | ✅ ÚNICO na raiz       |
| **README.md**            | `/domains/{domain}/`      | ✅ 1 por domínio       |
| **sad.md**               | `/SAD/docs/`              | ✅ ÚNICO global        |
| **sad-freeze-record.md** | `/SAD/docs/`              | ✅ ÚNICO global        |
| **execution-plan.md**    | `/docs/plan/`             | ✅ ÚNICO global        |
| **log-de-progresso.md**  | `/docs/logs/`             | ✅ ÚNICO global        |
| **copilot-context.md**   | `/ai-contexts/`           | ✅ ÚNICO global (ESTE) |
| **VALIDATION-REPORT.md** | `/domains/{domain}/docs/` | ✅ 1 por domínio       |

#### ✅ Documentos MÚLTIPLOS (Seguir Padrões)

| Tipo                | Padrão         | Localização                        | Exemplo                        |
| ------------------- | -------------- | ---------------------------------- | ------------------------------ |
| **ADRs Sistêmicos** | `adr-XXX-*.md` | `/SAD/docs/adrs/`                  | `adr-022-banco-dados.md`       |
| **ADRs de Domínio** | `adr-XXX-*.md` | `/domains/{domain}/docs/adr/`      | `adr-001-estrutura-inicial.md` |
| **Agentes**         | `{nome}.md`    | `/docs/agents/`                    | `gestor.md`                    |
| **Skills**          | `{nome}.md`    | `/docs/skills/`                    | `arquitetura.md`               |
| **Runbooks**        | `{nome}.md`    | `/domains/{domain}/docs/runbooks/` | `troubleshooting.md`           |

#### 📋 Workflow de Criação OBRIGATÓRIO

```yaml
1. IDENTIFICAR_NECESSIDADE:
   - Por que criar este documento?

2. VERIFICAR_EXISTENTE:
   - Existe documento similar?
   - Posso atualizar ao invés de criar?

3. VALIDAR_LOCALIZAÇÃO:
   - Diretório está na estrutura aprovada?
   - Nomenclatura está correta?

4. SOLICITAR_APROVAÇÃO: ⚠️ OBRIGATÓRIO
   prompt: |
     Identifico necessidade de criar:
     - Arquivo: {caminho/completo}
     - Motivo: {justificativa}
     - Conteúdo: {resumo}

     Posso prosseguir?

5. AGUARDAR_CONFIRMAÇÃO:
   - ✅ APROVADO → Prosseguir
   - ❌ REJEITADO → Buscar alternativa

6. CRIAR_DOCUMENTO:
   - Seguir template apropriado
   - Preencher metadados

7. REGISTRAR_CRIAÇÃO:
   - Adicionar entrada em log-de-progresso.md
```

#### 🛡️ Penalidades por Violação

**Se criar SEM aprovação**:
1. ❌ **REVERTER IMEDIATAMENTE**
2. ❌ **DELETAR ARQUIVO**
3. ❌ **DOCUMENTAR VIOLAÇÃO** no log

#### 📚 Referências Obrigatórias

- [STRICT-RULES.md](../docs/governance/STRICT-RULES.md) - Regras completas
- [Post-Activity Hook](../docs/hooks/post-activity-validation.md) - Validação automática
- [Log de Progresso](../docs/logs/log-de-progresso.md) - Registro de atividades

---

**Última Atualização Governança**: 2026-03-03
**Status**: ✅ ATIVO - CUMPRIMENTO OBRIGATÓRIO
