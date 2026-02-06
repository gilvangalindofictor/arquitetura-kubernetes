# Architecture Template

> **Responsabilidade**: AI (agente architect) com aprovação do usuário
> **Quando atualizar**: Após decisões arquiteturais significativas
> **Prioridade de leitura**: 2

---

## Visão Arquitetural

**Estilo Arquitetural**: [Monolito / Microservices / Serverless / Event-Driven / etc.]

**Princípios**:
- [Ex: Cloud-agnostic via Kubernetes operators]
- [Ex: Infrastructure as Code obrigatório]
- [Ex: Stateless quando possível, stateful isolado]

---

## Componentes Principais

### [Nome do Componente 1]

**Responsabilidade**: [O que faz]

**Tecnologia**: [Tecnologia/Framework usado]

**Dependências**:
- [Componente A]: [Para que usa]
- [Componente B]: [Para que usa]

**Deployment**: [Como é deployado - pod, statefulset, managed service, etc.]

**Observabilidade**:
- Logs: [Onde/como]
- Métricas: [Quais]
- Traces: [Se aplicável]

---

### [Nome do Componente 2]

[Repetir estrutura acima]

---

## Diagrama de Alto Nível

```
[Diagrama ASCII ou referência para .drawio / imagem]

┌─────────────┐       ┌─────────────┐
│   Client    │──────▶│   API GW    │
└─────────────┘       └─────────────┘
                            │
                            ▼
                      ┌──────────┐
                      │ Services │
                      └──────────┘
                            │
                            ▼
                      ┌──────────┐
                      │ Database │
                      └──────────┘
```

**Referências**:
- [Link para diagramas detalhados]
- [Link para documentação de sequência]

---

## Fluxos Críticos

### [Fluxo 1: Ex: Autenticação]

1. Usuário envia credenciais para `/auth/login`
2. API valida contra Keycloak
3. Token JWT retornado
4. Cliente usa token em header `Authorization: Bearer ...`

**Segurança**:
- Tokens expiram em 1h
- Refresh token disponível por 24h
- Rate limit: 5 req/min por IP

---

### [Fluxo 2: Ex: Deploy de Aplicação]

[Descrever fluxo]

---

## Dados

### Armazenamento

| Tipo de Dado        | Onde               | Por quê             |
| ------------------- | ------------------ | ------------------- |
| Configuração        | ConfigMaps/Secrets | Deploy-time config  |
| Secrets             | Vault + ESO        | Segurança           |
| Estado da aplicação | PostgreSQL         | ACID guarantees     |
| Logs                | Loki               | Agregação           |
| Métricas            | Prometheus         | Observabilidade     |
| Traces              | Tempo              | Distributed tracing |

### Schemas Principais

**[Nome da Tabela/Collection 1]**:
- Chave: [Tipo]
- Campos críticos: [Lista]
- Relacionamentos: [Com quais outras]

---

## Rede

**Segmentação**:
- VPC/VNET: [CIDR]
  - Subnet pública: [CIDR] - [O que vai aqui]
  - Subnet privada: [CIDR] - [O que vai aqui]
  - Subnet de dados: [CIDR] - [O que vai aqui]

**Segurança**:
- Network Policies: [Regras principais]
- Security Groups: [Regras principais]
- Ingress: [Como funciona]

---

## Escalabilidade

**Horizontal**:
- [Componente X]: HPA com target 70% CPU
- [Componente Y]: KEDA event-driven

**Vertical**:
- [Componente Z]: Vertical Pod Autoscaler

**Limites**:
- [Componente A]: Máximo 10 réplicas (limitação de licença)

---

## Resilência

**Alta Disponibilidade**:
- [Componente X]: Multi-AZ deployment
- [Componente Y]: StatefulSet com 3 réplicas

**Backup & DR**:
- RPO: [Ex: 15 minutos]
- RTO: [Ex: 1 hora]
- Backup: [Frequência e retenção]
- DR Plan: [Link ou resumo]

**Circuit Breakers**:
- [Onde implementados]

---

## Segurança

**Autenticação**:
- [Mecanismo usado - OAuth, mTLS, etc.]

**Autorização**:
- [RBAC, ABAC, policies]

**Encriptação**:
- Em trânsito: TLS 1.2+
- Em repouso: [Mecanismo]

**Secrets Management**:
- [Vault, AWS Secrets Manager, etc.]

---

## Observabilidade

**Stack**:
- Logs: Loki
- Métricas: Prometheus + Grafana
- Traces: Tempo
- Alertas: Alertmanager

**Dashboards Principais**:
- [Nome]: [O que mostra]
- [Nome]: [O que mostra]

**Alertas Críticos**:
- [Nome]: [Condição] → [Ação]

---

## Trade-offs e Decisões Arquiteturais

[Referência para ADRs ou documentação inline]

### [Decisão 1: Ex: PostgreSQL managed vs operator]

**Contexto**: [Situação que levou à decisão]

**Decisão**: [O que foi decidido]

**Consequências**:
- ✅ [Benefício 1]
- ✅ [Benefício 2]
- ⚠️ [Trade-off 1]
- ⚠️ [Trade-off 2]

---

## Evolução Futura

**Próximos Passos**:
- [ ] [Ex: Migrar de managed services para operators]
- [ ] [Ex: Implementar service mesh]

**Dívida Técnica Conhecida**:
- [Item 1]: [Impacto e quando resolver]
- [Item 2]: [Impacto e quando resolver]

---

_Última atualização: YYYY-MM-DD_
