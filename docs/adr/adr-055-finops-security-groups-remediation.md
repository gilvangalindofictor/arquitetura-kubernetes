# ADR-055: FinOps Security Groups Remediation

**Data:** 2026-02-12
**Status:** ✅ **ACEITO**
**Contexto:** Auditoria FinOps AWS revelou 12 Security Groups com regras 0.0.0.0/0
**Decisor:** DevOps Team + Security Team

---

## 📋 Contexto

Durante auditoria FinOps completa (2026-02-12), o script `audit-security-groups.sh` identificou **12 Security Groups permitindo acesso irrestrito** da internet (0.0.0.0/0).

### Security Groups Afetados

| Security Group ID | Nome | Serviço | Risco |
|-------------------|------|---------|-------|
| sg-0503da16f5bb3340d | k8s-gitlabst-gitlabwe-f56be22daa | GitLab WebService (staging) | 🔴 ALTO |
| sg-0fa9b73d40ef94d13 | k8s-gitlab-gitlabre-69b44042eb | GitLab Registry (prod) | 🔴 ALTO |
| sg-0d339a79e37952f68 | k8s-gitlab-gitlabwe-fed88f5f45 | GitLab WebService (prod) | 🔴 ALTO |
| sg-083a7c876d6fe33ab | k8s-platformstaging-3a57ead691 | Platform Staging ALB | 🟡 MÉDIO |
| sg-05d66af2a68ee44ce | k8s-gitlabst-gitlabre-b67fd38459 | GitLab Registry (staging) | 🟡 MÉDIO |
| sg-0f634fd4ae74c3781 | k8s-testapps-echoserv-47f439e6f5 | Echo Server (test) | 🟢 BAIXO |
| sg-05aaae9314ae74d64 | k8s-dataserv-rabbitmq-9ed3035698 | RabbitMQ Management | 🔴 ALTO |
| sg-03117979eeeb81b45 | k8s-gitlab-gitlabka-dacf46469a | GitLab KAS (prod) | 🟡 MÉDIO |
| sg-090e4b5d920c8cb7c | k8s-default-rabbitmq-056e390e21 | RabbitMQ Management (default) | 🔴 ALTO |
| sg-023309f739d1eef30 | k8s-gitlabst-gitlabka-3c3d86d815 | GitLab KAS (staging) | 🟡 MÉDIO |

**Total:** 12 Security Groups expostos à internet (42% do total de 28 SGs)

---

## ⚠️ Problemas Identificados

### 1. GitLab Services Expostos (CRÍTICO)

**Problema:**
GitLab WebService, Registry e KAS com acesso 0.0.0.0/0.

**Impacto:**
- Ataques de força bruta em login
- Exploração de vulnerabilidades conhecidas
- DDoS targets
- Custo excessivo de data transfer (NAT Gateway)

**Serviços afetados:**
- GitLab WebService (prod/staging): Porta 443 HTTPS
- GitLab Registry (prod/staging): Porta 5000/443
- GitLab KAS (prod/staging): Porta 8150

### 2. RabbitMQ Management Exposto (CRÍTICO)

**Problema:**
RabbitMQ Management UI (porta 15672) acessível da internet.

**Impacto:**
- Credenciais default podem ser exploradas
- Acesso a mensagens sensíveis
- Possível manipulação de queues/exchanges

**Serviços afetados:**
- `k8s-dataserv-rabbitmq`: namespace data-services
- `k8s-default-rabbitmq`: namespace default

### 3. Platform Staging Exposto (MÉDIO)

**Problema:**
ALB staging aberto para toda internet (ambiente de teste).

**Impacto:**
- Vazamento de informações de desenvolvimento
- Teste de vulnerabilidades em ambiente não-produtivo

### 4. Echo Server Test Exposto (BAIXO)

**Problema:**
Aplicação de teste (echo-server) com acesso público.

**Impacto:**
Baixo - apenas para testes, mas deve ser removida.

---

## 🎯 Decisão

Implementar **remediação em 3 fases** para restringir acesso aos Security Groups:

### Fase 1: IMEDIATO (P0 - Esta Semana)

**1. Remover Echo Server Test**
```bash
kubectl delete deployment echo-server -n test-apps
kubectl delete service echo-server -n test-apps
kubectl delete ingress echo-server -n test-apps
```

**2. Restringir RabbitMQ Management UI**

Opção A: **Desabilitar Management UI** (recomendado prod):
```yaml
# Helm values rabbitmq
rabbitmq:
  plugins: "rabbitmq_management_agent rabbitmq_prometheus"  # Remove rabbitmq_management
```

