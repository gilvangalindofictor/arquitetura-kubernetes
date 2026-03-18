# Catálogo de Componentes da Plataforma — Staging & Produção

**Data:** 2026-03-18 | **Cluster:** k8s-platform-prod (compartilhado) | **Status:** REFERÊNCIA VIVA
**Conta AWS:** 891377105802 | **Região:** us-east-1
**Produzido por:** Mesa Técnica — AWS Specialist + Security Specialist + FinOps Specialist

---

## Sobre este documento

Lista todos os componentes presentes (ou a provisionar) na plataforma, em ambos os ambientes (staging e produção), com:
- **Motivador**: por que este componente existe (o problema que resolve)
- **Status por ambiente**: staging / prod
- **Custo estimado**
- **ADR de referência** quando aplicável

> Convenção: ✅ Ativo | 🔄 Em provisionamento | ⏳ Pendente (próximas fases) | ❌ Não existe

---

## 1. INFRAESTRUTURA AWS BASE

### 1.1 Amazon EKS — Control Plane

| Atributo | Valor |
|---------|-------|
| **Motivador** | Orquestração de contêineres com plano de controle gerenciado pela AWS. Elimina a operação manual de etcd, kube-apiserver e kube-controller-manager. Habilita integração nativa com IAM (IRSA), VPC CNI, ALB Controller e Karpenter. Adotado no ADR-059. |
| Staging | ✅ Ativo (`k8s-platform-prod` — nome histórico, cluster é compartilhado) |
| Produção | ✅ Compartilhado com staging (mesmo cluster, namespaces separados) |
| Custo | $73.00/mês fixo (controle plane gerenciado) |
| ADR | ADR-059 (Karpenter), ADR-007 (Cluster Autoscaler) |

---

### 1.2 Karpenter — Node Provisioner

| Atributo | Valor |
|---------|-------|
| **Motivador** | Provisionamento dinâmico de nós EC2 baseado nas demandas reais dos Pods. Substitui o Cluster Autoscaler tradicional com latência menor (segundos vs minutos) e suporte a Spot, diversificação de instâncias e bin-packing avançado. Reduz custo ao dimensionar exatamente o que o workload precisa. |
| Staging | ✅ Ativo — provisiona nós sob demanda nos dias úteis |
| Produção | ✅ Compartilhado — provisiona nós 24×7 para workloads prod |
| Custo | Incluído no custo dos nós EC2 (sem custo adicional de software) |
| ADR | ADR-059 |

---

### 1.3 EC2 Nodes (t3.medium) — Nós de Trabalho

| Atributo | Valor |
|---------|-------|
| **Motivador** | Capacidade de compute para executar os Pods da plataforma. t3.medium (2 vCPU, 4GB RAM) equilibra custo e capacidade para workloads de plataforma (GitLab, Keycloak, Vault, Observabilidade). Karpenter provisiona e deprovision automaticamente conforme demanda. |
| Staging | ✅ ~8 nós avg durante 8h/dia útil (desligados fora do horário pelo FinOps Lambda) |
| Produção | ⏳ +9 nós estimados 24×7 pós fases 2-7 |
| Custo | $0.0416/h/nó. Staging com FinOps: ~$58/mês. Prod 24×7: ~$274/mês (9 nós) |
| ADR | ADR-007, ADR-022 (FinOps) |

---

### 1.4 Amazon RDS PostgreSQL — Banco de Dados Relacional

| Atributo | Valor |
|---------|-------|
| **Motivador** | Banco de dados relacional gerenciado para GitLab (metadados, CI/CD state), Keycloak (usuários, realms, sessions), Harbor (repositório de metadados de imagens) e SonarQube (análises de qualidade). RDS elimina operação de PostgreSQL self-managed (backup, patch, failover). Multi-AZ garante disponibilidade de 99.95% com failover automático em <120s. |
| **Estratégia** | **1 instância compartilhada Multi-AZ (db.t3.medium, 100GB) com databases isolados por ambiente** — decisão Mesa Técnica 2026-03-18. Saving $12.81/mês vs 2 instâncias dedicadas. |
| Staging | ✅ Databases `*_staging` na mesma instância RDS — role `NOSUPERUSER/NOCREATEDB`, `pg_monitor` revogado |
| Produção | ⏳ Databases `*_prod` na mesma instância RDS Multi-AZ — `pgaudit` por role, `dblink` desabilitado |
| Isolamento | Database-level: cada serviço tem user dedicado (`gitlab_staging_user`, `gitlab_prod_user`). Cross-database queries bloqueadas. `pg_stat_activity` de prod invisível para roles staging. |
| Custo | **$124.18/mês** (1 instância Multi-AZ shared) — vs $136.99/mês com 2 instâncias |
| ADR | ADR-050 (Multi-AZ para Data Services) |

---

### 1.5 Redis — Cache e Message Broker

| Atributo | Valor |
|---------|-------|
| **Motivador** | Cache distribuído e pub/sub para GitLab (cache de sessão, filas de background jobs Sidekiq), Keycloak (cache de sessões distribuídas em modo HA) e ArgoCD (cache de estado). Auto-gerenciado via Spotahome Redis Operator no K8s, sem custo adicional de licença. Sentinel em prod garante failover automático sem intervenção humana. |
| **Estratégia** | **DEDICADO por ambiente — obrigatório** (decisão Mesa Técnica 2026-03-18). Redis compartilhado reprovado por BACEN BCB 85/2021 Art.15 + LGPD Art.46: keyspace namespacing não constitui controle de isolamento auditável; eviction `allkeys-lru` e `FLUSHDB` não respeitam prefixo. 2 CRDs Redis Operator independentes. |
| Staging | ✅ 1 replica, maxmemory 512Mi, `allkeys-lru` — Redis Operator CRD `redis-staging` |
| Produção | ⏳ 3 replicas Sentinel, maxmemory 2Gi, `volatile-lru` — Redis Operator CRD `redis-prod` |
| Custo | **~$0 adicional** — compute incluído nos nós EC2 existentes |
| ADR | ADR-050 |

---

### 1.6 RabbitMQ — Message Queue

