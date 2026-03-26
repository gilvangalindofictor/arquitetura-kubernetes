# Plano de Estruturação do Ambiente de Produção

**Data:** 2026-03-18 | **Status:** FASES 1-4 CONCLUIDAS (2026-03-19) | **Cluster:** k8s-platform-prod
**Conta AWS:** 891377105802 | **Região:** us-east-1 | **VPC:** vpc-0b1396a59c417c1f0

---

## Resumo Executivo

- **Infraestrutura parcialmente provisionada:** prod environment possui RDS Multi-AZ, Redis 3 replicas, RabbitMQ 3 replicas e GitLab (compartilhado) no Terraform — mas sem WAF, sem domínio público, sem VPN, sem Vault/ESO, sem observabilidade, sem ArgoCD, sem Harbor de produção
- **Bloqueador externo crítico:** Delegação DNS de `prod.alvocard.com.br` para Route53 depende de ação do gestor do domínio no registrar — nenhum apply de prod é efetivo sem isso
- **GAP P0 de segurança:** Certificados ACM de produção não existem; todo acesso atual usa CA interna sem browser trust; 3 regras WAF em modo Count (não bloqueiam) no staging
- **Drift no Terraform:** Multi-AZ RDS está declarado no código mas o recurso real precisa ser validado; providers keycloak/vault/helm ausentes no `main.tf` prod para os módulos faltantes; ~205 recursos a criar em 7 fases
- **Dependências sequenciais críticas:** Domínio → Certificados → Keycloak público → VPN → serviços internos — nenhuma fase pode ser pulada

---

## Estado Atual da Infraestrutura

### Cluster EKS

| Item | Valor |
|------|-------|
| Nome | `k8s-platform-prod` (cluster compartilhado staging + prod) |
| Conta | 891377105802 |
| Região | us-east-1 |
| VPC | vpc-0b1396a59c417c1f0 (CIDR 10.0.0.0/16) |
| Subnets privadas | 10.0.128.0/20, 10.0.144.0/20 |
| Último apply TF (prod) | 2026-02-09 |
| Recursos TF prod ativos | ~70 |
| Recursos TF prod pendentes | ~205 (7 fases) |
| Node groups | Karpenter gerenciado (provisionamento dinâmico) |

### Rede (VPC, Subnets, NAT)

| Componente | Status | Observação |
|------------|--------|------------|
| VPC | Running | vpc-0b1396a59c417c1f0 |
| Subnets privadas (2 AZs) | Running | us-east-1a, us-east-1b |
| Internet Gateway | Running | compartilhado |
| NAT Gateway | Running — RISCO | Single-AZ (ver Riscos) |
| Route Tables | Running | |
| ALB `k8s-platformstaging-00e0ecf3b4` | internet-facing, active | WAF associado |
| ALB `k8s-gitlabstaging-da5a4e8c6d` | internet-facing, active | SEM WAF |
| ALB `k8s-stagingp-keycloak-0dbafff841` | internet-facing, active | SEM WAF |
| ALB `k8s-backstagestaging-c827d564e5` | internal, active | Backstage |
| ALBs de produção | NAO EXISTEM | a criar (fases 2-4) |

### Data Services (RDS, Redis, RabbitMQ)

| Serviço | Config Prod (TF declarado) | Config Staging | Status |
|---------|---------------------------|----------------|--------|
| RDS PostgreSQL | db.t3.medium, 100GB, Multi-AZ=true, deletion_protection=true | db.t3.micro, 20GB, Multi-AZ=false | Provisionado — validar Multi-AZ real |
| Redis | 3 replicas + Sentinel, 10Gi/replica | 1 replica, 5Gi | Provisionado |
| RabbitMQ | 3 replicas quorum, 10Gi/replica | 1 replica, 5Gi | Provisionado |
| Storage class | gp3 | gp3 | OK |
| S3 buckets | 30d lifecycle | 7d lifecycle | Provisionado |

**GAP P0 — Drift RDS Multi-AZ:** O TF declara `multi_az = true` mas o recurso real pode estar Single-AZ (apply 2026-02-09 com erros). Verificar com `aws rds describe-db-instances --profile k8s-platform-prod` antes de qualquer apply.

> **Resolução 2026-03-24**: multi_az=false aplicado via DEC-2026-03-24-RDS (defer para go-live). Drift TF corrigido em environments/prod/main.tf.

### Serviços Compartilhados (GitLab, Harbor)

| Serviço | Namespace | Status | Versão | Observação |
|---------|-----------|--------|--------|------------|
| GitLab CE | `staging-platform-gitlab` (compartilhado) | Running | 8.7.0 (Helm chart) | Sem TLS real; domínio fictício staging.internal |
| GitLab Runners | `staging-platform-gitlab` | 2/2 Running | — | Falso alarme CrashLoop resolvido |
| Harbor | `harbor-system` | Running | — | TLS via CA interna; sem HTTPS público |
| GitLab KAS | `staging-platform-gitlab` | Running | — | |