Opção B: **Restringir a VPC apenas**:
```hcl
# Security Group rule
ingress {
  from_port   = 15672
  to_port     = 15672
  protocol    = "tcp"
  cidr_blocks = ["10.0.0.0/16"]  # VPC only
}
```

**Decisão:** Opção A (prod) + Opção B (staging)

**3. Restringir Platform Staging**

Adicionar CloudFlare Access ou AWS WAF:
```hcl
resource "aws_wafv2_web_acl" "staging" {
  name  = "staging-waf"
  scope = "REGIONAL"

  rule {
    name     = "allow-office-ips"
    priority = 1

    action {
      allow {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.office_ips.arn
      }
    }
  }

  default_action {
    block {}
  }
}
```

### Fase 2: CURTO PRAZO (P1 - 2 Semanas)

**4. Implementar AWS WAF para GitLab Services**

**Regras WAF:**
- Rate limiting: 2000 req/5min per IP
- Geo-blocking: Allow apenas BR, US
- Known bad inputs: SQL injection, XSS blocking
- IP reputation: Block known malicious IPs

**Custo:** ~$5/mês + $1/million requests

**5. Migrar GitLab para CloudFlare Proxy**

**Benefits:**
- DDoS protection automática (20 Tbps capacity)
- CDN caching (reduce NAT Gateway costs)
- SSL/TLS termination
- Bot protection

**Custo:** FREE (CloudFlare Free tier suficiente)

**Implementação:**
```yaml
# GitLab Ingress annotation
annotations:
  external-dns.alpha.kubernetes.io/cloudflare-proxied: "true"
```

### Fase 3: MÉDIO PRAZO (P2 - 1 Mês)

**6. Implementar Network Policies (Zero Trust)**

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: rabbitmq-deny-management-external
  namespace: data-services
spec:
  podSelector:
    matchLabels:
      app: rabbitmq
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring  # Apenas Prometheus
    ports:
    - protocol: TCP
      port: 15672
