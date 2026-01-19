# Premissas e Cálculos de Custo AWS EKS

**Documento:** Detalhamento de premissas financeiras para transparência e auditoria
**Data:** 2026-01-15
**Última revisão:** 2026-01-15

---

## 1. Premissas Gerais

### Cotação e Região

| Parâmetro | Valor Adotado | Observações |
|-----------|---------------|-------------|
| **Cotação USD → BRL** | R$ 6,00 | Referência: jan/2026. Sujeito a variação cambial |
| **Região AWS** | us-east-1 (N. Virginia) | Região com menores custos na AWS |
| **Modelo de precificação** | On-demand | Sem commitment (Savings Plans ou Reserved Instances) |
| **Período de cálculo** | 730 horas/mês | Média mensal (365 dias ÷ 12 meses × 24h) |

### Variações Esperadas

| Fator | Impacto Estimado | Mitigação |
|-------|------------------|-----------|
| **Flutuação cambial** | ±5-10% mensal | AWS Budgets com margem 10% + revisão mensal |
| **Ajuste de preços AWS** | ±2-5% anual | Monitorar AWS Price List API + notificações |
| **Data transfer out** | +5-10% custo total | Estimado mas não incluído (varia por uso) |
| **Crescimento de storage** | +2-3% trimestral | Revisão de retenção de logs/backups |

---

## 2. Detalhamento de Custos por Recurso

### EKS Control Plane

| Item | Valor USD | Valor BRL | Base de Cálculo |
|------|-----------|-----------|-----------------|
| **EKS Cluster** | $0.10/hora | R$ 0,60/h | Preço fixo AWS |
| **Custo Mensal** | $73/mês | R$ 438/mês | 730h × $0.10 |
| **Rateio (2 ambientes)** | $36.50/ambiente | R$ 219/ambiente | $73 ÷ 2 |

**Observações:**
- Preço fixo por cluster, independente do número de nodes
- Compartilhado entre Staging e Prod (mesmo cluster, namespaces separados)
- Sempre ativo (não pode ser desligado)

---

### EC2 Instances (Worker Nodes)

#### Staging (2x t3.medium)

**Cenário Base (24/7):**
```
Instância: t3.medium (2 vCPU, 4GB RAM)
Preço AWS: $0.0416/hora (us-east-1, Linux on-demand)
Conversão: $0.0416 × R$ 6,00 = R$ 0,2496/h

Cálculo mensal (24/7):
2 instâncias × 730h × R$ 0,2496 = R$ 364/mês
```

**Cenário Otimizado (50h/semana):**
```
Horas/mês: 50h/semana × 4,3 semanas = 215h/mês
Cálculo: 2 instâncias × 215h × R$ 0,2496 = R$ 107/mês

Economia: R$ 364 - R$ 107 = R$ 257/mês (-70%)
```

#### Prod (3x t3.large)

```
Instância: t3.large (2 vCPU, 8GB RAM)
Preço AWS: $0.0832/hora (us-east-1, Linux on-demand)
Conversão: $0.0832 × R$ 6,00 = R$ 0,4992/h

Cálculo mensal (24/7):
3 instâncias × 730h × R$ 0,4992 = R$ 1.092/mês
```