**GAP:** GitLab versão 8.7.0 (muito acima do que existe atualmente — verificar se é versão do Helm chart ou da imagem). Sem domínio público, sem WAF, sem ACM.

### Segurança (Vault, ESO, Kyverno, Linkerd, WAF)

| Componente | Namespace | Status | Observação |
|------------|-----------|--------|------------|
| Vault | `staging-security-vault` | Running | Network Policy ativa; sem URL pública prod |
| ESO (External Secrets Operator) | — | Running | Integrado ao Vault |
| Kyverno | — | Running | Policies ativas |
| Linkerd Control Plane | — | Running | Phase 2 (injeção de workloads) em progresso |
| Linkerd Viz | — | Running | |
| WAF WebACL | `waf-k8s-platform-prod-staging` | Active | Associado apenas ao ALB platform-staging |
| cert-manager | — | Running | CA interna; sem ACME/DNS-validation público |
| External-DNS | — | **NAO INSTALADO** | DNS manual hoje |
| AWS Client VPN | — | **NAO EXISTE** | Acesso via port-forward + windows-hosts.txt |

---

## Gaps Identificados — Produção

### P0 — Bloqueadores (obrigatórios antes do go-live)

| GAP-ID | Descrição | Criticidade | Bloqueador de |
|--------|-----------|-------------|---------------|
| **GAP-P0-01** | Sem hosted zone pública Route53 `prod.alvocard.com.br` | CRITICO | Tudo que depende de DNS real |
| **GAP-P0-02** | Sem certificado ACM prod (atual é IMPORTED CA interna, sem browser trust) | CRITICO | HTTPS real, Keycloak OIDC, GitLab |
| **GAP-P0-03** | Delegação NS `prod.alvocard.com.br` não feita no registrar | CRITICO — EXTERNO | Validação ACM, DNS público |
| **GAP-P0-04** | ~~Drift RDS Multi-AZ~~ **RESOLVIDO 2026-03-19** — Mesa tecnica validou estrategia hibrida (1 RDS shared, Redis dedicado, RabbitMQ VHosts). Ver secao "Estrategia de Dados". | ~~CRITICO~~ RESOLVIDO | Disponibilidade 99.95% |
| **GAP-P0-05** | ~~WAF regras 30/40/50 em modo Count~~ **RESOLVIDO 2026-03-19** — Todas regras em Block + 3 ALBs internet-facing associados ao WAF. Zero drift. | ~~CRITICO~~ RESOLVIDO | Seguranca pos-go-live |
| **GAP-P0-06** | ~~ALBs gitlab-staging e keycloak-staging sem WAF~~ **RESOLVIDO 2026-03-19** — 3/3 ALBs internet-facing protegidos (GitLab + Keycloak + platform). | ~~CRITICO~~ RESOLVIDO | Seguranca imediata |
| **GAP-P0-07** | ~~Providers ausentes no main.tf prod~~ **RESOLVIDO 2026-03-19** — 4 providers + OIDC data source + namespace fixes + 14 variables sensiveis adicionados. | ~~CRITICO~~ RESOLVIDO | Apply das fases 2-7 |
| **GAP-P0-08** | ~~Variaveis de modulos ausentes~~ **RESOLVIDO 2026-03-19** — variables.tf e terraform.tfvars prod completos. BUG fix: postgresql module prefixo staging/ corrigido para var.environment. | ~~CRITICO~~ RESOLVIDO | Apply das fases 2-7 |

### P1 — Alta prioridade (sprint seguinte ao go-live)

| GAP-ID | Descrição | Criticidade | Bloqueador de |
|--------|-----------|-------------|---------------|
| **GAP-P1-01** | Vault sem URL pública prod → sem OIDC auth real no Vault prod | ALTO | VPN + Vault UI acesso |
| **GAP-P1-02** | ~~Network Policies ausentes~~ **PARCIAL 2026-03-19** — 24 policies em 5 namespaces (audit mode). Harbor 7 policies criadas. Falta enforcement mode. | ~~ALTO~~ PARCIAL | Seguranca lateral movement |
| **GAP-P1-03** | Sem AWS Client VPN → acesso interno via port-forward (operacional insustentável) | ALTO | Operação de produção |
| **GAP-P1-04** | External-DNS não instalado → registros DNS criados manualmente (drift propenso) | ALTO | Operação de DNS |
| **GAP-P1-05** | Linkerd Phase 2 incompleta → namespaces sem mTLS (argocd, gitlab, sonarqube, harbor) | ALTO | mTLS compliance |
| **GAP-P1-06** | ~~Vault prod sem modulo Terraform~~ **RESOLVIDO 2026-03-19** — Vault prod HA 3/3 Raft peers, KMS auto-unseal, K8s auth + policies + secrets seeded. Root token revogado. | ~~ALTO~~ RESOLVIDO | Secrets prod |
| **GAP-P1-07** | Sem Velero para backup/DR de prod | ALTO | RTO/RPO prod |
| **GAP-P1-08** | ~~Namespaces prod nao criados~~ **RESOLVIDO 2026-03-19** — 12 namespaces prod criados (DEC-074 convention). | ~~ALTO~~ RESOLVIDO | Deploy de aplicacoes prod |