| Atributo | Valor |
|---------|-------|
| **Motivador** | Mensageria assíncrona para o serviço Hatch ETL (processamento de mensagens financeiras de originadoras). Quorum queues em prod garantem durabilidade de mensagens (zero perda em falha de nó) — obrigatório para operações financeiras reguladas pelo BACEN. Auto-gerenciado via RabbitMQ Cluster Operator no K8s. |
| **Estratégia** | **1 cluster compartilhado com VHosts isolados** — decisão Mesa Técnica 2026-03-18. VHost é abstração nativa de multi-tenancy do RabbitMQ; isolamento é kernel-level no broker. Controles obrigatórios: staging tag=`management` (nunca `administrator`), Shovel + Federation desabilitados. |
| Staging | ✅ VHost `/staging` — user `rmq-staging` (tag: management) — configure/write/read: `.*` em `/staging` apenas |
| Produção | ⏳ VHost `/prod` — user `rmq-prod` (tag: management) — quorum queues, TTL obrigatório em filas com PII |
| Custo | **~$0 adicional** — compute incluído nos nós EC2 existentes |
| ADR | ADR-050 |

---

### 1.7 NAT Gateway — Saída de Internet para Recursos Privados

| Atributo | Valor |
|---------|-------|
| **Motivador** | Permite que Pods e instâncias nas subnets privadas (EKS nodes, RDS) acessem a internet para pull de imagens Docker, chamadas de API externas, atualizações de pacotes, sem expor esses recursos com IP público. Arquitetura de segurança fundamental: nós do cluster nunca têm IP público. |
| Status | ✅ 2 NAT Gateways (us-east-1a + us-east-1b) — confirmar ambos AVAILABLE |
| Custo | ~$32-38/mês por AZ. Total: ~$70-76/mês Multi-AZ. **Obrigatório antes do go-live prod** |
| Risco | Se apenas 1 AZ ativa, falha da AZ derruba todo o egress do cluster (SLA ~99.5%) |

---

### 1.8 Application Load Balancer (ALB) — Balanceador de Carga

| Atributo | Valor |
|---------|-------|
| **Motivador** | Ponto de entrada de tráfego HTTP/HTTPS para os serviços da plataforma. Termina TLS (via ACM), integra com WAF, suporta múltiplos serviços via IngressGroups (evita custo de 1 ALB por serviço), e distribui carga entre pods. Dois ALBs em prod: `internet-facing` (serviços públicos) e `internal` (serviços acessíveis apenas via VPN). |
| Staging | ✅ 4 ALBs: platform-staging (com WAF), gitlab-staging (sem WAF — GAP), keycloak-staging (sem WAF — GAP), backstage-staging (internal) |
| Produção | ⏳ 2 ALBs a criar: prod-platform-public (internet-facing + WAF) e prod-platform-internal (internal + VPN only) |
| Custo | ~$16-22/mês/ALB (base + LCU). Total staging: ~$26/mês. Total prod: +~$35/mês |
| ADR | ADR-008 (TLS Strategy) |

---

### 1.9 AWS WAF (Web Application Firewall) — Proteção de Camada 7

| Atributo | Valor |
|---------|-------|
| **Motivador** | Proteção ativa contra ataques OWASP Top 10, injeção SQL, inputs maliciosos (Log4Shell, RCE), bots automatizados, e tráfego de países de alto risco. Para serviço financeiro regulado pelo BACEN BCB 85/2021, WAF com regras em Block é obrigatório para serviços expostos à internet. Rate limiting protege contra DDoS de camada 7. **ATENÇÃO: staging atual tem regras em Count — não bloqueiam. Corrigi-las é ação imediata (GAP-P0-05).** |
| Staging | ✅ 1 WebACL ativo (`waf-k8s-platform-prod-staging`) — mas regras 30/40/50 em COUNT |
| Produção | ⏳ 1 WebACL novo a criar (`waf-k8s-platform-prod`) com 6 regras em BLOCK + Bot Control |
| Custo | Staging: ~$11/mês. Prod: ~$53-77/mês (inclui Bot Control + logs 90d) |
| ADR | ADR-099 (WAF Strategy iPaaS) |

**Regras WAF prod (todas em Block):**

| Prioridade | Regra | Propósito |
|-----------|-------|---------|
| P10 | Rate limit: 2.000 req/5min/IP | DDoS L7, scraping agressivo |
| P20 | Geo-block: CN, RU, KP, IR, BY | Conformidade BACEN BCB 85/2021 |
| P30 | AWSManagedRulesCommonRuleSet (OWASP) | OWASP Top 10 (XSS, CSRF, etc.) |
| P40 | AWSManagedRulesSQLiRuleSet | Injeção SQL contra RDS |
| P50 | AWSManagedRulesKnownBadInputsRuleSet | Log4Shell, RCE known exploits |
| P60 | AWSManagedRulesBotControlRuleSet | Bots, scrapers, automação maliciosa |

---

### 1.10 Amazon Route53 — DNS Gerenciado

| Atributo | Valor |
|---------|-------|
| **Motivador** | Serviço DNS autoritativo para o apex `alvocard.com.br`. Integração nativa com ACM para validação DNS automática de certificados. External-DNS automatiza criação de registros A (alias para ALBs) eliminando drift de DNS manual. **Estratégia v2.0 (decisão 2026-03-18):** mover o apex `alvocard.com.br` para o Route53 (ação única no registrar) — após isso, qualquer subdomínio (`prod.*`, `hml.*`, `ipaas.*`) é criado via Terraform sem depender do gestor de domínio. |
| Staging | ❌ Não existe — usa CoreDNS split-horizon com `*.staging.internal` (resolução apenas dentro do cluster) |
| Produção | ⏳ Hosted zone pública apex `alvocard.com.br` a criar (Fase 5) — **requer troca de NS no registrar (1 ação do gestor de domínio — definitiva)** |
| Custo | $0.50/zona/mês + $0.40/1M queries |
| ADR | ADR-098 (DNS e Controle de Acesso) |

---

### 1.11 AWS ACM — Certificados TLS

| Atributo | Valor |
|---------|-------|
| **Motivador** | Emissão gratuita de certificados TLS wildcard com renovação automática (60 dias antes da expiração). Certificados ACM são reconhecidos por todos os browsers e sistemas modernos (Amazon Trust Services). Elimina a necessidade de CA interna sem browser trust que existe hoje no staging. Integração nativa com ALB — sem gestão manual de renovação. |
| Staging | ⚠️ IMPORTED CA interna — sem browser trust (GAP-P0-02) |
| Produção | ⏳ Wildcards `*.alvocard.com.br` + `*.prod.alvocard.com.br` a criar após apex delegado ao Route53 (Fase 5) — validação DNS automática via Route53 |
| Custo | Gratuito (ACM público) |
| ADR | ADR-008 |

