# Setup VPN e Acesso Público — Produção (REVALIDADO)

**Data original:** 2026-03-18 | **Data revalidação:** 2026-03-18 | **Versão:** 2.1
**Cluster:** k8s-platform-prod | **Conta AWS:** 891377105802 | **Região:** us-east-1
**Status:** PLANEJAMENTO

**Atualização 2026-03-18 (v2.1):** Cenário A eliminado — FortiNet confirmado como apenas internet/home-office sem tunnel AWS.

Motivo da revalidação:

- FortiNet identificado como VPN corporativa existente na empresa (FortiGate + FortiClient)
- INC-05: inconsistência crítica entre diagrama (SAML) e código TF (certificate-auth) — resolvida
- Custos corrigidos com base em AWS CE real (baseline $1.281/mês, não $202/$316)
- NAT Gateway corrigido: 2 NAT GWs existem na VPC (risco Single-AZ não se aplica)
- GAPs de compliance BACEN adicionados: retenção 5 anos S3, CloudTrail, EKS Audit Logs

---

## ✅ DECISÃO FINAL — 2026-03-18

| Campo | Valor |
| --- | --- |
| **Solução escolhida** | Opção B — FortiGate Site-to-Site VPN (IPsec/IKEv2) |
| **Decisor** | Lead Engineer/Architect |
| **Data** | 2026-03-18 |
| **Rationale** | Menor custo ($37/mês vs $263/mês Opção C), R$15.730/ano economizados, sem dependência de Keycloak público (Fase 5), sem nova tooling para engineers, reutiliza FortiNet existente |
| **Próxima ação** | Obter IP público do FortiGate + ASN configurado → provisionar `aws_vpn_gateway` + `aws_customer_gateway` no módulo prod |
| **Cenários eliminados** | A (FortiNet internet-only, sem tunnel AWS) · C (AWS Client VPN, 7x mais caro, requer IAM IdC + Keycloak público) |

---

## MUDANCAS vs VERSAO 1.0

| # | Item | v1.0 | v2.0 |
| --- | --- | --- | --- |
| 1 | **Componente VPN** | AWS Client VPN como única opção | 3 cenários documentados; FortiNet como opção prioritária a verificar |
| 2 | **INC-05 autenticação** | Diagrama SAML + código `certificate-authentication` (contradição) | Resolvido: cada opção documentada separadamente com código correto e mutuamente exclusivo |
| 3 | **Custo VPN** | Dois valores contraditórios ($220/mês e $265/mês) | Custo correto por cenário (A: $0, B: ~$37/mês, C1: $263/mês, C2: $263/mês) |
| 4 | **Baseline custo AWS** | Não mencionado | $1.281/mês (AWS CE, março 2026, sem impostos) |
| 5 | **NAT Gateway** | "Single-AZ (risco)" | 2 NAT GWs confirmados em us-east-1a + us-east-1b — risco não se aplica |
| 6 | **Data source subnets públicas** | Não alertado | DEP-01: `data "aws_subnets" "public"` ausente em `environments/prod/main.tf` |
| 7 | **Compliance BACEN logs** | CloudWatch 90d apenas | Adicionado: S3 export 5 anos (BCB 85/2021 Art. 15) + CloudTrail + EKS Audit Logs |
| 8 | **Dependência Fase 5** | "VPN obrigatoriamente após Keycloak público" | Correto apenas para Cenário C2 (federated-auth). Cenário B e C1 não dependem de Keycloak público |
| 9 | **Cenário A FortiNet** | Listado como opção a verificar | ❌ Eliminado — FortiNet é apenas internet/home-office, sem tunnel AWS |

---

## Resumo Executivo

- **Hoje (staging):** acesso via `windows-hosts.txt` com IPs fixos dos ALBs para `*.staging.internal`; ALBs internet-facing sem WAF em 2 dos 3; Backstage via `kubectl port-forward`; nenhum Client VPN (`ClientVpnEndpoints: []` confirmado 2026-03-18)
- **Para produção:** 2 ALBs distintos (public + internal), WAF em Block (não Count), e solução VPN para acesso da equipe técnica a serviços internos
- **Decisao pendente do usuario:** qual cenário adotar — **B** (Site-to-Site FortiGate, recomendado, ~$73/mês) ou **C** (AWS Client VPN, ~$263/mês). Cenário A eliminado (v2.1)
- **Custo baseline atual (AWS CE):** ~$1.281/mês (sem impostos). VPN adiciona $0 a $263/mês dependendo do cenário escolhido
- **Sequência válida para ALBs + WAF:** sem bloqueadores externos — pode executar após DEP-01 resolvido

---

## Situacao Atual

### Como o acesso funciona hoje (staging)

| Método | Serviços | Problema |
| --- | --- | --- |
| `access/windows-hosts.txt` — IPs fixos dos ALBs mapeados para `*.staging.internal` | GitLab, Harbor, Keycloak, Grafana, ArgoCD, SonarQube | Domínio fictício não resolve externamente sem o arquivo hosts; quebra quando IPs dos ALBs mudam |
| ALBs internet-facing direto | Plataforma em geral | Sem controle de acesso por IP em 2 dos 3 ALBs; HTTP sem TLS real |
| `kubectl port-forward` | Backstage (ALB internal) | Manual, não escalável, cai quando a sessão kubectl expira |
| Sem VPN | Todos | `ClientVpnEndpoints: []` — confirmado 2026-03-18 |

### ALBs ativos (auditado 2026-03-18)

| ALB | Scheme | WAF | Serviços ativos | GAP de segurança |
| --- | --- | --- | --- | --- |
| `k8s-platformstaging-00e0ecf3b4` | internet-facing | **Sim** | plataforma geral | WAF regras 30/40/50 em Count (não bloqueiam) |
| `k8s-gitlabstaging-da5a4e8c6d` | internet-facing | **NAO** | gitlab, kas, minio | Exposto sem proteção WAF |
| `k8s-stagingp-keycloak-0dbafff841` | internet-facing | **NAO** | keycloak separado | Exposto sem proteção WAF |
| `k8s-backstagestaging-c827d564e5` | internal | N/A | backstage | Acesso apenas via port-forward |

### Rede (VPC, NAT Gateways) — fatos auditados 2026-03-18

| Componente | Status | Observacao |
| --- | --- | --- |
| VPC `vpc-0b1396a59c417c1f0` | Running | CIDR 10.0.0.0/16 |
| Subnets privadas | Running | us-east-1a (10.0.128.0/20), us-east-1b (10.0.144.0/20) |
| Subnets públicas | Running | us-east-1a (10.0.0.0/20), us-east-1b (10.0.16.0/20) — tag `kubernetes.io/role/elb=1` |
| NAT Gateway us-east-1a | Running | Confirmado — risco Single-AZ NAO se aplica |
| NAT Gateway us-east-1b | Running | Confirmado — HA Multi-AZ real |

> **NOTA DEP-01 (bloqueador Terraform):** O `data "aws_subnets" "public"` está **ausente** em `environments/prod/main.tf`. O recurso `aws_lb.platform_prod_public` (code abaixo) referencia `data.aws_subnets.public.ids`. Esse data source deve ser adicionado antes do `terraform apply` dos ALBs.

---

## Arquitetura Alvo

