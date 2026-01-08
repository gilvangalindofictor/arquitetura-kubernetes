# Mesa Técnica: Decisões Críticas para o Quickstart AWS EKS

**Data**: 2026-01-07
**Participantes**: Arquitetura, TI, Gestão, Financeiro
**Objetivo**: Avaliar viabilidade e dimensionamento correto do ambiente Kubernetes proposto

---

## Contexto

Estamos avaliando a implementação de uma plataforma Kubernetes (EKS) na AWS conforme descrito no [AWS EKS Quickstart](aws-eks-gitlab-quickstart.md). Antes de prosseguir, precisamos decidir sobre 3 questões fundamentais que impactam custo, complexidade e adequação ao time atual.

---

## Questão 1: Por que não usar EC2 simples ao invés de Kubernetes?

### 🎭 Argumentos PRÓ EC2 (Abordagem Tradicional)

**Apresentado por: Gestor de TI**

"Olha, nossa equipe conhece EC2. Subimos uma máquina, instalamos GitLab via apt-get, configuramos PostgreSQL, colocamos um Nginx na frente e pronto. Por que complicar?"

**Vantagens do EC2 Simples:**

1. **Curva de Aprendizado Quase Zero**
   - Time já sabe SSH, systemd, apt/yum
   - Não precisa entender pods, deployments, helm charts
   - Troubleshooting familiar (logs em `/var/log/`, `systemctl status`)

2. **Custo Inicial Menor (Aparente)**
   ```
   Cenário EC2 Tradicional:
   - 1x EC2 t3.large (GitLab): $60/mês
   - 1x EC2 t3.medium (PostgreSQL): $30/mês
   - 1x EC2 t3.small (Redis): $15/mês
   - EBS gp3 (100GB): $10/mês
   - ALB: $23/mês
   TOTAL: ~$138/mês USD (R$ 828/mês)

   vs

   Quickstart Kubernetes:
   - EKS Control Plane: $73/mês
   - 3x EC2 t3.medium (nodes): $90/mês
   - RDS t3.small: $30/mês
   - EBS + S3: $20/mês
   - ALB: $23/mês
   TOTAL: ~$236/mês USD (R$ 1.416/mês)

   Diferença: +$98/mês (+71% mais caro)
   ```

3. **Deploy Imediato**
   - GitLab instalado em 2-3 horas
   - Sem necessidade de entender Kubernetes

4. **Manutenção "Conhecida"**
   - Backup via rsync + snapshot EBS
   - Update via apt-get upgrade
   - Monitoramento com CloudWatch básico

**Citação do Gestor:**
> "Temos 2 analistas de infra que sabem gerenciar VMs. Nenhum sabe Kubernetes. Pra quê arriscar?"

---

### 🎯 Argumentos PRÓ Kubernetes (Plataforma)

**Apresentado por: Arquiteto de Soluções**

"EC2 funciona... até não funcionar mais. Deixa eu mostrar o que acontece em 6-12 meses."

#### **Problema 1: Escalabilidade Bloqueada**

**Cenário Real**:
```
Mês 1: GitLab rodando bem em t3.large
Mês 3: Time cresce, 50 pipelines concorrentes
Resultado: GitLab travando, runners insuficientes

Solução EC2:
❌ Resize da VM = DOWNTIME de 15-30min
❌ Adicionar mais runners = provisionamento manual
❌ Ajustar recursos = reiniciar serviços
```

**Solução Kubernetes**:
```yaml
# Apenas editar o manifesto
spec:
  replicas: 5  # Era 2, agora 5
  resources:
    requests:
      cpu: "2"   # Era 1, agora 2
```
✅ Zero downtime
✅ Ajuste em < 5 minutos
✅ Rollback automático se falhar

#### **Problema 2: Disaster Recovery Complexo**

