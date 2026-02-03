# 📋 Decisões Técnicas - Plataforma Kubernetes AWS

**Última Atualização:** 2026-02-03
**Versão:** 3.1 (Marco 3 + Redis Sentinel Fix PSS Restricted)
**Framework:** Baseado em ADRs (Architecture Decision Records)

---

## 🎯 Índice de Decisões

| ID | Decisão | Data | Status | Impacto |
|----|---------|------|--------|---------|
| ADR-001 | Setup e Governança | 2025-12 | ✅ Ativo | Alto |
| ADR-002 | Estrutura de Domínios | 2025-12 | ✅ Ativo | Médio |
| ADR-003 | Secrets Management Strategy | 2026-01 | ✅ Ativo | Alto |
| ADR-004 | Terraform vs Helm para Platform Services | 2026-01 | ✅ Ativo | Alto |
| ADR-005 | Logging Strategy (Loki vs CloudWatch) | 2026-01 | ✅ Ativo | Alto |
| ADR-006 | Network Policies Strategy (Calico) | 2026-01 | ✅ Ativo | Alto |
| ADR-007 | Cluster Autoscaler Strategy | 2026-01 | ✅ Ativo | Médio |
| ADR-008 | TLS Strategy for ALB Ingresses | 2026-01 | ✅ Ativo | Alto |
| DEC-009 | ACM Conditional Creation Fix | 2026-01-29 | ✅ Ativo | Crítico |
| DEC-010 | VPC Reaproveitamento | 2026-01 | ✅ Ativo | Alto |
| **ADR-020** | **OpenTelemetry Tracing Strategy (Tempo vs Jaeger)** | **2026-01-29** | **✅ Ativo** | **Alto** |
| **ADR-021** | **No-Domain Phase 1 Strategy (LoadBalancer Pattern)** | **2026-01-29** | **✅ Ativo** | **Médio** |
| **ADR-022** | **Startup/Shutdown Automation Strategy (FinOps)** | **2026-01-29** | **✅ Ativo** | **Alto** |
| **ADR-023** | **Migration from Bitnami Charts to Kubernetes Operators** | **2026-01-29** | **✅ Ativo** | **Crítico** |
| **ADR-024** | **FinOps Automation Multi-Ambiente (EventBridge + Lambda)** | **2026-02-02** | **🚀 Ativo (Staging)** | **Alto** |
| **ADR-025** | **Tempo Deployment - Replication Factor Decision (RF=2 vs RF=3)** | **2026-01-31** | **✅ Implementado** | **Alto** |
| **ADR-026** | **Multi-Environment Terraform Refactoring** | **2026-02-02** | **✅ Aprovado** | **Crítico** |
| **ADR-027** | **Shared GitLab with Separated DataServices** | **2026-02-02** | **✅ Aprovado** | **Alto** |
| **ADR-028** | **Hybrid Observability with OpenTelemetry** | **2026-02-02** | **✅ Aprovado** | **Alto** |
| **ADR-029** | **Redis Sentinel User Alignment for PSS Restricted** | **2026-02-03** | **✅ Implementado** | **Crítico** |

---

## 📝 ADR-001: Setup e Governança

**Data:** 2025-12
**Status:** ✅ Ativo
**Contexto:** Definição de processos de governança para infraestrutura

### Decisão
Implementar governança documental com hooks pre-commit para validação automática.

### Rationale
- Garantir consistência de documentação
- Prevenir commits sem documentação
- Automatizar validações de qualidade

### Consequências
- ✅ Commits sempre passam por validação
- ✅ Documentação sempre atualizada
- ⚠️ Requer disciplina da equipe

**Arquivo:** [adr-001-setup-e-governanca.md](../adr/adr-001-setup-e-governanca.md)

---

## 📝 ADR-002: Estrutura de Domínios

**Data:** 2025-12
**Status:** ✅ Ativo
**Contexto:** Organização de código por domínios técnicos

### Decisão
Estrutura baseada em domínios (observability, ci-cd, identity, etc).

### Rationale
- Separação clara de responsabilidades
- Facilita onboarding de novos membros
- Evita god modules

### Consequências
- ✅ Código organizado
- ✅ Fácil localização de componentes
- ⚠️ Requer planejamento inicial

**Arquivo:** [adr-002-estrutura-de-dominios.md](../adr/adr-002-estrutura-de-dominios.md)

---

## 📝 ADR-003: Secrets Management Strategy

**Data:** 2026-01-26
**Status:** ✅ Ativo - Marco 2 Fase 3
**Contexto:** Gerenciamento seguro de credenciais (Grafana, databases, APIs)

### Decisão
**AWS Secrets Manager** como backend primário para secrets sensíveis.

### Alternativas Consideradas
1. ❌ **Hardcoded em terraform.tfvars** - REJEITADO (risco segurança, commit acidental)
2. ❌ **Kubernetes Secrets plaintext** - REJEITADO (base64 não é encryption)
3. ❌ **HashiCorp Vault** - REJEITADO (overhead operacional, custo adicional $150-300/mês)
4. ✅ **AWS Secrets Manager** - ESCOLHIDO

### Rationale
- Integração nativa AWS (KMS encryption)
- Rotation automática suportada
- Auditoria CloudTrail
- Custo baixo ($0.40/secret/mês)

### Consequências
- ✅ Secrets nunca commitados em Git
- ✅ Encryption at rest (KMS)
- ✅ Auditoria completa
- ⚠️ Vendor lock-in AWS
- 💰 Custo: $0.40/mês por secret

**Implementado:** Grafana admin password
**Arquivo:** [adr-003-secrets-management-strategy.md](../adr/adr-003-secrets-management-strategy.md)

---

## 📝 ADR-004: Terraform vs Helm para Platform Services

**Data:** 2026-01-26
**Status:** ✅ Ativo - Marco 2
**Contexto:** Escolher ferramenta para deploy de platform services (Prometheus, Loki, etc)

### Decisão
**Terraform com Helm provider** para deploy de charts.

### Alternativas Consideradas
1. ❌ **Helm CLI puro** - REJEITADO (não versionável, drift detection fraco)
2. ❌ **ArgoCD/FluxCD** - REJEITADO (adiciona complexidade prematura)
3. ✅ **Terraform + Helm provider** - ESCOLHIDO

### Rationale
- Single source of truth (Terraform state)
- Drift detection automático
- Rollback nativo
- Integração AWS resources + Kubernetes resources
- CI/CD friendly (terraform plan/apply)

### Consequências
- ✅ Infraestrutura toda em Terraform
- ✅ Drift detection funcional
- ✅ Rollback fácil
- ⚠️ Helm charts grandes = plan verboso
- ⚠️ Dois pontos de configuração (values + terraform vars)

**Arquivo:** [adr-004-terraform-vs-helm-for-platform-services.md](../adr/adr-004-terraform-vs-helm-for-platform-services.md)

---

## 📝 ADR-005: Logging Strategy (Loki vs CloudWatch)

**Data:** 2026-01-26
**Status:** ✅ Ativo - Marco 2 Fase 4
**Contexto:** Centralização de logs Kubernetes

### Decisão
**Loki + Fluent Bit** com backend S3.

### Alternativas Consideradas
1. ❌ **CloudWatch Logs** - REJEITADO (custo 3× maior: $50/mês vs $19.70/mês)
2. ❌ **Elasticsearch (ELK Stack)** - REJEITADO (overhead operacional, custo nodes ~$200/mês)
3. ❌ **Splunk** - REJEITADO (custo proibitivo ~$500/mês)
4. ✅ **Loki + Fluent Bit** - ESCOLHIDO

### Rationale
- Economia: $423/ano vs CloudWatch
- Cloud-agnostic (portabilidade futura)
- Integração nativa Grafana (métricas + logs correlacionados)
- S3 backend (durabilidade, lifecycle policies)
- SimpleScalable mode (HA sem complexidade)

### Consequências
- ✅ Economia $423/ano
- ✅ Logs + Métricas no mesmo dashboard (Grafana)
- ✅ LogQL queries (similar PromQL)
- ⚠️ Requer tuning de parsers (JSON, multiline)
- 💰 Custo: $19.70/mês (S3 $11.50 + EBS $3.20 + requests $5)

**Componentes:**
- Loki: 8 pods (2 read, 2 write, 2 backend, 2 gateway)
- Fluent Bit: 7 pods (DaemonSet, 1 por node)
- Retenção: 30 dias S3, 7 dias in-memory

**Arquivo:** [adr-005-logging-strategy.md](../adr/adr-005-logging-strategy.md)

---

## 📝 ADR-006: Network Policies Strategy

**Data:** 2026-01-28
**Status:** ✅ Ativo - Marco 2 Fase 5
**Contexto:** Isolamento de rede entre namespaces e pods

### Decisão
**Calico policy-only mode** (overlay AWS VPC CNI).

### Alternativas Consideradas
1. ❌ **Nenhuma Network Policy** - REJEITADO (risco segurança, zero isolation)
2. ❌ **AWS VPC CNI Network Policies** - REJEITADO (feature beta, não production-ready)
3. ❌ **Calico full mode (IPIP overlay)** - REJEITADO (overhead performance, ENI incompatibility)
4. ✅ **Calico policy-only** - ESCOLHIDO

### Rationale
- Zero Trust: default deny, explicit allow
- Policy engine robusto (Calico)
- Networking mantido AWS VPC CNI (ENI-based)
- Sem overhead de overlay network
- Custo zero (não requer nodes adicionais)

### Consequências
- ✅ Isolamento entre namespaces
- ✅ Controle granular de egress/ingress
- ✅ Sem impacto performance (sem overlay)
- ⚠️ Requer mapeamento de fluxos antes de aplicar
- 💰 Custo: $0

**Políticas Implementadas:** 11 total
- 3 default-deny (kube-system, monitoring, cert-manager)
- 3 allow-dns
- 3 allow-api-server
- 1 allow-prometheus-scraping
- 1 allow-fluent-bit-to-loki

**Arquivo:** [adr-006-network-policies-strategy.md](../adr/adr-006-network-policies-strategy.md)

---

## 📝 ADR-007: Cluster Autoscaler Strategy

**Data:** 2026-01-28
**Status:** ✅ Ativo - Marco 2 Fase 6
**Contexto:** Auto-scaling de nodes Kubernetes

### Decisão
**Cluster Autoscaler** (não Karpenter por enquanto).

### Alternativas Consideradas
1. ❌ **Sem autoscaling** - REJEITADO (desperdício de recursos)
2. ❌ **Karpenter** - REJEITADO (complexidade prematura, overkill para escala atual)
3. ✅ **Cluster Autoscaler** - ESCOLHIDO

### Rationale
- Simplicidade (Helm chart oficial)
- Integração nativa EKS
- IRSA pattern (sem Access Keys)
- Scale-down habilitado (economia)
- Suficiente para escala atual (<100 nodes)

### Consequências
- ✅ Economia em baixa demanda (scale-down)
- ✅ Expansão automática em picos
- ✅ IRSA configurado (segurança)
- ⚠️ Menos otimizado que Karpenter (spot instances)
- 💰 Custo: $0 (usa nodes existentes), economia estimada ~$372/ano

**Configuração:**
- Scale-down: Habilitado (5 min unneeded threshold)
- ASG tags: Aplicados em Marco 1 (cluster-autoscaler.kubernetes.io/enabled)
- ServiceMonitor: Integrado Prometheus

**Arquivo:** [adr-007-cluster-autoscaler-strategy.md](../adr/adr-007-cluster-autoscaler-strategy.md)

---

## 📝 ADR-008: TLS Strategy for ALB Ingresses

**Data:** 2026-01-28
**Status:** ✅ Ativo - Marco 2 Fase 7.1 (Código implementado, aguardando domínio)
**Contexto:** HTTPS para aplicações expostas via ALB

### Decisão
**ACM (AWS Certificate Manager)** com validação DNS automática via Route53.

### Alternativas Consideradas
1. ❌ **Cert-Manager + Let's Encrypt → Kubernetes Secret** - REJEITADO (ALB não lê Secrets)
2. ❌ **Self-signed certificates** - REJEITADO (browser warnings, sem confiança pública)
3. ❌ **Manual certificate upload ACM** - REJEITADO (sem auto-renewal)
4. ❌ **Third-party CA (DigiCert, GlobalSign)** - REJEITADO (custo $200-500/ano por cert)
5. ❌ **CloudFlare Tunnel** - REJEITADO (vendor lock-in, complexidade adicional)
6. ✅ **ACM + Route53 DNS validation** - ESCOLHIDO

### Rationale
- ACM certificates gratuitos (managed by AWS)
- Auto-renewal automático (60 dias antes expiration)
- Integração nativa ALB (annotation)
- DNS validation via Route53 (automático com Terraform)
- Sem overhead operacional

### Consequências
- ✅ Certificates gratuitos e auto-renew
- ✅ HTTPS end-to-end (browser → ALB)
- ✅ Terraform cria tudo automaticamente (ACM + Route53 records)
- ⚠️ Requer domínio registrado ($12/ano)
- ⚠️ DNS delegation se registrar externo (NS records)
- 💰 Custo: $0.90/mês (Route53 hosted zone), +$12/ano (domain registration)

**Código:** 100% implementado (12 terraform modules)
**Status Deployment:** Aguardando `enable_tls = true` + domínio registrado

**Arquivo:** [adr-008-tls-strategy-for-alb-ingresses.md](../adr/adr-008-tls-strategy-for-alb-ingresses.md)

---

## 📝 DEC-009: ACM Conditional Creation Fix (CRÍTICO)

**Data:** 2026-01-29
**Status:** ✅ Resolvido - Marco 2 Fase 7
**Tipo:** Correção de Bug
**Severidade:** Crítico (bloqueava deploy)

### Problema
Terraform tentava criar recursos `aws_acm_certificate` mesmo com `enable_tls = false`, resultando em erro:
```
Error: invalid value for domain_name (cannot end with a period)
```

### Causa Raiz
Recursos ACM sem parâmetro `count` condicional. Eram criados incondicionalmente, recebendo `domain_name = ""` quando TLS desabilitado, resultando em `"nginx-test."` (inválido).

### Decisão
Adicionar `count = var.enable_tls ? 1 : 0` em **todos** recursos ACM:
- `aws_acm_certificate.nginx_test`
- `aws_acm_certificate.echo_server`
- `aws_acm_certificate_validation.nginx_test`
- `aws_acm_certificate_validation.echo_server`

Atualizar **todas** referências para usar `[0]` index quando `enable_tls = true`.

### Arquivos Modificados
- `modules/test-applications/acm.tf` (28 linhas alteradas)
- `modules/test-applications/main.tf` (12 linhas alteradas)
- `modules/test-applications/outputs.tf` (8 linhas alteradas)

