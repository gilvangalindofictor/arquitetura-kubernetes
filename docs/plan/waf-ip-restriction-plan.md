# WAF IP Restriction Plan — Protecao de Endpoints Publicos iPaaS

> **Data**: 2026-03-20
> **Status**: PLANO PENDENTE APROVACAO
> **GAP**: GAP-WAF-IP-001 — IP Allowlist para acesso do escritorio
> **Prioridade**: P0 (bloqueador de seguranca para acesso externo)
> **Autor**: Mesa Tecnica DevOps

---

## 1. Contexto e Problema

Os dominios `*.hml.alvocard.com.br` e `*.prod.alvocard.com.br` estao com DNS publico resolvivel via Route53.
Atualmente, 4 dos 7 ALBs sao **internet-facing** (acessiveis pela internet) e 3 sao **internal**.
A VPN ainda nao esta implementada. Precisamos de uma medida transitoria: **WAF com IP allowlist do escritorio**.

### Estado Atual

- WAF staging **ja existe** (`waf-k8s-platform-prod-staging`) com managed rules, rate limiting e geo-blocking
- WAF staging **default action = ALLOW** (permite todo trafego que nao bate em regras de bloqueio)
- **Nao existe IP allowlist** — nao ha `aws_wafv2_ip_set` criado
- **Nao existe WAF para prod** — modulo WAF nao esta instanciado em `environments/prod/main.tf`
- ALBs internet-facing estao com SGs abertos em `0.0.0.0/0` nas portas 80 e 443

---

## 2. Inventario de ALBs

### 2.1 ALBs Existentes (7 total)

| # | ALB Name | Scheme | WAF Associado | DNS Records Apontando | Ingress Group |
|---|----------|--------|---------------|----------------------|---------------|
| 1 | `k8s-platformstaging-00e0ecf3b4` | **internet-facing** | SIM (staging) | argocd.hml, grafana.hml, harbor.hml, keycloak.hml, rabbitmq.hml, sonarqube.hml, vault.hml | platform-staging |
| 2 | `k8s-gitlabstaging-da5a4e8c6d` | **internet-facing** | SIM (staging) | gitlab.hml, kas.hml, minio.hml | gitlab-staging |
| 3 | `k8s-stagingp-keycloak-0dbafff841` | **internet-facing** | SIM (staging) | keycloak.keycloak.example.com (legacy) | keycloakx |
| 4 | `k8s-backstagestaging-c827d564e5` | **internal** | NAO | backstage.hml | backstage-staging |
| 5 | `k8s-datainternal-b93298afa5` | **internal** | NAO | hatch.hml, hatch-api.hml, vemsoft-etl.hml | data-internal |
| 6 | `k8s-platformprod-ca65b3f8b1` | **internet-facing** | NAO | argocd.prod, access.prod (keycloak), keycloak.prod | platform-prod |
| 7 | `k8s-platformprodinter-f689ccecf4` | **internal** | NAO | harbor.prod | platform-prod-internal |

### 2.2 ARNs dos ALBs

```
# STAGING - internet-facing (3) — ja com WAF
arn:aws:elasticloadbalancing:us-east-1:891377105802:loadbalancer/app/k8s-platformstaging-00e0ecf3b4/1ef072a48e958803
arn:aws:elasticloadbalancing:us-east-1:891377105802:loadbalancer/app/k8s-gitlabstaging-da5a4e8c6d/a3785db2b304ad60
arn:aws:elasticloadbalancing:us-east-1:891377105802:loadbalancer/app/k8s-stagingp-keycloak-0dbafff841/e10bd2ceffde6421

# STAGING - internal (2) — sem WAF (nao acessiveis pela internet)
arn:aws:elasticloadbalancing:us-east-1:891377105802:loadbalancer/app/k8s-backstagestaging-c827d564e5/da8fa1f4ba218070
arn:aws:elasticloadbalancing:us-east-1:891377105802:loadbalancer/app/k8s-datainternal-b93298afa5/02478debdec7c69d

# PROD - internet-facing (1) — SEM WAF
arn:aws:elasticloadbalancing:us-east-1:891377105802:loadbalancer/app/k8s-platformprod-ca65b3f8b1/ced20c6e32f1c71b

# PROD - internal (1) — sem WAF (nao acessivel pela internet)
arn:aws:elasticloadbalancing:us-east-1:891377105802:loadbalancer/app/k8s-platformprodinter-f689ccecf4/0f7e2e0834adb0b4
```

