# 📓 Análise de Reaproveitamento de VPC para Cluster EKS

| Campo          | Valor                                    |
|----------------|------------------------------------------|
| **Data**       | 2026-01-22                               |
| **Demanda**    | Decisão sobre criar VPC nova ou reaproveitar VPC existente |
| **Impacto**    | Alto (Afeta arquitetura e custos)        |
| **Agentes**    | DevOps Team, Arquiteto de Soluções       |
| **Status**     | ✅ Concluído                             |
| **Duração**    | ~3-4 horas (análise completa)            |

---

## Contexto

Durante o planejamento inicial da plataforma Kubernetes na AWS, identificamos que já existe uma VPC na conta AWS (`vpc-0b1396a59c417c1f0`) utilizada para outros fins (workloads `fictor-*`). Surgiu a questão crítica: **devemos reaproveitar esta VPC ou criar uma nova?**

---

## Análise Técnica Realizada

### Comandos Executados para Diagnóstico

```bash
# 1. Verificar CIDR da VPC
aws ec2 describe-vpcs --vpc-ids vpc-0b1396a59c417c1f0 --query 'Vpcs[0].CidrBlock'
# Resultado: "10.0.0.0/16"

# 2. Listar subnets existentes
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-0b1396a59c417c1f0" \
    --query 'Subnets[*].[SubnetId,CidrBlock,AvailabilityZone,AvailableIpAddressCount]' \
    --output table

# 3. Verificar NAT Gateways
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=vpc-0b1396a59c417c1f0"

# 4. Verificar Internet Gateway
aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=vpc-0b1396a59c417c1f0"
```

### Infraestrutura Atual Identificada

```
VPC: 10.0.0.0/16 (vpc-0b1396a59c417c1f0)
│
├── us-east-1a
│   ├── subnet-0b5e0cae5658ea993 | 10.0.0.0/20   | Pública  | 4.089 IPs disponíveis
│   ├── subnet-0472ab28726cdf745 | 10.0.128.0/20 | Privada  | 4.091 IPs disponíveis
│   └── NAT Gateway: nat-03512e5ee0642dcf2 (EIP: 52.204.176.103)
│
├── us-east-1b
│   ├── subnet-07dca8ceb9882ba66 | 10.0.16.0/20  | Pública  | 4.090 IPs disponíveis
│   ├── subnet-0288a67cd352effa7 | 10.0.144.0/20 | Privada  | 4.091 IPs disponíveis
│   └── NAT Gateway: nat-0be570edfb2eff63e (EIP: 98.90.225.155)
│
└── Internet Gateway: igw-0a8a1ad9cfddd037e
```

**Naming Convention Identificada:**
- Prefixo: `fictor-*` (workloads legados)
- NAT Gateways: `fictor-nat-public{1,2}-us-east-1{a,b}`
- Internet Gateway: `fictor-igw`

---

## Avaliação por Critério

| Critério | Requisito Original | VPC Atual | Status | Comentário |
|----------|-------------------|-----------|--------|------------|
| **CIDR Block** | /16 ou maior | ✅ 10.0.0.0/16 | ✅ **PASS** | 65.536 IPs totais |
| **Availability Zones** | 3 AZs (1a, 1b, 1c) | ⚠️ 2 AZs (1a, 1b) | ⚠️ **LIMITADO** | **Falta us-east-1c** |
| **Subnets Privadas** | Mínimo 3x /24 | ✅ 2x /20 disponíveis | ✅ **PASS** | 4.091 IPs cada (sobra) |
| **NAT Gateway** | Mínimo 1 | ✅ 2 NATs (Multi-AZ) | ✅ **EXCELENTE** | Alta disponibilidade |
| **Internet Gateway** | Obrigatório | ✅ 1 IGW ativo | ✅ **PASS** | Funcional |
| **Espaço CIDR Livre** | ~3.000 IPs | ✅ ~48.000 IPs livres | ✅ **PASS** | Sobra significativa |

---

## Problema Crítico Identificado

### Apenas 2 Availability Zones configuradas