```text
                        INTERNET
                            │
                ┌───────────┴───────────┐
                │    WAF WebACL prod    │
                │  (Block: OWASP, SQLi, │
                │   BadInputs, Bots,    │
                │   Geo CN/RU/KP/IR/BY) │
                └───────────┬───────────┘
                            │
               ┌────────────▼────────────┐
               │  ALB: prod-public       │
               │  Scheme: internet-facing│
               │  Cert: *.prod.alvocard  │
               └────────────┬────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        ▼                   ▼                   ▼
  keycloak.prod        gitlab.prod          harbor.prod
  kas.prod             hatch-api.prod       hatch.prod


        EQUIPE TECNICA (laptop)
               │
               │  [VPN — cenário a definir: ver Parte 2]
               │  FortiClient (Cenário A/B) OU AWS VPN Client (Cenário C)
               ▼
  ┌─────────────────────────────────────────┐
  │   VPC: vpc-0b1396a59c417c1f0            │
  │   CIDR: 10.0.0.0/16                     │
  │                                         │
  │   ALB: prod-internal (scheme=internal)  │
  │   Cert: *.prod.alvocard.com.br          │
  │   SEM WAF (proteção por SG + VPN)       │
  │                                         │
  │   ├── argocd.prod.alvocard.com.br       │
  │   ├── grafana.prod.alvocard.com.br      │
  │   ├── vault.prod.alvocard.com.br        │
  │   ├── sonarqube.prod.alvocard.com.br    │
  │   ├── backstage.prod.alvocard.com.br    │
  │   └── rabbitmq.prod.alvocard.com.br     │
  │                                         │
  │   EKS nodes, RDS prod, Redis prod       │
  └─────────────────────────────────────────┘
```

---

## Parte 1 — Acesso Publico (ALBs + WAF)

### ALBs de Producao

| ALB | Scheme | IngressGroup | WAF | Certificado | Custo estimado |
| --- | --- | --- | --- | --- | --- |
| `prod-platform-public` | internet-facing | `prod-platform-public` | Sim — WebACL prod | ACM wildcard `*.prod.alvocard.com.br` | ~$18-22/mês (LCU) |
| `prod-platform-internal` | internal | `prod-platform-internal` | Nao (proteção por SG + VPN) | ACM wildcard `*.prod.alvocard.com.br` | ~$18-22/mês (LCU) |

### DEP-01 — Adicionar data source subnets públicas (obrigatório antes do apply)

O arquivo `environments/prod/main.tf` não possui o data source `aws_subnets` para subnets públicas. Adicionar antes do `terraform apply` dos ALBs:

```hcl
# environments/prod/main.tf — ADICIONAR (DEP-01)
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  tags = {
    "kubernetes.io/role/elb" = "1"
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}
```

### Terraform — ALBs prod

```hcl
# environments/prod/albs.tf

# ALB internet-facing (serviços públicos com WAF)
resource "aws_lb" "platform_prod_public" {
  name               = "prod-platform-public"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_public_prod.id]
  subnets            = data.aws_subnets.public.ids  # subnets públicas — DEP-01 resolvido

  enable_deletion_protection = true  # produção

  access_logs {
    bucket  = module.s3_buckets_prod.alb_logs_bucket_name
    prefix  = "alb-public-prod"
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name = "prod-platform-public"
    Type = "internet-facing"
  })
}

# Associar WAF ao ALB público de prod
resource "aws_wafv2_web_acl_association" "prod_public" {
  resource_arn = aws_lb.platform_prod_public.arn
  web_acl_arn  = aws_wafv2_web_acl.prod.arn
}

# ALB internal (serviços admin — acesso somente via VPN)
resource "aws_lb" "platform_prod_internal" {
  name               = "prod-platform-internal"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_internal_prod.id]
  subnets            = data.aws_subnets.private.ids  # subnets privadas

  enable_deletion_protection = true

  tags = merge(local.common_tags, {
    Name = "prod-platform-internal"
    Type = "internal"
  })
}
```

---

### Servicos Publicos vs Internos

| Serviço | URL Produção | Público? | WAF? | Motivo da decisão |
| --- | --- | --- | --- | --- |
| Keycloak SSO | `keycloak.prod.alvocard.com.br` | **Sim** | Sim | OIDC endpoint obrigatório para federation Entra ID |
| GitLab CE | `gitlab.prod.alvocard.com.br` | **Sim** | Sim | CI/CD acessado por desenvolvedores externos e webhooks |
| GitLab KAS | `kas.prod.alvocard.com.br` | **Sim** | Sim | Agentes de cluster externos precisam conectar |
| Harbor Registry | `harbor.prod.alvocard.com.br` | **Sim** | Sim | Pull de imagens pelos clusters e pipelines CI/CD |
| Hatch ETL API | `hatch-api.prod.alvocard.com.br` | **Sim** | Sim | API consumida por integrações externas e originadoras |
| Hatch Web UI | `hatch.prod.alvocard.com.br` | **Sim** | Sim | Interface de usuário final |
| ArgoCD | `argocd.prod.alvocard.com.br` | **Nao** | N/A | Controle do cluster — execução remota de código via sync |
| Grafana | `grafana.prod.alvocard.com.br` | **Nao** | N/A | Métricas de infra expõem arquitetura interna |
| Vault | `vault.prod.alvocard.com.br` | **Nao** | N/A | Secrets críticos da plataforma inteira |
| SonarQube | `sonarqube.prod.alvocard.com.br` | **Nao** | N/A | Análises de segurança expõem vulnerabilidades conhecidas |
| Backstage | `backstage.prod.alvocard.com.br` | **Nao** | N/A | Scaffolding não autorizado, SSRF via templates |
| RabbitMQ Mgmt | `rabbitmq.prod.alvocard.com.br` | **Nao** | N/A | Mensagens em trânsito, injeção de filas |
| Prometheus | sem ingress público | **Nao** | N/A | Acesso via Grafana ou port-forward com VPN |
| AlertManager | sem ingress público | **Nao** | N/A | Integração via webhook Teams |

---

### WAF Producao

#### Diferencas vs Staging

| Regra | Staging (atual) | Produção (alvo) | Justificativa |
| --- | --- | --- | --- |
| OWASP Common (P30) | **Count** (não bloqueia) | **Block** | Exposição real a ameaças financeiras |
| SQLi (P40) | **Count** (não bloqueia) | **Block** | RDS com dados sensíveis/PII |
| Known Bad Inputs (P50) | **Count** (não bloqueia) | **Block** | Log4Shell / RCE prevention |
| Bot Control (P60) | Nao existe | **Adicionar (Block)** | Proteção contra scraping e automação maliciosa |
| Geo block (P20) | CN, RU, KP | CN, RU, KP, **IR, BY** | Conformidade BACEN BCB 85/2021 |
| Rate limit (P10) | 1000 req/5min/IP | 2000 req/5min/IP | Ajustar para tráfego real de produção |

**Acao imediata no staging (antes de prod):** Mudar regras 30/40/50 de Count para Block no WAF existente (`waf-k8s-platform-prod-staging`). Pode ser feito agora sem aguardar domínio.

#### Terraform WAF prod