---

### 1.12 VPN — Acesso Seguro da Equipe Técnica

| Atributo | Valor |
|---------|-------|
| **Motivador** | Acesso seguro dos engenheiros aos serviços internos da plataforma (ArgoCD, Grafana, Vault, SonarQube, Backstage, RabbitMQ Admin) sem expô-los à internet pública. Substitui o acesso atual via `kubectl port-forward` e `windows-hosts.txt` (operacionalmente insustentável em produção). Split-tunnel roteia apenas tráfego `10.0.0.0/16` pela VPN, preservando performance da internet local. Logs de conexão em CloudWatch para auditoria BACEN. |
| **Decisão** | **Opção B — FortiGate site-to-site** (decisão 2026-03-18). FortiNet corporativo existente (hoje usado apenas para internet/home-office) configurado com IPSec tunnel para a VPC AWS. Custo: ~$37/mês. |
| Staging | ❌ Não existe. Acesso via port-forward + arquivo hosts local |
| Produção | ⏳ A criar na Fase 6 — `aws_vpn_gateway` + `aws_customer_gateway` (FortiGate IP público) + `aws_vpn_connection` |
| Custo | **~$37/mês** (aws_vpn_gateway $0.05/hr × 730h) — R$ 15.730/ano mais barato que AWS Client VPN |
| Pré-requisitos externos | IP público estático do FortiGate + BGP ASN + CIDR rede corporativa (fornecido pelo time de redes) |
| ADR | ADR-095 — atualizar para refletir Opção B FortiGate site-to-site |

---

### 1.13 Amazon S3 — Object Storage

| Atributo | Valor |
|---------|-------|
| **Motivador** | Armazenamento de objetos durável (11 noves de durabilidade) para: artifacts do GitLab CI/CD, blobs de imagens do Harbor (registry), backups do Velero (DR), logs do Loki (observabilidade), traces do Tempo, access logs dos ALBs e WAF, e backups do RDS. S3 como backend do Loki e Tempo elimina a necessidade de PVCs grandes no cluster. |
| Staging | ✅ Buckets: gitlab-artifacts, harbor-images, velero-backups (7d lifecycle), loki-chunks |
| Produção | ✅ Buckets provisionados: 30d lifecycle (vs 7d staging). A adicionar: alb-logs, waf-logs |
| Custo | ~$2-5/mês staging. Prod: ~$10-15/mês (dados reais de prod maiores) |

---

## 2. SEGURANÇA E IDENTIDADE

### 2.1 HashiCorp Vault — Gestão de Secrets

| Atributo | Valor |
|---------|-------|
| **Motivador** | Armazenamento centralizado e auditado de todas as credenciais da plataforma (senhas de banco, tokens de API, chaves privadas, certificados internos). Vault elimina secrets hardcoded em manifestos Kubernetes (violação do ADR-102) e em variáveis de ambiente. Auth backend Kubernetes permite que Pods autentiquem automaticamente via Service Account sem credentials estáticas. Audit log do Vault registra quem acessou qual secret e quando — obrigatório para BACEN BCB 85/2021. |
| Staging | ✅ Namespace `staging-security-vault` — 1 replica, Raft backend, Network Policy ativa |
| Produção | ⏳ Vault HA 3 replicas, Raft backend, namespace `prod-security-vault` (Fase 2) |
| Custo | Compute incluído nos nós EC2. HashiCorp Vault Community: gratuito |
| ADR | ADR-102 (External Secrets Operator), ADR-003 (Secrets Management) |

---

### 2.2 External Secrets Operator (ESO) — Sincronização de Secrets

| Atributo | Valor |
|---------|-------|
| **Motivador** | Sincroniza secrets do Vault para Kubernetes Secrets nativos, mantendo os valores atualizados sem intervenção manual. Implementa o padrão "secrets como código" — os manifestos declaram QUAIS secrets precisam, não OS VALORES. Quando uma senha é rotacionada no Vault, o ESO atualiza automaticamente o K8s Secret e os Pods recebem o novo valor sem redeploy. Elimina o risco de credencial estale (senha expirada ainda em uso). |
| Staging | ✅ Ativo — 11+ ExternalSecrets em estado `SecretSynced` |
| Produção | ⏳ ESO prod + ClusterSecretStore apontando para Vault prod (Fase 2) |
| Custo | Gratuito (open source) |
| ADR | ADR-102 |

---

### 2.3 cert-manager — Gestão de Certificados TLS Internos

| Atributo | Valor |
|---------|-------|
| **Motivador** | Emissão e renovação automática de certificados TLS internos (CA interna) para comunicação entre serviços dentro do cluster. Usada pelo Linkerd para o trust anchor mTLS e por serviços que precisam de TLS interno sem ACM. Elimina a operação manual de renovação de certificados (que já causou um P0 de trust anchor com trailing newline em sessão anterior). |
| Staging | ✅ Ativo — CA interna `*.staging.internal` |
| Produção | ✅ Compartilhado — CA interna para comunicação inter-serviço |
| Custo | Gratuito (CNCF project) |

---

### 2.4 Keycloak — Identity Provider (IdP)

| Atributo | Valor |
|---------|-------|
| **Motivador** | SSO (Single Sign-On) central de toda a plataforma via OIDC e SAML 2.0. Centraliza autenticação de GitLab, Harbor, ArgoCD, Grafana, SonarQube, Backstage, e VPN (via IAM Identity Center SAML). Implementa MFA (TOTP/WebAuthn) para acesso a ferramentas críticas. Em produção com URL pública, habilita Entra ID Federation (ADR-095) — usuários autenticam com credenciais corporativas Microsoft sem contas separadas por ferramenta. Realm prod completamente separado do staging. |
| Staging | ✅ Namespace `staging-platform-keycloak` — realm staging configurado, URLs `*.staging.internal` |
| Produção | ⏳ HA 2+ replicas, PostgreSQL PROD, URL `keycloak.prod.alvocard.com.br` (Fase 2 interno, Fase 5 público) |
| Custo | Compute incluído nos nós EC2. Keycloak: gratuito (Red Hat open source) |
| ADR | ADR-046 (Keycloak SSO Strategy), ADR-095 (Entra ID Federation) |

