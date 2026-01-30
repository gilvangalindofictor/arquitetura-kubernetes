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

## ⚠️ R-019: Riscos Automação FinOps STAGING (EventBridge + Lambda)

**Data Identificação:** 2026-01-30
**Status:** 📝 PLANEJADO (implementação prevista 2026-02-17)
**Categoria:** Disponibilidade + Operacional + Financeiro
**Impacto:** 🟡 MÉDIO (afeta STAGING apenas, PROD não impactado)
**Probabilidade:** 🟡 MÉDIA (5-10% chance de falhas operacionais)
**Severidade Combinada:** 🟡 **MÉDIA** (Probabilidade × Impacto = 5)

### Descrição

Implementação de automação start/stop do ambiente STAGING via EventBridge + Lambda para economia de R$ 4.320/ano introduz **novos riscos operacionais** relacionados a:

1. **Falhas de startup:** RDS/nodes não inicializam corretamente
2. **Perda de dados:** GitLab jobs ativos durante shutdown
3. **Dependências externas:** BrasilAPI indisponível
4. **Timeouts Lambda:** Operações excedem 300s limit
5. **Circuit breaker:** Desabilita automação após 3 falhas consecutivas

**Contexto Arquitetural:**
- **ADR-024:** FinOps Automation STAGING (EventBridge + Lambda)
- **Demanda:** [docs/demands/2026-01-30-automacao-finops-staging.md](../demands/2026-01-30-automacao-finops-staging.md)
- **Economia Projetada:** R$ 4.320/ano (ROI 44% Year 1, payback 6.7 meses)
- **Investimento:** R$ 3.000 (10h desenvolvimento)

---

### Riscos Identificados

#### R-019.1: Falha Startup RDS (Timeout ou Erro)

**Probabilidade:** 🟡 5% (1 falha a cada 20 startups)
**Impacto:** 🔴 ALTO ($60/dia STAGING indisponível, equipe bloqueada)

**Cenário:**
1. EventBridge dispara Lambda startup 8:00 AM BRT
2. Lambda chama `aws rds start-db-instance`
3. RDS timeout após 300s (5 min) OU erro AWS API throttling
4. Lambda retorna erro, STAGING permanece offline
5. Equipe chega 8:30 AM, descobre STAGING indisponível
6. Intervenção manual necessária (~30 min)

**Impacto Financeiro:**
- Perda produtividade: 4 devs × 0.5h × R$ 300/h = **R$ 600/incidente**
- Frequência estimada: 1× a cada 2 meses (6×/ano) = **R$ 3.600/ano**

**Mitigações:**

| Mitigação | Eficácia | Esforço | Status |
|-----------|---------|---------|--------|
| **Retry 3× com backoff exponencial** (30s, 60s, 120s) | 🟢 95% | BAIXO (2h) | ✅ Planejado |
| **Alerta PagerDuty on-call** (falha 3× consecutivas) | 🟢 100% detecção | BAIXO (1h) | ✅ Planejado |
| **Health check timeout aumentado** (de 300s para 600s) | 🟡 70% | BAIXO (30min) | ⏳ Considerar se necessário |
| **Fallback manual trigger** (botão Slack "Start STAGING") | 🟢 100% recovery | MÉDIO (4h) | ⏳ Q2 2026 |

**ROI Mitigação:**
- Investimento: R$ 900 (3h desenvolvimento)
- Redução perda: R$ 3.600 → R$ 360 (90% redução)
- **NPV Year 1:** R$ 3.240 - R$ 900 = **R$ 2.340 líquido**

---

#### R-019.2: GitLab Job Perdido Durante Shutdown

**Probabilidade:** 🟢 2% (1 falha a cada 50 shutdowns)
**Impacto:** 🔴 ALTO (rebuild job, retrabalho 1-4h, reputação equipe)

**Cenário:**
1. EventBridge dispara Lambda shutdown 18:00 BRT
2. Lambda verifica GitLab jobs ativos: `/api/v4/jobs?scope[]=running`
3. Health check FALHA (detecta 0 jobs) MAS job foi criado 1s depois (race condition)
4. Lambda prossegue shutdown, nodes terminam
5. GitLab job perdido mid-execution (ex: deploy staging app crítica)
6. Dev descobre falha 19:00, precisa rerun job (~2h rebuild)

**Impacto Financeiro:**
- Retrabalho dev: 2h × R$ 300/h = **R$ 600/incidente**
- Frequência estimada: 2×/ano = **R$ 1.200/ano**

**Mitigações:**

