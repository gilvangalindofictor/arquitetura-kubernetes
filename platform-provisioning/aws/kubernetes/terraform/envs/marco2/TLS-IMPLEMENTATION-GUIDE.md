# Guia de Implementação TLS - Marco 2 Fase 7.1

**Data:** 2026-01-28
**Status:** 📝 PRONTO PARA IMPLEMENTAÇÃO (código completo, aguardando domínio)
**Executor:** DevOps Team + Claude Sonnet 4.5

---

## 📋 Sumário Executivo

Este guia descreve como habilitar TLS/HTTPS nos ALBs das test applications usando AWS ACM + Route53.

**Código Terraform:** ✅ 100% implementado
**Tempo Estimado:** 4-6 horas (incluindo registro de domínio)
**Custo Adicional:** ~$10-30/ano (domínio + Route53)

---

## 🎯 Pré-Requisitos

### OBRIGATÓRIO: Domínio Registrado

Você precisa de um domínio real para emitir certificados ACM. Opções:

#### Opção A: Registrar Domínio Novo (Recomendado)

**Registro.br (.com.br):**
```bash
# 1. Acessar: https://registro.br
# 2. Verificar disponibilidade do domínio desejado
# 3. Registrar domínio (ex: k8s-platform-test.com.br)
#
# Custo: ~R$40/ano (≈$8 USD)
# Tempo: 1-2 horas (aprovação imediata geralmente)
```

**AWS Route53 (.com, .net, .org):**
```bash
# Registrar via AWS Console ou CLI
aws route53domains register-domain \
  --domain-name k8s-platform-test.com \
  --duration-in-years 1 \
  --admin-contact file://contact.json \
  --registrant-contact file://contact.json \
  --tech-contact file://contact.json

# Custo: $12-15/ano (.com)
# Tempo: 15-30 minutos
```

#### Opção B: Usar Subdomínio de Domínio Existente

Se você já tem um domínio (ex: `meudominio.com.br`), pode criar um subdomínio:

```
test-apps.meudominio.com.br
```

**Custo:** $0 (usa domínio existente)
**Setup:** Delegar DNS para Route53 (ver seção "Delegação DNS" abaixo)

---

## 🚀 Passos de Implementação

### ETAPA 1: Configurar Variáveis Terraform (5 minutos)

**Arquivo:** `terraform.tfvars` (ou passar via CLI)

```hcl
# Marco 2 Fase 7.1 - TLS Configuration
test_apps_domain_name          = "test-apps.k8s-platform.com.br"  # ALTERAR para seu domínio
test_apps_create_route53_zone  = true                             # true para criar nova zone
test_apps_enable_tls           = true                             # Habilitar TLS/HTTPS
```

**Criar arquivo `terraform.tfvars` (se não existir):**

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/envs/marco2

cat > terraform.tfvars <<EOF
# Variáveis existentes (manter)
cluster_name          = "k8s-platform-prod"
region                = "us-east-1"
vpc_id                = "vpc-0b1396a59c417c1f0"
letsencrypt_email     = "seu-email@example.com"
grafana_admin_password = "senha-segura-aqui"

# Fase 7.1: TLS Configuration (NOVO)
test_apps_domain_name          = "test-apps.k8s-platform.com.br"
test_apps_create_route53_zone  = true
test_apps_enable_tls           = true
EOF
```

---

### ETAPA 2: Terraform Plan (10 minutos)

**Validar recursos que serão criados:**

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/envs/marco2

# Inicializar Terraform (se necessário)
terraform init -upgrade

# Validar sintaxe
terraform validate

# Gerar plan
terraform plan -out=tfplan-fase7.1-tls

# Revisar plan
terraform show tfplan-fase7.1-tls
```

**Recursos Esperados (a serem criados):**

| Recurso | Quantidade | Descrição |
|---------|-----------|-----------|
| `aws_route53_zone.test_apps` | 1 | Hosted Zone DNS |
| `aws_acm_certificate.nginx_test` | 1 | Certificado NGINX |
| `aws_acm_certificate.echo_server` | 1 | Certificado Echo Server |
| `aws_route53_record.*_validation` | 2 | DNS validation records |
| `aws_acm_certificate_validation.*` | 2 | Aguardar validação |
| `aws_route53_record.nginx_test` | 1 | Alias para ALB NGINX |
| `aws_route53_record.echo_server` | 1 | Alias para ALB Echo Server |
| `kubectl_manifest.nginx_test` | 4 | **RECRIADOS** (com TLS) |
| `kubectl_manifest.echo_server` | 4 | **RECRIADOS** (com TLS) |

