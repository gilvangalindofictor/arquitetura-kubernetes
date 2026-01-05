# Plano de Execução

## Objetivo Principal
Provisionar uma fundação de observabilidade na AWS (open source) preparada para receber aplicações instrumentadas, com documentação, dashboards e alertas iniciais.

## Features
- Módulos Terraform para infra (VPC, EKS, S3, IAM)
- Deploy inicial do OpenTelemetry Collector
- Deploy PoC: Prometheus (+ Alertmanager), Grafana, Loki, Tempo
- Dashboards básicos (latência, taxa de erro, saturação)
- Alertas básicos (availability, error rate, high latency)
- Runbooks de instrumentação e onboarding de aplicações

## Tasks (Atualizadas após Mesa Técnica - 08/12/2025)

### Fase 1: Infraestrutura Base (Prazo: 15-18/12/2025)
- [ ] Criar módulo Terraform: VPC (3 AZs, subnets públicas/privadas)
- [ ] Criar módulo Terraform: EKS (single cluster, node groups por namespace)
- [ ] Criar módulo Terraform: S3 buckets (métricas, logs, backups)
- [ ] Criar módulo Terraform: IAM roles e policies (IRSA por namespace)
- [ ] Provisionar cluster EKS em ambiente dev

### Fase 2: Stack de Observabilidade (Prazo: 18-22/12/2025)
- [ ] Deploy kube-prometheus-stack via Helm (Prometheus + Alertmanager + Grafana)
- [ ] Deploy Loki via Helm (com S3 backend)
- [ ] Deploy Tempo via Helm (com S3 backend)
- [ ] Deploy OpenTelemetry Collector (modo gateway, namespaces separados)
- [ ] Configurar datasources no Grafana (Prometheus, Loki, Tempo)

### Fase 3: Dashboards e Alertas (Prazo: 22-27/12/2025)
- [ ] Criar dashboards Golden Signals (latência, erros, tráfego, saturação)
- [ ] Criar dashboards por namespace (dev/hml/prd)
- [ ] Configurar alertas básicos: availability, error rate, high latency
- [ ] Integrar Alertmanager com canal de notificação (Slack/email)

### Fase 4: Documentação e Instrumentação (Prazo: 27/12/2025 - 05/01/2026)
- [ ] Runbook: Como instrumentar aplicações com OpenTelemetry (Node.js, Python, Java)
- [ ] Runbook: Deploy e troubleshooting da plataforma
- [ ] Runbook: Disaster recovery e backups
- [ ] Aplicação exemplo instrumentada (smoke test real)
- [ ] Documentar limites de cardinalidade e políticas de retenção

### Fase 5: Validação e Ajustes (Prazo: 05-10/01/2026)
- [ ] Smoke tests: validar ingestão de métricas/logs/traces
- [ ] Testes de carga básicos (estimar custos reais)
- [ ] Revisão de custos com CTO
- [ ] Ajustar políticas de retenção e sampling conforme necessário
- [ ] Documentar lições aprendidas

## Subtasks (Criadas Dinamicamente)
Serão criadas conforme necessário durante execução das tasks principais.

## Dependências
- Conta AWS com permissões para criar recursos (VPC, EKS, S3, IAM)
- Acesso ao repositório de código e pipeline CI/CD (para integrar módulos Terraform)
- Helm e kubectl para deploys iniciais

## Critérios de Conclusão
- Terraform aplicado com sucesso nos recursos básicos
- Prometheus, Loki, Tempo e Grafana operando em PoC
- Coletores abertos e prontos para receber instrumentação
- Dashboards e alertas iniciais visíveis e testados
- Documentação mínima completa para onboarding de uma aplicação

## Políticas Anti-Alucinação
- Consultar `docs/context/context-generator.md` antes de qualquer ação que altere infra.
- Verificar ADR mais recente antes de mudanças arquiteturais.
- Executar mudanças apenas dentro do escopo autorizado pelo Gestor/CTO.
- Em caso de dúvida técnica ou conflito, acionar a mesa técnica (facilitador + arquiteto + CTO).
