# Context Generator

> 📘 **NOTA**: Este documento define a missão e escopo originais. Ver [/PROJECT-CONTEXT.md](../../PROJECT-CONTEXT.md) para status atualizado e contexto consolidado.

## Missão do Projeto
Estabelecer uma **plataforma corporativa de engenharia robusta e escalável** usando Kubernetes como base de articulação tecnológica do departamento, com governança AI-First, cloud-agnostic e preparada para crescimento, servindo como fundação para CI/CD, observabilidade, serviços de dados, segurança e governança de aplicações.

## Escopo
- **Plataforma Corporativa Kubernetes** com melhores práticas desde o início
- **Esteira CI/CD Completa**: GitLab, SonarQube, ArgoCD, Backstage Spotify
- **Observabilidade Full-Stack**: OpenTelemetry, Prometheus, Grafana, Loki, Tempo, Kiali
- **Serviços de Dados Gerenciados**: PostgreSQL, Redis, RabbitMQ (HA, backup, alarmes)
- **Segurança Corporativa**: Kong (API Gateway), Keycloak (autenticação), Service Mesh com sidecar, secrets management (Vault)
- **Governança de Aplicações**: Backstage como catálogo e orquestrador de criação de apps
- **Cloud-Agnostic**: Sem recursos nativos de cloud, migrável e escalável
- **Framework AI-First**: ADRs, SAD congelado, hooks obrigatórios, rastreabilidade total
- **Infraestrutura como Código**: Terraform + Helm para tudo

## Não-Escopo
- Desenvolvimento de aplicações de negócio (foco é na plataforma)
- Operação 24/7 de clusters em produção (inicialmente)
- Migração de workloads legacy não containerizados
- Integrações específicas de terceiros sem validação arquitetural
- Uso de recursos nativos de clouds específicas (AWS/GCP/Azure)
- Implementação de funcionalidades custom que existem em ferramentas maduras

## Usuários-Alvo
- **Arquitetos de Plataforma**: Definição de padrões e decisões sistêmicas
- **Platform Engineers**: Construção e manutenção da plataforma
- **SREs/DevOps**: Operação de clusters, esteira CI/CD, observabilidade
- **Desenvolvedores**: Consumo de serviços (CI/CD, databases, cache, mensageria, observabilidade)
- **Tech Leads**: Criação de novas aplicações via Backstage
- **Security Team**: Gestão de políticas, secrets, autenticação
- **Gestores/CTO** OBRIGATÓRIO**: Sem usar recursos nativos de clouds, 100% Kubernetes nativo
- **Escalabilidade Desde o Início**: Arquitetura preparada para crescimento mesmo usando pouco inicialmente
- **Melhores Práticas Obrigatórias**: Service mesh, API Gateway, autenticação centralizada, secrets management
- **Custo Controlado**: Priorizar open source mas sem comprometer qualidade
- **Segurança Corporativa**: RBAC, Network Policies, Pod Security Standards, isolamento entre namespaces
- **Compliance e Rastreabilidade**: Todas as decisões via ADRs, commits estruturados, auditoriamises
- **Custo Controlado**: Priorizar componentes open source e configurações otimizadas
- **Segurança**: RBAC, Network Policies, Pod Security Standards obrigatórios
- **Compliance**: Todas as decisões devem ser rastreáveis via ADRs e commits

## Regras Permanentes
- **Consultar ADRs**: Sempre verificar decisões arquiteturais antes de mudanças
- **Nunca agir sem contexto**: Validar com SAD e contexto de domínio
- **Nunca extrapolar escopo**: Mudanças fora do escopo exigem aprovação explícita
- **Decisões exigem rastreabilidade**: Commits estruturados + ADRs + logs
- **Isolamento por domínio**: Cada domínio opera de forma independente mas segue padrões do SAD

### Lacunas Identificadas na Mesa Técnica (DevOps/DevSecOps/SRE)
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

### ADRs Sugeridos
- **ADR-007**: Service Mesh (Linkerd recomendado por custo e simplicidade).
- **ADR-013**: Disaster Recovery (Velero + multi-region backup).
- **ADR-014**: Compliance Regulatória (auditoria e zero-trust).
- **ADR-015**: Multi-Tenancy (isolamento por equipe).
- **ADR-016**: Escalabilidade Vertical.
- **ADR-017**: Integrações Externas (Jira, Slack).
- **ADR-018**: Treinamento e Capacitação.

## Premissas
- Equipes terão acesso a clusters Kubernetes (EKS/GKE/AKS ou local)
- Desenvolvimento local via Docker/Kind/Minikube para validação
- Uso de Helm para deploy de componentes
- OpenTelemetry como padrão de instrumentação (para Observabilidade)
- GitOps como padrão de deployment (ArgoCD/Flux)