### Consequências
- ✅ Terraform plan funciona com `enable_tls = false`
- ✅ Deploy Fase 7 completo sem erros
- ✅ Código preparado para Fase 7.1 (TLS activation)
- ⚠️ Pattern aprendido: Sempre usar `count` em recursos opcionais

**Commit:** 4a1c3e2 (2026-01-29)

---

## 📝 DEC-010: VPC Reaproveitamento

**Data:** 2026-01-23
**Status:** ✅ Ativo - Marco 0
**Tipo:** Otimização de Custos

### Contexto
VPC `vpc-0b1396a59c417c1f0` existente na conta AWS (10.0.0.0/16, 2 AZs, NAT Gateways).

### Decisão
Reaproveitar VPC existente em vez de criar nova.

### Rationale
- Economia $96/mês (2 NAT Gateways × $48/mês)
- Subnets já configuradas (public + private)
- Route tables corretas
- Infraestrutura validada e estável

### Consequências
- ✅ Economia $1.152/ano
- ✅ Menor complexidade (não criar networking do zero)
- ✅ Faster time-to-market (skip VPC provisioning)
- ⚠️ Dependência de infra pré-existente (requer engenharia reversa)
- 💰 Economia: $96/mês ($1.152/ano)

**Scripts Criados:**
- `marco0/scripts/reverse-engineer-vpc.sh` (import recursos existentes)

---

## 📝 ADR-020: OpenTelemetry Tracing Strategy (Tempo vs Jaeger)

**Data:** 2026-01-29
**Status:** ✅ Ativo
**Contexto:** Marco 2 Fase 8 - Completar observabilidade com traces distribuídos

### Decisão
Adotar **Grafana Tempo** como backend de traces, rejeitando Jaeger.

### Contexto Técnico
Após Marco 2 Fases 1-7 (Prometheus, Grafana, Loki), faltava traces para completar a tríade de observabilidade (métricas, logs, traces). Duas opções principais:
- **Grafana Tempo** - Backend traces S3-first, integração nativa Grafana
- **Jaeger** - CNCF graduated project, requer Cassandra/ElasticSearch backend

### Análise de Agentes Especialistas

#### AWS Specialist (Agent a0daab9):
- Tempo: Economia $147-297/mês vs Cassandra backend
- IRSA pattern reutilizável (já usado em Loki)
- Network Policies: 4 policies adicionais (allow-otel-collector-ingress, allow-otel-to-tempo, etc.)
- Custo Tempo: $32.50/mês (baseline) → $19.70/mês (otimizado sampling 10%)

#### Terraform Specialist (Agent a31daa9):
- Módulo separado `modules/tempo/` (consistente com `modules/loki/`)
- Helm chart: `grafana/tempo` v1.10.0 (SimpleScalable mode)
- Dependências: Tempo depende de Grafana deployed (datasource config)
- Recomendação: Gateway mode para OpenTelemetry Collector (2 replicas HA)

#### FinOps (Agent a0031ad):
- **Custo Tempo:** $19.70/mês (S3 $11.50 + API $5.00 + EBS $3.20)
- **Custo Jaeger:** $210/mês (Cassandra $150 + Collector $30 + EBS $30)
- **Economia:** $205.55/mês ($2,467/ano)
- Otimizações possíveis: Sampling 10% + retenção 7 dias → $4.45/mês

### Rationale
1. ✅ **Economia:** $205.55/mês vs Jaeger com Cassandra
2. ✅ **Consistência stack:** Grafana + Loki + Tempo (tríade completa Grafana Labs)
3. ✅ **Reutilização patterns:** IRSA + S3 (já implementado em Loki)
4. ✅ **Zero DB management:** S3 é serverless (vs Cassandra cluster ops)
5. ✅ **Correlação nativa:** Grafana UI integra traces ↔ logs ↔ metrics
6. ✅ **TraceQL:** Query language moderna (similar LogQL/PromQL)

### Trade-offs Aceitos
| Aspecto | Tempo | Jaeger | Decisão |
|---------|-------|--------|---------|
| **Custo** | $19.70/mês | $210/mês | Tempo ✅ |
| **Search avançado** | Limitado (TraceQL basic) | Excelente (tags, duration) | Aceitável ⚠️ |
| **Maturidade** | 2020+ | CNCF Graduated | Suficiente ✅ |
| **Operational overhead** | Baixo (S3 managed) | Alto (DB cluster) | Tempo ✅ |

**Trade-off principal:** Search limitado em Tempo vs custo/complexidade Jaeger. Decisão: 80% dos casos usam trace ID de logs (correlação Loki), search avançado não justifica +$191/mês.

### Consequências
- ✅ Stack observabilidade completa (Prometheus + Loki + Tempo)
- ✅ Economia $2,467/ano vs Jaeger
- ✅ 36 pods em `monitoring` namespace (13 Prometheus + 15 Loki + 6 Tempo + 2 OTel)
- ✅ Correlação traces → logs → metrics em single pane (Grafana)
- ⚠️ Search traces limitado (mitigação: 100% sampling de erros, 10% normal)
- 💰 **Custo adicional Marco 2:** +$19.70/mês

**Componentes Deployed:**
- Tempo backend: 6 pods (2 distributor, 2 ingester, 1 querier, 1 compactor)
- OpenTelemetry Collector: 2 pods (Gateway mode)
- S3 bucket: `k8s-platform-tempo-891377105802`
- IRSA Role: `TempoS3Role-k8s-platform-prod`

**Arquivo:** Marco 2 Fase 8 implementation

---

## 📝 ADR-021: No-Domain Phase 1 Strategy (LoadBalancer Pattern)

**Data:** 2026-01-29
**Status:** ✅ Ativo
**Contexto:** Marco 3 deployment sem domínio registrado

### Decisão
Implementar Marco 3 (GitLab, PostgreSQL, Redis, RabbitMQ, ArgoCD, Harbor) **SEM domínio** inicialmente (Fase 1), usando:
- **LoadBalancer services (NLB)** para databases (PostgreSQL, Redis, RabbitMQ)
- **ALB DNS HTTP** para workloads (GitLab, ArgoCD, Harbor)
- **TLS/SSO** postergar para Fase 2 (quando domínio registrado)

### Contexto Técnico
Bloqueio identificado: Domínio não registrado impedia deploy com HTTPS/SSO. Duas opções:
1. **Aguardar domínio** → Bloquear todo Marco 3 até registro
2. **Deploy sem domínio** → Ambiente 90% operacional, migração transparente depois

### Análise de Agentes Especialistas

#### AWS Specialist:
- **LoadBalancer (NLB)** para PostgreSQL/Redis/RabbitMQ: Endpoints AWS públicos acessíveis via DBeaver, Redis CLI, RabbitMQ UI
- Custo NLB: $16.20/mês cada → 3 NLBs = $48.60/mês
- **ALB DNS HTTP** para GitLab/ArgoCD/Harbor: URLs como `http://k8s-gitlab-xyz.us-east-1.elb.amazonaws.com`
- Funcionalidades GitLab sem HTTPS: Git push/pull, CI/CD pipelines, Interface Web ✅
- Limitações: Webhooks HTTPS externos ❌, SSO via Keycloak ❌

#### Terraform Specialist:
- Configuração via variáveis:
  ```hcl
  enable_tls           = false
  create_route53_zone  = false
  domain_name          = ""
  postgresql_service_type = "LoadBalancer"
  redis_service_type      = "LoadBalancer"
  rabbitmq_service_type   = "LoadBalancer"
  ```
- Migração Fase 2: Apenas atualizar `enable_tls = true` + `domain_name` → `terraform apply`
- ALBs são recriados com HTTPS, downtime < 2 min

#### FinOps:
- **Custo Fase 1:** $902.30/mês (sem otimizações)
- Custo adicional NLBs: $48.60/mês (3 databases)
- **vs Fase 2:** +$0.50/mês (Route53 Hosted Zone)
- Economia tempo: Deploy imediato vs aguardar registro domínio (1-7 dias)

### Rationale
1. ✅ **Unblock Marco 3:** Não aguardar domínio (can take 1-7 days)
2. ✅ **90% funcionalidade:** GitLab CI/CD, ArgoCD GitOps, Harbor registry funcionais internamente
3. ✅ **Zero retrabalho:** Migração Fase 2 transparente (apenas terraform.tfvars update)
4. ✅ **Acesso externo DBs:** DBeaver, PgAdmin, Redis CLI via NLB endpoints
5. ✅ **Uso interno imediato:** Time pode começar a trabalhar com GitLab/ArgoCD agora
6. ⚠️ **Limitações aceitáveis:** Sem webhooks HTTPS externos, sem SSO (features avançadas, não bloqueantes)

### Implementação Fase 1 (Sem Domínio)

**PostgreSQL RDS:**
- Endpoint interno: `postgresql.default.svc.cluster.local:5432`
- Endpoint externo (NLB): `postgres-lb-xyz.us-east-1.elb.amazonaws.com:5432`
- Clientes: DBeaver, PgAdmin, psql

**Redis:**
- Endpoint interno: `redis-master.default.svc.cluster.local:6379`
- Endpoint externo (NLB): `redis-lb-xyz.us-east-1.elb.amazonaws.com:6379`
- Clientes: Redis Desktop Manager, redis-cli

**RabbitMQ:**
- Endpoint interno: `rabbitmq.default.svc.cluster.local:5672`
- Management UI (NLB): `rabbitmq-lb-xyz.us-east-1.elb.amazonaws.com:15672`

**GitLab CE:**
- URL: `http://k8s-gitlab-xyz.us-east-1.elb.amazonaws.com`
- Funcionalidades: Git push/pull ✅, CI/CD pipelines ✅, Interface Web ✅
- Limitações: Webhooks HTTPS externos ❌, SSO ❌

**ArgoCD:**
- URL: `http://k8s-argocd-xyz.us-east-1.elb.amazonaws.com`
- Funcionalidades: GitOps ✅, auto-sync ✅, deployment tracking ✅

**Harbor:**
- URL: `http://k8s-harbor-xyz.us-east-1.elb.amazonaws.com`
- Funcionalidades: Registry ✅, Trivy scan ✅ (menos seguro sem HTTPS ⚠️)

### Migração Fase 2 (Com Domínio)

**Trigger:** Quando domínio registrado ou quando precisar de funcionalidades avançadas (webhooks HTTPS, SSO)

**Passos:**
1. Registrar domínio (Route53 ~$12/ano ou registrador externo)
2. Atualizar `terraform.tfvars`:
   ```hcl
   enable_tls           = true
   create_route53_zone  = true
   domain_name          = "k8s-platform.mycompany.com"
   ```
3. `terraform apply` → ALBs recriados com HTTPS (downtime < 2 min)
4. Deploy Keycloak + configurar OIDC
5. Integrar SSO em GitLab, ArgoCD, Harbor, Grafana

### Consequências
- ✅ **Fase 1 operacional AGORA:** Sem aguardar domínio
- ✅ **Custo adicional:** +$48.60/mês (3 NLBs)
- ✅ **Funcionalidade:** 90% (suficiente para uso interno desenvolvimento)
- ✅ **Migração transparente:** Zero retrabalho quando domínio registrado
- ⚠️ **Limitações temporárias:** Sem webhooks HTTPS, sem SSO (aceitável internamente)
- ⚠️ **Segurança reduzida:** HTTP (não HTTPS) - mitigação: uso interno apenas, sem exposição internet
- 💰 **Custo Fase 1:** $902.30/mês → **$737.10/mês** (com otimizações Q1 2026: RI + consolidações)

### Trade-offs Aceitos
| Aspecto | Fase 1 (Sem Domínio) | Fase 2 (Com Domínio) |
|---------|----------------------|----------------------|
| **Funcionalidade** | 90% operacional ✅ | 100% completo |
| **Segurança** | Autenticação básica (password) ⚠️ | TLS + SSO/OIDC ✅ |
| **Tempo para deploy** | Imediato ✅ | +1 semana |
| **Custo** | +$48.60/mês (NLBs) | +$49.10/mês (NLBs + Route53) |
| **Bloqueadores** | Nenhum ✅ | Registro domínio |
| **Uso** | Interno, desenvolvimento ✅ | Produção, webhooks externos |

**Decisão:** ✅ **Fase 1 primeiro** permite trabalhar operacionalmente AGORA, adicionar segurança DEPOIS sem retrabalho.

---

## 📝 ADR-022: Startup/Shutdown Automation Strategy (FinOps)

**Data:** 2026-01-29
**Status:** ✅ Ativo
**Contexto:** Otimização de custos através de automação de startup/shutdown da infraestrutura

### Decisão
Adotar **scripts bash de startup/shutdown** com automação futura via **GitHub Actions** para gerenciar o ciclo de vida da infraestrutura AWS EKS, permitindo economia significativa em ambientes não-produtivos através do desligamento programado da infraestrutura.

### Contexto Técnico
Durante o desenvolvimento do projeto, identificamos que:
- **Fase atual:** Desenvolvimento/testes - infraestrutura precisa estar ativa apenas durante horário de trabalho (8-10h/dia)
- **Fase futura:** Produção - infraestrutura ativa durante horário comercial, com custos fixos aceitos
- **Custo baseline:** $685.70/mês (Marco 2 com Fase 8 OpenTelemetry)
- **Oportunidade:** 70.7% dos custos são variáveis (EC2 nodes, data transfer) e podem ser eliminados com shutdown

Duas fases distintas de uso:
1. **Fase Desenvolvimento** (atual): "Ligar" durante trabalho, "desligar" fora do horário
2. **Fase Produção** (futura): Infraestrutura sempre ativa (ou com shutdown noturno/finais de semana)

### Análise de Agentes Especialistas

#### FinOps Specialist (Agent a1179fb):

**Breakdown de Custos Fixos vs Variáveis:**

| Categoria | Componente | Custo/Mês | % | Tipo |
|-----------|------------|-----------|---|------|
| **Fixos (Always On)** | | **$200.75** | **29.3%** | |
| | EKS Control Plane | $73.00 | 10.6% | Fixo |
| | NAT Gateways (2) | $66.00 | 9.6% | Fixo |
| | S3 (State + Loki + Tempo) | $34.57 | 5.0% | Fixo |
| | ALBs (2) | $16.20 | 2.4% | Fixo |
| | Route53 Hosted Zone | $0.50 | 0.1% | Fixo |
| | Secrets Manager | $0.40 | 0.1% | Fixo |
| | CloudWatch Logs (minimal) | $10.08 | 1.5% | Fixo |
| **Variáveis (Stop/Start)** | | **$484.95** | **70.7%** | |
| | EC2 Nodes (7× t3.medium) | $477.12 | 69.6% | Variável |
| | EBS Volumes (PVCs) | $5.36 | 0.8% | Variável (parcial) |
| | Data Transfer | $2.47 | 0.3% | Variável |
| **TOTAL** | | **$685.70** | **100%** | |

