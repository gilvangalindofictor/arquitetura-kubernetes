# 📓 Diário de Bordo - Implementação AWS EKS

**Projeto:** Plataforma Kubernetes Corporativa Multi-Domínio
**Região:** us-east-1 (N. Virginia)
**Início:** 2026-01-22
**Responsável:** DevOps Team
**Status:** 🟡 Em Análise e Preparação

---

## 📋 Índice

- [Objetivo](#objetivo)
- [Descobertas e Análises](#descobertas-e-análises)
  - [2026-01-22 - Análise de Reaproveitamento de VPC](#2026-01-22---análise-de-reaproveitamento-de-vpc)
- [Decisões Técnicas](#decisões-técnicas)
- [Próximos Passos](#próximos-passos)
- [Referências](#referências)

---

## 🎯 Objetivo

Este documento registra o progresso da implementação da plataforma Kubernetes na AWS, incluindo descobertas técnicas, decisões arquiteturais, problemas encontrados e suas soluções. Serve como histórico vivo do projeto e referência para auditoria futura.

---

## 🔍 Descobertas e Análises

### 2026-01-22 - Análise de Reaproveitamento de VPC

#### 📌 Contexto

Durante o planejamento inicial, identificamos que já existe uma VPC na conta AWS (`vpc-0b1396a59c417c1f0`) utilizada para outros fins (identificada pelas tags `fictor-*`). Surgiu a questão: **devemos reaproveitar esta VPC ou criar uma nova?**

#### 🔬 Análise Técnica Realizada

**Comandos executados para diagnóstico:**

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

#### 📊 Resultado da Análise

**Infraestrutura Atual Identificada:**

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

#### ✅ Avaliação por Critério

| Critério | Requisito Original | VPC Atual | Status | Comentário |
|----------|-------------------|-----------|--------|------------|
| **CIDR Block** | /16 ou maior | ✅ 10.0.0.0/16 | ✅ **PASS** | 65.536 IPs totais |
| **Availability Zones** | 3 AZs (1a, 1b, 1c) | ⚠️ 2 AZs (1a, 1b) | ⚠️ **LIMITADO** | **Falta us-east-1c** |
| **Subnets Privadas** | Mínimo 3x /24 | ✅ 2x /20 disponíveis | ✅ **PASS** | 4.091 IPs cada (sobra) |
| **NAT Gateway** | Mínimo 1 | ✅ 2 NATs (Multi-AZ) | ✅ **EXCELENTE** | Alta disponibilidade |
| **Internet Gateway** | Obrigatório | ✅ 1 IGW ativo | ✅ **PASS** | Funcional |
| **Espaço CIDR Livre** | ~3.000 IPs | ✅ ~48.000 IPs livres | ✅ **PASS** | Sobra significativa |

#### 🔴 Problema Crítico Identificado

**Apenas 2 Availability Zones configuradas**

O plano original ([aws-console-execution-plan.md](aws-console-execution-plan.md)) prevê 3 AZs para alta disponibilidade em produção:

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

#### 📐 Mapeamento de CIDR Disponível

**Espaço utilizado pelos workloads legados:**

```
OCUPADO:
- 10.0.0.0/20    → 10.0.15.255   (4.096 IPs) - Subnet pública 1a
- 10.0.16.0/20   → 10.0.31.255   (4.096 IPs) - Subnet pública 1b
- 10.0.128.0/20  → 10.0.143.255  (4.096 IPs) - Subnet privada 1a
- 10.0.144.0/20  → 10.0.159.255  (4.096 IPs) - Subnet privada 1b

Total ocupado: 16.384 IPs (25% da VPC)
```

**Espaço livre para o cluster EKS:**

```
DISPONÍVEL PARA EKS:
- 10.0.32.0/19   → 10.0.63.255   (8.192 IPs)   🟢 Range A
- 10.0.64.0/18   → 10.0.127.255  (16.384 IPs)  🟢 Range B
- 10.0.160.0/19  → 10.0.191.255  (8.192 IPs)   🟢 Range C
- 10.0.192.0/18  → 10.0.255.255  (16.384 IPs)  🟢 Range D

Total disponível: ~49.152 IPs (75% da VPC)
```

**Conclusão:** Espaço de endereçamento **mais que suficiente** para o cluster EKS + workloads futuros.

#### 💰 Análise de Impacto Financeiro

**Comparação de Custos:**

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

#### 🏗️ Arquitetura Proposta: VPC Compartilhada com Isolamento

**Design de subnets para o cluster EKS:**

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

**Alocação de CIDR:**

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

#### 🔒 Estratégia de Isolamento de Segurança

**Camadas de isolamento obrigatórias:**

1. **Security Groups Dedicados:**
   ```
   ├── sg-eks-cluster       → Control Plane EKS
   ├── sg-eks-nodes         → Worker Nodes (isolado de workloads legados)
   ├── sg-eks-rds           → RDS PostgreSQL
   ├── sg-eks-redis         → ElastiCache Redis
   └── sg-eks-alb           → Application Load Balancer
   ```

2. **Network Policies (Kubernetes):**
   - Default deny-all por namespace
   - Whitelist explícita de comunicação pod-to-pod
   - Bloqueio de tráfego para subnets legadas (`10.0.0.0/20`, `10.0.16.0/20`, etc.)

3. **Route Tables Separadas:**
   - Route table dedicada para subnets EKS privadas
   - Associação aos NAT Gateways existentes (reaproveitamento)
   - Zero modificação nas route tables de workloads legados

4. **Tags de Identificação:**
   ```json
   {
     "Project": "k8s-platform",
     "Environment": "prod",
     "Owner": "devops-team",
     "ManagedBy": "terraform",
     "IsolationZone": "eks-cluster"
   }
   ```

#### ⚠️ Riscos Identificados e Mitigações

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

## 🎯 Decisões Técnicas

### Decisão #001: Reaproveitamento de VPC Existente

**Data:** 2026-01-22
**Decisores:** DevOps Team + Arquiteto de Soluções
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
- [ ] Criar 6 novas subnets dedicadas (public, private, db × 2 AZs)
- [ ] Security Groups completamente isolados (zero comunicação com `fictor-*`)
- [ ] Network Policies Kubernetes com default deny-all
- [ ] Route tables dedicadas sem impacto em workloads legados
- [ ] Monitoramento de uso de IPs via CloudWatch
- [ ] Documentação de toda a segmentação de rede

**Alternativas consideradas:**
1. **VPC Nova Dedicada:** Rejeitada (custo adicional $96/mês sem benefício técnico proporcional)
2. **VPC Peering:** Rejeitada (complexidade desnecessária para este cenário)
3. **VPC Compartilhada (ESCOLHIDA):** Economia + isolamento adequado

**Impacto:**
- 💰 Financeiro: Economia de ~$768-1.152/ano
- 🕐 Timeline: Zero atraso (infraestrutura base já existe)
- 🔒 Segurança: Risco BAIXO com isolamento adequado
- 🏗️ Arquitetura: Flexível para adicionar 3ª AZ no futuro

**Validação:**
- [ ] Aprovação do time de segurança
- [ ] Teste de isolamento de rede
- [ ] Validação de capacidade de IPs

---

### Decisão #002: Arquitetura com 2 Availability Zones (fase inicial)

**Data:** 2026-01-22
**Decisores:** DevOps Team + Especialista AWS
**Status:** ✅ **APROVADO DEFINITIVAMENTE**

**Decisão:**
Iniciar com 2 Availability Zones (us-east-1a, us-east-1b) ao invés das 3 AZs previstas no plano original, com possibilidade de expansão futura sem downtime.

**Contexto do negócio:**
Este projeto é uma **plataforma de engenharia/esteira de tecnologia** (GitLab, ArgoCD, SonarQube, Harbor, Keycloak), **NÃO** são workloads críticos de produção voltados para usuários finais. As ferramentas servem times internos de desenvolvimento que toleram breves interrupções planejadas ou não.

**Justificativa técnica:**
1. ✅ VPC atual (`vpc-0b1396a59c417c1f0`) só tem infraestrutura em 2 AZs
2. ✅ Economia de $32/mês (1 NAT Gateway a menos) = **$384/ano**
3. ✅ HA reduzida aceitável para plataforma DevOps não-crítica
4. ✅ Possibilidade de escalar para 3ª AZ **SEM downtime** no futuro
5. ✅ Time-to-market mais rápido (menos recursos para configurar)
6. ✅ Validação da stack completa com menor investimento inicial

**Infraestrutura atual reaproveitada:**
```
vpc-0b1396a59c417c1f0 (10.0.0.0/16)
├── NAT Gateway 1: nat-03512e5ee0642dcf2 (us-east-1a) → 52.204.176.103
├── NAT Gateway 2: nat-0be570edfb2eff63e (us-east-1b) → 98.90.225.155
└── Internet Gateway: igw-0a8a1ad9cfddd037e

✅ Benefício: Reaproveitamento de $96/mês em NAT Gateways já pagos
```

**Análise de Pontos Fortes e Fracos:**

#### ✅ **PONTOS FORTES**

| Aspecto | Benefício | Impacto |
|---------|-----------|---------|
| **Custo-benefício** | Economia de $384-1.152/ano sem perda funcional significativa | 🟢 ALTO |
| **Reaproveitamento de recursos** | NAT Gateways e IGW já existentes e pagos | 🟢 ALTO |
| **Simplicidade inicial** | 6 subnets ao invés de 9, menos complexidade para debugar | 🟢 MÉDIO |
| **Velocidade de deploy** | Menos recursos = deploy mais rápido, gera valor antes | 🟢 MÉDIO |
| **Flexibilidade** | Expansão para 3 AZs sem downtime quando necessário | 🟢 ALTO |
| **Espaço CIDR abundante** | 75% da VPC livre (~48.000 IPs) para crescimento | 🟢 ALTO |
| **Isolamento viável** | Security Groups dedicados garantem separação de workloads legados | 🟢 ALTO |
| **HA suficiente para DevOps** | EKS Control Plane ainda é tolerante a falhas com 2 AZs | 🟡 MÉDIO |
| **RDS Multi-AZ funcional** | Failover automático entre us-east-1a ↔ us-east-1b | 🟢 MÉDIO |
| **Risk mitigation** | Possibilidade de adicionar 3ª AZ em 2-3 horas, zero downtime | 🟢 ALTO |

**Economia total estimada:**
- **Ano 1 (2 AZs):** $1.152 economizado vs criar VPC nova
- **Após expansão (3 AZs):** $768/ano economizado vs criar VPC nova
- **ROI da expansão:** Se houver 1+ incidente de AZ/ano, adicionar 3ª AZ vale a pena

#### ⚠️ **PONTOS FRACOS (Riscos Aceitos)**

| Risco | Probabilidade | Impacto Real | Severidade | Mitigação |
|-------|---------------|--------------|------------|-----------|
| **Falha de 1 AZ** | BAIXO (~1-2x/ano na AWS) | Degradação de performance | 🟡 MÉDIA | Aceitável para DevOps tools |
| **Capacidade reduzida** | BAIXO (só em falha de AZ) | 50% de nodes disponíveis | 🟡 MÉDIA | Cluster continua operando |
| **RDS failover limitado** | MUITO BAIXO | Apenas 1 standby disponível | 🟢 BAIXA | Multi-AZ ainda funciona |
| **Redis com 1 replica** | BAIXO | Cache miss temporário | 🟢 BAIXA | Dados não são persistentes |
| **RTO/RPO maior** | BAIXO | Recuperação pode levar mais tempo | 🟡 MÉDIA | Documentar runbooks |
| **SLA reduzido** | N/A | ~99.5% ao invés de 99.9% | 🟡 MÉDIA | Aceitável para esteira interna |

**Impacto em cenário de falha de 1 AZ:**

| Componente | Comportamento com 2 AZs | Impacto nos Usuários |
|------------|------------------------|---------------------|
| **EKS Control Plane** | ✅ Continua operando normalmente | 🟢 Nenhum |
| **Worker Nodes** | ⚠️ 50% de capacidade (1 AZ restante) | 🟡 GitLab pode ficar lento |
| **RDS PostgreSQL** | ✅ Failover automático para AZ saudável | 🟢 ~30s de interrupção |
| **ElastiCache Redis** | ⚠️ 1 replica restante (de 2) | 🟡 Cache pode ter miss temporário |
| **ALB** | ✅ Roteia 100% para AZ saudável | 🟢 Nenhum |
| **GitLab** | ⚠️ Pods redistribuídos, pode ter fila | 🟡 Push/clone podem demorar |
| **ArgoCD/Harbor** | ⚠️ Pods redistribuídos automaticamente | 🟡 Deploy pode atrasar 5-10 min |

**Frequência histórica de falhas de AZ na AWS:**
- Incidentes por ano: ~1-2 eventos globais
- Duração média: 30 minutos - 4 horas
- Probabilidade de afetar us-east-1a ou 1b: <0.1%

**Custo de indisponibilidade calculado:**
```
Cenário conservador: Falha de 1 AZ por 2 horas/ano
├── Desenvolvedores afetados: ~30
├── Custo/hora médio: $50
├── Perda de produtividade: 30 × 2h × $50 = $3.000
└── Investimento no 3º NAT: $384/ano

ROI: Se houver 1 incidente/ano com 2h+ de duração, vale adicionar 3ª AZ
```

**Conclusão sobre pontos fracos:**
- ⚠️ Riscos são **ACEITÁVEIS** para plataforma DevOps interna
- ✅ Usuários (desenvolvedores) toleram breves interrupções
- ✅ Não há SLA contratual com penalidades financeiras
- ✅ Ferramentas não são revenue-generating (não afetam clientes finais)

#### 🎯 **Análise Comparativa: 2 AZs vs 3 AZs**

| Critério | 2 AZs (Escolhido) | 3 AZs (Futuro) | Vencedor |
|----------|-------------------|----------------|----------|
| **Custo inicial** | $700/mês | $732/mês | 🏆 2 AZs |
| **HA para DevOps** | ✅ Suficiente | ✅ Excelente | 🤝 Empate |
| **HA para Produção** | ⚠️ Limitado | ✅ Ideal | 🏆 3 AZs |
| **Complexidade** | ✅ Menor | ⚠️ Maior | 🏆 2 AZs |
| **Time-to-market** | ✅ Rápido | ⚠️ Normal | 🏆 2 AZs |
| **Blast radius** | ⚠️ 50% em falha | ✅ 33% em falha | 🏆 3 AZs |
| **Esforço de expansão** | N/A | ✅ 2-3h, zero downtime | 🏆 2 AZs |

**Estratégia vencedora:** Começar com 2 AZs, escalar quando necessário.

**Riscos aceitos formalmente:**
- ⚠️ RTO/RPO ligeiramente maior em caso de falha de AZ (aceitável)
- ⚠️ SLA interno de ~99.5% ao invés de 99.9% (aceitável para DevOps)
- ⚠️ Degradação de performance temporária em falha de AZ (aceitável)

**Plano de evolução:**
- **Fase 1 (Q1 2026 - atual):** 2 AZs - Validação e onboarding de times
- **Fase 2 (Q2-Q3 2026 - condicional):** Adicionar 3ª AZ se:
  - [ ] Cluster hospedar aplicações críticas de produção
  - [ ] Histórico de incidentes de rede/infra (>2 por trimestre)
  - [ ] >50 usuários ativos diários dependendo da plataforma
  - [ ] Compliance/auditoria exigir HA documentada
  - [ ] Budget aprovado para custo adicional (+$32/mês)
- **Critério de upgrade:** 2 ou mais condições acima verdadeiras

**Processo de expansão (quando necessário):**
```bash
# Processo validado pelo especialista AWS: 2-3 horas, ZERO downtime
1. Criar 3 novas subnets em us-east-1c (public, private, db)
2. Criar NAT Gateway em us-east-1c (+$32/mês)
3. Atualizar Node Groups para incluir 1c (rolling update automático)
4. Adicionar subnet 1c aos DB Subnet Groups
5. Validar distribuição de pods e nodes

✅ Resultado: Cluster expande de 2→3 AZs sem interromper workloads
```

**Reversão:**
Adicionar 3ª AZ pode ser feito a qualquer momento sem impacto nos workloads existentes. Processo é **aditivo** (apenas cria recursos novos), não requer alteração dos existentes.

---

### Decisão #003: Estrutura de Diretórios Terraform

**Data:** 2026-01-22
**Decisores:** DevOps Team + Especialista DevOps
**Status:** ✅ **APROVADO**

**Decisão:**
Utilizar a estrutura `platform-provisioning/aws/kubernetes/terraform/` existente, expandindo com novos módulos e separação por ambientes.

**Localização Base:**
```
/home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/
```

**Estrutura Aprovada:**

```
platform-provisioning/aws/
│
├── README.md                                    # Documentação geral AWS
│
├── kubernetes/
│   ├── terraform/
│   │   │
│   │   ├── environments/                        # 🆕 Ambientes isolados
│   │   │   ├── prod/
│   │   │   │   ├── backend.tf                   # S3 backend (state remoto)
│   │   │   │   ├── main.tf                      # Orquestração de módulos
│   │   │   │   ├── terraform.tfvars             # Variáveis de produção
│   │   │   │   └── README.md
│   │   │   └── staging/
│   │   │       ├── backend.tf
│   │   │       ├── main.tf
│   │   │       ├── terraform.tfvars
│   │   │       └── README.md
│   │   │
│   │   ├── modules/                             # Módulos reutilizáveis
│   │   │   ├── vpc/                             # ✅ Existe
│   │   │   ├── subnets/                         # 🆕 Subnets EKS dedicadas
│   │   │   ├── security-groups/                 # 🆕 SGs isolados
│   │   │   ├── eks/                             # ✅ Existe (atualizar)
│   │   │   ├── rds/                             # 🆕 PostgreSQL Multi-AZ
│   │   │   ├── elasticache/                     # 🆕 Redis Cluster
│   │   │   ├── s3/                              # ✅ Existe (expandir)
│   │   │   ├── iam/                             # ✅ Existe (expandir)
│   │   │   ├── kms/                             # 🆕 Encryption Keys
│   │   │   ├── secrets-manager/                 # 🆕 AWS Secrets Manager
│   │   │   └── route53/                         # 🆕 DNS Management
│   │   │
│   │   ├── main.tf                              # ✅ Existe (atualizar)
│   │   ├── provider.tf                          # 🆕 AWS Provider config
│   │   ├── versions.tf                          # 🆕 Terraform/Provider versions
│   │   ├── variables.tf                         # ✅ Existe (expandir)
│   │   ├── outputs.tf                           # ✅ Existe (expandir)
│   │   └── README.md                            # 🆕 Instruções detalhadas
│   │
│   └── docs/
│       ├── architecture.md                      # 🆕 Arquitetura AWS
│       ├── networking.md                        # 🆕 Networking detalhado
│       ├── runbook.md                           # 🆕 Procedimentos operacionais
│       └── troubleshooting.md                   # 🆕 Solução de problemas
│
└── scripts/                                     # 🆕 Scripts auxiliares
    ├── setup-terraform.sh                       # Setup inicial
    ├── create-backend-bucket.sh                 # Criar S3 backend
    ├── validate-vpc.sh                          # Validar VPC existente
    └── apply-with-approval.sh                   # Terraform apply interativo
```

**Justificativa:**

1. ✅ **Aproveita estrutura existente:** 4 módulos já criados (vpc, eks, s3, iam)
2. ✅ **Separação de ambientes:** `environments/` para isolamento de prod/staging
3. ✅ **Modularização granular:** Cada componente em módulo dedicado
4. ✅ **Alinhamento com ADRs:** Segue ADR-020 (cloud-specific separado)
5. ✅ **Escalabilidade:** Fácil adicionar novos módulos no futuro

**Módulos Novos a Criar:**

| Módulo | Prioridade | Sprint | Função |
|--------|-----------|--------|--------|
| `subnets/` | 🔴 ALTA | Sprint 1 | Criar 6 subnets EKS (2 AZs) |
| `security-groups/` | 🔴 ALTA | Sprint 1 | 5 SGs isolados |
| `kms/` | 🔴 ALTA | Sprint 1 | Customer managed key |
| `rds/` | 🟡 MÉDIA | Sprint 2 | PostgreSQL Multi-AZ |
| `elasticache/` | 🟡 MÉDIA | Sprint 2 | Redis Cluster |
| `secrets-manager/` | 🟡 MÉDIA | Sprint 3 | Secrets centralizados |
| `route53/` | 🟢 BAIXA | Sprint 3 | DNS management |

**Módulos Existentes a Atualizar:**

| Módulo | Ação | Sprint |
|--------|------|--------|
| `eks/` | Adicionar 3 node groups | Sprint 2 |
| `s3/` | Adicionar buckets (backups, artifacts) | Sprint 2 |
| `iam/` | Adicionar IRSA roles | Sprint 3 |

**Plano de Implementação:**

#### **SPRINT 1: Networking Foundation** (Semana 1)

**Objetivo:** Criar base de rede isolada para o cluster EKS

```
Dia 1-2: Setup Inicial
├── environments/prod/backend.tf           # Backend S3 configurado
├── environments/prod/main.tf              # Orquestração inicial
├── environments/prod/terraform.tfvars     # Variáveis de produção
└── scripts/create-backend-bucket.sh       # Script de setup

Dia 3-4: Módulos de Rede
├── modules/kms/                           # Encryption primeiro
├── modules/security-groups/               # SGs antes de recursos
└── modules/subnets/                       # Subnets EKS dedicadas

Dia 5: Validação
├── terraform plan                         # Revisar mudanças
├── terraform apply                        # Criar recursos
└── scripts/validate-vpc.sh                # Validar isolamento
```

**Entregas Sprint 1:**
- ✅ 6 subnets EKS criadas (10.0.40-53.0/24)
- ✅ 5 Security Groups configurados
- ✅ KMS key para encryption
- ✅ Route tables associadas aos NAT Gateways existentes
- ✅ Tags Kubernetes aplicadas
- ✅ Isolamento de rede validado

#### **SPRINT 2: Compute & Databases** (Semana 2)

**Objetivo:** Provisionar cluster EKS e bancos de dados

```
Dia 1-2: EKS Cluster
├── modules/eks/ (atualizado)
│   ├── main.tf                            # Cluster config
│   ├── node-groups.tf                     # 3 node groups
│   └── addons.tf                          # AWS LB Controller, EBS CSI

Dia 3-4: Databases
├── modules/rds/                           # PostgreSQL Multi-AZ (2 AZs)
├── modules/elasticache/                   # Redis Cluster (2 AZs)
└── modules/s3/ (atualizado)               # Novos buckets

Dia 5: Validação
├── kubectl get nodes                      # Verificar nodes
├── kubectl get storageclasses             # Verificar storage
└── Testar conectividade EKS → RDS/Redis
```

**Entregas Sprint 2:**
- ✅ Cluster EKS operacional (1.29)
- ✅ 7 worker nodes distribuídos (2 AZs)
- ✅ RDS PostgreSQL Multi-AZ disponível
- ✅ ElastiCache Redis Cluster ativo
- ✅ S3 buckets criados (backups, artifacts, state)
- ✅ kubectl configurado e testado

#### **SPRINT 3: Secrets & Security** (Semana 3)

**Objetivo:** Configurar gestão de secrets e segurança

```
Dia 1-2: Secrets Management
├── modules/secrets-manager/               # Secrets para RDS, Redis
└── modules/iam/ (atualizado)              # IRSA roles

Dia 3-4: DNS e Documentação
├── modules/route53/                       # DNS management
├── docs/architecture.md                   # Arquitetura AWS
├── docs/networking.md                     # Networking detalhado
└── docs/runbook.md                        # Procedimentos operacionais

Dia 5: Environment Staging
└── environments/staging/                  # Replicar estrutura prod
```

**Entregas Sprint 3:**
- ✅ AWS Secrets Manager configurado
- ✅ IRSA roles para Service Accounts
- ✅ Route53 hosted zone criada
- ✅ Documentação completa
- ✅ Ambiente staging funcional

#### **SPRINT 4: Observability & Validation** (Semana 4)

**Objetivo:** Habilitar observabilidade e validar plataforma

```
Dia 1-2: Observability
├── CloudWatch Container Insights          # Habilitado
├── VPC Flow Logs                          # Configurado
└── CloudWatch Alarms                      # Alertas básicos

Dia 3-4: Security Hardening
├── Network Policies                       # Default deny-all
├── Pod Security Standards                 # Enforced
└── Security Groups Review                 # Auditoria

Dia 5: Validation & Handoff
├── Testes de carga                        # Stress test
├── Disaster Recovery test                 # Simular falha de AZ
└── Documentação de handoff                # Transferência para time
```

**Entregas Sprint 4:**
- ✅ Observabilidade AWS configurada
- ✅ Security hardening aplicado
- ✅ Plataforma validada e documentada
- ✅ Pronta para deploy dos domínios

**Outputs Terraform Esperados:**

```hcl
# Cluster EKS
cluster_endpoint          # URL Kubernetes API
cluster_ca_certificate    # Certificado CA
cluster_name              # k8s-platform-prod
cluster_version           # 1.29

# Networking
vpc_id                    # vpc-0b1396a59c417c1f0
private_subnet_ids        # [subnet-eks-private-1a, subnet-eks-private-1b]
public_subnet_ids         # [subnet-eks-public-1a, subnet-eks-public-1b]
db_subnet_ids             # [subnet-eks-db-1a, subnet-eks-db-1b]

# Databases
rds_endpoint              # hostname:5432
redis_endpoint            # hostname:6379

# Storage
s3_bucket_backups         # Nome do bucket
s3_bucket_artifacts       # Nome do bucket

# IAM
eks_cluster_role_arn      # ARN da role
eks_node_role_arn         # ARN da role

# Encryption
kms_key_id                # alias/k8s-platform-prod
```

**Validação:**
- [ ] Terraform plan sem erros
- [ ] Terraform apply bem-sucedido
- [ ] Todos os outputs disponíveis
- [ ] kubectl get nodes retorna todos os nodes
- [ ] Conectividade EKS → RDS testada
- [ ] Conectividade EKS → Redis testada
- [ ] Isolamento de rede validado
- [ ] Documentação completa

---

## 📋 Próximos Passos

### ✅ Concluído
- [x] Análise de viabilidade da VPC existente
- [x] Mapeamento de CIDR e subnets
- [x] Validação de NAT Gateways e Internet Gateway
- [x] Análise de custos comparativa
- [x] Design de arquitetura com isolamento
- [x] Criação de documento de contexto (este arquivo)
- [x] Scripts de Marco 0 (engenharia reversa + incremental)
- [x] Validação de ambiente WSL para testes locais

### 🔄 Em Progresso
- [ ] Estruturação de módulos Terraform
- [ ] Execução do script de engenharia reversa

### 📅 Planejado

**SPRINT 1: Preparação de Rede (Semana 1)**
- [ ] Criar 6 subnets EKS (public, private, db × 2 AZs)
- [ ] Configurar route tables dedicadas
- [ ] Adicionar tags Kubernetes nas subnets
- [ ] Criar Security Groups isolados
- [ ] Validar conectividade e isolamento

**SPRINT 2: Deploy EKS Cluster (Semana 2)**
- [ ] Criar cluster EKS com subnets privadas
- [ ] Deploy de 3 Node Groups (system, workloads, critical)
- [ ] Instalar AWS Load Balancer Controller
- [ ] Configurar kubectl local
- [ ] Validar conectividade ao cluster

**SPRINT 3: Serviços de Dados (Semana 3)**
- [ ] Criar RDS PostgreSQL Multi-AZ (2 AZs)
- [ ] Criar ElastiCache Redis Cluster (2 AZs)
- [ ] Criar DB Subnet Group
- [ ] Configurar Security Groups de DB
- [ ] Testar conectividade EKS → RDS/Redis

**SPRINT 4: Observabilidade e Segurança (Semana 4)**
- [ ] Habilitar CloudWatch Container Insights
- [ ] Configurar VPC Flow Logs
- [ ] Deploy de Network Policies (default deny-all)
- [ ] Instalar Prometheus + Grafana
- [ ] Configurar alertas de segurança

**BACKLOG:**
- [ ] Avaliar criação de 3ª AZ (us-east-1c) para HA total
- [ ] Implementar AWS Backup para RDS e EBS
- [ ] Configurar WAF para ALB
- [ ] Deploy dos 6 domínios da plataforma (GitLab, Keycloak, etc.)

---

### Decisão #004: Marco 0 - Engenharia Reversa e Abordagem Incremental

**Data:** 2026-01-22
**Decisores:** DevOps Team + Especialista DevOps AWS
**Status:** ✅ **APROVADO E IMPLEMENTADO**

**Decisão:**
Implementar Marco 0 como baseline da infraestrutura atual usando **engenharia reversa** da VPC existente, seguido de scripts incrementais para expansão gradual.

**Contexto:**
O projeto segue um plano de execução detalhado ([aws-console-execution-plan.md](aws-console-execution-plan.md)), mas a VPC atual (`vpc-0b1396a59c417c1f0`) já possui infraestrutura provisionada manualmente. Precisamos de uma estratégia para:
1. Documentar o estado atual como código (baseline)
2. Permitir evolução incremental sem downtime
3. Viabilizar testes locais no WSL antes de aplicar na AWS

**Abordagem Implementada:**

#### Script 1: Engenharia Reversa (`00-marco0-reverse-engineer-vpc.sh`)

**Propósito:** Extrair configuração atual da VPC e gerar Terraform equivalente.

**Funcionalidades:**
- ✅ Extração automatizada via AWS CLI de:
  - VPC (CIDR, DNS settings, tags)
  - Subnets (4 subnets em us-east-1a e us-east-1b)
  - Internet Gateway
  - NAT Gateways (2, um por AZ)
  - Route Tables (públicas e privadas)
- ✅ Geração de módulos Terraform modulares:
  - `modules/vpc/`
  - `modules/subnets/`
  - `modules/nat-gateways/`
  - `modules/internet-gateway/`
  - `modules/route-tables/`
- ✅ Documentação automática (JSONs brutos + README + SUMMARY)
- ✅ Outputs Terraform para integração

**Resultado Esperado:**
```
vpc-reverse-engineered/
├── terraform/              # Código Terraform equivalente ao estado atual
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── modules/
└── docs/                   # Documentação + JSONs da AWS
    ├── vpc-raw.json
    ├── subnets-raw.json
    ├── nat-gateways-raw.json
    ├── igw-raw.json
    ├── route-tables-raw.json
    └── SUMMARY.md
```

**Uso:**
```bash
cd platform-provisioning/aws/scripts
./00-marco0-reverse-engineer-vpc.sh
cd vpc-reverse-engineered/terraform
terraform init
terraform plan  # Validar equivalência com estado atual
```

#### Script 2: Incremental - Adicionar us-east-1c (`01-marco0-incremental-add-region.sh`)

**Propósito:** Adicionar 3ª Availability Zone (us-east-1c) sem impactar recursos existentes.

**Funcionalidades:**
- ✅ Criação de 3 novas subnets:
  - `eks-public-1c` (10.0.42.0/24) - ALB, Ingress
  - `eks-private-1c` (10.0.54.0/24) - EKS Nodes
  - `eks-db-1c` (10.0.55.0/24) - RDS, ElastiCache
- ✅ NAT Gateway opcional (variável `enable_nat_gateway_1c`):
  - `true`: Cria NAT dedicado (+$32/mês, HA total)
  - `false`: Usa NAT de us-east-1a como fallback (economia)
- ✅ Route Tables dedicadas para us-east-1c
- ✅ Zero impacto em recursos existentes (100% incremental)
- ✅ Makefile para automação:
  - `make plan` - Dry-run
  - `make apply-no-nat` - Aplicar sem NAT dedicado
  - `make apply-with-nat` - Aplicar com NAT dedicado
  - `make validate` - Validar recursos criados
  - `make destroy` - Rollback

**Resultado Esperado:**
```
marco0-incremental-1c/
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── modules/
│       ├── subnets-1c/
│       ├── nat-gateway-1c/
│       └── route-tables-1c/
├── Makefile
├── README.md
└── SUMMARY.md
```

**Uso:**
```bash
cd platform-provisioning/aws/scripts
./01-marco0-incremental-add-region.sh
cd marco0-incremental-1c
make init
make plan
make apply-no-nat  # Opção econômica (recomendada inicialmente)
# OU
make apply-with-nat  # HA total (+$32/mês)
make validate
```

**Impacto Financeiro:**

| Cenário | Custo Adicional | Benefício |
|---------|-----------------|-----------|
| **Incremental SEM NAT** | $0/mês | Economia, usa NAT existente |
| **Incremental COM NAT** | +$32/mês | HA total, AZ independente |

**Justificativa da Abordagem:**

1. ✅ **Rastreabilidade:** Baseline documentado como código (IaC)
2. ✅ **Segurança:** Zero risco de modificar recursos em produção (engenharia reversa é read-only)
3. ✅ **Testabilidade:** Scripts validáveis localmente no WSL antes de aplicar
4. ✅ **Incrementalidade:** Expansão gradual (2 AZs → 3 AZs) sem downtime
5. ✅ **Economia:** Opção de usar NAT existente reduz custo inicial
6. ✅ **Flexibilidade:** Possibilidade de adicionar NAT dedicado posteriormente sem downtime

**Validação de Ambiente WSL:**

O ambiente WSL está **100% instrumentado** para execução dos scripts:

```
✅ AWS CLI v2.33.4 (compatível)
✅ Terraform v1.14.3 (latest)
✅ kubectl v1.34.1 (latest)
✅ Docker v29.1.3 (para testes de containers)
✅ jq v1.7 (para parsing JSON)
✅ git v2.43.0 (para versionamento)
✅ curl v8.5.0 (para HTTP requests)
✅ Credenciais AWS configuradas (região: us-east-1)
```

**Testes Locais Possíveis:**

- ✅ `terraform plan` - Validar sintaxe e mudanças planejadas
- ✅ `terraform validate` - Validar configuração
- ✅ Scripts Bash - Executar dry-run completo
- ✅ AWS CLI - Consultar recursos via read-only APIs
- ❌ `terraform apply` - **NÃO** executar em WSL (risco de criar recursos duplicados)

**Workflow Recomendado:**

```bash
# 1. WSL: Engenharia Reversa (read-only, seguro)
./00-marco0-reverse-engineer-vpc.sh
cd vpc-reverse-engineered/terraform
terraform init
terraform plan  # Validar equivalência

# 2. WSL: Preparar Incremental (validação local)
cd ../../
./01-marco0-incremental-add-region.sh
cd marco0-incremental-1c
make init
make plan  # Revisar mudanças planejadas

# 3. AWS Console ou CI/CD: Aplicar (produção)
make apply-no-nat  # Executar APENAS em ambiente controlado
make validate      # Verificar recursos criados
```

**Condições obrigatórias:**
- [x] Ambiente WSL instrumentado e validado
- [x] Scripts de engenharia reversa criados
- [x] Scripts incrementais criados
- [x] Documentação de uso completa
- [ ] Execução do script de engenharia reversa
- [ ] Validação do Terraform gerado
- [ ] Execução do script incremental (ambiente controlado)
- [ ] Validação de recursos criados na AWS

**Alternativas consideradas:**
1. **Terraform Import Manual:** Rejeitada (trabalhoso, propenso a erros, não escalável)
2. **Recriação Total da VPC:** Rejeitada (downtime, custo adicional, risco)
3. **Engenharia Reversa + Incremental (ESCOLHIDA):** Baseline + evolução gradual

**Impacto:**
- 🕐 Timeline: Marco 0 pronto em ~2-3 horas (execução dos scripts)
- 💰 Financeiro: $0 (engenharia reversa) + $0-32/mês (incremental, conforme escolha)
- 🔒 Segurança: Risco ZERO (read-only + validação local antes de apply)
- 🏗️ Arquitetura: Baseline sólido para evolução futura

**Validação:**
- [x] Scripts criados e validados
- [x] Ambiente WSL instrumentado
- [x] Documentação completa
- [ ] Execução bem-sucedida do script de engenharia reversa
- [ ] Terraform plan validado (equivalência com estado atual)
- [ ] Execução do script incremental (ambiente controlado)
- [ ] Recursos de us-east-1c criados e validados

---

## 📚 Referências

### Documentos do Projeto
- [Plano de Execução AWS Console](aws-console-execution-plan.md)
- [Índice Geral](00-indice-geral.md)
- [Infraestrutura Base AWS](01-infraestrutura-base-aws.md)

### Documentação AWS
- [Amazon EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [VPC and Subnet Sizing](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Subnets.html)
- [EKS Network Requirements](https://docs.aws.amazon.com/eks/latest/userguide/network_reqs.html)
- [Security Groups for EKS](https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html)

### ADRs (Architecture Decision Records)
- [ADR-001: AWS EKS como plataforma de orquestração](../../adr/ADR-001-escolha-kubernetes-eks.md)
- [ADR-002: Kyverno como Policy Engine](../../adr/ADR-002-policy-engine-kyverno.md)

---

## 🔄 Changelog

| Data | Versão | Alterações | Autor |
|------|--------|------------|-------|
| 2026-01-22 | 1.0 | Criação do diário de bordo, análise de VPC existente | DevOps Team |

---

**Última atualização:** 2026-01-22
**Próxima revisão:** Após criação das subnets EKS
**Mantenedor:** DevOps Team