---

## Estratégia de Dados — Decisão Mesa Técnica 2026-03-18

**Contexto:** Mesa técnica (AWS Specialist + TF Specialist + Security Specialist) validou a estratégia de isolamento de dados entre staging e produção em 2026-03-18. A decisão equilibra custo, compliance regulatório e separação de blast radius.

### Tabela de Decisão por Serviço

| Serviço | Estratégia | Instância / Config | Saving vs Alternativa | Fundamento |
| ------- | ---------- | ------------------ | --------------------- | ---------- |
| **PostgreSQL RDS** | **Shared — databases isolados por env** | db.t3.medium Multi-AZ, databases `staging_db` e `prod_db` separados, usuários com NOSUPERUSER/NOCREATEDB | **$12.81/mês** ($153.72/ano) vs 2 instâncias separadas | Databases isolados fornecem blast radius suficiente; custo de 2x instâncias não justificado neste porte |
| **Redis** | **Dedicado por env — OBRIGATÓRIO** | Staging: 1 replica, 512Mi, Redis Operator CRD independente. Prod: 3 replicas Sentinel, 2Gi, volatile-lru | **~$0 adicional** (in-cluster, nodes existentes) | **BACEN BCB 85/2021** Art. 4º §2º + **LGPD Art. 46** exigem segregação de dados de sessão/cache entre ambientes regulados |
| **RabbitMQ** | **2 clusters independentes (prod-data-rabbitmq + staging-data-infrastructure)** | Cluster staging: namespace `staging-data-infrastructure`; Cluster prod: namespace `prod-data-infrastructure` | Custo adicional mínimo (in-cluster) | BACEN BCB 85/2021 exige isolamento de ambientes; VHosts descartados (DEC-2026-03-24-RABBITMQ) |
| **GitLab** | **Shared — exceção documentada** | 1 instância compartilhada, namespace `staging-platform-gitlab` | — | ADR-046: GitLab CE único para staging + prod; acesso por grupos/projetos RBAC Keycloak |

### Detalhamento por Serviço

#### PostgreSQL RDS — Shared Multi-AZ (db.t3.medium)

```text
Instância:      k8s-platform-prod-postgresql (única)
Databases:      staging_db    → staging_user  (NOSUPERUSER, NOCREATEDB)
                prod_db       → prod_user     (NOSUPERUSER, NOCREATEDB)
Multi-AZ:       true (obrigatório — ADR-050)
Custo:          $124.18/mês (db.t3.medium Multi-AZ, 100GB gp3)
Saving:         $12.81/mês ($153.72/ano) vs 2 instâncias separadas
```

**Controles de segurança obrigatórios — PostgreSQL:**

- `NOSUPERUSER` e `NOCREATEDB` em todos os usuários de aplicação (staging e prod)
- `REVOKE pg_monitor FROM staging_user` — staging não monitora databases de prod
- `DROP EXTENSION dblink` — previne tunneling cross-database
- `pgaudit` configurado por role em prod: auditoria de DDL + DML em `prod_db`
- Row-Level Security (RLS) avaliada para tabelas com dados regulados (LGPD Art. 46)

#### Redis — Dedicado por Env (Obrigatório Regulatório)

```text
RAZÃO REGULATÓRIA: BACEN BCB 85/2021 Art. 4º §2º + LGPD Art. 46
  → Dados de sessão, tokens e cache de autenticação NÃO podem ser
    compartilhados entre ambientes com classificações de risco distintas.

Staging Redis:
  replicas:     1
  memory:       512Mi
  policy:       allkeys-lru
  operator:     Redis Operator CRD (independente do prod)
  namespace:    staging-data-services

Prod Redis:
  replicas:     3 (Sentinel HA)
  memory:       2Gi
  policy:       volatile-lru
  namespace:    prod-data-services

Custo adicional: ~$0 (in-cluster, nodes já provisionados pelo Karpenter)
```

#### RabbitMQ — 2 Clusters Independentes

> **Atualização 2026-03-24**: Estratégia VHosts descartada. Adotados 2 clusters independentes (DEC-2026-03-24-RABBITMQ). Ver ADR-062 Revisão 2026-03-24.

```text
Cluster staging: staging-data-infrastructure  → namespace: staging-data-infrastructure
Cluster prod:    prod-data-rabbitmq            → namespace: prod-data-infrastructure

Rationale:
  - Blast radius isolado: falha em staging não afeta prod
  - BACEN BCB 85/2021: isolamento de ambientes regulatório obrigatório
  - Ciclo de vida independente: upgrades sem janela de manutenção cruzada
```

### Impacto FinOps da Decisão