**EC2 Tradicional**:
```bash
# Procedimento de DR:
1. Restaurar snapshot EBS (10-30min)
2. Iniciar nova EC2
3. Reconfigurar IPs/DNS
4. Restaurar dump PostgreSQL (variável)
5. Testar serviços manualmente
6. Rezar para tudo funcionar

RTO (Recovery Time Objective): 2-4 horas
RPO (Recovery Point Objective): 24 horas (backup diário)
Risco: Alto (processo manual, propenso a erro)
```

**Kubernetes**:
```bash
# Procedimento de DR:
1. Velero restore backup (5-10min)
2. RDS automated snapshot restore (10-15min)
3. Validação automática de health checks

RTO: < 30 minutos
RPO: < 1 hora (backups contínuos)
Risco: Baixo (processo automatizado, testado)
```

#### **Problema 3: Multi-Ambiente Caro em EC2**

**Crescimento Natural do Projeto**:

```
Hoje: "Só precisamos de um ambiente dev/test"

Mês 4: "Precisamos de staging para homologação"
Solução EC2: Clonar TODAS as VMs = 2x custo

Mês 6: "Precisamos de produção separada"
Solução EC2: Clonar NOVAMENTE = 3x custo

Custo EC2 Multi-Ambiente:
- Dev: $138/mês
- Staging: $138/mês
- Prod: $276/mês (HA, instâncias maiores)
TOTAL: $552/mês (R$ 3.312/mês)
```

**Kubernetes**:
```
Mês 4: Adicionar namespace staging
Custo adicional: +$50/mês (RDS staging + storage)

Mês 6: Adicionar namespace prod
Custo adicional: +$120/mês (recursos dedicados)

Custo K8s Multi-Ambiente:
- Cluster único: $236/mês (base)
- + Staging: +$50/mês
- + Prod: +$120/mês
TOTAL: $406/mês (R$ 2.436/mês)

Economia: $146/mês (-26%)
```

#### **Problema 4: Vendor Lock-In**

**EC2**: Totalmente amarrado à AWS
- Scripts específicos AWS CLI
- Dependência de AMIs customizadas
- Networking específico VPC/SG

**Kubernetes**: Cloud-agnostic (conforme ADR-003)
- Helm charts funcionam em qualquer cloud
- Migração AWS → Azure → GCP possível
- Multi-cloud feasible (futuro)

#### **Problema 5: Observabilidade Primitiva**

**EC2**:
```
Monitoramento:
- CloudWatch (métricas básicas de VM)
- Logs espalhados em /var/log/
- Sem tracing distribuído
- Sem correlação entre serviços

Troubleshooting:
"GitLab está lento"
→ SSH na VM
→ Rodar top, iotop, netstat
→ Checar logs manualmente
→ Tentar adivinhar o problema
Tempo médio: 1-3 horas
```

**Kubernetes**:
```
Monitoramento (Quickstart já inclui):
- Prometheus (métricas de TUDO)
- Loki (logs centralizados)
- Tempo (tracing distribuído)
- Grafana (dashboards prontos)

Troubleshooting:
"GitLab está lento"
→ Abrir Grafana
→ Ver dashboard GitLab CI
→ Identificar: "Runner X com CPU 100%"
→ Escalar runners automaticamente
Tempo médio: 5-10 minutos
```

---

### 📊 Comparativo Técnico Detalhado

| Aspecto | EC2 Tradicional | Kubernetes (EKS) | Vencedor |
|---------|-----------------|------------------|----------|
| **Setup Inicial** | 4-6h | 3 sprints (6 semanas) | EC2 ✅ |
| **Custo Inicial** | $138/mês | $236/mês | EC2 ✅ |
| **Curva Aprendizado** | Baixa | Alta | EC2 ✅ |
| **Escalabilidade** | Manual, com downtime | Automática, zero downtime | K8s ✅ |
| **Multi-Ambiente** | 3x custo | 1.7x custo | K8s ✅ |
| **Disaster Recovery** | RTO: 2-4h, manual | RTO: < 30min, automático | K8s ✅ |
| **Observabilidade** | Básica (CloudWatch) | Completa (Prom+Grafana+Loki+Tempo) | K8s ✅ |
| **Vendor Lock-in** | Total (AWS) | Baixo (cloud-agnostic) | K8s ✅ |
| **Manutenção** | Conhecida, manual | Automatizada, declarativa | K8s ✅ |
| **Custo em 12 meses** | $1.656 (single env) | $2.832 (multi-env pronto) | K8s ✅ |
| **Evolução Futura** | Refatoração total | Incremental | K8s ✅ |

