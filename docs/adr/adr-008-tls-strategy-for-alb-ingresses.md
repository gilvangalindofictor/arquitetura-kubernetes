# ADR-008: TLS Strategy for ALB Ingresses

**Status:** ✅ APPROVED
**Data:** 2026-01-28
**Decisores:** DevOps Team + Claude Sonnet 4.5
**Tags:** `tls`, `https`, `acm`, `alb`, `security`, `certificates`

---

## Contexto

Durante a implementação do Marco 2 Fase 7 (Test Applications), enfrentamos um **bloqueio crítico** ao tentar habilitar TLS/HTTPS nos ALBs provisionados pelo AWS Load Balancer Controller:

**Problema Identificado:**
- Ingresses configurados com TLS section e domínios fake (`.local`) sem DNS real
- Cert-Manager não conseguiu gerar certificados válidos para domínios não existentes
- ALB Controller exigiu certificados reais antes de provisionar HTTPS listeners
- AWS ALB API erro: `ValidationError: A certificate must be specified for HTTPS listeners`

**Impacto:**
- ALBs não foram provisionados inicialmente (sem ADDRESS no Ingress)
- Solução temporária: Remover TLS, configurar HTTP-only
- Marco 3 (GitLab, Keycloak) **requer** HTTPS (credenciais, OAuth2 tokens)

**Necessidade:**
Definir estratégia de TLS adequada para ALBs internet-facing que:
1. Funcione sem DNS configurado (ideal) ou com custo mínimo de DNS
2. Forneça browser trust (certificados válidos)
3. Suporte auto-renewal (evitar renovação manual)
4. Seja gerenciável via Terraform (IaC completo)
5. Estabeleça pattern reutilizável para Marco 3

---

## Decisão

**Implementar AWS ACM (Certificate Manager) com validação DNS via Route53**

### Componentes da Solução

| Componente | Tecnologia | Justificativa |
|------------|------------|---------------|
| **Certificados** | AWS ACM (público, DNS-validated) | Gratuito, auto-renewal automático, browser trust |
| **DNS** | AWS Route53 Hosted Zone | Validação automática, integração nativa AWS |
| **Provisioning** | Terraform `aws_acm_certificate` resource | IaC completo, drift zero, state gerenciado |
| **Ingress Integration** | ALB annotation `certificate-arn` | Integração nativa ALB Controller, sem sync tools |

### Arquitetura

```
┌─────────────────────────────────────────────────────────┐
│                       Internet                           │
└──────────────────────┬──────────────────────────────────┘
                       │
                ┌──────▼───────┐
                │  Route53     │
                │  Hosted Zone │  ← Validação DNS automática
                └──────┬───────┘
                       │
        ┌──────────────┴──────────────┐
        │  ACM Certificate            │
        │  (DNS-validated)            │  ← Renovação automática
        │  CN=app.domain.com          │
        └──────────────┬──────────────┘
                       │
                ┌──────▼───────┐
                │  ALB (HTTPS) │  ← Annotation: certificate-arn
                │  Port 443    │
                └──────┬───────┘
                       │
                ┌──────▼───────┐
                │  Ingress     │  ← Sem TLS section (ACM gerencia)
                │  (Kubernetes)│
                └──────────────┘
```

---

## Alternativas Consideradas

### ❌ Opção A: Self-Signed via Cert-Manager (Sem DNS)

**Rejeitada:**
- 🔴 **Browser Warnings:** Navegadores exibem "Your connection is not private"
- 🔴 **Incompatibilidade Arquitetural:** ALB não lê Kubernetes Secrets
- 🔴 **Renovação Manual:** Requer sync tool ou upload manual ACM a cada 90 dias
- 🔴 **Não Prod-Ready:** Inadequado para testes realistas e produção
- ✅ **Custo:** $0/ano
- ✅ **Sem DNS:** Não requer domínio real

**Decisão:** Rejeitado - Browser warnings violam requisito de testes realistas

---

### ⚠️ Opção B: Let's Encrypt HTTP-01 + Route53

**Não Recomendada:**
- 🔴 **Complexidade:** Cert-Manager + sync tool (`kube-cert-acm`) + Route53
- 🔴 **Chicken-Egg:** ALB precisa existir para validação, mas validação é requisito para HTTPS
- 🔴 **Dependência Externa:** Tool de terceiros para sync Secret → ACM
- 🔴 **Drift Risk:** Certificados criados fora do Terraform state
- ✅ **Browser Trust:** Certificados Let's Encrypt válidos
- ✅ **Custo:** $6-10/ano (Route53)
- 🟡 **Auto-Renewal:** Complexo (Cert-Manager + sync tool)

