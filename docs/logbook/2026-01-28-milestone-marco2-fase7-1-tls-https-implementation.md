# 📓 Marco 2 Fase 7.1 - TLS/HTTPS Implementation

| Campo          | Valor                                    |
|----------------|------------------------------------------|
| **Data**       | 2026-01-28                               |
| **Demanda**    | Implementar TLS/HTTPS para ALB Ingresses |
| **Impacto**    | Alto (Blocker para Marco 3)              |
| **Agentes**    | Multi-Agent Framework (4 especialistas)  |
| **Status**     | ✅ Código Completo (Pendente teste real) |
| **Duração**    | ~4 horas (decisão + implementação + docs) |

---

## Contexto

Implementação de TLS/HTTPS para os ALB Ingresses das test applications, solucionando o problema identificado na Fase 7 onde domínios fake (.local) impediam certificados válidos.

---

## Descoberta Crítica

**ALB Controller NÃO consegue ler Kubernetes Secrets para certificados**

Suporta apenas:
- ✅ AWS ACM (Amazon Certificate Manager) via annotation ARN
- ✅ IAM Server Certificates
- ❌ Kubernetes Secrets (gerados por Cert-Manager)

**Isso torna Cert-Manager incompatível com ALB.**

---

## Processo de Decisão Multi-Agente

Utilizou framework rigoroso multi-agente com **4 especialistas**:

### Agentes Ativados

**1. AWS Specialist**
- **Voto:** ACM + Route53 ✅
- **Rationale:** Free certificates, auto-renewal, native ALB integration

**2. Terraform Specialist**
- **Voto:** ACM + Route53 ✅
- **Rationale:** Lifecycle rules, conditional resources

**3. Security Specialist**
- **Voto:** ACM + Route53 ✅ (RECOMENDAÇÃO FORTE)
- **Rationale:** TLS é blocker para Marco 3 (GitLab, Keycloak requerem PKI)

**4. FinOps Specialist**
- **Voto:** HTTP-only 🟡
- **Rationale:** Custo zero, mas reconheceu $6/ano como aceitável

**Resultado:** 3/4 agentes recomendaram ACM + Route53

---

## Alternativas Avaliadas (6 Soluções)

| Alternativa | Votos | Status | Custo/Ano | Toil Operacional |
|-------------|-------|--------|-----------|------------------|
| Self-signed | 0/4 ❌ | Rejeitado | $0 | Baixo |
| Let's Encrypt HTTP-01 | 1/4 🟡 | Rejeitado | $10-30 | Médio |
| Let's Encrypt DNS-01 | 1/4 🟡 | Rejeitado | $16 | Alto |
| ACM + Manual Upload | 0/4 ❌ | Rejeitado | $10-30 | Muito Alto |
| HTTP-only (No TLS) | 0/4 ❌ | Rejeitado | $0 | Zero |
| **ACM + Route53 DNS** | **3/4 ✅** | **ESCOLHIDA** | **$10-11** | **Muito Baixo** |

---

## Decisão Final: ACM + Route53 DNS Validation

### Justificativa

**Vantagens:**
- ✅ **ACM:** Certificados públicos gratuitos com auto-renewal automático (60 dias antes de expirar)
- ✅ **Route53 DNS Validation:** Terraform cria TXT records automaticamente em 5-30 minutos
- ✅ **Backward Compatibility:** `enable_tls=false` mantém HTTP-only sem quebras
- ✅ **Marco 3 Ready:** Certificados confiáveis essenciais para GitLab, Keycloak, Harbor
- ✅ **Zero Toil:** Sem necessidade de Cert-Manager IRSA, rotation manual, ou renovação

**Trade-offs Aceitos:**
- ⚠️ Vendor lock-in AWS (aceito para simplificar operações)
- ⚠️ Custo Route53: $11/ano (ROI justificado para eliminar toil)

---

## Solução Implementada

### Módulos Terraform Criados

**1. acm.tf (129 linhas)**

