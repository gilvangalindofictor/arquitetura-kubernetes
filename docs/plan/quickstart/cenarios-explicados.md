# Explicação Detalhada: Cenário Base vs Cenário Otimizado

**Documento:** Guia prático para entender as estratégias de custo da plataforma AWS EKS
**Data:** 2026-01-15

---

## Contexto: Por que 2 Cenários?

A plataforma terá **2 ambientes:**
- **Staging** (homologação/testes)
- **Prod** (produção)

A diferença entre os cenários está **apenas no ambiente Staging**. O ambiente de **Prod sempre roda 24/7** em ambos os casos.

---

## Cenário Base (Staging 24/7)

### O que é?

Ambiente Staging **sempre ligado**, disponível 24 horas por dia, 7 dias por semana, da mesma forma que produção.

### Como funciona?

| Recurso | Configuração | Disponibilidade |
|---------|--------------|-----------------|
| **EC2 Nodes Staging** | 2x t3.medium | 168h/semana (sempre ligado) |
| **RDS Staging** | db.t3.small Multi-AZ | 24/7 (sempre ligado) |
| **Redis Staging** | bitnami/redis (no K8s) | 24/7 (sempre ligado) |
| **RabbitMQ Staging** | bitnami/rabbitmq (no K8s) | 24/7 (sempre ligado) |

### Custos Staging (Cenário Base)

```
EC2 Nodes (2x t3.medium × 730h/mês):        ~R$ 260/mês
RDS db.t3.small Multi-AZ (730h/mês):        ~R$ 360/mês
Redis + RabbitMQ (consumo de node):         ~R$ 90/mês
EBS volumes (50GB):                         ~R$ 15/mês
S3 backups:                                 ~R$ 5/mês
EKS Control Plane (rateio 50%):            ~R$ 220/mês
NAT Gateway (rateio):                       ~R$ 172/mês
─────────────────────────────────────────────────────
SUBTOTAL STAGING:                           R$ 1.122/mês
```

### Custos TOTAIS (Base)

```
Staging (24/7):           R$ 1.122/mês
Prod (24/7):              R$ 2.802/mês
Observability:            R$ 150/mês
─────────────────────────────────────────
TOTAL MENSAL:             R$ 4.074/mês
TOTAL ANUAL:              R$ 48.888/ano
```

### Quando usar?

✅ Time trabalha em turnos ou horários variados
✅ Necessidade de acesso ao Staging fora do horário comercial
✅ Testes noturnos ou fins de semana frequentes
✅ Desenvolvimento contínuo (CI/CD rodando 24/7)

---

## Cenário Otimizado (Staging Scheduled)

### O que é?

Ambiente Staging **ligado apenas durante horário comercial** (segunda a sexta, 8h às 18h). Fora desse período, os recursos são **automaticamente desligados** para economizar custos.

### Como funciona?

**Schedule de Staging:**
- **Segunda a sexta:** Ligado das 8h às 18h (10 horas/dia × 5 dias = 50h/semana)
- **Noites (18h-8h):** Desligado automaticamente
- **Finais de semana:** Desligado automaticamente
- **Feriados:** Configurável (desligado por padrão)

**Redução de tempo:** 50h/semana vs 168h/semana = **-70% de uso**

### O que é desligado automaticamente?

| Recurso | Ação no Horário Não-Comercial | Economia |
|---------|-------------------------------|----------|
| **EC2 Nodes Staging** | Stopped (AWS Stop Instance) | -70% custo EC2 |
| **RDS Staging** | Auto-pause (Aurora Serverless) ou snapshot | -50% custo RDS |
| **Redis Staging** | Pod scaled to 0 (dados em PVC persistido) | -70% consumo |
| **RabbitMQ Staging** | Pod scaled to 0 (dados em PVC persistido) | -70% consumo |
| **EBS Volumes** | Permanecem (dados persistidos) | Custo fixo |

### Como é feita a automação?

**Opção 1: AWS Instance Scheduler** (Recomendado)
```bash
# Lambda function que executa em schedule definido
# Comandos executados:

# Às 18h (segunda a sexta):
aws ec2 stop-instances --instance-ids <staging-nodes>
aws rds stop-db-instance --db-instance-identifier <staging-rds>
kubectl scale deployment redis -n staging --replicas=0
kubectl scale statefulset rabbitmq -n staging --replicas=0

# Às 8h (segunda a sexta):
aws ec2 start-instances --instance-ids <staging-nodes>
aws rds start-db-instance --db-instance-identifier <staging-rds>
# Aguarda nodes prontos, então:
kubectl scale deployment redis -n staging --replicas=2
kubectl scale statefulset rabbitmq -n staging --replicas=3
```