**Score**: EC2 (3 pontos) vs Kubernetes (8 pontos)

---

### 💡 Recomendação: Quando Usar Cada Um

**Use EC2 Tradicional SE:**
- ✅ Projeto tem vida útil definida (< 12 meses)
- ✅ Ambiente NUNCA vai crescer além de 1 servidor
- ✅ Time tem zero capacidade de aprender (extremamente improvável)
- ✅ Budget crítico (não tem R$ 500/mês adicionais)

**Use Kubernetes (Quickstart) SE:**
- ✅ Projeto é estratégico de longo prazo
- ✅ Previsão de crescimento (mais apps, mais ambientes)
- ✅ Time disposto a aprender (investimento em capacitação)
- ✅ Quer evitar refatoração brutal no futuro

**Decisão Recomendada**: **Kubernetes (EKS)**

**Razão**: O "investimento" de R$ 1.416/mês vs R$ 828/mês (diferença de R$ 588/mês) é na verdade um **seguro contra débito técnico futuro**. Em 6-12 meses, migrar de EC2 para K8s custaria:
- 3-4 meses de trabalho (R$ 60.000 - R$ 80.000 em consultoria)
- Downtime durante migração
- Risco de perda de dados

Gastar R$ 588/mês hoje evita gastar R$ 70.000 amanhã.

---

## Questão 2: Time Pequeno Precisa de Ambiente DEV? (Dev vs Staging+Prod)

### 🎭 Argumentos PRÓ Eliminar DEV

**Apresentado por: Gestor Financeiro**

"Somos uma equipe pequena. Ninguém vai estar desenvolvendo em paralelo. Por que pagar por um ambiente DEV que vai ficar ocioso 80% do tempo?"

**Análise de Utilização Real**:

```
Time Atual:
- 2 Analistas de Infra (não desenvolvem apps)
- 1 DBA (não desenvolve apps)
- 0 Desenvolvedores full-time

Apps Planejados:
- GitLab (3rd party, não desenvolvemos)
- Observability (3rd party, não desenvolvemos)
- Talvez 1-2 scripts internos/ano
```

**Economia Proposta**:

```diff
Cenário Atual (3 ambientes):
- Dev: $120/mês
- Staging: $150/mês
- Prod: $280/mês
TOTAL: $550/mês

Cenário 2 ambientes:
- Staging (usado para testes): $180/mês
- Prod: $280/mês
TOTAL: $460/mês

Economia: $90/mês ($1.080/ano)
```

**Argumentos**:
1. "Dev ficaria ocioso 80% do tempo"
2. "Staging pode servir como dev+homologação"
3. "Economizamos quase R$ 6.500/ano"

---

### 🎯 Contra-Argumentos: Por Que DEV é CRÍTICO

**Apresentado por: Arquiteto + Engenheiro SRE**

"Não ter DEV é o equivalente a testar medicamentos direto em humanos, pulando os testes em laboratório."

#### **Realidade 1: Você VAI Desenvolver Mais Do Que Pensa**

**Apps Que Sempre Aparecem** (primeiros 12 meses):

```
Mês 2: "Precisamos de um dashboard customizado para o CEO"
→ 1 app Python/Node simples

Mês 4: "Integrações entre GitLab e sistema legado X"
→ Webhooks + API middlewares

Mês 6: "Automatizar onboarding de novos funcionários"
→ Scripts que viram microserviços

Mês 8: "Portal interno para requisições de TI"
→ App web completo

Mês 10: "Integrações com RH/Financeiro/etc"
→ Mais 2-3 apps
```

