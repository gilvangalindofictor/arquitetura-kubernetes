# Setup de Domínio para Produção — alvocard.com.br

**Data:** 2026-03-18 | **Atualizado:** 2026-03-19 | **Domínio:** alvocard.com.br | **Registrar:** a identificar
**Conta AWS:** 891377105802 | **Região:** us-east-1 | **Status:** AGUARDANDO AÇÃO EXTERNA
**Versão:** 3.0 — Delegação de subdomínio (apex intocado no registrar)

---

## Resumo

O ambiente opera hoje com domínios fictícios `*.staging.internal` resolvidos via CoreDNS split-horizon dentro do cluster. Não existe zona pública no Route53 nem certificado ACM válido para browsers.

**Estratégia adotada (v3.0): Delegação de subdomínio — apex intocado.**

O gestor de domínio **apenas adiciona registros NS** no registrar para os subdomínios `prod` e `hml`. O apex `alvocard.com.br` permanece 100% no registrar atual — email, site, MX, SPF, tudo intocado. Zero risco.

**Zonas delegadas (2 delegações):**

| Subdomínio | Ambiente | Propósito |
|-----------|----------|-----------|
| `prod.alvocard.com.br` | Produção | Todos os serviços prod: `keycloak.prod.alvocard.com.br`, `ipaas.prod.alvocard.com.br`, etc. |
| `hml.alvocard.com.br` | Homologação | Todos os serviços staging: `keycloak.hml.alvocard.com.br`, `ipaas.hml.alvocard.com.br`, etc. |

**Quem faz o que:**

| Responsável | Ação | Tempo | Frequência |
|------------|------|-------|-----------|
| Engenheiro DevOps | `terraform apply` — criar 2 hosted zones no Route53 | 10 min | 1x |
| Engenheiro DevOps | Enviar os NS ao gestor (4 NS por zona = 8 registros total) | 5 min | 1x |
| **Gestor de domínio** | **Adicionar 8 registros NS no registrar (4 para prod + 4 para hml)** | **15 min** | **1x — DEFINITIVO** |
| Engenheiro DevOps | Validar propagação + provisionar ACM + ALBs + registros | 60 min | 1x |
| Engenheiro DevOps | Novos serviços dentro de prod/hml | 2 min | Autônomo — sem gestor |

**Bloqueador externo:** A adição dos 8 registros NS é a única ação do gestor. Após isso, temos autonomia total dentro de `*.prod.alvocard.com.br` e `*.hml.alvocard.com.br`.

---

## Histórico de Versões

| Versão | Estratégia | Status | Motivo da mudança |
|--------|-----------|--------|-------------------|
| v1.0 | Delegação de `prod.alvocard.com.br` apenas | Substituída | Cobria apenas prod |
| v2.0 | Migração do apex para Route53 | Substituída | Risco alto (MX/email), dependência do gestor para auditoria completa |
| **v3.0** | **Delegação de 2 subdomínios (prod + hml)** | **ATIVA** | Menor risco, apex intocado, 2 delegações cobrem todos os cenários |

---

## Arquitetura DNS

```
Registrar (alvocard.com.br) — INTOCADO
    │
    ├── alvocard.com.br          → Registros existentes (MX, SPF, site, etc.) — SEM MUDANÇA
    ├── www.alvocard.com.br      → Como está — SEM MUDANÇA
    │
    ├── prod.alvocard.com.br  NS → 4 nameservers Route53    ← ÚNICO REGISTRO NOVO (prod)
    │       │
    │       └── Route53 — Hosted Zone: prod.alvocard.com.br
    │               ├── keycloak.prod.alvocard.com.br  → ALB internet-facing (público)
    │               ├── gitlab.prod.alvocard.com.br    → ALB internet-facing (público)
    │               ├── kas.prod.alvocard.com.br       → ALB internet-facing (público)
    │               ├── harbor.prod.alvocard.com.br    → ALB internet-facing (público)
    │               ├── hatch-api.prod.alvocard.com.br → ALB internet-facing (público)
    │               ├── hatch.prod.alvocard.com.br     → ALB internet-facing (público)
    │               ├── ipaas.prod.alvocard.com.br     → ALB internet-facing (público)
    │               ├── argocd.prod.alvocard.com.br    → ALB internal (VPN)
    │               ├── grafana.prod.alvocard.com.br   → ALB internal (VPN)
    │               ├── vault.prod.alvocard.com.br     → ALB internal (VPN)
    │               ├── sonarqube.prod.alvocard.com.br → ALB internal (VPN)
    │               ├── backstage.prod.alvocard.com.br → ALB internal (VPN)
    │               └── (qualquer novo serviço prod — via Terraform, sem gestor)
    │
    └── hml.alvocard.com.br  NS → 4 nameservers Route53     ← ÚNICO REGISTRO NOVO (hml)
            │
            └── Route53 — Hosted Zone: hml.alvocard.com.br
                    ├── keycloak.hml.alvocard.com.br   → ALB staging
                    ├── gitlab.hml.alvocard.com.br     → ALB staging
                    ├── harbor.hml.alvocard.com.br     → ALB staging
                    ├── ipaas.hml.alvocard.com.br      → ALB staging
                    ├── grafana.hml.alvocard.com.br    → ALB staging
                    └── (qualquer novo serviço hml — via Terraform, sem gestor)
```

