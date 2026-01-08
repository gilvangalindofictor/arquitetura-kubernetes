# Changelog - AWS EKS Quickstart

## [2.0.0] - 2026-01-07

### 🎯 Decisão Estratégica: Arquitetura de 2 Ambientes

Após análise técnica e financeira documentada em [technical-roundtable.md](technical-roundtable.md), decidimos por uma **arquitetura de 2 ambientes (Staging + Prod)**, removendo o ambiente Dev dedicado.

### ✅ Mudanças Principais

#### Arquitetura
- **REMOVIDO**: Ambiente Dev dedicado
- **ADICIONADO**: Staging assume papel dual (testes + homologação)
- **MANTIDO**: Prod dedicado com alta disponibilidade

#### Namespaces
```diff
- namespace: dev         (REMOVIDO)
- namespace: app-default (REMOVIDO)
+ namespace: staging     (NOVO - testes + homologação)
+ namespace: prod        (NOVO - produção)
  namespace: observability (compartilhado entre staging e prod)
  namespace: kube-system (sistema)
```

#### Infraestrutura
- **RDS PostgreSQL**: 2 instâncias (1 staging db.t3.small, 1 prod db.t3.medium)
- **Redis**: 2 deployments (staging básico, prod HA com Sentinel)
- **RabbitMQ**: 2 deployments (staging single-node, prod cluster)
- **GitLab**: 2 instalações (staging compartilhada, prod dedicada)

#### Custos Atualizados

| Componente | Antes (3 ambientes) | Depois (2 ambientes) | Economia |
|------------|---------------------|----------------------|----------|
| **Mensal** | R$ 5.100 | R$ 4.074 | **-R$ 1.026 (-20%)** |
| **Anual** | R$ 61.200 | R$ 48.888 | **-R$ 12.312 (-20%)** |

**Com otimizações de start/stop em Staging**:
- Custo otimizado: **R$ 3.624/mês** (R$ 43.488/ano)
- Economia adicional: **R$ 450/mês** (R$ 5.400/ano)
- **Economia total vs 3 ambientes**: **R$ 1.476/mês** (R$ 17.712/ano) = **-29%**

### 📊 Documentos Atualizados

#### 1. [aws-eks-gitlab-quickstart.md](aws-eks-gitlab-quickstart.md)
- ✅ Seção "Decisões chave" atualizada
- ✅ "Componentes Principais" reflete 2 ambientes
- ✅ Custos recalculados com breakdown detalhado
- ✅ Tabela comparativa 2 vs 3 ambientes
- ✅ Seção "Observações" atualizada com uso de Staging
- ✅ Link para mesa técnica de decisão

#### 2. [diagrams/gitlab_eks_platform.mmd](diagrams/gitlab_eks_platform.mmd)
- ✅ Diagrama completamente redesenhado
- ✅ Namespace `staging` em verde (testes)
- ✅ Namespace `prod` em vermelho (produção)
- ✅ Namespace `observability` em azul (compartilhado)
- ✅ 2 instâncias RDS separadas visíveis
- ✅ Redis/RabbitMQ segregados por namespace
- ✅ Labels de telemetria multi-tenant (env=staging/prod)

#### 3. [technical-roundtable.md](technical-roundtable.md) - NOVO
- ✅ Simulação completa de mesa técnica
- ✅ Debate: EC2 vs Kubernetes (Decisão: K8s)
- ✅ Debate: Precisa de Dev? (Decisão: Não, otimizar custo)
- ✅ Debate: Investir sem devs? (Decisão: Sim, com capacitação)
- ✅ Análise de ROI detalhada
- ✅ Budget aprovado: R$ 113k (ano 1) + R$ 35k (ano 2)
- ✅ ROI esperado: +89% (R$ 132k ganho em 2 anos)

#### 4. [evolution-strategy.md](evolution-strategy.md) - NOVO
- ✅ Roadmap de evolução completo (5 fases)
- ✅ Custos evolutivos por fase
- ✅ Gatekeepers de transição
- ✅ Checklists de validação
- ✅ Exemplos práticos de código

### 🎯 Justificativa da Decisão

#### Por que remover Dev?

**Análise de Custo-Benefício**:
- Time atual: 2 analistas infra, 1 DBA, 0 desenvolvedores dedicados
- Uso previsto de Dev: <20% do tempo (baixa utilização)
- Staging pode servir como ambiente de testes
- Economia: R$ 12.312/ano

**Quando Staging NÃO é suficiente**:
- Se time crescer para 5+ desenvolvedores
- Se houver 10+ deploys/dia
- Se experimentação causar >3 quebras/mês em staging
- **Neste caso**: Adicionar Dev novamente (custo incremental ~R$ 1.000/mês)

#### Por que manter 2 ambientes (não apenas 1)?

**Isolamento é crítico**:
- Testes em staging não afetam prod
- Validação de upgrades sem risco
- POCs e experimentações seguras
- DR drill sem impacto em prod
- Custo marginal: Apenas R$ 1.122/mês para staging

### 📋 Próximos Passos

1. **Aprovação Executiva**
   - [ ] Apresentar [technical-roundtable.md](technical-roundtable.md) para C-Level
   - [ ] Obter budget approval: R$ 113k (ano 1)

2. **Revisão de Documentação**
   - [x] Quickstart atualizado com 2 ambientes
   - [x] Diagramas atualizados
   - [x] Custos recalculados
   - [ ] Executar validação técnica com time terceirizado

3. **Implementação** (seguir [aws-eks-gitlab-quickstart.md](aws-eks-gitlab-quickstart.md))
   - Sprint 1: Cluster + GitLab staging
   - Sprint 2: Observability + GitLab prod
   - Sprint 3: Hardening + DR Drill

### 🔗 Referências

- [AWS EKS Quickstart](aws-eks-gitlab-quickstart.md) - Plano de implementação
- [Mesa Técnica](technical-roundtable.md) - Análise de decisões
- [Estratégia de Evolução](evolution-strategy.md) - Roadmap futuro
- [Diagrama Arquitetural](diagrams/gitlab_eks_platform.mmd) - Arquitetura visual

---

## [1.0.0] - 2026-01-06

### Versão Inicial
- Quickstart com 3 ambientes (Dev + Staging + Prod)
- Custos estimados: R$ 5.100/mês
- Diagramas conceituais
- Épicos e sprints definidos