```hcl
# environments/prod/waf.tf

resource "aws_wafv2_web_acl" "prod" {
  name        = "waf-k8s-platform-prod"
  description = "WAF de producao — regras em Block, Bot Control ativo"
  scope       = "REGIONAL"

  default_action { allow {} }

  # P10: Rate limiting
  rule {
    name     = "rate-limit-per-ip"
    priority = 10
    action { block {} }
    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "ProdRateLimit"
      sampled_requests_enabled   = true
    }
  }

  # P20: Geo block (BACEN BCB 85/2021)
  rule {
    name     = "geo-block-high-risk-countries"
    priority = 20
    action { block {} }
    statement {
      geo_match_statement {
        country_codes = ["CN", "RU", "KP", "IR", "BY"]
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "ProdGeoBlock"
      sampled_requests_enabled   = true
    }
  }

  # P30: OWASP Common — Block (vs Count no staging)
  rule {
    name            = "aws-managed-owasp-common"
    priority        = 30
    override_action { none {} }  # usa o default Block da managed rule
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
        # Harbor: se upload de imagens Docker grandes for bloqueado,
        # adicionar rule_action_override para SizeRestrictions_BODY
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "ProdOWASP"
      sampled_requests_enabled   = true
    }
  }

  # P40: SQLi — Block
  rule {
    name            = "aws-managed-sqli"
    priority        = 40
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "ProdSQLi"
      sampled_requests_enabled   = true
    }
  }

  # P50: Known Bad Inputs — Block
  rule {
    name            = "aws-managed-known-bad-inputs"
    priority        = 50
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "ProdBadInputs"
      sampled_requests_enabled   = true
    }
  }

  # P60: Bot Control (NOVO para prod)
  rule {
    name            = "aws-managed-bot-control"
    priority        = 60
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesBotControlRuleSet"
        vendor_name = "AWS"
        managed_rule_group_configs {
          aws_managed_rules_bot_control_rule_set {
            inspection_level = "COMMON"
          }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "ProdBotControl"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "ProdWebACL"
    sampled_requests_enabled   = true
  }

  tags = merge(local.common_tags, {
    Name = "waf-k8s-platform-prod"
  })
}

# CloudWatch Log Group para WAF (retenção 90 dias operacional — BACEN)
# NOTA: 90 dias no CloudWatch é suficiente para ops. Para BACEN BCB 85/2021 Art. 15
# (5 anos de retenção de logs de acesso), usar o recurso aws_wafv2_web_acl_logging_configuration
# com destino S3 — ver seção de Compliance BACEN abaixo.
resource "aws_cloudwatch_log_group" "waf_prod" {
  name              = "/aws/wafv2/prod-platform"
  retention_in_days = 90

  tags = local.common_tags
}

resource "aws_wafv2_web_acl_logging_configuration" "prod" {
  log_destination_configs = [aws_cloudwatch_log_group.waf_prod.arn]
  resource_arn            = aws_wafv2_web_acl.prod.arn
}

output "prod_waf_acl_arn" {
  description = "ARN do WAF WebACL prod — usar nas annotations dos Ingresses publicos"
  value       = aws_wafv2_web_acl.prod.arn
}
```

**Custo WAF prod estimado:** ~$100-140/mês (WebACL + 6 regras managed + logs CloudWatch 90d + requests)

---

### Ingress Annotations Padrao (prod)

#### Template obrigatorio — Ingress público (ALB internet-facing)

```yaml
# Template: aplicar em TODOS os Ingresses de servicos publicos de producao
metadata:
  annotations:
    # ALB Controller
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/group.name: prod-platform-public

    # TLS
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/certificate-arn: "<ARN do ACM wildcard prod — terraform output prod_acm_certificate_arn>"
    alb.ingress.kubernetes.io/ssl-policy: "ELBSecurityPolicy-TLS13-1-2-2021-06"

    # WAF
    alb.ingress.kubernetes.io/wafv2-acl-arn: "<ARN do WAF prod — terraform output prod_waf_acl_arn>"

    # Backend
    alb.ingress.kubernetes.io/backend-protocol: HTTP
    alb.ingress.kubernetes.io/target-group-attributes: deregistration_delay.timeout_seconds=30

    # Health check
    alb.ingress.kubernetes.io/healthcheck-path: /healthz
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: "30"
    alb.ingress.kubernetes.io/success-codes: "200-399"
```

#### Template obrigatorio — Ingress interno (ALB internal, somente via VPN)

```yaml
# Template: aplicar em TODOS os Ingresses de servicos internos de producao
metadata:
  annotations:
    # ALB Controller
    alb.ingress.kubernetes.io/scheme: internal
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/group.name: prod-platform-internal

    # TLS
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/certificate-arn: "<ARN do ACM wildcard prod>"
    alb.ingress.kubernetes.io/ssl-policy: "ELBSecurityPolicy-TLS13-1-2-2021-06"

    # Sem WAF no ALB interno — protecao por Security Group
    # (aceita apenas CIDR VPN — 10.200.0.0/16 para AWS Client VPN
    #  ou CIDR tunnel FortiGate conforme Cenário B)
    alb.ingress.kubernetes.io/backend-protocol: HTTP
```

#### Annotations especiais por servico

```yaml
# GitLab KAS — WebSocket persistente
alb.ingress.kubernetes.io/target-group-attributes: >-
  stickiness.enabled=true,
  stickiness.lb_cookie.duration_seconds=86400

# Harbor — upload de imagens grandes (OWASP body size limit)
# Se regra SizeRestrictions_BODY bloquear pushes de imagens Docker:
# Adicionar rule_action_override no WAF para rota harbor.prod.alvocard.com.br/v2/
```

---

## Parte 2 — VPN com FortiNet: Tres Cenarios

> **DECISAO PENDENTE DO USUARIO:** FortiNet (FortiGate + FortiClient) é a VPN corporativa existente.
> A implementação da VPN para esta VPC depende da situação atual do FortiGate.
> **Responda qual cenário se aplica para prosseguir com a Fase VPN.**

---

### Resolucao INC-05 (Inconsistencia de autenticacao)

O documento v1.0 continha uma inconsistência crítica:

- O **diagrama** descrevia: `Laptop → IAM Identity Center → Keycloak SAML → VPN` (federated-authentication)
- O **código Terraform** implementava: `authentication_options { type = "certificate-authentication" }` (mutual TLS)

**Esses dois mecanismos são mutuamente exclusivos no AWS Client VPN.** Um endpoint não pode ter ambos simultaneamente.

A resolução está nos Cenários C1 e C2 abaixo: cada opção tem seu próprio bloco de código TF correto. Escolha apenas uma das opções se o Cenário C for adotado.

---

### Cenario A — FortiGate ja tem tunnel Site-to-Site para esta VPC

> ❌ CENÁRIO A — NÃO SE APLICA
> **Confirmado em 2026-03-18:** FortiNet corporativo é utilizado exclusivamente para
> acesso internet/home-office. Não existe tunnel FortiGate ↔ AWS VPC atualmente.
> Verificação: `aws ec2 describe-vpn-connections` retorna vazio (nenhum Customer Gateway ativo).

**Situacao:** Um AWS Site-to-Site VPN (ou Direct Connect) já conecta a rede corporativa à VPC `vpc-0b1396a59c417c1f0`.

O que isso significa operacionalmente:

- Engenheiros com FortiClient conectado à rede corporativa já têm acesso à VPC via roteamento FortiGate
- O ALB internal (`prod-platform-internal`) é acessível sem nenhum componente AWS adicional
- Custo de VPN adicional: **$0**
- Tooling para engenheiros: nenhuma mudança (já usam FortiClient)

Como verificar se o tunnel existe:

```bash
# Verificar conexões VPN Site-to-Site ativas
aws ec2 describe-vpn-connections \
  --profile k8s-platform-prod \
  --region us-east-1 \
  --query 'VpnConnections[*].{ID:VpnConnectionId,State:State,CustomerGW:CustomerGatewayId,VGWID:VpnGatewayId}' \
  --output table

# Verificar Virtual Private Gateways (necessário para Site-to-Site VPN)
aws ec2 describe-vpn-gateways \
  --profile k8s-platform-prod \
  --region us-east-1 \
  --query 'VpnGateways[*].{ID:VpnGatewayId,State:State,VpcAttachments:VpcAttachments}' \
  --output table

# Verificar Transit Gateway (alternativa ao VGW)
aws ec2 describe-transit-gateways \
  --profile k8s-platform-prod \
  --region us-east-1 \
  --output table
```