| Item | Custo sem decisão | Custo com decisão | Delta mensal |
| ---- | ----------------- | ----------------- | ------------ |
| 2x RDS separados (alternativa rejeitada) | $136.99/mês | — | — |
| 1x RDS shared Multi-AZ (decisão adotada) | — | $124.18/mês | **-$12.81/mês** |
| Redis (in-cluster, ambos os envs) | $0 | $0 | $0 |
| RabbitMQ shared VHosts | $0 | $0 | $0 |
| **Total saving vs alternativa** | | | **$12.81/mês ($153.72/ano)** |

---

### P2 — Médio prazo

| GAP-ID | Descrição | Criticidade |
|--------|-----------|-------------|
| **GAP-P2-01** | Entra ID Federation não implementada (ADR-095) | MÉDIO |
| **GAP-P2-02** | Bot Control WAF não configurado | MÉDIO |
| **GAP-P2-03** | VPA não provisionado para prod | MÉDIO |
| **GAP-P2-04** | Backstage prod não existe (apenas staging) | MÉDIO |
| **GAP-P2-05** | SonarQube sem Network Policy e sem URL pública prod | MÉDIO |
| **GAP-P2-06** | Keycloak session lifetime não ajustada (risco R-100, ADR-095) | MÉDIO |

---

## Plano de Implementação — 7 Fases

### Fase 1 — Correções Imediatas (sem bloqueadores externos) -- CONCLUIDA 2026-03-19

**Pre-requisitos:** Nenhum. Pode ser executada agora.

**Objetivo:** Corrigir GAPs criticos no estado atual sem precisar de dominio publico.

**STATUS: CONCLUIDA 2026-03-19** — WAF 3/3 ALBs protegidos (Block mode), 24 NetworkPolicies em 5 namespaces (audit mode, ADR-070), TF prod 4 providers + OIDC data source + 14 variables, BUG fix postgresql module prefixo staging/ para var.environment, DNS WSL2 resolv.conf corrigido, credenciais estaticas expiradas removidas.

| Ação | Recurso | Estimativa |
|------|---------|------------|
| Verificar drift RDS Multi-AZ (`aws rds describe-db-instances`) | `module.postgresql_prod` | 30 min |
| Mudar WAF regras 30/40/50 de Count → Block no staging | `waf-k8s-platform-prod-staging` | 1h |
| Associar WAF existente aos ALBs gitlab-staging e keycloak-staging | Security Group + WAF association | 1h |
| Adicionar providers ausentes (`keycloak`, `vault`) ao `main.tf` prod | `environments/prod/main.tf` | 2h |
| Completar variáveis de módulos em `variables.tf` + `terraform.tfvars` prod | `environments/prod/variables.tf` | 2h |
| Iniciar `terraform plan` prod para mapear delta completo | `environments/prod/` | 1h |
| Aplicar Network Policies ADR-070 Marco 4 em modo audit | `domains/security/network-policies/marco4/` | 2h |

**Estimativa total:** 1 dia (8-10h)
**Resultado esperado:** Zero drift TF, WAF em modo Block, providers completos, plan limpo

---

### Fase 2 — Segredos e Identidade (Vault + ESO + Keycloak) -- CONCLUIDA 2026-03-19

**Pre-requisitos:** Fase 1 concluida; dominio DNS NAO necessario para configuracao interna

**Objetivo:** Provisionar Vault prod, ESO, e Keycloak prod com configuracoes de producao.

**STATUS: CONCLUIDA 2026-03-19** — 12 namespaces prod criados (DEC-074 convention). 4 modulos parametrizados: vault, external-secrets, keycloak, vault-config (var.environment). Vault prod HA 3/3 Raft peers, KMS auto-unseal, root token revogado. ESO prod ClusterSecretStore vault-backend-prod (Valid, ReadWrite). Vault Config prod K8s auth + policies + secrets seeded. Keycloak prod HA 2/2 Running (v26.5.1, RDS prod). Kyverno inject-corporate-labels-prod-namespaces policy criada.

**NOTA:** Keycloak prod deployado via Helm direto (TF bloqueado por postgresql provider VPC-only constraint). Codificar no TF quando tunnel VPC disponivel.

| Ação | Módulo TF | Estimativa |
|------|-----------|------------|
| Criar namespaces prod no cluster (`prod-platform-keycloak`, `prod-security-vault`, etc.) | `kubectl_manifest` namespace resources | 1h |
| Provisionar Vault prod (HA, 3 replicas, backend DynamoDB ou Raft) | `modules/vault` | 4h |
| Provisionar ESO prod + ClusterSecretStore apontando para Vault prod | `modules/external-secrets` | 2h |
| Provisionar Keycloak prod (HA, 2+ replicas, PostgreSQL PROD RDS) | `modules/keycloak` | 4h |
| Configurar realm prod no Keycloak via Terraform | `modules/keycloak-clients` | 3h |
| Criar ExternalSecrets para todos os workloads prod | manifests/external-secrets | 3h |

