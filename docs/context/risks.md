# ⚠️ Análise de Riscos - Plataforma Kubernetes AWS

**Última Atualização:** 2026-01-29
**Versão:** 2.0 (Marco 2 Completo)
**Framework:** Baseado em executor-terraform.md

---

## 📊 Matriz de Riscos

| ID | Risco | Probabilidade | Impacto | Severidade | Status | Mitigação |
|----|-------|---------------|---------|------------|--------|-----------|
| R-001 | State lock travado | BAIXO | MÉDIO | 🟡 MÉDIO | ✅ Mitigado | DynamoDB locking + force-unlock |
| R-002 | EKS add-ons deadlock | BAIXO | ALTO | 🟡 MÉDIO | ✅ Resolvido | Dependency order fixado |
| R-003 | Network Policies bloqueiam tráfego | MÉDIO | ALTO | 🔴 ALTO | ✅ Mitigado | Mapeamento de fluxos prévio |
| R-004 | Custos S3 Loki excedem estimativa | MÉDIO | BAIXO | 🟢 BAIXO | ⚠️ Monitorar | CloudWatch billing alerts |
| R-005 | ACM certificate expiration | BAIXO | MÉDIO | 🟡 MÉDIO | ✅ Mitigado | Auto-renewal ACM + alarm |
| R-006 | ALB provisioning timeout | BAIXO | MÉDIO | 🟡 MÉDIO | ✅ Tolerado | Retry terraform apply |
| R-007 | Pods OOMKilled (memory limits) | MÉDIO | MÉDIO | 🟡 MÉDIO | ⚠️ Monitorar | Prometheus alerts + tuning |
| R-008 | Vendor lock-in AWS | ALTO | BAIXO | 🟡 MÉDIO | ✅ Aceito | Trade-off custo vs portabilidade |
| R-009 | Single AZ failure (2 AZs only) | BAIXO | ALTO | 🟡 MÉDIO | ✅ Aceito | RTO 15min (recreate nodes) |
| R-010 | Secrets leak em Git | BAIXO | CRÍTICO | 🔴 ALTO | ✅ Mitigado | AWS Secrets Manager + pre-commit hooks |
| R-011 | Drift entre Terraform state e recursos | MÉDIO | MÉDIO | 🟡 MÉDIO | ✅ Mitigado | Terraform plan daily + drift detection |
| R-012 | Cluster Autoscaler scale-down agressivo | BAIXO | MÉDIO | 🟡 MÉDIO | ✅ Mitigado | 5min threshold + PDB configurados |
| R-013 | Data loss durante shutdown (ADR-022) | BAIXO | ALTO | 🟡 MÉDIO | ✅ Mitigado | PVCs persistem, S3 always-on |
| R-014 | Startup failure após shutdown | BAIXO | ALTO | 🟡 MÉDIO | ✅ Mitigado | Health checks automáticos, rollback |
| R-015 | RDS 7-day auto-restart (Marco 3) | MÉDIO | MÉDIO | 🟡 MÉDIO | ⚠️ Planejar | Snapshot strategy ou 24/7 |
| R-016 | Cold start excede tolerância (>10min) | BAIXO | BAIXO | 🟢 BAIXO | ✅ Mitigado | Target 5-8min, monitorado |
| R-017 | State drift Terraform vs Cluster Autoscaler | MÉDIO | BAIXO | 🟢 BAIXO | ✅ Mitigado | ignore_changes em desired_size |
| **R-018** | **Licenciamento Bitnami → Tanzu Standard** | **ALTO** | **CRÍTICO** | **🟢 EVITADO** | ✅ **Mitigado (ADR-023)** | **Migração para Operators** |

---

## 🔴 Riscos Críticos (ALTO Impacto)

### R-010: Secrets Leak em Git

**Probabilidade:** BAIXO
**Impacto:** CRÍTICO
**Severidade:** 🔴 ALTO

**Descrição:**
Credenciais sensíveis (Grafana password, API keys, database credentials) commitadas acidentalmente em repositório Git.

**Cenário de Falha:**
1. Desenvolvedor adiciona secret em `terraform.tfvars`
2. Commit sem validação
3. Push para repositório (GitHub public/private)
4. Credenciais expostas (scan automático de bots)
5. Acesso não autorizado a plataforma

**Mitigações Implementadas:**
- ✅ **AWS Secrets Manager:** Todas credenciais sensíveis armazenadas externamente
- ✅ **Pre-commit hook:** Validação automática (block commits com secrets)
- ✅ **.gitignore:** terraform.tfvars, *.tfvars, *.env (ignored)
- ✅ **Governance validation:** Hook custom validando padrões de secrets