**Sem DEV**:
```
Desenvolvedor: "Vou testar essa integração nova"
Onde testar?
❌ Staging = Risco de quebrar homologação de outros
❌ Prod = Inaceitável
❌ Local = Não replica real behavior

Resultado: Deploy direto em staging
Consequência: Staging quebra, homologação atrasa, stress aumenta
```

**Com DEV**:
```
Desenvolvedor: "Vou testar essa integração nova"
Testa em DEV → Quebra? Sem problema! → Fix → Testa de novo
Aprova em DEV → Move pra Staging → Homologação limpa
Staging OK → Move pra Prod → Confiança alta
```

#### **Realidade 2: Experimentos e POCs**

**Cenários Comuns**:

```
"Vamos testar Kong API Gateway antes de decidir"
Sem DEV: Testa em staging → Quebra ambiente → Rollback demorado

"Vamos testar Linkerd antes de colocar em prod"
Sem DEV: Testa em staging → Problema de rede → 4h debugando

"Vamos testar nova versão do GitLab 17.x"
Sem DEV: Testa em staging → Incompatível com plugins → Downtime

"Vamos testar backup/restore"
Sem DEV: Testa em staging → Backup funciona, restore faz drop na database errada → Disaster
```

**Com DEV**: Todos esses testes em ambiente isolado, risco zero.

#### **Realidade 3: Onboarding de Novos Membros**

**Situação Inevitável**: Time vai crescer (contratar júnior, estagiário, ou novo pleno)

**Sem DEV**:
```
Novo Dev: "Onde eu testo meu código?"
Lead: "Usa staging, mas cuidado pra não quebrar"
Novo Dev: *nervoso, com medo de errar*
Resultado: Deploy lento, com medo, erro eventual catastrófico
```

**Com DEV**:
```
Novo Dev: "Onde eu testo meu código?"
Lead: "DEV é seu playground. Quebra à vontade, é pra isso que existe"
Novo Dev: *experimenta, quebra 10x, aprende rápido*
Resultado: Onboarding 3x mais rápido, menos stress
```

#### **Realidade 4: Troubleshooting Real**

**Cenário**: Bug reportado em produção

**Sem DEV**:
```
1. Tentar reproduzir localmente (50% de chance de funcionar)
2. Não consegue reproduzir
3. Tenta reproduzir em staging (pode afetar homologação em andamento)
4. Adiciona logs extras
5. Deploy em staging (afeta homologação)
6. Analisa logs
7. Fix
8. Testa em staging (afeta homologação)
9. Finalmente deploy em prod

Tempo médio: 4-8 horas
Risco: Alto (homologação impactada)
```

**Com DEV**:
```
1. Reproduz bug em DEV (ambiente idêntico a prod)
2. Adiciona logs/debug
3. Identifica root cause
4. Fix + testa em DEV
5. Valida em staging
6. Deploy em prod

Tempo médio: 1-2 horas
Risco: Zero (staging intocada)
```

---

### 📊 Análise de Custo-Benefício Real

**Custo de NÃO Ter DEV**:

```
Incidentes em Staging (estimativa conservadora):

Ano 1:
- 4 quebras de staging por experimentação: 4h cada = 16h downtime
- 6 problemas de homologação atrasada: 2h cada = 12h atraso
- 2 bugs em prod que poderiam ser pegos em dev: 8h cada = 16h fix urgente
TOTAL: 44 horas de problema/ano

Custo em tempo de engenharia:
44h × R$ 150/h (custo médio eng sênior) = R$ 6.600/ano

+ Custo de oportunidade (features não entregues): R$ 10.000/ano (estimativa)
+ Custo de stress/burnout da equipe: Inestimável

TOTAL: R$ 16.600+/ano em problemas
```

**Economia Real de DEV**:

```
Investimento: R$ 7.200/ano (R$ 600/mês)
Economia de problemas: R$ 16.600/ano

ROI: +130% (economia de R$ 9.400/ano)
```