**Padrão de nomes:** Serviços idênticos em ambos os ambientes, diferenciados pelo subdomínio:

| Serviço | Produção | Homologação |
|---------|----------|-------------|
| Keycloak SSO | `keycloak.prod.alvocard.com.br` | `keycloak.hml.alvocard.com.br` |
| iPaaS | `ipaas.prod.alvocard.com.br` | `ipaas.hml.alvocard.com.br` |
| GitLab | `gitlab.prod.alvocard.com.br` | `gitlab.hml.alvocard.com.br` |
| Hatch ETL | `hatch.prod.alvocard.com.br` | `hatch.hml.alvocard.com.br` |
| Grafana | `grafana.prod.alvocard.com.br` | `grafana.hml.alvocard.com.br` |

---

## Hosted Zones a Criar (Route53)

| Zona | Tipo | Propósito |
|------|------|-----------|
| `prod.alvocard.com.br` | Pública | Todos os serviços de produção |
| `hml.alvocard.com.br` | Pública | Todos os serviços de homologação/staging |

**Custo:** $0.50/mês por hosted zone = $1.00/mês total.

---

## Certificados ACM

| Certificado | Cobre | Quando criar |
|------------|-------|-------------|
| `*.prod.alvocard.com.br` | Todos os serviços prod | Após delegação NS confirmada |
| `*.hml.alvocard.com.br` | Todos os serviços hml | Após delegação NS confirmada |

**Validação DNS:** ACM cria um registro CNAME na hosted zone Route53. Como temos controle da zona, a validação é automática.

**Renovação:** Automática pelo ACM 60 dias antes da expiração. Não requer ação humana.

---

## Mapa de Subdomínios por Serviço

### Produção (`*.prod.alvocard.com.br`)

| Serviço | URL Produção | Tipo | Namespace |
|---------|-------------|------|-----------|
| Keycloak SSO | `keycloak.prod.alvocard.com.br` | **Público** | prod-platform-keycloak |
| GitLab CE | `gitlab.prod.alvocard.com.br` | **Público** | staging-platform-gitlab (compartilhado) |
| GitLab KAS | `kas.prod.alvocard.com.br` | **Público** | staging-platform-gitlab (compartilhado) |
| Harbor Registry | `harbor.prod.alvocard.com.br` | **Público** | prod-platform-harbor |
| Hatch ETL API | `hatch-api.prod.alvocard.com.br` | **Público** | prod-data-hatch-etl |
| Hatch Web UI | `hatch.prod.alvocard.com.br` | **Público** | prod-data-hatch-etl |
| iPaaS | `ipaas.prod.alvocard.com.br` | **Público** | prod-data-ipaas |
| ArgoCD | `argocd.prod.alvocard.com.br` | Interno (VPN) | prod-platform-argocd |
| Grafana | `grafana.prod.alvocard.com.br` | Interno (VPN) | prod-observability-monitoring |
| Vault | `vault.prod.alvocard.com.br` | Interno (VPN) | prod-security-vault |
| SonarQube | `sonarqube.prod.alvocard.com.br` | Interno (VPN) | prod-platform-sonarqube |
| Backstage IDP | `backstage.prod.alvocard.com.br` | Interno (VPN) | prod-platform-backstage |
| RabbitMQ Mgmt | `rabbitmq.prod.alvocard.com.br` | Interno (VPN) | prod-data-services |

### Homologação (`*.hml.alvocard.com.br`)