---

### 2.5 Kyverno — Policy Engine Kubernetes

| Atributo | Valor |
|---------|-------|
| **Motivador** | Enforce de políticas de governança em nível de cluster sem precisar modificar os manifestos dos aplicativos. Garante que Pods têm labels obrigatórios (namespace, ambiente, equipe) para rastreabilidade de custo e operação. Injeta automaticamente o sidecar Linkerd em namespaces anotados (MutatingAdmissionWebhook). Bloqueia o deploy de imagens sem tag imutável (`latest` proibido em produção). |
| Staging | ✅ Ativo — 80/80 namespaces de observabilidade PASS. MutatingPolicy GitLab auto-inject ativa |
| Produção | ✅ Compartilhado (mesmo cluster) — policies serão aplicadas aos namespaces prod |
| Custo | Gratuito (CNCF project) |

---

### 2.6 Network Policies — Micro-segmentação de Rede

| Atributo | Valor |
|---------|-------|
| **Motivador** | Implementam o princípio do menor privilégio a nível de rede dentro do cluster. Sem Network Policies, qualquer Pod pode comunicar com qualquer outro Pod — um Pod comprometido (via supply chain attack ou vulnerabilidade em dependência) pode alcançar Vault, Keycloak ou RDS. As policies definem exatamente quais Pods podem receber e enviar tráfego, limitando o raio de explosão em caso de compromisso. |
| Staging | ⚠️ Parcial — cert-manager, data-services, kube-system, staging-observability OK. **5 namespaces críticos SEM policy: argocd, gitlab, keycloak, sonarqube, harbor (RISCO CRITICO AGORA)** |
| Produção | ⏳ Aplicar em modo audit + enforcement (Fases 1 e 3) |
| Custo | Gratuito (K8s nativo) |
| ADR | ADR-070 (Network Policies Marco 4), ADR-006 (Network Policies Strategy) |

---

## 3. CI/CD E QUALIDADE DE CÓDIGO

### 3.1 GitLab CE — Repositório e CI/CD

| Atributo | Valor |
|---------|-------|
| **Motivador** | Plataforma central de desenvolvimento: versionamento de código (Git), pipelines de CI/CD (GitLab CI), gestão de issues e merge requests, integração com Harbor (push de imagens), ArgoCD (trigger de deploys via GitOps), SonarQube (quality gates) e Harbor (scanning de vulnerabilidades em imagens). GitLab CE é self-hosted — código e pipelines ficam dentro da infra da empresa (sem dependência de SaaS externo para dados sensíveis). Compartilhado entre staging e prod (namespace `staging-platform-gitlab`). |
| Staging | ✅ v18.9.1 (Helm 8.7.0), 11/11 Running, namespace `staging-platform-gitlab` |
| Produção | ✅ Compartilhado — mesmo GitLab serve pipelines de prod |
| Custo | Compute e RDS compartilhados. GitLab CE: gratuito |

---

### 3.2 Harbor — Container Registry

| Atributo | Valor |
|---------|-------|
| **Motivador** | Registry privado de imagens Docker com scanning automático de vulnerabilidades (Trivy). Garante que apenas imagens verificadas e sem CVEs críticos sejam deployadas no cluster. OIDC via Keycloak — developers autenticam com SSO corporativo sem criar contas Harbor separadas. Imagens armazenadas em S3 (sem PVC para blobs). Em produção, exposição pública (`harbor.prod.alvocard.com.br`) permite pull de imagens pelos clusters e pipelines sem acesso VPN. |
| Staging | ✅ Namespace `harbor-system`, Trivy enabled, OIDC via Keycloak staging |
| Produção | ⏳ HA, PostgreSQL PROD, Redis PROD, S3 PROD (Fase 3) |
| Custo | Compute: ~$20-30/mês em nós adicionais. S3: ~$2-5/mês. Harbor: gratuito (CNCF) |

---

### 3.3 ArgoCD — GitOps Continuous Delivery

| Atributo | Valor |
|---------|-------|
| **Motivador** | GitOps controller que mantém o estado do cluster sincronizado com os manifestos no Git. Toda mudança de infra passa pelo Git (PR + review) antes de ser aplicada — elimina `kubectl apply` direto em produção. ArgoCD detecta drift entre o estado desejado (Git) e o estado real (cluster) e corrige automaticamente ou alerta. RBAC via Keycloak OIDC — acesso ao ArgoCD de prod é controlado por grupo no IdP corporativo. |
| Staging | ✅ v2.10.9 (Helm 6.7.18), namespace `staging-platform-argocd`, PKCE S256 ativo |
| Produção | ⏳ HA 2 servers + 3 application-controller (Fase 3) |
| Custo | Compute: ~$10-15/mês em nós compartilhados. ArgoCD: gratuito (CNCF) |

---

### 3.4 SonarQube — Qualidade e Segurança de Código

| Atributo | Valor |
|---------|-------|
| **Motivador** | Análise estática de qualidade e segurança de código em cada MR/PR. Quality Gates bloqueiam o merge de código com bugs críticos, code smells acima do threshold, cobertura de testes insuficiente, ou vulnerabilidades de segurança conhecidas (SAST). Para serviço financeiro, SAST automático é um controle de segurança exigido pelo BACEN BCB 85/2021 (gestão de vulnerabilidades em desenvolvimento). |
| Staging | ✅ Ativo, PostgreSQL staging, Quality Gate blocking no GitLab CI |
| Produção | ⏳ PostgreSQL PROD, ALB internal (acesso somente via VPN) (Fase 3) |
| Custo | Compute: ~$5/mês. SonarQube Community: gratuito |

---

## 4. OBSERVABILIDADE

### 4.1 kube-prometheus-stack — Métricas e Alertas

| Atributo | Valor |
|---------|-------|
| **Motivador** | Stack completo de observabilidade de métricas: Prometheus (coleta e armazenamento TSDB), Alertmanager (roteamento de alertas para Teams/PagerDuty), e Grafana (visualização e dashboards). ServiceMonitors e PodMonitors coletam métricas de todos os componentes da plataforma automaticamente. SLO alerts (latência P99, error rate, disponibilidade) notificam antes que os usuários percebam degradação. |
| Staging | ✅ Ativo, retenção 30d, AlertmanagerConfig via Teams (Slack→Teams migrado DT-005) |
| Produção | ⏳ Retenção 30d, PVC maior (~100GB), SLO alerts prod configurados (Fase 4) |
| Custo | EBS: $8/mês (100GB TSDB prod). kube-prometheus-stack: gratuito |

