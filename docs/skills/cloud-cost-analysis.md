# Skill: Cloud Cost Analysis

> **Especialização**: Análise financeira e técnica de infraestrutura cloud  
> **Aplicável a**: Cloud Architects (AWS, Azure, GCP), CTO, Gestores  
> **Output**: Documentos estruturados com custos, arquitetura e comparações

---

## 🎯 Objetivo

Esta skill ensina como criar **documentos técnico-financeiros estruturados** para análise de custos de infraestrutura cloud, incluindo:
- Levantamento detalhado de componentes
- Cálculo de custos por serviço e domínio
- Tabelas comparativas
- Gráficos e diagramas (Mermaid)
- Análise de trade-offs
- Recomendações estratégicas

---

## 📋 Estrutura do Documento de Análise de Custos

### 1. Cabeçalho e Contexto

```markdown
# Agente: Cloud Architect [CLOUD_NAME]

> **Especialização**: [Cloud Provider]  
> **Domínio**: Provisionamento de infraestrutura cloud-específica  
> **Output**: Documentos técnicos com custos, arquitetura e componentes  
> **Skill Associada**: [cloud-cost-analysis.md](../skills/cloud-cost-analysis.md)

---

## 🎯 Objetivo

Você é o **Cloud Architect especializado em [CLOUD]**, responsável por:
1. **Provisionar infraestrutura** para os 6 domínios da plataforma
2. **Gerar documentos técnicos** com detalhes de componentes e custos
3. **Manter documentos atualizados** conforme evolução do projeto
4. **Calcular custos** baseados em régua de estrutura básica e short
5. **Colaborar com agente CTO** fornecendo inputs para consolidação
```

**Elementos Obrigatórios**:
- Nome do agente e especialização
- Domínio de atuação
- Tipo de output esperado
- Referência à skill (este documento)

---

### 2. Provisionamento de Clusters Kubernetes

#### Template:

```markdown
### 1. Provisionamento de Clusters Kubernetes
- **Serviço**: [EKS / AKS / GKE]
- **Configuração Básica**:
  - Control Plane gerenciado (alta disponibilidade)
  - Node Groups/Pools com Auto Scaling
  - Networking (VPC, VNet, VPC)
  - Load Balancer para ingress
  - Security Groups/NSGs/Firewall Rules

**Referência**: [ADR-020 - Provisionamento de Clusters](../../SAD/docs/adrs/adr-020-provisionamento-clusters.md)
```

**Detalhes Necessários**:
- Nome do serviço managed Kubernetes
- Tipo de control plane (managed, regional, zonal)
- SLA esperado
- Configuração de rede básica
- Referência ao ADR-020 (cloud-agnostic)

---

### 3. Provisionamento por Domínio

Para cada um dos 6 domínios, documentar:

#### Template por Domínio:

```markdown
#### 2.X [DOMAIN_NAME]
**Componentes [CLOUD]**:
- Componente 1: descrição técnica
- Componente 2: descrição técnica
- Componente 3: descrição técnica

**Custos Estimados (Basic/Short)**:
| Componente | Quantidade | Custo Mensal (USD) |
|------------|------------|-------------------|
| Componente 1 | X unidades | $Y |
| Componente 2 | X unidades | $Y |
| Componente 3 | X unidades | $Y |
| **TOTAL** | | **$ZZZ** |
```

**Regras de Cálculo**:
1. **Basic/Short**: Configuração mínima viável para produção
   - Instâncias pequenas (t3.medium, Standard_B2s, e2-medium)
   - Storage básico (gp3, Standard SSD, pd-standard)
   - Single-AZ quando possível (NAT, data services)
   - Managed services tier básico