#### **Recomendação de Configuração**

**Modelo "Dev Econômico"**:

```yaml
# Dev otimizado para custo
Recursos Dev:
  - Nodes compartilhados com staging (sem dedicados)
  - RDS t3.micro (suficiente para testes)
  - Sem HA (single-AZ)
  - Auto-shutdown fora horário (8h/dia útil)

Custo Otimizado:
  - Dev: $60/mês (compartilhando nodes)
  - Staging: $150/mês
  - Prod: $280/mês
TOTAL: $490/mês (economia de $60/mês vs design original)

Economia vs sem DEV: Ainda assim economiza R$ 4.400/ano em problemas
```

---

### 💡 Decisão Recomendada: **MANTER DEV (com otimização)**

**Razões**:
1. ✅ ROI positivo mesmo com custo (130% retorno)
2. ✅ Reduz risco de impacto em staging/prod
3. ✅ Permite experimentação segura
4. ✅ Facilita onboarding futuro
5. ✅ Otimização de custo possível ($60/mês vs $120/mês original)

**Exceção**: Eliminar DEV SOMENTE se:
- ❌ Time NUNCA vai desenvolver nada (apenas usa 3rd party apps)
- ❌ NUNCA vai fazer POCs/testes
- ❌ NUNCA vai crescer o time

**Realidade**: Isso é estatisticamente improvável. Toda empresa de TI eventualmente desenvolve algo.

---

## Questão 3: Faz Sentido Esse Investimento para um Depto de TI Sem Devs?

### 🎭 A Questão Fundamental

**Apresentado por: C-Level / Diretor de TI**

"Temos um departamento de TI operacional. Gerenciamos infraestrutura, damos suporte a usuários, mantemos sistemas legados. Não somos uma software house. Faz sentido investir R$ 1.400-3.000/mês em Kubernetes quando nem temos desenvolvedores?"

**Perfil Real do Time**:
```
Departamento de TI Atual:
├── 1 Gerente de TI
├── 2 Analistas de Infraestrutura (Windows/Linux admin)
├── 1 DBA (PostgreSQL/SQL Server)
├── 2 Analistas de Suporte (N1/N2)
└── 0 Desenvolvedores dedicados

Skills:
✅ Gerenciar VMs, Active Directory, backups
✅ Troubleshooting de rede, firewall, VPN
✅ Manutenção de bancos de dados
❌ Desenvolvimento de software
❌ Kubernetes, containers, orquestração
❌ GitOps, CI/CD avançado
```

---

### 📊 Análise: 3 Cenários Possíveis

#### **Cenário A: Status Quo (Sem Kubernetes)**

**Infraestrutura Atual Provável**:
```
- GitLab: Instalação manual em VM ou SaaS (gitlab.com)
- CI/CD: Runners em VMs avulsas
- Monitoramento: CloudWatch + Zabbix/Nagios legado
- Backups: Scripts rsync + snapshots manuais
- Ambientes: Dev/Staging/Prod em VMs separadas (ou tudo misturado)
```

**Problemas Crescentes**:

1. **Dep

endência de Terceiros**
   ```
   Situação atual:
   "Precisamos de uma dashboard customizada"
   → Contrata fornecedor: R$ 15.000 - R$ 30.000
   → Tempo: 2-3 meses
   → Manutenção: R$ 5.000/ano

   "Precisamos integrar Sistema A com Sistema B"
   → Contrata fornecedor: R$ 20.000 - R$ 40.000
   → Tempo: 3-4 meses
   → Resultado: API frágil, difícil de manter
   ```

2. **Custo de Oportunidade**
   ```
   Projetos que ficam na gaveta (porque "não temos dev"):
   - Portal de autoatendimento de TI
   - Automações de processos manuais
   - Integrações entre sistemas
   - Dashboards executivos customizados
   - APIs para parceiros externos

   Perda estimada: R$ 50.000 - R$ 100.000/ano em eficiência
   ```

