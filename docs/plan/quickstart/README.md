# AWS EKS Quickstart - Documentação Consolidada

**Versão**: 2.0.0
**Data**: 2026-01-07
**Status**: Aprovado para Implementação

---

## 📋 Visão Geral

Este conjunto de documentos define a estratégia completa para implementação de uma plataforma Kubernetes (AWS EKS) com GitLab, Observability e serviços básicos, otimizada para um departamento de TI sem time dedicado de desenvolvedores.

### 🎯 Decisão Estratégica Final

**Arquitetura de 2 Ambientes: Staging + Prod**

Após mesa técnica completa (ver [technical-roundtable.md](technical-roundtable.md)), decidimos por uma arquitetura otimizada que:
- ✅ Reduz custos em 20% (R$ 12.312/ano)
- ✅ Mantém isolamento adequado entre ambientes
- ✅ Permite experimentação segura em Staging
- ✅ Produção dedicada com alta disponibilidade

---

## 📚 Documentos Principais

### 1. **[AWS EKS Quickstart](aws-eks-gitlab-quickstart.md)** 🚀
**Para**: Time terceirizado (implementação)

**Conteúdo**:
- Arquitetura detalhada de 2 ambientes
- 3 Sprints (6 semanas) com Definition of Done
- Helm charts e versões recomendadas
- Diagramas de rede e security groups
- Custos detalhados: **R$ 4.074/mês** (R$ 48.888/ano)

**Use quando**: Precisa implementar a plataforma

---

### 2. **[Mesa Técnica](technical-roundtable.md)** 💼
**Para**: C-Level, Diretoria, Gestores

**Conteúdo**:
- Debate: EC2 vs Kubernetes → **Decisão: Kubernetes**
- Debate: Precisa de Dev? → **Decisão: Não (otimizar custos)**
- Debate: Investir sem devs? → **Decisão: Sim (com capacitação)**
- Budget aprovado: **R$ 113k (ano 1)** + R$ 35k (ano 2)
- ROI esperado: **+89%** (R$ 132k ganho em 2 anos)

**Use quando**: Precisa justificar investimento ou tomar decisões estratégicas

---

### 3. **[Estratégia de Evolução](evolution-strategy.md)** 📈
**Para**: Time interno (futuro), Arquitetos

**Conteúdo**:
- Roadmap de crescimento (5 fases de maturidade)
- Fase 0 → Fase 5: Do quickstart ao Platform Engineering
- Custos evolutivos por fase
- Gatekeepers de transição
- Checklists de validação

**Use quando**: Quer entender como evoluir a plataforma além do quickstart

---

### 4. **[Diagrama Arquitetural](diagrams/gitlab_eks_platform.mmd)** 🎨
**Para**: Todos

**Conteúdo**:
- Visualização completa da arquitetura
- 2 ambientes segregados (Staging verde, Prod vermelho)
- Fluxos de dados e dependências
- Componentes de observability compartilhados

**Use quando**: Precisa visualizar a arquitetura completa

---

### 5. **[Changelog](CHANGELOG.md)** 📝
**Para**: Controle de versão

**Conteúdo**:
- Histórico de mudanças
- v2.0.0: Migração de 3 para 2 ambientes
- Justificativas e impactos
- Próximos passos

**Use quando**: Quer entender evolução da documentação

---

## 💰 Resumo Financeiro

### Custos Mensais (2 Ambientes)

| Ambiente | Recursos | Custo/Mês (BRL) |
|----------|----------|-----------------|
| **Staging** | 2 nodes t3.medium, RDS t3.small, Redis, RabbitMQ | R$ 1.122 |
| **Prod** | 3 nodes t3.large (HA), RDS t3.medium, Redis HA, RabbitMQ cluster | R$ 2.802 |
| **Observability** | Prometheus, Grafana, Loki, Tempo (compartilhado) | R$ 150 |
| **TOTAL** | | **R$ 4.074** |

### Economia vs 3 Ambientes

```
Antes (Dev + Staging + Prod): R$ 5.100/mês = R$ 61.200/ano
Depois (Staging + Prod):       R$ 4.074/mês = R$ 48.888/ano
Economia:                      R$ 1.026/mês = R$ 12.312/ano (-20%)

Com otimização start/stop:     R$ 3.624/mês = R$ 43.488/ano
Economia total:                R$ 1.476/mês = R$ 17.712/ano (-29%)
```

### Investimento Total (2 Anos)