**Se o resultado mostrar tunnel ativo para a VPC:** Cenário A confirmado. A seção VPN deste documento está **completa** — não há nada a implementar.

Impacto no documento se Cenário A:

- Seção VPN: substituída por "FortiGate tunnel ativo — sem componentes AWS adicionais"
- Security Group do ALB internal: aceitar CIDR da rede corporativa (ex: 10.x.x.x/y) ao invés de CIDR VPN
- Fase VPN da sequência de implementação: removida
- Custo total de VPN: $0

---

### Cenario B — FortiGate ainda nao tem tunnel (Site-to-Site a criar) ✅ RECOMENDADO

**Situacao:** FortiGate confirmado como existente mas sem tunnel AWS (v2.1). A rede corporativa não tem acesso direto à VPC atualmente.

**Recomendacao:** AWS Site-to-Site VPN + Virtual Private Gateway (não AWS Client VPN).
Aproveita o FortiNet já existente na empresa — engenheiros continuam usando FortiClient sem aprender nova ferramenta VPN.

Por que Site-to-Site e nao Client VPN:

- Engenheiros continuam usando FortiClient — zero mudança de tooling
- Custo ~7x menor: ~$36.50/mês (Site-to-Site) vs ~$263/mês (Client VPN para 5 eng.)
- Mais simples de operar: sem gerenciamento de PKI de cliente, sem arquivos .ovpn individuais
- Alinhado com a infraestrutura corporativa existente (FortiGate)

Custo Cenario B:

| Item | Custo/hora | Custo/mês |
| --- | --- | --- |
| VPN Gateway (VGW) | $0.05 | ~$36.50 |
| VPN Connection | $0.05 | ~$36.50 |
| Transferência de dados | $0.09/GB | variável |
| **Total base** | | **~$73/mês** |

> Nota: se já existir Transit Gateway, o custo da conexão VPN ao TGW é similar (~$36.50 + $0.05/GB attachment).

Terraform — Site-to-Site VPN (Cenario B):

```hcl
# environments/prod/vpn-site-to-site.tf
# Cenario B: FortiGate existente, sem tunnel atual → criar Site-to-Site

variable "fortgate_public_ip" {
  description = "IP público do FortiGate corporativo (Customer Gateway)"
  type        = string
  # Obter com a equipe de rede corporativa
}

variable "corporate_cidr" {
  description = "CIDR da rede corporativa (ex: 192.168.0.0/16 ou 10.10.0.0/8)"
  type        = string
}

# Customer Gateway (representa o FortiGate)
resource "aws_customer_gateway" "fortigate" {
  bgp_asn    = 65000  # ASN do FortiGate — confirmar com equipe de rede
  ip_address = var.fortgate_public_ip
  type       = "ipsec.1"

  tags = merge(local.common_tags, {
    Name = "fortigate-prod-cgw"
  })
}

# Virtual Private Gateway (lado AWS)
resource "aws_vpn_gateway" "prod" {
  vpc_id            = var.vpc_id
  amazon_side_asn   = 64512

  tags = merge(local.common_tags, {
    Name = "prod-platform-vgw"
  })
}

# Site-to-Site VPN Connection
resource "aws_vpn_connection" "fortigate_to_prod" {
  vpn_gateway_id      = aws_vpn_gateway.prod.id
  customer_gateway_id = aws_customer_gateway.fortigate.id
  type                = "ipsec.1"
  static_routes_only  = false  # BGP preferido; true se FortiGate não suportar BGP

  tags = merge(local.common_tags, {
    Name = "fortigate-to-prod-vpn"
  })
}

# Route propagation: VGW propaga rotas corporativas para route tables privadas
resource "aws_vpn_gateway_route_propagation" "private_a" {
  vpn_gateway_id = aws_vpn_gateway.prod.id
  route_table_id = data.aws_route_table.private_a.id
}

resource "aws_vpn_gateway_route_propagation" "private_b" {
  vpn_gateway_id = aws_vpn_gateway.prod.id
  route_table_id = data.aws_route_table.private_b.id
}

# CloudWatch Logs para auditoria VPN (BACEN — 90 dias operacional)
resource "aws_cloudwatch_log_group" "vpn_site_to_site" {
  name              = "/aws/vpn/prod-platform-site-to-site"
  retention_in_days = 90
  tags              = local.common_tags
}

output "vpn_tunnel1_address" {
  description = "IP do Tunnel 1 — configurar no FortiGate"
  value       = aws_vpn_connection.fortigate_to_prod.tunnel1_address
}

output "vpn_tunnel2_address" {
  description = "IP do Tunnel 2 — configurar no FortiGate"
  value       = aws_vpn_connection.fortigate_to_prod.tunnel2_address
}

output "vpn_tunnel1_preshared_key" {
  description = "Pre-shared key Tunnel 1 — configurar no FortiGate"
  value       = aws_vpn_connection.fortigate_to_prod.tunnel1_preshared_key
  sensitive   = true
}
```

Pos-apply — configurar no FortiGate:

```text
Após terraform apply, recuperar os outputs:
  terraform output vpn_tunnel1_address
  terraform output vpn_tunnel1_preshared_key  # sensitive — usar Vault

Configurar no FortiGate (com equipe de rede corporativa):
  1. Criar IPsec Phase 1: remote gateway = tunnel1_address, pre-shared key = output
  2. Criar IPsec Phase 2: local subnet = 192.168.x.x/y, remote subnet = 10.0.0.0/16
  3. Criar Static Route: destination = 10.0.0.0/16, interface = ipsec tunnel
  4. Criar Policy: allow corporate CIDR → 10.0.0.0/16

Verificar:
  aws ec2 describe-vpn-connections --region us-east-1 \
    --query 'VpnConnections[0].VgwTelemetry[*].{IP:OutsideIpAddress,Status:Status}' \
    --output table
  # Ambos tunnels devem aparecer como UP
```

---

### Cenario C — AWS Client VPN ainda necessario

Quando faz sentido mesmo com FortiNet:

- Contractors ou parceiros externos que não têm acesso à rede corporativa FortiGate
- Equipe técnica em regiões geográficas onde o FortiGate corporativo não atende com latência aceitável
- Auditores com acesso temporário e escopo limitado (autorização por grupo no Client VPN)
- Requisito de isolamento: acesso VPN não deve passar pela rede corporativa (segregação de auditoria)

Se o Cenario C for escolhido, definir qual autenticacao usar (C1 ou C2 sao mutuamente exclusivos):

#### Opcao C1 — Certificate Authentication (mutual TLS)

**Quando usar:** Pode ser implementado agora, sem depender de Keycloak público.
**Pré-requisito:** Apenas PKI VPN (CA root + certificado servidor) — pode ser gerado hoje.
**Autenticação:** Cada engenheiro recebe um certificado cliente assinado pela CA VPN. Sem SSO, sem MFA via Keycloak.
**Desvantagem:** Gerenciamento de PKI (gerar, distribuir, revogar certificados individuais). Sem integração com identidade corporativa.