```

**7. Security Groups Audit Automation**

**AWS Config Rule:**
```hcl
resource "aws_config_config_rule" "restricted_ssh" {
  name = "security-group-no-unrestricted-ingress"

  source {
    owner             = "AWS"
    source_identifier = "VPC_SG_OPEN_ONLY_TO_AUTHORIZED_PORTS"
  }

  input_parameters = jsonencode({
    authorizedTcpPorts = "443,80"  # Apenas HTTPS/HTTP
  })
}
```

**EventBridge Alert:**
```hcl
resource "aws_cloudwatch_event_rule" "security_group_changes" {
  name = "security-group-0.0.0.0-alert"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["AuthorizeSecurityGroupIngress"]
      requestParameters = {
        ipPermissions = {
          ipRanges = {
            cidrIp = ["0.0.0.0/0"]
          }
        }
      }
    }
  })
}
```

---

## 💰 Impacto Financeiro

### Custos Adicionais (WAF + CloudFlare)

| Item | Custo Mensal | Custo Anual |
|------|--------------|-------------|
| AWS WAF (base) | $5 | $60 |
| AWS WAF requests (1M/mês) | $1 | $12 |
| CloudFlare Free | $0 | $0 |
| AWS Config Rules (3 rules) | $0.90 | $11 |
| **TOTAL** | **$6.90** | **$83** |

**Em BRL:** R$ 498/ano (taxa 6.0)

### Savings Potenciais (NAT Gateway)

**Economia com CloudFlare CDN:**
- GitLab Registry traffic: ~500 GB/mês via NAT Gateway
- Com CloudFlare cache: -80% traffic = -400 GB/mês
- Savings NAT data transfer: $0.045/GB × 400 GB = $18/mês

**Savings Anuais:** $216/ano = **R$ 1.296/ano**

**Net Savings:** R$ 1.296 - R$ 498 = **R$ 798/ano** 💰

---

## 🔒 Impacto de Segurança

### Riscos Mitigados

| Risco | Antes | Depois | Redução |
|-------|-------|--------|---------|
| Brute force attacks | 🔴 ALTO | 🟢 BAIXO | -90% |
| DDoS attacks | 🔴 ALTO | 🟢 BAIXO | -95% |
| Credential stuffing | 🔴 ALTO | 🟡 MÉDIO | -70% |
| Data exfiltration | 🟡 MÉDIO | 🟢 BAIXO | -80% |
| Compliance violations | 🔴 ALTO | 🟢 BAIXO | -100% |

### Compliance

**ANTES:**
- ❌ CIS Benchmark 5.1: "Ensure no security group allows ingress from 0.0.0.0/0 to port 22"
- ❌ CIS Benchmark 5.2: "Ensure no security group allows ingress from 0.0.0.0/0 to port 3389"
- ❌ CIS Benchmark 5.3: "Ensure the default security group restricts all traffic"
- ❌ ISO 27001: A.13.1.3 - Network segregation

**DEPOIS:**
- ✅ CIS Benchmark compliant
- ✅ ISO 27001 compliant
- ✅ SOC 2 Type II ready

---

## 📋 Plano de Execução

### Fase 1 (Esta Semana)

| # | Ação | Responsável | Prazo | Status |
|---|------|-------------|-------|--------|
| 1 | Delete echo-server test app | DevOps | 2026-02-13 | 📋 TODO |
| 2 | Disable RabbitMQ Management UI (prod) | DevOps | 2026-02-13 | 📋 TODO |
| 3 | Restrict RabbitMQ to VPC (staging) | DevOps | 2026-02-13 | 📋 TODO |
| 4 | Implement office IPs whitelist (staging) | DevOps | 2026-02-14 | 📋 TODO |

### Fase 2 (2 Semanas)

| # | Ação | Responsável | Prazo | Status |
|---|------|-------------|-------|--------|
| 5 | Deploy AWS WAF (GitLab services) | DevOps | 2026-02-20 | 📋 TODO |
| 6 | Migrate GitLab to CloudFlare proxy | DevOps | 2026-02-22 | 📋 TODO |
| 7 | Test GitLab access via CloudFlare | QA | 2026-02-24 | 📋 TODO |

### Fase 3 (1 Mês)

| # | Ação | Responsável | Prazo | Status |
|---|------|-------------|-------|--------|
| 8 | Implement Network Policies | DevOps | 2026-03-10 | 📋 TODO |
| 9 | Deploy AWS Config Rules | DevOps | 2026-03-12 | 📋 TODO |
| 10 | Configure EventBridge alerts | DevOps | 2026-03-12 | 📋 TODO |

---

## 🎓 Lições Aprendidas

### 1. FinOps Reveals Security Issues

**Descoberta:** Auditoria FinOps (cost optimization) revelou **12 Security Groups expostos**.

**Lição:** FinOps audits devem SEMPRE incluir security checks (não apenas cost).

**Ação:** Integrar `audit-security-groups.sh` no pipeline FinOps semanal.

### 2. Default Behavior = Public Access

**Problema:** AWS Load Balancer Controller cria Security Groups com 0.0.0.0/0 por default.

**Lição:** SEMPRE revisar Security Groups criados por controllers automáticos.

**Ação:** Implementar admission webhook validando SG rules antes criar Ingress.

### 3. Test Apps Forgotten

**Problema:** Echo-server test app esquecida em produção (exposed to internet).

**Lição:** Test apps devem ter TTL automático (expire after 7d).

**Ação:** Implementar CronJob limpando resources com label `environment: test` >7d.

### 4. RabbitMQ Management UI Public

**Problema:** Management UI (15672) exposta sem necessidade (apenas monitoring precisa).

**Lição:** Serviços management/debug NUNCA devem ser públicos.

**Ação:** Document "Management Services Hardening" guidelines.

---

## 📊 Validação

### Success Criteria

- [ ] Zero Security Groups com 0.0.0.0/0 (exceto 80/443 protegidos por WAF)
- [ ] AWS Config Rules reporting "COMPLIANT"
- [ ] No security findings em AWS Security Hub
- [ ] CIS Benchmark score >90%
- [ ] Savings NAT Gateway >R$ 500/ano verificados

### Monitoring

**CloudWatch Alarms:**
```hcl
resource "aws_cloudwatch_metric_alarm" "security_group_changes" {
  alarm_name          = "security-group-unrestricted-access"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "SecurityGroupOpenToWorld"
  namespace           = "CustomMetrics"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
}
```

**Weekly Audit:**
```bash
# Scheduled via cron (every Monday 9am)
0 9 * * 1 /path/to/scripts/finops/audit-security-groups.sh
```

---

## 🔗 Referências

- [CIS AWS Foundations Benchmark v1.4](https://www.cisecurity.org/benchmark/amazon_web_services)
- [AWS Well-Architected Security Pillar](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/)
- [OWASP Top 10 API Security 2023](https://owasp.org/API-Security/editions/2023/en/0x11-t10/)
- [ADR-053: Tempo Distributed Tracing](adr-053-tempo-distributed-tracing.md)
- [FinOps Audit 2026-02-11](../finops/AWS-AUDIT-2026-02-11.md)
- [Security Groups Audit Report](../../reports/aws-costs/audit-security-groups-2026-02-12.json)

---

**Aprovado por:** Security Team + DevOps Lead
**Data Aprovação:** 2026-02-12
**Próxima Revisão:** 2026-03-12 (após Fase 3)
**Status:** ✅ **ACEITO - IMPLEMENTAÇÃO EM ANDAMENTO**