3. **Vendor Lock-In Crescente**
   ```
   Cada sistema novo = novo fornecedor = nova dependência
   Resultado em 3 anos:
   - 10+ fornecedores diferentes
   - 10+ sistemas não integrados
   - R$ 200.000+/ano em licenças e manutenção
   - Zero autonomia técnica
   ```

**Custo Total Anual (Status Quo)**:
```
- Fornecedores e consultorias: R$ 80.000/ano
- Licenças de SaaS (GitLab, monitoring, etc): R$ 60.000/ano
- Overhead operacional (manual, ineficiente): R$ 40.000/ano
TOTAL: R$ 180.000/ano
```

---

#### **Cenário B: Kubernetes Sem Capacitação (Falha Garantida)**

**O Que Acontece**:
```
Mês 1-2: Time terceirizado implementa quickstart
Mês 3: Handoff para time interno
Mês 4: Primeiro problema crítico
  → Time não sabe debugar
  → Chama terceirizado de volta (R$ 5.000 - R$ 10.000/incidente)
Mês 6: Segundo problema
  → Mesma situação
Mês 9: Time frustra, quer voltar para VMs
Mês 12: Kubernetes abandonado, R$ 50.000 jogados fora
```

**Sintomas de Falha**:
- ❌ "Kubectl não funciona" = time não entende contextos
- ❌ "Pod crashando" = não sabem ver logs
- ❌ "Helm install falhou" = não entendem values.yaml
- ❌ "Como faço deploy?" = não sabem usar CI/CD

**Custo do Fracasso**:
```
- Investimento inicial: R$ 50.000 (implementação)
- 3-4 chamadas de suporte: R$ 30.000
- Migração de volta para VMs: R$ 20.000
- Perda de credibilidade: Inestimável
TOTAL: R$ 100.000 perdidos
```

---

#### **Cenário C: Kubernetes + Upskilling do Time (Transformação)**

**O Plano de Transformação** (12-18 meses):

**Fase 0-3 meses: Implementação + Capacitação Intensiva**
```
1. Terceirizado implementa quickstart (6 semanas)

2. PARALELAMENTE: Treinamento intensivo do time interno
   - Curso Kubernetes Foundation (40h): R$ 3.000/pessoa × 3 = R$ 9.000
   - Treinamento hands-on com terceirizado (60h): R$ 30.000
   - Certificação CKA opcional (1 pessoa): R$ 5.000

3. Knowledge Transfer estruturado:
   - Semana 1-2: Shadowing (time observa terceirizado)
   - Semana 3-4: Pair programming (fazem juntos)
   - Semana 5-6: Time faz, terceirizado valida
   - Semana 7-8: Time independente, terceirizado suporte
```

**Fase 3-6 meses: Consolidação**
```
Time interno:
- Gerencia operações dia-a-dia
- Faz deploy de apps simples
- Troubleshooting básico (70% dos problemas)
- Chama terceirizado apenas para 30% complexos

Novos projetos simples:
- Dashboard customizado #1 (feito internamente!)
- Integração API simples
- Automação de processo manual
```

**Fase 6-12 meses: Autonomia**
```
Time interno:
- 90% troubleshooting independente
- Implementa novos apps sem ajuda
- Evolui a plataforma (adiciona namespaces, etc)
- Apenas consultorias pontuais para arquitetura

Novos projetos médios:
- Portal de autoatendimento completo
- 3-4 microsserviços internos
- Integrações complexas
```

**Fase 12-18 meses: Transformação Completa**
```
Time evoluiu para:
- DevOps Engineers (não mais simples admins)
- Capazes de contratar/mentorear júniors
- Autonomia para 95% dos cenários
- Referência técnica na organização

Projetos avançados:
- Multi-cluster (prod dedicado)
- Service mesh (Linkerd)
- Platform engineering (Backstage)
```

