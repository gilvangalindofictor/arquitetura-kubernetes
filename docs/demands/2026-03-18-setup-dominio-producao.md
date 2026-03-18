# Setup de Domínio para Produção — alvocard.com.br

**Data:** 2026-03-18 | **Domínio:** alvocard.com.br | **Registrar:** a identificar
**Conta AWS:** 891377105802 | **Região:** us-east-1 | **Status:** AGUARDANDO AÇÃO EXTERNA
**Versão:** 2.0 — Estratégia atualizada para gestão do apex no Route53

---

## Resumo

O ambiente de produção opera hoje com domínios fictícios `*.staging.internal` resolvidos apenas via CoreDNS split-horizon dentro do cluster. Não existe zona pública no Route53 nem certificado ACM válido para browsers.

**Estratégia adotada (v2.0): Mover o apex `alvocard.com.br` para o Route53.**

O gestor de domínio faz **uma única ação** no registrar: troca os NS do apex `alvocard.com.br` para os NS do Route53. A partir daí, toda gestão de subdomínios (`prod.*`, `hml.*`, `ipaas.*`, qualquer outro) é feita exclusivamente via Terraform — sem depender do gestor para cada novo ambiente ou serviço.

**Quem faz o que:**

| Responsável | Ação | Tempo | Frequência |
|------------|------|-------|-----------|
| Engenheiro DevOps | Auditar registros DNS existentes no registrar | 10 min | 1x (antes da migração) |
| Engenheiro DevOps | `terraform apply` — criar zona `alvocard.com.br` + recriar registros existentes | 20 min | 1x |
| **Gestor de domínio** | **Trocar NS do apex `alvocard.com.br` para os NS do Route53** | **15 min** | **1x — DEFINITIVO** |
| Engenheiro DevOps | Validar propagação + provisionar ACM + ALBs + registros | 60 min | 1x |
| Engenheiro DevOps | Novos ambientes/subdomínios futuros | 2 min | Autônomo — sem gestor |

**Bloqueador externo:** A troca dos NS do apex `alvocard.com.br` é a única ação que requer o gestor de domínio. Após isso, a equipe técnica tem autonomia total para criar qualquer subdomínio via Terraform.

**Aviso crítico pré-migração:** Se `alvocard.com.br` possui outros registros DNS ativos (www, mail/MX, SPF, etc.), eles DEVEM ser recriados no Route53 antes de trocar os NS. A equipe técnica é responsável por essa auditoria — o gestor deve informar quais registros existem.

---

## Arquitetura DNS

```
Registrar (alvocard.com.br)
    │
    │  Troca NS do APEX → Route53 (ação única)
    │
    ▼
Route53 — Hosted Zone: alvocard.com.br (pública — apex)
    │
    ├── prod.alvocard.com.br  → A alias → ALB internet-facing
    │       ├── keycloak.prod.alvocard.com.br    (público)
    │       ├── gitlab.prod.alvocard.com.br       (público)
    │       ├── kas.prod.alvocard.com.br           (público)
    │       ├── harbor.prod.alvocard.com.br        (público)
    │       ├── hatch-api.prod.alvocard.com.br     (público)
    │       └── hatch.prod.alvocard.com.br         (público)
    │
    ├── prod.alvocard.com.br  → A alias → ALB internal (somente via VPN)
    │       ├── argocd.prod.alvocard.com.br
    │       ├── grafana.prod.alvocard.com.br
    │       ├── vault.prod.alvocard.com.br
    │       ├── sonarqube.prod.alvocard.com.br
    │       ├── backstage.prod.alvocard.com.br
    │       └── rabbitmq.prod.alvocard.com.br
    │
    ├── hml.alvocard.com.br   → A alias → ALB staging (futuro)
    │       └── *.hml.alvocard.com.br              (quando staging for exposto)
    │
    ├── ipaas.alvocard.com.br → A alias / CNAME → ALB iPaaS (quando criado)
    │
    └── (qualquer outro subdomínio) → criado via Terraform sem tocar no registrar
                │
                ▼
        EKS k8s-platform-prod
        AWS LB Controller → Ingress → Service → Pods
```