| Mitigação | Eficácia | Esforço | Status |
|-----------|---------|---------|--------|
| **Health check com retry 3×** (verificar jobs 3× com 10s intervalo) | 🟢 99% | BAIXO (1h) | ✅ Planejado |
| **Grace period 5 min** (bloquear shutdown se job criado < 5min) | 🟢 95% | BAIXO (30min) | ✅ Planejado |
| **Notificação Slack pre-shutdown** (5 min aviso "STAGING will shutdown") | 🟡 80% awareness | BAIXO (1h) | ⏳ Nice-to-have |
| **GitLab webhook** (cancelar shutdown se novo job) | 🟢 99.9% | ALTO (8h) | ⏳ Q2 2026 |

**ROI Mitigação:**
- Investimento: R$ 450 (1.5h desenvolvimento health checks)
- Redução perda: R$ 1.200 → R$ 120 (90% redução)
- **NPV Year 1:** R$ 1.080 - R$ 450 = **R$ 630 líquido**

---

#### R-019.3: BrasilAPI Indisponível (Feriados Não Detectados)

**Probabilidade:** 🟢 1% (API pública, SLA ~99%)
**Impacto:** 🟡 MÉDIO (workloads ligam desnecessariamente em feriado, perda $2/feriado)

**Cenário:**
1. EventBridge dispara Lambda startup 8:00 AM em feriado nacional
2. Lambda chama BrasilAPI: `GET https://brasilapi.com.br/api/feriados/v1/{ano}`
3. BrasilAPI timeout ou retorna 500 Internal Server Error
4. Lambda fallback: consulta cache local DynamoDB (30 dias TTL)
5. Cache expirado (último sync 31 dias atrás)
6. Lambda fallback final: lista estática hardcoded (feriados fixos apenas)
7. Feriado móvel (ex: Carnaval, Páscoa) NÃO detectado
8. STAGING liga, equipe não trabalha, desperdício $2/dia

**Impacto Financeiro:**
- Desperdício por feriado: $2/dia (workloads ligados 1 dia sem uso)
- Frequência: 1-2 feriados/ano = **$4/ano** (desprezível)

**Mitigações:**

| Mitigação | Eficácia | Esforço | Status |
|-----------|---------|---------|--------|
| **Cache local DynamoDB** (30 dias TTL, sync semanal) | 🟢 99% | BAIXO (2h) | ✅ Planejado |
| **Lista estática fallback** (feriados fixos hardcoded) | 🟡 70% (feriados fixos apenas) | BAIXO (30min) | ✅ Planejado |
| **Alerta CloudWatch** (log warning BrasilAPI unreachable) | 🟢 100% detecção | BAIXO (30min) | ✅ Planejado |
| **Sync manual mensal** (atualizar lista estática 1×/ano) | 🟡 80% | BAIXO (15min/ano) | ⏳ Processo operacional |

**ROI Mitigação:**
- Investimento: R$ 750 (2.5h desenvolvimento cache + fallback)
- Redução perda: $4/ano (desprezível, mas melhora confiabilidade)
- **Justificativa:** Investimento defensivo (evitar falso-positivo, reputação)

---

#### R-019.4: Lambda Timeout 300s (Startup Lento)

**Probabilidade:** 🟢 1% (1 timeout a cada 100 startups)
**Impacto:** 🟡 MÉDIO (Lambda timeout, startup parcial, recovery manual 15 min)

**Cenário:**
1. Lambda startup inicia: RDS start, ASG scale up, aguardar nodes Ready
2. RDS leva 4 min (normal), nodes join 3 min, pods scheduling 2 min
3. Total: 9 min > 300s Lambda limit
4. Lambda timeout, retorna erro
5. RDS ficou online, nodes Ready, mas pods ainda scheduling
6. Estado inconsistente: infraestrutura partially up
7. Próxima tentativa (retry) detecta RDS/nodes já up, finaliza startup
8. Startup completo em 2ª tentativa (10 min total)

**Impacto Financeiro:**
- Delay startup: 10 min vs 6 min esperado = +4 min atraso
- Frequência: 1×/ano = **impacto desprezível**

**Mitigações:**

| Mitigação | Eficácia | Esforço | Status |
|-----------|---------|---------|--------|
| **Operações assíncronas** (não aguardar pods inline, validar em retry) | 🟢 99% | MÉDIO (4h) | ✅ Planejado |
| **Timeout Lambda 600s** (dobrar limite para 10 min) | 🟡 90% | BAIXO (15min config) | ⏳ Se necessário |
| **Step Functions** (workflow multi-step, sem timeout single Lambda) | 🟢 99.9% | ALTO (12h) | ⏳ Q2 2026 se frequente |
| **Idempotência** (retry detecta estado partial, continua de onde parou) | 🟢 100% | MÉDIO (3h) | ✅ Planejado |

**ROI Mitigação:**
- Investimento: R$ 1.200 (4h operações assíncronas + idempotência)
- Redução perda: Desprezível (1×/ano), mas melhora robustez
- **Justificativa:** Investimento preventivo (arquitetura sólida)