**Estimativa total:** 2 dias
**Resultado esperado:** Vault prod rodando, ESO sincronizando secrets, Keycloak realm prod configurado (sem URL pública ainda)

---

### Fase 3 — GitOps e Qualidade (ArgoCD + Harbor + SonarQube) -- CONCLUIDA 2026-03-19

**Pre-requisitos:** Fase 2 concluida (Vault + ESO funcionando para injetar secrets nos deployments)

**Objetivo:** Plataforma de CI/CD e qualidade de producao.

**STATUS: CONCLUIDA 2026-03-19** — ArgoCD prod 10/10 Running (HA: 3 app-controller + 2 server + 2 repo + 2 appset + 1 redis). Harbor prod 9/9 Running (core 2/2 + registry 2/2 + portal 2/2 + jobservice + exporter + trivy). SonarQube prod 1/1 Running (imagem via ECR mirror — Docker Hub rate limit workaround).

**NOTA:** Deploy via Helm direto (TF bloqueado por postgresql provider VPC-only). NetworkPolicies Harbor: 7 policies criadas. Mesa tecnica Docker Hub rate limit: ECR Pull-Through Cache recomendado para longo prazo.

| Ação | Módulo TF | Estimativa |
|------|-----------|------------|
| Provisionar ArgoCD prod (HA, 2 replicas server + 3 application-controller) | `modules/argocd` | 3h |
| Configurar ArgoCD AppProject prod + RBAC via Keycloak OIDC | `modules/argocd` + Helm values | 2h |
| Provisionar Harbor prod (HA, PostgreSQL PROD, Redis PROD, S3 PROD) | `modules/harbor` | 4h |
| Configurar Harbor com Keycloak OIDC | Harbor Helm values | 2h |
| Provisionar SonarQube prod (PostgreSQL PROD) | `modules/sonarqube` | 2h |
| Aplicar Network Policies Marco 4 em modo enforcement (argocd, gitlab, harbor, sonarqube) | `domains/security/network-policies/marco4/` | 2h |

**Estimativa total:** 2 dias
**Resultado esperado:** ArgoCD + Harbor + SonarQube rodando com auth via Keycloak, Network Policies ativas

---

### Fase 4 — Observabilidade (Prometheus + Loki + Tempo + OTel) -- CONCLUIDA 2026-03-19

**Pre-requisitos:** Fases 1-3 concluídas

**Objetivo:** Observabilidade completa em produção com retenção correta e WAF prod.

**STATUS: CONCLUIDA 2026-03-19** — kube-prometheus-stack prod 5/5 Ready (Prometheus, Grafana, Alertmanager, Operator, KSM). Loki prod 10/10 Ready (S3 backend k8s-platform-loki-prod-891377105802, IRSA LokiS3Role). Tempo prod 12/12 Ready (S3 backend k8s-platform-tempo-prod-891377105802, IRSA TempoS3Role). OTel Collector prod 2/2 Ready. Total 29/29 core pods + 6 loki-canary Pending (non-blocking, DaemonSet nodeAffinity). Cluster autoscaler workloads 5→6 nodes. Node-exporter desabilitado em prod (staging ja cobre todos os 13 nodes via hostNetwork — sem conflito de porta).

**NOTA:** WAF Bot Control e External-DNS adiados para Fase 5 (sem ALBs/hosted zone prod ainda). ECR Pull-Through Cache regra criada mas credenciais Docker Hub invalidas (pendente PAT valido).

| Ação | Módulo TF | Estimativa |
|------|-----------|------------|
| Provisionar kube-prometheus-stack prod (retenção 30d, PVC maior) | `modules/kube-prometheus-stack` | 3h |
| Provisionar Loki prod (S3 backend, retenção 30d) | `modules/loki` | 2h |
| Provisionar Tempo prod (retenção 14d) | `modules/tempo` | 2h |
| Provisionar OpenTelemetry Collector prod | `modules/opentelemetry-collector` | 2h |
| ~~Criar WAF WebACL prod (novo, com regras em Block, Bot Control)~~ | ~~`modules/waf`~~ | ~~2h~~ → **ADIADO Fase 5** |
| ~~Instalar External-DNS~~ | ~~Helm + IAM IRSA~~ | ~~2h~~ → **ADIADO Fase 5** |
| Configurar alertas SLO prod (latência P99, error rate, disponibilidade) | Prometheus rules | 3h |

**Estimativa total:** 2 dias
**Resultado esperado:** Stack de observabilidade prod completa, WAF prod com regras em Block, External-DNS automatizando registros

---

### Fase 5 — DNS + Certificados + Domínio + WAF prod + External-DNS (DEPENDE DE AÇÃO EXTERNA)

**Pre-requisitos:** Gestor de domínio executa checklist do Documento 2; Fases 1-4 concluídas

**Objetivo:** Tornar os serviços acessíveis via `*.prod.alvocard.com.br` com HTTPS real. Inclui WAF Bot Control e External-DNS (adiados da Fase 4 por dependencia de ALBs/hosted zone prod).