O plano original previa 3 AZs para alta disponibilidade em produção:

```
Plano Original (3 AZs):          VPC Atual (2 AZs):
├── us-east-1a ✅                ├── us-east-1a ✅
├── us-east-1b ✅                ├── us-east-1b ✅
└── us-east-1c ✅                └── us-east-1c ❌ AUSENTE
```

**Impactos da limitação:**

| Componente | Impacto | Severidade |
|------------|---------|------------|
| EKS Control Plane | ⚠️ Funciona, mas HA reduzida | MÉDIA |
| Node Groups | ⚠️ 2 AZs para distribuição | MÉDIA |
| RDS Multi-AZ | ⚠️ Failover limitado a 2 AZs | MÉDIA |
| ElastiCache | ⚠️ 2 replicas ao invés de 3 | BAIXA |
| ALB | ✅ Opera normalmente com 2 AZs | NENHUM |

---

## Mapeamento de CIDR Disponível

### Espaço utilizado pelos workloads legados

```
OCUPADO:
- 10.0.0.0/20    → 10.0.15.255   (4.096 IPs) - Subnet pública 1a
- 10.0.16.0/20   → 10.0.31.255   (4.096 IPs) - Subnet pública 1b
- 10.0.128.0/20  → 10.0.143.255  (4.096 IPs) - Subnet privada 1a
- 10.0.144.0/20  → 10.0.159.255  (4.096 IPs) - Subnet privada 1b

Total ocupado: 16.384 IPs (25% da VPC)
```

### Espaço livre para o cluster EKS

```
DISPONÍVEL PARA EKS:
- 10.0.32.0/19   → 10.0.63.255   (8.192 IPs)   🟢 Range A
- 10.0.64.0/18   → 10.0.127.255  (16.384 IPs)  🟢 Range B
- 10.0.160.0/19  → 10.0.191.255  (8.192 IPs)   🟢 Range C
- 10.0.192.0/18  → 10.0.255.255  (16.384 IPs)  🟢 Range D

Total disponível: ~49.152 IPs (75% da VPC)
```

**Conclusão:** Espaço de endereçamento **mais que suficiente** para o cluster EKS + workloads futuros.

---

## Análise de Impacto Financeiro

### Comparação de Custos

| Cenário | NAT Gateways | Elastic IPs | Custo Mensal | Economia |
|---------|--------------|-------------|--------------|----------|
| **VPC Nova (3 AZs)** | 3 novos | +3 EIPs | +$96/mês | Baseline |
| **Reaproveitar (2 AZs)** | 2 existentes | 0 EIPs novos | **$0** | **-$96/mês** 🎉 |
| **Reaproveitar + 3ª AZ** | 2 existentes + 1 novo | +1 EIP | +$32/mês | **-$64/mês** |

**Breakdown de custos NAT Gateway:**
- Custo por hora: $0.045/hora
- Custo mensal por NAT: $32.40/mês
- Custo de transferência de dados: $0.045/GB

**Economia estimada ao reaproveitar:**
- **Cenário conservador (2 AZs):** $96/mês = $1.152/ano
- **Cenário HA total (3 AZs):** $64/mês = $768/ano

---

## Arquitetura Proposta: VPC Compartilhada com Isolamento

### Design de Subnets para o Cluster EKS