**Opção 2: EventBridge + Lambda**
```yaml
# Regra no AWS EventBridge
StopStaging:
  schedule: "cron(0 21 ? * MON-FRI *)"  # 18h BRT = 21h UTC
  action: Lambda função "stop-staging-env"

StartStaging:
  schedule: "cron(0 11 ? * MON-FRI *)"  # 8h BRT = 11h UTC
  action: Lambda função "start-staging-env"
```

**Opção 3: Karpenter/Cluster Autoscaler**
```yaml
# Escala nodes baseado em schedule
apiVersion: karpenter.sh/v1alpha5
kind: NodePool
metadata:
  name: staging
spec:
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 30s
  limits:
    cpu: "0"  # Fora do horário comercial
```

### Custos Staging (Cenário Otimizado)

**Cálculo detalhado:**

```
EC2 Nodes (2x t3.medium × 50h/semana × 4.3 semanas):
  - Base: 730h/mês × R$ 0,0356/h × 2 nodes = R$ 260/mês
  - Otimizado: 215h/mês × R$ 0,0356/h × 2 nodes = R$ 77/mês
  - Economia: R$ 183/mês (-70%)

RDS db.t3.small Multi-AZ:
  - Base: 730h/mês × R$ 0,493/h = R$ 360/mês
  - Otimizado (auto-pause): ~R$ 180/mês (-50%)
  - Economia: R$ 180/mês

Redis + RabbitMQ (consumo de resources quando ligado):
  - Base: R$ 90/mês
  - Otimizado: R$ 27/mês (-70%)
  - Economia: R$ 63/mês

EBS volumes (sempre ligados, dados persistidos):
  - R$ 15/mês (sem redução)

S3 backups:
  - R$ 5/mês (sem redução)

EKS Control Plane (compartilhado, sempre ligado):
  - R$ 220/mês (sem redução)

NAT Gateway (tráfego reduzido):
  - Base: R$ 172/mês
  - Otimizado: R$ 120/mês (-30%)
  - Economia: R$ 52/mês

─────────────────────────────────────────────────────
SUBTOTAL STAGING (Base):        R$ 1.122/mês
SUBTOTAL STAGING (Otimizado):   R$ 672/mês
ECONOMIA MENSAL STAGING:        R$ 450/mês (-40%)
```

### Custos TOTAIS (Otimizado)

```
Staging (scheduled):      R$ 672/mês
Prod (24/7):              R$ 2.802/mês  (sem alteração)
Observability:            R$ 150/mês    (sem alteração)
─────────────────────────────────────────
TOTAL MENSAL:             R$ 3.624/mês
TOTAL ANUAL:              R$ 43.488/ano

ECONOMIA vs Base:         R$ 450/mês (R$ 5.400/ano)
```

### Quando usar?

✅ Time trabalha em horário comercial fixo (8h-18h, seg-sex)
✅ Sem necessidade de acesso ao Staging fora do expediente
✅ Testes e deploys realizados apenas durante o dia
✅ Aceitação de 10-15 minutos de "warm-up" ao ligar Staging pela manhã

### Considerações Importantes

**⚠️ Tempo de inicialização (cold start):**
- EC2 nodes: ~2-3 minutos
- RDS: ~5-10 minutos (se paused)
- Pods Redis/RabbitMQ: ~2 minutos
- **Total:** ~10-15 minutos para ambiente totalmente operacional

**✅ Dados preservados:**
- RDS: Snapshots automáticos (dados 100% preservados)
- Redis: Dados em PVC (persistent volume) - mantidos
- RabbitMQ: Mensagens e filas em PVC - mantidas
- GitLab: Repositories e configs intactos

**🔄 Startup automático:**
- Sistema liga automaticamente às 8h (segunda a sexta)
- Desenvolvedores chegam e ambiente está pronto (~8h10-8h15)
- Não requer intervenção manual

---

## Comparação Visual