### 2.3 Security Groups dos ALBs internet-facing

| ALB | SG Dedicado | Regras Inbound | Risco |
|-----|-------------|----------------|-------|
| platform-staging | `sg-083a7c876d6fe33ab` | 80/tcp 0.0.0.0/0, 443/tcp 0.0.0.0/0 | ALTO — aberto ao mundo |
| gitlab-staging | `sg-02e3e02a75696f9cb` | 80/tcp 0.0.0.0/0 | ALTO — aberto ao mundo |
| keycloak-staging | `sg-078cfcab3681d4f45` | 80/tcp 0.0.0.0/0, 443/tcp 0.0.0.0/0 | ALTO — aberto ao mundo |
| platform-prod | `sg-0e25f4faca5689f14` | 80/tcp 0.0.0.0/0, 443/tcp 0.0.0.0/0 | **CRITICO** — prod aberto ao mundo |

> **Nota**: Todos compartilham SG `sg-05be7680bbffb5cb3` (backend/shared) que nao tem inbound rules.

### 2.4 WAF Staging — Regras Atuais

| Prioridade | Nome | Tipo | Acao |
|------------|------|------|------|
| 10 | rate-limit-per-ip | RateBasedStatement (1000 req/5min) | BLOCK 429 |
| 20 | geo-block-high-risk-countries | GeoMatch (CN, RU, KP) | BLOCK |
| 30 | aws-managed-owasp-common | AWSManagedRulesCommonRuleSet | BLOCK |
| 40 | aws-managed-sqli | AWSManagedRulesSQLiRuleSet | BLOCK |
| 50 | aws-managed-known-bad-inputs | AWSManagedRulesKnownBadInputsRuleSet | BLOCK |

**Default Action: ALLOW** — qualquer request que nao bata nas regras acima e permitido.

---

## 3. Arquitetura Proposta

### 3.1 Diagrama ASCII

```
                        INTERNET
                           |
                    [DNS Publico]
              *.hml.alvocard.com.br
              *.prod.alvocard.com.br
                           |
                    [Route53 Alias]
                           |
              +============+============+
              |     AWS WAF v2          |
              |  (REGIONAL scope)       |
              |                         |
              |  Priority 1: IP Allow   |  <-- NOVA REGRA
              |    -> IP Set escritorio  |
              |    -> Action: ALLOW      |
              |                         |
              |  Priority 10: Rate Limit|
              |  Priority 20: Geo Block |
              |  Priority 30: OWASP     |
              |  Priority 40: SQLi      |
              |  Priority 50: Bad Input |
              |                         |
              |  Default Action: BLOCK  |  <-- MUDANCA CRITICA
              +============+============+
                           |
              +------------+------------+
              |                         |
     [ALB Staging]              [ALB Prod]
     internet-facing            internet-facing
              |                         |
     [EKS Nodes]               [EKS Nodes]
     (target groups)           (target groups)
```

### 3.2 Logica da Mudanca

**ANTES (estado atual):**
```
WAF Default Action = ALLOW
Regras = BLOCK (rate limit, geo, OWASP, SQLi, bad inputs)
Resultado: TODO mundo acessa, exceto quem bate em regra de bloqueio
```

**DEPOIS (estado desejado):**
```
WAF Default Action = BLOCK
Regra Priority 1 = ALLOW se IP esta no IP Set do escritorio
Regras Priority 10-50 = BLOCK (rate limit, geo, OWASP, SQLi, bad inputs)
Resultado: SO o escritorio acessa, E ainda passa pelas regras de protecao
```

> **ATENCAO**: A ordem de avaliacao importa. Priority 1 (IP Allow) e avaliada ANTES das managed rules.
> Se o IP do escritorio acionar uma managed rule (ex: false positive OWASP), ele sera bloqueado.
> Solucao: usar scope-down statement OU ajustar prioridades para que IP allow tenha precedencia absoluta.

### 3.3 Abordagem Recomendada — IP Allow com Scope-Down

Em vez de simplesmente mudar default action para BLOCK e adicionar uma regra ALLOW:

```
Opcao A (Simples mas arriscada):
  - Default: BLOCK
  - Rule 1: ALLOW se IP in ip_set
  - Rules 10-50: BLOCK (managed rules)
  -> PROBLEMA: IP do escritorio AINDA pode ser bloqueado por managed rules (priority 10-50)

Opcao B (Recomendada — Defense in Depth):
  - Default: BLOCK
  - Rule 1: ALLOW se IP in ip_set (avaliada primeiro, permite acesso)
  - Rules 10-50: BLOCK (managed rules) com scope-down statement "NOT in ip_set"
  -> IP do escritorio passa DIRETO, managed rules so se aplicam a trafego externo
  -> PROBLEMA: Scope-down em managed rules nao protege o escritorio contra OWASP/SQLi

Opcao C (Recomendada para transicao — mais segura):
  - Default: BLOCK
  - Rule 1: ALLOW se IP in ip_set
  - Rules 10-50: BLOCK (managed rules sem scope-down — protegem TODO trafego)
  -> IP do escritorio e permitido na Rule 1, mas Rule 1 termina avaliacao (Action=ALLOW)
  -> FATO AWS: Quando uma regra com Action=ALLOW faz match, WAF PARA de avaliar regras seguintes
  -> IP do escritorio NAO passa por managed rules
  -> Para seguranca interna: confiar no WAF externo + NetworkPolicies K8s
```

**DECISAO RECOMENDADA: Opcao C**
- Simples de implementar
- IP do escritorio e confiavel (rede corporativa)
- Managed rules protegem contra trafego externo (que sera bloqueado pelo default BLOCK anyway)
- Quando VPN estiver pronta, remover IP set e reverter default para ALLOW

---

## 4. Mudancas no Modulo Terraform

### 4.1 Novas Variaveis — `modules/waf/variables.tf`

```hcl
#------------------------------------------------------------------------------
# IP Allowlist (Priority 1) — GAP-WAF-IP-001
#------------------------------------------------------------------------------

variable "enable_ip_allowlist" {
  description = "Enable IP-based allowlist rule. When true, only IPs in allowed_ipv4_cidrs are permitted (default action changes to BLOCK). Transitional measure until VPN is ready."
  type        = bool
  default     = false
}

variable "allowed_ipv4_cidrs" {
  description = "List of IPv4 CIDR blocks to allow through WAF when enable_ip_allowlist=true. Typically the office public IP(s). Format: [\"203.0.113.10/32\", \"198.51.100.0/24\"]"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.allowed_ipv4_cidrs : can(cidrhost(cidr, 0))])
    error_message = "All entries in allowed_ipv4_cidrs must be valid IPv4 CIDR blocks (e.g., 203.0.113.10/32)."
  }
}

variable "allowed_ipv6_cidrs" {
  description = "List of IPv6 CIDR blocks to allow through WAF when enable_ip_allowlist=true. Leave empty if office does not use IPv6."
  type        = list(string)
  default     = []
}

variable "ip_allowlist_description" {
  description = "Description for the IP set resource (visible in AWS Console)."
  type        = string
  default     = "Office IP allowlist - transitional measure until VPN deployment"
}
```

### 4.2 Novos Resources — `modules/waf/main.tf`

Adicionar ANTES do resource `aws_wafv2_web_acl`:

```hcl
# -----------------------------------------------------------------------------
# IP Set — Office Allowlist (GAP-WAF-IP-001)
# Created when enable_ip_allowlist = true.
# Contains the public IP(s) of the office for WAF allowlist filtering.
# Transitional: will be removed when VPN is deployed.
# -----------------------------------------------------------------------------

resource "aws_wafv2_ip_set" "office_allowlist_v4" {
  count = var.enable_ip_allowlist ? 1 : 0

  name               = "office-allowlist-v4-${local.name_prefix}"
  description        = var.ip_allowlist_description
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = var.allowed_ipv4_cidrs

  tags = merge(var.common_tags, {
    Name    = "office-allowlist-v4-${local.name_prefix}"
    Purpose = "GAP-WAF-IP-001 transitional IP allowlist"
    Module  = "waf"
  })
}

resource "aws_wafv2_ip_set" "office_allowlist_v6" {
  count = var.enable_ip_allowlist && length(var.allowed_ipv6_cidrs) > 0 ? 1 : 0

  name               = "office-allowlist-v6-${local.name_prefix}"
  description        = var.ip_allowlist_description
  scope              = "REGIONAL"
  ip_address_version = "IPV6"
  addresses          = var.allowed_ipv6_cidrs

  tags = merge(var.common_tags, {
    Name    = "office-allowlist-v6-${local.name_prefix}"
    Purpose = "GAP-WAF-IP-001 transitional IP allowlist"
    Module  = "waf"
  })
}
```

