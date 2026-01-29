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

## 📈 Tendências de Riscos

### Riscos Emergentes (Marco 3)
- **R-013:** GitLab CE single point of failure (sem HA configurado)
- **R-014:** Backup & DR strategy inexistente (loss tolerance: 24h RPO)
- **R-015:** PostgreSQL RDS sem Multi-AZ (custo vs HA trade-off)
- **R-016:** Secrets rotation policy inexistente (compliance risk)

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