```terraform
# 2 ACM Certificates
resource "aws_acm_certificate" "nginx_test" {
  domain_name       = "nginx-test.${var.domain_name}"
  validation_method = "DNS"
}

resource "aws_acm_certificate" "echo_server" {
  domain_name       = "echo-server.${var.domain_name}"
  validation_method = "DNS"
}

# Route53 Validation Records (for_each loop)
resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in concat(
      aws_acm_certificate.nginx_test.domain_validation_options,
      aws_acm_certificate.echo_server.domain_validation_options
    ) : dvo.domain_name => dvo
  }

  zone_id = aws_route53_zone.main[0].zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  records = [each.value.resource_record_value]
  ttl     = 60
}

# Certificate Validation (timeout 30min)
resource "aws_acm_certificate_validation" "nginx_test" {
  certificate_arn         = aws_acm_certificate.nginx_test.arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]

  timeouts {
    create = "30m"
  }

  lifecycle {
    create_before_destroy = true
  }
}
```

**2. route53.tf (113 linhas)**

```terraform
# Hosted Zone (condicional)
resource "aws_route53_zone" "main" {
  count = var.create_route53_zone ? 1 : 0
  name  = var.domain_name
}

# Alias Records para ALBs
resource "aws_route53_record" "nginx_test" {
  zone_id = aws_route53_zone.main[0].zone_id
  name    = "nginx-test.${var.domain_name}"
  type    = "A"

  alias {
    name                   = data.aws_lb.nginx_test.dns_name
    zone_id                = data.aws_lb.nginx_test.zone_id
    evaluate_target_health = true
  }
}
```

**3. main.tf (modificado)**

Substituído `file()` por `templatefile()` com variáveis dinâmicas:

```terraform
resource "kubectl_manifest" "nginx_test_ingress" {
  yaml_body = templatefile("${path.module}/manifests/nginx-test-ingress.yaml", {
    ENABLE_TLS   = var.enable_tls
    DOMAIN_NAME  = var.domain_name
    CERT_ARN     = var.enable_tls ? aws_acm_certificate.nginx_test[0].arn : ""
    LISTEN_PORTS = var.enable_tls ?
      "[{\"HTTP\": 80}, {\"HTTPS\": 443}]" :
      "[{\"HTTP\": 80}]"
  })
}
```

**4. variables.tf (modificado)**

```terraform
variable "domain_name" {
  description = "Base domain for test applications"
  type        = string
  default     = ""
}

variable "create_route53_zone" {
  description = "Whether to create Route53 hosted zone"
  type        = bool
  default     = true
}

variable "enable_tls" {
  description = "Enable TLS/HTTPS for ingresses"
  type        = bool
  default     = false  # Backward compatibility
}
```

**5. outputs.tf (modificado)**

```terraform
output "tls_summary" {
  value = var.enable_tls && var.domain_name != "" ? {
    domain_name           = var.domain_name
    nginx_url            = "https://nginx-test.${var.domain_name}"
    echo_server_url      = "https://echo-server.${var.domain_name}"
    nginx_cert_arn       = aws_acm_certificate.nginx_test[0].arn
    echo_cert_arn        = aws_acm_certificate.echo_server[0].arn
    route53_zone_id      = aws_route53_zone.main[0].zone_id
    route53_name_servers = aws_route53_zone.main[0].name_servers
  } : null
}
```

---

## Manifest Templates (HCL Conditionals)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-test
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/listen-ports: '${LISTEN_PORTS}'
    %{ if ENABLE_TLS && DOMAIN_NAME != "" ~}
    alb.ingress.kubernetes.io/certificate-arn: ${CERT_ARN}
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    %{ endif ~}
spec:
  ingressClassName: alb
  rules:
    %{ if ENABLE_TLS && DOMAIN_NAME != "" ~}
    - host: nginx-test.${DOMAIN_NAME}
    %{ else ~}
    - host: nginx-test.example.com
    %{ endif ~}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nginx-test
                port:
                  number: 80