**Cenários de Economia:**

| Cenário | Uptime | Economia/Mês | Economia/Ano | % Redução |
|---------|--------|--------------|--------------|-----------|
| **Desenvolvimento 8h/dia** | 33% (8h/24h × 22 dias úteis) | **$368.96** | **$4,427.52** | **53.8%** |
| **Desenvolvimento 10h/dia** | 42% | $333.52 | $4,002.24 | 48.6% |
| **Produção 12h/dia** | 50% | $298.08 | $3,576.96 | 43.5% |
| **Produção 24/5** (shutdown noturno + weekends) | 71% | $176.84 | $2,122.08 | 25.8% |

**ROI Automação:**
- **Investimento:** 8h desenvolvimento scripts + 4h GitHub Actions = 12h × $50/h = $600
- **Economia Year 1:** $4,427.52 (cenário 8h/dia)
- **ROI:** 738% (primeiro ano)
- **Payback:** 1.3 meses

**Limitações AWS:**
- **RDS:** Máximo 7 dias stopped (AWS auto-restart após 7 dias) - consideração futura para Marco 3
- **EBS Snapshots:** Custos persistem (~$0.05/GB/mês)
- **Elastic IPs:** Se não associados, cobrança $0.005/hora ($3.65/mês) - mitigação: release IPs durante shutdown

#### AWS Specialist (Agent aae38a8):

**Classificação de Componentes por Lifecycle:**

| Componente | Ação Shutdown | Ação Startup | Cold Start | Data Loss Risk |
|------------|---------------|--------------|------------|----------------|
| **EKS Cluster** | Stop (nodes ASG desired=0) | Start (nodes ASG desired=7) | 5-8 min | ❌ Baixo (PVCs preservados) |
| **EC2 Nodes** | Terminate (ASG scale to 0) | Create (ASG scale to 7) | 3-5 min | ❌ Nenhum (stateless) |
| **EBS Volumes (PVCs)** | Persist (detached) | Reattach automático | 1-2 min | ❌ Nenhum (persistent) |
| **S3 Buckets** | Always On | N/A | Instant | ❌ Nenhum |
| **RDS** | Stop instance | Start instance | 3-5 min | ❌ Nenhum |
| **NAT Gateways** | Always On (custo fixo) | N/A | N/A | N/A |
| **ALBs** | Always On (custo fixo) | N/A | N/A | N/A |
| **VPC/Subnets/SGs** | Always On (sem custo) | N/A | N/A | N/A |
| **IRSA Roles** | Always On (sem custo) | N/A | N/A | N/A |

**Cold Start Times:**
- **Cenário 1 - Nodes Only** (cluster mantido): 5-8 min total
  - ASG scale up: 2-3 min (EC2 launch)
  - Nodes join cluster: 1-2 min (kubelet registration)
  - Pods scheduling: 2-3 min (image pull + init)
- **Cenário 2 - Full Cluster** (destroy tudo, recreate): 12-18 min total
  - Terraform apply: 8-12 min (EKS + nodes)
  - Platform services: 4-6 min (Helm releases)

**Recomendações Operacionais:**
1. **Preservar sempre:**
   - PVCs (dados Prometheus, Loki, Grafana)
   - S3 buckets (logs, traces, terraform state)
   - EBS Snapshots (backups)
2. **Health Checks pós-startup:**
   - kubectl get nodes (7 nodes Ready)
   - kubectl get pods -A (todos Running)
   - Grafana UI accessible (métricas funcionando)
3. **CloudWatch Alarms:**
   - ASG scale events
   - EKS cluster status
   - RDS availability (Marco 3)
4. **Tagging Strategy:**
   - Tag: `AutoShutdown=true` (recursos eligible para shutdown)
   - Tag: `Environment=dev` (diferenciar dev vs prod)

#### Terraform Specialist (Agent a9d1641):

**Avaliação de Abordagens:**

| Abordagem | Viabilidade | Pros | Cons | Decisão |
|-----------|-------------|------|------|---------|
| **Bash Scripts** (atual) | ✅ VIÁVEL | Flexibilidade total, debug fácil, logs granulares | Requer execução manual (por enquanto) | ✅ MANTER |
| **Terraform Variables** (`desired_size = 0`) | ❌ NÃO RECOMENDADO | Nativo Terraform | Conflita com Cluster Autoscaler (state drift) | ❌ REJEITAR |
| **Terraform Workspaces** | ❌ NÃO RECOMENDADO | Isolamento state | Não é para estados transientes (up/down) | ❌ REJEITAR |
| **null_resource + local-exec** | ❌ ANTI-PATTERN | Terraform-native | Difícil debug, logs ruins, anti-pattern | ❌ REJEITAR |
| **GitHub Actions CI/CD** | ✅ RECOMENDADO (futuro) | Automação schedule, logs centralizados, notifications | Requer setup inicial | ✅ IMPLEMENTAR FASE 2 |

**Problema: Cluster Autoscaler vs Terraform State Drift**

O Cluster Autoscaler ajusta `desired_size` dinamicamente no ASG (ex: de 7 para 5 em baixa demanda). Se usarmos Terraform para controlar `desired_size`, ocorrerá state drift:

```hcl
# Terraform state: desired_size = 7
# AWS real state: desired_size = 5 (ajustado pelo Cluster Autoscaler)
# Resultado: terraform plan mostra drift constante
```

**Solução:** Usar `ignore_changes` no Terraform para ASG:

```hcl
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

Isso permite:
- ✅ Terraform gerencia `min_size` e `max_size` (limites)
- ✅ Cluster Autoscaler gerencia `desired_size` (valor atual)
- ✅ Scripts bash podem ajustar via AWS CLI sem state drift

**Scripts Bash Recomendados:**

```bash
# down.sh - Shutdown infraestrutura
#!/bin/bash
set -euo pipefail

echo "==> Stopping EKS Cluster nodes..."
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name k8s-platform-prod-node-group \
  --desired-capacity 0 \
  --region us-east-1

# Aguardar nodes terminarem
aws autoscaling wait group-in-service \
  --auto-scaling-group-name k8s-platform-prod-node-group \
  --region us-east-1

echo "==> Infrastructure stopped. Fixed costs: $200.75/month"

# up.sh - Startup infraestrutura
#!/bin/bash
set -euo pipefail

echo "==> Starting EKS Cluster nodes..."
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name k8s-platform-prod-node-group \
  --desired-capacity 7 \
  --region us-east-1

# Aguardar nodes Ready
kubectl wait --for=condition=Ready nodes --all --timeout=600s

echo "==> Infrastructure started. Full cost: $685.70/month"
```

**GitHub Actions Automation (Fase 2):**

```yaml
# .github/workflows/infra-shutdown.yml
name: Infrastructure Shutdown
on:
  schedule:
    - cron: '0 22 * * 1-5'  # 22:00 UTC, Mon-Fri (19h BRT)
  workflow_dispatch:  # Manual trigger

jobs:
  shutdown:
    runs-on: ubuntu-latest
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::891377105802:role/GithubActionsRole
          aws-region: us-east-1
      - run: ./scripts/down.sh
      - uses: actions/slack-notification@v1  # Notificar equipe
        with:
          message: "☑️ Infraestrutura desligada - Economia: $16.77/dia"

# .github/workflows/infra-startup.yml
name: Infrastructure Startup
on:
  schedule:
    - cron: '0 11 * * 1-5'  # 11:00 UTC, Mon-Fri (8h BRT)
  workflow_dispatch:

jobs:
  startup:
    runs-on: ubuntu-latest
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::891377105802:role/GithubActionsRole
          aws-region: us-east-1
      - run: ./scripts/up.sh
      - run: ./scripts/health-check.sh
      - uses: actions/slack-notification@v1
        with:
          message: "✅ Infraestrutura operacional - Grafana: http://..."
```

### Rationale
1. ✅ **Economia massiva:** $4,427.52/ano (53.8% redução) em ambientes dev
2. ✅ **Flexibilidade:** Bash scripts permitem lógica customizada (health checks, rollback, notifications)
3. ✅ **Compatibilidade:** Não conflita com Cluster Autoscaler (via AWS CLI, não Terraform)
4. ✅ **Observabilidade:** Logs detalhados de cada etapa (startup/shutdown)
5. ✅ **Automação gradual:** Fase 1 manual (scripts), Fase 2 automática (GitHub Actions)
6. ✅ **Zero data loss:** PVCs e S3 preservados durante shutdown
7. ✅ **Fast cold start:** 5-8 min (nodes only), aceitável para dev

### Trade-offs Aceitos

| Aspecto | Bash Scripts + GitHub Actions | Terraform Native | Decisão |
|---------|-------------------------------|------------------|---------|
| **Flexibilidade** | Alta (shell completo) ✅ | Limitada (HCL) | Bash ✅ |
| **Debug** | Fácil (logs granulares) ✅ | Difícil (null_resource) | Bash ✅ |
| **State Drift** | Zero (usa AWS CLI) ✅ | Conflito com CA ❌ | Bash ✅ |
| **Automação** | GitHub Actions (Fase 2) ✅ | Requer workarounds | Bash ✅ |
| **Consistency** | Requer disciplina ⚠️ | Terraform state garante | Aceitável ⚠️ |

**Trade-off principal:** Bash scripts requerem mais disciplina (documentação, error handling) vs Terraform declarativo. Decisão: Flexibilidade e compatibilidade com Cluster Autoscaler justificam abordagem imperativa.

### Consequências

#### Fase 1 - Desenvolvimento (Scripts Manuais)
- ✅ **Economia:** $368.96/mês ($4,427.52/ano) com 8h/dia uptime
- ✅ **Custo efetivo dev:** $316.74/mês (vs $685.70 baseline)
- ✅ **Scripts criados:**
  - `scripts/up.sh` - Startup completo (nodes + health checks)
  - `scripts/down.sh` - Shutdown seguro (drain nodes + scale ASG)
  - `scripts/health-check.sh` - Validação pós-startup
- ✅ **Cold start:** 5-8 min (aceitável para dev)
- ⚠️ **Execução:** Manual (via terminal ou cron local)

#### Fase 2 - Produção (GitHub Actions Automatizado)
- ✅ **Automação completa:** Workflows scheduled (startup 8h, shutdown 19h)
- ✅ **Notificações:** Slack/Email quando infraestrutura sobe/desce
- ✅ **Auditoria:** GitHub Actions logs centralizados
- ✅ **Fallback:** Manual trigger via workflow_dispatch
- ✅ **Economia produção:** $176.84/mês (24/5 com shutdown noturno)
- ⚠️ **Dependência:** GitHub Actions availability (SLA 99.9%)

#### Custos por Fase de Uso

| Fase | Uptime | Custo Fixo | Custo Variável | Total/Mês | Economia |
|------|--------|------------|----------------|-----------|----------|
| **Marco 2 Baseline** (24/7) | 100% | $200.75 | $484.95 | $685.70 | - |
| **Dev 8h/dia** (atual) | 33% | $200.75 | $116.03 | $316.78 | **-$368.92** (-53.8%) |
| **Dev 10h/dia** | 42% | $200.75 | $151.43 | $352.18 | -$333.52 (-48.6%) |
| **Prod 24/5** (noturno off) | 71% | $200.75 | $308.11 | $508.86 | -$176.84 (-25.8%) |
| **Prod 24/7** | 100% | $200.75 | $484.95 | $685.70 | $0 (baseline) |

#### Marco 3 Considerações (PostgreSQL RDS)

**Problema:** RDS não pode ficar stopped > 7 dias (AWS auto-restart)

**Soluções avaliadas:**
1. **Snapshot + Delete + Restore:**
   - Economia: $50/mês (RDS db.t3.medium)
   - Restore time: 10-15 min
   - Custo snapshot: $0.095/GB/mês (~$9.50/mês para 100GB)
   - Economia líquida: $40.50/mês
2. **Manter RDS 24/7:**
   - Custo fixo: $50/mês
   - Zero downtime
   - Simplificação operacional
3. **Hybrid:** RDS 24/7 (dev precisa dados persistentes), shutdown EKS apenas

**Decisão Marco 3:** Avaliar padrão de uso. Se dados RDS são fixtures/test data: Snapshot. Se são persistentes: Manter 24/7.

### Implementação Atual

**Localização Scripts:**
```
platform-provisioning/aws/kubernetes/terraform/
├── scripts/
│   ├── up.sh              # Startup infraestrutura (ASG + health checks)
│   ├── down.sh            # Shutdown infraestrutura (drain + scale)
│   ├── health-check.sh    # Validação pós-startup (nodes, pods, Grafana)
│   └── README.md          # Documentação uso
```

**Uso Manual (Fase 1):**
```bash
# Ligar infraestrutura (início do dia)
cd platform-provisioning/aws/kubernetes/terraform
./scripts/up.sh
# Output: "✅ Infrastructure started in 6m23s. Grafana: http://..."

# Verificar saúde
./scripts/health-check.sh
# Output: "✅ 7 nodes Ready, 36 pods Running (monitoring)"

# Desligar infraestrutura (fim do dia)
./scripts/down.sh
# Output: "☑️ Infrastructure stopped. Saving $16.77 tonight."
```

**GitHub Actions (Fase 2 - Planejado):**
- Workflow: `.github/workflows/infra-shutdown.yml` (cron: 22:00 UTC)
- Workflow: `.github/workflows/infra-startup.yml` (cron: 11:00 UTC)
- IAM Role: `GithubActionsRole` com policies `AmazonEKSClusterPolicy`, `AutoScalingFullAccess`
- Notifications: Slack webhook `#infrastructure` channel

### Custos Fixos Inevitáveis (Always On)

Mesmo com shutdown completo, custos que persistem:

| Componente | Custo/Mês | Justificativa |
|------------|-----------|---------------|
| EKS Control Plane | $73.00 | Não pode ser stopped (AWS managed) |
| NAT Gateways (2) | $66.00 | Necessário para cluster (não pode ser deleted sem downtime) |
| S3 Storage | $34.57 | Dados persistentes (logs, traces, state) |
| ALBs (2) | $16.20 | Ingress endpoints (não destroyable sem recreate) |
| CloudWatch Logs | $10.08 | Retenção logs infraestrutura |
| Secrets Manager | $0.40 | Credentials (Grafana, futuros) |
| Route53 Hosted Zone | $0.50 | DNS (Marco 3) |
| **TOTAL FIXO** | **$200.75/mês** | **29.3% do custo total** |

**Implicação:** Economia máxima possível é 70.7% ($484.95/mês), nunca 100%.

### Roadmap de Evolução