**Vantagem da estratégia apex:** Qualquer novo ambiente ou serviço (`ipaas.alvocard.com.br`, `hml.alvocard.com.br`, `api.alvocard.com.br`) é criado com um único `aws_route53_record` no Terraform. Zero dependência do gestor de domínio após a migração inicial.

**Nota Route53 Public — serviços internos:** Os registros de serviços internos (argocd, grafana, vault, etc.) existem na zona pública mas apontam para o ALB internal (scheme=internal). Esses registros resolvem para IPs privados acessíveis apenas via VPN. Usuários externos veem o IP privado mas não conseguem conectar — WAF e Security Groups garantem o bloqueio.

---

## Hosted Zone a Criar (Route53)

| Zona | Tipo | Propósito | Estratégia |
|------|------|-----------|------------|
| `alvocard.com.br` | Pública — apex | Gestão centralizada de TODOS os subdomínios | Route53 owns the apex (recomendado v2.0) |

**Uma única zona** — todos os subdomínios são `aws_route53_record` dentro dela. Não é necessário criar zonas separadas para `prod.alvocard.com.br`, `hml.alvocard.com.br`, etc.

**Estratégia anterior (v1.0 — descontinuada):** Delegação de subdomínio `prod.alvocard.com.br` apenas — mantinha apex no registrar. Descontinuada pois exigia ação do gestor para cada novo ambiente ou serviço exposto.

---

## Migração — Procedimento Seguro

A migração do apex é irreversível em termos de operação (os registros DNS existentes param de funcionar se não forem recriados antes). Seguir esta sequência elimina o risco de downtime:

### FASE 0 — Auditoria (antes de qualquer apply)

```bash
# Verificar registros DNS existentes no registrar
# O gestor de domínio deve fornecer ou o engenheiro deve acessar o painel:
# - Registros A (www, mail, etc.)
# - Registros MX (email)
# - Registros TXT (SPF, DKIM, verificações de propriedade)
# - Registros CNAME existentes
# - TTLs atuais

# Se existir serviço de email em alvocard.com.br → OBRIGATÓRIO recriar MX+SPF+DKIM no Route53 antes de trocar NS
# Se não existir (domínio só para sistemas técnicos) → migração é trivial
```

### FASE 1 — Criar zona no Route53 e recriar registros existentes

```bash
terraform apply   # Cria aws_route53_zone.apex + registros existentes migrados
terraform output apex_route53_name_servers  # Anotar os 4 NS
```

### FASE 2 — Validar (sem tocar no registrar ainda)

```bash
# Testar resolução diretamente nos NS do Route53 ANTES de trocar o registrar
# Isso valida que os registros estão corretos sem impacto em produção
dig @ns-XXX.awsdns-XX.com www.alvocard.com.br
dig @ns-XXX.awsdns-XX.com alvocard.com.br MX
```

### FASE 3 — Trocar NS no registrar (ação do gestor — janela de manutenção)

O gestor troca os NS do domínio `alvocard.com.br` para os 4 NS do Route53.
Após a propagação (5–60 min), toda resolução passa pelo Route53.

### FASE 4 — Provisionar ACM + ALBs + registros de serviços

```bash
terraform apply   # Cria ACM wildcard, registros de validação, ALBs, DNS dos serviços
```

---

## Certificados ACM

**Estratégia:** Certificados wildcard ACM DNS-validated via Route53 — padrão ADR-008.

| Certificado | Cobre | Quando criar |
|------------|-------|-------------|
| `*.alvocard.com.br` + `alvocard.com.br` | Todos os subdomínios diretos | Fase 4 (após apex no Route53) |
| `*.prod.alvocard.com.br` | Subdomínios de prod (keycloak.prod.*, gitlab.prod.*) | Fase 4 junto com o wildcard apex |

**Nota:** O wildcard `*.alvocard.com.br` cobre `prod.alvocard.com.br` mas NÃO cobre `keycloak.prod.alvocard.com.br` (dois níveis). Por isso, ambos os certificados são necessários — ou usar um Subject Alternative Name no mesmo cert.

**Renovação:** Automática pelo ACM 60 dias antes da expiração. Não requer ação humana.