---

### 4.2 Grafana — Dashboards de Observabilidade

| Atributo | Valor |
|---------|-------|
| **Motivador** | Interface unificada de observabilidade que correlaciona métricas (Prometheus), logs (Loki) e traces (Tempo) em um único painel. Exemplars no Prometheus linkam métricas com traces específicos no Tempo — engenheiros identificam a causa raiz de incidentes sem trocar de ferramenta. Dashboards pré-construídos para Kubernetes, GitLab, Harbor e serviços de dados. |
| Staging | ✅ Ativo via kube-prometheus-stack, correlação Loki↔Tempo 90% configurada |
| Produção | ⏳ ALB internal (acesso somente via VPN), OIDC via Keycloak prod (Fase 4) |
| Custo | Incluído no kube-prometheus-stack. Gratuito |

---

### 4.3 Loki — Agregação de Logs

| Atributo | Valor |
|---------|-------|
| **Motivador** | Agregação de logs de todos os Pods e componentes do cluster com custo muito menor que CloudWatch Logs ou ElasticSearch. Backend S3 elimina PVCs grandes. Integração com Grafana via LogQL permite correlacionar logs com métricas e traces. Retenção de 30d em prod atende ao requisito operacional sem custo excessivo de armazenamento. Logs críticos de segurança (Vault audit, WAF, VPN) exportados separadamente para S3 com retenção 5 anos (BACEN). |
| Staging | ✅ Ativo, S3 backend, retenção 7d |
| Produção | ⏳ S3 backend, retenção 30d, ~80GB/mês (Fase 4) |
| Custo | S3: ~$1.84/mês. Compute incluído. Loki: gratuito |
| ADR | ADR-005 (Logging Strategy) |

---

### 4.4 Tempo — Distributed Tracing

| Atributo | Valor |
|---------|-------|
| **Motivador** | Traces distribuídos (OpenTelemetry) permitem rastrear uma requisição do usuário através de múltiplos serviços (Hatch API → RabbitMQ → ETL Worker → RDS) identificando onde a latência está ocorrendo. Indispensável para debug de problemas de performance em arquiteturas de microsserviços. S3 backend com retenção 14d em prod equilibra custo e utilidade dos traces. |
| Staging | ✅ Ativo, S3 backend, retenção configurada |
| Produção | ⏳ S3 backend, retenção 14d (Fase 4) |
| Custo | S3: ~$1.15/mês. Compute incluído. Tempo: gratuito |

---

### 4.5 OpenTelemetry Collector — Instrumentação

| Atributo | Valor |
|---------|-------|
| **Motivador** | Coleta, processa e exporta telemetria (métricas, logs, traces) dos serviços para os backends corretos (Prometheus, Loki, Tempo). Como agente neutro (CNCF), elimina o vendor lock-in de instrumentação — troca de Loki por Elasticsearch ou Tempo por Jaeger requer apenas reconfigurar o collector, sem alterar o código das aplicações. |
| Staging | ✅ Ativo |
| Produção | ⏳ Provisionar (Fase 4) |
| Custo | Gratuito (CNCF project) |

---

## 5. SERVICE MESH E RESILIÊNCIA

### 5.1 Linkerd — Service Mesh (mTLS)

| Atributo | Valor |
|---------|-------|
| **Motivador** | mTLS (mutual TLS) automático entre todos os serviços dentro do cluster — comunicação inter-Pod é criptografada e autenticada sem alterar o código das aplicações. Para serviço financeiro, isso garante que dados em trânsito dentro do cluster não possam ser interceptados via sniffing de rede mesmo em caso de compromisso de um nó. Linkerd também fornece métricas de latência e error rate por rota via `linkerd viz` para observabilidade de camada 7. |
| Staging | ✅ Phase 2 em progresso — GitLab 2/2+3/3, Harbor 7/7, CNI 10/12 |
| Produção | ⏳ Phase 2 completa em todos os namespaces prod (Fase 6) — **antecipar Keycloak e Vault para Fase 3** |
| Custo | Overhead ~5% CPU por sidecar. Compute incluído nos nós. Linkerd: gratuito (CNCF) |
| ADR | ADR-086 (Linkerd Service Mesh mTLS) |

---

### 5.2 Velero — Backup e Disaster Recovery

| Atributo | Valor |
|---------|-------|
| **Motivador** | Backup automatizado do estado do cluster Kubernetes (recursos, PVCs via CSI snapshots) e restauração de namespaces completos. Em caso de corrupção de dados, deleção acidental ou falha catastrófica, Velero permite restaurar um namespace inteiro em minutos. Schedules diários + hourly garantem RPO < 1h. Testes de restore trimestrais validam que o backup está realmente funcional (backup não testado não é backup). |
| Staging | ✅ Schedules daily+hourly ativos. Restore test (V-010) pendente desde 2026-03-05 |
| Produção | ⏳ S3 bucket dr, schedule diário, retenção 7d (Fase 6) |
| Custo | S3: ~$0.69/mês. EBS Snapshots: ~$7/mês. Velero: gratuito |
| ADR | ADR-090 (Velero DR Strategy) |

---

### 5.3 VPA (Vertical Pod Autoscaler) — Dimensionamento de Recursos

| Atributo | Valor |
|---------|-------|
| **Motivador** | Analisa o consumo real de CPU e memória dos Pods ao longo do tempo e sugere (modo recomendação) ou aplica (modo enforcement) ajustes nos requests/limits. Elimina super-provisionamento (reservar 2 CPU quando o Pod usa 0.2 CPU) que desperdiça capacidade de nós e aumenta custo. Após 30d de observação em prod, migrar para enforcement pode gerar economia de R$ 1.170/ano (estimado da sessão 2026-03-04). |
| Staging | ✅ 4 VPAs com dados coletados. R$1.170/ano net savings estimados |
| Produção | ⏳ Modo recomendação inicialmente; enforcement após 30d de observação (Fase 6) |
| Custo | Gratuito. Economia estimada: R$ 1.170/ano |
| ADR | ADR-105 (VPA Resource Management) |

---

## 6. DEVELOPER EXPERIENCE (IDP)

### 6.1 Backstage — Internal Developer Portal (IDP)