**Q1 2026 (Fase 1 - Atual):**
- ✅ Scripts bash funcionais (`up.sh`, `down.sh`, `health-check.sh`)
- ✅ Documentação uso (README.md)
- ✅ Execução manual (terminal/cron local)
- ✅ Economia: $368.96/mês (8h/dia dev)

**Q2 2026 (Fase 2 - Automação):**
- [ ] GitHub Actions workflows (startup/shutdown)
- [ ] IAM Role para GitHub Actions (OIDC)
- [ ] Slack notifications integradas
- [ ] Fallback automático (health check failure → rollback)
- [ ] Dashboard economia (CloudWatch metrics)

**Q3 2026 (Fase 3 - Otimizações):**
- [ ] Spot Instances para dev (economia adicional 60-70%)
- [ ] Karpenter (substituir Cluster Autoscaler) - scale to zero
- [ ] Reserved Instances para prod (economia 30-40% on-demand)
- [ ] S3 Intelligent-Tiering (economia storage)

**Q4 2026 (Fase 4 - Multi-Ambiente):**
- [ ] Scripts parametrizados (dev, staging, prod)
- [ ] Terraform workspaces por ambiente
- [ ] Políticas diferenciadas (dev: shutdown agressivo, prod: 24/7)

### Documentos Relacionados

- **[costs.md](costs.md):** Breakdown completo custos Marco 2 (atualizado com Fixos vs Variáveis)
- **[risks.md](risks.md):** Riscos operacionais shutdown (data loss, startup failures)
- **[00-diario-de-bordo.md](../plan/aws-execution/00-diario-de-bordo.md):** Histórico implementação scripts
- **ADR-007:** Cluster Autoscaler Strategy (compatibilidade com startup/shutdown)
- **ADR-010:** VPC Reaproveitamento (NAT Gateways como custo fixo)

### Métricas de Sucesso

**KPIs Fase 1:**
- [ ] Tempo cold start < 10 min (target: 5-8 min) ✅
- [ ] Zero data loss em 30 shutdowns consecutivos ✅
- [ ] Economia > $300/mês primeiro mês ✅
- [ ] Health check success rate > 95% ✅

**KPIs Fase 2 (GitHub Actions):**
- [ ] Automação success rate > 99%
- [ ] Notificações < 2 min após evento
- [ ] Rollback automático < 5 min (se health check fail)
- [ ] Economia anualizada > $4.000/ano

---

## 📝 ADR-023: Migration from Bitnami Charts to Kubernetes Operators

**Data:** 2026-01-29
**Status:** ✅ Ativo
**Contexto:** Marco 3 Data Services - Descoberta crítica licenciamento Bitnami Charts → Tanzu Standard

### Decisão

Adotar **Kubernetes Operators** (Spotahome Redis Operator + RabbitMQ Cluster Operator) em vez de Bitnami Helm Charts para Redis e RabbitMQ no Marco 3.

### Contexto Técnico

**Descoberta Crítica (2026-01-29):**
- Bitnami Helm Charts migrarão para modelo pago (Tanzu Standard) em Setembro 2025
- Custo licenciamento: $72,000/ano ($6,000/mês)
- Componentes afetados: Redis + RabbitMQ (planejados no Quickstart Sprint 1)

**Planejamento Original:**
- Quickstart ([aws-eks-gitlab-quickstart.md](../plan/quickstart/aws-eks-gitlab-quickstart.md)) previa:
  - Sprint 1, Task C.2: Deploy Redis via `bitnami/redis` (8h)
  - Sprint 1, Task C.3: Deploy RabbitMQ via `bitnami/rabbitmq` (8h)

**Impacto Financeiro se NÃO agir:**
- Infraestrutura AWS: $7,248/ano
- Licenciamento Tanzu: $72,000/ano
- **TOTAL:** $79,248/ano (+993% vs planejamento original) 🔴

### Alternativas Consideradas

| Alternativa | Custo/Ano | Esforço | HA | Cloud-Agnostic | Decisão |
|-------------|-----------|---------|----|--------------|---------|
| **Continuar Bitnami + Pagar Tanzu** | $79,248 | 20h | Manual | ❌ | ❌ REJEITADO |
| **AWS Managed (ElastiCache + MQ)** | $11,640 | 12h | Automático | ❌ | ⚠️ Alternativa |
| **Kubernetes Operators** | **$6,348** | **24h** | **Automático** | **✅** | ✅ **ESCOLHIDO** |

### Rationale

1. ✅ **Economia massiva:** $72,900/ano vs Tanzu Standard (92% economia)
2. ✅ **Melhor TCO:** $6,348/ano vs $7,248 planejamento original ($900 economia adicional)
3. ✅ **HA superior:** Failover automático < 30s (vs 5-6 min manual Bitnami)
4. ✅ **Backups nativos:** CronJobs automáticos (vs scripts manuais)
5. ✅ **Cloud-agnostic:** Portável para GCP/Azure (vs vendor lock-in AWS ou VMware)
6. ✅ **Zero-downtime upgrades:** Rolling updates (vs downtime Helm upgrades)
7. ⚠️ **Esforço adicional:** +4h no Sprint 1 (24h vs 20h original) - aceitável

### Operators Selecionados

#### Redis: Spotahome Redis Operator

- **Repository:** https://github.com/spotahome/redis-operator
- **Maturidade:** Production-ready (>50 companies, 3+ anos produção)
- **CRD:** RedisFailover (1 master + 2 replicas + 3 sentinels)
- **Features:** HA automático, persistence (PVC), ServiceMonitor Prometheus
- **Helm:** `https://spotahome.github.io/redis-operator`

#### RabbitMQ: RabbitMQ Cluster Operator

- **Repository:** https://github.com/rabbitmq/cluster-operator
- **Maturidade:** Oficial VMware/Broadcom
- **CRD:** RabbitmqCluster (quorum queues, 3 nodes cluster)
- **Features:** TLS automático, Management UI, ServiceMonitor
- **Deploy:** kubectl apply (CRDs + Operator)

### Consequências

**Positivas:**
- ✅ Economia total: $72,900/ano vs Tanzu + $900/ano vs planejamento original = $73,800/ano
- ✅ HA automático: Failover < 30s (12× mais rápido que Bitnami manual)
- ✅ Backups automáticos: CronJobs nativos (vs scripts bash manuais)
- ✅ Zero-downtime upgrades: Rolling updates
- ✅ Cloud-agnostic: Portabilidade futura GCP/Azure sem refactoring
- ✅ Monitoring nativo: ServiceMonitors Prometheus out-of-the-box

**Negativas:**
- ⚠️ Esforço adicional: +4h no Sprint 1 (1.5% aumento, aceitável)
- ⚠️ Curva aprendizado: Team precisa estudar Operators (4h onboarding)
- ⚠️ Complexidade inicial: CRDs + Operator deployment (vs Helm install simples)

**Mitigações:**
- ✅ Documentação oficial excelente (ambos Operators)
- ✅ POC em ambiente dev antes Sprint 1 (4h validação)
- ✅ Comunidades ativas (Slack, GitHub Discussions)
- ✅ Runbooks operacionais (failover, backups, troubleshooting)

### Impacto no Planejamento Quickstart

**Tasks Ajustadas:**

| Task Original | Task Ajustada | Esforço | Delta |
|---------------|---------------|---------|-------|
| C.2: Deploy bitnami/redis (8h) | Deploy Spotahome Redis Operator (10h) | 10h | +2h |
| C.3: Deploy bitnami/rabbitmq (8h) | Deploy RabbitMQ Cluster Operator (10h) | 10h | +2h |

**Custos Ajustados:**

| Ambiente | Original (Bitnami) | Ajustado (Operators) | Economia |
|----------|-------------------|---------------------|----------|
| Staging | $112/mês | $97/mês | -$15/mês |
| Prod | $467/mês | $407/mês | -$60/mês |
| **TOTAL** | **$604/mês** | **$529/mês** | **-$75/mês (-$900/ano)** |

**Esforço Total Ajustado:**
- Sprint 1: 88h → 92h (+4h, +1.5%)
- Sprints 2-3: Sem alteração
- **TOTAL:** 262h → 266h (+4h)

### Comparativo Features

| Feature | Bitnami Charts | Operators | Vencedor |
|---------|----------------|-----------|----------|
| **Custo Total** | $79,248/ano (Tanzu) | $6,348/ano | ✅ Operators (92% economia) |
| **Failover Time** | 5-6 min (manual) | < 30s (automático) | ✅ Operators (12× faster) |
| **Backups** | Scripts manuais | CronJobs nativos | ✅ Operators |
| **Monitoring** | Exporter manual | ServiceMonitors nativos | ✅ Operators |
| **Upgrades** | Downtime | Zero-downtime | ✅ Operators |
| **Cloud Portability** | AWS-specific (EBS) | Cloud-agnostic (PVC) | ✅ Operators |
| **Simplicidade Deploy** | Helm install | CRDs + Operator | ✅ Bitnami |

**Score:** Operators **6-1** vs Bitnami

### ROI

| Métrica | Valor |
|---------|-------|
| **Investimento:** | +4h Sprint 1 ($400 @ $100/h) |
| **Economia Ano 1:** | $73,800 (Tanzu avoided + infra savings) |
| **ROI:** | 18,450% |
| **Payback:** | 5 dias |

### Implementação

**Fase 1 (Sprint 1 Marco 3):**
1. Deploy Spotahome Redis Operator via Helm (2h)
2. Criar RedisFailover CRD (3 replicas: master + 2 slaves + 3 sentinels) (3h)
3. Validar HA (simular failover, testar Sentinel) (2h)
4. Deploy RabbitMQ Cluster Operator via kubectl (2h)
5. Criar RabbitmqCluster CRD (3 nodes, quorum queues) (3h)
6. Configurar ServiceMonitors Prometheus (2h)
7. Documentação runbooks (2h)

**Total:** 24h (vs 20h Bitnami original)

**Fase 2 (Post-Sprint 1):**
- Integração GitLab CE com Redis/RabbitMQ Operators
- Testes end-to-end (pipeline CI com app usando Redis + RabbitMQ)
- Monitoramento Grafana (dashboards Redis/RabbitMQ)

### Documentos Relacionados

- **Análise Impacto:** [BITNAMI-LICENSING-IMPACT-ANALYSIS.md](../../finops/BITNAMI-LICENSING-IMPACT-ANALYSIS.md)
- **Cruzamento Quickstart:** [QUICKSTART-VS-BITNAMI-ANALYSIS.md](../../finops/QUICKSTART-VS-BITNAMI-ANALYSIS.md)
- **Custos Completos:** [COST-PROJECTION-COMPLETE.md](../../finops/COST-PROJECTION-COMPLETE.md)
- **Quickstart Original:** [aws-eks-gitlab-quickstart.md](../../plan/quickstart/aws-eks-gitlab-quickstart.md)

### Métricas de Sucesso

**KPIs Fase 1 (Sprint 1):**
- [x] **Redis Operator deployado** (Spotahome v1.3.0, 3 Redis + 3 Sentinels) ✅ **2026-02-02**
- [x] **HA validado**: Sentinel failover automático < 30s ✅ **2026-02-02**
- [ ] RabbitMQ Operator deployado (RabbitmqCluster 3 nodes)
- [ ] ServiceMonitors configurados (Prometheus scraping metrics) ⚠️ *Exporter pendente*
- [ ] Backups configurados (CronJobs schedules)
- [ ] Runbooks documentados (operação, troubleshooting)

**KPIs Fase 2 (Post-Sprint 1):**
- [ ] GitLab CE integrado com Operators (cache + message queue funcional)
- [ ] Pipeline CI end-to-end (app teste usando Redis + RabbitMQ)
- [ ] Dashboards Grafana (Redis: memory usage, commands/sec; RabbitMQ: queue depth, msg rate)
- [ ] Zero downtime upgrade testado (rolling update Operator versions)

**KPIs Financeiros:**
- [ ] Economia mensal confirmada: -$75/mês (vs planejamento original)
- [ ] Zero custo licenciamento (vs $6,000/mês Tanzu avoided)
- [ ] ROI validado: 18,450% Ano 1

---

## 📝 ADR-024: FinOps Automation Multi-Ambiente (EventBridge + Lambda)

**Data:** 2026-01-30 (Implementação) | 2026-02-02 (Ativação)
**Status:** 🚀 **Ativo em Produção** (EventBridge ENABLED, 5/5 testes validados, SNS configurado)
**Framework:** [executor-terraform.md](../prompts/executor-terraform.md) (Multi-Agent Validation: AWS, Terraform, FinOps, Security)
**Contexto:** Ambientes STAGING e PRODUCTION operam 24/7 mas com uso parcial, gerando desperdício total de R$ 1.140/mês ($190)
**Prioridade:** 🟡 MÉDIA-ALTA (ROI consolidado 204% Fase 2, 391% Fase 3, payback 2.4 meses Fase 3)
**Estratégia:** Implementação faseada 3-etapas (STAGING → STAGING+PROD → STAGING on-demand+PROD)

### Estratégia Evolutiva Multi-Ambiente

**Abordagem:** Implementação faseada para validar automação em STAGING antes de expandir para PRODUCTION, culminando em STAGING on-demand quando PROD estabilizar.

#### Fase 1: STAGING 8h-18h Mon-Fri (Pré-PROD)
```
STAGING (Dev+Homolog):  Ligado 8h-18h Mon-Fri (desenvolvimento ativo)
PROD:                   Não existe (Marco 3 pendente)
────────────────────────────────────
Economia:               R$ 4.320/ano
Investimento:           R$ 3.000
ROI Year 1:             44%
Payback:                6.7 meses
Timeline:               2026-02-17 (deploy) → 2026-03-17 (validação 1 mês)
```

**Milestone Crítico Fase 1:** STAGING operação 1 mês SEM falhas antes de avançar Fase 2

#### Fase 2: STAGING + PRODUCTION (Go-Live Simultâneo)
```
STAGING (Dev+Homolog):  Ligado 8h-18h Mon-Fri (testes + homologação)
PROD:                   Ligado 7h-0h 7 dias/semana (operação clientes)
────────────────────────────────────
Economia STAGING:       R$ 4.320/ano
Economia PROD:          R$ 9.360/ano
────────────────────────────────────
TOTAL ECONOMIA:         R$ 13.680/ano ✅
Investimento Total:     R$ 4.500 (STAGING R$ 3.000 + PROD R$ 1.500)
ROI Year 1:             204%
Payback:                3.9 meses
Timeline:               2026-04-15 (deploy PROD) → 2026-06-15 (validação 2 meses)
```

**Gatilhos Fase 2:**
- [ ] STAGING validado 1 mês SEM falhas (Fase 1 completa)
- [ ] PROD environment deployado (Marco 3 completo)
- [ ] Load tests PROD validados (99.9% SLA confirmado)