### 4.3 Mudanca no WebACL — Default Action Condicional

Alterar o bloco `default_action` no resource `aws_wafv2_web_acl "main"`:

```hcl
  # Default action: BLOCK when IP allowlist is active, ALLOW otherwise
  # When IP allowlist is active, only whitelisted IPs pass through Rule 1.
  # All other traffic is blocked by default.
  dynamic "default_action" {
    for_each = var.enable_ip_allowlist ? [1] : []
    content {
      block {
        custom_response {
          response_code = 403
          response_header {
            name  = "X-WAF-Block-Reason"
            value = "ip-not-in-allowlist"
          }
        }
      }
    }
  }

  dynamic "default_action" {
    for_each = var.enable_ip_allowlist ? [] : [1]
    content {
      allow {}
    }
  }
```

### 4.4 Nova Regra — IP Allow (Priority 1)

Adicionar como primeiro `dynamic "rule"` dentro do `aws_wafv2_web_acl "main"`:

```hcl
  # ---------------------------------------------------------------------------
  # Rule 0 — IP Allowlist (Priority 1) — GAP-WAF-IP-001
  # When enabled, ONLY requests from IPs in the allowlist are permitted.
  # This rule is evaluated FIRST (lowest priority number).
  # Match: source IP in office_allowlist_v4 OR office_allowlist_v6
  # Action: ALLOW (terminates rule evaluation — request is permitted)
  # Combined with default_action=BLOCK, this creates an effective IP whitelist.
  # ---------------------------------------------------------------------------
  dynamic "rule" {
    for_each = var.enable_ip_allowlist ? [1] : []

    content {
      name     = "ip-allowlist-office"
      priority = 1

      statement {
        or_statement {
          statement {
            ip_set_reference_statement {
              arn = aws_wafv2_ip_set.office_allowlist_v4[0].arn
            }
          }

          # Include IPv6 set only if it was created
          dynamic "statement" {
            for_each = length(var.allowed_ipv6_cidrs) > 0 ? [1] : []
            content {
              ip_set_reference_statement {
                arn = aws_wafv2_ip_set.office_allowlist_v6[0].arn
              }
            }
          }
        }
      }

      action {
        allow {}
      }

      visibility_config {
        cloudwatch_metrics_enabled = var.cloudwatch_metrics_enabled
        metric_name                = "waf-ip-allowlist-${var.environment}"
        sampled_requests_enabled   = var.enable_sampled_requests
      }
    }
  }
```

> **NOTA IMPORTANTE sobre or_statement**: AWS WAF exige que `or_statement` tenha no minimo 2 statements.
> Se `allowed_ipv6_cidrs` estiver vazio, o dynamic statement nao sera criado, e `or_statement` tera apenas 1 statement, o que causa ERRO.
> **Solucao**: Quando nao ha IPv6, usar `ip_set_reference_statement` direto (sem or_statement). Implementar com condicional:

```hcl
  dynamic "rule" {
    for_each = var.enable_ip_allowlist && length(var.allowed_ipv6_cidrs) == 0 ? [1] : []

    content {
      name     = "ip-allowlist-office"
      priority = 1

      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.office_allowlist_v4[0].arn
        }
      }

      action {
        allow {}
      }

      visibility_config {
        cloudwatch_metrics_enabled = var.cloudwatch_metrics_enabled
        metric_name                = "waf-ip-allowlist-${var.environment}"
        sampled_requests_enabled   = var.enable_sampled_requests
      }
    }
  }

  dynamic "rule" {
    for_each = var.enable_ip_allowlist && length(var.allowed_ipv6_cidrs) > 0 ? [1] : []

    content {
      name     = "ip-allowlist-office"
      priority = 1

      statement {
        or_statement {
          statement {
            ip_set_reference_statement {
              arn = aws_wafv2_ip_set.office_allowlist_v4[0].arn
            }
          }
          statement {
            ip_set_reference_statement {
              arn = aws_wafv2_ip_set.office_allowlist_v6[0].arn
            }
          }
        }
      }

      action {
        allow {}
      }

      visibility_config {
        cloudwatch_metrics_enabled = var.cloudwatch_metrics_enabled
        metric_name                = "waf-ip-allowlist-${var.environment}"
        sampled_requests_enabled   = var.enable_sampled_requests
      }
    }
  }
```

