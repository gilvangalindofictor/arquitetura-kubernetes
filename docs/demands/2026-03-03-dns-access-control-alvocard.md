# 📋 DEMANDA — DNS Real + Controle de Acesso Público: alvocard.com.br

**Data:** 2026-03-03
**Solicitante:** Plataforma / DevOps
**Prioridade:** MÉDIA — Habilitador de Segurança e Acesso Real
**Impacto Financeiro:** ~$1/mês incremental (Route53 Hosted Zone staging.alvocard.com.br)
**Status:** 📋 PLANEJAMENTO

---

## 🎯 Objetivo

Migrar o ambiente de staging da plataforma EKS de domínios fictícios `*.staging.internal` (resolvidos apenas via CoreDNS split-horizon) para o domínio real `*.staging.alvocard.com.br`, com HTTPS via ACM, controle de acesso por WAF IP whitelist, e cenários progressivos de segurança adequados à ausência atual de VPN.

---

## 📊 Estado Atual

| Aspecto | Estado Atual | Estado Desejado |
|---------|-------------|----------------|
| **Domínio** | `*.staging.internal` (fictício, CoreDNS split-horizon) | `*.staging.alvocard.com.br` (DNS real, Route53) |
| **Protocolo** | HTTP-only (porta 80) | HTTPS (porta 443, ACM wildcard) |
| **Acesso** | ALBs internet-facing sem controle de IP | WAF IP whitelist (apenas IPs autorizados) |
| **VPN** | Inexistente | Inexistente hoje → híbrido → full VPN (futuro) |
| **OIDC URLs** | `http://keycloak.staging.internal/...` | `https://keycloak.staging.alvocard.com.br/...` |
| **Custo DNS** | $0 (domínios fictícios) | ~$1/mês (1 hosted zone + queries mínimas) |

**Problemas do Estado Atual:**
- Domínios `*.staging.internal` não resolvem externamente (sem VPN, acesso impossível)
- HTTP-only expõe credenciais, tokens OAuth2 e cookies em trânsito
- Sem controle de acesso por IP: qualquer pessoa com o DNS name do ALB pode tentar acesso
- URLs OIDC fictícias bloqueiam federation real com Entra ID / Keycloak
- Certificados inválidos bloqueiam fluxos OAuth2/OIDC de clientes externos

---

## 🔒 Cenários Progressivos de Segurança

### Cenário A — Imediato (sem VPN): WAF IP Whitelist + ACM + OIDC Real

**Quando usar:** Agora. A empresa não possui VPN. A equipe acessa via IPs fixos conhecidos.

**Componentes:**
- Route53 Hosted Zone: `staging.alvocard.com.br`
- ACM Certificate: `*.staging.alvocard.com.br` (wildcard, DNS-validated)
- WAF WebACL com IP Whitelist (Priority 5 — bloqueia todo o resto)
- Keycloak: `domain_suffix` atualizado para `staging.alvocard.com.br`
- Ingress: annotation `certificate-arn` + `waf-acl-arn`
- CoreDNS: split-horizon atualizado (resolução interna → Service ClusterIP)
- OIDC URLs: locals refatorados (`keycloak_base_url`, `harbor_base_url`, etc.)

**Nível de segurança:** ⭐⭐⭐ Adequado para staging sem VPN

**Limitação:** IPs fixos necessários — não funciona para equipes com IP dinâmico

---

### Cenário B — Transição (VPN Híbrida): VPN para Equipe + ALB Público para Keycloak

**Quando usar:** Quando a empresa contratar VPN (AWS Client VPN ou Tailscale).

**Componentes adicionais ao Cenário A:**
- AWS Client VPN Endpoint (ou Tailscale): VPN para equipe técnica
- ALB interno: maioria dos serviços migra para `internal` scheme
- ALB público: apenas Keycloak (necessário para federation Entra ID)
- WAF IP whitelist: mantida apenas no ALB público de Keycloak
- Security Groups: ALB interno restringe a CIDR da VPN

**Nível de segurança:** ⭐⭐⭐⭐ Recomendado para equipes em crescimento

---

### Cenário C — Futuro (VPN Completa): Tudo via VPN, ALB Interno

**Quando usar:** Quando todos os acessos administrativos estiverem sob VPN.

**Componentes adicionais ao Cenário B:**
- ALB scheme: todos `internal` exceto onde federation externa é obrigatória
- WAF: removida ou mantida apenas para compliance (logging + rate limiting)
- Route53 Private Hosted Zone: resolução DNS exclusivamente via VPN
- Split-horizon completo: DNS público aponta apenas para Keycloak/OIDC