| Serviço | URL Homologação | Tipo | Namespace |
|---------|----------------|------|-----------|
| Keycloak SSO | `keycloak.hml.alvocard.com.br` | Misto | staging-platform-keycloak |
| GitLab CE | `gitlab.hml.alvocard.com.br` | Misto | staging-platform-gitlab |
| Harbor Registry | `harbor.hml.alvocard.com.br` | Misto | harbor-system |
| iPaaS | `ipaas.hml.alvocard.com.br` | Misto | staging-data-ipaas |
| Grafana | `grafana.hml.alvocard.com.br` | Interno (VPN) | staging-observability-monitoring |
| Hatch ETL | `hatch.hml.alvocard.com.br` | Misto | staging-data-hatch-etl |

---

## CHECKLIST PARA O GESTOR DE DOMÍNIO

> **ATENÇÃO — Esta seção é destinada ao responsável pelo domínio alvocard.com.br no registrar.**
> O apex e registros existentes (email, site, MX, SPF) NÃO são afetados.
> É uma operação aditiva e segura — apenas adiciona registros novos.

---

### Contexto (ler antes de agir)

A equipe técnica precisa que 2 subdomínios (`prod` e `hml`) sejam direcionados para a AWS. Para isso, basta adicionar registros NS no registrar. É como adicionar um registro CNAME — mesma interface, mesma simplicidade.

**O que NÃO muda:** Nada. O domínio `alvocard.com.br`, email, site, MX, SPF, DKIM — tudo continua funcionando exatamente como está.

**O que muda:** Consultas DNS para `*.prod.alvocard.com.br` e `*.hml.alvocard.com.br` passam a ser resolvidas pela AWS. Apenas isso.

---

### AÇÃO ÚNICA — Adicionar 8 registros NS

A equipe técnica enviará **8 registros** (4 para prod + 4 para hml). Adicione-os no painel de DNS do registrar:

```
REGISTROS PARA PRODUÇÃO (prod.alvocard.com.br):

Tipo    Nome                     Valor                              TTL
NS      prod.alvocard.com.br     ns-1292.awsdns-33.org              3600
NS      prod.alvocard.com.br     ns-1698.awsdns-20.co.uk            3600
NS      prod.alvocard.com.br     ns-684.awsdns-21.net               3600
NS      prod.alvocard.com.br     ns-277.awsdns-34.com               3600


REGISTROS PARA HOMOLOGAÇÃO (hml.alvocard.com.br):

Tipo    Nome                     Valor                              TTL
NS      hml.alvocard.com.br      ns-1415.awsdns-48.org              3600
NS      hml.alvocard.com.br      ns-1958.awsdns-52.co.uk            3600
NS      hml.alvocard.com.br      ns-719.awsdns-25.net               3600
NS      hml.alvocard.com.br      ns-377.awsdns-47.com               3600
```

> **Zonas criadas em 2026-03-19.** Valores acima são definitivos — prontos para cadastro no registrar.

---

### Resumo executivo para o gestor

```
O QUE VOCÊ FAZ:          Adicionar 8 registros NS no painel de DNS do registrar
PARA QUAIS NOMES:        prod.alvocard.com.br (4 NS) + hml.alvocard.com.br (4 NS)
O QUE NÃO MUDA:          Absolutamente nada — apex, email, site, MX, SPF intocados
QUANTO TEMPO LEVA:        15 minutos
QUANDO FAZER:             Após receber os NS exatos da equipe técnica
RISCO:                    Zero — é aditivo (adiciona registros novos, não altera existentes)
ROLLBACK:                 Remover os 8 registros — volta ao estado original instantaneamente
AÇÕES FUTURAS:            Nenhuma — equipe técnica gerencia tudo dentro de prod/hml
```

---

### O QUE NÃO FAZER

```
NÃO trocar os Name Servers do apex alvocard.com.br
    → O apex continua no registrar atual — intocado

NÃO alterar registros A, MX, TXT, CNAME existentes
    → Tudo que existe hoje continua funcionando

NÃO adquirir certificado SSL pelo registrar
    → A AWS emite certificados gratuitamente (ACM)

NÃO criar registros A ou CNAME para prod.alvocard.com.br
    → Apenas registros NS (delegação) — a equipe cuida do resto na AWS
```

---

## Configuração Terraform

**Arquivo:** `platform-provisioning/aws/kubernetes/terraform/environments/prod/dns-acm.tf`