### 4.5 Novos Outputs — `modules/waf/outputs.tf`

```hcl
#------------------------------------------------------------------------------
# IP Allowlist (GAP-WAF-IP-001)
#------------------------------------------------------------------------------

output "waf_ip_allowlist_enabled" {
  description = "Whether IP allowlist is active on this WAF WebACL."
  value       = var.enable_ip_allowlist
}

output "waf_ip_set_v4_arn" {
  description = "ARN of the IPv4 IP set used for office allowlist. Empty when disabled."
  value       = var.enable_ip_allowlist ? aws_wafv2_ip_set.office_allowlist_v4[0].arn : ""
}

output "waf_default_action" {
  description = "Current default action of the WAF WebACL (allow or block)."
  value       = var.enable_ip_allowlist ? "block" : "allow"
}
```

---

## 5. Mudancas nos Environments

### 5.1 Staging — `environments/staging/variables.tf`

```hcl
#------------------------------------------------------------------------------
# WAF IP Allowlist (GAP-WAF-IP-001)
#------------------------------------------------------------------------------

variable "waf_enable_ip_allowlist" {
  description = "Enable WAF IP allowlist (office only). Default action becomes BLOCK."
  type        = bool
  default     = false
}

variable "waf_allowed_ipv4_cidrs" {
  description = "Office public IPv4 CIDR(s) for WAF allowlist."
  type        = list(string)
  default     = []
}
```

### 5.2 Staging — `environments/staging/main.tf` (modulo waf_staging)

Adicionar ao bloco `module "waf_staging"`:

```hcl
  # IP Allowlist (GAP-WAF-IP-001) — transitional until VPN
  enable_ip_allowlist = var.waf_enable_ip_allowlist
  allowed_ipv4_cidrs  = var.waf_allowed_ipv4_cidrs
```

### 5.3 Staging — `environments/staging/terraform.tfvars`

```hcl
# WAF IP Allowlist — GAP-WAF-IP-001
# ATENCAO: Substituir pelo IP publico real do escritorio
# Para descobrir: curl -4 ifconfig.me (executar de dentro do escritorio)
waf_enable_ip_allowlist = true
waf_allowed_ipv4_cidrs  = ["<IP_ESCRITORIO>/32"]   # TODO: obter IP real
```

### 5.4 Prod — `environments/prod/main.tf`

**Prod nao tem WAF instanciado.** Criar bloco:

```hcl
# ==============================================================================
# WAF v2 — Production (GAP-010 + GAP-WAF-IP-001)
# ==============================================================================

module "waf_prod" {
  source = "../../modules/waf"

  environment  = "production"
  cluster_name = local.cluster_name
  common_tags  = local.common_tags

  # Primary ALB — platform-prod (internet-facing)
  alb_arn = data.aws_lb.platform_prod_alb.arn

  # Rate limiting (mais conservador em prod)
  rate_limit = var.waf_rate_limit

  # Geographic blocking
  enable_geo_blocking = var.waf_enable_geo_blocking
  blocked_countries   = var.waf_blocked_countries

  # Managed rule groups
  enable_owasp_common_ruleset     = true
  enable_sqli_ruleset             = true
  enable_known_bad_inputs_ruleset = true

  # IP Allowlist (GAP-WAF-IP-001)
  enable_ip_allowlist = var.waf_enable_ip_allowlist
  allowed_ipv4_cidrs  = var.waf_allowed_ipv4_cidrs

  # Logging
  enable_logging     = true
  create_log_bucket  = true
  log_retention_days = var.waf_log_retention_days

  # Observability
  cloudwatch_metrics_enabled = true
  enable_sampled_requests    = true
}
```

