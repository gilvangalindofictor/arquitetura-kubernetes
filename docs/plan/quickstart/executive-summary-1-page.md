# AWS EKS Platform — Resumo Executivo (1 Página)

**Para:** CTO | **Data:** 2026-01-15 | **Decisão:** Aprovação de recursos

---

## Proposta

Implantação de plataforma Kubernetes AWS EKS com GitLab CI/CD, observability completa e segurança enterprise-grade.

**Arquitetura:** 2 ambientes (Staging + Prod) | **Timeline:** 6 semanas | **Time:** Interno (262h)

---

## Investimento

| Item | Valor |
|------|-------|
| **Implantação (one-time)** | R$ 2.000 - R$ 3.000 |
| **Operação mensal** | R$ 3.624 |
| **Ano 1 TOTAL** | **R$ 45.488 - R$ 46.488** |
| **Anos subsequentes** | R$ 43.488/ano |

**⚠️ Disclaimer:** Valores baseados em cotação USD→BRL R$ 6,00 e preços AWS atuais (jan/2026). Variação esperada: ±10-15% devido a flutuação cambial e ajustes de preços AWS.

---

## Estratégia de Custo: Staging com Automação

**Decisão:** Como o time trabalha em **horário comercial** (seg-sex, 8h-18h), o Staging será configurado para **desligar automaticamente** fora desse período.

**Schedule:**
- **Ligado:** Segunda a sexta, 8h-18h (50h/semana)
- **Desligado:** Noites (18h-8h) + finais de semana
- **Inicialização:** ~10-15 minutos às 8h (automático)

**Economia:** R$ 5.400/ano vs Staging rodando 24/7

**O que é desligado:**
- EC2 nodes (VMs do Kubernetes): -70% custo
- RDS PostgreSQL: Auto-pause (-50% custo)
- Redis/RabbitMQ: Pods scaled to 0

**Dados preservados:** 100% dos dados mantidos em volumes persistentes (EBS)

---

## ROI e Economia

| Métrica | Valor |
|---------|-------|
| **Economia vs 3 ambientes** | -29% (R$ 17.712/ano) |
| **Economia projetada (3 anos)** | R$ 16.200 |
| **Com Savings Plans** | +R$ 19.000 adicional |

**Benefícios:**
- Deploy automatizado (minutos vs horas)
- Observability proativa (redução de incidentes)
- Auto-scaling (crescimento sem downtime)
- Security compliance (WAF, encryption, RBAC)

---

## Timeline (3 Sprints × 2 semanas)

| Sprint | Entregáveis |
|--------|-------------|
| **1** | VPC Multi-AZ, EKS, GitLab, RDS, Redis, RabbitMQ |
| **2** | Prometheus, Grafana, Loki, Tempo, Dashboards |
| **3** | WAF, NetworkPolicies, Backups, **DR Drill** |

**Critérios de sucesso:** GitLab funcional, observability completa, DR testado (RTO < 1h)

---

## Decisão Solicitada

✅ **Aprovar R$ 45.488 - R$ 46.488 (Ano 1)** para implantação

**Requisitos:**
- [ ] Orçamento aprovado (R$ 2-3k implantação + R$ 43.488/ano operação)
- [ ] Alocação: 2 engenheiros internos × 6 semanas
- [ ] Credenciais AWS (VPC, EKS, RDS, S3, IAM)
- [ ] Domínio corporativo para GitLab
- [ ] IPs corporativos para allowlist (WAF)

---

**Documentação completa:** [executive-summary-cto.md](executive-summary-cto.md) | [aws-eks-gitlab-quickstart.md](aws-eks-gitlab-quickstart.md)