```hcl
# =============================================================================
# Route53 Hosted Zones — Delegação de subdomínio (v3.0)
# Apex alvocard.com.br permanece no registrar — intocado
# =============================================================================

# --- Zona PROD ---
resource "aws_route53_zone" "prod" {
  name    = "prod.alvocard.com.br"
  comment = "Produção — delegado do apex via NS records no registrar"

  tags = merge(local.common_tags, {
    Domain      = "prod"
    Environment = "production"
  })
}

# --- Zona HML ---
resource "aws_route53_zone" "hml" {
  name    = "hml.alvocard.com.br"
  comment = "Homologação — delegado do apex via NS records no registrar"

  tags = merge(local.common_tags, {
    Domain      = "hml"
    Environment = "staging"
  })
}

# =============================================================================
# ACM Certificates — Wildcard por zona
# =============================================================================

resource "aws_acm_certificate" "prod_wildcard" {
  domain_name       = "*.prod.alvocard.com.br"
  validation_method = "DNS"

  lifecycle { create_before_destroy = true }
  tags = merge(local.common_tags, { Name = "wildcard-prod-alvocard" })
}

resource "aws_acm_certificate" "hml_wildcard" {
  domain_name       = "*.hml.alvocard.com.br"
  validation_method = "DNS"

  lifecycle { create_before_destroy = true }
  tags = merge(local.common_tags, { Name = "wildcard-hml-alvocard" })
}

# --- Validação DNS automática (prod) ---
resource "aws_route53_record" "prod_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.prod_wildcard.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = aws_route53_zone.prod.zone_id
  name    = each.value.name
  records = [each.value.record]
  ttl     = 60
  type    = each.value.type
}

resource "aws_acm_certificate_validation" "prod_wildcard" {
  certificate_arn         = aws_acm_certificate.prod_wildcard.arn
  validation_record_fqdns = [for r in aws_route53_record.prod_cert_validation : r.fqdn]
  timeouts { create = "30m" }
}

# --- Validação DNS automática (hml) ---
resource "aws_route53_record" "hml_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.hml_wildcard.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = aws_route53_zone.hml.zone_id
  name    = each.value.name
  records = [each.value.record]
  ttl     = 60
  type    = each.value.type
}

resource "aws_acm_certificate_validation" "hml_wildcard" {
  certificate_arn         = aws_acm_certificate.hml_wildcard.arn
  validation_record_fqdns = [for r in aws_route53_record.hml_cert_validation : r.fqdn]
  timeouts { create = "30m" }
}

# =============================================================================
# DNS Records — Produção
# =============================================================================

locals {
  prod_public_services = toset([
    "keycloak", "gitlab", "kas", "harbor",
    "hatch-api", "hatch", "ipaas",
  ])
  prod_internal_services = toset([
    "argocd", "grafana", "vault",
    "sonarqube", "backstage", "rabbitmq",
  ])
}

resource "aws_route53_record" "prod_public" {
  for_each = local.prod_public_services

  zone_id = aws_route53_zone.prod.zone_id
  name    = "${each.value}.prod.alvocard.com.br"
  type    = "A"

  alias {
    name                   = aws_lb.platform_prod_public.dns_name
    zone_id                = aws_lb.platform_prod_public.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "prod_internal" {
  for_each = local.prod_internal_services

  zone_id = aws_route53_zone.prod.zone_id
  name    = "${each.value}.prod.alvocard.com.br"
  type    = "A"

  alias {
    name                   = aws_lb.platform_prod_internal.dns_name
    zone_id                = aws_lb.platform_prod_internal.zone_id
    evaluate_target_health = true
  }
}

# =============================================================================
# DNS Records — Homologação (adicionar conforme serviços forem expostos)
# =============================================================================

# resource "aws_route53_record" "hml_services" {
#   for_each = toset(["keycloak", "gitlab", "harbor", "ipaas", "grafana", "hatch"])
#   zone_id  = aws_route53_zone.hml.zone_id
#   name     = "${each.value}.hml.alvocard.com.br"
#   type     = "A"
#   alias { ... }  # ALB staging quando configurado
# }

# =============================================================================
# Outputs
# =============================================================================

output "prod_route53_zone_id" {
  description = "Zone ID prod — usar em outros módulos"
  value       = aws_route53_zone.prod.zone_id
}

output "prod_route53_name_servers" {
  description = "NS prod — enviar ao gestor para cadastro no registrar"
  value       = aws_route53_zone.prod.name_servers
}

output "hml_route53_zone_id" {
  description = "Zone ID hml — usar em outros módulos"
  value       = aws_route53_zone.hml.zone_id
}

output "hml_route53_name_servers" {
  description = "NS hml — enviar ao gestor para cadastro no registrar"
  value       = aws_route53_zone.hml.name_servers
}

output "prod_acm_certificate_arn" {
  description = "ARN do wildcard ACM prod — usar nos Ingresses"
  value       = aws_acm_certificate_validation.prod_wildcard.certificate_arn
}

output "hml_acm_certificate_arn" {
  description = "ARN do wildcard ACM hml — usar nos Ingresses staging"
  value       = aws_acm_certificate_validation.hml_wildcard.certificate_arn
}
```