> **NOTA**: Sera necessario criar `data "aws_lb" "platform_prod_alb"` para buscar o ARN do ALB prod.

---

## 6. Plano de Execucao — Fases

### Fase 0 — Pre-requisitos (BLOQUEADOR)

| # | Acao | Status | Responsavel |
|---|------|--------|-------------|
| 0.1 | **Obter IP publico do escritorio** | PENDENTE | Usuario |
| 0.2 | Validar que IP e estatico (nao DHCP dinamico do ISP) | PENDENTE | Usuario |
| 0.3 | Se IP dinamico: considerar DDNS ou range /24 do ISP | PENDENTE | Usuario |

```bash
# Executar de dentro do escritorio:
curl -4 ifconfig.me
# Resultado esperado: ex. 177.71.XXX.YYY
```

### Fase 1 — Modulo WAF (codigo)

| # | Acao | Ambiente | Risco |
|---|------|----------|-------|
| 1.1 | Adicionar variaveis IP allowlist em `modules/waf/variables.tf` | Modulo | Nenhum |
| 1.2 | Adicionar resources `aws_wafv2_ip_set` em `modules/waf/main.tf` | Modulo | Nenhum |
| 1.3 | Alterar `default_action` para condicional em `modules/waf/main.tf` | Modulo | **ALTO** |
| 1.4 | Adicionar regra IP allowlist (priority 1) em `modules/waf/main.tf` | Modulo | Medio |
| 1.5 | Adicionar outputs em `modules/waf/outputs.tf` | Modulo | Nenhum |

### Fase 2 — Staging Apply

| # | Acao | Detalhe |
|---|------|---------|
| 2.1 | Adicionar variaveis em `staging/variables.tf` | `waf_enable_ip_allowlist`, `waf_allowed_ipv4_cidrs` |
| 2.2 | Passar variaveis no `module "waf_staging"` em `staging/main.tf` | 2 linhas |
| 2.3 | Definir valores em `staging/terraform.tfvars` | IP real do escritorio |
| 2.4 | `terraform plan` — revisar changeset | Esperar: IP Set create, WebACL update |
| 2.5 | `terraform apply` | Aplicar em staging |
| 2.6 | **TESTE IMEDIATO**: acessar `argocd.hml.alvocard.com.br` do escritorio | Deve funcionar |
| 2.7 | **TESTE IMEDIATO**: acessar de IP externo (4G celular) | Deve retornar 403 |
| 2.8 | Verificar CloudWatch metrics `waf-ip-allowlist-staging` | Deve mostrar AllowedRequests |

### Fase 3 — Prod WAF Deploy

| # | Acao | Detalhe |
|---|------|---------|
| 3.1 | Criar `data "aws_lb"` para ALB prod em `prod/main.tf` | Lookup por tag ou nome |
| 3.2 | Criar `module "waf_prod"` em `prod/main.tf` | Copiar padrao staging |
| 3.3 | Adicionar variaveis em `prod/variables.tf` | Ja parcialmente existe |
| 3.4 | Definir valores em `prod/terraform.tfvars` | Mesmo IP do escritorio |
| 3.5 | `terraform plan` + `terraform apply` | Criar WAF prod + associar ALB |
| 3.6 | **TESTE**: acessar `argocd.prod.alvocard.com.br` do escritorio | Deve funcionar |
| 3.7 | **TESTE**: acessar de IP externo | Deve retornar 403 |

### Fase 4 — ALBs Internos (Backstage, Data, Harbor-Prod)

**Decisao necessaria**: migrar ALBs internos para internet-facing?

| ALB | Servicos | Recomendacao |
|-----|----------|-------------|
| backstage-staging (internal) | backstage.hml | **SIM** — migrar para internet-facing + WAF |
| data-internal (internal) | hatch.hml, hatch-api.hml, vemsoft-etl.hml | **AVALIAR** — se precisa acesso externo |
| platform-prod-internal (internal) | harbor.prod | **NAO** — Harbor deve ficar interno (pull via nodes) |

Para migrar um ALB de internal para internet-facing:
1. Alterar annotation no Ingress: `alb.ingress.kubernetes.io/scheme: internet-facing`
2. AWS LBC recria o ALB (novo ARN, novo DNS)
3. Atualizar Route53 alias para novo ALB
4. Associar WAF ao novo ALB
5. **RISCO**: downtime durante recriacao do ALB (1-3 min)