```hcl
# environments/prod/dns-acm.tf

resource "aws_acm_certificate" "apex_wildcard" {
  domain_name = "*.alvocard.com.br"
  subject_alternative_names = [
    "alvocard.com.br",
    "*.prod.alvocard.com.br",
    "*.hml.alvocard.com.br",    # adicionar futuros ambientes aqui
  ]
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, { Name = "wildcard-apex-alvocard" })
}
```

---

## Mapa de Subdomínios por Serviço

| Serviço | Staging (atual) | Produção (alvo) | Tipo | Namespace Prod |
|---------|-----------------|-----------------|------|----------------|
| Keycloak SSO | keycloak.staging.internal | `keycloak.prod.alvocard.com.br` | **Público** | prod-platform-keycloak |
| GitLab CE | gitlab.staging.internal | `gitlab.prod.alvocard.com.br` | **Público** | staging-platform-gitlab (compartilhado) |
| GitLab KAS | kas.staging.internal | `kas.prod.alvocard.com.br` | **Público** | staging-platform-gitlab (compartilhado) |
| Harbor Registry | harbor.staging.internal | `harbor.prod.alvocard.com.br` | **Público** | harbor-system |
| Hatch ETL API | hatch-api.staging.internal | `hatch-api.prod.alvocard.com.br` | **Público** | prod-data-hatch-etl |
| Hatch Web UI | hatch.staging.internal | `hatch.prod.alvocard.com.br` | **Público** | prod-data-hatch-etl |
| ArgoCD | argocd.staging.internal | `argocd.prod.alvocard.com.br` | Interno (VPN) | prod-platform-argocd |
| Grafana | grafana.staging.internal | `grafana.prod.alvocard.com.br` | Interno (VPN) | prod-observability |
| Vault | vault.staging.internal | `vault.prod.alvocard.com.br` | Interno (VPN) | prod-security-vault |
| SonarQube | sonarqube.staging.internal | `sonarqube.prod.alvocard.com.br` | Interno (VPN) | prod-platform-sonarqube |
| Backstage IDP | backstage.staging.internal | `backstage.prod.alvocard.com.br` | Interno (VPN) | prod-platform-backstage |
| RabbitMQ Mgmt | rabbitmq.staging.internal | `rabbitmq.prod.alvocard.com.br` | Interno (VPN) | data-services-prod |
| Prometheus | N/A (port-forward) | N/A (acesso via Grafana) | Interno (sem ingress) | prod-observability |
| AlertManager | N/A (port-forward) | N/A (integração Teams) | Interno (sem ingress) | prod-observability |
| Staging apps (futuro) | *.staging.internal | `*.hml.alvocard.com.br` | Misto | staging-* |
| iPaaS (futuro) | N/A | `ipaas.alvocard.com.br` | A definir | prod-ipaas |

---

## CHECKLIST PARA O GESTOR DE DOMÍNIO

> **ATENÇÃO — Esta seção é destinada ao responsável pelo domínio alvocard.com.br no registrar.**
> Esta é a única ação que depende de alguém fora da equipe técnica.
> É uma ação única e definitiva — após ela, a equipe técnica tem autonomia total.

---

### Contexto (ler antes de agir)

A empresa possui o domínio `alvocard.com.br` registrado em um registrar externo (GoDaddy, RegistroBR, Cloudflare, etc.). A equipe técnica quer mover a gestão do DNS do domínio inteiro para o AWS Route53.

**Por que isso é melhor:** Após essa mudança, a equipe técnica pode criar qualquer subdomínio (`prod.*`, `hml.*`, `ipaas.*`, etc.) de forma autônoma via código (Terraform), sem precisar acionar o gestor de domínio novamente.

**O que você precisa fazer (duas partes):**

1. **Antes** da equipe aplicar o Terraform: fornecer a lista de todos os registros DNS ativos em `alvocard.com.br` (A, MX, TXT, CNAME, etc.) para que sejam recriados na AWS antes da troca.
2. **Após** a equipe confirmar que tudo está no Route53: trocar os 4 Name Servers do domínio `alvocard.com.br` no registrar para os NS do Route53.

---

### AÇÃO 0 — Fornecer registros DNS existentes (ANTES de qualquer mudança)

Acesse o painel de DNS do `alvocard.com.br` no registrar e envie para a equipe técnica **todos** os registros ativos:

```
Tipo    Nome                  Valor                     TTL
A       alvocard.com.br       XX.XX.XX.XX               300
MX      alvocard.com.br       mail.exemplo.com          300
TXT     alvocard.com.br       "v=spf1 ..."              300
CNAME   www.alvocard.com.br   alvocard.com.br           300
(etc.)
```

**Se o domínio não possui registros públicos ativos** (apenas sistemas internos/AWS) → informe "sem registros existentes" e pule direto para AÇÃO 1.

**Por que isso é crítico:** Se existir email configurado (`@alvocard.com.br`), os registros MX/SPF/DKIM precisam ser recriados no Route53 antes da troca de NS. Caso contrário, o email parará de funcionar.

---

### AÇÃO 1 — Receber os 4 Name Servers da equipe técnica

Após a equipe executar o Terraform e confirmar que todos os registros existentes foram recriados no Route53, ela enviará 4 endereços no formato:

```
ns-XXX.awsdns-XX.com
ns-XXX.awsdns-XX.net
ns-XXX.awsdns-XX.org
ns-XXX.awsdns-XX.co.uk
```

**Não executar a troca até receber confirmação explícita da equipe técnica.**

---

### AÇÃO 2 — Trocar os Name Servers do domínio `alvocard.com.br`

No painel administrativo do registrar:

1. Acesse a gestão do domínio `alvocard.com.br`
2. Localize a seção "Name Servers" ou "Servidores DNS" (não a seção de registros DNS)
3. **Substitua** os NS atuais pelos 4 NS do Route53 recebidos na AÇÃO 1

**Exemplo visual (pode variar por registrar):**

```
ANTES (NS atuais do registrar):       DEPOIS (NS do Route53):
ns1.registrobr.com.br         →       ns-123.awsdns-45.com
ns2.registrobr.com.br         →       ns-678.awsdns-90.net
                                       ns-234.awsdns-12.org
                                       ns-567.awsdns-89.co.uk
```

| Campo | Valor |
|-------|-------|
| **O que muda** | Name Servers do APEX `alvocard.com.br` |
| **TTL recomendado** | `300` (reduzir para 5 min antes da troca, se possível) |
| **Impacto** | DNS do domínio inteiro passa para AWS Route53 |

---

### O QUE NÃO FAZER

```
NÃO criar registros NS para subdomínios (prod, hml, etc.)
    → Com essa estratégia, tudo fica na zona apex — sem delegações
    → A equipe cria subdomínios diretamente no Route53

NÃO alterar registros A, MX, CNAME existentes
    → A equipe técnica cuida disso no Route53

NÃO adquirir certificado SSL pelo registrar
    → A AWS (ACM) emite gratuitamente com renovação automática
```

---

### AÇÃO 3 — Confirmar a troca (notificar equipe)

Após trocar os NS, notifique a equipe técnica. A propagação leva **5 a 60 minutos**.

A equipe validará com:
```bash
dig NS alvocard.com.br
# Esperado: 4 NS do Route53 (ns-XXX.awsdns-XX.{com,net,org,co.uk})
```

**Após confirmação:** Nenhuma outra ação do gestor de domínio será necessária. A equipe tem autonomia total.

---

### Resumo executivo para o gestor

```
O QUE VOCÊ FAZ (parte 1):  Enviar lista de registros DNS ativos em alvocard.com.br
O QUE VOCÊ FAZ (parte 2):  Trocar os 4 Name Servers do domínio para os NS do Route53
PARA QUAL DOMÍNIO:          alvocard.com.br (apex — o domínio inteiro)
QUANTO TEMPO LEVA:          15–30 minutos
QUANDO FAZER:               Somente após confirmação explícita da equipe técnica
IMPACTO SE NÃO FEITO:       Sistemas de produção não terão HTTPS válido
AÇÕES FUTURAS:              Nenhuma — a equipe técnica gerencia tudo autonomamente
```

---

## Configuração Terraform Completa

**Arquivo:** `platform-provisioning/aws/kubernetes/terraform/environments/prod/dns-acm.tf`