**Fonte de preços:** [AWS EC2 Pricing](https://aws.amazon.com/ec2/pricing/on-demand/)

---

### RDS PostgreSQL

#### Staging (db.t3.small Multi-AZ)

**Cenário Base (24/7):**
```
Instância: db.t3.small Multi-AZ (2 vCPU, 2GB RAM)
Preço AWS: $0.082/hora (us-east-1, PostgreSQL Multi-AZ)
Conversão: $0.082 × R$ 6,00 = R$ 0,492/h

Cálculo mensal (24/7):
730h × R$ 0,492 = R$ 359/mês
```

**Cenário Otimizado (auto-pause):**
```
Com auto-pause: ~50% do tempo ativo (estimativa conservadora)
Cálculo: R$ 359 × 0,50 = R$ 180/mês

Economia: R$ 359 - R$ 180 = R$ 179/mês (-50%)
```

**Observação:** RDS não tem "auto-pause" nativo como Aurora Serverless. A economia vem de `stop-db-instance` (grátis quando stopped, cobra apenas storage EBS).

#### Prod (db.t3.medium Multi-AZ)

```
Instância: db.t3.medium Multi-AZ (2 vCPU, 4GB RAM)
Preço AWS: $0.164/hora (us-east-1, PostgreSQL Multi-AZ)
Conversão: $0.164 × R$ 6,00 = R$ 0,984/h

Cálculo mensal (24/7):
730h × R$ 0,984 = R$ 718/mês
```

**Fonte de preços:** [AWS RDS Pricing](https://aws.amazon.com/rds/postgresql/pricing/)

---

### EBS Volumes (Storage)

#### Staging

```
Tipo: gp3 (SSD de propósito geral)
Preço AWS: $0.08/GB/mês
Conversão: $0.08 × R$ 6,00 = R$ 0,48/GB/mês

Volumes:
- RDS storage: 50GB × R$ 0,48 = R$ 24/mês
- Redis PVC: 10GB × R$ 0,48 = R$ 4,80/mês
- RabbitMQ PVC: 10GB × R$ 0,48 = R$ 4,80/mês
- GitLab PVC: 20GB × R$ 0,48 = R$ 9,60/mês

SUBTOTAL: R$ 43,20/mês
```

#### Prod

```
Volumes:
- RDS storage: 100GB × R$ 0,48 = R$ 48/mês
- Redis PVC: 20GB × R$ 0,48 = R$ 9,60/mês
- RabbitMQ PVC: 20GB × R$ 0,48 = R$ 9,60/mês
- GitLab PVC: 50GB × R$ 0,48 = R$ 24/mês
- Prometheus TSDB: 50GB × R$ 0,48 = R$ 24/mês

SUBTOTAL: R$ 115,20/mês
```

**Observação:** EBS é cobrado por GB/mês mesmo quando EC2 está stopped.

**Fonte de preços:** [AWS EBS Pricing](https://aws.amazon.com/ebs/pricing/)

---

### S3 Storage (Backups)

#### Staging

```
Tipo: S3 Standard
Preço AWS: $0.023/GB/mês (primeiros 50TB)
Conversão: $0.023 × R$ 6,00 = R$ 0,138/GB/mês

Estimativa:
- GitLab backups: 20GB × R$ 0,138 = R$ 2,76/mês
- Loki logs: 5GB × R$ 0,138 = R$ 0,69/mês
- Tempo traces: 3GB × R$ 0,138 = R$ 0,41/mês

SUBTOTAL: R$ 3,86/mês (~R$ 5/mês arredondado)
```

#### Prod

```
Estimativa:
- GitLab backups: 50GB × R$ 0,138 = R$ 6,90/mês
- Loki logs: 30GB × R$ 0,138 = R$ 4,14/mês
- Tempo traces: 20GB × R$ 0,138 = R$ 2,76/mês

SUBTOTAL: R$ 13,80/mês (~R$ 15/mês arredondado)
```

**Observação:** Valores estimados conservadores. Uso real varia conforme retenção e volume de dados.

**Fonte de preços:** [AWS S3 Pricing](https://aws.amazon.com/s3/pricing/)

---

### NAT Gateway

```
Preço AWS: $0.045/hora + $0.045/GB processado
Conversão: $0.045 × R$ 6,00 = R$ 0,27/h

Cálculo base (24/7):
730h × R$ 0,27 = R$ 197/mês (hourly charge)
Data processing: ~50GB × R$ 0,27 = R$ 13,50/mês (estimado)
TOTAL: R$ 210/mês
```

**Rateio por ambiente:**
- Staging (Base 24/7): R$ 105/mês
- Staging (Otimizado): R$ 70/mês (redução proporcional ao uso)
- Prod: R$ 105/mês

**Fonte de preços:** [AWS VPC Pricing](https://aws.amazon.com/vpc/pricing/)

---

### Application Load Balancer (ALB)

```
Preço AWS:
- ALB-hour: $0.0225/hora
- LCU (Load Balancer Capacity Unit): $0.008/LCU/hora

Conversão:
- $0.0225 × R$ 6,00 = R$ 0,135/h
- $0.008 × R$ 6,00 = R$ 0,048/LCU/h

Cálculo mensal (estimativa conservadora):
730h × R$ 0,135 = R$ 98,55 (hourly)
730h × 1 LCU média × R$ 0,048 = R$ 35,04 (LCU)
TOTAL: R$ 133,59/mês (~R$ 135/mês)
```

**Observação:** ALB é compartilhado (Prod apenas). Staging usa NodePort interno.

**Fonte de preços:** [AWS ELB Pricing](https://aws.amazon.com/elasticloadbalancing/pricing/)

---

### AWS WAF

```
Preço AWS:
- Web ACL: $5/mês por ACL
- Rule: $1/mês por regra
- Requests: $0.60/milhão de requests

Conversão:
- $5 × R$ 6,00 = R$ 30/mês (Web ACL)
- $1 × R$ 6,00 × 5 regras = R$ 30/mês (regras OWASP básicas)
- Requests: desprezível para tráfego inicial

TOTAL: R$ 60/mês
```

**Observação:** WAF aplicado apenas em Prod (ALB).

**Fonte de preços:** [AWS WAF Pricing](https://aws.amazon.com/waf/pricing/)

---

## 3. Consolidação de Custos

### Staging (Cenário Otimizado - 50h/semana)

| Recurso | Custo Mensal | Observações |
|---------|--------------|-------------|
| EKS Control Plane (rateio) | R$ 219 | Compartilhado, sempre ativo |
| EC2 (2x t3.medium) | R$ 107 | 50h/semana (otimizado) |
| RDS (db.t3.small) | R$ 180 | Stopped fora horário (~50% economia) |
| EBS Volumes | R$ 43 | Cobrado mesmo EC2 stopped |
| S3 Backups | R$ 5 | Storage apenas |
| NAT Gateway | R$ 70 | Redução proporcional ao uso |
| Redis/RabbitMQ | R$ 48 | Estimativa consumo resources |
| **TOTAL STAGING** | **R$ 672** | - |

### Prod (24/7)

| Recurso | Custo Mensal | Observações |
|---------|--------------|-------------|
| EKS Control Plane (rateio) | R$ 219 | Compartilhado, sempre ativo |
| EC2 (3x t3.large) | R$ 1.092 | 24/7 Multi-AZ |
| RDS (db.t3.medium) | R$ 718 | 24/7 Multi-AZ |
| EBS Volumes | R$ 115 | 24/7 |
| S3 Backups | R$ 15 | Storage + replication |
| NAT Gateway | R$ 105 | 24/7 |
| ALB | R$ 135 | 24/7 |
| WAF | R$ 60 | Aplicado ao ALB |
| Redis HA + RabbitMQ | R$ 343 | HA com Sentinel/cluster |
| **TOTAL PROD** | **R$ 2.802** | - |

### Observability (Compartilhada)

| Recurso | Custo Mensal | Observações |
|---------|--------------|-------------|
| Storage adicional (métricas/logs) | R$ 150 | S3 + EBS para TSDB |
| **TOTAL OBSERVABILITY** | **R$ 150** | Roda nos nodes existentes |

---

## 4. Fatores de Variação

### Variação Cambial (USD → BRL)

| Cotação | Custo Mensal Total | Variação vs Base |
|---------|-------------------|------------------|
| R$ 5,40 (-10%) | R$ 3.262 | -10% (-R$ 362) |
| **R$ 6,00 (base)** | **R$ 3.624** | **Baseline** |
| R$ 6,60 (+10%) | R$ 3.986 | +10% (+R$ 362) |
| R$ 7,20 (+20%) | R$ 4.349 | +20% (+R$ 725) |

**Recomendação:** Configurar AWS Budget com limite de R$ 4.000/mês (margem de segurança 10%).

---

### Crescimento de Storage (Logs/Métricas)

| Mês | Storage Estimado | Custo S3 Adicional | Observação |
|-----|------------------|--------------------|-----------  |
| Mês 1 | 50GB | R$ 7/mês | Baseline |
| Mês 3 | 80GB | R$ 11/mês | +60% crescimento |
| Mês 6 | 120GB | R$ 17/mês | +140% crescimento |
| Mês 12 | 180GB | R$ 25/mês | +260% crescimento |

**Mitigação:**
- Configurar retenção Loki: 30 dias (vs padrão 90 dias)
- Configurar retenção Prometheus: 15 dias (vs padrão 30 dias)
- Habilitar lifecycle policies S3 (delete após 90 dias)

---

### Data Transfer Out (não incluído nos custos base)

```
Preço AWS: $0.09/GB (primeiros 10TB/mês para internet)
Conversão: $0.09 × R$ 6,00 = R$ 0,54/GB

Estimativa conservadora:
- Prod: ~50GB/mês × R$ 0,54 = R$ 27/mês
- Staging: ~10GB/mês × R$ 0,54 = R$ 5,40/mês

TOTAL ESTIMADO: R$ 32/mês adicional (~1% do custo total)
```

**Observação:** Não incluído nos cálculos principais por ser difícil estimar sem padrões de uso reais.

---

## 5. Oportunidades de Otimização (Ano 2+)

### Savings Plans (1 ano de commitment)

```
Desconto AWS: ~20% em EC2 e RDS
Aplicação:
- EC2 Staging: R$ 107 × 0,80 = R$ 86/mês (-R$ 21)
- EC2 Prod: R$ 1.092 × 0,80 = R$ 874/mês (-R$ 218)
- RDS Staging: R$ 180 × 0,80 = R$ 144/mês (-R$ 36)
- RDS Prod: R$ 718 × 0,80 = R$ 574/mês (-R$ 144)

ECONOMIA MENSAL: R$ 419/mês
ECONOMIA ANUAL: R$ 5.028/ano
```

### Reserved Instances (3 anos de commitment)

```
Desconto AWS: ~40% em EC2 e RDS
Aplicação:
- EC2 Staging: R$ 107 × 0,60 = R$ 64/mês (-R$ 43)
- EC2 Prod: R$ 1.092 × 0,60 = R$ 655/mês (-R$ 437)
- RDS Staging: R$ 180 × 0,60 = R$ 108/mês (-R$ 72)
- RDS Prod: R$ 718 × 0,60 = R$ 431/mês (-R$ 287)

ECONOMIA MENSAL: R$ 839/mês
ECONOMIA ANUAL: R$ 10.068/ano
```

**Recomendação:** Avaliar após 6-12 meses de operação para confirmar padrões de uso estáveis.

---

## 6. Monitoramento e Revisão

### Checklist de Monitoramento Mensal

- [ ] Comparar custo real (AWS Billing) vs projeção
- [ ] Verificar variação cambial USD→BRL do período
- [ ] Analisar top 5 recursos por custo (Cost Explorer)
- [ ] Validar crescimento de storage (S3, EBS)
- [ ] Revisar alertas de AWS Budget
- [ ] Identificar recursos ociosos (Trusted Advisor)

### Gatilhos para Ajuste de Projeção

| Condição | Ação |
|----------|------|
| Variação > 15% por 2 meses consecutivos | Revisar premissas e ajustar orçamento |
| Dólar > R$ 6,60 por 30 dias | Considerar hedge cambial ou ajustar budget |
| Storage crescendo > 10%/mês | Revisar políticas de retenção |
| Custo de um recurso > 30% do total | Investigar otimizações específicas |

---

## 7. Fontes e Referências

- **AWS Pricing Calculator:** https://calculator.aws/
- **AWS EC2 Pricing:** https://aws.amazon.com/ec2/pricing/
- **AWS RDS Pricing:** https://aws.amazon.com/rds/pricing/
- **AWS EBS Pricing:** https://aws.amazon.com/ebs/pricing/
- **AWS S3 Pricing:** https://aws.amazon.com/s3/pricing/
- **AWS Price List API:** https://aws.amazon.com/pricing/
- **Cotação USD/BRL:** Banco Central do Brasil (jan/2026)

---

**Última atualização:** 2026-01-15
**Próxima revisão sugerida:** 2026-02-15 (após 1 mês de operação)
