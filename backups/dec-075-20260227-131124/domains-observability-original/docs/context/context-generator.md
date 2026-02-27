# Context Generator

## Missão do Projeto
Implementar a fundação de uma plataforma de observabilidade na AWS (cloud inicial) com ferramentas open source e arquitetura cloud-agnostic, pronta para receber instrumentação de aplicações futuras nos ambientes `dev`, `hml` e `prd`.

## Escopo
- Provisionamento inicial de infraestrutura observability-ready na AWS via IaC (Terraform).
- Stack open source: Prometheus (métricas), Loki (logs), Tempo/Jaeger (traces), Grafana (visualização), OpenTelemetry Collector (recepção/roteamento).
- Configuração de pipelines básicos (métricas → long-term storage/exporter, logs → Loki, traces → Tempo).
- Dashboards e alertas iniciais para SREs e desenvolvedores.
- Documentação e runbooks para instrumentação por equipes de desenvolvimento.

## Não-Escopo
- Instrumentação automática das aplicações existentes (será feita pelas equipes quando as aplicações nascerem).
- Operação 24/7 (não implementaremos rotinas de on-call neste primeiro momento).
- Migração de sistemas legados fora da AWS.

## Usuários-Alvo
- Desenvolvedores (consumo de métricas, logs e traces das suas aplicações)
- SREs / DevOps (gestão da plataforma, alertas e runbooks)
- Arquitetos e CTO (visão estratégica e decisões de adoção)

## Restrições
- Orçamento: custo zero/minimizado — priorizar componentes open source e configurações de baixo custo.
- Plataforma inicial: AWS (mas projetar para portabilidade entre clouds).
- Equipe dedicada somente no futuro — projetar para manutenção simples e documentação clara.

## Regras Permanentes
- Sempre consultar ADRs antes de tomar decisões infraestruturais.
- Só gerar subtasks justificadas e com impacto claro.
- Nunca trabalhar sem contexto validado pelo Gestor/CTO.
- Não extrapolar escopo sem autorização da mesa técnica.

## Premissas
- A equipe terá acesso total à AWS.
- Aplicações futuras seguirão OpenTelemetry para instrumentação.
- Sem SLA de disponibilidade mínimo nesta fase inicial.

## Stack e Tecnologias (se aplicável)
- **Estratégia Central**: OpenTelemetry Collector como hub central de ingestão, processamento e roteamento de todos os sinais (métricas, logs, traces). Isso garante portabilidade e evita vendor lock-in.
- **Observability Backends**: Prometheus, Grafana, Loki, Tempo/Jaeger
- **Instrumentação**: OpenTelemetry SDKs
- **Infraestrutura**: Terraform, módulos reutilizáveis
- **Orquestração**: Kubernetes (EKS) preferencial, mas agnóstico
- **Ferramentas auxiliares**: Grafana Agent, Alertmanager, Prometheus Operator

## Critérios de Sucesso
- Infraestrutura provisionada via Terraform na AWS (baseline).
- Collectors configurados e prontos para receber métricas/logs/traces.
- Dashboards básicos no Grafana visíveis para SREs e desenvolvedores.
- Documentação `/docs` criada e runbooks iniciais disponíveis.

## Riscos Identificados
- Custo inesperado com volume de dados (logs, métricas, traces).
- Complexidade de manutenção do stack open source.
- Falta de expertise inicial na equipe para operar todas as ferramentas.
