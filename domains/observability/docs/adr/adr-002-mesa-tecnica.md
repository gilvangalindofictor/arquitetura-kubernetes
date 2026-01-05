# ADR 002 – Decisões da Mesa Técnica

> **Status**: Superseded by SAD Corporativo (`/SAD/docs/sad.md` v1.0)
> **Migrado para**: Domínio da Plataforma Corporativa Kubernetes
> **Conformidade**: Ver ADR-003 (Validação contra SAD)

## Reunião
- Data: 08 de Dezembro de 2025
- Participantes: CTO (Gilvan Galindo), Arquiteto Sênior (simulado), SRE Lead (simulado), Dev Lead (simulado)
- Facilitador / Anotador: Agente Gestor

**Nota**: Este ADR foi criado quando observability era projeto independente. Decisões conflitantes com o SAD devem seguir o SAD como fonte suprema.

## Objetivo da reunião
Registrar decisões críticas para provisionamento da fundação de observabilidade (PoC) na AWS, conforme pauta em `docs/plan/mesa-tecnica-pauta.md`.

## Itens discutidos e decisões

### 1. Modelo de contas AWS e isolamento por ambiente
**Decisão:** Conta AWS única com isolamento por namespace Kubernetes + IAM roles por ambiente (dev/hml/prd).

**Rationale / justificativa:**
- Para PoC e fase inicial, múltiplas contas AWS aumentariam complexidade operacional sem time dedicado.
- Kubernetes namespaces oferecem isolamento suficiente (network policies, resource quotas, RBAC).
- IAM roles com IRSA (IAM Roles for Service Accounts) garantem separação de permissões por ambiente.
- Migração futura para contas separadas é viável sem retrabalho significativo nos módulos Terraform.

**Artefatos produzidos:** 
- Diagrama de arquitetura lógica será criado em `docs/infra/arquitetura-logica.md`
- Políticas IAM mínimas em `infra/terraform/iam-policies/`

### 2. Topologia: centralizada vs por-ambiente
**Decisão:** Topologia **centralizada** — um único cluster EKS com namespaces separados (observability-dev, observability-hml, observability-prd).

**Rationale:**
- Reduz custos operacionais significativamente (1 control plane vs 3).
- Facilita manutenção com equipe pequena/inexistente inicialmente.
- Namespaces Kubernetes + network policies garantem isolamento adequado para PoC.
- Permite compartilhamento de recursos (Grafana único com folders por ambiente).

**Impactos:**
- **Custo:** Redução estimada de 60% vs 3 clusters separados.
- **Segurança:** Mitigado com RBAC, network policies e service mesh (futuro).
- **Escalabilidade:** Suficiente para dezenas de aplicações; revisitar após crescimento significativo.

### 3. Orquestração e compute (EKS/ECS/EC2)
**Decisão:** **Amazon EKS** (Kubernetes) como plataforma de orquestração.

**Rationale:**
- Kubernetes é padrão de mercado para workloads de observabilidade (Prometheus Operator, Grafana Operator).
- Facilita portabilidade cloud-agnostic (charts Helm são reutilizáveis em GKE, AKS).
- Comunidade open source ativa com charts maduros.
- Equipe já tem conhecimento básico de Kubernetes.

**Runbooks necessários:**
- Setup inicial EKS via Terraform
- Deploy via Helm/kubectl
- Troubleshooting básico (pods, logs, eventos)

### 4. Armazenamento de longo prazo e retenção
**Decisão:** S3 como backend de long-term storage + políticas de lifecycle.

**Política inicial:**
- **Métricas:** 15 dias no Prometheus (local), 90 dias no S3 (via Thanos ou remote write para Cortex — decisão postergada para fase 2).
- **Logs:** 7 dias no Loki (local), 30 dias no S3.
- **Traces:** 7 dias no Tempo (local), sem long-term storage inicialmente (traces são volumosos).

**Estimativa de custo (rápida):**
- Assumindo ~10 aplicações com instrumentação média:
  - Métricas: ~5GB/dia → S3 ~$3/mês
  - Logs: ~20GB/dia → S3 ~$12/mês
  - Storage local (EBS): ~$30/mês
  - **Total estimado:** ~$50-80/mês para storage (sem compute EKS)

### 5. Confirmação do stack (Prometheus, Grafana, Loki, Tempo, OpenTelemetry Collector)
- **Estratégia Central**: OpenTelemetry Collector em modo gateway como hub central de ingestão, processamento e roteamento de todos os sinais. Isso garante portabilidade e flexibilidade para trocar backends no futuro.
- **Stack confirmado com versões estáveis**: Prometheus, Grafana, Loki, Tempo.

**Observações:**
- Usar Prometheus Operator para gerenciamento declarativo de métricas.
- Grafana como single pane of glass (datasources: Prometheus, Loki, Tempo).
- OpenTelemetry Collector em modo gateway (recebe de apps, roteia para backends).

