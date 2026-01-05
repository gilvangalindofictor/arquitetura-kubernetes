# Pauta: Mesa Técnica — Fundação de Observabilidade

**Objetivo da reunião**
Alinhar decisões críticas para provisionamento da fundação de observabilidade na AWS (PoC), priorizando portabilidade cloud-agnostic, baixo custo e operacionalidade.

**Duração sugerida**: 90 minutos

**Participantes recomendados**
- CTO (decisor)
- Arquiteto sênior (responsável técnico)
- SRE/DevOps lead
- Representante de desenvolvimento (dev lead)
- Facilitador / anotador (pode ser o Gestor)

**Pré-leituras (obrigatórias)**
- `docs/context/context-generator.md`
- `docs/adr/adr-001-decisoes-iniciais.md`
- `docs/plan/execution-plan.md`

---

## Agenda (90 min)

1. Abertura e objetivos da mesa (5 min)
   - Alinhar expectativas e resultados esperados.

2. Modelo de contas AWS e isolamento por ambiente (20 min)
   - Opções: conta por ambiente vs conta única com roles/OUs.
   - Decisão requerida: qual modelo adotar provisoriamente para PoC.
   - Artefatos necessários: lista de permissões, diagramas mínimos de conta/OU.

3. Estratégia de topologia (centralizada vs por-ambiente) (15 min)
   - Impactos em custo, segurança e escalabilidade.
   - Decisão requerida: centralizar observability (único cluster) ou provisionar por ambiente.

4. Orquestração e compute (EKS vs ECS vs EC2) (10 min)
   - Restrições operacionais e skill da equipe.
   - Decisão requerida: escolher stack inicial para PoC (EKS recomendado, mas discutir).

5. Armazenamento de longo prazo e retenção (S3 + Thanos/remote-write) (10 min)
   - Políticas de retenção sugeridas e limites de cardinalidade.
   - Decisão requerida: política inicial de retenção e mecanismo de long-term storage.

6. Stack de observabilidade (confirmação final) (10 min)
   - Confirmação: Prometheus, Grafana, Loki, Tempo/Jaeger, OpenTelemetry Collector.
   - Confirmação de versões/helm charts ou imagens preferenciais.

7. Controles de custo e observabilidade do próprio stack (10 min)
   - Guardrails: budgets, alertas de custo, compressão/ingest filters.
   - Decisão requerida: limites iniciais e responsáveis por monitoramento de custo.

8. Integração CI/CD e IaC (Terraform) — pipeline de deploy (5 min)
   - Definir responsável e passos mínimos (PR → review → terraform plan/apply controlado).

9. Próximos passos, responsáveis e prazos (5 min)
   - Validar owner para cada decisão e prazo para PoC mínimo (ex: 2-4 semanas).

---

## Itens de decisão (resumo com critérios de aceitação)
- **Modelo de contas AWS**: Aceito quando existir diagrama de contas/OUs e lista de permissions para PoC.
- **Topologia (centralizada vs por-ambiente)**: Aceito quando trade-offs documentados e plano de rollback.
- **Compute (EKS/ECS/EC2)**: Aceito quando for apontado owner da stack e lista de runbooks iniciais.
- **Retenção / long-term storage**: Aceito quando existir política de retenção e custo estimado básico.
- **Stack final**: Aceito quando houver consenso e lista de helm charts/imagens.

## Artefatos a produzir durante/apos a mesa
- Diagrama de contas AWS (simples)
- Decisão ADR atualizada (adicionar ADR002 com decisões da mesa)
- Lista de tarefas do PoC (módulos Terraform iniciais, scripts de bootstrap)
- Papel e responsabilidade (RACI) para deploy e operação inicial

## Preparação do meeting owner (Checklist)
- Enviar pré-leituras 48h antes
- Preparar estimativas rápidas de custo para retenção/ingest (ex.: logs 7d, metrics 15d)
- Ter exemplos de políticas IAM mínimas para deploy PoC

## Sugestão de outcomes por 48h
- ADR atualizado com decisões principais
- Issues / tasks no repo para cada módulo Terraform
- Agenda de follow-up (deploy PoC e validações de ingest)

---

## Modelo de nota/minutos (a preencher durante a reunião)
- Data:
- Participantes:
- Decisões tomadas:
- Ações e responsáveis (owner, prazo):

---

Se quiser, eu gero agora um e-mail/template de convite com o texto pré-preenchido para enviar aos participantes e crio a `docs/adr/adr-002-mesa-tecnica.md` placeholder para registrar as decisões imediatamente após a reunião.