| Ação | Módulo TF | Estimativa |
|------|-----------|------------|
| Criar hosted zone Route53 `prod.alvocard.com.br` | `aws_route53_zone.prod` | 15 min |
| Enviar 4 NS records para gestor de domínio | — (procedimento manual) | 30 min (gestor) |
| Aguardar propagação DNS (dig NS prod.alvocard.com.br retornar NS corretos) | — | 5-60 min |
| Criar certificado ACM wildcard `*.prod.alvocard.com.br` + validação DNS | `aws_acm_certificate.prod_wildcard` | 15-30 min |
| Criar ALBs de produção (public + internal) com WAF + ACM | `aws_lb.platform_prod*` | 1h |
| Criar registros DNS Route53 (alias A para ALBs) | `aws_route53_record.*` | 1h |
| Atualizar Keycloak prod com URL pública + KC_HOSTNAME | Helm values + TF | 2h |
| Atualizar Ingresses de todos os serviços prod (annotations ACM + WAF) | manifests prod | 3h |
| Instalar ExternalDNS e validar automação | Helm + IAM | 1h |
| Testar HTTPS e OIDC discovery endpoint | `curl` + `dig` | 1h |

**Estimativa total:** 1 dia (+ tempo de propagação DNS)
**Resultado esperado:** Todos os serviços prod com HTTPS real, certificados válidos, OIDC funcional

---

### Fase 6 — Resiliência e DR (Velero + Linkerd + VPA)

**Pre-requisitos:** Fase 5 concluída (ambiente prod acessível)

**Objetivo:** Alta disponibilidade, DR, e mTLS completo.

| Ação | Módulo TF | Estimativa |
|------|-----------|------------|
| Provisionar Velero prod (S3 bucket dr, schedule diário, retenção 7d) | `modules/velero-helm` | 2h |
| Completar Linkerd Phase 2: injetar todos os namespaces prod | `domains/service-mesh/infra/linkerd/namespace-annotations/` | 3h |
| Provisionar VPA prod (recomendações de resources) | `modules/vpa` | 1h |
| Configurar PodDisruptionBudgets para todos os serviços críticos | manifests PDB | 2h |
| Testar DR: backup + restore de namespace prod de teste | Velero CLI | 2h |
| Validar mTLS via Linkerd viz (tap) para todos os namespaces prod | Linkerd CLI | 1h |

**Estimativa total:** 1.5 dias
**Resultado esperado:** Velero com backups automáticos, mTLS em todos os namespaces prod, VPA com recomendações

---

### Fase 7 — VPN e IDP (VPN + Backstage Prod)

**Pre-requisitos:** Fase 5 concluída (Keycloak com URL pública funcionando para SAML/OIDC)

**Objetivo:** Acesso seguro para equipe técnica e IDP de produção.

| Ação | Módulo TF | Estimativa |
|------|-----------|------------|
| Criar módulo `modules/client-vpn/` | novo módulo | 4h |
| Gerar PKI VPN (CA root + certificados) | openssl/easy-rsa | 1h |
| Upload CA VPN para ACM | `aws acm import-certificate` | 30 min |
| Provisionar AWS Client VPN Endpoint (2 AZs) | `modules/client-vpn` | 2h |
| Configurar authorization rules (platform-admins → 10.0.0.0/16) | `aws_ec2_client_vpn_authorization_rule` | 1h |
| Configurar Keycloak SAML para IAM Identity Center (VPN auth) | Keycloak admin | 3h |
| Distribuir .ovpn para engenheiros | — | 1h |
| Provisionar Backstage prod (Helm + Keycloak OIDC) | `modules/backstage` | 4h |
| Migrar ALBs de serviços internos para `internal` scheme (somente via VPN) | manifests prod | 2h |

**Estimativa total:** 2 dias
**Resultado esperado:** VPN funcional com auth Keycloak SAML, Backstage prod, serviços internos acessíveis apenas via VPN

---

## Grafo de Dependências

```
[EXTERNO] Gestor de Domínio (alvocard.com.br)
    │
    │ cria NS delegation prod.alvocard.com.br
    ▼
[FASE 1] Correções Imediatas (pode iniciar AGORA)
    │  ├─ Drift RDS fix
    │  ├─ WAF Count→Block
    │  ├─ Providers TF prod
    │  └─ Variables TF prod
    ▼
[FASE 2] Vault + ESO + Keycloak (sem URL pública)
    │  (Keycloak funciona internamente; URL pública vem na Fase 5)
    ▼
[FASE 3] ArgoCD + Harbor + SonarQube
    │  (dependem de Vault/ESO para secrets)
    ▼
[FASE 4] Observabilidade (Prometheus+Loki+Tempo+OTel) ✅ CONCLUIDA 2026-03-19
    │  (WAF prod + External-DNS movidos para Fase 5)
    ▼
[FASE 5] DNS + Certificados + ALBs prod + WAF prod + External-DNS  ← DEPENDE DO GESTOR EXTERNO
    │  (Route53 zona → NS delegation → ACM wildcard → ALBs → Ingresses)
    ▼
[FASE 6] Velero + Linkerd + VPA        [FASE 7] VPN + Backstage prod
    │  (paralelo após Fase 5)               │  (paralelo após Fase 5)
    ▼                                       ▼
                  [GO-LIVE PRODUÇÃO]
```