**Total:** ~15-20 recursos criados/modificados

**⚠️ ATENÇÃO:**
- Ingress resources serão **RECRIADOS** (destroy + create)
- ALBs serão **RECRIADOS** com HTTPS listeners
- Downtime esperado: ~5-10 minutos (durante ALB recreation)

---

### ETAPA 3: Terraform Apply (20-30 minutos)

**Executar apply:**

```bash
terraform apply tfplan-fase7.1-tls
```

**Timeline Esperada:**

```
[00:00] Iniciando apply...
[00:01] Criando Route53 Hosted Zone... ✅ (2min)
[00:03] Criando certificados ACM... ✅ (1min)
[00:04] Criando DNS validation records... ✅ (30s)
[00:05] Aguardando validação ACM... ⏳ (5-25min)
        Status: PENDING_VALIDATION → ISSUED
[00:15] Validação completada! ✅
[00:16] Recriando Ingress resources... ✅ (2min)
[00:18] ALB Controller detecta mudança...
[00:19] Recriando ALBs com HTTPS... ⏳ (5-8min)
[00:25] ALBs ativos com HTTPS listeners ✅
[00:26] Criando DNS Alias records... ✅ (1min)
[00:27] Apply completo! ✅

Total: ~20-30 minutos
```

**Monitorar progresso:**

```bash
# Terminal 1: Terraform apply
terraform apply tfplan-fase7.1-tls

# Terminal 2: Watch Ingress status
watch -n 5 'kubectl get ingress -n test-apps'

# Terminal 3: Watch pods
watch -n 5 'kubectl get pods -n test-apps'

# Terminal 4: ALB Controller logs
kubectl logs -f -n kube-system deployment/aws-load-balancer-controller
```

---

### ETAPA 4: Delegação DNS (se usar subdomínio) (10 minutos)

**Se você criou subdomínio de domínio existente, delegar DNS:**

```bash
# 1. Obter Name Servers do Route53 Hosted Zone
terraform output test_apps_tls_summary
# Procurar por: route53_name_servers

# Exemplo de output:
# route53_name_servers = [
#   "ns-123.awsdns-45.com",
#   "ns-678.awsdns-90.org",
#   "ns-901.awsdns-23.co.uk",
#   "ns-456.awsdns-78.net"
# ]

# 2. No domínio PAI (ex: k8s-platform.com.br), criar NS record:
#    Nome: test-apps.k8s-platform.com.br
#    Tipo: NS
#    Valores: (copiar name servers do Route53)
```

**Via AWS Route53 Console (se domínio pai também está no Route53):**
```bash
aws route53 change-resource-record-sets \
  --hosted-zone-id <ZONE_ID_DOMINIO_PAI> \
  --change-batch file://delegation.json

# delegation.json:
{
  "Changes": [{
    "Action": "CREATE",
    "ResourceRecordSet": {
      "Name": "test-apps.k8s-platform.com.br",
      "Type": "NS",
      "TTL": 300,
      "ResourceRecords": [
        {"Value": "ns-123.awsdns-45.com"},
        {"Value": "ns-678.awsdns-90.org"},
        {"Value": "ns-901.awsdns-23.co.uk"},
        {"Value": "ns-456.awsdns-78.net"}
      ]
    }
  }]
}
```

---

### ETAPA 5: Validação (15 minutos)

#### V1: Verificar Certificados ACM

```bash
# Status dos certificados
terraform output test_apps_tls_summary

# Esperado:
# nginx_test_certificate_status = "ISSUED"
# echo_server_certificate_status = "ISSUED"

# Detalhes via AWS CLI
aws acm describe-certificate \
  --certificate-arn $(terraform output -raw test_apps_tls_summary | jq -r '.nginx_test_certificate_arn') \
  --region us-east-1
```

#### V2: Verificar DNS Resolution