## Stack Tecnológica

### Core
- **Orquestração**: Kubernetes (EKS/GKE/AKS/on-prem)
- **IaC**: Terraform (módulos reutilizáveis cloud-agnostic)
- **CD**: Helm, ArgoCD
- **Containers**: Docker, containerd

### Domínios da Plataforma

#### 1. Platform-Core (Fundação)
- **API Gateway**: Kong
- **Autenticação**: Keycloak
- **Service Mesh**: Istio ou Linkerd (sidecar para isolamento)
- **Certificados**: cert-manager
- **Ingress**: NGINX

#### 2. CI/CD Platform (Esteira DevOps)
- **Git**: GitLab (self-hosted)
- **Qualidade de Código**: SonarQube
- **Continuous Deployment**: ArgoCD
- **Developer Portal**: Backstage Spotify (catálogo + governança)
- **Pipelines**: GitLab CI inicialmente, expansível para Tekton
- **Stacks Suportadas**: Python (inicial), expansível para outras

#### 3. Observability (Monitoramento e Logs)
- **Coletor Central**: OpenTelemetry Collector
- **Métricas**: Prometheus
- **Visualização**: Grafana, Kiali (service mesh)
- **Logs**: Loki
- **Traces**: Tempo
- **Dashboards**: Golden Signals, por domínio, por aplicação

#### 4. Data Services (Serviços de Dados)
- **Database**: PostgreSQL (HA com replicação)
- **Cache**: Redis (cluster mode)
- **Mensageria**: RabbitMQ (cluster, HA)
- **Backup/Restore**: Automatizado com Velero
- **Observabilidade**: Exporters para Prometheus
- **Alarmística**: Alertmanager integrado

#### 5. Secrets Management (Cofre de Senhas)
- **Vault**: HashiCorp Vault ou External Secrets Operator
- **Integração CI/CD**: Injeção automática de secrets
- **Rotação**: Automática de credenciais
- **Auditoria**: Logs de acesso a secrets

#### 6. Security (Segurança e Compliance)
- **Policy Engine**: OPA ou Kyverno
- **Runtime Security**: Falco
- **RBAC**: Centralizado e documentado
- **Network Policies**: Por namespace/domínio
- **Pod Security**: Pod Security Standards enforced
- **Scan de Vulnerabilidades**: Trivy integrado no CI/CD

## Critérios de Sucesso

### FASE 0 (Setup) ✅
- Estrutura base criada seguindo padrão iPaaS
- Framework AI-First validado

### FASE 1 (SAD)
- SAD congelado com decisões sistêmicas cloud-agnostic
- ADRs sistêmicos aprovados (mínimo 8)
- Regras de herança e contratos entre domínios definidos

### FASE 2-3 (Implementação)
- **Platform-Core**: Kong + Keycloak + Service Mesh operacionais
- **CI/CD**: GitLab + SonarQube + ArgoCD + Backstage operacionais
- **Observability**: Stack completa operacional (OpenTelemetry → Prometheus/Loki/Tempo → Grafana/Kiali)
- **Data Services**: PostgreSQL + Redis + RabbitMQ com HA e backup
- **Secrets**: Vault integrado com CI/CD
- **Security**: Políticas, RBAC, Network Policies aplicados

### FASE 4 (Integração)
- Pipeline CI/CD Python funcionando end-to-end
- Aplicação exemplo criada via Backstage
- Observabilidade coletando de todos os domínios
- Secrets injetados via Vault no CI/CD
- Autenticação via Keycloak funcionando

### FASE 5 (Governança)
- Documentação completa (runbooks, troubleshooting)
- Backstage como catálogo central funcionando
- Processos de criação de novas apps documentados
- Equipe treinada

## Riscos Identificados
- **Complexidade multi-domínio**: 6 domínios interdependentes - Mitigado por isolamento claro e SAD bem definido
- **Over-engineering inicial**: Arquitetura corporativa robusta mesmo usando pouco - Mitigado por implantação incremental
- **Custo de múltiplos serviços**: GitLab, SonarQube, Vault, etc. consomem recursos - Monitoramento FinOps desde o início
- **Curva de aprendizado**: Stack complexa (service mesh, API gateway, Backstage) - Documentação extensiva e runbooks
- **Integração entre domínios**: Backstage ↔ GitLab ↔ ArgoCD ↔ Vault - Contratos bem definidos e testados
- **Secrets na imagem vs external**: Decisão arquitetural crítica - Mesa técnica obrigatória
- **Cloud lock-in**: Tentação de usar recursos nativos - Validação rigorosa via Architect Guardian

## FRASE DE CONTROLE GLOBAL
Se uma ação não puder ser rastreada em documentos, logs ou commits, ela NÃO deve ser executada.