| Item | Ano 1 | Ano 2 | Total |
|------|-------|-------|-------|
| **Infraestrutura** | R$ 18.000 | R$ 20.000 | R$ 38.000 |
| **Implementação** | R$ 50.000 | - | R$ 50.000 |
| **Capacitação** | R$ 25.000 | R$ 5.000 | R$ 30.000 |
| **Suporte** | R$ 20.000 | R$ 10.000 | R$ 30.000 |
| **TOTAL** | **R$ 113.000** | **R$ 35.000** | **R$ 148.000** |

**Retorno Esperado**: R$ 280.000+
**ROI**: +89% (R$ 132.000 de ganho líquido em 2 anos)

---

## 🏗️ Arquitetura Resumida

### Componentes por Ambiente

#### Staging (Testes + Homologação)
```
namespace: staging
├── GitLab CE (testes)
├── GitLab Runners
├── Redis (single instance)
├── RabbitMQ (single instance)
└── RDS PostgreSQL (db.t3.small Multi-AZ)

Uso: 8h/dia útil (automação start/stop possível)
```

#### Prod (Produção)
```
namespace: prod
├── GitLab CE (produção)
├── GitLab Runners (dedicated)
├── Redis HA (Master-Replica + Sentinel)
├── RabbitMQ (cluster mode)
└── RDS PostgreSQL (db.t3.medium Multi-AZ)

Uso: 24/7 alta disponibilidade (3 AZs)
```

#### Observability (Compartilhado)
```
namespace: observability
├── OpenTelemetry Collector (DaemonSet + Gateway)
├── Prometheus + Alertmanager (multi-tenant)
├── Grafana (dashboards staging + prod)
├── Loki (logs - S3 backend)
└── Tempo (traces - S3 backend)

Labels: env=staging ou env=prod (segregação lógica)
```

---

## ⏱️ Timeline de Implementação

### Sprint 1 (2 semanas) - Cluster + GitLab Staging
- Provisionar VPC, EKS cluster, node groups
- Deploy GitLab em namespace staging
- Configurar RDS PostgreSQL staging
- Deploy Redis/RabbitMQ staging

### Sprint 2 (2 semanas) - Observability + GitLab Prod
- Deploy stack de observability completa
- Deploy GitLab em namespace prod
- Configurar RDS PostgreSQL prod
- Deploy Redis/RabbitMQ prod (HA)

### Sprint 3 (2 semanas) - Hardening + DR
- Configurar WAF, IP allowlist, Network Policies
- Implementar RBAC granular
- Testar backups e disaster recovery
- Executar DR Drill obrigatório
- Validação completa e handoff

**Total**: 6 semanas (com 2 engenheiros em paralelo)

---

## ✅ Definition of Success

### Fase 0 - Quickstart Completo (6 semanas)

- [ ] GitLab staging e prod acessíveis via HTTPS
- [ ] 3+ pipelines CI rodando em staging
- [ ] Observability coletando métricas de ambos ambientes
- [ ] Grafana com dashboards staging e prod
- [ ] 1 backup restaurado com sucesso em cada ambiente
- [ ] Network Policies aplicadas e testadas
- [ ] DR Drill executado (RTO < 1h, RPO < 24h)
- [ ] Time treinado (80h de capacitação)

### Fase 1 - Estabilização (3 meses após quickstart)

- [ ] Staging usado regularmente (10+ deploys/mês)
- [ ] Prod estável (zero downtime não planejado)
- [ ] Time interno resolve 70% dos incidentes sozinho
- [ ] 5+ promoções staging → prod bem-sucedidas

### Fase 2 - Autonomia (6-12 meses)

- [ ] Time interno gerencia 90% das operações
- [ ] GitOps implementado (ArgoCD)
- [ ] Novos apps sendo desenvolvidos internamente
- [ ] Redução de 60% em custos com terceiros

---

## 🚨 Riscos e Mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|-------|---------------|---------|-----------|
| Time não absorve conhecimento | Média | Alto | Treinamento intensivo (80h) + suporte escalonado por 12 meses |
| Staging usado inadequadamente | Baixa | Médio | Documentação clara de uso + RBAC restritivo |
| Custos maiores que previstos | Média | Médio | FinOps desde dia 1, alertas de custo, budget mensal |
| Falha de implementação | Baixa | Crítico | Gates de validação a cada 3 meses, opção de abort |

---

## 📞 Suporte e Escalação

### Durante Implementação (Sprint 1-3)
- **Terceirizado**: Responsável 100%
- **Time interno**: Shadowing e aprendizado
- **SLA**: 24/7 durante sprints