```hcl
# modules/client-vpn/main.tf — OPCAO C1 (certificate-authentication)
# MUTUAMENTE EXCLUSIVO com C2 — escolher apenas um

variable "vpc_id"                        { type = string }
variable "private_subnet_ids"            { type = list(string) }
variable "server_certificate_arn"        { type = string }
variable "client_ca_certificate_arn"     { type = string }
variable "dns_servers"                   { type = list(string) }
variable "client_cidr_block"             { type = string ; default = "10.200.0.0/16" }
variable "common_tags"                   { type = map(string) }

resource "aws_security_group" "client_vpn" {
  name        = "client-vpn-prod"
  description = "Security Group para AWS Client VPN endpoint de producao"
  vpc_id      = var.vpc_id

  ingress {
    description = "VPN client connections (UDP 443)"
    from_port   = 443
    to_port     = 443
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Acesso total a VPC (split-tunnel)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

  tags = merge(var.common_tags, { Name = "client-vpn-prod" })
}

resource "aws_ec2_client_vpn_endpoint" "prod" {
  description            = "prod-platform-vpn — autenticacao mutual TLS (C1)"
  server_certificate_arn = var.server_certificate_arn
  client_cidr_block      = var.client_cidr_block
  split_tunnel           = true
  transport_protocol     = "udp"
  vpc_id                 = var.vpc_id
  security_group_ids     = [aws_security_group.client_vpn.id]
  session_timeout_hours  = 8

  # C1: certificate-authentication (mutual TLS)
  # NÃO combinar com federated-authentication no mesmo endpoint
  authentication_options {
    type                       = "certificate-authentication"
    root_certificate_chain_arn = var.client_ca_certificate_arn
  }

  connection_log_options {
    enabled               = true
    cloudwatch_log_group  = aws_cloudwatch_log_group.vpn.name
    cloudwatch_log_stream = aws_cloudwatch_log_stream.vpn.name
  }

  dns_servers = var.dns_servers  # ["10.0.0.2"] — Route53 Resolver na VPC

  tags = merge(var.common_tags, {
    Name        = "prod-platform-vpn"
    Environment = "production"
    AuthType    = "certificate"
  })
}

resource "aws_ec2_client_vpn_network_association" "prod" {
  for_each               = toset(var.private_subnet_ids)
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.prod.id
  subnet_id              = each.value
}

resource "aws_ec2_client_vpn_authorization_rule" "platform_full" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.prod.id
  target_network_cidr    = "10.0.0.0/16"
  authorize_all_groups   = true
  description            = "Acesso completo a VPC para engenheiros autorizados (C1)"
}

resource "aws_cloudwatch_log_group" "vpn" {
  name              = "/aws/vpn/prod-platform"
  retention_in_days = 90
  tags              = var.common_tags
}

resource "aws_cloudwatch_log_stream" "vpn" {
  name           = "prod-platform-vpn-connections"
  log_group_name = aws_cloudwatch_log_group.vpn.name
}

output "client_vpn_endpoint_id" {
  value = aws_ec2_client_vpn_endpoint.prod.id
}

output "client_vpn_dns_name" {
  value       = aws_ec2_client_vpn_endpoint.prod.dns_name
  description = "DNS name do endpoint VPN — usar no arquivo .ovpn"
}
```

Geracao de PKI para C1:

```bash
# Executar ANTES de criar o módulo Terraform
# Requer: openssl instalado

# 1. Gerar CA root para VPN
openssl genrsa -out vpn-ca.key 4096
openssl req -x509 -new -nodes -key vpn-ca.key -sha256 -days 3650 \
  -out vpn-ca.crt \
  -subj "/CN=vpn-ca.prod.alvocard.com.br/O=Alvocard/C=BR"

# 2. Gerar chave e certificado do servidor VPN
openssl genrsa -out vpn-server.key 4096
openssl req -new -key vpn-server.key \
  -out vpn-server.csr \
  -subj "/CN=vpn-server.prod.alvocard.com.br/O=Alvocard/C=BR"
openssl x509 -req -in vpn-server.csr \
  -CA vpn-ca.crt -CAkey vpn-ca.key -CAcreateserial \
  -out vpn-server.crt -days 3650 -sha256

# 3. Upload CA para ACM (sera o client_ca_certificate_arn)
aws acm import-certificate \
  --profile k8s-platform-prod \
  --region us-east-1 \
  --certificate fileb://vpn-ca.crt \
  --private-key fileb://vpn-ca.key

# 4. Upload certificado do servidor para ACM (sera o server_certificate_arn)
aws acm import-certificate \
  --profile k8s-platform-prod \
  --region us-east-1 \
  --certificate fileb://vpn-server.crt \
  --private-key fileb://vpn-server.key \
  --certificate-chain fileb://vpn-ca.crt

# 5. Gerar certificado para cada engenheiro (repetir por usuario)
openssl genrsa -out eng-joao.key 4096
openssl req -new -key eng-joao.key -out eng-joao.csr \
  -subj "/CN=eng-joao/O=Alvocard/C=BR"
openssl x509 -req -in eng-joao.csr \
  -CA vpn-ca.crt -CAkey vpn-ca.key -CAcreateserial \
  -out eng-joao.crt -days 365 -sha256

# IMPORTANTE: guardar vpn-ca.key em Vault prod (jamais em git)
# Os ARNs retornados pelos uploads acima vao nas variaveis do modulo TF
```

#### Opcao C2 — Federated Authentication (SAML via IAM Identity Center + Keycloak)

**Quando usar:** Somente após Fase 5 do plano de produção (Keycloak com URL pública `keycloak.prod.alvocard.com.br` funcionando).
**Pré-requisito adicional:** IAM Identity Center habilitado + aplicação SAML configurada no Keycloak.
**Vantagem:** SSO corporativo, MFA via Keycloak/Entra ID, sem gerenciamento de PKI de cliente.
**Autenticação:** `Engenheiro → AWS VPN Client app → SAML → IAM Identity Center → Keycloak → (opcional: Entra ID)`