**Mitigações Adicionais (Futuro):**
- [ ] **git-secrets AWS plugin:** Scan automático de padrões AWS (Access Keys, etc)
- [ ] **Periodic audit:** Monthly review de commits históricos
- [ ] **Rotation policy:** Quarterly rotation de credentials (Secrets Manager)

**Monitoramento:**
- CloudTrail: Unauthorized API calls (DetectPortScan rule)
- GuardDuty: Credential compromise detection (se habilitado)

---

### R-003: Network Policies Bloqueiam Tráfego Essencial

**Probabilidade:** MÉDIO
**Impacto:** ALTO
**Severidade:** 🔴 ALTO

**Descrição:**
Network Policies excessivamente restritivas bloqueiam comunicação necessária entre pods, causando falhas em aplicações.

**Cenário de Falha:**
1. Deploy nova aplicação no namespace `monitoring`
2. Default-deny policy aplicada
3. App não consegue resolver DNS (bloqueado)
4. App não consegue acessar API Kubernetes (bloqueado)
5. Pods crashloop, aplicação indisponível

**Mitigações Implementadas:**
- ✅ **Mapeamento de fluxos:** Análise prévia de comunicação (Prometheus → targets, Fluent Bit → Loki)
- ✅ **Allow-list explícito:** Políticas granulares (DNS, API server, scraping, logging)
- ✅ **Testing em staging:** Validação antes de aplicar em namespaces produtivos
- ✅ **Rollback rápido:** `kubectl delete networkpolicy <name>` (restaura comunicação)

**Monitoramento:**
- Prometheus alerts: Pod restarts > 3 (indica crash loops)
- Logs Loki: Query `{namespace="monitoring"} |= "connection refused"` (detecta bloqueios)

**Próximas Ações:**
- [ ] Criar Grafana dashboard específico para Network Policies violations
- [ ] Implementar Calico Policy Audit Mode (log violations sem bloquear)

---

### R-009: Single AZ Failure (Cluster com 2 AZs)

**Probabilidade:** BAIXO
**Impacto:** ALTO
**Severidade:** 🟡 MÉDIO

**Descrição:**
Falha completa de uma Availability Zone (us-east-1a ou us-east-1b), reduzindo capacidade do cluster pela metade.

**Cenário de Falha:**
1. AWS degrada us-east-1a (power outage, network issue)
2. 50% dos nodes ficam unreachable (3-4 nodes perdidos)
3. Pods em nodes afetados entram Terminating
4. Cluster reduz para ~50% capacidade
5. Workloads critical podem falhar se não houver réplicas em AZ saudável

**Mitigações Implementadas:**
- ✅ **2 AZs (não 1):** Reduz risco de total outage (single AZ seria 100% loss)
- ✅ **Pod Anti-affinity:** Réplicas distribuídas entre AZs diferentes (topology spread)
- ✅ **Cluster Autoscaler:** Auto-scale em AZ saudável (replenish capacity)

**Mitigações Aceitas (Trade-off):**
- ⚠️ **Não implementar 3 AZs:** Custo adicional $500/mês (33% mais nodes + NAT Gateway)
- ⚠️ **RTO 15 minutos:** Tempo para Cluster Autoscaler provisionar nodes de reposição

**Monitoramento:**
- AWS Health Dashboard: AZ status (us-east-1 region)
- Prometheus: Node readiness por AZ (alert se >50% nodes down)

**Decisão:**
✅ **ACEITO** - RTO 15min aceitável para DevOps workloads (não critical user-facing)

---

## 🟡 Riscos Médios

### R-001: State Lock Travado (Terraform)

**Probabilidade:** BAIXO
**Impacto:** MÉDIO
**Severidade:** 🟡 MÉDIO

**Descrição:**
Lock DynamoDB travado após terraform apply falhar ou interrupção manual (Ctrl+C).

**Cenário de Falha:**
1. `terraform apply` iniciado
2. Usuário interrompe (Ctrl+C) durante apply
3. Lock não é liberado automaticamente
4. Próximo `terraform plan` falha: "Error acquiring state lock"

**Mitigações:**
- ✅ **DynamoDB locking:** Backend S3 com state locking habilitado
- ✅ **Force-unlock command:** `terraform force-unlock <LOCK_ID>` (manual recovery)
- ✅ **Timeout configuration:** 30 segundos timeout para lock acquisition

**Resolução:**
```bash
# 1. Verificar lock ativo
terraform plan
# Error: ID: 78557c8a-c29b-856a-d1d2-ac4df7306c04

# 2. Force unlock (após confirmar que nenhum terraform está rodando)
terraform force-unlock -force 78557c8a-c29b-856a-d1d2-ac4df7306c04

# 3. Retry plan
terraform plan
```