**Nível de segurança:** ⭐⭐⭐⭐⭐ Enterprise-grade

---

## 🛠️ Detalhamento — Cenário A (7 Steps de Implementação)

### Step 1 — Módulo Terraform: Route53 + ACM Wildcard

**Arquivo:** `platform-provisioning/aws/kubernetes/terraform/environments/staging/dns-acm.tf`

```hcl
# Route53 Hosted Zone
resource "aws_route53_zone" "staging_alvocard" {
  name    = "staging.alvocard.com.br"
  comment = "Staging platform — EKS alvocard.com.br"
  tags    = local.common_tags
}

# ACM Wildcard Certificate
resource "aws_acm_certificate" "staging_wildcard" {
  domain_name               = "*.staging.alvocard.com.br"
  subject_alternative_names = ["staging.alvocard.com.br"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = local.common_tags
}

# DNS Validation Records (automático)
resource "aws_route53_record" "staging_wildcard_validation" {
  for_each = {
    for dvo in aws_acm_certificate.staging_wildcard.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  zone_id = aws_route53_zone.staging_alvocard.zone_id
  name    = each.value.name
  records = [each.value.record]
  ttl     = 60
  type    = each.value.type
}

resource "aws_acm_certificate_validation" "staging_wildcard" {
  certificate_arn         = aws_acm_certificate.staging_wildcard.arn
  validation_record_fqdns = [for r in aws_route53_record.staging_wildcard_validation : r.fqdn]
  timeouts { create = "30m" }
}

# Outputs
output "staging_acm_certificate_arn" {
  value = aws_acm_certificate.staging_wildcard.arn
}
output "staging_route53_zone_id" {
  value = aws_route53_zone.staging_alvocard.zone_id
}
output "staging_route53_name_servers" {
  description = "NS records — configurar no registrador alvocard.com.br"
  value       = aws_route53_zone.staging_alvocard.name_servers
}
```

**Dependências:** Após apply, copiar NS records para o registrador de `alvocard.com.br` (delegação de subdomínio).

---

### Step 2 — WAF IP Whitelist (Priority 5)

**Arquivo:** `platform-provisioning/aws/kubernetes/terraform/environments/staging/waf-ip-whitelist.tf`

```hcl
# IP Set com IPs autorizados
resource "aws_wafv2_ip_set" "staging_whitelist" {
  name               = "staging-ip-whitelist"
  description        = "IPs autorizados para acesso ao staging"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"

  addresses = var.staging_allowed_ips  # ["x.x.x.x/32", "y.y.y.y/32"]
  tags      = local.common_tags
}

# WebACL com regra de whitelist
resource "aws_wafv2_web_acl" "staging_access_control" {
  name        = "staging-access-control"
  description = "Controle de acesso por IP para ambiente staging"
  scope       = "REGIONAL"

  default_action {
    block {}  # Bloqueia tudo por padrão
  }

  rule {
    name     = "AllowWhitelistedIPs"
    priority = 5

    action {
      allow {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.staging_whitelist.arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "StagingIPWhitelist"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "StagingAccessControl"
    sampled_requests_enabled   = true
  }

  tags = local.common_tags
}

output "staging_waf_acl_arn" {
  value = aws_wafv2_web_acl.staging_access_control.arn
}
```

**Variável a adicionar em `variables.tf`:**
```hcl
variable "staging_allowed_ips" {
  description = "Lista de IPs autorizados (CIDR) para acesso ao ambiente staging"
  type        = list(string)
  default     = []  # Preencher com IPs reais antes do deploy
}
```

---

### Step 3 — Keycloak: domain_suffix + Protocol

**Arquivo:** `domains/secrets-management/keycloak/values-staging.yaml` (ou equivalente Helm values)

```yaml
# Antes (HTTP, domínio fictício)
keycloak:
  ingress:
    hostname: keycloak.staging.internal
  extraEnv: |
    - name: KC_HOSTNAME
      value: keycloak.staging.internal
    - name: KC_HOSTNAME_STRICT
      value: "false"

# Depois (HTTPS, domínio real)
keycloak:
  ingress:
    hostname: keycloak.staging.alvocard.com.br
    annotations:
      alb.ingress.kubernetes.io/certificate-arn: "${ACM_CERT_ARN}"
      alb.ingress.kubernetes.io/wafv2-acl-arn: "${WAF_ACL_ARN}"
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
      alb.ingress.kubernetes.io/ssl-redirect: "443"
  extraEnv: |
    - name: KC_HOSTNAME
      value: https://keycloak.staging.alvocard.com.br
    - name: KC_HOSTNAME_STRICT
      value: "true"
    - name: KC_PROXY
      value: edge
```