**Decisão:** Complexidade não justificada vs ACM direto (Opção C escolhida)

---

### ⚠️ Opção C: Let's Encrypt DNS-01 + Route53

**Não Recomendada:**
- 🔴 **Ainda Mais Complexo:** Cert-Manager + IRSA Route53 + sync tool
- 🔴 **Overhead:** IAM Policy Route53, ServiceAccount annotation, kube-cert-acm
- ✅ **Wildcard Support:** Permite `*.domain.com` (útil para múltiplos subdomínios)
- ✅ **Segurança:** Não requer porta 80 aberta (vs HTTP-01)
- ✅ **Browser Trust:** Certificados Let's Encrypt válidos
- 🟡 **Custo:** $6-10/ano (Route53)

**Decisão:** Complexidade desnecessária - ACM oferece mesmas vantagens com menos componentes

---

### ❌ Opção D: Certificado Manual Upload ACM

**Rejeitada:**
- 🔴 **Renovação Manual:** A cada 90 dias (Let's Encrypt) ou 1 ano (certificado pago)
- 🔴 **Viola IaC:** Mudanças fora do Terraform
- 🔴 **Drift Alto:** Sem auditoria, difícil rastrear alterações
- 🔴 **Toil Operacional:** Insustentável para múltiplos ambientes
- ✅ **Browser Trust:** Certificados válidos
- 🟡 **Custo:** $0 (Let's Encrypt) a $200/ano (certificado comercial)

**Decisão:** Violação de princípios de automação e IaC

---

### ❌ Opção E: HTTP-only (Manter Status Quo)

**Temporário Apenas:**
- 🔴 **Segurança:** Tráfego não criptografado exposto à internet
- 🔴 **Compliance:** Viola boas práticas mesmo em test/staging
- 🔴 **Bloqueador Marco 3:** GitLab/Keycloak REQUEREM HTTPS obrigatoriamente
- 🔴 **Cert-Manager Não Validado:** Fase 2 nunca testada em cenário real
- ✅ **Custo:** $0/ano
- ✅ **Simplicidade:** Zero configuração adicional

**Decisão:** Aceitável por 1-2 semanas como workaround, **não** solução permanente

---

### ✅ Opção F: AWS ACM + Route53 DNS Validation (ESCOLHIDA)

**Aprovada:**
- ✅ **Browser Trust:** Certificados validados por Amazon Trust Services (CA pública)
- ✅ **Auto-Renewal Nativo:** ACM renova automaticamente 60 dias antes de expirar
- ✅ **Zero Custo Certificados:** ACM público é gratuito
- ✅ **IaC Completo:** Terraform resource `aws_acm_certificate` + `aws_route53_record`
- ✅ **Drift Zero:** State gerenciado, `terraform plan` detecta mudanças
- ✅ **Integração Nativa:** ALB Controller annotation `certificate-arn` (sem sync tools)
- ✅ **Prod-Ready:** Adequado para produção (compliance, auditoria CloudTrail)
- ✅ **Simplicidade:** Menos componentes que Let's Encrypt + Cert-Manager + sync
- ✅ **Observabilidade:** CloudWatch Metrics nativos (Days to Expiry)
- 🟡 **Custo DNS:** $6-10/ano (Route53 Hosted Zone + queries)
- 🟡 **Requer Domínio Real:** Não funciona com domínios fake

**Custo-Benefício:**
- Investimento: $6-10/ano (Route53)
- Economia vs Manual Renewal: ~12h/ano de toil operacional
- Habilitador: Desbloqueia Marco 3 (GitLab, Keycloak)

---

## Configuração Implementada

### Terraform Resources

**1. Route53 Hosted Zone (DNS)**
```hcl
resource "aws_route53_zone" "test_apps" {
  name    = var.domain_name  # e.g., "test-apps.k8s-platform.com.br"
  comment = "Test Applications - Marco 2 Fase 7.1"
}
```

**2. ACM Certificate (TLS)**
```hcl
resource "aws_acm_certificate" "nginx_test" {
  domain_name       = "nginx-test.${var.domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}
```

**3. DNS Validation (Automática)**
```hcl
resource "aws_route53_record" "nginx_test_validation" {
  for_each = {
    for dvo in aws_acm_certificate.nginx_test.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = aws_route53_zone.test_apps.zone_id
  name    = each.value.name
  records = [each.value.record]
  ttl     = 60
  type    = each.value.type
}
```

**4. Aguardar Validação**
```hcl
resource "aws_acm_certificate_validation" "nginx_test" {
  certificate_arn         = aws_acm_certificate.nginx_test.arn
  validation_record_fqdns = [for record in aws_route53_record.nginx_test_validation : record.fqdn]

  timeouts {
    create = "30m"
  }
}
```

**5. Ingress com ACM Certificate**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    alb.ingress.kubernetes.io/certificate-arn: ${NGINX_CERT_ARN}
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
spec:
  rules:
  - host: nginx-test.test-apps.k8s-platform.com.br
    http:
      paths:
      - path: /
        backend:
          service:
            name: nginx-test
```

**6. DNS Alias para ALB**
```hcl
resource "aws_route53_record" "nginx_test" {
  zone_id = aws_route53_zone.test_apps.zone_id
  name    = "nginx-test.${var.domain_name}"
  type    = "A"

  alias {
    name                   = data.aws_lb.nginx_test_alb.dns_name
    zone_id                = data.aws_lb.nginx_test_alb.zone_id
    evaluate_target_health = true
  }
}
```

---

## Variáveis Terraform

**Marco 2 Environment:**
```hcl
variable "test_apps_domain_name" {
  description = "Base domain for test applications (e.g., test-apps.k8s-platform.com.br)"
  type        = string
  default     = ""  # Leave empty to disable TLS
}

variable "test_apps_create_route53_zone" {
  description = "Create Route53 hosted zone (false if zone already exists)"
  type        = bool
  default     = false
}

variable "test_apps_enable_tls" {
  description = "Enable TLS/HTTPS for ALB Ingresses"
  type        = bool
  default     = false
}
```

---

## Consequências

### Positivas ✅

1. **Segurança:**
   - Tráfego HTTPS criptografado (TLS 1.2+)
   - Browser trust funcional (sem avisos de certificado)
   - Pattern seguro estabelecido para Marco 3 (GitLab, Keycloak)

2. **Operacional:**
   - Auto-renewal eliminando toil manual (ACM renova automaticamente)
   - Observabilidade via CloudWatch (Days to Expiry metric)
   - Auditoria completa via CloudTrail (emissão, renovação, revogação)

3. **IaC & Drift:**
   - Terraform gerencia lifecycle completo (zero drift)
   - `terraform plan` detecta mudanças em certificados
   - Reproduzível em múltiplos ambientes (dev, staging, prod)

4. **Custo:**
   - Certificados gratuitos (ACM público sem custo)
   - Baixo custo DNS ($6-10/ano Route53)
   - Economia vs certificados comerciais ($50-200/ano)

### Negativas ⚠️

1. **Custo Recorrente:**
   - Route53 Hosted Zone: $0.50/mês × 12 = $6/ano
   - Route53 Queries: ~$0.40/mês × 12 = $4.80/ano
   - **Total:** ~$10/ano por domínio

2. **Dependência AWS:**
   - Vendor lock-in ACM (certificados não exportáveis para uso fora AWS)
   - Migração futura para outro cloud requer re-emissão de certificados
   - Mitigação: Arquitetura permite substituir ACM por Cert-Manager + Let's Encrypt

3. **Requisito Domínio Real:**
   - Impossível usar domínios fake (`.local`, `.test`)
   - Requer registro de domínio real ($12-20/ano)
   - Mitigação: Subdomínio de domínio existente (custo zero adicional)

4. **Tempo de Validação:**
   - Primeira emissão: 5-30 minutos (validação DNS)
   - Deploy pode levar até 30 min total (ACM validation + ALB reconciliation)
   - Mitigação: Timeout configurado `create = "30m"` no Terraform

### Riscos Identificados 🚨

| Risco | Probabilidade | Impacto | Mitigação |
|-------|---------------|---------|-----------|
| **Falha validação DNS** | BAIXA | ALTO | Terraform retry automático, validação manual via AWS console se necessário |
| **ALB não provisiona HTTPS** | BAIXA | ALTO | Rollback para HTTP-only via annotation, troubleshoot ALB Controller logs |
| **Renovação ACM falha** | MUITO BAIXA | MÉDIO | ACM notifica 45/30/15 dias antes expiração via email, renovação manual possível |
| **Custo Route53 excede orçamento** | BAIXA | BAIXO | Monitorar AWS Cost Explorer, consolidar zonas DNS se possível |

---

## Métricas de Sucesso

### Funcionalidade
- [x] Certificados ACM status `ISSUED` (validação DNS bem-sucedida)
- [x] ALBs provisionados com HTTPS listeners (porta 443 ativa)
- [x] Browser trust validado (cadeado verde, sem avisos)
- [x] Redirect HTTP → HTTPS funcionando (`ssl-redirect: "443"`)

### Segurança
- [x] TLS 1.2+ habilitado (AWS default)
- [x] Certificados renovados automaticamente (ACM managed)
- [x] Auditoria CloudTrail ativa (emissão, renovação)
- [x] Secrets não expostos (certificados gerenciados por ACM, não em Git)

### Custo
- [x] Custo Route53 < $15/ano
- [x] Certificados ACM: $0 (gratuito)
- [x] ROI vs certificado comercial: $40-190/ano economizados

### IaC
- [x] Terraform state inclui certificados ACM
- [x] `terraform plan` drift detection funcional
- [x] Rollback possível (destroy + apply anterior state)
- [x] Reproduzível em ambientes múltiplos

---

## Lições Aprendidas

### Técnicas

1. **ALB + Cert-Manager Incompatibilidade**
   - ALB Controller NÃO lê Kubernetes Secrets (certificados)
   - Certificados devem estar em ACM ou IAM Server Certificates
   - Cert-Manager útil para NGINX Ingress, não para ALB

2. **Domínios Fake Não Funcionam**
   - `.local`, `.test`, `.localhost` não resolvem publicamente
   - Let's Encrypt requer DNS público para validação
   - Self-signed gera browser warnings (inadequado para testes realistas)

3. **Terraform Templatefile para Ingress**
   - Injetar `certificate-arn` via templatefile() dinâmico
   - Permite habilitar/desabilitar TLS via variável `enable_tls`
   - Manifests YAML com sintaxe template HCL (`%{ if }`)

4. **Validação DNS Automática**
   - ACM gera TXT records que devem ser criados no Route53
   - Terraform `for_each` automatiza criação de validation records
   - `aws_acm_certificate_validation` aguarda validação completar (timeout 30min)

### Operacionais

5. **Tempo de Provisionamento**
   - ACM validation: 5-10 minutos (típico), até 30 min (pior caso)
   - ALB reconciliation: 3-5 minutos após certificado validado
   - Total: ~15-20 minutos para HTTPS funcional

6. **Troubleshooting**
   - Logs ALB Controller: `kubectl logs -n kube-system deployment/aws-load-balancer-controller`
   - ACM status: `aws acm describe-certificate --certificate-arn <ARN>`
   - DNS propagation: `dig nginx-test.domain.com` (verificar CNAME/A record)

### Arquiteturais

7. **Pattern Reutilizável Marco 3**
   - Mesmo pattern ACM + Route53 para GitLab, Keycloak, Harbor
   - Wildcard certificate viável: `*.apps.k8s-platform.com.br` (1 cert para múltiplos apps)
   - IngressGroup consolidation possível (múltiplos Ingresses, 1 ALB, 1 certificado)

8. **Separação de Responsabilidades**
   - ACM para ALB Ingresses (internet-facing, public trust)
   - Cert-Manager para NGINX Ingress futuros (internal, pod-to-pod mTLS)
   - Documentar em ADR evita confusão de quando usar cada um

---

## Referências

**AWS Documentation:**
- [AWS Certificate Manager](https://docs.aws.amazon.com/acm/)
- [SSL certificates for ALB](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/https-listener-certificates.html)
- [Route53 Developer Guide](https://docs.aws.amazon.com/route53/)

**Kubernetes & ALB Controller:**
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [Ingress annotations](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/ingress/annotations/)

**Terraform:**
- [aws_acm_certificate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate)
- [aws_route53_record](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record)

**Projeto:**
- [FASE7-IMPLEMENTATION.md](../../platform-provisioning/aws/kubernetes/terraform/envs/marco2/FASE7-IMPLEMENTATION.md)
- [executor-terraform.md](../prompts/executor-terraform.md) - Framework de análise TLS
- [00-diario-de-bordo.md](../plan/aws-execution/00-diario-de-bordo.md) - Fase 7.1 entry

**ADRs Relacionados:**
- [ADR-002: Estrutura de Domínios](adr-002-estrutura-de-dominios.md)
- [ADR-003: Secrets Management](adr-003-secrets-management-strategy.md)
- [ADR-004: Terraform vs Helm](adr-004-terraform-vs-helm-for-platform-services.md)

---

**Aprovado por:** DevOps Team + Claude Sonnet 4.5
**Data de Aprovação:** 2026-01-28
**Próxima Revisão:** Marco 3 GitLab deployment (validar pattern em produção)