**Lições Aprendidas:**
- Sempre verificar `ps aux | grep terraform` antes de force-unlock
- Nunca interromper terraform apply (aguardar conclusão ou usar -auto-approve=false)

---

### R-002: EKS Add-ons Deadlock (RESOLVIDO)

**Probabilidade:** BAIXO (após correção)
**Impacto:** ALTO
**Severidade:** 🟡 MÉDIO
**Status:** ✅ Resolvido (2026-01-28)

**Descrição:**
Add-ons EKS entravam em deadlock durante criação paralela, travando deploy do cluster.

**Cenário de Falha (Antes da Correção):**
1. Terraform cria 4 add-ons em paralelo (vpc-cni, kube-proxy, coredns, ebs-csi-driver)
2. coredns depende de vpc-cni (networking)
3. Criação paralela causa race condition
4. Add-ons ficam "Degraded" indefinidamente

**Correção Implementada:**
```hcl
# Ordem correta de dependências:
1. vpc-cni (primeiro - base networking)
2. kube-proxy (depende de vpc-cni)
3. coredns (depende de vpc-cni)
4. ebs-csi-driver (último - storage)
```

**Resultado:**
- ✅ 4/4 add-ons "Active" em ~5 minutos
- ✅ Cluster operacional com 7 nodes
- ✅ Zero degradation

**Arquivo:** `marco1/main.tf` - Dependency order explícito com `depends_on`

---

### R-004: Custos S3 Loki Excedem Estimativa

**Probabilidade:** MÉDIO
**Impacto:** BAIXO
**Severidade:** 🟢 BAIXO

**Descrição:**
Uso de S3 para logs Loki excede estimativa inicial ($11.50/mês), devido a maior volume de logs ou retention inadequada.

**Cenário de Falha:**
1. Aplicações geram logs excessivos (debug level em produção)
2. S3 storage cresce para 1TB+ (estimativa era 500GB)
3. Custo S3 duplica: $23/mês (vs $11.50 estimado)
4. Alerta de billing AWS dispara

**Mitigações:**
- ✅ **S3 Lifecycle Policy:** 30 dias retention configurado
- ⚠️ **CloudWatch Billing Alert:** Configurar alarm para S3 > $15/mês (PENDENTE)
- ✅ **Loki Retention:** 7 dias in-memory cache (reduz queries S3)

**Próximas Ações:**
- [ ] Implementar S3 Lifecycle para Glacier após 90 dias (80% economia)
- [ ] Configurar CloudWatch billing alerts por serviço
- [ ] Revisar log levels em aplicações (INFO em prod, não DEBUG)

**Monitoramento:**
```bash
# Check S3 storage usage
aws s3 ls s3://k8s-platform-loki-891377105802 --recursive --human-readable --summarize

# Check billing
aws ce get-cost-and-usage --time-period Start=2026-01-01,End=2026-01-31 \
  --granularity MONTHLY --metrics "UnblendedCost" \
  --filter file://s3-filter.json
```

---

### R-007: Pods OOMKilled (Memory Limits Inadequados)

**Probabilidade:** MÉDIO
**Impacto:** MÉDIO
**Severidade:** 🟡 MÉDIO

**Descrição:**
Pods excedendo memory limits configurados, sendo killed pelo Kubernetes OOM (Out of Memory) killer.

**Cenário de Falha:**
1. Prometheus pod configurado com `limits.memory: 2Gi`
2. Workload aumenta (mais targets scraped)
3. Prometheus memory usage atinge 2Gi
4. Kubernetes OOMKills o pod
5. Pod reinicia, perde dados in-memory (queries recentes)

**Mitigações:**
- ✅ **Requests < Limits:** Configurado (ex: requests 1Gi, limits 2Gi) permite burst
- ✅ **Prometheus alerts:** Alert `container_memory_usage_bytes` > 80% limit
- ⚠️ **Tuning periódico:** Revisar limits baseado em usage histórico (MANUAL)

**Monitoramento:**
```promql
# Prometheus query para detectar pods próximos do OOM
container_memory_working_set_bytes{namespace="monitoring"}
  / container_spec_memory_limit_bytes{namespace="monitoring"}
  > 0.8
```

**Ações Corretivas:**
- Aumentar limits gradualmente (10-20% por iteração)
- Analisar memory leaks (Grafana heap analysis)
- Considerar horizontal scaling (mais réplicas, menos memory por pod)

---

## 🟢 Riscos Baixos (Aceitos)

### R-008: Vendor Lock-in AWS

**Probabilidade:** ALTO (já estamos locked-in)
**Impacto:** BAIXO (trade-off consciente)
**Severidade:** 🟡 MÉDIO
**Status:** ✅ Aceito