```hcl
# modules/client-vpn/main.tf — OPCAO C2 (federated-authentication)
# MUTUAMENTE EXCLUSIVO com C1 — escolher apenas um
# PRE-REQUISITO: Keycloak com URL publica + IAM Identity Center habilitado

variable "vpc_id"                        { type = string }
variable "private_subnet_ids"            { type = list(string) }
variable "server_certificate_arn"        { type = string }
variable "saml_provider_arn"             { type = string }  # ARN do SAML provider no IAM Identity Center
variable "self_service_saml_provider_arn" { type = string } # ARN para self-service portal (opcional)
variable "dns_servers"                   { type = list(string) }
variable "client_cidr_block"             { type = string ; default = "10.200.0.0/16" }
variable "common_tags"                   { type = map(string) }

resource "aws_security_group" "client_vpn" {
  name        = "client-vpn-prod"
  description = "Security Group para AWS Client VPN endpoint de producao"
  vpc_id      = var.vpc_id

  ingress {
    description = "VPN client connections (UDP 443)"
    from_port   = 443
    to_port     = 443
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Acesso total a VPC (split-tunnel)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

  tags = merge(var.common_tags, { Name = "client-vpn-prod" })
}

resource "aws_ec2_client_vpn_endpoint" "prod" {
  description            = "prod-platform-vpn — autenticacao SAML Keycloak (C2)"
  server_certificate_arn = var.server_certificate_arn
  client_cidr_block      = var.client_cidr_block
  split_tunnel           = true
  transport_protocol     = "udp"
  vpc_id                 = var.vpc_id
  security_group_ids     = [aws_security_group.client_vpn.id]
  session_timeout_hours  = 8

  # C2: federated-authentication (SAML via IAM Identity Center → Keycloak)
  # NÃO combinar com certificate-authentication no mesmo endpoint
  authentication_options {
    type                           = "federated-authentication"
    saml_provider_arn              = var.saml_provider_arn
    self_service_saml_provider_arn = var.self_service_saml_provider_arn
  }

  connection_log_options {
    enabled               = true
    cloudwatch_log_group  = aws_cloudwatch_log_group.vpn.name
    cloudwatch_log_stream = aws_cloudwatch_log_stream.vpn.name
  }

  dns_servers = var.dns_servers  # ["10.0.0.2"] — Route53 Resolver na VPC

  tags = merge(var.common_tags, {
    Name        = "prod-platform-vpn"
    Environment = "production"
    AuthType    = "saml-federated"
  })
}

resource "aws_ec2_client_vpn_network_association" "prod" {
  for_each               = toset(var.private_subnet_ids)
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.prod.id
  subnet_id              = each.value
}

# C2: Authorization rule por grupo SAML
resource "aws_ec2_client_vpn_authorization_rule" "platform_admins" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.prod.id
  target_network_cidr    = "10.0.0.0/16"
  authorize_all_groups   = false
  access_group_id        = "platform-admins"  # grupo definido no Keycloak/IAM Identity Center
  description            = "platform-admins group -> VPC full access (C2)"
}

resource "aws_cloudwatch_log_group" "vpn" {
  name              = "/aws/vpn/prod-platform"
  retention_in_days = 90
  tags              = var.common_tags
}

resource "aws_cloudwatch_log_stream" "vpn" {
  name           = "prod-platform-vpn-connections"
  log_group_name = aws_cloudwatch_log_group.vpn.name
}

output "client_vpn_endpoint_id" {
  value = aws_ec2_client_vpn_endpoint.prod.id
}

output "client_vpn_dns_name" {
  value       = aws_ec2_client_vpn_endpoint.prod.dns_name
  description = "DNS name do endpoint VPN — usar no arquivo .ovpn"
}
```

Passos adicionais C2 (alem do terraform apply):

```text
1. Verificar IAM Identity Center habilitado:
   aws sso-admin list-instances --profile k8s-platform-prod

2. Criar aplicacao SAML no IAM Identity Center para o Client VPN endpoint

3. Configurar Keycloak realm prod com SAML SP para IAM Identity Center:
   Keycloak Admin Console → Clients → New Client → SAML
   Entity ID: urn:amazon:webservices:clientvpn
   ACS URL: https://self-service.clientvpn.amazonaws.com/api/auth/sso/saml

4. Exportar metadata do Keycloak → upload para IAM Identity Center

5. Obter ARN do SAML provider no IAM e usar na variavel saml_provider_arn
```

### Custo Estimado por Cenario

| Cenario | Descricao | Custo/mês adicional | Observacao |
| --- | --- | --- | --- |
| ~~**A**~~ | ~~FortiGate tunnel existente~~ | ~~**$0**~~ | ❌ N/A — eliminado (v2.1): FortiNet apenas internet/home-office, sem tunnel AWS |
| **B** ✅ | Site-to-Site VPN (VGW + FortiGate) — **RECOMENDADO** | **~$73/mês** | $36.50 VGW + $36.50 VPN Connection. Aproveita FortiNet existente |
| **C1** | AWS Client VPN (certificate auth) | **~$263/mês** | $73 endpoint + $146 assoc. (2 AZs) + ~$44 conexões (5 eng. 8h/dia) |
| **C2** | AWS Client VPN (SAML/Keycloak) | **~$263/mês** | Mesmo custo que C1 + dependência Fase 5 |

**Baseline atual AWS CE (março 2026):** ~$1.281/mês (sem impostos, conforme AWS Cost Explorer MTD 01-17/03).
VPN adiciona entre $0 (Cenário A) e $263/mês (Cenários C1/C2) sobre esse baseline.

---

## Network Policies Criticas (faltando)

### Status atual

```text
COM Network Policy:     cert-manager, data-services, kube-system,
                        staging-data-infrastructure,
                        staging-observability-monitoring,
                        staging-security-vault

SEM Network Policy:     staging-platform-argocd    <- RISCO CRITICO
                        staging-platform-gitlab     <- RISCO CRITICO
                        staging-platform-keycloak   <- RISCO CRITICO
                        staging-platform-sonarqube  <- RISCO ALTO
                        harbor-system               <- RISCO ALTO
```

### Policies recomendadas por namespace (ordem de criticidade)

#### 1. staging-platform-keycloak (P0 — SSO de toda a plataforma)

```yaml
# Permitir apenas: ALB -> Keycloak (8080), Keycloak -> RDS prod (5432), Keycloak -> Redis prod (6379)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: keycloak-network-policy
  namespace: staging-platform-keycloak
spec:
  podSelector:
    matchLabels:
      app: keycloak
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system  # AWS LB Controller health checks
      ports:
        - port: 8080
    - from: []  # ALB: trafego do ALB entra via Security Group — NetworkPolicy nao filtra SG
      ports:
        - port: 8080
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: data-services
      ports:
        - port: 5432  # PostgreSQL
        - port: 6379  # Redis
    - to: []          # DNS
      ports:
        - port: 53
          protocol: UDP
```

#### 2. harbor-system (P1 — registry de imagens de producao)

Referencia: `domains/security/network-policies/marco4/harbor-network-policy.yaml`
Permitir: ALB → Harbor (80, 443, 5000), Harbor → RDS (5432), Harbor → Redis (6379), Harbor → S3 (egress HTTPS)

#### 3. staging-platform-argocd (P1 — controle do cluster)

Referencia: `domains/security/network-policies/marco4/argocd-network-policy.yaml`
Permitir: ALB internal → ArgoCD (80, 443), ArgoCD → K8s API (6443), ArgoCD → GitLab (HTTPS)
Bloquear: Egress irrestrito (ArgoCD nao deve alcançar internet diretamente)

#### 4. staging-platform-gitlab (P1 — codigo fonte e CI/CD)

Referencia: `domains/security/network-policies/marco4/gitlab-network-policy.yaml`
Permitir: ALB → GitLab (80, 443, 22), GitLab → RDS (5432), GitLab → Redis (6379), GitLab → Harbor (443), GitLab → S3

#### 5. staging-platform-sonarqube (P2 — analises de seguranca)

Referencia: `domains/security/network-policies/marco4/sonarqube-network-policy.yaml`
Permitir: ALB internal → SonarQube (9000), SonarQube → RDS (5432)

### Como aplicar (modo seguro)

```bash
# Passo 1: Aplicar em modo audit (sem enforcement)
kubectl annotate namespace staging-platform-keycloak \
  policy.cilium.io/audit-mode="true"

# Passo 2: Aplicar as Network Policies
kubectl apply -f domains/security/network-policies/marco4/

# Passo 3: Monitorar por 48h
kubectl logs -n kube-system -l k8s-app=kube-dns
kubectl get networkpolicies -A

# Passo 4: Remover annotation para enforcement
kubectl annotate namespace staging-platform-keycloak \
  policy.cilium.io/audit-mode-

# Repetir por namespace, um por vez
```

---

## Compliance BACEN BCB 85/2021 — Gaps de Retencao de Logs

> **ATENCAO:** O documento v1.0 mencionava apenas retenção de 90 dias no CloudWatch para WAF e VPN. Isso é **insuficiente** para o Art. 15 da BCB 85/2021, que exige retenção de 5 anos para registros de acesso a sistemas de informação de serviços financeiros.