**Clients a atualizar no Keycloak IaC (Terraform):**
- `gitlab` → redirectUri: `https://gitlab.staging.alvocard.com.br/*`
- `harbor` → redirectUri: `https://harbor.staging.alvocard.com.br/*`
- `grafana` → redirectUri: `https://grafana.staging.alvocard.com.br/*`
- `argocd` → redirectUri: `https://argocd.staging.alvocard.com.br/*`
- `sonarqube` → redirectUri: `https://sonarqube.staging.alvocard.com.br/*`

---

### Step 4 — Ingress HTTPS + ACM + WAF

**Padrão a aplicar em todos os Ingresses internet-facing:**

```yaml
# Antes
metadata:
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}]'

# Depois
metadata:
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/certificate-arn: "arn:aws:acm:sa-east-1:ACCOUNT:certificate/CERT-ID"
    alb.ingress.kubernetes.io/wafv2-acl-arn: "arn:aws:wafv2:sa-east-1:ACCOUNT:regional/webacl/staging-access-control/ID"
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/group.name: "staging-platform"
spec:
  rules:
  - host: <service>.staging.alvocard.com.br
```

**Ingresses a modificar:**
- `domains/cicd-platform/infra/gitlab/ingress.yaml` → `gitlab.staging.alvocard.com.br`
- `domains/cicd-platform/infra/harbor/ingress.yaml` → `harbor.staging.alvocard.com.br`
- `domains/observability/infra/grafana/ingress.yaml` → `grafana.staging.alvocard.com.br`
- `domains/cicd-platform/infra/argocd/ingress.yaml` → `argocd.staging.alvocard.com.br`
- `domains/cicd-platform/infra/sonarqube/ingress.yaml` → `sonarqube.staging.alvocard.com.br`

---

### Step 5 — CoreDNS Split-Horizon Update

**Arquivo:** `domains/platform-core/infra/coredns/coredns-configmap.yaml`

```yaml
# Antes — resolução interna de domínios fictícios
data:
  Corefile: |
    staging.internal:53 {
        hosts {
            <ClusterIP-gitlab>    gitlab.staging.internal
            <ClusterIP-harbor>    harbor.staging.internal
            <ClusterIP-keycloak>  keycloak.staging.internal
            <ClusterIP-grafana>   grafana.staging.internal
            fallthrough
        }
        reload
    }

# Depois — resolução interna de domínios reais (evita roundtrip externo)
data:
  Corefile: |
    staging.alvocard.com.br:53 {
        hosts {
            <ClusterIP-gitlab>    gitlab.staging.alvocard.com.br
            <ClusterIP-harbor>    harbor.staging.alvocard.com.br
            <ClusterIP-keycloak>  keycloak.staging.alvocard.com.br
            <ClusterIP-grafana>   grafana.staging.alvocard.com.br
            <ClusterIP-argocd>    argocd.staging.alvocard.com.br
            fallthrough
        }
        reload
    }
    .:53 {
        forward . /etc/resolv.conf
        cache 30
        loop
        reload
        loadbalance
    }
```

---

### Step 6 — OIDC URLs Refactoring (Terraform locals)

**Arquivo:** `platform-provisioning/aws/kubernetes/terraform/environments/staging/locals.tf`

```hcl
locals {
  # Domínio base — alterar aqui muda tudo
  staging_domain = "staging.alvocard.com.br"
  staging_scheme = "https"

  # URLs derivadas automaticamente
  keycloak_base_url  = "${local.staging_scheme}://keycloak.${local.staging_domain}"
  gitlab_base_url    = "${local.staging_scheme}://gitlab.${local.staging_domain}"
  harbor_base_url    = "${local.staging_scheme}://harbor.${local.staging_domain}"
  grafana_base_url   = "${local.staging_scheme}://grafana.${local.staging_domain}"
  argocd_base_url    = "${local.staging_scheme}://argocd.${local.staging_domain}"
  sonarqube_base_url = "${local.staging_scheme}://sonarqube.${local.staging_domain}"

  # OIDC Issuer URL (Keycloak realm)
  oidc_issuer_url    = "${local.keycloak_base_url}/realms/staging"
  oidc_jwks_url      = "${local.oidc_issuer_url}/protocol/openid-connect/certs"
  oidc_token_url     = "${local.oidc_issuer_url}/protocol/openid-connect/token"
  oidc_userinfo_url  = "${local.oidc_issuer_url}/protocol/openid-connect/userinfo"
}
```