---

#### R-019.5: Circuit Breaker Ativado Erroneamente

**Probabilidade:** 🟢 1% (ativação falso-positivo 1×/ano)
**Impacto:** 🟡 MÉDIO (automação desabilitada, intervenção manual 30 min)

**Cenário:**
1. Startup falha 3× consecutivas (ex: RDS maintenance window não planejado)
2. Lambda detecta threshold, ativa circuit breaker: `state = CIRCUIT_OPEN`
3. DynamoDB `finops-scheduler-state` atualizada: `failures = 3`
4. EventBridge rule desabilitada automaticamente: `aws events disable-rule`
5. Notificação PagerDuty on-call: "FinOps automation disabled"
6. On-call investiga logs (15 min), identifica manutenção AWS temporária
7. Reset circuit breaker manualmente: `aws dynamodb update-item --set failures = 0`
8. Reabilita EventBridge rule: `aws events enable-rule`
9. Automação restaurada (30 min total intervenção)

**Impacto Financeiro:**
- Tempo on-call: 0.5h × R$ 400/h = **R$ 200/incidente**
- Frequência: 1×/ano = **R$ 200/ano**

**Mitigações:**

| Mitigação | Eficácia | Esforço | Status |
|-----------|---------|---------|--------|
| **Threshold ajustável** (3 falhas vs 5 falhas, configurável) | 🟡 70% | BAIXO (1h) | ✅ Planejado |
| **Notificação imediata** (PagerDuty + Slack alert) | 🟢 100% detecção | BAIXO (1h) | ✅ Planejado |
| **Runbook recovery** (docs/runbooks/finops-circuit-breaker-reset.md) | 🟢 100% recovery | BAIXO (2h) | ✅ Planejado |
| **Auto-reset após 24h** (reset automático se 24h sem falhas) | 🟡 80% | MÉDIO (3h) | ⏳ Q2 2026 |

**ROI Mitigação:**
- Investimento: R$ 1.200 (4h runbook + alertas + threshold config)
- Redução perda: R$ 200 → R$ 40 (80% redução com runbook eficiente)
- **NPV Year 1:** R$ 160 - R$ 1.200 = **-R$ 1.040 líquido** (investimento preventivo)

---

### Matriz de Riscos Consolidada

| Risco | Probabilidade | Impacto | Perda/Ano | Investimento Mitigação | ROI Mitigação | Prioridade |
|-------|--------------|---------|-----------|------------------------|---------------|------------|
| **R-019.1** RDS Startup Failure | 🟡 5% | 🔴 Alto | R$ 3.600 | R$ 900 | **R$ 2.340** | 🔴 ALTA |
| **R-019.2** GitLab Job Lost | 🟢 2% | 🔴 Alto | R$ 1.200 | R$ 450 | **R$ 630** | 🟡 MÉDIA |
| **R-019.3** BrasilAPI Down | 🟢 1% | 🟡 Médio | R$ 24 | R$ 750 | **-R$ 726** | 🟢 BAIXA |
| **R-019.4** Lambda Timeout | 🟢 1% | 🟡 Médio | R$ 50 | R$ 1.200 | **-R$ 1.150** | 🟢 BAIXA |
| **R-019.5** Circuit Breaker | 🟢 1% | 🟡 Médio | R$ 200 | R$ 1.200 | **-R$ 1.040** | 🟢 BAIXA |
| **TOTAL RISCOS** | | | **R$ 5.074/ano** | **R$ 4.500** | **R$ 54** | |

**Observação:** Mesmo com perda anual projetada R$ 5.074 (cenário pessimista), **economia R$ 4.320/ano ainda justifica implementação** (break-even em ROI negativo aceitável).

---

### Análise de Viabilidade Considerando Riscos

**Economia Projetada (sem riscos):** R$ 4.320/ano
**Perda Esperada (riscos não mitigados):** R$ 5.074/ano
**Economia Líquida (pessimista):** **-R$ 754/ano** ❌ **NEGATIVA**

**Decisão Crítica:** Implementar **TODAS as mitigações prioritárias** (R-019.1 + R-019.2) = R$ 1.350 investimento adicional

**Recalculo com Mitigações:**
```
Economia Projetada:              R$ 4.320/ano
Investimento Total:              R$ 3.000 (desenvolvimento) + R$ 1.350 (mitigações) = R$ 4.350
Perda Esperada (mitigada 90%):   R$ 507/ano (R$ 5.074 × 10%)
Custo Operacional Lambda:        R$ 24/ano
────────────────────────────────────────────────────────
Economia Líquida Year 1:         R$ 4.320 - R$ 4.350 - R$ 507 - R$ 24 = -R$ 561 ❌

ROI Year 1 (com mitigações):     -12.9% (NEGATIVO) ❌
Payback:                         NUNCA (economia < investimento)
```