**Investimento em Capacitação**:
```
Ano 1:
- Treinamentos formais: R$ 15.000
- Consultoria terceirizada: R$ 50.000 (implementação)
- Suporte pontual (6-12 meses): R$ 20.000
TOTAL: R$ 85.000

Ano 2:
- Suporte ocasional: R$ 10.000
- Atualização de skills: R$ 5.000
TOTAL: R$ 15.000
```

**ROI da Transformação**:

```
INVESTIMENTO (2 anos):
- Kubernetes infra: R$ 36.000 (R$ 1.500/mês × 24)
- Capacitação: R$ 100.000 (ano 1: R$ 85k, ano 2: R$ 15k)
TOTAL: R$ 136.000

ECONOMIA/GANHOS (2 anos):
- Redução de fornecedores: R$ 120.000 (R$ 60k/ano × 2)
- Projetos internos (vs terceirizar): R$ 100.000
- Aumento de eficiência operacional: R$ 60.000
- Autonomia técnica: Inestimável (reduz risco)
TOTAL: R$ 280.000+

ROI: +106% (R$ 144.000 de ganho líquido em 2 anos)
```

---

### 🎯 Análise Comparativa Final

| Aspecto | Status Quo | K8s Sem Capacitação | K8s + Upskilling | Vencedor |
|---------|------------|---------------------|------------------|----------|
| **Custo Ano 1** | R$ 180k | R$ 86k (implementação + infra) | R$ 103k (implementação + capacitação + infra) | K8s Sem Cap ✅ |
| **Custo Ano 2** | R$ 180k | R$ 50k (suporte contínuo) + R$ 18k (infra) = R$ 68k | R$ 15k (suporte) + R$ 18k (infra) = R$ 33k | K8s + Up ✅ |
| **Autonomia Técnica** | Zero (100% dependente) | Zero (100% dependente) | Alta (90%+ independente) | K8s + Up ✅ |
| **Risco de Fracasso** | Baixo (continua igual) | **ALTÍSSIMO** (80%+ chance) | Baixo (20% chance) | K8s + Up ✅ |
| **Evolução do Time** | Estagnado | Estagnado + frustrado | Transformado (DevOps) | K8s + Up ✅ |
| **Flexibilidade Futura** | Baixa (vendor lock-in) | Baixa (dependência terceiro) | Alta (autonomia) | K8s + Up ✅ |
| **ROI 2 anos** | -R$ 360k (custo puro) | -R$ 100k (fracasso) | +R$ 144k (lucro) | K8s + Up ✅ |

---

### 💡 Decisão Recomendada: **Investir EM Kubernetes, MAS Com Plano de Capacitação Agressivo**

#### **Condições Obrigatórias para Sucesso**:

1. ✅ **Comprometimento de Upskilling**
   - Mínimo 3 pessoas do time (2 infra + 1 DBA)
   - 80h de treinamento formal/pessoa no primeiro ano
   - Budget para certificações (CKA/CKAD)

2. ✅ **Contrato de Suporte Escalonado**
   ```
   Mês 1-3: Suporte 24/7 (implementação)
   Mês 4-6: Suporte comercial (4h SLA)
   Mês 7-12: Suporte best-effort (8h SLA)
   Ano 2: Suporte por demanda (consultoria pontual)
   ```

3. ✅ **Evolução Gradual de Responsabilidades**
   ```
   Não jogar time no fundo da piscina. Transição gradual:
   Mês 1-2: 100% terceirizado
   Mês 3-4: 70% terceirizado, 30% time interno
   Mês 5-6: 50/50
   Mês 7-9: 30% terceirizado, 70% time interno
   Mês 10-12: 90% time interno, 10% consultoria
   ```

4. ✅ **Métricas de Sucesso Claras**
   ```
   Mês 3: Time consegue fazer deploy básico sozinho
   Mês 6: Time resolve 70% dos incidentes sem ajuda
   Mês 9: Time implementa nova funcionalidade sozinho
   Mês 12: Time treina novos membros
   ```

#### **Red Flags para ABORTAR**:

Se qualquer um desses acontecer, considere voltar para status quo:

- ❌ Time não consegue fazer deploy básico após 6 meses
- ❌ Chamadas de suporte não diminuem (ainda alto após 9 meses)
- ❌ Resistência cultural do time (não querem aprender)
- ❌ Problemas em prod frequentes (>1/mês após estabilização)
- ❌ Custo de suporte > R$ 10k/mês após 1 ano

**Neste caso**: Migre de volta para VMs, mas considere contratar 1 DevOps dedicado ao invés de Kubernetes.

---

## Conclusão da Mesa Técnica

### 📋 Decisões Finais Recomendadas

| Questão | Decisão | Rationale |
|---------|---------|-----------|
| **1. EC2 vs Kubernetes** | **Kubernetes (EKS)** | ROI positivo em 12 meses, evita débito técnico, preparado para crescimento |
| **2. Dev vs Staging+Prod** | **Manter DEV (otimizado)** | ROI +130%, previne problemas, custo otimizável para R$ 360/mês |
| **3. Investir sem Devs?** | **SIM, MAS com plano de capacitação obrigatório** | Transforma time, ROI +106% em 2 anos, cria autonomia técnica |

### 💰 Budget Total Aprovado (Cenário Recomendado)

**Ano 1**:
```
Infraestrutura:
- Kubernetes (EKS): R$ 18.000 (R$ 1.500/mês × 12)
- Ambientes (Dev otimizado): R$ 600/mês incluído acima

Implementação:
- Time terceirizado (quickstart): R$ 50.000
- Consultoria/suporte (primeiros 12m): R$ 20.000

Capacitação:
- Treinamentos formais: R$ 15.000
- Certificações: R$ 10.000

TOTAL ANO 1: R$ 113.000
```

**Ano 2**:
```
Infraestrutura: R$ 20.000 (crescimento +10%)
Suporte pontual: R$ 10.000
Atualização skills: R$ 5.000

TOTAL ANO 2: R$ 35.000
```

**TOTAL 2 ANOS: R$ 148.000**

**RETORNO ESPERADO 2 ANOS: R$ 280.000+**

**ROI: +89% (R$ 132.000 de ganho líquido)**

---

### ⚠️ Riscos e Mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|-------|---------------|---------|-----------|
| Time não absorve conhecimento | Média | Alto | Contrato de suporte estendido, considerar contratação DevOps |
| Complexidade subestimada | Alta | Médio | Buffer de 20% no budget, terceirizado em standby |
| Custo operacional maior que previsto | Média | Médio | Monitoramento FinOps desde dia 1, alertas de custo |
| Resistência cultural do time | Baixa | Alto | Envolvimento da liderança, incentivos (certificações pagas) |
| Fracasso da implementação | Baixa | Crítico | Gates de validação a cada 3 meses, opção de abort |

---

### 📅 Próximos Passos

1. **Aprovação Executiva** (esta semana)
   - Apresentar este documento para C-Level
   - Obter buy-in e budget approval

2. **Seleção de Fornecedor** (2 semanas)
   - RFP para terceirizado (com requisito de capacitação)
   - Avaliar 3 opções, escolher melhor custo-benefício

3. **Kick-off do Projeto** (Semana 3)
   - Sprint 0: Setup de ambiente, acesso AWS
   - Início do treinamento formal do time interno

4. **Gates de Validação**
   - Mês 3: Review de progresso #1
   - Mês 6: Review de progresso #2 (decisão go/no-go para continuar)
   - Mês 12: Review final, decisão de renovar suporte ou ir 100% interno

---

**Documento aprovado por**: _______________ (Assinatura C-Level)

**Data**: _______________

---

**Anexos**:
- [AWS EKS Quickstart - Plano Técnico](aws-eks-gitlab-quickstart.md)
- [Estratégia de Evolução](evolution-strategy.md)
- [Cotações de Fornecedores](fornecedores-cotacoes.md) [PENDENTE]
- [Plano de Treinamento Detalhado](plano-treinamento.md) [PENDENTE]