| Atributo | Valor |
|---------|-------|
| **Motivador** | Portal central para desenvolvedores descobrirem, criarem e gerenciarem serviços sem precisar de acesso direto ao Kubernetes. Software Catalog lista todos os serviços com ownership, documentação e status de saúde. Scaffolder permite criar um novo serviço com repositório GitLab, pipeline CI/CD, namespace K8s e Helm chart — em minutos, sem intervenção de DevOps. Reduz a carga operacional da equipe de plataforma. |
| Staging | ✅ Ativo, namespace `staging-platform-backstage`, ALB internal (acesso via port-forward hoje) |
| Produção | ⏳ Helm + Keycloak OIDC, ALB internal (acesso via VPN) (Fase 7) |
| Custo | Compute: ~$5-10/mês. Backstage: gratuito (CNCF) |

---

### 6.2 External-DNS — Automação de DNS

| Atributo | Valor |
|---------|-------|
| **Motivador** | Cria automaticamente registros DNS no Route53 quando um Ingress é criado ou modificado no Kubernetes. Elimina o processo manual de criar registros A/CNAME no Route53 após cada deploy — que é fonte de drift (o Ingress aponta para um ALB mas o DNS ainda aponta para o antigo). Com External-DNS, o DNS é código (derivado dos manifestos K8s) e nunca fica dessincronizado. |
| Staging | ❌ Não instalado — DNS manual (propenso a drift) |
| Produção | ⏳ Helm + IAM IRSA com policy `route53:ChangeResourceRecordSets` (Fase 4) |
| Custo | Gratuito (open source CNCF) |
| ADR | GAP-P1-04 |

---

### 6.3 AWS Load Balancer Controller — Provisionamento de ALBs

| Atributo | Valor |
|---------|-------|
| **Motivador** | Traduz recursos Ingress do Kubernetes em Application Load Balancers da AWS com todas as configurações necessárias (WAF, ACM, IngressGroups, target groups). Sem ele, seria necessário criar ALBs manualmente no console AWS para cada serviço. Com IngressGroups, múltiplos serviços compartilham um único ALB (economia de ~$16-22/mês por serviço sem ALB próprio). |
| Staging | ✅ Ativo via IAM IRSA |
| Produção | ✅ Compartilhado — **verificar se a IAM Role tem permissão na zona prod.alvocard.com.br** |
| Custo | Gratuito. Economia por IngressGroup: ~$16-22/mês por serviço sem ALB próprio |

---

## 7. FINOPS E AUTOMAÇÃO

### 7.1 FinOps Lambda — Scheduler de Shutdown

| Atributo | Valor |
|---------|-------|
| **Motivador** | Desliga automaticamente os nós do cluster staging e a instância RDS staging fora do horário comercial (noites e fins de semana). Redução de ~76% no tempo de execução de staging: de 730h para ~176h por mês. Economia realizada de R$ 61.638/ano (99.4% da meta R$ 62K). Produção NÃO é afetada — Lambda opera apenas em staging. |
| Staging | ✅ Ativo — EventBridge rules para shutdown/startup + Sunday rule |
| Produção | ✅ Excluído do shutdown (prod é 24×7) |
| Custo | ~$0.50/mês (Lambda invocações + EventBridge) |
| ADR | ADR-022 (FinOps Automation Strategy), ADR-024 (FinOps Scheduler) |

---

## 8. APLICAÇÕES DE NEGÓCIO

### 8.1 Hatch ETL API — Serviço de Integração Financeira

| Atributo | Valor |
|---------|-------|
| **Motivador** | API que recebe mensagens financeiras de originadoras via RabbitMQ e processa operações de ETL (Extract, Transform, Load) para o banco de dados de produção. Serviço de negócio principal da plataforma — é o único componente com exposição pública por necessidade de negócio (integração com parceiros externos). WAF + ACM obrigatórios por processar dados financeiros regulados pelo BACEN. |
| Staging | ✅ Namespace `staging-data-hatch-etl`, pipeline CI/CD via GitLab |
| Produção | ⏳ Namespace `prod-data-hatch-etl`, URL `hatch-api.prod.alvocard.com.br` (pós Fase 5) |
| Custo | Compute incluído nos nós EC2 |

---

### 8.2 Hatch Web UI — Interface de Usuário

| Atributo | Valor |
|---------|-------|
| **Motivador** | Interface web de usuário final da plataforma financeira. Frontend que consome a Hatch ETL API e exibe dados processados. Exposição pública (`hatch.prod.alvocard.com.br`) com WAF + ACM. OIDC via Keycloak para autenticação de usuários finais. |
| Staging | ✅ Namespace `staging-data-hatch-etl` |
| Produção | ⏳ URL `hatch.prod.alvocard.com.br` (pós Fase 5) |
| Custo | Compute incluído nos nós EC2 |

---

## 9. MAPA RESUMIDO: STAGING vs PRODUÇÃO