```
┌──────────────────────────────────────────────────────────────┐
│                   COMPARAÇÃO DE CUSTOS                       │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  CENÁRIO BASE                    CENÁRIO OTIMIZADO          │
│  ════════════                    ══════════════════          │
│                                                              │
│  Staging: 168h/semana            Staging: 50h/semana        │
│  ├─ EC2:     R$ 260/mês          ├─ EC2:     R$ 77/mês      │
│  ├─ RDS:     R$ 360/mês          ├─ RDS:     R$ 180/mês     │
│  ├─ Redis:   R$ 45/mês           ├─ Redis:   R$ 14/mês      │
│  ├─ Rabbit:  R$ 45/mês           ├─ Rabbit:  R$ 13/mês      │
│  ├─ EBS:     R$ 15/mês           ├─ EBS:     R$ 15/mês      │
│  ├─ S3:      R$ 5/mês            ├─ S3:      R$ 5/mês       │
│  ├─ EKS:     R$ 220/mês          ├─ EKS:     R$ 220/mês     │
│  └─ NAT:     R$ 172/mês          └─ NAT:     R$ 120/mês     │
│                                                              │
│  💰 R$ 1.122/mês                 💰 R$ 672/mês               │
│                                                              │
│                  ⚡ ECONOMIA: R$ 450/mês ⚡                   │
│                  📊 REDUÇÃO: -40% no Staging                 │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

## Resumo Executivo: Qual Escolher?

### Escolha Cenário Base SE:
- ❌ Time trabalha em turnos/horários variados
- ❌ Necessidade de acesso 24/7 ao Staging
- ❌ Pipelines CI/CD rodando continuamente
- ❌ Testes automatizados noturnos/finais de semana

**Custo anual:** R$ 48.888

---

### Escolha Cenário Otimizado SE:
- ✅ Time trabalha seg-sex, 8h-18h
- ✅ Sem necessidade de Staging fora do horário
- ✅ Aceita 10-15min de inicialização pela manhã
- ✅ Prioriza economia de custos

**Custo anual:** R$ 43.488
**Economia:** R$ 5.400/ano

---

## Implementação do Cenário Otimizado

### Passo a Passo Técnico

**1. Criar Lambda Function para Stop (30 minutos)**
```python
# stop-staging-env.py
import boto3

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    rds = boto3.client('rds')

    # Stop EC2 instances
    ec2.stop_instances(InstanceIds=['i-staging-node-1', 'i-staging-node-2'])

    # Stop RDS
    rds.stop_db_instance(DBInstanceIdentifier='staging-gitlab-db')

    return {'statusCode': 200, 'body': 'Staging stopped'}
```

**2. Criar Lambda Function para Start (30 minutos)**
```python
# start-staging-env.py
import boto3
import time

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    rds = boto3.client('rds')

    # Start EC2 instances
    ec2.start_instances(InstanceIds=['i-staging-node-1', 'i-staging-node-2'])

    # Wait for instances
    waiter = ec2.get_waiter('instance_running')
    waiter.wait(InstanceIds=['i-staging-node-1', 'i-staging-node-2'])

    # Start RDS
    rds.start_db_instance(DBInstanceIdentifier='staging-gitlab-db')

    return {'statusCode': 200, 'body': 'Staging started'}
```

**3. Configurar EventBridge Rules (15 minutos)**
```bash
# Stop às 18h (segunda a sexta)
aws events put-rule \
  --name stop-staging \
  --schedule-expression "cron(0 21 ? * MON-FRI *)"

aws events put-targets \
  --rule stop-staging \
  --targets "Id"="1","Arn"="arn:aws:lambda:...:function:stop-staging-env"

# Start às 8h (segunda a sexta)
aws events put-rule \
  --name start-staging \
  --schedule-expression "cron(0 11 ? * MON-FRI *)"

aws events put-targets \
  --rule start-staging \
  --targets "Id"="1","Arn"="arn:aws:lambda:...:function:start-staging-env"
```

**4. Configurar Auto-scaling de Pods (10 minutos)**
```bash
# Scale down pods quando nodes param
kubectl create -f - <<EOF
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: redis-scaler
  namespace: staging
spec:
  scaleTargetRef:
    name: redis
  minReplicaCount: 0
  maxReplicaCount: 2
  triggers:
  - type: cron
    metadata:
      timezone: America/Sao_Paulo
      start: 0 8 * * 1-5
      end: 0 18 * * 1-5
      desiredReplicas: "2"
EOF
```

**Tempo total de implementação:** ~2 horas

---

## Perguntas Frequentes

**Q: E se precisar acessar Staging fora do horário?**
A: Pode ligar manualmente via Console AWS ou CLI em ~10 minutos. Também pode ajustar o schedule temporariamente.

**Q: Dados são perdidos quando desliga?**
A: Não. RDS, Redis e RabbitMQ usam volumes persistentes. Dados são 100% preservados.

**Q: Pode mudar de cenário depois?**
A: Sim. Pode ativar/desativar a automação a qualquer momento sem impacto na arquitetura.

**Q: Quanto tempo leva para implementar a otimização?**
A: ~2 horas. Pode ser feito após a implantação inicial (Sprint 3) ou em qualquer momento posterior.

**Q: Economia justifica o esforço?**
A: Sim. R$ 5.400/ano de economia com 2h de implementação = ROI positivo em 1 semana.

---

## Recomendação Final

**Implante inicialmente no Cenário Base** (mais simples) e **migre para Cenário Otimizado** após validação do ambiente (Sprint 3 ou posteriores).

**Razão:** Permite validar a plataforma sem complexidade adicional, depois otimiza custos quando tudo estiver estável.

**Cronograma sugerido:**
- Sprint 1-3: Cenário Base (validação)
- Sprint 4 ou posterior: Implementar automação (2h) → Cenário Otimizado
- Economia começa imediatamente após ativação