2. **Fontes de Preço**:
   - AWS: [AWS Pricing Calculator](https://calculator.aws/)
   - Azure: [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/)
   - GCP: [Google Cloud Pricing Calculator](https://cloud.google.com/products/calculator)

3. **Atualização de Preços**: Revisar trimestralmente (clouds mudam preços)

---

### 4. Custo Total e Gráfico de Distribuição

#### Template:

```markdown
## 💰 Custo Total [CLOUD] (Estrutura Básica/Short)

\`\`\`mermaid
pie title Distribuição de Custos [CLOUD] por Domínio
    "Platform-Core" : XXX
    "CI/CD Platform" : XXX
    "Observability" : XXX
    "Data Services" : XXX
    "Secrets Management" : XXX
    "Security" : XXX
\`\`\`

| Domínio | Custo Mensal (USD) |
|---------|-------------------|
| Platform-Core | $XXX |
| CI/CD Platform | $XXX |
| Observability | $XXX |
| Data Services | $XXX |
| Secrets Management | $XXX |
| Security | $XXX |
| **TOTAL MENSAL** | **$XXX** |
| **TOTAL ANUAL** | **$XXX** |
```

**Gráfico Mermaid - Pie Chart**:
- Usar para mostrar distribuição percentual de custos
- Valores numéricos (não percentuais)
- Título claro com nome da cloud

**Tabela de Custos**:
- Custo mensal por domínio
- Total mensal (soma)
- Total anual (mensal x 12)

---

### 5. Arquitetura Visual (Mermaid)

#### Template:

```markdown
## 🏗️ Arquitetura [CLOUD] (Mermaid)

\`\`\`mermaid
graph TB
    subgraph "[CLOUD] Cloud"
        subgraph "Network Layer"
            LB[Load Balancer]
        end
        
        subgraph "Kubernetes Cluster"
            CP[Control Plane<br/>Managed]
            NP1[Node Pool 1<br/>Type x Count]
        end
        
        subgraph "Data Layer"
            DB[(Database<br/>Service)]
            CACHE[(Cache<br/>Service)]
        end
        
        subgraph "Managed Services"
            STORAGE[Object Storage]
            SECRETS[Secrets Manager]
        end
        
        subgraph "Security"
            SEC1[Security Service 1]
            SEC2[Security Service 2]
        end
    end
    
    Internet((Internet)) --> LB
    LB --> CP
    CP --> NP1
    NP1 --> DB
    NP1 --> CACHE
    NP1 --> STORAGE
    
    style CP fill:#[CLOUD_COLOR]
    style LB fill:#[CLOUD_COLOR]
\`\`\`
```

**Regras de Diagrama**:
1. **Estrutura hierárquica**: Cloud → Network → Cluster → Data → Services → Security
2. **Subgraphs**: Usar para agrupar componentes logicamente
3. **Nodes**: Nome do serviço + especificações (tipo, tamanho)
4. **Edges**: Fluxo de comunicação (Internet → LB → Cluster → Data)
5. **Cores**: Usar cores oficiais das clouds
   - AWS: `#FF9900`
   - Azure: `#0078D4`
   - GCP: `#4285F4`

---

### 6. Detalhamento Técnico por Domínio

Para cada domínio, incluir seção expandida:

#### Template:

```markdown
## 📊 Detalhamento Técnico por Domínio

### [DOMAIN_NAME]

**Objetivo**: [Breve descrição do domínio]

**Componentes Detalhados**:
1. **[Componente 1]**
   - Especificação: [tipo, tamanho, IOPS, throughput]
   - Configuração: [parâmetros relevantes]
   - SLA: [uptime, RTO, RPO]
   - Backup: [estratégia de backup]

2. **[Componente 2]**
   - [mesmo padrão]

**Terraform Providers** (para Platform-Core):
\`\`\`hcl
provider "[cloud]" {
  # configuração
}

provider "kubernetes" {
  # configuração
}

provider "helm" {
  # configuração
}
\`\`\`

**Outputs para Domínios**:
\`\`\`hcl
output "cluster_endpoint" {
  value = [cluster_reference]
}

output "storage_class_name" {
  value = "[storage_class]"
}
\`\`\`

**Connection Strings** (para Data Services):
\`\`\`yaml
# PostgreSQL
postgresql://user:pass@endpoint:5432/db

# Redis
redis://endpoint:6379
\`\`\`

**Custo Breakdown**:
- Componente A: $X/mês (Y% do total)
- Componente B: $X/mês (Y% do total)
- Data transfer: $X/mês
```

**Profundidade Necessária**:
- Especificações técnicas precisas (vCPU, RAM, IOPS, throughput)
- Configuração de alta disponibilidade
- Estratégia de backup e retenção
- Connection strings e endpoints
- Terraform providers e outputs
- Breakdown de custo detalhado

---

### 7. Workflow de Atualização

#### Template:

```markdown
## 🔄 Workflow de Atualização

### 1. Monitoramento de Evolução
- Acompanhar [docs/logs/log-de-progresso.md](../logs/log-de-progresso.md)
- Verificar mudanças no [SAD](../../SAD/docs/sad.md)
- Observar novos ADRs em [SAD/docs/adrs/](../../SAD/docs/adrs/)

### 2. Atualização de Documentos
Quando houver mudanças arquiteturais:
- Recalcular custos com base em novas configurações
- Atualizar diagramas Mermaid
- Revisar tabelas de componentes
- Adicionar novos serviços necessários

### 3. Versionamento
- Manter histórico de versões neste documento
- Documentar mudanças significativas de custo (>10%)
- Justificar decisões de trade-off (custo vs performance)
```

---

### 8. Colaboração com CTO

#### Template:

```markdown
## 🤝 Colaboração com CTO

### Inputs Fornecidos para Consolidação
1. **Custo Total [CLOUD]**: $XXX/mês ($YYY/ano)
2. **Breakdown por Domínio**: tabela detalhada
3. **Arquitetura Visual**: diagrama Mermaid
4. **Trade-offs [CLOUD]-específicos**:
   - Managed service A vs self-hosted: +X% custo, -Y% esforço
   - Configuration B vs C: +X% custo, +Y% SLA
   - [Cloud-specific insights]

### Perguntas para CTO
1. Prioridade: custo ou redução de esforço operacional?
2. Aceitável usar managed services ou preferir self-hosted?
3. Requisitos de SLA (RTO/RPO) justificam Multi-AZ?
4. Budget anual disponível para [CLOUD]?
```

---

### 9. Referências e Histórico

#### Template:

```markdown
## 📚 Referências

- [SAD v1.1](../../SAD/docs/sad.md)
- [ADR-003: Cloud-Agnostic](../../SAD/docs/adrs/adr-003-cloud-agnostic.md)
- [ADR-004: IaC e GitOps](../../SAD/docs/adrs/adr-004-iac-gitops.md)
- [ADR-020: Provisionamento de Clusters](../../SAD/docs/adrs/adr-020-provisionamento-clusters.md)
- [ADR-019: FinOps](../../SAD/docs/adrs/adr-019-finops.md)
- [[CLOUD] Pricing Calculator](https://...)
- [[CLOUD] Best Practices](https://...)

---

## 📝 Histórico de Versões

| Versão | Data | Autor | Mudanças |
|--------|------|-------|----------|
| 1.0 | YYYY-MM-DD | Cloud Architect [CLOUD] | Versão inicial com custos básicos/short |
```

---

## 🎨 Guia de Gráficos Mermaid

### 1. Pie Chart (Distribuição de Custos)

**Uso**: Mostrar distribuição percentual de custos por domínio

```mermaid
pie title Distribuição de Custos por Domínio
    "Platform-Core" : 218.50
    "CI/CD Platform" : 95
    "Observability" : 53
    "Data Services" : 196
    "Secrets Management" : 2.80
    "Security" : 34
```

**Sintaxe**:
```
pie title [TÍTULO]
    "[Label 1]" : [Valor Numérico]
    "[Label 2]" : [Valor Numérico]
```

**Dicas**:
- Usar valores numéricos (não percentuais)
- Mermaid calcula percentuais automaticamente
- Máximo 8-10 slices para legibilidade

---

### 2. Graph TB/LR (Arquitetura)

**Uso**: Mostrar arquitetura cloud com componentes e fluxos

```mermaid
graph TB
    subgraph "AWS Cloud"
        subgraph "VPC"
            ALB[Application Load Balancer]
            EKS[EKS Cluster]
        end
        S3[S3 Bucket]
    end
    
    Internet((Internet)) --> ALB
    ALB --> EKS
    EKS --> S3
    
    style EKS fill:#FF9900
```

**Sintaxe**:
- `graph TB`: Top to Bottom
- `graph LR`: Left to Right
- `subgraph "[Título]"`: Agrupamento
- `Node[Label]`: Nó retangular
- `Node[(Label)]`: Nó cilíndrico (banco de dados)
- `Node((Label))`: Nó circular
- `A --> B`: Seta direcionada
- `style Node fill:#COLOR`: Colorir nó

**Dicas**:
- Usar subgraphs para hierarquia (Cloud → Network → Cluster → Services)
- Cores das clouds: AWS `#FF9900`, Azure `#0078D4`, GCP `#4285F4`
- Limitar a 15-20 nodes para legibilidade

---

### 3. Quadrant Chart (Análise Multi-Dimensional)

**Uso**: Comparar clouds em 2 dimensões (ex: custo vs esforço)

```mermaid
%%{init: {'theme':'base'}}%%
quadrantChart
    title Análise: Custo vs Esforço Operacional
    x-axis Menor Esforço --> Maior Esforço
    y-axis Maior Custo --> Menor Custo
    quadrant-1 Alta Eficiência
    quadrant-2 Baixo Custo
    quadrant-3 Não Recomendado
    quadrant-4 Premium
    Azure: [0.3, 0.4]
    AWS: [0.5, 0.5]
    GCP: [0.6, 0.2]
```

**Sintaxe**:
- `x-axis [Label Esquerda] --> [Label Direita]`
- `y-axis [Label Inferior] --> [Label Superior]`
- `quadrant-N [Label]`: Nomear quadrantes
- `[Item]: [X, Y]`: Posicionar item (valores 0.0 a 1.0)

**Dicas**:
- Normalizar valores para escala 0.0-1.0
- Quadrante superior-esquerdo = ideal (depende do contexto)
- Máximo 5-7 pontos para legibilidade

---

### 4. Comparison Table (Markdown)

**Uso**: Comparar custos, specs, SLAs entre clouds

```markdown
| Domínio | AWS | Azure | GCP | Menor |
|---------|-----|-------|-----|-------|
| **Platform-Core** | $218.50 | $63.53 | $170.20 | **Azure** (-71%) |
| **CI/CD Platform** | $95.00 | $145.00 | $332.10 | **AWS** (-34%) |
| **TOTAL** | **$599.30** | **$615.12** | **$837.11** | **AWS** (-2.6%) |
```

**Dicas**:
- Coluna "Menor" mostra vencedor + economia percentual
- Bold para destacar totais e vencedores
- Alinhar números à direita para melhor legibilidade

---

## 🧮 Fórmulas de Cálculo

### 1. Custo Total por Domínio

```
Custo_Domínio = Σ (Custo_Componente_i)
```

**Exemplo**:
```
Platform-Core = EKS ($73) + EC2 ($90) + ALB ($20) + NAT ($35) + Route53 ($0.50)
              = $218.50
```

### 2. Custo Total Mensal

```
Custo_Mensal = Σ (Custo_Domínio_i)
```

### 3. Custo Total Anual

```
Custo_Anual = Custo_Mensal × 12
```

### 4. Economia com Reserved Instances

```
Economia_RI = Custo_On_Demand × (1 - Discount_Rate)
```

**Discount Rates**:
- 1-Year RI: 30%
- 3-Year RI: 40%

**Exemplo**:
```
AWS On-Demand: $7,191.60/ano
AWS 3-Year RI: $7,191.60 × (1 - 0.40) = $4,314.96/ano
Economia: $2,876.64/ano (40%)
```

### 5. Comparação Percentual entre Clouds

```
Diferença_% = ((Custo_Cloud_A - Custo_Cloud_B) / Custo_Cloud_B) × 100
```

**Exemplo**:
```
Azure vs AWS: (($615.12 - $599.30) / $599.30) × 100 = +2.6%
GCP vs AWS: (($837.11 - $599.30) / $599.30) × 100 = +39.7%
```

### 6. Breakdown Percentual por Domínio

```
Percentual_Domínio = (Custo_Domínio / Custo_Total) × 100
```

**Exemplo**:
```
Platform-Core (AWS): ($218.50 / $599.30) × 100 = 36.5%
```

---

## 📐 Checklist de Qualidade do Documento

Antes de finalizar o documento, verificar:

### Completude
- [ ] Todos os 6 domínios documentados
- [ ] Custo total mensal e anual calculado
- [ ] Breakdown por componente para cada domínio
- [ ] Pelo menos 1 gráfico Mermaid (pie chart ou arquitetura)
- [ ] Detalhamento técnico com specs precisas
- [ ] Trade-offs documentados
- [ ] Referências ao SAD e ADRs relevantes

### Precisão
- [ ] Custos verificados no pricing calculator da cloud
- [ ] Especificações técnicas corretas (vCPU, RAM, IOPS, throughput)
- [ ] SLAs e disponibilidade documentados
- [ ] Connection strings e endpoints realistas
- [ ] Terraform providers e outputs corretos

### Formatação
- [ ] Markdown válido (tables, code blocks, links)
- [ ] Gráficos Mermaid renderizam corretamente
- [ ] Tabelas alinhadas e legíveis
- [ ] Títulos e subtítulos hierárquicos
- [ ] Emojis consistentes (🎯, 📋, 💰, 🏗️, 📊, 🔄, 🤝, 📚, 📝)

### Manutenibilidade
- [ ] Histórico de versões presente
- [ ] Workflow de atualização documentado
- [ ] Referências a documentos externos corretas
- [ ] Skill associada mencionada

---

## 🎯 Casos de Uso

### 1. Cloud Architect: Documentar Nova Cloud

**Cenário**: Criar documento de análise para uma nova cloud (ex: Oracle Cloud)

**Passos**:
1. Copiar template desta skill
2. Pesquisar serviços equivalentes (Managed Kubernetes, Object Storage, etc)
3. Coletar preços no pricing calculator da cloud
4. Calcular custo por domínio
5. Criar diagrama de arquitetura (Mermaid)
6. Documentar trade-offs específicos da cloud
7. Adicionar seção de colaboração com CTO

**Output**: `docs/agents/cloud-architect-[CLOUD].md`

---

### 2. Cloud Architect: Atualizar Custos Trimestralmente

**Cenário**: Revisar e atualizar custos após 3 meses

**Passos**:
1. Verificar mudanças de preço no pricing calculator
2. Recalcular custos por domínio
3. Atualizar tabelas de custo
4. Atualizar gráfico Mermaid (pie chart)
5. Documentar mudanças >10% com justificativa
6. Adicionar nova entrada no histórico de versões

**Output**: `docs/agents/cloud-architect-[CLOUD].md` (v1.1)

---

### 3. CTO: Consolidar Análises Multi-Cloud

**Cenário**: Comparar 3 clouds e tomar decisão estratégica

**Passos**:
1. Ler documentos dos 3 Cloud Architects
2. Criar tabela comparativa (custo total, breakdown por domínio)
3. Criar gráfico comparativo (Mermaid quadrant chart ou bar chart)
4. Analisar trade-offs de cada cloud
5. Definir 3 cenários (Mínimo Custo, Balanced, Premium)
6. Fazer recomendação final com justificativa
7. Documentar roadmap de implementação

**Output**: `docs/agents/cto.md`

---

### 4. Gestor: Criar Relatório Executivo

**Cenário**: Extrair informações para apresentação a stakeholders

**Passos**:
1. Ler documento do CTO
2. Extrair custo total por cloud (tabela + gráfico)
3. Extrair recomendação final
4. Extrair roadmap de implementação
5. Extrair oportunidades de FinOps (economia com RIs, right-sizing)
6. Formatar em slides (PowerPoint, Google Slides)

**Output**: `docs/reports/cloud-cost-executive-summary.pptx`

---

## 📚 Referências e Ferramentas

### Pricing Calculators
- **AWS**: https://calculator.aws/
- **Azure**: https://azure.microsoft.com/pricing/calculator/
- **GCP**: https://cloud.google.com/products/calculator

### Best Practices
- **AWS**: https://aws.amazon.com/architecture/well-architected/
- **Azure**: https://learn.microsoft.com/azure/well-architected/
- **GCP**: https://cloud.google.com/architecture/framework

### Mermaid Documentation
- **Official Docs**: https://mermaid.js.org/
- **Live Editor**: https://mermaid.live/

### FinOps Foundation
- **Website**: https://www.finops.org/
- **Framework**: https://www.finops.org/framework/

---

## 📝 Histórico de Versões

| Versão | Data | Autor | Mudanças |
|--------|------|-------|----------|
| 1.0 | 2026-01-05 | System | Versão inicial da skill de análise de custos cloud |

---

**Usada por**:
- [Cloud Architect AWS](../agents/cloud-architect-aws.md)
- [Cloud Architect Azure](../agents/cloud-architect-azure.md)
- [Cloud Architect GCP](../agents/cloud-architect-gcp.md)
- [CTO](../agents/cto.md)