**Descrição:**
Dependência de serviços específicos AWS (EKS, ALB, S3, ACM, Secrets Manager) dificulta migração para outra cloud.

**Trade-off Consciente:**
- **Vantagem:** Time-to-market 3× faster, custo 50% menor (vs multi-cloud)
- **Desvantagem:** Migração futura para GCP/Azure custaria 200-300h de refactoring

**Decisão:**
✅ **ACEITO** - Prioridade atual: Custo + Velocidade > Portabilidade

**Mitigações (Arquiteturais):**
- ✅ Loki (cloud-agnostic, poderia usar GCS ou Azure Blob)
- ✅ Prometheus (cloud-agnostic)
- ✅ Calico Network Policies (funciona em qualquer Kubernetes)
- ⚠️ ALB Controller (AWS-specific) - alternativa: NGINX Ingress Controller

**Reversibilidade:**
- Migração estimada: 200-300h engineering effort
- Ferramentas: Terraform multi-cloud modules, Kubernetes portável (exceto ALB)

---

### R-006: ALB Provisioning Timeout

**Probabilidade:** BAIXO
**Impacto:** MÉDIO
**Severidade:** 🟡 MÉDIO
**Status:** ✅ Tolerado

**Descrição:**
ALB provisioning via Ingress demora 3-5 minutos, ocasionalmente timeout 10min.

**Cenário:**
1. `kubectl apply -f ingress.yaml`
2. ALB Controller cria ALB na AWS
3. ALB leva 5-10 minutos para ficar "Active"
4. Timeout em CI/CD pipelines configurados com 5min max

**Mitigação:**
- ✅ **Retry logic:** CI/CD pipelines com retry automático (3 tentativas)
- ✅ **Timeout extension:** Aumentar timeout para 15 minutos
- ✅ **Health checks:** Validar ALB active antes de prosseguir

**Não é Bug:**
- Comportamento esperado AWS (ALB provisioning time)
- Não há mitigação técnica (é limitação AWS)

---

### R-012: Cluster Autoscaler Scale-Down Agressivo

**Probabilidade:** BAIXO
**Impacto:** MÉDIO
**Severidade:** 🟡 MÉDIO
**Status:** ✅ Mitigado

**Descrição:**
Cluster Autoscaler remove nodes prematuramente, causando reschedule desnecessário de pods.

**Cenário:**
1. Carga reduz (ex: fim de horário comercial)
2. Cluster Autoscaler detecta nodes com baixa utilização
3. Scale-down remove node após 5 minutos idle
4. Pods rescheduled para outros nodes (I/O spike temporário)
5. Possível breve indisponibilidade (30s-1min)

**Mitigações:**
- ✅ **Threshold 5 min:** Node precisa estar idle por 5 minutos antes de remoção
- ✅ **PodDisruptionBudgets:** Configurados para platform services (prevent simultaneous eviction)
- ✅ **Node taint tolerations:** Critical workloads em nodes dedicated (não removidos)

**Configuração:**
```yaml
--scale-down-unneeded-time: 5m
--scale-down-delay-after-add: 10m
```

**Monitoramento:**
- Prometheus: Node count histórico (detectar flapping)
- Alert: Node removed > 2× em 1 hora (indica scale-down agressivo)

---

## 🔄 Riscos Startup/Shutdown Automation (ADR-022)