**Fases executáveis em paralelo:** 3 e 4 (parcialmente); 6 e 7 (pós Fase 5)
**Gargalo crítico:** Fase 5 é o único ponto de serialização por dependência externa

---

## Pré-Requisitos Críticos (Bloqueadores Externos)

| # | Pré-Requisito | Responsável | Ação Necessária | Impacto se não feito |
|---|---------------|-------------|-----------------|----------------------|
| 1 | Delegação NS `prod.alvocard.com.br` no registrar | **Gestor de domínio externo** | Criar 4 NS records no painel do registrar | ACM validation timeout → impossível criar certificado HTTPS real |
| 2 | Credenciais AWS SSO ativas (`k8s-platform-prod`) | Engenheiro DevOps | `aws sso login --profile k8s-platform-prod` | Nenhum apply TF possível |
| 3 | Decisão: domínio apex vs subdomínio | **Arquiteto / Gestor** | Confirmar estratégia `prod.alvocard.com.br` vs `*.alvocard.com.br` | Retrabalho de DNS e certificados se mudar depois |
| 4 | IAM Identity Center habilitado (para VPN SAML) | **AWS Admin / Gestor** | Verificar AWS Organizations + habilitar IAM Identity Center | VPN auth SAML não funciona sem IAM Identity Center |
| 5 | Política corporativa de certificados | **CISO / Compliance** | Confirmar se ACM (Amazon Trust Services) é aceito ou se precisa de CA corporativa | Pode mudar estratégia de certificados para certificado comercial (DigiCert/GlobalSign) |

---

## Riscos e Mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|-------|---------------|---------|-----------|
| **NAT Gateway Single-AZ:** Se o NAT Gateway estiver em apenas uma AZ, falha da AZ derruba todo o tráfego egress do cluster | ALTA | CRITICO | Verificar NAT gateways existentes; criar NAT Gateway na segunda AZ antes do go-live |
| **GitLab version drift:** GitLab declarado na versão 8.7.0 do Helm chart — verificar compatibilidade com versão de imagem e se há breaking changes na upgrade path | MÉDIA | ALTO | Executar `helm list -n staging-platform-gitlab`; mapear versão real e testar upgrade em staging primeiro |
| **Drift RDS Multi-AZ:** Apply de 2026-02-09 pode ter criado RDS Single-AZ a despeito do `multi_az = true` | ALTA | ALTO | `aws rds describe-db-instances --profile k8s-platform-prod` antes de qualquer apply — se Single-AZ, planejar modificação com janela de manutenção (pode causar failover ~3 min) |
| **ACM validation timeout:** Se NS delegation não estiver correto, ACM fica aguardando validação DNS e falha após 30 min | MÉDIA | MÉDIO | Validar `dig NS prod.alvocard.com.br` antes de criar ACM; usar `timeouts { create = "30m" }` no TF |
| **Keycloak OIDC redirect_uri mismatch:** Trocar de staging.internal para prod.alvocard.com.br sem atualizar todos os clients no Keycloak quebrará o SSO | ALTA | ALTO | Atualizar todos os Keycloak clients (gitlab, harbor, argocd, grafana, sonarqube) antes de alterar KC_HOSTNAME |
| **WAF falsos positivos em Harbor:** Regra OWASP em Block pode bloquear uploads de imagens Docker grandes (payloads multipart) | MÉDIA | MÉDIO | Monitorar CloudWatch WAF metrics por 48h no staging com Count antes de mudar para Block; adicionar `rule_action_override` se necessário |
| **GitLab KAS WebSocket timeout via WAF:** WAF pode encerrar conexões WebSocket do GitLab KAS por idle timeout | MÉDIA | MÉDIO | Adicionar `alb.ingress.kubernetes.io/target-group-attributes: stickiness.enabled=true` no Ingress KAS |
| **Custo VPN:** AWS Client VPN tem custo base de ~$220/mês independente de uso | BAIXA | MÉDIO | Avaliar Tailscale como alternativa (custo fixo previsível); implementar VPN apenas quando equipe atingir tamanho que justifique |
| **Linkerd mTLS breaking change:** Habilitar mTLS em namespaces que não foram testados pode causar erros 503 em conexões mTLS não configuradas | MÉDIA | ALTO | Usar modo audit do Linkerd antes de enforcement; testar por namespace em staging antes de prod |

---

## ADRs Aplicáveis