### Fase 5 — Monitoramento

| # | Acao |
|---|------|
| 5.1 | Criar CloudWatch alarm: `waf-ip-allowlist-staging BlockedRequests > 100/min` |
| 5.2 | Criar CloudWatch alarm: `waf-ip-allowlist-staging AllowedRequests = 0 por 10min` (indica problema) |
| 5.3 | Verificar WAF logs no S3: `aws-waf-logs-k8s-platform-prod-staging` |
| 5.4 | Criar dashboard Grafana via YACE CloudWatch Exporter (metricas WAF) |

---

## 7. Riscos e Mitigacoes

| # | Risco | Impacto | Probabilidade | Mitigacao |
|---|-------|---------|---------------|-----------|
| R1 | IP do escritorio muda (ISP dinamico) | **CRITICO** — perda total de acesso | Media | Usar range /24 do ISP; monitorar via alarm; documentar processo de atualizacao rapida |
| R2 | Default BLOCK bloqueia trafego legitimo nao previsto | Alto | Baixa | Testar exaustivamente em staging; manter `enable_ip_allowlist = false` como rollback |
| R3 | Managed rules bloqueiam requests do escritorio (false positive) | Medio | Media | ALLOW na priority 1 termina avaliacao — managed rules nao sao avaliadas para IPs permitidos |
| R4 | AWS LBC recria ALB e perde associacao WAF | Alto | Baixa | WAF association via Terraform (nao manual); associar por tag/data source |
| R5 | Acesso remoto (home office) bloqueado | Alto | Alta | Adicionar IPs de VPN/home no ip_set; OU manter VPN como solucao definitiva |
| R6 | KAS (GitLab Agent) para de funcionar | Alto | Media | KAS usa WebSocket de dentro do cluster (node→ALB); verificar se trafego e intra-VPC |
| R7 | Webhooks externos bloqueados (ex: GitHub→GitLab mirror) | Medio | Media | Adicionar IPs de servicos externos no ip_set se necessario |
| R8 | Terraform state lock durante apply | Baixo | Baixa | Coordenar janela de manutencao |

### Rollback Plan

```bash
# Rollback IMEDIATO (< 1 min): desabilitar IP allowlist
# Em terraform.tfvars:
waf_enable_ip_allowlist = false

# Aplicar:
terraform apply -var="waf_enable_ip_allowlist=false"

# Resultado: default action volta para ALLOW, IP set e destruido
# Downtime: 0 (WAF update e atomic)
```

---

## 8. Alternativas Consideradas

### 8.1 VPN Only (ALBs internos + VPN)

| Aspecto | Avaliacao |
|---------|-----------|
| Seguranca | Excelente — zero exposicao publica |
| Complexidade | Alta — precisa configurar VPN server, client configs, routing |
| Timeline | Semanas (VPN nao esta pronta) |
| Custo | ~$75/mes (VPN instance + NAT gateway) |
| **Veredicto** | Solucao definitiva, mas nao disponivel agora |

### 8.2 CloudFront + WAF (em vez de ALB + WAF direto)

| Aspecto | Avaliacao |
|---------|-----------|
| Seguranca | Excelente — ALBs podem permanecer internos |
| Complexidade | Alta — CloudFront + Origin Shield + ACM em us-east-1 |
| Performance | Melhor (CDN cache) |
| Custo | ~$10-50/mes adicional (CloudFront requests + transfer) |
| **Veredicto** | Overengineering para uso interno; considerar pos-VPN |

### 8.3 WAF + ALB Internet-Facing + IP Restriction (RECOMENDADA)

| Aspecto | Avaliacao |
|---------|-----------|
| Seguranca | Boa — IP allowlist + managed rules + rate limit |
| Complexidade | Baixa — modulo WAF ja existe, apenas adicionar IP set |
| Timeline | 1-2 dias (codigo + apply + teste) |
| Custo | +$0 incremental (WAF ja existe; IP set nao tem custo adicional) |
| **Veredicto** | Melhor custo-beneficio para medida transitoria |

---

## 9. Estimativa de Custo Mensal

### WAF (ja existente — staging)