### Requisito legal (BCB 85/2021, Art. 15)

| Tipo de log | Retencao minima exigida | Status atual | Acao requerida |
| --- | --- | --- | --- |
| Logs de acesso a sistemas (WAF) | **5 anos** | CloudWatch 90d apenas | Exportar para S3 com lifecycle 5 anos |
| Logs de conexao VPN | **5 anos** | CloudWatch 90d apenas | Exportar para S3 com lifecycle 5 anos |
| Logs de auditoria de API (CloudTrail) | **5 anos** | Nao mencionado no doc anterior | Habilitar CloudTrail + exportar S3 5 anos |
| Logs de auditoria K8s (EKS Audit) | **5 anos** | Nao mencionado | Habilitar EKS control plane logging + S3 |

### Terraform — Exportacao de logs WAF e VPN para S3 (5 anos)

```hcl
# environments/prod/compliance-logs.tf

# S3 Bucket para logs de compliance (retencao 5 anos — BACEN BCB 85/2021)
resource "aws_s3_bucket" "compliance_logs" {
  bucket = "alvocard-platform-compliance-logs-prod"

  tags = merge(local.common_tags, {
    Name       = "compliance-logs-prod"
    Compliance = "BACEN-BCB-85-2021"
    Retention  = "5years"
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "compliance_logs" {
  bucket = aws_s3_bucket.compliance_logs.id

  rule {
    id     = "compliance-5year-retention"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "STANDARD_IA"  # mais barato após 90 dias
    }

    transition {
      days          = 365
      storage_class = "GLACIER"  # arquivamento após 1 ano
    }

    expiration {
      days = 1825  # 5 anos (365 * 5)
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "compliance_logs" {
  bucket = aws_s3_bucket.compliance_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "compliance_logs" {
  bucket = aws_s3_bucket.compliance_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Kinesis Firehose para entrega em tempo real dos logs WAF → S3
resource "aws_kinesis_firehose_delivery_stream" "waf_logs" {
  name        = "aws-waf-logs-prod-platform"  # prefixo "aws-waf-logs-" obrigatorio
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose_waf.arn
    bucket_arn = aws_s3_bucket.compliance_logs.arn
    prefix     = "waf-logs/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "waf-logs-errors/"

    buffering_size     = 5    # MB
    buffering_interval = 300  # segundos

    compression_format = "GZIP"
  }

  tags = local.common_tags
}

# Reconfigurar WAF logging para usar Firehose (5 anos via S3) em vez de CloudWatch (90d)
resource "aws_wafv2_web_acl_logging_configuration" "prod_s3" {
  # Sobrescreve a configuração CloudWatch-only com Firehose + S3
  log_destination_configs = [aws_kinesis_firehose_delivery_stream.waf_logs.arn]
  resource_arn            = aws_wafv2_web_acl.prod.arn
}
```

### CloudTrail (ausente — GAP BACEN)

```hcl
# environments/prod/cloudtrail.tf
# CloudTrail ausente do documento original — obrigatório para BACEN

resource "aws_cloudtrail" "prod" {
  name                          = "prod-platform-trail"
  s3_bucket_name                = aws_s3_bucket.compliance_logs.id
  s3_key_prefix                 = "cloudtrail"
  include_global_service_events = true
  is_multi_region_trail         = false  # us-east-1 apenas (onde está o cluster)
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::alvocard-platform-compliance-logs-prod/"]
    }
  }

  tags = merge(local.common_tags, {
    Name       = "prod-platform-trail"
    Compliance = "BACEN-BCB-85-2021"
  })
}
```

### EKS Audit Logs (ausente — GAP BACEN)

```hcl
# modules/eks/main.tf — adicionar enabled_cluster_log_types
# EKS Audit Logs ausente do documento original

resource "aws_eks_cluster" "prod" {
  # ... configurações existentes ...

  enabled_cluster_log_types = [
    "api",        # API server calls — OBRIGATÓRIO para auditoria
    "audit",      # Audit log K8s — OBRIGATÓRIO para BACEN
    "authenticator",
    "controllerManager",
    "scheduler"
  ]
}

# Os logs do EKS vão para CloudWatch /aws/eks/<cluster>/cluster
# Adicionar export para S3 via CloudWatch Logs subscription filter
resource "aws_cloudwatch_log_subscription_filter" "eks_audit_to_s3" {
  name            = "eks-audit-logs-to-s3"
  log_group_name  = "/aws/eks/k8s-platform-prod/cluster"
  filter_pattern  = ""  # exportar todos
  destination_arn = aws_kinesis_firehose_delivery_stream.eks_audit.arn
  # Criar firehose similar ao de WAF acima, com prefixo "eks-audit-logs/"
}
```

### Auditoria de VPN FortiNet (Cenario A ou B)

Se FortiNet for a solução de VPN (Cenários A ou B), os logs de conexão VPN **não ficam no CloudWatch AWS**. Eles ficam nos logs do FortiGate. Para compliance BACEN:

```text
Acoes necessarias:
  1. Confirmar que o FortiGate exporta logs para SIEM (Splunk, Elastic, etc.) com retencao 5 anos
  2. OU configurar Syslog do FortiGate → CloudWatch Logs → S3 compliance bucket (5 anos)
  3. Registrar na politica de segurança qual sistema é o sistema de registro oficial para logs VPN
  4. Incluir logs VPN no escopo da auditoria BACEN (evidencias para regulador)
```

---

## Sequencia de Implementacao

### Decisao necessaria antes de continuar

Antes de iniciar a Parte VPN, o usuario deve responder:

```text
PERGUNTA: Qual cenario FortiNet se aplica?

[ ] Cenario A: FortiGate já tem tunnel ativo para vpc-0b1396a59c417c1f0
              → VPN completa, sem nada a fazer. Continuar apenas com ALBs + WAF.

[ ] Cenario B: FortiGate existe, sem tunnel ainda
              → Criar Site-to-Site VPN (VGW + Customer GW). Preciso do IP público do FortiGate.

[ ] Cenario C1: AWS Client VPN (certificate auth) — pode implementar agora
              → Independente de Keycloak público. Pode ir junto com ALBs + WAF.

[ ] Cenario C2: AWS Client VPN (SAML/Keycloak) — depende de Fase 5
              → Somente após Keycloak com URL pública estar funcionando.

[ ] Cenario Misto: Cenário A/B para equipe interna + Cenário C para contractors/auditores
              → Ambos podem coexistir (endpoints diferentes, custos somados).
```

### Fases de execucao (por decisao)

#### Se Cenario A confirmado

```text
HOJE (sem bloqueadores):
  1. Verificar tunnel FortiGate: aws ec2 describe-vpn-connections
  2. Confirmar rotas: route tables das subnets privadas mostram rota corporativa?
  3. Mudar WAF regras 30/40/50 de Count -> Block (staging)
  4. Associar WAF existente a gitlab-staging e keycloak-staging ALBs
  5. Adicionar DEP-01 (data source subnets públicas) em environments/prod/main.tf
  6. Aplicar Network Policies ADR-070 em modo audit

AGUARDANDO GESTOR DE DOMINIO:
  7. terraform apply Route53 zona + extrair NS -> enviar para gestor
  8. Gestor cria 4 registros NS no registrar para prod.alvocard.com.br

APOS PROPAGACAO DNS:
  9. terraform apply ACM wildcard -> aguardar ISSUED
  10. Criar ALB prod-public (internet-facing) com WAF + ACM
  11. Criar ALB prod-internal (internal) com ACM + SG (aceitar CIDR rede corporativa)
  12. Criar registros DNS Route53 (alias A para ALBs)
  13. Atualizar Ingresses de todos os servicos (annotations ACM + WAF)
  14. Validar HTTPS, OIDC discovery, WAF block test
  15. Migrar ALBs de servicos internos para scheme=internal
  16. Remover windows-hosts.txt (obsoleto)
  17. Remover mode audit das Network Policies -> enforcement
  18. Provisionar compliance-logs.tf (CloudTrail + S3 5 anos + EKS audit logs)
```