| ADR | Título | Impacto na Produção |
|-----|--------|---------------------|
| ADR-008 | TLS Strategy for ALB Ingresses | Padrão ACM + Route53 para todos os ingresses prod — certificado wildcard `*.prod.alvocard.com.br` |
| ADR-046 | Keycloak SSO Strategy | HA com 2+ replicas em prod; OIDC clients atualizados para URLs prod; HTTPS obrigatório |
| ADR-050 | Multi-AZ para Data Services | RDS Multi-AZ obrigatório; Redis com Sentinel; RabbitMQ quorum queues |
| ADR-059 | Karpenter para node provisioning | Nenhum node group fixo em prod — apenas Karpenter provisioners |
| ADR-070 | Network Policies Marco 4 | 20 políticas para argocd, sonarqube, keycloak, gitlab — aplicar antes do go-live |
| ADR-086 | Linkerd Service Mesh mTLS | Phase 2: injeção de todos os namespaces prod antes do go-live |
| ADR-090 | Velero DR Strategy | Backup diário, retenção 7d, restore testado trimestralmente |
| ADR-095 | Entra ID Identity Federation | Keycloak OIDC broker para Entra ID — implementar após Keycloak com URL pública |
| ADR-098 | DNS e Controle de Acesso (alvocard.com.br) | Estratégia de subdomínio delegado `prod.alvocard.com.br`; transição para apex quando estável |
| ADR-099 | WAF Strategy iPaaS | Regras em Block em prod; Bot Control adicionado; rate limit 2000/5min |
| ADR-102 | External Secrets Operator | Todas as secrets prod via ESO + Vault; zero secrets hardcoded em manifests |
| ADR-105 | VPA Resource Management | VPA em modo recomendação inicialmente; migrar para enforcement após observação 30d |

---

## Checklist de Go-Live (pré-produção)

```text
[x] Fase 1 concluida (2026-03-19) — TF sem drift, WAF em Block, providers completos, 24 NetworkPolicies
[x] Fase 2 concluida (2026-03-19) — Vault prod HA 3/3, ESO sincronizando, Keycloak prod HA 2/2
[x] Fase 3 concluida (2026-03-19) — ArgoCD 10/10 + Harbor 9/9 + SonarQube 1/1 Running (Helm direto, TF VPC-only)
[x] Fase 4 concluida (2026-03-19) — 29/29 core pods Running (Prometheus 5/5, Loki 10/10, Tempo 12/12, OTel 2/2). WAF prod + External-DNS adiados Fase 5
[ ] Gestor de domínio executou checklist (Document 2)
[ ] dig NS prod.alvocard.com.br retorna 4 NS do Route53
[ ] ACM wildcard *.prod.alvocard.com.br: status ISSUED
[ ] Fase 5 concluída — HTTPS real em todos os serviços, OIDC discovery endpoint retorna issuer correto
[ ] Fase 6 concluída — Velero backup executado com sucesso, restore testado, mTLS ativo
[ ] Fase 7 concluída — VPN funcional, engenheiros conectados, serviços internos apenas via VPN
[ ] terraform plan retorna "No changes" em todas as fases
[ ] Alertas SLO configurados e testados (latência P99, error rate)
[ ] Runbook de rollback documentado e testado
```

### Checklist de Segurança de Dados — Estratégia Mesa Técnica 2026-03-18

```text
PostgreSQL RDS — Controles obrigatórios antes do go-live:
[ ] staging_user: NOSUPERUSER, NOCREATEDB, NOLOGIN-only-on-staging-db confirmados
[ ] prod_user: NOSUPERUSER, NOCREATEDB, permissões restritas a prod_db confirmadas
[ ] REVOKE pg_monitor FROM staging_user — validado via \du no psql
[ ] DROP EXTENSION dblink em ambos os databases — validado via \dx
[ ] pgaudit ativo em prod_db: auditoria DDL + DML — validado via pg_audit.log
[ ] Conexão cross-database bloqueada: staging_user não conecta em prod_db (teste negativo)

Redis — Controles obrigatórios antes do go-live:
[ ] Redis staging em namespace isolado (staging-data-services) — sem acesso cross-ns
[ ] Redis prod com Sentinel 3 replicas ativo — validado via redis-cli sentinel masters
[ ] Network Policy: pods staging só acessam Redis staging; pods prod só acessam Redis prod
[ ] Sem segredo Redis compartilhado entre staging e prod (ESO ExternalSecrets distintos)

RabbitMQ — Controles obrigatórios antes do go-live:
[ ] staging_user: tag=management APENAS — confirmar via rabbitmqctl list_users
[ ] rabbitmq_shovel plugin: DESABILITADO — confirmar via rabbitmqctl list_plugins
[ ] rabbitmq_federation plugin: DESABILITADO — confirmar via rabbitmqctl list_plugins
[ ] Alerta Prometheus cross-vhost configurado e testado (disparo em acesso /prod por staging_user)
[ ] staging_user não tem permissão em VHost /prod (teste de binding negativo)
```

---

*Documento produzido pela Mesa Técnica — AWS Specialist + TF Specialist + Security Specialist*
*Referência: `2026-03-18-security-domain-vpn-prod.md` (Security Specialist)*