```bash
# Obter domínios
NGINX_DOMAIN=$(terraform output -raw test_apps_tls_summary | jq -r '.nginx_test_domain')
ECHO_DOMAIN=$(terraform output -raw test_apps_tls_summary | jq -r '.echo_server_domain')

# Verificar resolução DNS
dig $NGINX_DOMAIN A +short
# Esperado: IPs do ALB

dig $ECHO_DOMAIN A +short
# Esperado: IPs do ALB
```

#### V3: Teste HTTPS

```bash
# NGINX Test
curl -I https://nginx-test.test-apps.k8s-platform.com.br
# Esperado:
# HTTP/2 200
# server: nginx/1.27

# Echo Server
curl https://echo-server.test-apps.k8s-platform.com.br | jq
# Esperado: JSON com request details

# Verificar certificado
curl -vI https://nginx-test.test-apps.k8s-platform.com.br 2>&1 | grep "subject:"
# Esperado: CN=nginx-test.test-apps.k8s-platform.com.br

curl -vI https://nginx-test.test-apps.k8s-platform.com.br 2>&1 | grep "issuer:"
# Esperado: issuer: C=US; O=Amazon; CN=Amazon RSA 2048 M02
```

#### V4: Browser Test

```bash
# Abrir no navegador:
https://nginx-test.test-apps.k8s-platform.com.br

# Verificar:
# ✅ Cadeado verde (sem avisos de segurança)
# ✅ Certificado válido (clicar no cadeado → Ver certificado)
# ✅ Emitido por: Amazon Trust Services
# ✅ Válido até: (data 1 ano no futuro)
```

#### V5: Redirect HTTP → HTTPS

```bash
# Testar redirect
curl -I http://nginx-test.test-apps.k8s-platform.com.br
# Esperado:
# HTTP/1.1 301 Moved Permanently
# Location: https://nginx-test.test-apps.k8s-platform.com.br/
```

---

## 🔍 Troubleshooting

### Problema 1: Certificado fica PENDING_VALIDATION > 30min

**Diagnóstico:**
```bash
aws acm describe-certificate \
  --certificate-arn <ARN> \
  --region us-east-1 | jq '.Certificate.DomainValidationOptions'
```

**Possíveis Causas:**
- DNS validation record não foi criado
- Route53 Hosted Zone incorreta
- Propagação DNS lenta

**Solução:**
```bash
# Verificar se validation record existe
aws route53 list-resource-record-sets \
  --hosted-zone-id <ZONE_ID> | \
  jq '.ResourceRecordSets[] | select(.Type=="CNAME" and (.Name | contains("acm-validations")))'

# Se não existir, criar manualmente
aws route53 change-resource-record-sets \
  --hosted-zone-id <ZONE_ID> \
  --change-batch file://manual-validation.json

# Aguardar até 30 minutos
```

---

### Problema 2: ALB não provisiona com HTTPS

**Diagnóstico:**
```bash
# Logs ALB Controller
kubectl logs -n kube-system deployment/aws-load-balancer-controller --tail=50

# Procurar por erros:
# "ValidationError: A certificate must be specified for HTTPS listeners"
```

**Possíveis Causas:**
- Certificado ainda não validado (status != ISSUED)
- ARN do certificado incorreto no Ingress annotation
- Region mismatch (certificado deve estar em us-east-1, mesma região do ALB)

**Solução:**
```bash
# Verificar certificado status
aws acm list-certificates --region us-east-1

# Aguardar validação completar
# Verificar ARN no Ingress
kubectl get ingress nginx-test-ingress -n test-apps -o yaml | grep certificate-arn
```

---

### Problema 3: DNS não resolve

**Diagnóstico:**
```bash
# Trace DNS resolution
dig nginx-test.test-apps.k8s-platform.com.br +trace

# Verificar NS records
dig test-apps.k8s-platform.com.br NS
```

**Possíveis Causas:**
- Delegação DNS não configurada (se subdomínio)
- Propagação DNS lenta (até 48h, geralmente < 1h)
- Route53 Alias record não criado

**Solução:**
```bash
# Verificar Alias record existe
aws route53 list-resource-record-sets \
  --hosted-zone-id <ZONE_ID> | \
  jq '.ResourceRecordSets[] | select(.Name | contains("nginx-test"))'

# Aguardar propagação DNS (verificar a cada 5min)
watch -n 300 'dig nginx-test.test-apps.k8s-platform.com.br A +short'
```

---

## 📊 Custo Estimado