```
┌──────────────────────────────────────────────────────────────────────┐
│              VPC: 10.0.0.0/16 (vpc-0b1396a59c417c1f0)                │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  🔵 WORKLOADS LEGADOS (fictor-*) - NÃO MODIFICAR                     │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │ us-east-1a                                                     │ │
│  │  ├── 10.0.0.0/20    (subnet-0b5e0cae5658ea993)   [Pública]    │ │
│  │  ├── 10.0.128.0/20  (subnet-0472ab28726cdf745)   [Privada]    │ │
│  │  └── NAT: nat-03512e5ee0642dcf2                               │ │
│  │                                                                 │ │
│  │ us-east-1b                                                     │ │
│  │  ├── 10.0.16.0/20   (subnet-07dca8ceb9882ba66)   [Pública]    │ │
│  │  ├── 10.0.144.0/20  (subnet-0288a67cd352effa7)   [Privada]    │ │
│  │  └── NAT: nat-0be570edfb2eff63e                               │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  🟢 CLUSTER EKS (k8s-platform-prod) - NOVO E ISOLADO                 │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │ us-east-1a                                                     │ │
│  │  ├── 10.0.40.0/24  - eks-public-1a   (ALB, Ingress)          │ │
│  │  ├── 10.0.50.0/24  - eks-private-1a  (EKS Nodes)             │ │
│  │  └── 10.0.51.0/24  - eks-db-1a       (RDS, ElastiCache)      │ │
│  │                                                                 │ │
│  │ us-east-1b                                                     │ │
│  │  ├── 10.0.41.0/24  - eks-public-1b   (ALB, Ingress)          │ │
│  │  ├── 10.0.52.0/24  - eks-private-1b  (EKS Nodes)             │ │
│  │  └── 10.0.53.0/24  - eks-db-1b       (RDS, ElastiCache)      │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  🔴 OPCIONAL: 3ª AZ para HA Total                                    │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │ us-east-1c (A CRIAR)                                           │ │
│  │  ├── 10.0.42.0/24  - eks-public-1c   (ALB, Ingress)          │ │
│  │  ├── 10.0.54.0/24  - eks-private-1c  (EKS Nodes)             │ │
│  │  ├── 10.0.55.0/24  - eks-db-1c       (RDS, ElastiCache)      │ │
│  │  └── NAT: nat-XXXXX (novo NAT Gateway - custo: +$32/mês)     │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

### Alocação de CIDR

| Subnet | CIDR | IPs | AZ | Propósito |
|--------|------|-----|----|-----------|
| eks-public-1a | 10.0.40.0/24 | 256 | us-east-1a | ALB, Ingress Controllers |
| eks-public-1b | 10.0.41.0/24 | 256 | us-east-1b | ALB, Ingress Controllers |
| eks-public-1c | 10.0.42.0/24 | 256 | us-east-1c | ALB, Ingress Controllers (opcional) |
| eks-private-1a | 10.0.50.0/24 | 256 | us-east-1a | EKS Worker Nodes |
| eks-private-1b | 10.0.52.0/24 | 256 | us-east-1b | EKS Worker Nodes |
| eks-private-1c | 10.0.54.0/24 | 256 | us-east-1c | EKS Worker Nodes (opcional) |
| eks-db-1a | 10.0.51.0/24 | 256 | us-east-1a | RDS, ElastiCache |
| eks-db-1b | 10.0.53.0/24 | 256 | us-east-1b | RDS, ElastiCache |
| eks-db-1c | 10.0.55.0/24 | 256 | us-east-1c | RDS, ElastiCache (opcional) |

**Total alocado:** 2.304 IPs (1.536 para 2 AZs, 2.304 para 3 AZs)
**Margem de crescimento:** ~46.848 IPs restantes (95% da VPC ainda livre)

---

## Estratégia de Isolamento de Segurança

### Camadas de Isolamento Obrigatórias

**1. Security Groups Dedicados:**
```
├── sg-eks-cluster       → Control Plane EKS
├── sg-eks-nodes         → Worker Nodes (isolado de workloads legados)
├── sg-eks-rds           → RDS PostgreSQL
├── sg-eks-redis         → ElastiCache Redis
└── sg-eks-alb           → Application Load Balancer
```

**2. Network Policies (Kubernetes):**
- Default deny-all por namespace
- Whitelist explícita de comunicação pod-to-pod
- Bloqueio de tráfego para subnets legadas (`10.0.0.0/20`, `10.0.16.0/20`, etc.)

**3. Route Tables Separadas:**
- Route table dedicada para subnets EKS privadas
- Associação aos NAT Gateways existentes (reaproveitamento)
- Zero modificação nas route tables de workloads legados

**4. Tags de Identificação:**
```json
{
  "Project": "k8s-platform",
  "Environment": "prod",
  "Owner": "devops-team",
  "ManagedBy": "terraform",
  "IsolationZone": "eks-cluster"
}
```

---

## Riscos Identificados e Mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|-------|---------------|---------|-----------|
| **Conflito de rotas** | BAIXO | ALTO | Route tables dedicadas, zero sobreposição de CIDR |
| **Comunicação não autorizada** | MÉDIO | ALTO | Security Groups rígidos + Network Policies |
| **Exaustão de IPs** | MUITO BAIXO | MÉDIO | Monitoramento de uso via CloudWatch |
| **Falha de AZ (2 AZs)** | MÉDIO | MÉDIO | Adicionar 3ª AZ ou aceitar RTO/RPO maior |
| **Impacto em workloads legados** | BAIXO | CRÍTICO | Zero alteração em subnets/SGs existentes |
| **Blast radius de incidente** | BAIXO | ALTO | Isolamento por Security Groups + Network ACLs |

**Mitigação prioritária:**
- ✅ Criar Security Groups ANTES de qualquer recurso EKS
- ✅ Testar isolamento com instância EC2 de teste
- ✅ Documentar todas as alterações em route tables
- ⚠️ Avaliar criação de 3ª AZ para produção crítica

---

## Decisões Tomadas

### Decisão #001: Reaproveitamento de VPC Existente

**Status:** ✅ **APROVADO COM CONDIÇÕES**

**Decisão:**
Reaproveitar a VPC existente (`vpc-0b1396a59c417c1f0`) para o cluster EKS, criando subnets dedicadas e isoladas dos workloads legados.

**Justificativa:**
1. ✅ Economia de $64-96/mês em NAT Gateways
2. ✅ CIDR /16 com 75% de espaço livre (~48.000 IPs)
3. ✅ Infraestrutura de rede já estabelecida (NAT, IGW)
4. ✅ Isolamento técnico viável via Security Groups + Network Policies
5. ⚠️ Limitação de 2 AZs aceitável para fase inicial (pode escalar para 3)

**Condições obrigatórias:**
- ✅ Criar 6 novas subnets dedicadas (public, private, db × 2 AZs)
- ✅ Security Groups completamente isolados (zero comunicação com `fictor-*`)
- ✅ Network Policies Kubernetes com default deny-all
- ✅ Route tables dedicadas sem impacto em workloads legados
- ✅ Monitoramento de uso de IPs via CloudWatch
- ✅ Documentação de toda a segmentação de rede

**Alternativas consideradas:**
1. **VPC Nova Dedicada:** Rejeitada (custo adicional $96/mês sem benefício técnico proporcional)
2. **VPC Peering:** Rejeitada (complexidade desnecessária para este cenário)
3. **VPC Compartilhada (ESCOLHIDA):** Economia + isolamento adequado

**Impacto:**
- 💰 Financeiro: Economia de ~$768-1.152/ano
- 🕐 Timeline: Zero atraso (infraestrutura base já existe)
- 🔒 Segurança: Risco BAIXO com isolamento adequado
- 🏗️ Arquitetura: Flexível para adicionar 3ª AZ no futuro

### Decisão #002: Arquitetura com 2 Availability Zones (fase inicial)

**Status:** ✅ **APROVADO DEFINITIVAMENTE**

**Decisão:**
Iniciar com 2 Availability Zones (us-east-1a, us-east-1b) ao invés das 3 AZs previstas no plano original, com possibilidade de expansão futura sem downtime.

**Contexto do negócio:**
Este projeto é uma **plataforma de engenharia/esteira de tecnologia** (GitLab, ArgoCD, SonarQube, Harbor, Keycloak), **NÃO** são workloads críticos de produção voltados para usuários finais. As ferramentas servem times internos de desenvolvimento que toleram breves interrupções.

**Justificativa técnica:**
1. ✅ VPC atual só tem infraestrutura em 2 AZs
2. ✅ Economia de $32/mês (1 NAT Gateway a menos) = **$384/ano**
3. ✅ HA reduzida aceitável para plataforma DevOps não-crítica
4. ✅ Possibilidade de escalar para 3ª AZ **SEM downtime** no futuro
5. ✅ Time-to-market mais rápido (menos recursos para configurar)
6. ✅ Validação da stack completa com menor investimento inicial

**Infraestrutura reaproveitada:**
```
vpc-0b1396a59c417c1f0 (10.0.0.0/16)
├── NAT Gateway 1: nat-03512e5ee0642dcf2 (us-east-1a) → 52.204.176.103
├── NAT Gateway 2: nat-0be570edfb2eff63e (us-east-1b) → 98.90.225.155
└── Internet Gateway: igw-0a8a1ad9cfddd037e