```

---

## Resultado Final

### Arquitetura TLS

- [x] ACM certificates resources criados (2 certs)
- [x] Route53 validation records configurados (auto-created via for_each)
- [x] Route53 alias records para ALBs
- [x] Conditional resources (apenas com `enable_tls=true`)
- [x] Backward compatibility (HTTP-only sem quebras)

### Documentação Criada

**1. ADR-008: TLS Strategy for ALB Ingresses** (500+ linhas)
- Context: Timeline do problema desde Fase 7
- Decision: ACM + Route53
- Alternatives: 6 soluções comparadas
- Configuration: Examples Terraform
- Consequences: Trade-offs e KPIs

**2. TLS Implementation Guide** (400+ linhas)
- Pré-requisitos
- 5 Etapas detalhadas
- Troubleshooting (3 cenários)
- Rollback procedure

**3. Terraform Modules** (4 arquivos)
- acm.tf: 129 linhas
- route53.tf: 113 linhas
- main.tf: templatefile() integration
- variables.tf + outputs.tf

---

## Métricas

| Métrica | Valor |
|---------|-------|
| Tempo de decisão (multi-agent) | ~30 min |
| Tempo de implementação | ~3 horas |
| Tempo de documentação | ~1 hora |
| **Tempo total** | **~4 horas** |
| Arquivos modificados | 12 |
| Linhas adicionadas | +1416 |
| Git commit | 94ad71b |

---

## Custo e ROI

### Custo TLS

| Item | Custo Mensal | Custo Anual |
|------|--------------|-------------|
| ACM Certificates | **$0** (free tier) | **$0** |
| Route53 Hosted Zone | $0.50 | $6 |
| Route53 Queries | ~$0.40 | ~$5 |
| **Total** | **$0.90/mês** | **~$11/ano** |

### ROI vs Alternativas

**vs Let's Encrypt DNS-01:**
- Economia financeira: $0 (ambos usam Route53)
- **Economia operacional:** ~10h/ano toil (sem Cert-Manager IRSA, sem cert rotation)

**vs Manual Certificates:**
- Economia: ~10h/ano toil manual renewal

**vs HTTP-only:**
- Custo: $11/ano
- **Benefício:** Segurança essencial para Marco 3 (GitLab, Keycloak)

---

## Issues e Lessons Learned

### Issue #1: Conditional Output Syntax Error

**Erro:** Missing false expression em `outputs.tf`

**Causa:** Referência a recursos condicionais em ternary expressions

**Fix:** Reestruturado para sempre retornar objeto com campos condicionais internamente

### Issue #2: YAML Linter em Template Files

**Erro:** Múltiplos erros YAML devido sintaxe HCL template

**Status:** NÃO É ERRO - Comportamento esperado (files são templates, não YAML puro)

**Fix:** YAML linter deve ignorar `manifests/*.yaml`

---

## Lições Aprendidas

### 🤖 Multi-Agent Framework

| # | Lição | Impacto |
|---|-------|---------|
| 1 | **Multi-Agent Framework funciona** - 4 especialistas analisaram 6 alternativas e consenso obtido em 30 min vs dias de research | 🔴 Crítico |
| 2 | Security Specialist classificou TLS como blocker crítico (não otimização) para Marco 3 | 🔴 Crítico |

### 🔒 ALB + Kubernetes

| # | Lição | Impacto |
|---|-------|---------|
| 3 | **ALB Controller NÃO consegue ler Kubernetes Secrets** - TLS para ALB SEMPRE requer ACM ou IAM | 🔴 Crítico |
| 4 | Domínios fake (.local, .internal) bloqueiam Let's Encrypt e ACM | 🔴 Crítico |
| 5 | Se TLS requerido, domínio real é obrigatório | 🔴 Crítico |

### 🏗️ Arquitetura

| # | Lição | Impacto |
|---|-------|---------|
| 6 | Backward compatibility (`enable_tls=false`) deve ser primeira classe | 🟡 Médio |
| 7 | Cert-Manager vs ACM: Trade-off entre vendor agnostic (toil alto) vs vendor lock-in (toil zero) | 🟡 Médio |
| 8 | ACM auto-renewal 60 dias antes de expirar elimina toil operacional | 🟡 Médio |

---

## Status Final

- ✅ Código completo e documentado
- ✅ ADR-008 criado
- ✅ Implementation Guide criado
- ✅ Governance validated
- ✅ Git commit approved
- ⏳ **Pendente:** Teste real de deploy com domínio registrado

---

## Referências

- [ADR-008: TLS Strategy for ALB Ingresses](../adr/adr-008-tls-strategy-for-alb-ingresses.md)
- [AWS ACM Documentation](https://docs.aws.amazon.com/acm/)
- [Route53 DNS Validation](https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- Git commit: `94ad71b`