#### Se Cenario B (Site-to-Site FortiGate)

```text
ADICIONAR (executar em paralelo com passo 5-6 acima):
  B1. Obter IP publico do FortiGate com equipe de rede corporativa
  B2. Obter CIDR da rede corporativa
  B3. terraform apply vpn-site-to-site.tf (Customer GW + VGW + VPN Connection)
  B4. Recuperar outputs: vpn_tunnel1_address + vpn_tunnel1_preshared_key
  B5. Enviar dados para equipe FortiGate configurar o tunnel
  B6. Verificar: aws ec2 describe-vpn-connections -> ambos tunnels UP
  B7. Testar: nslookup argocd.prod.alvocard.com.br -> IP 10.x.x.x via VPN
```

#### Se Cenario C1 (AWS Client VPN, certificate auth)

```text
PODE EXECUTAR AGORA (nao depende de Keycloak publico):
  C1a. Gerar PKI VPN (vpn-ca.key, vpn-ca.crt, vpn-server.crt) via openssl
  C1b. Upload PKI para ACM (anotar ARNs)
  C1c. Criar modulo modules/client-vpn/ com codigo C1 acima
  C1d. terraform apply modulo client-vpn
  C1e. Exportar .ovpn: aws ec2 export-client-vpn-client-configuration
  C1f. Gerar certificado cliente para cada engenheiro (eng-joao.crt etc.)
  C1g. Distribuir .ovpn + certificado cliente para cada engenheiro
  C1h. Testar: conectar -> nslookup argocd.prod -> IP privado 10.x.x.x

APOS VPN FUNCIONAL:
  (continuar sequencia de ALBs acima)
```

#### Se Cenario C2 (AWS Client VPN, SAML/Keycloak)

```text
PRE-REQUISITO OBRIGATORIO:
  [X] Fases 1-5 do plano de producao concluidas
  [X] Keycloak com URL publica keycloak.prod.alvocard.com.br funcionando
  [X] IAM Identity Center habilitado na conta

SEQUENCIAL apos pre-requisitos:
  C2a. Verificar IAM Identity Center: aws sso-admin list-instances
  C2b. Criar aplicacao SAML no IAM Identity Center para Client VPN
  C2c. Configurar Keycloak realm prod: SAML SP para IAM Identity Center
  C2d. Exportar metadata Keycloak -> upload IAM Identity Center
  C2e. Criar modulo modules/client-vpn/ com codigo C2 acima
  C2f. terraform apply modulo client-vpn (usando saml_provider_arn do passo C2d)
  C2g. Exportar .ovpn (sem certificado cliente — auth via browser SAML)
  C2h. Distribuir .ovpn para engenheiros
  C2i. Testar: conectar via AWS VPN Client -> autenticar Keycloak -> nslookup -> curl
```

---

## Validacoes de Acesso

```bash
# Pos-implementacao: executar checklist completo

# 1. Acesso publico (sem VPN)
curl -vI https://keycloak.prod.alvocard.com.br      # deve retornar 200
curl -vI https://gitlab.prod.alvocard.com.br         # deve retornar 302 (login)
curl -vI https://harbor.prod.alvocard.com.br         # deve retornar 200
curl -vI https://argocd.prod.alvocard.com.br         # deve retornar 403/timeout (ALB internal)

# 2. WAF block test (de IP nao autorizado ou pais bloqueado)
# Usar VPN externa temporaria simulando IP da China/Russia -> deve retornar 403

# 3. Acesso interno via VPN (conectar primeiro — cenario adequado ao escolhido)
nslookup argocd.prod.alvocard.com.br   # IP privado 10.x.x.x
curl https://argocd.prod.alvocard.com.br/healthz
curl https://vault.prod.alvocard.com.br/v1/sys/health
curl https://grafana.prod.alvocard.com.br/api/health

# 4. mTLS via Linkerd (apos Phase 2 completa)
linkerd viz tap -n prod-platform-keycloak deploy/keycloak \
  | grep "tls=true"  # todas as conexoes devem ter mTLS

# 5. Network Policy enforcement test
kubectl run test-pod --image=curlimages/curl -n default -- \
  curl http://keycloak.staging-platform-keycloak.svc.cluster.local:8080
# Deve falhar com connection refused (NetworkPolicy bloqueando)

# 6. Validar compliance logs
aws s3 ls s3://alvocard-platform-compliance-logs-prod/waf-logs/ --profile k8s-platform-prod
aws s3 ls s3://alvocard-platform-compliance-logs-prod/cloudtrail/ --profile k8s-platform-prod
```

---

## Resumo de Decisoes Pendentes do Usuario

| # | Decisao | Opcoes | Impacto |
| --- | --- | --- | --- |
| **D1** | Qual cenario FortiNet? | A, B, C1, C2, ou misto | Define custo VPN e sequencia de implementacao |
| **D2** | IP publico do FortiGate (se Cenario B) | Obter com equipe de rede | Necessario para `aws_customer_gateway` |
| **D3** | CIDR rede corporativa (se Cenario B) | Obter com equipe de rede | Necessario para SG do ALB internal |
| **D4** | Contractors/auditores precisam de acesso? (Cenario Misto) | Sim/Nao | Se sim: Cenario C1 adicional sobre B |
| **D5** | FortiGate exporta logs para SIEM? (compliance BACEN) | Sim/Nao/Nao sei | Se nao: configurar Syslog FortiGate -> S3 |

---

## Gate de Sucesso (checklist de validacao)

- [ ] Documento sem inconsistencia INC-05 — resolvida (C1 e C2 documentados separadamente e mutuamente exclusivos)
- [ ] Secao FortiNet com 3 cenarios documentados (A, B, C)
- [ ] Custo VPN correto por cenario (A: $0, B: ~$73/mes, C1/C2: ~$263/mes)
- [ ] Baseline custo mencionado ($1.281/mes AWS CE marco 2026)
- [ ] NAT Gateway corrigido (2 NAT GWs — risco Single-AZ nao se aplica)
- [ ] DEP-01 documentado (data source aws_subnets public ausente em prod/main.tf)
- [ ] Compliance BACEN: exportacao 5 anos S3 para WAF logs (Kinesis Firehose)
- [ ] Compliance BACEN: CloudTrail adicionado
- [ ] Compliance BACEN: EKS Audit Logs adicionados
- [ ] Compliance BACEN: FortiNet logs — orientacao de auditoria
- [ ] Codigo TF correto por opcao VPN (C1: certificate-auth; C2: federated-auth — mutuamente exclusivos)
- [ ] Sequencia de implementacao atualizada por cenario (A/B/C1/C2)

---

*Documento revalidado pela Mesa Tecnica — AWS Specialist + Security Specialist + TF Specialist*
*Versao 2.0 — 2026-03-18*
*Referencias: `2026-03-18-security-domain-vpn-prod.md` | `2026-03-18-plano-ambiente-producao.md`*
*ADRs aplicaveis: ADR-008, ADR-046, ADR-070, ADR-086, ADR-095, ADR-098, ADR-099*