```hcl
# =============================================================================
# Route53 Hosted Zone — alvocard.com.br (APEX)
# Gestão centralizada de todos os subdomínios no Route53
# =============================================================================

resource "aws_route53_zone" "apex" {
  name    = "alvocard.com.br"
  comment = "Apex zone — todos os subdomínios gerenciados aqui — ManagedBy Terraform"

  tags = merge(local.common_tags, {
    Domain = "apex"
    Zone   = "alvocard-apex-public"
  })
}

# =============================================================================
# ACM Certificate — wildcard apex + prod + hml
# =============================================================================

resource "aws_acm_certificate" "apex_wildcard" {
  domain_name = "*.alvocard.com.br"
  subject_alternative_names = [
    "alvocard.com.br",
    "*.prod.alvocard.com.br",
    "*.hml.alvocard.com.br",
  ]
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, { Name = "wildcard-apex-alvocard" })

  depends_on = [aws_route53_zone.apex]
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.apex_wildcard.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = aws_route53_zone.apex.zone_id
  name    = each.value.name
  records = [each.value.record]
  ttl     = 60
  type    = each.value.type
}

resource "aws_acm_certificate_validation" "apex_wildcard" {
  certificate_arn         = aws_acm_certificate.apex_wildcard.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]

  timeouts { create = "30m" }
}

# =============================================================================
# DNS Records — Produção (público)
# =============================================================================

locals {
  prod_public_services = toset([
    "keycloak", "gitlab", "kas", "harbor", "hatch-api", "hatch",
  ])
  prod_internal_services = toset([
    "argocd", "grafana", "vault", "sonarqube", "backstage", "rabbitmq",
  ])
}

resource "aws_route53_record" "prod_public" {
  for_each = local.prod_public_services

  zone_id = aws_route53_zone.apex.zone_id
  name    = "${each.value}.prod.alvocard.com.br"
  type    = "A"

  alias {
    name                   = aws_lb.platform_prod_public.dns_name
    zone_id                = aws_lb.platform_prod_public.zone_id
    evaluate_target_health = true
  }
}

# =============================================================================
# DNS Records — Produção (internos — somente via VPN)
# =============================================================================

resource "aws_route53_record" "prod_internal" {
  for_each = local.prod_internal_services

  zone_id = aws_route53_zone.apex.zone_id
  name    = "${each.value}.prod.alvocard.com.br"
  type    = "A"

  alias {
    name                   = aws_lb.platform_prod_internal.dns_name
    zone_id                = aws_lb.platform_prod_internal.zone_id
    evaluate_target_health = true
  }
}

# =============================================================================
# DNS Records — Novos subdomínios (adicionar conforme necessário)
# Exemplo: ipaas.alvocard.com.br, hml.*, staging.*
# =============================================================================

# resource "aws_route53_record" "ipaas" {
#   zone_id = aws_route53_zone.apex.zone_id
#   name    = "ipaas.alvocard.com.br"
#   type    = "A"
#   alias { ... }
# }

# =============================================================================
# Outputs
# =============================================================================

output "apex_route53_zone_id" {
  description = "Zone ID da hosted zone apex — usar em outros módulos"
  value       = aws_route53_zone.apex.zone_id
}

output "apex_route53_name_servers" {
  description = "NS do apex — enviar para gestor do domínio para troca definitiva"
  value       = aws_route53_zone.apex.name_servers
}

output "apex_acm_certificate_arn" {
  description = "ARN do wildcard ACM apex — usar nas annotations dos Ingresses ALB"
  value       = aws_acm_certificate_validation.apex_wildcard.certificate_arn
}
```

---

## Sequência de Execução