| Item | Custo |
|------|-------|
| WebACL | $5.00/mes |
| Rules (5 existentes + 1 nova IP allowlist) | $6.00/mes ($1/rule) |
| Requests (estimativa 1M/mes) | $0.60/mes |
| IP Set | $0.00 (sem custo adicional) |
| S3 Logs (estimativa 1GB/mes) | $0.02/mes |
| **Subtotal Staging** | **~$11.62/mes** |

### WAF (novo — prod)

| Item | Custo |
|------|-------|
| WebACL | $5.00/mes |
| Rules (6 regras) | $6.00/mes |
| Requests (estimativa 500K/mes) | $0.30/mes |
| IP Set | $0.00 |
| S3 Logs | $0.01/mes |
| **Subtotal Prod** | **~$11.31/mes** |

### Total Incremental

| Item | Custo |
|------|-------|
| Staging (IP rule adicional) | +$1.00/mes |
| Prod (WebACL + rules novos) | +$11.31/mes |
| **Total incremental** | **~$12.31/mes** |

---

## 10. Checklist de Validacao

### Pre-Apply

- [ ] IP publico do escritorio obtido e confirmado como estatico
- [ ] Modulo WAF atualizado com IP allowlist (variables, resources, outputs)
- [ ] Staging `terraform plan` revisado — sem surpresas
- [ ] Plano de rollback documentado e testado mentalmente

### Pos-Apply Staging

- [ ] `terraform plan` retorna "No changes" (zero drift)
- [ ] WAF WebACL atualizado com default action BLOCK
- [ ] IP Set criado com IP do escritorio
- [ ] Regra `ip-allowlist-office` visivel no AWS Console com priority 1
- [ ] Acesso do escritorio: `curl -I https://argocd.hml.alvocard.com.br` retorna 200
- [ ] Acesso externo: `curl -I https://argocd.hml.alvocard.com.br` retorna 403
- [ ] CloudWatch metrics `waf-ip-allowlist-staging` mostrando dados
- [ ] WAF logs no S3 mostrando BLOCK para IPs externos
- [ ] GitLab CI/CD pipelines continuam funcionando (runners sao internos ao cluster)
- [ ] ArgoCD sync continua funcionando (server-to-repo e outbound)

### Pos-Apply Prod

- [ ] `terraform plan` retorna "No changes"
- [ ] WAF WebACL prod criado e associado ao ALB prod
- [ ] Acesso do escritorio a `argocd.prod.alvocard.com.br` funciona
- [ ] Acesso do escritorio a `access.prod.alvocard.com.br` (Keycloak) funciona
- [ ] Acesso externo bloqueado

### Pos-VPN (futuro — reverter WAF IP allowlist)

- [ ] VPN funcional e testada
- [ ] `waf_enable_ip_allowlist = false` em staging e prod
- [ ] `terraform apply` — default action volta para ALLOW
- [ ] IP Sets destruidos automaticamente
- [ ] ALBs podem voltar a internal (se VPN cobre todos os casos de uso)

---

## 11. Dados Pendentes do Usuario

| # | Dado | Para que | Status |
|---|------|----------|--------|
| 1 | **IP publico do escritorio** (IPv4) | IP Set WAF | **PENDENTE** |
| 2 | IP e estatico ou dinamico? | Definir CIDR (/32 vs /24) | **PENDENTE** |
| 3 | Existe acesso remoto (home office)? | Adicionar IPs extras | **PENDENTE** |
| 4 | Backstage precisa de acesso externo? | Decidir migracao ALB internal→internet-facing | **PENDENTE** |
| 5 | Hatch/VemSoft ETL precisa acesso externo? | Decidir migracao ALB data-internal | **PENDENTE** |
| 6 | Existem webhooks externos (GitHub, Slack, etc)? | Adicionar IPs ao allowlist | **PENDENTE** |

---

## 12. Proximos Passos

1. **IMEDIATO**: Usuario fornece IP do escritorio
2. **DIA 1**: Implementar mudancas no modulo WAF + staging `terraform plan`
3. **DIA 1**: `terraform apply` em staging + testes de acesso
4. **DIA 2**: `terraform apply` em prod (WAF novo) + testes
5. **DIA 2**: Monitoramento CloudWatch + alarmes
6. **FUTURO**: VPN → reverter IP allowlist → ALBs voltam para internal