**⚠️ CONCLUSÃO CRÍTICA:** Implementação da automação **NÃO é viável financeiramente no Year 1** quando consideramos:
1. Investimento desenvolvimento: R$ 3.000
2. Mitigações obrigatórias: R$ 1.350
3. Perdas residuais: R$ 507/ano

**ALTERNATIVA RECOMENDADA:**

| Abordagem | Investimento | Economia Year 1 | ROI Year 1 | Decisão |
|-----------|-------------|-----------------|-----------|---------|
| **Automação Completa (proposta inicial)** | R$ 4.350 | -R$ 561 | -12.9% | ❌ REJEITADO |
| **Automação Simplificada** (sem health checks complexos) | R$ 2.700 | R$ 1.113 | 41% | ✅ **APROVADO** |
| **Manual Scripts** (zero automação, processo operacional) | R$ 0 | R$ 0 | N/A | ⏳ Considerar |

**Automação Simplificada (Proposta Ajustada):**
- Investimento: R$ 2.700 (9h vs 14.5h)
- Remove: Health checks GitLab complexos (R-019.2), Step Functions fallback (R-019.4)
- Mantém: Retry RDS (R-019.1), BrasilAPI cache (R-019.3), Circuit breaker básico (R-019.5)
- Aceita: Risco residual R-019.2 (2% GitLab jobs perdidos) = R$ 1.200/ano perda esperada
- **Economia Líquida Year 1:** R$ 4.320 - R$ 2.700 - R$ 1.200 - R$ 24 = **R$ 396** ✅
- **ROI Year 1:** 14.7% (viável porém marginal)
- **Payback:** 8.2 meses

---

### Recomendações Finais

**Decisão Executiva:**
1. ⏸️ **PAUSAR implementação completa** (ADR-024 original)
2. ✅ **APROVAR versão simplificada** (70% features, 60% investimento)
3. ⏳ **REAVALIAR Q3 2026** (após 6 meses operação, validar perdas reais)

**Critérios de Sucesso Versão Simplificada:**
- Zero falhas startup (R-019.1 mitigado)
- ≤ 2 jobs GitLab perdidos/ano (R-019.2 risco aceito)
- Economia observada ≥ R$ 350/mês (threshold viabilidade)
- Satisfação equipe > 7/10 (aceitação processo)

**Triggers para Upgrade Completo:**
- Perda observada R-019.2 > R$ 2.000/ano (upgrade health checks GitLab)
- Falhas Lambda timeout > 5×/ano (upgrade Step Functions)
- Budget disponível Q3 2026 (ROI cumulativo justifica investimento adicional)

---

**Referências:**
- [Demanda Original](../demands/2026-01-30-automacao-finops-staging.md)
- [ADR-024 (Original)](./decisions.md#adr-024)
- [Costs Analysis](./costs.md#automacao-finops-staging-planejada---adr-024)
- [Architecture](./architecture.md#fase-9-finops-automation-staging-environment)

**Status:** 📝 PLANEJADO → Aguardando aprovação versão simplificada
**Responsável:** FinOps Team + DevOps Lead
**Próxima Revisão:** 2026-02-03 (decisão stakeholders versão simplificada)

---

### Security Review (Agente Security & Compliance - 2026-01-30)

**Análise Pré-Execução:** Identificados 3 riscos de segurança com ressalvas obrigatórias.

**Decisão Agente Security:** ✅ **APROVADO COM 2 RESSALVAS OBRIGATÓRIAS**

#### S-019.1: DynamoDB Encryption at Rest

**Severidade:** 🟡 MÉDIA | **Status:** ⚠️ OBRIGATÓRIO
- **Problema:** Circuit breaker state sem encryption (violação best practice)
- **Solução:** Habilitar KMS encryption
- **Custo:** +R$ 6/mês
- **Deadline:** Antes de terraform apply

#### S-019.2: Lambda VPC Validation

**Severidade:** 🟡 MÉDIA | **Status:** ⚠️ OBRIGATÓRIO
- **Problema:** Lambda precisa internet para BrasilAPI
- **Solução:** Usar Lambda sem VPC (default) ou validar NAT Gateway
- **Custo:** $0 (sem VPC) ou $32/mês (NAT)
- **Decisão:** Lambda SEM VPC (recomendado)

#### S-019.3: IAM Policy Versioning

**Severidade:** 🟢 BAIXA | **Status:** 💡 RECOMENDADO
- **Problema:** Policies sem versionamento dificultam rollback
- **Solução:** Adicionar sufixo `-v1` no policy name
- **Custo:** $0
- **Prioridade:** Baixa (implementar se houver tempo)

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