| Item | Custo/Mês | Custo/Ano | Nota |
|------|-----------|-----------|------|
| **Domínio** (.com.br) | $0.67 | $8 | Registro.br |
| **Domínio** (.com) | $1.00 | $12 | Route53 registration |
| **Route53 Hosted Zone** | $0.50 | $6 | Por hosted zone |
| **Route53 Queries** | $0.40 | $4.80 | Estimado: 1M queries/mês |
| **ACM Certificates** | $0 | $0 | Gratuito (público) |
| **Total (domínio .com.br)** | **$1.57** | **$18.80** | |
| **Total (domínio .com)** | **$1.90** | **$22.80** | |
| **Total (subdomínio existente)** | **$0.90** | **$10.80** | Sem custo domínio |

**Economia vs Alternativas:**
- vs Certificado comercial: $40-200/ano economizado
- vs Let's Encrypt + sync tool: Elimina complexidade operacional
- vs HTTP-only: Habilita Marco 3 (GitLab, Keycloak)

---

## 🔄 Rollback (Se Necessário)

**Cenário:** TLS não funcionou, preciso voltar para HTTP-only

```bash
# 1. Desabilitar TLS via variável
cat > terraform.tfvars <<EOF
# ... (variáveis existentes)
test_apps_enable_tls = false  # DESABILITAR TLS
EOF

# 2. Apply
terraform apply

# 3. Aguardar ALBs serem recriados em HTTP-only (~5min)
kubectl get ingress -n test-apps -w

# 4. Validar HTTP funcionando
curl http://<ALB_DNS_NAME>
```

**Tempo de Rollback:** ~10 minutos

---

## 📚 Próximos Passos (Após TLS Funcional)

### Curto Prazo (1-2 semanas)

1. **Consolidar ALBs (Economia):**
   ```hcl
   # Adicionar annotation em ambos Ingresses
   alb.ingress.kubernetes.io/group.name: test-apps-shared
   alb.ingress.kubernetes.io/group.order: '10'  # nginx
   # ou '20' para echo-server
   ```
   - Resultado: 1 ALB em vez de 2
   - Economia: $16.20/mês ($194.40/ano)

2. **Wildcard Certificate (Simplificação):**
   ```hcl
   resource "aws_acm_certificate" "wildcard" {
     domain_name = "*.test-apps.k8s-platform.com.br"
     # ...
   }
   ```
   - 1 certificado para múltiplos apps
   - Facilita adição de novos apps

3. **WAF no ALB (Segurança):**
   ```yaml
   annotations:
     alb.ingress.kubernetes.io/wafv2-acl-arn: <WAF_ACL_ARN>
   ```
   - Proteção contra SQL injection, XSS, etc.
   - Custo adicional: ~$10/mês

### Marco 3 (Workloads Produtivos)

4. **Aplicar Pattern em GitLab:**
   - Mesma estrutura ACM + Route53
   - Domínio: `gitlab.apps.k8s-platform.com.br`
   - TLS obrigatório (OAuth2, Git push via HTTPS)

5. **Aplicar Pattern em Keycloak:**
   - Domínio: `auth.apps.k8s-platform.com.br`
   - TLS obrigatório (OAuth2 provider)

6. **Aplicar Pattern em ArgoCD:**
   - Domínio: `argocd.apps.k8s-platform.com.br`
   - TLS recomendado (web UI, CLI auth)

---

## 📖 Referências

**Documentação Criada:**
- [ADR-008: TLS Strategy](../../../../../docs/adr/adr-008-tls-strategy-for-alb-ingresses.md)
- [FASE7-IMPLEMENTATION.md](FASE7-IMPLEMENTATION.md) - Seção "Próximas Soluções TLS"

**AWS Documentation:**
- [ACM User Guide](https://docs.aws.amazon.com/acm/)
- [Route53 DNS Guide](https://docs.aws.amazon.com/route53/)
- [ALB HTTPS Listeners](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/create-https-listener.html)

**Terraform Docs:**
- [aws_acm_certificate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate)
- [aws_route53_zone](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone)

---

**Preparado por:** DevOps Team + Claude Sonnet 4.5
**Data:** 2026-01-28
**Status:** ✅ PRONTO PARA USO

Quando estiver pronto para implementar TLS, siga este guia passo a passo!