| Componente | Staging | Produção | Diferença Principal |
|-----------|---------|----------|---------------------|
| EKS Control Plane | ✅ | ✅ compartilhado | Mesmo cluster |
| Karpenter | ✅ | ✅ compartilhado | Prod: 24×7 / Staging: 8h/dia útil |
| EC2 Nodes | ✅ ~8 nós (peak) | ⏳ +9 nós 24×7 | Prod sempre ligado |
| RDS PostgreSQL | ✅ databases `*_staging` (shared) | ✅ databases `*_prod` (shared, Multi-AZ) | 1 instância t3.medium, databases isolados — Mesa Técnica |
| Redis | ✅ 1 replica (CRD `redis-staging`) | ⏳ 3 replicas Sentinel (CRD `redis-prod`) | DEDICADO por env — BACEN/LGPD obrigatório |
| RabbitMQ | ✅ VHost `/staging` | ⏳ VHost `/prod` | 1 cluster, VHosts isolados — Mesa Técnica |
| NAT Gateway | ✅ 2 AZs (validar) | ✅ 2 AZs obrigatório | Prod: Multi-AZ obrigatório |
| ALB | ✅ 4 (sem WAF em 2) | ⏳ 2 novos (public+internal) | Prod: todos com WAF |
| WAF | ✅ Count (não bloqueia) | ⏳ Block + Bot Control | Prod: 6 regras Block |
| Route53 | ❌ | ⏳ apex `alvocard.com.br` (Fase 5) | Estratégia: 1 zona apex, NS no registrar (1x) |
| ACM | ⚠️ CA interna | ⏳ Wildcards `*.alvocard.com.br` + `*.prod.*` | Prod: browser trust, validação DNS automática |
| VPN FortiGate | ❌ | ⏳ Fase 6 (site-to-site) | ~$37/mês — decisão definitiva 2026-03-18 |
| Vault | ✅ 1 replica | ⏳ 3 replicas HA | Prod: HA |
| ESO | ✅ 11+ SecretSynced | ⏳ ClusterSecretStore prod | Prod: Vault prod |
| cert-manager | ✅ | ✅ compartilhado | Mesmo |
| Keycloak | ✅ realm staging | ⏳ realm prod + URL pública | Prod: HTTPS real, OIDC funcional |
| Kyverno | ✅ | ✅ compartilhado | Policies se aplicam por namespace |
| Network Policies | ⚠️ parcial (5 namespaces sem) | ⏳ completo | **Urgente nos dois ambientes** |
| GitLab CE | ✅ v18.9.1 compartilhado | ✅ compartilhado | Mesmo namespace |
| Harbor | ✅ | ⏳ HA | Prod: HA + S3 prod |
| ArgoCD | ✅ | ⏳ HA | Prod: 2 servers + 3 controllers |
| SonarQube | ✅ | ⏳ ALB internal | Prod: apenas via VPN |
| Backstage | ✅ port-forward | ⏳ VPN | Prod: acesso via VPN |
| External-DNS | ❌ | ⏳ Fase 4 | Staging: DNS manual |
| Prometheus | ✅ 30d | ⏳ 30d | Prod: PVC maior |
| Grafana | ✅ | ⏳ VPN only | Prod: acesso via VPN |
| Loki | ✅ 7d | ⏳ 30d | Prod: retenção maior |
| Tempo | ✅ | ⏳ 14d | Prod: retenção maior |
| OTel Collector | ✅ | ⏳ | Prod: Fase 4 |
| Linkerd (mTLS) | ✅ Phase 2 em progresso | ⏳ Fase 6 (completo) | Prod: todos os namespaces |
| Velero | ✅ schedules ativos | ⏳ Fase 6 | Prod: S3 bucket dr separado |
| VPA | ✅ recomendação | ⏳ Fase 6 | Prod: enforcement após 30d |
| FinOps Lambda | ✅ staging only | ✅ excluído (prod 24×7) | Prod não sofre shutdown |

---

## 10. PREVISÃO DE CUSTOS — RESUMO EXECUTIVO

> Análise completa produzida pelo FinOps Specialist. Preços us-east-1, março 2026, on-demand.

### Baseline Atual (Staging com FinOps)

| Categoria | $/mês |
|-----------|-------|
| Compute (EKS + ~8 nós, 24.1% uptime) | $131.60 |
| Database (RDS staging, 24.1% uptime) | $4.10 |
| Storage (EBS + S3) | $14.46 |
| Network (NAT + 4 ALBs + egress) | $34.87 |
| Security (WAF staging) | $11.00 |
| Managed (Lambda + CloudWatch) | $6.00 |
| **TOTAL STAGING COM FINOPS** | **~$202/mês** |

### Custo Incremental por Fase (Produção)

| Fase | Componentes | Incremento |
|------|------------|-----------|
| Fase 1 | Correções (WAF Block, providers TF) | $0 |
| Fase 2 | Vault HA + ESO + Keycloak prod | +$67/mês |
| Fase 3 | ArgoCD + Harbor + SonarQube prod | +$107/mês |
| Fase 4 | Observabilidade + WAF prod + External-DNS | +$125/mês |
| Fase 5 | Route53 + ACM + 2 ALBs prod | +$44/mês |
| Fase 6 | Velero + Linkerd overhead + VPA | +$38/mês |
| Fase 7 (sem VPN) | Backstage prod | +$32/mês |
| Fase 7 (com VPN AWS) | + AWS Client VPN | +$296/mês |
| **NAT Multi-AZ (obrigatório)** | +NAT segunda AZ | **+$38/mês** |

### Custo Total Pós Go-Live

| Cenário | $/mês | $/ano | Observação |
|---------|-------|-------|------------|
| Staging only (atual) | ~$202 | ~$2.424 | Baseline hoje |
| Pós Fase 7 SEM VPN + NAT Multi-AZ | ~$651 | ~$7.812 | |
| **Pós Fase 7 AWS Client VPN + NAT Multi-AZ** | **~$943** | **~$11.316** | Cenário documentado |
| **Pós Fase 7 Tailscale + NAT Multi-AZ** | **~$710** | **~$8.520** | **Recomendado FinOps** |
| Cenário otimizado (Tailscale + Reserved + Spot) | ~$600 | ~$7.200 | 6 meses pós go-live |

### 3 Decisões Financeiras de Alto Impacto

| Decisão | Opção A | Opção B | Diferença anual |
|---------|---------|---------|----------------|
| **VPN** | AWS Client VPN ($263/mês) | Tailscale ($30/mês para 5 users) | **R$ 16.800/ano** |
| **NAT Gateway** | Manter Single-AZ (risco SLA) | Adicionar 2ª AZ ($38/mês) | +$456/ano (obrigatório) |
| **RDS Reserved** | On-demand $127/mês | Reserved 1 ano $80/mês | **-$564/ano** |

---

## 11. GAPS IDENTIFICADOS PELA MESA TÉCNICA

> Lista consolidada de inconsistências e gaps encontrados nos 3 documentos de demanda.

### GAPs de Cobertura (Staging não coberto pelos documentos)

| ID | Descrição | Impacto |
|----|-----------|---------|
| GAP-STG-01 | Staging sem domínio público `staging.alvocard.com.br` — docs não planejam isso | Sem HTTPS real em staging para demos e parceiros |
| GAP-STG-02 | Sem sequência de rollback para WAF Count→Block em staging (pode quebrar Harbor ou GitLab KAS) | Blackout de CI/CD ao habilitar Block |
| GAP-STG-03 | Network Policies dos docs aplicam nos namespaces `staging-platform-*` AGORA, não nos `prod-*` futuros | Risco de bloqueio inadvertido em staging |
| GAP-STG-04 | Velero restore test (V-010) não endereçado nos 3 docs novos | DR não validado no ambiente ativo |
| GAP-STG-05 | External-DNS não planejado para staging | DNS manual em staging continua após go-live prod |