| # | Ação | Responsável | Dependência | Duração |
|---|------|-------------|-------------|---------|
| 0 | Auditar registros DNS ativos no registrar atual | **Gestor de domínio** | — | 10 min |
| 1 | `terraform apply` — criar zona apex + recriar registros existentes | Engenheiro DevOps | Step 0 concluído | 15 min |
| 2 | Validar registros nos NS do Route53 (sem tocar no registrar): `dig @ns-XXX...` | Engenheiro DevOps | Step 1 concluído | 10 min |
| 3 | Extrair NS: `terraform output apex_route53_name_servers` e enviar ao gestor | Engenheiro DevOps | Step 2 OK | 5 min |
| **4** | **Trocar NS do apex `alvocard.com.br` para NS Route53** | **Gestor de domínio** | **Step 3 concluído** | **15 min** |
| 5 | Validar propagação: `dig NS alvocard.com.br` | Engenheiro DevOps | Step 4 + propagação | 5-60 min |
| 6 | `terraform apply` — criar ACM wildcard + registros de validação | Engenheiro DevOps | Step 5 validado | 5 min |
| 7 | Aguardar ACM: status ISSUED (automático) | — | Step 6 + propagação | 5-30 min |
| 8 | `terraform output apex_acm_certificate_arn` — copiar ARN | Engenheiro DevOps | Step 7 concluído | 2 min |
| 9 | Criar ALBs prod (public + internal) com WAF + ACM | Engenheiro DevOps | Step 8 concluído | 1h |
| 10 | Criar registros DNS de serviços prod (public + internal) | Engenheiro DevOps | Step 9 concluído | 10 min |
| 11 | Validar HTTPS end-to-end | Engenheiro DevOps | Step 10 concluído | 30 min |

**Caminho crítico:** Step 0 (gestor audita registros, ~10 min) → Steps 1-3 (equipe, ~30 min) → Step 4 (gestor troca NS, ~15 min) → Steps 5-11 (equipe, ~2-3h)

**Após Step 4:** Equipe técnica tem autonomia total. Novos subdomínios = 2 linhas de Terraform. Zero dependência do gestor.

---

## Dependências e Bloqueadores

| Dependência | Tipo | Status | Impacto se bloqueado |
|------------|------|--------|----------------------|
| Sessão AWS SSO ativa (`k8s-platform-prod`) | Técnica interna | A verificar | Nenhum apply TF possível |
| Gestor fornecer lista de registros DNS existentes em `alvocard.com.br` | **Externo — pré-requisito** | **PENDENTE** | Risco de downtime de serviços existentes se não migrados |
| Gestor trocar NS do apex `alvocard.com.br` para Route53 | **Externo — bloqueador crítico** | **PENDENTE** | ACM não valida; sem HTTPS real em prod |
| Fases 1-4 do plano de produção concluídas | Técnica interna | PENDENTE | ALBs prod não existem para criar alias records |
| `data "aws_subnets" "public"` adicionado em `environments/prod/main.tf` | Técnica interna (DEP-01) | **PENDENTE** | `terraform apply` dos ALBs falha |

---

## Comandos de Validação

```bash
# 1. Verificar NS do apex após troca (executar após gestor configurar o registrar)
dig NS alvocard.com.br
# Esperado: 4 NS do Route53 (ns-XXX.awsdns-XX.{com,net,org,co.uk})

# 2. Verificar resolução de serviço público
dig A keycloak.prod.alvocard.com.br
# Esperado: IP do ALB internet-facing

# 3. Verificar certificado ACM
curl -vI https://keycloak.prod.alvocard.com.br 2>&1 | grep -E "SSL|certificate|subject|issuer"
# Esperado: issuer=Amazon, subject=*.prod.alvocard.com.br

# 4. Verificar redirect HTTP → HTTPS
curl -I http://keycloak.prod.alvocard.com.br
# Esperado: HTTP 301 → https://...

# 5. Verificar OIDC discovery endpoint
curl https://keycloak.prod.alvocard.com.br/realms/prod/.well-known/openid-configuration | jq .issuer
# Esperado: "https://keycloak.prod.alvocard.com.br/realms/prod"

# 6. Verificar status ACM
aws acm describe-certificate \
  --certificate-arn $(terraform output -raw apex_acm_certificate_arn) \
  --profile k8s-platform-prod \
  --query 'Certificate.Status'
# Esperado: "ISSUED"

# 7. Adicionar novo subdomínio (exemplo futuro — zero dependência do gestor)
# Basta adicionar aws_route53_record no dns-acm.tf e fazer terraform apply
```

---

*Documento produzido pela Mesa Técnica — AWS Specialist + Security Specialist*
*v2.0: Estratégia atualizada para gestão do apex no Route53 (autonomia total pós-migração)*
*Referência: `2026-03-18-security-domain-vpn-prod.md` (Security Specialist)*
*Referência: ADR-098 (estratégia DNS)*