### Pós-Implementação (Mês 4-12)
- **Mês 4-6**: Terceirizado (70%) + Time interno (30%)
- **Mês 7-9**: Terceirizado (30%) + Time interno (70%)
- **Mês 10-12**: Time interno (90%) + Consultoria pontual (10%)
- **SLA**: 4h (mês 4-6) → 8h (mês 7-12)

### Ano 2+
- **Time interno**: 95%+ autonomia
- **Consultoria**: Apenas para arquitetura/evolução
- **SLA**: Best-effort, por demanda

---

## 🎓 Plano de Capacitação

### Treinamento Obrigatório (Ano 1)

**3 pessoas do time (2 infra + 1 DBA)**:

| Treinamento | Duração | Custo | Quando |
|-------------|---------|-------|--------|
| Kubernetes Foundation (CKF) | 40h | R$ 3.000/pessoa | Mês 1-2 |
| Hands-on com terceirizado | 60h | R$ 10.000/pessoa | Mês 1-3 |
| GitOps + Helm avançado | 20h | R$ 2.000/pessoa | Mês 4-5 |
| Observability (Prometheus/Grafana) | 16h | R$ 1.500/pessoa | Mês 5-6 |
| **Opcional**: CKA Certification | 80h preparo | R$ 5.000 (1 pessoa) | Mês 6-12 |

**Total**: R$ 25.000 (ano 1) + R$ 5.000 (ano 2 - atualização)

---

## 🔄 Quando Adicionar Ambiente Dev?

**Considere adicionar Dev SE**:

- ✅ Time crescer para 5+ desenvolvedores
- ✅ 15+ deploys/dia em staging
- ✅ >3 quebras/mês em staging por experimentação
- ✅ Conflitos frequentes de uso de staging

**Custo incremental**: ~R$ 1.000/mês (R$ 12.000/ano)

**Implementação**: Ver [evolution-strategy.md - Fase 1](evolution-strategy.md) para migration path sem downtime

---

## 📚 Leitura Recomendada por Persona

### Para C-Level / Diretoria
1. ⭐ [Mesa Técnica](technical-roundtable.md) - Decisões e ROI
2. Este README (visão geral)
3. [Seção de Custos do Quickstart](aws-eks-gitlab-quickstart.md#estimativa-de-custos-2-ambientes-staging--prod)

### Para Time de Implementação (Terceirizado)
1. ⭐ [AWS EKS Quickstart](aws-eks-gitlab-quickstart.md) - Guia completo
2. [Diagrama Arquitetural](diagrams/gitlab_eks_platform.mmd)
3. [Changelog](CHANGELOG.md) - Últimas mudanças

### Para Time Interno (Futuro)
1. ⭐ [Estratégia de Evolução](evolution-strategy.md) - Roadmap futuro
2. [AWS EKS Quickstart](aws-eks-gitlab-quickstart.md) - Fundação
3. [Mesa Técnica](technical-roundtable.md) - Contexto das decisões

### Para Arquitetos
1. ⭐ [Estratégia de Evolução](evolution-strategy.md) - Fases de maturidade
2. [Diagrama Arquitetural](diagrams/gitlab_eks_platform.mmd)
3. [Mesa Técnica - Questão 1](technical-roundtable.md#questão-1-por-que-não-usar-ec2-simples-ao-invés-de-kubernetes) - Comparativo técnico

---

## 🎯 Próximas Ações Imediatas

### Esta Semana
- [ ] **C-Level**: Revisar e aprovar [technical-roundtable.md](technical-roundtable.md)
- [ ] **Financeiro**: Aprovar budget de R$ 113.000 (ano 1)
- [ ] **TI**: Definir 3 pessoas para capacitação

### Próximas 2 Semanas
- [ ] **Compras**: Abrir RFP para terceirizado
- [ ] **TI**: Configurar acessos AWS (IAM, billing)
- [ ] **Terceirizado**: Inscrever time em treinamento Kubernetes Foundation

### Mês 1
- [ ] **Kick-off**: Sprint 0 + início da capacitação
- [ ] **Implementação**: Sprint 1 (cluster + GitLab staging)
- [ ] **Capacitação**: 40h de treinamento formal

---

**Status**: ✅ Documentação completa e aprovada
**Próximo milestone**: Aprovação executiva + seleção de fornecedor
**Dúvidas**: Consultar arquiteto responsável

---

**Última atualização**: 2026-01-07
**Versão**: 2.0.0