**Referência:** [ADR-022](decisions.md#adr-022-startupshutdown-automation-strategy-finops), [costs.md - Economia Start/Stop](costs.md#custos-fixos-vs-variaveis--economia-startstop)

### R-013: Data Loss Durante Shutdown

**Probabilidade:** BAIXO
**Impacto:** ALTO
**Severidade:** 🟡 MÉDIO
**Status:** ✅ Mitigado

**Descrição:**
Perda de dados persistentes (métricas Prometheus, logs Loki, dashboards Grafana) durante shutdown da infraestrutura (ASG scale to 0).

**Cenário de Falha:**
1. `./scripts/down.sh` executado (ASG scale to 0)
2. Nodes são terminados antes de flush completo de dados
3. PVCs detached mas dados in-memory não persistidos
4. Startup posterior detecta dados corrompidos ou missing
5. Métricas/logs recentes (últimos 5-10min) perdidos

**Mitigações Implementadas:**
- ✅ **PVCs persistem sempre:** EBS volumes não são deleted, apenas detached (reattach automático no startup)
- ✅ **S3 backend:** Loki e Tempo usam S3 como storage primário (always-on, não afetado por shutdown)
- ✅ **Graceful shutdown:** Scripts `down.sh` executam `kubectl drain` antes de scale to 0 (30s grace period)
- ✅ **Retention policies:** Prometheus 15d local + remote write para Thanos (futuro), Loki 7d cache + 30d S3

**Componentes Always-On (Não Afetados):**
- S3 buckets: `k8s-platform-loki-*`, `k8s-platform-tempo-*` (logs + traces persistidos)
- EBS PVCs: Prometheus (20GB), Grafana (5GB), Loki Write (20GB) - **persist detached**
- Terraform state: S3 `k8s-terraform-state-*` (infraestrutura preservada)

**Data Loss Risk por Componente:**

| Componente | Storage Backend | Risk Level | Justificativa |
|------------|-----------------|------------|---------------|
| Prometheus | EBS PVC (20GB) | 🟡 MÉDIO | Últimos 5-10min podem ser perdidos (in-memory buffer) |
| Loki | S3 (500GB) | 🟢 BAIXO | S3 always-on, flush automático a cada 1min |
| Tempo | S3 (500GB) | 🟢 BAIXO | S3 always-on, traces persistidos |
| Grafana | EBS PVC (5GB) | 🟢 BAIXO | Dashboards/config persistidos (zero data loss) |

**Monitoramento:**
```bash
# Verificar PVCs após startup
kubectl get pvc -n monitoring
# Esperado: Todos "Bound" (reattached)

# Verificar data integrity Prometheus
kubectl exec -n monitoring prometheus-0 -- promtool tsdb list /prometheus
# Esperado: Blocos de dados sem corrupção
```

**Ações Pós-Startup:**
- [ ] Validar Prometheus TSDB integrity (zero corruption)
- [ ] Verificar Grafana dashboards acessíveis (config preservado)
- [ ] Query Loki últimos logs pre-shutdown (validar continuidade)

---

### R-014: Startup Failure Após Shutdown

**Probabilidade:** BAIXO
**Impacto:** ALTO
**Severidade:** 🟡 MÉDIO
**Status:** ✅ Mitigado

**Descrição:**
Falha ao iniciar infraestrutura após shutdown, deixando plataforma indisponível por tempo prolongado (> 30 min).

**Cenários de Falha:**

**1. ASG não escala (Stuck at 0 nodes):**
- Causa: IAM role Cluster Autoscaler sem permissões, ASG tags incorretos
- Impacto: Cluster sem nodes, 100% indisponível
- Mitigação: `aws autoscaling set-desired-capacity` manual override

**2. Nodes join mas ficam NotReady:**
- Causa: VPC CNI add-on degraded, ENI allocation failure
- Impacto: Nodes visíveis mas pods não scheduleam
- Mitigação: Restart vpc-cni daemonset, verificar subnet IPs disponíveis

**3. Pods crashloop após startup:**
- Causa: PVCs não reattach, image pull errors (ECR throttling)
- Impacto: Platform services (Prometheus, Grafana, Loki) indisponíveis
- Mitigação: Describe pods, retry imagePullBackOff, resize PVCs se necessário

**Mitigações Implementadas:**
- ✅ **Health check automático:** `scripts/health-check.sh` valida nodes + pods + Grafana UI
- ✅ **Retry logic:** Script `up.sh` tenta 3× antes de falhar (1min sleep entre tentativas)
- ✅ **Timeout configurado:** 10min timeout para nodes Ready, 15min para pods Running
- ✅ **Rollback strategy:** Se health check fail, escalar ASG to 0 novamente (reset state)

**Health Checks Validados:**
```bash
# scripts/health-check.sh (executado automaticamente por up.sh)
✅ 7 nodes Ready (kubectl get nodes)
✅ 36 pods Running em monitoring (kubectl get pods -n monitoring)
✅ Grafana UI accessible (curl http://localhost:3000/login)
✅ Loki ingestion functional (logcli query --limit=1)
✅ Tempo traces functional (tempo-cli query)
```

**Troubleshooting Startup Failure:**
```bash
# 1. Verificar ASG
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names k8s-platform-prod-node-group
# Esperado: DesiredCapacity=7, CurrentCapacity aumentando

# 2. Verificar nodes
kubectl get nodes -o wide
# Esperado: 7 nodes Ready em 5-8 min

# 3. Verificar pods crashloop
kubectl get pods -A | grep -v Running
# Se houver pods Error/CrashLoopBackOff: kubectl describe pod <name>

# 4. Forçar reschedule
kubectl delete pod <pod-name> -n monitoring --force
```

**Fallback Manual:**
Se `up.sh` falhar após 3 tentativas:
1. Verificar AWS Health Dashboard (AZ outage?)
2. Escalar ASG manualmente: `aws autoscaling set-desired-capacity --desired-capacity 7`
3. Aguardar 10min, re-executar `health-check.sh`
4. Se persistir: Contato AWS Support (caso extremo, <1% probabilidade)

**Cold Start Time Targets:**
- ⚡ **Normal:** 5-8 min (nodes up + pods scheduled)
- ⚠️ **Degraded:** 10-15 min (image pulls lentos, ENI allocation delays)
- 🔴 **Failure:** > 15 min (indica problema real, ativar troubleshooting)

---

### R-015: RDS 7-Day Auto-Restart Limitation (Marco 3)

**Probabilidade:** MÉDIO
**Impacto:** MÉDIO
**Severidade:** 🟡 MÉDIO
**Status:** ⚠️ Planejar (Marco 3)

**Descrição:**
PostgreSQL RDS (Marco 3 Data Services) não pode ficar stopped > 7 dias consecutivos. AWS auto-restart após 7 dias, gerando custos inesperados em ambientes dev/staging longos shutdowns (ex: férias time, 2-3 semanas).

**Cenário de Falha:**
1. Time para de trabalhar em sexta-feira (shutdown infraestrutura)
2. Férias coletivas (2 semanas sem atividade)
3. Dia 8: AWS auto-restart RDS automaticamente
4. RDS roda sozinho por 1 semana adicional (custo $50 desperdiçado)
5. Billing alert dispara, surpresa no fim do mês

**Impacto Financeiro:**
- **Baseline:** RDS db.t3.medium $50/mês (Marco 3)
- **Cenário férias 2 semanas:** $25 extra cobrado (auto-restart dia 8-21)
- **Anualizado:** 3 períodos longos = $75/ano desperdício

**Soluções Avaliadas:**

| Abordagem | Economia/Mês | Restore Time | Custo Snapshot | Complexidade | Decisão |
|-----------|--------------|--------------|----------------|--------------|---------|
| **RDS 24/7 Always-On** | $0 | Instant | $0 | ⚡ Baixa | ✅ **Produção** |
| **RDS Stop/Start (< 7d)** | $50 (se shutdown full) | 3-5 min | $0 | 🟡 Média | ✅ **Dev (ciclos curtos)** |
| **Snapshot + Delete + Restore** | $40.50 líquido | 10-15 min | $9.50/mês (100GB) | 🔴 Alta | ✅ **Dev (férias longas)** |

**Decisão Recomendada Marco 3:**
- **Dev/Staging:** Snapshot + Delete strategy para shutdowns > 5 dias
  - Automação: Script `scripts/rds-snapshot-delete.sh` (executar antes de férias)
  - Restore: Script `scripts/rds-restore.sh` (executar no retorno)
- **Produção:** RDS 24/7 Always-On (dados persistentes necessários, zero downtime)

**Scripts Planejados (Q2 2026):**
```bash
# rds-snapshot-delete.sh
#!/bin/bash
aws rds create-db-snapshot \
  --db-instance-identifier k8s-platform-postgres \
  --db-snapshot-identifier k8s-postgres-vacation-$(date +%Y%m%d)

aws rds wait db-snapshot-completed \
  --db-snapshot-identifier k8s-postgres-vacation-$(date +%Y%m%d)

aws rds delete-db-instance \
  --db-instance-identifier k8s-platform-postgres \
  --skip-final-snapshot

echo "✅ RDS deleted. Snapshot: k8s-postgres-vacation-$(date +%Y%m%d)"
echo "💰 Economia: $50/mês - $9.50 snapshot = $40.50/mês líquido"

# rds-restore.sh
#!/bin/bash
SNAPSHOT_ID=$(aws rds describe-db-snapshots \
  --query 'DBSnapshots[?starts_with(DBSnapshotIdentifier, `k8s-postgres-vacation`)] | sort_by(@, &SnapshotCreateTime) | [-1].DBSnapshotIdentifier' \
  --output text)

aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier k8s-platform-postgres \
  --db-snapshot-identifier $SNAPSHOT_ID

echo "⏳ Restoring RDS from $SNAPSHOT_ID (10-15 min)..."
aws rds wait db-instance-available \
  --db-instance-identifier k8s-platform-postgres

echo "✅ RDS restored. Endpoint: $(aws rds describe-db-instances --db-instance-identifier k8s-platform-postgres --query 'DBInstances[0].Endpoint.Address' --output text)"
```

**Monitoramento:**
- CloudWatch Event: RDS state change "stopped" → "starting" (detectar auto-restart)
- Alert: Email DevOps Lead se RDS auto-restart detectado (ação: avaliar se intencional)

**Mitigação Imediata:**
- [ ] Documentar limitation em runbook Marco 3
- [ ] Adicionar reminder em scripts `down.sh`: "⚠️ RDS will auto-restart in 7 days"
- [ ] Criar calendar reminder: RDS auto-restart check (dia 6 após shutdown)

---

### R-016: Cold Start Excede Tolerância (>10min)

**Probabilidade:** BAIXO
**Impacto:** BAIXO
**Severidade:** 🟢 BAIXO
**Status:** ✅ Mitigado

**Descrição:**
Tempo de cold start (startup completo da infraestrutura) excede 10 minutos, impactando produtividade do time (atraso início do dia).

**Target vs Reality:**
- 🎯 **Target:** 5-8 min (nodes up + pods Running + health checks)
- ✅ **Baseline actual:** 6m23s (medido 2026-01-29)
- ⚠️ **Worst-case aceitável:** 10 min
- 🔴 **Unacceptable:** > 15 min (indica problema infraestrutura)

**Fatores que Aumentam Cold Start:**
1. **Image pulls lentos:** ECR throttling ou imagens grandes (> 1GB)
2. **ENI allocation delays:** Subnet com poucos IPs disponíveis (AWS slow allocation)
3. **PVC attach delays:** EBS volumes em AZ diferente do node (cross-AZ attach)
4. **Init containers timeout:** Health checks Prometheus/Grafana lentos (dependencies não prontos)

**Mitigações Implementadas:**
- ✅ **Image caching:** ECR pull-through cache (reduz pulls externos)
- ✅ **PVC topology:** StorageClass com `volumeBindingMode: WaitForFirstConsumer` (attach local AZ)
- ✅ **Parallel scheduling:** Kubernetes schedules pods assim que nodes Ready (não sequencial)
- ✅ **Monitoring:** Script `up.sh` mede tempo total, log em `startup.log`

**Monitoramento Cold Start:**
```bash
# scripts/up.sh (adiciona timestamp)
START_TIME=$(date +%s)
# ... ASG scale up ...
# ... Health checks ...
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
echo "✅ Infrastructure started in ${DURATION}s ($(($DURATION / 60))m $((DURATION % 60))s)"

# Histórico cold start times (tail logs)
grep "Infrastructure started" /var/log/startup.log
```

**Ações Se Cold Start > 10min:**
1. Verificar qual componente demorou (nodes Ready? pods Running? health checks?)
2. Revisar AWS Health Dashboard (degradação AZ?)
3. Analisar `kubectl describe nodes` (taints, unschedulable?)
4. Otimizar imagens Docker (remover layers desnecessários, multi-stage builds)

**Trade-off Aceito:**
- ⚠️ Cold start 6-8min é aceitável para dev environments (vs economia $3,890/ano)
- ✅ Produção: 24/7 (zero cold start, sempre disponível)

---

### R-017: State Drift Terraform vs Cluster Autoscaler

**Probabilidade:** MÉDIO
**Impacto:** BAIXO
**Severidade:** 🟢 BAIXO
**Status:** ✅ Mitigado

**Descrição:**
Cluster Autoscaler ajusta `desired_size` do ASG dinamicamente (ex: 7 → 5 em baixa demanda), causando state drift com Terraform que espera `desired_size = 7`.

**Cenário de Drift:**
1. Terraform define ASG: `desired_size = 7, min_size = 3, max_size = 10`
2. Cluster Autoscaler scale down para 5 nodes (baixa utilização)
3. AWS ASG real state: `desired_size = 5`
4. `terraform plan` mostra drift: "desired_size: 7 → 5"
5. `terraform apply` reseta para 7 (undo do autoscaling)

**Solução Implementada:**
```hcl
# marco1/main.tf (ASG configuration)
resource "aws_eks_node_group" "main" {
  scaling_config {
    desired_size = 7
    min_size     = 3
    max_size     = 10
  }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}
```

**Resultado:**
- ✅ Terraform gerencia `min_size` e `max_size` (limites)
- ✅ Cluster Autoscaler gerencia `desired_size` (valor atual)
- ✅ `terraform plan` não mostra drift em `desired_size`
- ✅ Scripts bash `up.sh`/`down.sh` ajustam `desired_size` via AWS CLI (não Terraform)

**Validação:**
```bash
# 1. Verificar Terraform ignora desired_size
terraform plan
# Esperado: "No changes. Infrastructure is up-to-date."

# 2. Simular Cluster Autoscaler scale-down
kubectl scale deployment nginx-test --replicas=0
# Aguardar 5min (Cluster Autoscaler threshold)
# Cluster Autoscaler reduz nodes 7 → 6

# 3. Re-verificar Terraform
terraform plan
# Esperado: AINDA "No changes" (ignore_changes funciona)
```

**Documentação:**
- ADR-022: Decisão Terraform Specialist (Agent a9d1641)
- Pattern reutilizável: Sempre usar `ignore_changes` em recursos gerenciados por controllers K8s

---

### R-018: Licenciamento Bitnami Charts → Tanzu Standard (EVITADO)

**Probabilidade:** ALTA (se não agir)
**Impacto:** CRÍTICO (+$72k/ano)
**Severidade:** 🟢 EVITADO
**Status:** ✅ Mitigado (ADR-023)

**Descrição:**
Bitnami Helm Charts (Redis, RabbitMQ) migrariam para modelo pago (Tanzu Standard) em Setembro 2025, gerando custo de licenciamento de $72,000/ano ($6,000/mês).

**Descoberta:**
- Data: 2026-01-29
- Componentes afetados: Redis + RabbitMQ (planejados no Quickstart Marco 3)
- Custo licenciamento: $72,000/ano (Tanzu Standard)
- Prazo: Setembro 2025 (8 meses restantes)

**Impacto Financeiro SE NÃO MITIGADO:**
- Infraestrutura AWS: $7,248/ano
- Licenciamento Tanzu: $72,000/ano
- **TOTAL:** $79,248/ano (+993% vs planejamento original) 🔴

**Mitigação Implementada (ADR-023):**
✅ Migração para Kubernetes Operators:
- **Redis:** Spotahome Redis Operator (open source, $0 licenciamento)
- **RabbitMQ:** RabbitMQ Cluster Operator (oficial VMware, open source, $0)

**Resultado Mitigação:**
- ✅ Custo licenciamento: $0 (evitado $72,000/ano)
- ✅ Economia infraestrutura: $900/ano (Operators mais eficientes)
- ✅ **Economia total:** $72,900/ano (92% redução vs Tanzu)
- ✅ Benefícios técnicos adicionais:
  - HA automático (failover < 30s vs 5-6 min manual)
  - Backups nativos (CronJobs automáticos)
  - Zero-downtime upgrades (rolling updates)
  - Cloud-agnostic (portável GCP/Azure)

**Investimento Mitigação:**
- +4h esforço Sprint 1 ($400 @ $100/h)
- 4h onboarding Operators (estudo documentação)
- 4h POC em ambiente dev (validação)
- **TOTAL:** 12h ($1,200)

**ROI Mitigação:**
- Investimento: $1,200
- Economia Ano 1: $72,900
- **ROI:** 6,075% (payback 5 dias)

**Status Atual:**
- ✅ Decisão aprovada stakeholders (2026-01-29)
- ✅ ADR-023 criado ([decisions.md](decisions.md#adr-023))
- ⏳ Implementação prevista: Sprint 1 Marco 3
- ⏳ Operators a deployar: Spotahome Redis Operator + RabbitMQ Cluster Operator

**Documentação:**
- **ADR-023:** [decisions.md#adr-023](decisions.md#adr-023-migration-from-bitnami-charts-to-kubernetes-operators)
- **Análise Impacto:** [BITNAMI-LICENSING-IMPACT-ANALYSIS.md](../../finops/BITNAMI-LICENSING-IMPACT-ANALYSIS.md)
- **Cruzamento Quickstart:** [QUICKSTART-VS-BITNAMI-ANALYSIS.md](../../finops/QUICKSTART-VS-BITNAMI-ANALYSIS.md)
- **Custos Completos:** [COST-PROJECTION-COMPLETE.md](../../finops/COST-PROJECTION-COMPLETE.md)

**Lições Aprendidas:**
- ✅ Monitorar licenciamento de dependências open source (alertas mudanças roadmap)
- ✅ Avaliar cloud-agnostic alternatives (Operators vs vendor-specific charts)
- ✅ Realizar análise financeira proativa (antes de lock-in)
- ✅ Priorizar portabilidade e HA nativa (vs simplicidade deploy inicial)

---

## 📈 Tendências de Riscos

### Riscos Emergentes (Marco 3)
- **R-019:** GitLab CE single point of failure (sem HA configurado)
- **R-020:** Backup & DR strategy inexistente (loss tolerance: 24h RPO)
- **R-021:** PostgreSQL RDS sem Multi-AZ (custo vs HA trade-off)
- **R-022:** Secrets rotation policy inexistente (compliance risk)

---

## 🔄 Processo de Review

### Frequência
- **Semanal:** Review de riscos ALTOS
- **Mensal:** Review de todos os riscos + atualização matriz
- **Ad-hoc:** Após incidentes ou mudanças arquiteturais

### Responsáveis
- **DevOps Lead:** Dono da matriz de riscos
- **Security Specialist:** Review de riscos de segurança
- **FinOps:** Review de riscos de custo

---

**Mantenedor:** DevOps Team
**Última Revisão:** 2026-01-29
**Próxima Revisão:** 2026-02-05 (Marco 3 planning)
