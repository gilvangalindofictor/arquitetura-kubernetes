# 📋 Decisões Técnicas - Plataforma Kubernetes AWS

**Última Atualização:** 2026-01-29
**Versão:** 2.0 (Marco 2 Completo)
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

**Mantenedor:** DevOps Team
**Última Revisão:** 2026-01-29
**Próxima Revisão:** Marco 3 Planning (GitLab deployment decisions)