### Inconsistências Técnicas (entre os 3 documentos)

| ID | Inconsistência | Ação Necessária |
|----|---------------|----------------|
| INC-01 | `data.aws_subnets.public` ausente no `prod/main.tf` — Fase 5 falha no plan | Adicionar data source antes da Fase 5 |
| INC-02 | 2 NAT Gateways já existem (vpc-reverse-engineered) — risco pode ser menor que documentado | Confirmar `aws ec2 describe-nat-gateways` |
| INC-03 | GAP-P0-07 superdimensionado — `helm`, `kubernetes`, `kubectl` providers já existem no main.tf prod | Apenas `keycloak` e `vault` providers realmente faltam |
| INC-04 | GAP-P0-08 superdimensionado — variables.tf e tfvars prod existem para módulos atuais | Gap real é para variáveis das fases 2-7 |
| **INC-05** | **VPN TF usa `certificate-authentication` mas arquitetura descreve SAML — mutuamente exclusivos** | **Decisão obrigatória antes da Fase 7** |
| INC-06 | `namespace = "gitlab"` no prod/main.tf mas cluster usa `staging-platform-gitlab` | Corrigir antes de qualquer plan de prod |
| INC-07 | Custo VPN: $220/mês (Doc segurança) vs $265/mês (Doc VPN) — inconsistência entre docs | Usar $265/mês como referência correta |

### Dependências AWS Não Documentadas

| ID | Dependência | Criticidade |
|----|------------|------------|
| DEP-01 | `data "aws_subnets" "public"` ausente no main.tf prod | CRITICO — Fase 5 falha |
| DEP-02 | IAM IRSA do AWS LB Controller — precisa de permissão na zona prod | ALTO |
| DEP-03 | IAM IRSA do External-DNS — policy `route53:ChangeResourceRecordSets` na zona prod | ALTO |
| DEP-04 | IAM Identity Center: ninguém verificou se está habilitado | ALTO — bloqueia VPN Fase 7 |
| DEP-05 | Security Groups para ALBs prod (`alb_public_prod`, `alb_internal_prod`) — não documentados | ALTO — TF falha |
| DEP-06 | S3 bucket para ALB access logs — output do módulo não confirmado | MÉDIO |
| DEP-07 | KMS encryption para logs CloudWatch WAF (BACEN BCB 85/2021) | MÉDIO — compliance |
| DEP-08 | ACM wildcard NÃO pode ser certificado de servidor VPN — PKI dedicada obrigatória | CRITICO — VPN falha |

### Gaps de Compliance BACEN BCB 85/2021

| ID | Gap | Ação |
|----|-----|------|
| BACEN-01 | Logs WAF/VPN em CloudWatch (90d) sem exportação para S3 (5 anos) | Adicionar S3 lifecycle: CloudWatch → S3 → Glacier após 1 ano |
| BACEN-02 | CloudTrail não mencionado em nenhum dos 3 documentos | Verificar CloudTrail multi-region ativo na conta 891377105802 |
| BACEN-03 | K8s Audit Logs (EKS) não configurados | Habilitar auditoria EKS → CloudWatch → S3 |
| BACEN-04 | RDS pgaudit (PostgreSQL audit log) não mencionado | Habilitar pgaudit em prod para DDL/DML de dados de clientes |
| BACEN-05 | RBAC K8s para namespaces prod não documentado — quem é cluster-admin? | Auditoria RBAC antes do go-live: `kubectl auth can-i --list` |

---

## 12. PRÓXIMAS AÇÕES RECOMENDADAS

### P0 — Fazer Antes de Qualquer Apply Prod

1. **Corrigir `data "aws_subnets" "public"` em `prod/main.tf`** — sem isso Fase 5 falha
2. **Decidir VPN: mutual TLS (agora) vs SAML (pós Fase 5)** — atualizar TF do módulo client-vpn conforme decisão
3. **Corrigir namespace GitLab no TF prod** — `namespace = "staging-platform-gitlab"` (não `"gitlab"`)
4. **Definir e codificar SGs para ALBs prod** — regras para ALB public (80+443 aberto) e ALB internal (somente CIDR VPN 10.200.0.0/16)
5. **Mudar WAF Count→Block em staging** + associar WAF a gitlab-staging e keycloak-staging ALBs
6. **Confirmar CNI antes de aplicar Network Policies** — `kubectl get pods -n kube-system | grep -E "cilium|aws-node"`

### P1 — Sprint Seguinte

7. Confirmar NAT Gateways: `aws ec2 describe-nat-gateways --filter Name=vpc-id,Values=vpc-0b1396a59c417c1f0`
8. Verificar IAM Identity Center: `aws sso-admin list-instances --profile k8s-platform-prod`
9. Verificar RDS Multi-AZ: `aws rds describe-db-instances --profile k8s-platform-prod --query 'DBInstances[*].[DBInstanceIdentifier,MultiAZ]'`
10. Adicionar exportação logs WAF + VPN → S3 (5 anos, BACEN)
11. Verificar CloudTrail ativo na conta
12. Antecipar mTLS Linkerd para Keycloak e Vault (antes da Fase 6, na Fase 3)
13. Executar restore test Velero (V-010 pendente desde 2026-03-05)

### P2 — Médio Prazo

14. Avaliar Tailscale vs AWS Client VPN antes da Fase 7 (R$ 16.800/ano de diferença)
15. Reduzir validade CA VPN de 3.650 para 1.095 dias (3 anos)
16. RBAC K8s audit para namespaces prod (kubectl auth can-i --list por ServiceAccount)
17. Harbor Kyverno ImagePolicy: bloquear pull de imagens com CVE crítico em prod
18. RDS Reserved Instance após 30d de prod estável (-$564/ano)

---

*Documento produzido pela Mesa Técnica em 2026-03-18*
*Agentes: AWS Specialist ☁️ + Security & Compliance 🔐 + FinOps 💰*
*Referências: 2026-03-18-plano-ambiente-producao.md | 2026-03-18-setup-dominio-producao.md | 2026-03-18-setup-vpn-acesso-publico.md*
*ADRs: ADR-008, ADR-046, ADR-050, ADR-059, ADR-070, ADR-086, ADR-090, ADR-095, ADR-098, ADR-099, ADR-102, ADR-105*