**Arquivos que consomem estas locals:**
- `domains/secrets-management/terraform/keycloak-clients.tf`
- `domains/cicd-platform/infra/gitlab/terraform/gitlab-oidc.tf`
- `domains/cicd-platform/infra/argocd/values.yaml`
- `domains/observability/infra/grafana/values.yaml`

---

### Step 7 — Route53 A-Alias Records (DNS Público)

**Arquivo:** `platform-provisioning/aws/kubernetes/terraform/environments/staging/dns-records.tf`

```hcl
# Data source para obter ALB DNS name de cada serviço
data "aws_lb" "staging_platform_alb" {
  tags = {
    "ingress.k8s.aws/stack" = "staging-platform"
  }
}

# A-alias records para cada serviço
locals {
  staging_services = {
    "gitlab"     = "gitlab.staging.alvocard.com.br"
    "harbor"     = "harbor.staging.alvocard.com.br"
    "keycloak"   = "keycloak.staging.alvocard.com.br"
    "grafana"    = "grafana.staging.alvocard.com.br"
    "argocd"     = "argocd.staging.alvocard.com.br"
    "sonarqube"  = "sonarqube.staging.alvocard.com.br"
  }
}

resource "aws_route53_record" "staging_services" {
  for_each = local.staging_services

  zone_id = aws_route53_zone.staging_alvocard.zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = data.aws_lb.staging_platform_alb.dns_name
    zone_id                = data.aws_lb.staging_platform_alb.zone_id
    evaluate_target_health = true
  }
}
```

---

## 📁 Arquivos Críticos a Modificar

| Arquivo | Tipo | Ação | Cenário |
|---------|------|------|---------|
| `platform-provisioning/aws/.../staging/dns-acm.tf` | Terraform | CRIAR | A |
| `platform-provisioning/aws/.../staging/waf-ip-whitelist.tf` | Terraform | CRIAR | A |
| `platform-provisioning/aws/.../staging/dns-records.tf` | Terraform | CRIAR | A |
| `platform-provisioning/aws/.../staging/locals.tf` | Terraform | MODIFICAR | A |
| `platform-provisioning/aws/.../staging/variables.tf` | Terraform | MODIFICAR | A |
| `domains/cicd-platform/infra/gitlab/ingress.yaml` | Kubernetes | MODIFICAR | A |
| `domains/cicd-platform/infra/harbor/ingress.yaml` | Kubernetes | MODIFICAR | A |
| `domains/observability/infra/grafana/ingress.yaml` | Kubernetes | MODIFICAR | A |
| `domains/cicd-platform/infra/argocd/ingress.yaml` | Kubernetes | MODIFICAR | A |
| `domains/cicd-platform/infra/sonarqube/ingress.yaml` | Kubernetes | MODIFICAR | A |
| `domains/secrets-management/keycloak/values-staging.yaml` | Helm Values | MODIFICAR | A |
| `domains/secrets-management/terraform/keycloak-clients.tf` | Terraform | MODIFICAR | A |
| `domains/platform-core/infra/coredns/coredns-configmap.yaml` | Kubernetes | MODIFICAR | A |
| `domains/platform-core/infra/gitlab-runner/values-staging.yaml` | Helm Values | MODIFICAR | A |
| `platform-provisioning/aws/.../staging/main.tf` | Terraform | MODIFICAR | A |

---

## 🔄 Sequência de Deploy — Cenário A

```
Step 1: Terraform apply (Route53 + ACM)
    ↓ (aguardar ~15-20 min validação ACM)
Step 2: Configurar NS delegation no registrador alvocard.com.br
    ↓ (aguardar propagação DNS ~5-60 min)
Step 3: Terraform apply (WAF IP Whitelist)
    ↓
Step 4: Atualizar Keycloak IaC (clients + hostname)
    ↓
Step 5: Atualizar Ingresses (certificate-arn + waf-arn)
    ↓ (kubectl apply)
Step 6: Atualizar CoreDNS ConfigMap
    ↓ (kubectl rollout restart coredns)
Step 7: Atualizar OIDC locals + Terraform apply restante
    ↓
Verificação: dig, curl, OIDC flow, WAF block test
```