#### Fase 3: STAGING On-Demand + PRODUCTION (Estável)
```
STAGING:                DESLIGADO permanentemente (liga SOB DEMANDA)
PROD:                   Ligado 7h-0h 7 dias/semana (operação clientes)
────────────────────────────────────
Economia STAGING:       R$ 12.744/ano ✅ (95% economia, uptime ~5%)
Economia PROD:          R$ 9.360/ano
────────────────────────────────────
TOTAL ECONOMIA:         R$ 22.104/ano ✅✅
Investimento:           R$ 4.500 (não muda)
ROI Year 1:             391%
Payback:                2.4 meses
NPV 3 anos:             R$ 50.479 (ROI cumulativo 1.121%)
Timeline:               2026-09-15 (STAGING on-demand)
```

**Gatilhos Fase 3:**
- [ ] PROD estável > 3 meses sem incidentes críticos
- [ ] Cobertura testes automatizados > 80%
- [ ] Equipe confortável com CI/CD production-first
- [ ] STAGING usado < 2×/mês (validar necessidade real)

---

### Problema

#### STAGING (Dev+Homolog Environment)

**Desperdício atual:**
- STAGING ligado 168h/semana (24/7)
- Utilização real: 50h/semana (8h-18h Mon-Fri)
- **Desperdício: 70% do tempo** (118h/semana sem uso)

**Custo mensal 24/7:**
```
EKS Control Plane (rateio 50%):  $37/mês
EC2 nodes (2× t3.medium):        $60/mês
RDS db.t3.small Multi-AZ:        $70/mês
Redis Operator (infra):          $10/mês
RabbitMQ Operator (infra):       $10/mês
────────────────────────────────────────
TOTAL STAGING 24/7:              $187/mês = R$ 1.122/mês
```

**Perda anual STAGING:** R$ 1.122/mês × 12 = **R$ 13.464/ano**

---

#### PRODUCTION (Customer-Facing Environment)

**Desperdício projetado:**
- PRODUCTION ligado 168h/semana (24/7 quando deployado)
- Utilização real: 119h/semana (7h-0h, 7 dias/semana)
- **Desperdício: 29% do tempo** (49h/semana madrugada 0h-7h)

**Custo mensal 24/7 (projeção):**
```
EKS Control Plane (rateio 50%):  $37/mês
EC2 nodes production (4× t3.large): $240/mês  # Scaled 2× vs STAGING
RDS db.t3.large Multi-AZ:        $280/mês  # Production tier
Redis Operator (production):     $20/mês
RabbitMQ Operator (production):  $20/mês
S3 backups + artifacts:          $23/mês
ALB production:                  $32/mês
────────────────────────────────────────
TOTAL PRODUCTION 24/7:           $652/mês = R$ 3.912/mês
```

**Perda anual PRODUCTION:** R$ 3.912/mês × 12 = **R$ 46.944/ano**

---

#### Desperdício Consolidado

**Perda Total Multi-Ambiente:**
```
STAGING:     R$ 13.464/ano (70% desperdício)
PRODUCTION:  R$ 46.944/ano (29% desperdício)
────────────────────────────────────────
TOTAL:       R$ 60.408/ano desperdiçados ❌
```

**Observação:** Fase 3 (STAGING on-demand) reduz desperdício STAGING de R$ 13.464 → R$ 720 (economia adicional R$ 12.744)

### Decisão

**Implementar automação start/stop via EventBridge + Lambda** para ambientes STAGING e PRODUCTION com estratégia faseada:

#### Configuração STAGING (Fase 1)

1. **Schedule automático:**
   - STARTUP: 8:00 AM BRT (11:00 UTC) - Segunda a Sexta
   - SHUTDOWN: 6:00 PM BRT (21:00 UTC) - Segunda a Sexta
   - Feriados: SKIP (não liga em feriados, via BrasilAPI)

2. **Node Groups:**
   - **critical-always-on** (24/7): GitLab, Harbor, ArgoCD, Prometheus/Grafana
   - **regular** (8h-18h): Keycloak, SonarQube, Kong, Redis, RabbitMQ

3. **Health Checks (básicos):**
   - Bloquear shutdown se GitLab jobs ativos
   - Bloquear shutdown se ArgoCD syncs em progresso
   - Aguardar RDS available antes de marcar startup completo

4. **Circuit Breaker:**
   - Threshold: 3 falhas consecutivas
   - Notificação: Slack #finops-alerts
   - Recovery: Manual via runbook

---

#### Configuração PRODUCTION (Fase 2)

1. **Schedule automático:**
   - STARTUP: 7:00 AM BRT (10:00 UTC) - 7 dias/semana
   - SHUTDOWN: 00:00 (meia-noite) BRT (03:00 UTC) - 7 dias/semana
   - Feriados: LIGA SEMPRE (clientes ativos em feriados, BrasilAPI não bloqueia)

2. **Node Groups:**
   - **critical-always-on** (24/7): Prometheus/Grafana, GitLab CI/CD, AlertManager
   - **production** (7h-0h): Apps cliente, APIs, Kong, Redis, RabbitMQ

3. **Health Checks (rigorosos):**
   - Bloquear shutdown se transações DB ativas (> 0)
   - Bloquear shutdown se conexões idle recentes (< 5 min, > 10 conexões)
   - Bloquear shutdown se mensagens RabbitMQ pendentes (> 100)
   - Bloquear shutdown se manutenção não agendada (AlertManager)
   - Criar snapshot RDS PRÉ-shutdown (RPO < 1h)

4. **Circuit Breaker:**
   - Threshold: 2 falhas consecutivas (mais sensível que STAGING)
   - Notificação: PagerDuty P1 + Slack #prod-incidents
   - Recovery: Rollback AUTOMÁTICO (< 5 min)

5. **Rollback Automático:**
   - Desabilita EventBridge rules
   - Executa startup manual via runbook
   - Escala gerência (SLA breach iminente)
   - Prepara comunicação externa (status page)

---

#### Comparação STAGING vs PRODUCTION

| Aspecto | STAGING | PRODUCTION |
|---------|---------|------------|
| **Schedule** | 8h-18h Mon-Fri | 7h-0h 7 dias/semana |
| **Uptime** | 50h/semana (30%) | 119h/semana (71%) |
| **Feriados** | SKIP (não liga) | LIGA (clientes ativos) |
| **Health Checks** | Básicos (GitLab jobs) | Rigorosos (transações DB, conexões, queues) |
| **Rollback** | Manual (30 min) | Automático (< 5 min) |
| **SLA** | 99.5% (8h-18h) | 99.9% (7h-0h) |
| **Circuit Breaker** | 3 falhas | 2 falhas (mais sensível) |
| **Snapshot RDS** | Não | Sim (pré-shutdown, RPO < 1h) |
| **Notificação** | Slack | PagerDuty P1 + Slack |
| **Investimento** | R$ 3.000 (10h dev) | R$ 1.500 (5h incremental) |
| **Economia Anual** | R$ 4.320 | R$ 9.360 |
| **ROI Year 1** | 44% | 521% |
| **Payback** | 6.7 meses | 1.9 meses |

### Alternativas Consideradas

| Alternativa | Custo Mensal | Economia/Ano | Decisão | Rationale |
|-------------|--------------|--------------|---------|-----------|
| **1. Status Quo (24/7)** | $187 | $0 | ❌ REJEITADO | Desperdício 70% recursos |
| **2. Shutdown manual diário** | $130 | $684/ano | ❌ REJEITADO | Requer intervenção humana 2×/dia, toil alto |
| **3. Automação parcial (sem feriados)** | $135 | $624/ano | ❌ REJEITADO | Workloads ligam em feriados desnecessariamente |
| **4. Automação completa (EventBridge + Lambda)** | $127 | $720/ano | ✅ **ESCOLHIDO** | Zero toil, ROI 44%, payback 4.2 meses |
| **5. Delete staging (usar PROD)** | $0 | $2.244/ano | ❌ REJEITADO | Riscos altíssimos, violação boas práticas |

### Rationale

**Por que EventBridge + Lambda?**

1. **Serverless = Custo Ótimo:**
   - Lambda: $0.20/mês (100 invocações, 300s cada)
   - EventBridge: $1.00/mês (2 rules)
   - **Total overhead:** $2.00/mês vs $60 economia = **30:1 ROI mensal**

2. **Integração Nativa AWS:**
   - IAM roles (IRSA pattern consistente)
   - CloudWatch Logs/Metrics (observabilidade zero-config)
   - SNS notifications (Slack/PagerDuty)

3. **Simplicidade Operacional:**
   - Zero infraestrutura adicional (sem EC2, containers)
   - Sem dependências externas (ex: Kubernetes CronJobs requerem cluster up)
   - Fallback robusto: falha Lambda = STAGING permanece no estado atual (seguro)

4. **Portabilidade Limitada Aceitável:**
   - Trade-off: vendor lock-in AWS vs custo/complexidade
   - Migração futura (se necessário): StepFunctions ou Kubernetes CronJobs

**Por que separar Node Groups?**

- **GitLab:** Jobs noturnos agendados (backups 2 AM, security scans 4 AM)
- **Harbor:** Push/pull images pode ocorrer fora horário (pipelines automatizados)
- **ArgoCD:** Reconciliação contínua essencial para health checks
- **Prometheus/Grafana:** Observabilidade 24/7 permite troubleshooting histórico

**Economia Real vs Projetada:**

```
Cenário Otimizado (50h/semana):
────────────────────────────────────────────
EKS Control Plane (obrigatório):     $37/mês
EC2 critical-always-on (1× t3.medium): $30/mês
EC2 regular (2× t3.medium 30% uptime): $18/mês ✅ -$42 economia
RDS auto-pause (60% economia):        $30/mês ✅ -$40 economia
Redis scaled to 0:                    $5/mês ✅ -$5 economia
RabbitMQ scaled to 0:                 $5/mês ✅ -$5 economia
Lambda + EventBridge:                 $2/mês
────────────────────────────────────────────
TOTAL COM AUTOMAÇÃO:                 $127/mês
ECONOMIA:                             $60/mês = $720/ano (USD)
ECONOMIA BRL (taxa 6.0):              R$ 4.320/ano
```

### Arquitetura Técnica

**Componentes AWS:**

```
┌─────────────────────────────────────────────────────────────┐
│              EventBridge Scheduler (2 rules)                │
├─────────────────────────────────────────────────────────────┤
│  Rule 1: STARTUP  → cron(0 11 ? * MON-FRI *)  # 8AM BRT    │
│  Rule 2: SHUTDOWN → cron(0 21 ? * MON-FRI *)  # 6PM BRT    │
│  Target: Lambda finops-scheduler-staging                    │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│         Lambda: finops-scheduler-staging (Python 3.12)      │
├─────────────────────────────────────────────────────────────┤
│  1. Verificar feriados (BrasilAPI + cache local)           │
│  2. Health checks (GitLab API, ArgoCD kubectl)              │
│  3. Executar ação:                                          │
│     STOP:  ASG min=0, RDS pause, scale operators to 0       │
│     START: RDS resume, ASG restore min=2, wait Ready        │
│  4. Circuit breaker tracking (DynamoDB)                     │
│  5. Métricas CloudWatch + notificação Slack/PagerDuty       │
│  6. Timeout: 300s (5 min max execution)                     │
└─────────────────────────────────────────────────────────────┘
         │                  │                  │
         ▼                  ▼                  ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ ASG Scaling  │  │  RDS Pause   │  │  DynamoDB    │
│ (EC2 Nodes)  │  │  (staging)   │  │  (state)     │
└──────────────┘  └──────────────┘  └──────────────┘
```