---

## Sequência de Execução

| # | Ação | Responsável | Duração |
|---|------|-------------|---------|
| 1 | `terraform apply` — criar 2 hosted zones (prod + hml) | Engenheiro DevOps | 5 min |
| 2 | Extrair NS: `terraform output prod_route53_name_servers` e `hml_route53_name_servers` | Engenheiro DevOps | 2 min |
| 3 | Enviar NS ao gestor + texto de solicitação (seção acima) | Engenheiro DevOps | 5 min |
| **4** | **Gestor adiciona 8 registros NS no registrar** | **Gestor de domínio** | **15 min** |
| 5 | Validar propagação: `dig NS prod.alvocard.com.br` e `dig NS hml.alvocard.com.br` | Engenheiro DevOps | 5-60 min |
| 6 | `terraform apply` — criar ACM wildcards + validação DNS | Engenheiro DevOps | 5-30 min |
| 7 | `terraform apply` — criar ALBs prod (public + internal) com WAF + ACM | Engenheiro DevOps | 30 min |
| 8 | `terraform apply` — criar registros DNS dos serviços | Engenheiro DevOps | 10 min |
| 9 | Validar HTTPS end-to-end | Engenheiro DevOps | 30 min |

**Após Step 4:** Equipe técnica tem autonomia total. Novos serviços = 1 linha no `locals` do Terraform.

---

## Comandos de Validação

```bash
# 1. Verificar delegação NS (após gestor cadastrar)
dig NS prod.alvocard.com.br
dig NS hml.alvocard.com.br
# Esperado: 4 NS do Route53 para cada

# 2. Verificar resolução de serviço
dig A keycloak.prod.alvocard.com.br
# Esperado: IP do ALB

# 3. Verificar certificado HTTPS
curl -vI https://keycloak.prod.alvocard.com.br 2>&1 | grep -E "SSL|certificate|subject"
# Esperado: subject=*.prod.alvocard.com.br, issuer=Amazon

# 4. Novo serviço (exemplo — zero dependência do gestor)
# Basta adicionar "novo-servico" ao locals.prod_public_services e terraform apply
```

---

## Texto para Comunicação ao Gestor

```
ASSUNTO: Solicitação de cadastro de registros DNS — prod e hml em alvocard.com.br

Prezado(a),

Solicitamos a adição de registros DNS para dois subdomínios no domínio
alvocard.com.br. A operação é simples, segura e não altera nada existente.

O QUE FAZER:
  Adicionar 8 registros do tipo NS no painel de DNS do registrar.
  (4 para prod.alvocard.com.br + 4 para hml.alvocard.com.br)

O QUE NÃO MUDA:
  O domínio alvocard.com.br, email, site, MX, SPF — TUDO como está.
  Esta operação é ADITIVA — apenas adiciona registros novos.

REGISTROS PARA PRODUÇÃO (prod.alvocard.com.br):

  Tipo: NS    Nome: prod.alvocard.com.br    Valor: ns-1292.awsdns-33.org      TTL: 3600
  Tipo: NS    Nome: prod.alvocard.com.br    Valor: ns-1698.awsdns-20.co.uk    TTL: 3600
  Tipo: NS    Nome: prod.alvocard.com.br    Valor: ns-684.awsdns-21.net       TTL: 3600
  Tipo: NS    Nome: prod.alvocard.com.br    Valor: ns-277.awsdns-34.com       TTL: 3600

REGISTROS PARA HOMOLOGAÇÃO (hml.alvocard.com.br):

  Tipo: NS    Nome: hml.alvocard.com.br     Valor: ns-1415.awsdns-48.org      TTL: 3600
  Tipo: NS    Nome: hml.alvocard.com.br     Valor: ns-1958.awsdns-52.co.uk    TTL: 3600
  Tipo: NS    Nome: hml.alvocard.com.br     Valor: ns-719.awsdns-25.net       TTL: 3600
  Tipo: NS    Nome: hml.alvocard.com.br     Valor: ns-377.awsdns-47.com       TTL: 3600

ROLLBACK:
  Se necessário, basta remover os registros — volta ao estado original.

Atenciosamente,
[Equipe de Infraestrutura]
```

---

*Documento v3.0 — Delegação de subdomínio (apex intocado)*
*Atualizado: 2026-03-19 — Decisão do usuário: não migrar apex, apenas delegar prod + hml*
*Referência: ADR-098 (estratégia DNS)*