---

## 💰 Análise de Custo

| Item | Custo/Mês | Custo/Ano |
|------|-----------|-----------|
| Route53 Hosted Zone `staging.alvocard.com.br` | $0,50 | $6,00 |
| Route53 Queries (estimado ~1M/mês) | $0,40 | $4,80 |
| ACM Certificate Wildcard | $0,00 | $0,00 |
| WAF WebACL (1 ACL, sem regras managed) | $0,00* | $0,00* |
| **Total Incremental** | **~$1/mês** | **~$11/ano** |

*WAF tem custo de $5/mês por WebACL se houver regras managed rules. Com apenas IP whitelist custom, o custo é mínimo (cobrança por requests processados — ~$0,60/mês para volumes baixos de staging).

**ROI:** Custo de $11/ano para eliminar risco de exposição de credenciais em HTTP + habilitar OIDC federation real.

---

## ⚠️ Riscos e Mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|-------|---------------|---------|-----------|
| IP fixo da equipe muda (WAF bloqueia) | MÉDIA | ALTO | Terraform variable list — atualizar e re-apply em minutos |
| ACM validation timeout (>30 min) | BAIXA | MÉDIO | Verificar NS delegation + retry manual via Console |
| CoreDNS split-horizon causa loop | BAIXA | ALTO | Testar com `kubectl exec` + `nslookup` antes de merge |
| Keycloak redirect_uri mismatch pós-migração | MÉDIA | ALTO | Atualizar todos os clients ANTES de trocar URLs |
| Certificado wildcard não cobre subdomínio de 3º nível | BAIXA | BAIXO | `*.staging.alvocard.com.br` cobre todos os casos de uso atuais |

---

## 🔁 Hooks de Transição entre Cenários

### A → B (quando contratar VPN)
1. Provisionar VPN (AWS Client VPN ou Tailscale)
2. Criar ALB interno para serviços não-públicos
3. Migrar Ingresses de `internet-facing` → `internal` (exceto Keycloak)
4. Manter WAF apenas no ALB público de Keycloak
5. Atualizar Security Groups: ALB interno accept CIDR VPN

### B → C (VPN madura, equipe consolidada)
1. Migrar Keycloak para ALB interno (se federation Entra ID suportar IP privado)
2. Criar Route53 Private Hosted Zone + associate com VPC
3. Remover registros DNS públicos exceto OIDC well-known endpoint
4. WAF: manter apenas rate limiting + logging (compliance)

---

## ✅ Critérios de Verificação

### DNS
```bash
# Verificar NS delegation
dig NS staging.alvocard.com.br

# Verificar A record
dig gitlab.staging.alvocard.com.br

# Verificar resolução interna (CoreDNS)
kubectl exec -n staging-platform-cicd deploy/gitlab -it -- nslookup gitlab.staging.alvocard.com.br
```

### HTTPS
```bash
# Verificar certificado
curl -vI https://gitlab.staging.alvocard.com.br 2>&1 | grep -E "SSL|certificate|subject"

# Verificar redirect HTTP→HTTPS
curl -I http://gitlab.staging.alvocard.com.br
# Esperado: 301 → https://
```

### OIDC Flow
```bash
# Verificar discovery endpoint
curl https://keycloak.staging.alvocard.com.br/realms/staging/.well-known/openid-configuration | jq .issuer

# Esperado: "https://keycloak.staging.alvocard.com.br/realms/staging"
```

### WAF Block Test
```bash
# De IP não autorizado (deve retornar 403)
curl -I https://gitlab.staging.alvocard.com.br
# Esperado: HTTP/1.1 403 Forbidden

# De IP autorizado (deve retornar 200 ou redirect login)
curl -I https://gitlab.staging.alvocard.com.br
# Esperado: HTTP/1.1 302 → /users/sign_in
```

---

## 📚 Referências

- **ADR-008:** TLS Strategy for ALB Ingresses (ACM + Route53 pattern aprovado)
- **ADR-046:** Keycloak SSO Strategy (OIDC federation — requer HTTPS)
- **ADR-047:** Estrutura Corporativa de Domínios (organização de subdomínios)
- **ADR-098:** DNS e Controle de Acesso Staging — alvocard.com.br (decisão arquitetural desta demanda)
- **GOV-005:** Keycloak SSO Governance (clients e redirect URIs)
- **Logbook 2026-02-27:** WAF Dashboard Deploy (WAF observability já implantado)