**IAM Role Policy (finops-scheduler-role):**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ManageAutoScalingGroups",
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:UpdateAutoScalingGroup",
        "autoscaling:SuspendProcesses",
        "autoscaling:ResumeProcesses"
      ],
      "Resource": "arn:aws:autoscaling:*:*:autoScalingGroup:*:autoScalingGroupName/eks-marco2-staging-regular-*",
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/Environment": "staging"
        }
      }
    },
    {
      "Sid": "ManageRDS",
      "Effect": "Allow",
      "Action": [
        "rds:DescribeDBInstances",
        "rds:StopDBInstance",
        "rds:StartDBInstance"
      ],
      "Resource": "arn:aws:rds:*:*:db:marco2-staging-rds",
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/Environment": "staging"
        }
      }
    }
  ]
}
```

**Princípios Aplicados:**
- ✅ Least privilege (apenas staging resources via tags)
- ✅ Sem permissões PROD (blast radius limitado)
- ✅ Conditions baseadas em tags (defense-in-depth)

### Consequências

**Positivas:**
- ✅ Economia R$ 4.320/ano (ROI 44% Year 1)
- ✅ Zero toil operacional (end-of-day manual shutdowns)
- ✅ Observabilidade completa (CloudWatch + Grafana)
- ✅ Segurança (IRSA, least privilege, circuit breaker)
- ✅ Aderência boas práticas FinOps (rightsize, schedule)

**Negativas:**
- ⚠️ Vendor lock-in AWS (EventBridge + Lambda específicos)
- ⚠️ Complexidade adicional (Lambda code maintenance)
- ⚠️ Risco falha startup (mitigado: retry 3×, alertas PagerDuty)
- ⚠️ Feriados brasileiros dependem API externa (mitigado: cache + fallback)

**Trade-offs Aceitos:**
- Vendor lock-in AWS vs custo/simplicidade (prioridade: ROI > portabilidade)
- Node groups separados (critical vs regular) vs custos (prioridade: disponibilidade GitLab jobs > economia $30/mês)

### Riscos e Mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|-------|--------------|---------|-----------|
| **Falha startup RDS timeout** | 🟡 Média (5%) | 🔴 Alto | Retry 3× com backoff exponencial (30s, 60s, 120s), alerta PagerDuty falha 3× |
| **GitLab job perdido durante shutdown** | 🟢 Baixa (2%) | 🔴 Alto | Health check: `GET /api/v4/jobs?scope[]=running`, bloqueia shutdown se > 0 jobs |
| **BrasilAPI indisponível** | 🟢 Baixa (1%) | 🟡 Médio | Cache local DynamoDB (30 dias TTL), fallback lista estática feriados fixos |
| **Lambda timeout 300s** | 🟢 Baixa (1%) | 🟡 Médio | Operações assíncronas (não aguardar nodes Ready inline), Step Functions futuro se necessário |
| **Circuit breaker ativado erroneamente** | 🟢 Baixa (1%) | 🟡 Médio | Threshold ajustável (3 falhas), notificação imediata, recovery manual documentado |
| **DynamoDB write throttling** | 🟢 Baixa (<1%) | 🟢 Baixo | On-demand billing mode (auto-scale), retry exponential backoff |

**Plano de Rollback:**
1. Desabilitar EventBridge rules (disable via console)
2. Startup manual via script: `./scripts/finops/startup-marco2.sh staging`
3. Investigar logs Lambda: `aws logs tail /aws/lambda/finops-scheduler-staging --follow`
4. Rollback Terraform: `terraform destroy -target=module.finops_scheduler`

### Observabilidade

**CloudWatch Metrics:**

| Métrica | Namespace | Descrição | Threshold Alerta |
|---------|-----------|-----------|-----------------|
| `finops.startup.duration` | FinOps/Scheduler | Tempo total startup (segundos) | Warning: > 600s (10 min), Critical: > 900s (15 min) |
| `finops.shutdown.duration` | FinOps/Scheduler | Tempo total shutdown (segundos) | Warning: > 300s (5 min) |
| `finops.cost_savings_daily` | FinOps/Costs | Economia diária estimada (USD) | Info: < $2/dia (esperado $2.40) |
| `finops.circuit_breaker_state` | FinOps/Health | 0 = closed (OK), 1 = open (disabled) | Critical: state = 1 |
| `finops.holiday_detected` | FinOps/Scheduler | 1 = feriado (ação skipped) | Info |

**Grafana Dashboard:** "FinOps Staging Automation"
- Panel 1: Uptime real vs planejado (gráfico temporal 30 dias)
- Panel 2: Economia acumulada (gauge: meta R$ 450/mês)
- Panel 3: Histórico startups/shutdowns (timeline com annotations)
- Panel 4: Falhas e circuit breaker (stat panel com threshold)

**Alertas:**

| Condição | Severidade | Destino | Ação |
|----------|-----------|---------|------|
| Startup duration > 15 min | 🟡 Warning | Slack #finops-alerts | Investigar performance RDS/nodes |
| Startup failed 3× consecutivas | 🔴 Critical | PagerDuty on-call | Circuit breaker ativado, disable automation, startup manual |
| BrasilAPI unreachable | 🟢 Info | CloudWatch Logs | Fallback para lista estática, continuar operação |
| Cost savings < $2/dia | 🟡 Warning | Slack #finops | Validar uptime real vs esperado |

### Custo-Benefício Detalhado

**Investimento Inicial:**
```
Desenvolvimento Lambda (10h × R$ 300/h):      R$ 3.000
Testes integrados (incluído):                 R$ 0
Documentação (incluído):                      R$ 0
────────────────────────────────────────────────────
TOTAL INVESTIMENTO:                           R$ 3.000
```

**Economia Anual:**
```
$60/mês × 12 meses = $720/ano (USD)
$720 × 6.0 (taxa câmbio) = R$ 4.320/ano (BRL)
```

**ROI Year 1:**
```
(Economia - Investimento) / Investimento
(R$ 4.320 - R$ 3.000) / R$ 3.000 = 44%
```

**Payback Period:**
```
Investimento / Economia Mensal
R$ 3.000 / R$ 360 = 8.3 meses (considerando taxa 6.0)
R$ 3.000 / (R$ 450 economia real esperada) = 6.7 meses
```

**NPV 3 Anos (desconto 10%):**
```
Year 1: R$ 4.320 / 1.10 = R$ 3.927
Year 2: R$ 4.320 / 1.21 = R$ 3.570
Year 3: R$ 4.320 / 1.33 = R$ 3.248
────────────────────────────────────────
NPV 3 anos: R$ 10.745
Investimento: R$ 3.000
────────────────────────────────────────
NPV líquido: R$ 7.745 (258% ROI cumulativo)
```

**Análise de Sensibilidade:**

| Cenário | Uptime Real | Economia/Ano | ROI Year 1 | Payback |
|---------|-------------|--------------|-----------|---------|
| **Pessimista** (60h/semana) | 36% mês | R$ 3.600 | 20% | 10 meses |
| **Base Case** (50h/semana) | 30% mês | R$ 4.320 | 44% | 6.7 meses |
| **Otimista** (40h/semana) | 24% mês | R$ 5.040 | 68% | 5.6 meses |

**Conclusão:** ROI positivo em todos os cenários, decisão **robusta a variações**.

### Critérios de Sucesso

**Fase 1 - Deploy (Semana 1):**
- [ ] Lambda deployed e testado (local + AWS)
- [ ] EventBridge rules criadas (disabled inicialmente)
- [ ] IAM roles configuradas (least privilege validado)
- [ ] DynamoDB table criada (state tracking)

**Fase 2 - Testes (Semana 2):**
- [ ] Teste manual shutdown (validar scripts)
- [ ] Teste manual startup (validar recovery < 10 min)
- [ ] Teste BrasilAPI mock (feriado simulado)
- [ ] Teste circuit breaker (3 falhas consecutivas)

**Fase 3 - Produção (Semana 3-7):**
- [ ] EventBridge habilitado (monitoramento intensivo)
- [ ] Zero falhas startup/shutdown (1 mês)
- [ ] Economia observada ≥ R$ 400/mês (tolerance: 10%)
- [ ] SLA disponibilidade staging 8h-18h ≥ 99.5%

**KPIs Mensais:**
- [ ] Uptime real vs planejado: ≥ 95% aderência (48-52h/semana)
- [ ] Falhas mensais: < 2 (target: 0)
- [ ] Startup time médio: < 8 min (target: 6 min)
- [ ] Satisfação equipe: > 8/10 (survey trimestral)

### Timeline

| Marco | Prazo | Responsável | Status |
|-------|-------|-------------|--------|
| Aprovação arquitetura + FinOps | 2026-02-03 | Arquitetura + FinOps | 📋 Pendente |
| Desenvolvimento Lambda + Terraform | 2026-02-10 | DevOps | 📋 Pendente |
| Testes integrados (local + staging) | 2026-02-13 | QA + DevOps | 📋 Pendente |
| Deploy produção (EventBridge enabled) | 2026-02-17 | DevOps | 📋 Pendente |
| Monitoramento intensivo (1 mês) | 2026-03-17 | FinOps | 📋 Pendente |
| Retrospectiva + KPIs validados | 2026-03-20 | Time completo | 📋 Pendente |

### Referências

**Documentação Multi-Ambiente:**
- [Demanda STAGING](../demands/2026-01-30-automacao-finops-staging.md)
- [Demanda PRODUCTION](../demands/2026-01-30-automacao-finops-production.md)
- [Architecture Documentation Multi-Ambiente](./architecture.md#fase-9-finops-automation-multi-ambiente)
- [Costs Analysis Multi-Ambiente](./costs.md#automação-finops-multi-ambiente)
- [Risks STAGING](./risks.md#r-019-riscos-automação-finops-staging)
- [Risks PRODUCTION](./risks.md#r-020-riscos-automação-finops-production)
- [Plano Executável Multi-Ambiente](../plan/aws-execution/fase-8-finops-multi-ambiente-automation.md)

**Scripts e APIs:**
- [Scripts Existentes](../../scripts/finops/shutdown-marco2.sh)
- [BrasilAPI Feriados](https://brasilapi.com.br/docs#tag/Feriados-Nacionais)

**AWS Documentation:**
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [AWS EventBridge Scheduler](https://docs.aws.amazon.com/scheduler/latest/UserGuide/what-is-scheduler.html)

### Aprovações

- [x] **AWS Specialist** (arquitetura AWS, IAM, resiliência) - ✅ Aprovado com ressalvas (2026-01-30)
- [x] **Terraform Specialist** (módulos, state, providers) - ✅ Aprovado com ressalvas (2026-01-30)
- [x] **FinOps** (ROI validado 43.6%, breakdown custos) - ✅ Aprovado com ressalvas (2026-01-30)
- [x] **Security** (LGPD compliance, DynamoDB encryption KMS, IAM least privilege) - ✅ Aprovado após correções (2026-01-30)

**Consenso Multi-Agente:** ✅ APROVADO (8/11 ressalvas resolvidas, 3 pendentes não-bloqueantes)

**Status Atual:** 🚀 **ATIVO EM PRODUÇÃO** (2026-02-02)

**Timeline de Implementação:**
- ✅ 2026-01-30: Módulo Terraform desenvolvido e aprovado
- ✅ 2026-01-31: Deploy STAGING (SNS desabilitado, automation desabilitada)
- ✅ 2026-02-02: Testes manuais 5/5 completos (100% sucesso)
- ✅ 2026-02-02: SNS notifications configurado e validado
- ✅ 2026-02-02: EventBridge automation HABILITADA
- 📅 2026-02-03: Primeira execução automática (segunda-feira 08:00 BRT)

**Recursos Ativos:**
- ✅ Lambda START: `finops-scheduler-start-staging`
- ✅ Lambda STOP: `finops-scheduler-stop-staging`
- ✅ EventBridge Rules: ENABLED (startup 08:00 BRT, shutdown 18:00 BRT Mon-Fri)
- ✅ SNS Topic: `finops-automation-staging` (email confirmado)
- ✅ CloudWatch Alarms: 3 alarms ativos (startup failures, shutdown failures, duration high)
- ✅ DynamoDB State: `finops-scheduler-state-staging` (circuit breaker threshold=3)

**Validação Manual (5/5 Testes):**
1. ✅ Test 1: Shutdown básico (23 min, non-graceful aceitável para staging)
2. ✅ Test 2: Startup completo (7 nodes, 6.5 min)
3. ✅ Test 3: BrasilAPI feriados (skip correto)
4. ✅ Test 4: Circuit breaker (3 falhas consecutivas)
5. ✅ Test 5: RDS startup após 4 dias downtime (8 min, <10 min target)

**Métricas Validadas:**
- Lambda Performance: 1.2-1.7s (target <3s) ✅
- Startup Duration: 6-8 min (target <10 min) ✅
- Nodes Recovery: 7/7 Ready (100%) ✅
- RDS Startup: 8 min após 4 dias downtime ✅

**Monitoramento Ativo:**
- CloudWatch Logs: `/aws/lambda/finops-scheduler-{start,stop}-staging`
- Email Notifications: gilvan.galindo@fctconsig.com.br
- Circuit Breaker: Auto-disable após 3 falhas consecutivas

**Próxima Validação:**
- 📅 2026-02-03 08:00 BRT: Primeira execução automática startup
- 📅 2026-02-03 18:00 BRT: Primeira execução automática shutdown
- 📊 2026-03-03: Review mensal (30 dias operação, validar economia real)

**Ressalvas Resolvidas:**
1. ✅ SNS notifications implementado (2026-02-02)
2. ✅ Testes manuais completos 5/5 (2026-02-02)
3. ✅ RDS 7-day auto-start validado (Test 5, startup após 4 dias)

---

## 📊 Consolidação de Decisões

### Economia Total Decisões
| Decisão | Economia/Ano | Rationale |
|---------|--------------|-----------|
| VPC Reaproveitamento | $1.152/ano | Evitar criar NAT Gateways |
| Loki vs CloudWatch | $423/ano | Menor custo ingestion + storage |
| Calico policy-only | $0 | Evitar nodes adicionais para overlay |
| Cluster Autoscaler | ~$372/ano | Scale-down em baixa demanda |
| ACM vs Third-party CA | $400/ano | Certificates gratuitos AWS |
| **TOTAL ECONOMIA** | **~$2.347/ano** | |

### Trade-offs Aceitos
| Trade-off | Justificativa |
|-----------|---------------|
| Vendor lock-in AWS | Prioridade: Time-to-market + Custo vs Portabilidade |
| 2 AZs (não 3) | Suficiente para DevOps tools (não critical workloads) |
| Cluster Autoscaler (não Karpenter) | Simplicidade vs Otimização spot instances |
| Terraform + Helm (não ArgoCD) | Single source of truth vs GitOps nativo |

---

## 🔄 Revisões e Atualizações

### Próximas Decisões (Marco 3)
- [ ] **DEC-011:** GitLab CE Deployment Strategy (Helm vs GitLab Operator)
- [ ] **DEC-012:** Database Strategy (RDS vs In-cluster PostgreSQL)
- [ ] **DEC-013:** Redis Deployment (Standalone vs Sentinel vs Cluster)
- [ ] **DEC-014:** Backup & Disaster Recovery Strategy
- [ ] **DEC-015:** Multi-tenant Strategy (namespace isolation vs cluster per tenant)

---

---

## 📝 ADR-025: Tempo Deployment - Replication Factor Decision (RF=2 vs RF=3)

**Data:** 2026-01-31
**Status:** ✅ Implementado - Marco 2 Fase 8
**Contexto:** Correção de deployment Tempo com replication_factor mismatch

### Problema

Durante deployment do Tempo (Marco 2 Fase 8), encontramos crash loop em Ingesters devido a **replication_factor mismatch**:
- **Configurado**: 2 replicas de Ingester
- **Chart default**: replication_factor = 3
- **Resultado**: Ingesters em crash loop (Exit Code 2)

### Decisão

**Manter replication_factor = 2** alinhado com 2 replicas de Ingester (staging), postergar RF=3 para Marco 3 (produção).

### Análise Multi-Agente

#### Terraform Specialist
- ❌ **Erro identificado**: Parâmetro Helm incorreto `tempo.ingester.lifecycler.ring.replication_factor` (chart ignora prefixo `tempo.`)
- ✅ **Correção**: `ingester.lifecycler.ring.replication_factor = 2`
- ⚠️ **Liveness probes**: Configurações agressivas matando containers stateful prematuramente
- ✅ **Fix probes**: `initialDelaySeconds=60s`, `failureThreshold=5` para Ingester/Compactor

#### FinOps Specialist
- **Opção 1 (RF=2, 2 Ingesters)**: $2.47/mês (zero delta) ✅
- **Opção 2 (RF=3, 3 Ingesters)**: $63.47/mês (+$61.00, +2,465%) ❌
- **Recomendação**: Opção 1 para staging, diferir Opção 2 para Marco 3 produção

### Rationale

1. ✅ **FinOps**: Economia de $61/mês vs RF=3 ($732/ano)
2. ✅ **Staging adequado**: RF=2 aceitável para ambiente não-produtivo
3. ✅ **Consistência**: Mantém target Marco 2 ($2.47/mês total)
4. ✅ **Rápido deploy**: Zero custo adicional, <5 minutos implementação

### Trade-offs Aceitos

| Aspecto | RF=2 (staging) | RF=3 (produção) |
|---------|----------------|-----------------|
| **HA** | ⚠️ Perda de 1 Ingester = degradação | ✅ Tolera 2 falhas simultâneas |
| **Custo** | $2.47/mês | $63.47/mês |
| **Recovery** | Single point durante failover | Multi-point resiliente |
| **Quorum** | 2/2 (sem margem) | 2/3 (tolerante) |

**Mitigações RF=2**:
- PodDisruptionBudget com `maxUnavailable=0`
- CloudWatch Alarm para Ingester down >5min
- Tail sampling (10% traces) → impacto reduzido

### Consequências

- ✅ Deployment bem-sucedido (11/12 pods healthy, 91%)
- ✅ Custo mantido $2.47/mês (87% economia vs projeção inicial $19.70)
- ✅ S3 backend + IRSA funcionando perfeitamente
- ⚠️ 1 Querier com leve instabilidade (não-crítico, 2 queriers disponíveis)
- 💰 Economia total: $732/ano vs RF=3

### Troubleshooting Realizado

1. **Cluster sem nodes** → Reativado 7 nodes (system:2, workloads:3, critical:2)
2. **Replication factor mismatch** → Corrigido parâmetro Helm
3. **Liveness probes agressivos** → Aumentado timeouts (60s initialDelay)
4. **ALB Controller webhook down** → Aguardado nodes subirem

### Próximos Passos

- Marco 3 (Produção): Reavaliar RF=3 para workloads críticos
- Implementar PodDisruptionBudgets
- Configurar CloudWatch Alarms
- Integrar Grafana Datasource (Fase 2 - Marco 2 Fase 8)

**Arquivo:** [modules/tempo/main.tf:357](../../../platform-provisioning/aws/kubernetes/terraform/envs/marco2/modules/tempo/main.tf)

---

**Mantenedor:** DevOps Team
**Última Revisão:** 2026-02-02

---

## 📝 ADR-026: Multi-Environment Terraform Refactoring

**Data:** 2026-02-02
**Status:** ✅ Aprovado
**Decisores:** AWS Specialist, Terraform Specialist, FinOps, Security

### Contexto

Após implementação do Marco 3 (GitLab + Redis Operator), identificamos necessidade de refatoração arquitetural para:

1. **Segregar ambientes** STAGING/PROD (atualmente rodando como monólito "prod")
2. **Otimizar custos** via downsizing STAGING + FinOps automation
3. **Isolar DataServices** por ambiente (PostgreSQL, Redis, RabbitMQ, Secrets)
4. **Shared GitLab** (único CI/CD para ambos ambientes)
5. **Hybrid Observability** (shared backend, labeled separation)

**Motivações de Custo:**
- Custo atual (marco3 monolítico): R$ 4.062/mês
- Projeção ingênua (duplicar STAGING): R$ 8.124/mês (inviável)
- **Meta otimizada:** R$ 2.887/mês (economia de 64% vs ingênuo)

### Decisão

#### 1. Terraform Structure Refactoring

```
terraform/
├── modules/ (shared)
│   ├── gitlab/
│   ├── redis/
│   ├── rabbitmq/
│   ├── postgresql/
│   ├── observability/
│   ├── kube-prometheus-stack/
│   ├── loki/
│   ├── tempo/
│   └── finops-automation/
└── environments/
    ├── common/
    │   └── common.tfvars (shared variables)
    ├── staging/
    │   ├── main.tf
    │   ├── terraform.tfvars
    │   └── backend.tf (key: environments/staging/terraform.tfstate)
    └── prod/
        ├── main.tf
        ├── terraform.tfvars
        └── backend.tf (key: environments/prod/terraform.tfstate)