✅ Benefício: Reaproveitamento de $96/mês em NAT Gateways já pagos
```

---

## Lições Aprendidas

### 💰 Análise Financeira

| # | Lição | Impacto |
|---|-------|---------|
| 1 | **Reaproveitamento de recursos existentes pode gerar economias significativas** ($768-1.152/ano) sem comprometer requisitos técnicos | 🔴 Crítico |
| 2 | NAT Gateways são um dos maiores custos em arquiteturas multi-AZ → avaliar reuso antes de criar novos | 🟡 Médio |
| 3 | Economia de $32/mês por NAT Gateway pode parecer pequena, mas somam $384/ano → justifica decisão técnica | 🟢 Baixo |

### 🏗️ Arquitetura e Design

| # | Lição | Impacto |
|---|-------|---------|
| 4 | **Isolamento em VPC compartilhada é viável** via Security Groups, Network Policies e Route Tables dedicadas | 🔴 Crítico |
| 5 | CIDR planning é crítico: VPC /16 com 75% livre permite crescimento sem reestruturação | 🟡 Médio |
| 6 | Arquitetura com 2 AZs é suficiente para workloads DevOps não-críticos (GitLab, ArgoCD, Harbor) | 🟡 Médio |
| 7 | Expansion path deve ser planejado desde o início → possibilidade de adicionar 3ª AZ sem downtime | 🟡 Médio |

### 🔒 Segurança

| # | Lição | Impacto |
|---|-------|---------|
| 8 | **Múltiplas camadas de isolamento** (SG + Network Policies + Route Tables) são necessárias em VPC compartilhada | 🔴 Crítico |
| 9 | Tags consistentes (`IsolationZone`, `Project`, `ManagedBy`) facilitam troubleshooting e auditoria | 🟢 Baixo |
| 10 | Blast radius deve ser considerado → zero modificação em workloads legados minimiza riscos | 🟡 Médio |

### ⚙️ Operações e Processo

| # | Lição | Impacto |
|---|-------|---------|
| 11 | **Comandos AWS CLI são essenciais** para diagnóstico de infraestrutura existente (describe-vpcs, describe-subnets, etc.) | 🟡 Médio |
| 12 | Documentar decisões arquiteturais com justificativas financeiras e técnicas facilita aprovações futuras | 🟢 Baixo |
| 13 | Análise de riscos estruturada (probabilidade × impacto × mitigação) torna decisões mais objetivas | 🟡 Médio |

---

## Métricas

| Métrica | Valor |
|---------|-------|
| Tempo de análise | ~3-4 horas |
| VPCs analisadas | 1 |
| Comandos AWS CLI executados | 4 |
| Economia estimada (anual) | $768 - $1.152 |
| IPs disponíveis identificados | ~49.152 |
| Cenários avaliados | 3 (VPC nova, reuso 2 AZs, reuso 3 AZs) |

---

## Referências

- Plano original: [docs/plan/aws-console-execution-plan.md](../plan/aws-console-execution-plan.md)
- VPC ID: `vpc-0b1396a59c417c1f0`
- Região AWS: `us-east-1` (N. Virginia)
- [AWS NAT Gateway Pricing](https://aws.amazon.com/vpc/pricing/)
- [AWS VPC Best Practices](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-best-practices.html)