**Versões / Charts preferenciais:**
- `kube-prometheus-stack` (Helm chart, versão ~55.x)
- `grafana/loki` (Helm chart, versão ~5.x)
- `grafana/tempo` (Helm chart, versão ~1.x)
- `open-telemetry/opentelemetry-collector` (Helm chart, versão ~0.80.x)

### 6. Controles de custo e guardrails
**Decisão:** Implementar budgets AWS + alertas de custo + limites de cardinalidade.

**Guardrails:**
- AWS Budget alert: $200/mês (threshold de 80% e 100%).
- Limites de cardinalidade no Prometheus: max 1M séries temporais.
- Limites de ingest no Loki: max 50GB/dia.
- Sampling de traces: 10% de amostragem inicial (ajustável).

**Responsáveis por monitoramento de custo:**
- SRE Lead (quando disponível) + CTO (oversight mensal).

### 7. Integração CI/CD e IaC
**Decisão:** Terraform para IaC + GitHub Actions para CI/CD (ou GitLab CI conforme preferência).

**Owner pipeline Terraform:** Dev Lead (transição para SRE quando disponível).

**Processo de deploy aprovado:**
1. PR com mudanças Terraform
2. `terraform plan` automático no CI
3. Review obrigatório (Arquiteto ou CTO)
4. `terraform apply` manual/aprovado em ambiente controlado
5. Validação pós-deploy (smoke tests)

## Alternativas consideradas (resumo)

### Múltiplas contas AWS vs conta única
- **Rejeitado:** Múltiplas contas aumentam overhead operacional sem ganho significativo para PoC.
- **Aceito:** Conta única com IAM roles + namespaces Kubernetes.

### ELK vs Loki para logs
- **Rejeitado:** ELK (Elasticsearch) tem custo operacional mais alto e complexidade de manutenção.
- **Aceito:** Loki por simplicidade, baixo custo e integração nativa com Grafana.

### Jaeger vs Tempo para traces
- **Aceito:** Tempo (mais novo, integração direta com Grafana, storage em S3 nativo).
- **Alternativa:** Jaeger pode ser considerado se requisitos de UI específica surgirem.

## Consequências / Notas de risco

### Riscos identificados:
1. **Custo de storage S3 pode crescer rapidamente** com aumento de volume → Mitigação: alertas de custo + revisão trimestral de retenção.
2. **Cluster EKS único é ponto de falha** → Mitigação: backups regulares de configurações, runbook de disaster recovery.
3. **Falta de expertise em Kubernetes pode gerar incidentes** → Mitigação: documentação extensiva, runbooks, treinamento básico da equipe.

### Consequências positivas:
- Stack moderno e cloud-agnostic posiciona bem a empresa para crescimento.
- Baixo custo inicial permite validação de valor antes de investimento maior.
- Comunidade open source oferece suporte e evolução contínua.

## Ações / Próximos passos (com responsáveis e prazos)

- [ ] Criar módulos Terraform para VPC, EKS, S3, IAM — Owner: Dev Lead — Prazo: 15/12/2025
- [ ] Provisionar cluster EKS em ambiente dev — Owner: Dev Lead — Prazo: 18/12/2025
- [ ] Deploy PoC: Prometheus, Grafana, Loki, Tempo via Helm — Owner: Dev Lead — Prazo: 20/12/2025
- [ ] Configurar OpenTelemetry Collector (gateway mode) — Owner: Arquiteto — Prazo: 22/12/2025
- [ ] Criar dashboards básicos (Golden Signals) — Owner: SRE Lead — Prazo: 27/12/2025
- [ ] Documentar runbook de instrumentação para devs — Owner: Arquiteto — Prazo: 30/12/2025
- [ ] Aplicação exemplo com instrumentação OpenTelemetry — Owner: Dev Lead — Prazo: 03/01/2026
- [ ] Configurar alertas básicos (Alertmanager) — Owner: SRE Lead — Prazo: 05/01/2026
- [ ] Revisão de custos inicial (após 2 semanas rodando) — Owner: CTO — Prazo: 10/01/2026

## Artefatos gerados
- Diagrama de arquitetura lógica: `docs/infra/arquitetura-logica.md` (a criar)
- Módulos Terraform: `infra/terraform/modules/{vpc,eks,s3,iam}` (a criar)
- Tasks/Issues: Registradas no backlog do projeto

## Aprovação
- Decisão tomada por: CTO (Gilvan Galindo)
- Data de aprovação: 08 de Dezembro de 2025

---

> Instruções rápidas: preencha as decisões durante a reunião e, imediatamente após, atualize `docs/adr/adr-002-mesa-tecnica.md` com justificativas e mova as ações para o backlog/issue tracker com owners e prazos.