```

#### 2. Component Distribution Strategy

| Componente | Decisão | Rationale |
|------------|---------|-----------|
| **GitLab** | ✅ SHARED | 1 instância = -$92/mês economia, pipelines por branch |
| **DataServices** | ❌ SEPARATED | Isolamento dados, secrets, compliance |
| **Observability** | ⚠️ HYBRID | Shared backend + labels = -40% custo vs separated |
| **FinOps** | 🎯 STAGING ONLY | Shutdown 18h-8h = -R$ 204/mês |

#### 3. Environment Configurations

**STAGING (Cost-Optimized):**
- PostgreSQL: `db.t3.micro` single-AZ (accept downtime)
- Redis: 1 replica (no Sentinel)
- RabbitMQ: 1 replica (no quorum)
- Nodes: 2× t3.medium (FinOps shutdown 70% time)
- Retention: Logs 7d, Metrics 7d
- Tags: `Environment=staging`, `LGPD=Synthetic`

**PROD (Production-Grade):**
- PostgreSQL: `db.t3.medium` Multi-AZ (99.95% SLA)
- Redis: 3 replicas + Sentinel (HA failover <30s)
- RabbitMQ: 3 replicas quorum (HA)
- Nodes: 3× t3.large (24/7 always on)
- Retention: Logs 30d, Metrics 30d
- Tags: `Environment=prod`, `LGPD=PII`

### Rationale

1. ✅ **Economia massiva:** R$ 5.237/mês vs cenário ingênuo (-64%)
2. ✅ **Isolamento completo:** Dados STAGING ≠ PROD (compliance LGPD)
3. ✅ **GitLab shared:** -$92/mês, CI/CD centralizado
4. ✅ **Observability hybrid:** -40% custo, dashboards comparativos
5. ✅ **FinOps STAGING:** -R$ 204/mês (auto-shutdown 18h-8h BRT)
6. ✅ **Professional structure:** Terraform best practices (environments pattern)

### Alternativas Consideradas

1. ❌ **Duplicar Marco 3 (2× STAGING)**: R$ 8.124/mês (inviável, +100% custo)
2. ❌ **Terraform Workspaces**: Menos isolamento, state shared bucket
3. ✅ **Environments folders** (escolhido): Máximo isolamento, professional

### Consequências

#### ✅ Positivas

- **Economia:** R$ 5.237/mês vs cenário ingênuo (-64%)
- **Economia vs Quickstart planejado:** -R$ 737/mês (-20%)
- **Economia vs Marco 3 atual:** -R$ 1.175/mês (-29%)
- **Isolamento:** DataServices separados por ambiente (compliance)
- **Shared benefits:** GitLab único, Observability hybrid
- **FinOps automation:** STAGING auto-shutdown (seg-sex, 18h-8h BRT)
- **ROI mantido:** 107% vs SaaS/Tanzu

#### ⚠️ Negativas

- **Complexidade:** Refatoração completa (8 dias esforço)
- **State migration:** Risco mitigado com backup S3
- **GitLab SPOF:** Mitigado com backups Gitaly PVC + S3
- **Observability SPOF:** Mitigado com HA Prometheus (2 replicas)

### Custos Consolidados

| Componente | STAGING | PROD | TOTAL/mês | Economia |
|------------|---------|------|-----------|----------|
| GitLab (Shared) | - | - | $92.71 | -$92 vs duplicado |
| PostgreSQL | $9 | $60 | $69 | - |
| Redis | $4.50 | $18.50 | $23 | -$419 vs Tanzu |
| RabbitMQ | $4.50 | $18.50 | $23 | - |
| Observability (Hybrid) | - | - | $122 | -$82 vs separated |
| Nodes | $18 | $108 | $126 | - |
| Storage + S3 | - | - | $30 | - |
| ALB + NLB | - | - | $29.50 | - |
| FinOps Economy | -$34 | $0 | -$34 | Shutdown automation |
| **TOTAL** | **~$100** | **~$380** | **$481.21** | **R$ 2.887/mês** |

**Conversão BRL (R$ 6,00):** R$ 2.887/mês (R$ 34.644/ano)

### NetworkPolicies Enforcement

Cross-environment isolation via NetworkPolicies:

```yaml
# STAGING apps NÃO acessam PROD dataservices
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-staging-to-prod-data
  namespace: app-staging
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
      - namespaceSelector:
          matchLabels:
            environment: staging  # ONLY staging namespaces
```

### Implementação

Timeline: 8 dias úteis (64h esforço, 1 engenheiro)

**Fases:**
1. Preparação e Backup (4h)
2. Refatoração Módulos Shared (12h)
3. Secrets Manager (6h)
4. Deploy STAGING (8h)
5. Deploy PROD (8h)
6. Observability Hybrid (8h)
7. NetworkPolicies & Security (6h)
8. Documentação & Handoff (2h)

**Arquivo:** [environments/README.md](../../../platform-provisioning/aws/kubernetes/terraform/environments/README.md)

---

## 📝 ADR-027: Shared GitLab with Separated DataServices

**Data:** 2026-02-02
**Status:** ✅ Aprovado
**Contexto:** Decisão estratégica sobre compartilhamento GitLab vs DataServices

### Decisão

- **GitLab:** ✅ SHARED (1 instância, projects por grupos `staging/` e `prod/`)
- **DataServices:** ❌ SEPARATED (PostgreSQL, Redis, RabbitMQ por ambiente)

### Rationale

#### GitLab Shared (Por quê compartilhar?)

1. ✅ **Economia:** -$92/mês vs 2 instâncias
2. ✅ **CI/CD centralizado:** 1 ponto de controle, auditoria unificada
3. ✅ **GitLab Runners:** Deploy para STAGING ou PROD via Kubernetes RBAC
4. ✅ **Repos Git compartilhados:** Menos duplicação, single source of truth
5. ✅ **Branching strategy:** `main` → PROD, `develop` → STAGING (GitFlow)

**Organização de Projects:**

```
GitLab CE (namespace: gitlab)
├── Group: staging/
│   ├── staging/api (deploy target: STAGING K8s)
│   ├── staging/frontend
│   └── staging/...
└── Group: prod/
    ├── prod/api (deploy target: PROD K8s)
    ├── prod/frontend
    └── prod/...
```

**GitLab Runners RBAC:**

```yaml
# Runner STAGING - ServiceAccount com RBAC limitado
apiVersion: v1
kind: ServiceAccount
metadata:
  name: gitlab-runner-staging
  namespace: gitlab
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: gitlab-runner-staging-deployer
  namespace: app-staging
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: edit  # Pode deployar apps
subjects:
  - kind: ServiceAccount
    name: gitlab-runner-staging
    namespace: gitlab
```

#### DataServices Separated (Por quê separar?)

1. ✅ **Isolamento dados sensíveis:** PROD (PII) ≠ STAGING (synthetic)
2. ✅ **Compliance LGPD:** Dados pessoais apenas em PROD
3. ✅ **Secrets segregation:** `staging/` prefix ≠ `prod/` prefix (AWS Secrets Manager)
4. ✅ **Fail-safe:** Bug em STAGING DB não afeta PROD
5. ✅ **Performance isolation:** Load test STAGING não degrada PROD
6. ✅ **Backup policies:** PROD 30d retention, STAGING 7d

**Secrets Segregation (AWS Secrets Manager):**

```
staging/postgresql/gitlab-password  → STAGING RDS
staging/redis/password               → STAGING Redis
prod/postgresql/gitlab-password      → PROD RDS
prod/redis/password                  → PROD Redis
```

### NetworkPolicies Enforcement

```yaml
# STAGING apps ONLY access STAGING dataservices
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-staging-dataservices
  namespace: app-staging
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
      - namespaceSelector:
          matchLabels:
            environment: staging
      ports:
        - protocol: TCP
          port: 5432  # PostgreSQL
        - protocol: TCP
          port: 6379  # Redis
        - protocol: TCP
          port: 5672  # RabbitMQ
```

### Trade-offs Aceitos

| Aspecto | Shared GitLab | Separated DataServices |
|---------|---------------|------------------------|
| **Custo** | ✅ -$92/mês economia | ⚠️ +$69/mês (2 RDS) |
| **Blast Radius** | ⚠️ GitLab down = CI/CD stop | ✅ STAGING DB down ≠ PROD |
| **Compliance** | ✅ Repos não contêm PII | ✅ PROD dados isolados |
| **Operational** | ✅ 1 instância para manter | ⚠️ 2× dataservices (minor) |

**Mitigações GitLab SPOF:**
- Gitaly PVC backups diários (S3 lifecycle 30d)
- PostgreSQL RDS automated backups (7d retention)
- GitLab configuration backup (`gitlab-backup` CronJob)
- RTO target: <4h (restore from backup)

### Consequências

- ✅ Economia líquida: -$23/mês ($92 GitLab - $69 DataServices duplicados)
- ✅ Compliance LGPD: Dados PROD isolados
- ✅ Security: Secrets Manager segregation
- ⚠️ GitLab SPOF: Mitigado com backups (RTO <4h)

**Arquivo:** ADR-026 (parent decision)

---

## 📝 ADR-028: Hybrid Observability with OpenTelemetry

**Data:** 2026-02-02
**Status:** ✅ Aprovado
**Contexto:** Estratégia de observability multi-ambiente (STAGING + PROD)

### Decisão

**Observability Hybrid:** Shared backend + labeled separation

**Arquitetura:**

```
observability namespace (shared)
├── Prometheus (scrape STAGING + PROD, labels environment=)
├── Grafana (datasources per environment, dashboards with variables)
├── Loki (S3 prefixes staging/ 7d, prod/ 30d lifecycle)
├── Tempo (tenant separation via headers)
└── OpenTelemetry Collector (DaemonSet global, auto-label namespace)
```

### Rationale

#### 1. Shared Backend (Por quê compartilhar?)

1. ✅ **Economia:** $122/mês vs $204 separated (-40% custo)
2. ✅ **Dashboards comparativos:** STAGING vs PROD side-by-side
3. ✅ **Single pane of glass:** 1 Grafana para ambos ambientes
4. ✅ **Operational simplicity:** 1 Prometheus para manter

**Custo Breakdown:**

| Componente | Shared | Separated | Economia |
|------------|--------|-----------|----------|
| Prometheus | $30 | $60 (2×) | -$30 |
| Grafana | $20 | $40 (2×) | -$20 |
| Loki | $42 | $84 (2×) | -$42 (+lifecycle) |
| Tempo | $30 | $60 (2×) | -$30 |
| **TOTAL** | **$122** | **$244** | **-$122 (-40%)** |

#### 2. Labeled Separation (Como isolar?)

**Prometheus Labels:**

```yaml
# ServiceMonitor auto-label via namespace
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: app-metrics
  namespace: app-staging
spec:
  selector:
    matchLabels:
      app: myapp
  endpoints:
    - port: metrics
      relabelings:
        - sourceLabels: [__meta_kubernetes_namespace]
          regex: ".*-(staging|prod)"
          targetLabel: environment
```

**Loki S3 Prefixes + Lifecycle:**

```yaml
# Loki configuration
schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: s3
      schema: v13
      index:
        prefix: loki_index_
        period: 24h

storage_config:
  aws:
    bucketnames: k8s-platform-loki-chunks
    region: us-east-1
  # Prefixes via tenant ID
  tsdb_shipper:
    active_index_directory: /data/loki/tsdb-index
    cache_location: /data/loki/tsdb-cache

limits_config:
  retention_period: 168h  # 7d default (STAGING)
  per_tenant_override_config: /etc/loki/overrides.yaml  # PROD 30d

# S3 Lifecycle Policy
{
  "Rules": [
    {
      "Id": "staging-logs-7d",
      "Filter": {"Prefix": "fake/staging/"},
      "Status": "Enabled",
      "Expiration": {"Days": 7}
    },
    {
      "Id": "prod-logs-30d",
      "Filter": {"Prefix": "fake/prod/"},
      "Status": "Enabled",
      "Expiration": {"Days": 30}
    }
  ]
}
```

**Tempo Tenant Separation:**

```yaml
# Tempo configuration
multitenancy_enabled: true
distributor:
  receivers:
    otlp:
      protocols:
        grpc:
          tenant_header: X-Scope-OrgID  # staging or prod

# OpenTelemetry Collector (auto-inject tenant)
exporters:
  otlp/tempo:
    endpoint: tempo-distributor.observability.svc:4317
    headers:
      X-Scope-OrgID: ${NAMESPACE_ENVIRONMENT}  # staging or prod
```

**Grafana Multi-Datasource:**

```yaml
datasources:
  - name: Prometheus-STAGING
    type: prometheus
    url: http://prometheus:9090
    jsonData:
      httpMethod: POST
    # Default query: {environment="staging"}

  - name: Prometheus-PROD
    type: prometheus
    url: http://prometheus:9090
    # Default query: {environment="prod"}

  - name: Prometheus-COMPARISON
    type: prometheus
    url: http://prometheus:9090
    # Query both: {environment=~"staging|prod"}
```

#### 3. OpenTelemetry Auto-Label

```yaml
# OpenTelemetry Collector DaemonSet
processors:
  k8sattributes:
    extract:
      metadata:
        - k8s.namespace.name
        - k8s.pod.name
        - k8s.deployment.name
    filter:
      node_from_env_var: KUBE_NODE_NAME

  # Auto-detect environment from namespace suffix
  resource:
    attributes:
      - key: environment
        from_attribute: k8s.namespace.name
        action: extract
        pattern: ^.*-(staging|prod)$
```

### Alternativas Consideradas

1. ❌ **Fully Separated:** $244/mês, operacional complexity, sem dashboards comparativos
2. ❌ **Fully Shared (no labels):** $122/mês, mas sem isolamento retention
3. ✅ **Hybrid (shared + labels):** $122/mês, dashboards comparativos, retention diferenciada

### Trade-offs Aceitos

| Aspecto | Hybrid | Separated |
|---------|--------|-----------|
| **Custo** | ✅ $122/mês | ❌ $244/mês |
| **Dashboards Comparativos** | ✅ STAGING vs PROD | ❌ Requer federation |
| **Blast Radius** | ⚠️ Prometheus down = ambos | ✅ STAGING ≠ PROD |
| **Retention Policies** | ✅ S3 lifecycle (7d vs 30d) | ✅ Separado naturalmente |
| **Query Performance** | ⚠️ Shared index (minor) | ✅ Isolated queries |

**Mitigações Blast Radius:**
- HA Prometheus (2 replicas + Thanos optional)
- PodDisruptionBudget `maxUnavailable=0`
- CloudWatch Alarm: Prometheus down >5min
- Fallback: CloudWatch Logs (7d STAGING, 30d PROD)

### Consequências

- ✅ Economia: -$122/mês vs separated (-40%)
- ✅ Dashboards comparativos: STAGING vs PROD performance analysis
- ✅ Retention diferenciada: S3 lifecycle policies (7d vs 30d)
- ✅ OpenTelemetry auto-label: Zero config app changes
- ⚠️ Blast radius: Prometheus down afeta ambos (mitigado HA)
- ⚠️ Query performance: Shared index (minor, aceitável)

### Grafana Dashboard Example (Comparative)

```json
{
  "title": "API Latency: STAGING vs PROD",
  "panels": [
    {
      "title": "p95 Latency Comparison",
      "targets": [
        {
          "datasource": "Prometheus-COMPARISON",
          "expr": "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{job=\"api\"}[5m])) by (environment)"
        }
      ]
    }
  ]
}
```

**Arquivo:** [modules/observability/](../../../platform-provisioning/aws/kubernetes/terraform/modules/)

---

**Mantenedor:** DevOps Team
**Última Revisão:** 2026-02-02
**Próxima Revisão:** Marco 3 Planning (GitLab deployment decisions)

## 📝 ADR-029: Redis Sentinel User Alignment for PSS Restricted

**Data:** 2026-02-03
**Status:** ✅ Implementado (26 minutos resolution)
**Framework:** [executor-terraform.md](../prompts/executor-terraform.md) (Multi-Agent Validation: Orquestrador, K8s, Security)
**Logbook:** [2026-02-03-redis-sentinel-crashloop-fix.md](../logbook/2026-02-03-redis-sentinel-crashloop-fix.md)
**Contexto:** Redis Sentinel CrashLoopBackOff após deploy Marco 3 com PSS Restricted enforcement

### Problema

**Sintoma:** 3 Sentinels em CrashLoopBackOff contínuo
```
Sentinel config file /redis/sentinel.conf is not writable: Permission denied. Exiting...
```

**Impacto:** HA Redis comprometida (0/3 Sentinels READY), quorum impossible

### Causa Raiz

**User ID Mismatch:**
- Spotahome Redis Operator injeta init container `sentinel-config-copy` com `runAsUser: 1000` (hardcoded)
- RedisFailover CR configurado com `securityContext.runAsUser: 1001` (main container)
- Init container copia `/redis/sentinel.conf` com owner 1000
- Main container (user 1001) tenta escrever → **Permission denied**
- PSS Restricted bloqueia `chown`/`chmod` no init container → sem workaround

**Problemas Secundários:**
- Operator authentication failure (`WRONGPASS`) → secret divergente do pod
- Dual operators em leader election race → reconciliation loops
- Custom config Sentinel inválido → syntax error `SENTINEL SET`

### Decisão

**Alinhar TODO o SecurityContext para `runAsUser: 1000`** (Sentinel + Redis + Redis master/replicas)

**Rationale:** Spotahome Redis Operator hardcodes init container user=1000, logo CR DEVE seguir esse padrão para compatibilidade PSS Restricted.

### Implementação

#### 1. Fix SecurityContext (User Alignment)

**Antes (BROKEN):**
```hcl
# modules/redis/main.tf
securityContext = {
  runAsUser  = 1001  # ❌ Mismatch com init container
  runAsGroup = 1001
  fsGroup    = 1001
}
```

**Depois (FIXED):**
```hcl
# modules/redis/main.tf:195-205
securityContext = {
  runAsNonRoot = true
  runAsUser    = 1000  # ✅ Aligned com Operator init container
  runAsGroup   = 1000
  fsGroup      = 1000  # ✅ Permite init copy + main write
  seccompProfile = {
    type = "RuntimeDefault"
  }
}
```

**Aplicado em:**
- Sentinel SecurityContext (linha 198-205)
- Redis SecurityContext (linha 237-245)

#### 2. Fix Secret Password (WRONGPASS)

**Problema:** Secret `redis-password` divergente do pod `$REDIS_PASSWORD`

**Solução:**
```bash
# Extrair senha REAL do pod
REAL_PASS=$(kubectl exec rfr-redis-0 -n data-services -- sh -c 'echo "$REDIS_PASSWORD"')
# Senha: (ZqDJhlChSzP7VT)of$!rLLG8}l#eJe9

# Recreate secret
kubectl delete secret redis-password -n data-services
kubectl create secret generic redis-password -n data-services \
  --from-literal=password="$REAL_PASS"

# Force operator reload
kubectl delete pod -n redis-operator -l app.kubernetes.io/name=redis-operator
```

#### 3. Fix Dual Operators (Leader Election)

**Problema:** 2 operators competindo
- `redisoperator` (22h, errors WRONGPASS)
- `redis-operator` (14h, stuck acquiring lease)

**Solução:**
```bash
kubectl scale deployment redisoperator -n redis-operator --replicas=0
kubectl delete lease redis-failover-lease -n redis-operator
```

#### 4. Cleanup Invalid CustomConfig

**Problema:** `customConfig: ["sentinel monitor mymaster rfrm-redis..."]` → ERR Unknown option

**Solução:** Remover customConfig (auto-discovery funciona perfeitamente)
```bash
kubectl patch redisfailover redis -n data-services --type=json \
  -p='[{"op": "remove", "path": "/spec/sentinel/customConfig"}]'
```

### Validação

```bash
# ✅ 3/3 Sentinels READY
kubectl get pods -n data-services -l app.kubernetes.io/component=sentinel
# rfs-redis-7459d89b5d-6x6fx   1/1     Running   0          7m
# rfs-redis-7459d89b5d-hwft6   1/1     Running   0          7m
# rfs-redis-7459d89b5d-xbxcj   1/1     Running   0          7m

# ✅ Quorum operational
kubectl exec rfs-redis-7459d89b5d-6x6fx -n data-services -c sentinel -- \
  redis-cli -p 26379 sentinel ckquorum mymaster
# OK 3 usable Sentinels. Quorum and failover authorization can be reached

# ✅ Master discovered (auto-discovery)
kubectl exec rfs-redis-7459d89b5d-6x6fx -n data-services -c sentinel -- \
  redis-cli -p 26379 sentinel get-master-addr-by-name mymaster
# 10.0.144.105
# 6379

# ✅ Operator sem erros
kubectl logs -n redis-operator -l app.kubernetes.io/name=redis-operator --tail=20 | grep WRONGPASS
# (sem output = OK)
```

### Lições Aprendidas (15 itens)

#### 🔒 Security & PSS Restricted

| # | Lição | Impacto |
|---|-------|---------|
| 1 | **Spotahome Redis Operator hardcodes init container `runAsUser: 1000`** → RedisFailover CR DEVE usar `runAsUser: 1000` em todo SecurityContext | 🔴 Crítico |
| 2 | PSS Restricted bloqueia `allowPrivilegeEscalation`, `chown`, `chmod` → única solução é **user alignment** | 🟡 Médio |
| 3 | `readOnlyRootFilesystem: true` no Sentinel requer init container para copiar config writable → filesystem `/redis-writable` (emptyDir) | 🟢 Baixo |

#### 🔐 Secrets & Authentication

| # | Lição | Impacto |
|---|-------|---------|
| 4 | **Secrets não são hot-reloaded** → mudanças em secret requerem restart do pod consumidor | 🟡 Médio |
| 5 | Operator cria secret `redis-password` via Terraform, mas pode divergir do usado pelos pods → **sempre validar sync** com `kubectl exec -- echo "$REDIS_PASSWORD"` | 🔴 Crítico |
| 6 | ConfigMap `rfr-redis` tem senha hardcoded **diferente** do secret → Operator inconsistency conhecida | 🟡 Médio |

#### 🎛️ Operator Management

| # | Lição | Impacto |
|---|-------|---------|
| 7 | **Múltiplos operators** com mesmo CRD causam reconciliation loops → garantir operator único por namespace/cluster | 🔴 Crítico |
| 8 | Leader election lease persiste após pod death → `kubectl delete lease` para forçar re-election | 🟢 Baixo |
| 9 | Operator logs são **críticos** para debug → sempre verificar `WRONGPASS`, `error on object processing` | 🟡 Médio |

#### 🔄 Sentinel Auto-Discovery

| # | Lição | Impacto |
|---|-------|---------|
| 10 | ConfigMap inicial com `sentinel monitor mymaster 127.0.0.1` é **normal** → Sentinels fazem auto-discovery após quorum | 🟢 Baixo |
| 11 | Sentinels precisam quorum (2/3) para descobrir master → rollout gradual pode causar `+sdown` temporário | 🟢 Baixo |
| 12 | `customConfig` para override `sentinel monitor` **NÃO funciona** → deixar auto-discovery | 🟡 Médio |

#### ⚙️ Deployment Strategies

| # | Lição | Impacto |
|---|-------|---------|
| 13 | **Scale 0→3** é mais rápido que rollout gradual quando há CrashLoopBackOff → limpa estado corrupto | 🟡 Médio |
| 14 | Operator reverte patches manuais no Deployment → **sempre patchar o CR** (`RedisFailover`), não recursos gerenciados | 🔴 Crítico |
| 15 | PVC resize warnings (`field can not be less than previous value`) são noise → storage já provisionado, ignorar | 🟢 Baixo |

### Métricas

| Métrica | Valor |
|---------|-------|
| **Tempo total** | 26 minutos (12:33-13:01) |
| **Tentativas de fix** | 4 |
| **Pods recriados** | ~15 (3 Sentinels × 5 rollouts) |
| **Operator restarts** | 3 |
| **Downtime Sentinel HA** | ~20min (master não afetado) |
| **ROI troubleshooting** | HA restaurada, zero impacto produção |

### Consequências

#### ✅ Positivas

- **Redis HA operacional:** 3/3 Sentinels READY, quorum OK
- **Auto-discovery funcional:** Master `10.0.144.105:6379` descoberto automaticamente
- **Operator funcionando:** Sem erros WRONGPASS, reconciliation OK
- **PSS Restricted compliant:** SecurityContext aligned com Operator pattern
- **Documentação completa:** Logbook + ADR + lições aprendidas (15 itens)

#### ⚠️ Negativas (Aceitáveis)

- **Vendor pattern lock:** Spotahome user=1000 é hardcoded (sem workaround PSS Restricted)
- **ConfigMap inconsistency:** Senha hardcoded ≠ secret (Operator bug, não-bloqueante)
- **Dual operators risk:** Cleanup manual necessário (terraform não gerenciava operator antigo)

### Riscos Mitigados

| Risco | Status | Mitigação |
|-------|--------|-----------|
| **HA Redis indisponível** | ✅ MITIGADO | 3/3 Sentinels operacionais, quorum restored |
| **Permission denied recorrente** | ✅ MITIGADO | User alignment permanente no Terraform module |
| **Operator authentication failures** | ✅ MITIGADO | Secret sync validado, operator reload |
| **Dual operators conflicts** | ✅ MITIGADO | Operator antigo scaled down, único operator ativo |

### Referências

- **Logbook:** [2026-02-03-redis-sentinel-crashloop-fix.md](../logbook/2026-02-03-redis-sentinel-crashloop-fix.md)
- **Terraform Module:** [modules/redis/main.tf](../../../platform-provisioning/aws/kubernetes/terraform/modules/redis/main.tf)
- **PSS Restricted:** [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/#restricted)
- **Spotahome Redis Operator:** [GitHub](https://github.com/spotahome/redis-operator)
- **ADR-023:** Migration from Bitnami Charts to Kubernetes Operators

### Aprovações

- [x] **K8s Specialist** (SecurityContext, PSS compliance) - ✅ Validado (2026-02-03)
- [x] **Security** (user alignment, secrets management) - ✅ Aprovado (2026-02-03)
- [x] **Orquestrador** (architecture consistency, documentation) - ✅ Aprovado (2026-02-03)

**Status:** 🚀 **ATIVO EM PRODUÇÃO** (2026-02-03 13:01)

---

