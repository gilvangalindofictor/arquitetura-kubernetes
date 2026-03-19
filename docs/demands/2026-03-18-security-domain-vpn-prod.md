# Segurança, Domínio e Acesso Público — Análise para Produção

**Data:** 2026-03-18
**Autor:** Security & Compliance Specialist — Mesa Técnica
**Cluster:** `k8s-platform-prod` | Conta: `891377105802` | Região: `us-east-1`
**Compliance:** BACEN BCB 85/2021 | BACEN Circular 4.557/2021 | NSA K8s Hardening Guide

---

## Estado Atual (Baseline Auditado — 2026-03-18)

### ALBs Ativos

| ALB | Scheme | Status |
|-----|--------|--------|
| `k8s-platformstaging-00e0ecf3b4` | internet-facing | active |
| `k8s-gitlabstaging-da5a4e8c6d` | internet-facing | active |
| `k8s-stagingp-keycloak-0dbafff841` | internet-facing | active |
| `k8s-backstagestaging-c827d564e5` | **internal** | active |

### Certificado ACM Principal

- **ARN:** `arn:aws:acm:us-east-1:891377105802:certificate/6aa5140b-e1ba-4005-a703-d9f5850bc16a`
- **DomainName:** `keycloak.staging.internal`
- **SANs:** `*.staging.internal`
- **Tipo:** IMPORTED (self-signed/CA interna — NÃO público, sem browser trust)
- **Em uso por:** ALB platform-staging + ALB backstage-staging

### Cert-Manager (Issuers ativos)

| Issuer | Tipo | Status |
|--------|------|--------|
| `selfsigned-issuer` | ClusterIssuer | True |
| `staging-internal-ca-issuer` | ClusterIssuer | True (CA interna) |
| `gitlab-issuer` | Issuer (namespace) | True |

### Certificados emitidos pelo cert-manager

| Namespace | Certificado | Issuer | Status |
|-----------|-------------|--------|--------|
| `harbor-system` | harbor-tls | staging-internal-ca-issuer | True |
| `staging-platform-gitlab` | gitlab-{gitlab,kas,minio}-tls | gitlab-issuer | True |
| `staging-platform-keycloak` | keycloak-tls | staging-internal-ca-issuer | True |

**Conclusão crítica:** Todo o ambiente de staging opera com certificado importado (`*.staging.internal`) emitido por CA interna — sem browser trust público. Não existe certificado ACM DNS-validated público. Não existe hosted zone pública no Route53 (apenas zona privada `staging.internal`).

### Route53

- Única zona: `staging.internal` (privada, associada à VPC `vpc-0b1396a59c417c1f0`)
- 2 registros apenas
- **Sem hosted zone pública**

### WAF

- **WebACL:** `waf-k8s-platform-prod-staging` (`bb9d4557-ca28-4539-b493-b62b2f0d602c`)
- **Associado a:** ALB `k8s-platformstaging-00e0ecf3b4` (platform-staging apenas)
- **DefaultAction:** Allow
- **Regras:**
  - Priority 10: `rate-limit-per-ip` → Block
  - Priority 20: `geo-block-high-risk-countries` → Block (CN, RU, KP)
  - Priority 30: `aws-managed-owasp-common` → Count (não bloqueia ainda)
  - Priority 40: `aws-managed-sqli` → Count (não bloqueia ainda)
  - Priority 50: `aws-managed-known-bad-inputs` → Count (não bloqueia ainda)
- **ALBs SEM WAF:** gitlab-staging, keycloak separado — expostos sem proteção WAF

### Linkerd (Service Mesh mTLS)

- **Control plane:** Running (destination + identity + proxy-injector)
- **Viz:** Running (metrics-api + tap + tap-injector + web)
- **Status fase 2 (injeção de workloads):** EM PROGRESSO conforme ADR-086

### Network Policies

Ativos em: `cert-manager`, `data-services`, `kube-system`, `staging-data-infrastructure`, `staging-observability-monitoring`, `staging-security-vault`

**Sem Network Policies em:** `staging-platform-argocd`, `staging-platform-gitlab`, `staging-platform-keycloak`, `staging-platform-sonarqube`, `harbor-system`

### VPN

- **Nenhum AWS Client VPN configurado** (`ClientVpnEndpoints: []`)
- Acesso ao cluster: via IPs públicos dos ALBs + `windows-hosts.txt` com mapeamento estático de IPs

### External-DNS

- **Não instalado** no cluster

---

---

# DOCUMENTO 1: SETUP DE DOMÍNIO PARA PRODUÇÃO

## 1.1 Domínio Público Necessário

**Domínio da empresa:** `alvocard.com.br`

Conforme ADR-098 (aprovado para staging) e ADR-008 (padrão ACM + Route53), a estratégia para produção é:

| Ambiente | Subdomínio base | Tipo de zona |
|----------|-----------------|--------------|
| Staging | `staging.alvocard.com.br` | Route53 pública (delegada) |
| Produção | `prod.alvocard.com.br` | Route53 pública (delegada) |

**Alternativa (produção direta no apex):** `*.alvocard.com.br` — subdomínios diretos no domínio raiz. Requer controle total sobre `alvocard.com.br` no Route53. Mais elegante para usuários finais, porém migração mais disruptiva.

**Recomendação:** Iniciar com `prod.alvocard.com.br` (subdomínio delegado), mantendo o apex `alvocard.com.br` no registrar atual. Migrar para apex quando a plataforma estiver estável.

## 1.2 Subdomínios por Serviço

### Serviços com ALB internet-facing (exposição pública controlada)

| Serviço | Hostname Prod | Namespace | Criticidade |
|---------|---------------|-----------|-------------|
| Keycloak (SSO/OIDC) | `keycloak.prod.alvocard.com.br` | staging-platform-keycloak | P0 — exige URL pública para federation Entra ID |
| GitLab | `gitlab.prod.alvocard.com.br` | staging-platform-gitlab | P0 |
| GitLab KAS | `kas.prod.alvocard.com.br` | staging-platform-gitlab | P1 |
| Harbor (Registry) | `harbor.prod.alvocard.com.br` | harbor-system | P1 |
| Hatch ETL API | `hatch-api.prod.alvocard.com.br` | prod-data-hatch-etl | P1 |
| Hatch Web UI | `hatch.prod.alvocard.com.br` | prod-data-hatch-etl | P1 |

### Serviços com ALB internal (acesso somente via VPN)

| Serviço | Hostname Prod | Namespace |
|---------|---------------|-----------|
| ArgoCD | `argocd.prod.alvocard.com.br` | staging-platform-argocd |
| Grafana | `grafana.prod.alvocard.com.br` | staging-observability-monitoring |
| Vault | `vault.prod.alvocard.com.br` | staging-security-vault |
| SonarQube | `sonarqube.prod.alvocard.com.br` | staging-platform-sonarqube |
| Backstage | `backstage.prod.alvocard.com.br` | staging-platform-backstage |
| RabbitMQ Management | `rabbitmq.prod.alvocard.com.br` | data-services |

### Estratégia: Wildcard vs Subdomínios individuais

**Decisão: Certificado wildcard `*.prod.alvocard.com.br` (ACM)**

Justificativa:
- 1 certificado ACM cobre todos os subdomínios (zero custo adicional por serviço)
- Compatível com ALB IngressGroup (múltiplos ingresses, 1 ALB, 1 ARN)
- Reduz complexidade operacional vs certificados individuais por serviço
- Alinhado com padrão estabelecido no staging (`*.staging.internal`)

## 1.3 Hosted Zone AWS Route53

### Opção A — Subdomínio delegado (recomendada para início)

```
Registrar de alvocard.com.br
    └── NS delegation → Route53
           └── prod.alvocard.com.br (hosted zone pública)
                   └── *.prod.alvocard.com.br → ALB DNS name (alias A)
```

**Terraform — criar hosted zone:**
```hcl
resource "aws_route53_zone" "prod" {
  name    = "prod.alvocard.com.br"
  comment = "Production platform services — k8s-platform-prod"
  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
    Domain      = "platform"
  }
}
```

Após o `terraform apply`, o Route53 gerará 4 name servers (formato `ns-NNN.awsdns-NN.{co.uk,com,net,org}`). Esses 4 NS devem ser configurados no registrar como NS records para `prod.alvocard.com.br`.

### Registros DNS a criar

```hcl
# Wildcard → ALB internet-facing (serviços públicos)
resource "aws_route53_record" "wildcard_public" {
  zone_id = aws_route53_zone.prod.zone_id
  name    = "*.prod.alvocard.com.br"
  type    = "A"
  alias {
    name                   = aws_lb.platform_prod.dns_name
    zone_id                = aws_lb.platform_prod.zone_id
    evaluate_target_health = true
  }
}

# Subdomínios internos (VPN) → ALB internal
# (registros só resolvem dentro da VPC via split-horizon CoreDNS)
# ArgoCD, Grafana, Vault, SonarQube, Backstage, RabbitMQ
resource "aws_route53_record" "argocd" {
  zone_id = aws_route53_zone.prod.zone_id
  name    = "argocd.prod.alvocard.com.br"
  type    = "A"
  alias {
    name                   = aws_lb.platform_prod_internal.dns_name
    zone_id                = aws_lb.platform_prod_internal.zone_id
    evaluate_target_health = true
  }
}
# ... repetir para grafana, vault, sonarqube, backstage, rabbitmq
```

## 1.4 Certificados TLS — ACM

### Estratégia

**ACM wildcard DNS-validated via Route53** (padrão ADR-008, já aprovado).

**Diferença crítica vs staging:** No staging o certificado é IMPORTED (CA interna, sem browser trust). Em produção DEVE ser ACM público, emitido pela Amazon Trust Services, com browser trust completo.

```hcl
resource "aws_acm_certificate" "prod_wildcard" {
  domain_name               = "*.prod.alvocard.com.br"
  subject_alternative_names = ["prod.alvocard.com.br"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

resource "aws_route53_record" "cert_validation" {
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
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
  timeouts { create = "30m" }
}
```

**Custo:** ~$10/ano (Route53 apenas — ACM é gratuito).
**Renovação:** Automática pelo ACM (60 dias antes da expiração).

## 1.4 CHECKLIST PARA O GESTOR DE DOMÍNIOS

```
CONTEXTO: A empresa possui o domínio alvocard.com.br registrado num registrar externo.
A equipe técnica precisa das seguintes ações do gestor de domínios ANTES de executar
o Terraform de produção.

AÇÃO REQUERIDA — Gestor do Domínio alvocard.com.br:

[ ] AÇÃO 1 — Receber os 4 Name Servers do Route53
      Após execução de: terraform apply (módulo route53-prod)
      A equipe técnica enviará 4 registros no formato:
        ns-XXX.awsdns-XX.com
        ns-XXX.awsdns-XX.net
        ns-XXX.awsdns-XX.org
        ns-XXX.awsdns-XX.co.uk

[ ] AÇÃO 2 — Criar NS delegation no registrar para prod.alvocard.com.br
      No painel do registrar de alvocard.com.br:
      Criar 4 registros do tipo NS para o subdomínio prod.alvocard.com.br
      apontando para os Name Servers recebidos na AÇÃO 1.
      TTL recomendado: 300 segundos (5 minutos).

      IMPORTANTE: NÃO alterar os NS do domínio raiz alvocard.com.br.
      Apenas adicionar NS records para o SUBDOMÍNIO prod.alvocard.com.br.

[ ] AÇÃO 3 — Confirmar propagação DNS (responsabilidade técnica)
      Após a criação dos NS, a equipe técnica validará:
        dig NS prod.alvocard.com.br
      O retorno deve listar os 4 NS do Route53.
      Tempo estimado: 5 a 60 minutos (TTL atual do registrar).

[ ] AÇÃO 4 — (Opcional) Política interna de certificados
      Verificar se a empresa possui política que exige certificados
      emitidos por CA própria (ex: GlobalSign, DigiCert corporativo).
      Se sim: informar a equipe técnica antes do provisionamento ACM.
      Se não: ACM público (Amazon Trust Services) é suficiente e aprovado.

[ ] NÃO NECESSÁRIO — registros A/CNAME no registrar
      A equipe técnica cria todos os registros DNS dentro do Route53.
      O registrar só precisa delegar o subdomínio via NS records.

[ ] NÃO NECESSÁRIO — certificado wildcard emitido pelo registrar
      ACM (AWS Certificate Manager) emite o wildcard *.prod.alvocard.com.br
      gratuitamente com renovação automática. Certificado comercial é desnecessário.

PRAZO ESTIMADO PARA GESTOR: 30 minutos (apenas criar 4 registros NS).
IMPACTO SE NÃO FEITO: O Terraform de certificados ACM ficará aguardando
  validação DNS por até 30 min e então falhará com timeout.
```

---

---

# DOCUMENTO 2: SETUP VPN

## 2.1 Estado Atual

**VPN:** Não existe (`ClientVpnEndpoints: []` — confirmado via AWS CLI em 2026-03-18).

**Como o acesso ao cluster é feito hoje (staging):**
- Arquivo `access/windows-hosts.txt` com IPs fixos dos ALBs mapeados para hostnames `*.staging.internal`
- IPs dos ALBs são IPs públicos dos ALBs internet-facing (verificados em 2026-03-17)
- Backstage: ALB internal — acesso via `kubectl port-forward` ou IP privado (requer estar na VPC)
- Sem controle de acesso por IP nos ALBs principais (exceto WAF no platform-staging)

**Risco atual:** ALBs internet-facing `gitlab-staging` e `k8s-stagingp-keycloak-0dbafff841` não têm WAF — acessíveis por qualquer IP da internet.

**Roadmap de VPN (ADR-098):**
- Cenário A (atual): WAF IP whitelist — sem VPN
- Cenário B (Q2/Q3 2026): VPN híbrida — equipe técnica via VPN, serviços públicos via ALB
- Cenário C (futuro): VPN completa — ALBs internos, tudo via VPN

## 2.2 Proposta para Produção — AWS Client VPN + Keycloak OIDC

Para produção, a VPN é obrigatória para serviços de plataforma interna (ArgoCD, Grafana, Vault, SonarQube, Backstage, RabbitMQ).

### Arquitetura

```
Engenheiro (laptop)
     │
     │  AWS Client VPN (OpenVPN)
     │  Autenticação: Keycloak OIDC
     │  MFA: TOTP (Keycloak) ou delegado Entra ID
     ▼
┌─────────────────────────────────────┐
│  Client VPN Endpoint               │
│  CIDR: 10.200.0.0/16 (VPN clients) │
│  Split-tunnel: ON                   │
│  DNS: 10.0.0.2 (Route53 Resolver)  │
└─────────────────┬───────────────────┘
                  │ (apenas tráfego 10.0.0.0/16)
                  ▼
┌─────────────────────────────────────┐
│  VPC: vpc-0b1396a59c417c1f0         │
│  CIDR: 10.0.0.0/16                  │
│                                     │
│  ALB internal → ArgoCD, Grafana,    │
│                 Vault, SonarQube,   │
│                 Backstage, RabbitMQ │
│                                     │
│  EKS nodes, RDS, Redis              │
└─────────────────────────────────────┘
```

### Componentes necessários

| Componente | Detalhe |
|------------|---------|
| Client VPN Endpoint | 1 endpoint em 2 AZs (us-east-1a, us-east-1b) |
| Autenticação | Certificado mútuo (TLS) + SAML/OIDC Keycloak |
| CIDR VPN clients | `10.200.0.0/16` (não conflita com VPC 10.0.0.0/16) |
| Split-tunnel | ON — só roteia 10.0.0.0/16 pela VPN |
| Associação à VPC | Subnets privadas (us-east-1a + us-east-1b) |

### Integração Keycloak OIDC

O AWS Client VPN suporta autenticação via SAML 2.0 federado ao IAM Identity Center, que por sua vez pode federar com Keycloak. O fluxo:

```
Usuário → AWS VPN Client → SAML → IAM Identity Center → Keycloak OIDC → Entra ID
```

**Pré-requisito:** Keycloak deve ter URL pública (`keycloak.prod.alvocard.com.br`) antes de configurar o Client VPN com SAML. Isso é viabilizado pelo Documento 1 (domínio público).

### Certificados para Client VPN

O Client VPN requer:
1. Certificado de CA do servidor (carregado no ACM) — pode ser o mesmo ACM wildcard
2. Certificado de CA do cliente (para autenticação mútua TLS) — gerado separadamente

```bash
# Geração de PKI para Client VPN (usando easy-rsa ou openssl)
# CA root para VPN
openssl genrsa -out vpn-ca.key 2048
openssl req -x509 -new -nodes -key vpn-ca.key -sha256 -days 3650 \
  -out vpn-ca.crt -subj "/CN=vpn-ca.prod.alvocard.com.br"

# Upload para ACM
aws acm import-certificate --profile k8s-platform-prod --region us-east-1 \
  --certificate fileb://vpn-ca.crt \
  --private-key fileb://vpn-ca.key
```

**Módulo Terraform necessário:** `modules/client-vpn/` (a criar — não existe no repositório atual).

## 2.3 Plano de Implementação VPN

### Pré-requisitos

| Item | Status | Dependência |
|------|--------|-------------|
| Domínio público `prod.alvocard.com.br` | Pendente | Documento 1 completo |
| Keycloak com URL pública | Pendente | Domínio + ACM cert |
| Certificates VPN CA | Pendente | Não existe |
| IAM Identity Center habilitado | Verificar | AWS Organizations |

### Sequência de criação (Terraform)

```
Fase 1: Domínio + ACM (Documento 1)
    ↓
Fase 2: ALBs internal prod (ArgoCD, Grafana, Vault, SonarQube, Backstage, RabbitMQ)
    ↓
Fase 3: Certificados VPN CA → upload ACM
    ↓
Fase 4: Client VPN Endpoint (Terraform module client-vpn)
    ↓
Fase 5: VPN → VPC subnet associations (2 AZs)
    ↓
Fase 6: Authorization rules (grupo platform-admins → 10.0.0.0/16)
    ↓
Fase 7: Keycloak realm configuration (SAML/OIDC para VPN)
    ↓
Fase 8: Distribuição do arquivo .ovpn para engenheiros
```

### Módulo Terraform `modules/client-vpn/` (esqueleto)

```hcl
resource "aws_ec2_client_vpn_endpoint" "prod" {
  description            = "prod platform VPN — Keycloak OIDC auth"
  server_certificate_arn = aws_acm_certificate_validation.prod_wildcard.certificate_arn
  client_cidr_block      = "10.200.0.0/16"
  split_tunnel           = true
  transport_protocol     = "udp"
  vpc_id                 = var.vpc_id
  security_group_ids     = [aws_security_group.client_vpn.id]

  authentication_options {
    type              = "certificate-authentication"
    root_certificate_chain_arn = aws_acm_certificate.vpn_ca.arn
  }

  connection_log_options {
    enabled               = true
    cloudwatch_log_group  = aws_cloudwatch_log_group.vpn.name
    cloudwatch_log_stream = aws_cloudwatch_log_stream.vpn.name
  }

  dns_servers = ["10.0.0.2"]  # Route53 Resolver na VPC

  tags = {
    Name        = "prod-platform-vpn"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

resource "aws_ec2_client_vpn_network_association" "prod" {
  for_each               = toset(var.private_subnet_ids)
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.prod.id
  subnet_id              = each.value
}

resource "aws_ec2_client_vpn_authorization_rule" "platform_admins" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.prod.id
  target_network_cidr    = "10.0.0.0/16"
  authorize_all_groups   = false
  access_group_id        = var.keycloak_platform_admins_group_id
  description            = "platform-admins group → VPC full access"
}
```

**Custo estimado:**
- Client VPN Endpoint: $0.10/hora = ~$73/mês
- Client VPN associations (2 AZs): $0.10/hora × 2 = ~$146/mês
- Client VPN connections: $0.05/hora/conexão simultânea
- **Total base:** ~$220/mês + conexões ativas

### Teste de acesso pós-configuração

```bash
# 1. Conectar via VPN (arquivo .ovpn distribuído)
# 2. Verificar resolução DNS via Route53 Resolver
nslookup argocd.prod.alvocard.com.br
# Deve retornar IP privado do ALB internal (10.x.x.x)

# 3. Verificar acesso ao ArgoCD
curl -v https://argocd.prod.alvocard.com.br/healthz

# 4. Verificar acesso ao Vault
curl https://vault.prod.alvocard.com.br/v1/sys/health
```

---

---

# DOCUMENTO 3: ACESSO PÚBLICO PARA PRODUÇÃO

## 3.1 ALB Internet-facing

### Estado atual no cluster

| ALB | WAF | Serviços |
|-----|-----|---------|
| `k8s-platformstaging-00e0ecf3b4` | **Sim** (waf-k8s-platform-prod-staging) | keycloak, harbor, grafana, argocd, vault, sonarqube, rabbitmq, hatch-{api,web} |
| `k8s-gitlabstaging-da5a4e8c6d` | **Não** — exposição sem proteção | gitlab, kas, minio |
| `k8s-stagingp-keycloak-0dbafff841` | **Não** — exposição sem proteção | keycloak (ALB separado) |
| `k8s-backstagestaging-c827d564e5` | N/A (internal) | backstage |

**GAP de segurança crítico:** `k8s-gitlabstaging-da5a4e8c6d` e `k8s-stagingp-keycloak-0dbafff841` estão internet-facing sem WAF.

### Para produção: estrutura de ALBs recomendada

```
ALB prod-public (internet-facing + WAF)
  └── IngressGroup: prod-platform-public
      ├── keycloak.prod.alvocard.com.br      (Keycloak — necessário público para OIDC)
      ├── gitlab.prod.alvocard.com.br        (GitLab — CI/CD público)
      ├── kas.prod.alvocard.com.br           (GitLab KAS — agentes externos)
      ├── harbor.prod.alvocard.com.br        (Harbor — registry CI/CD)
      ├── hatch-api.prod.alvocard.com.br     (Hatch ETL API — uso externo)
      └── hatch.prod.alvocard.com.br         (Hatch Web UI)

ALB prod-internal (internal — apenas via VPN)
  └── IngressGroup: prod-platform-internal
      ├── argocd.prod.alvocard.com.br        (ArgoCD — GitOps)
      ├── grafana.prod.alvocard.com.br       (Grafana — dashboards)
      ├── vault.prod.alvocard.com.br         (Vault — secrets)
      ├── sonarqube.prod.alvocard.com.br     (SonarQube — qualidade)
      ├── backstage.prod.alvocard.com.br     (Backstage — IDP)
      └── rabbitmq.prod.alvocard.com.br      (RabbitMQ management)
```

### Anotações Kubernetes necessárias (ALB público)

```yaml
metadata:
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/group.name: prod-platform-public
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/certificate-arn: "<ARN do ACM wildcard prod>"
    alb.ingress.kubernetes.io/ssl-policy: "ELBSecurityPolicy-TLS13-1-2-2021-06"
    alb.ingress.kubernetes.io/wafv2-acl-arn: "<ARN do WAF prod>"
    alb.ingress.kubernetes.io/backend-protocol: HTTP
```

### Anotações Kubernetes necessárias (ALB internal)

```yaml
metadata:
  annotations:
    alb.ingress.kubernetes.io/scheme: internal
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/group.name: prod-platform-internal
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/certificate-arn: "<ARN do ACM wildcard prod>"
    alb.ingress.kubernetes.io/ssl-policy: "ELBSecurityPolicy-TLS13-1-2-2021-06"
    # Sem WAF no ALB interno — proteção por Security Group + VPN
    alb.ingress.kubernetes.io/backend-protocol: HTTP
```

## 3.2 WAF para Produção

### Regras existentes (staging) — estado atual

| Priority | Regra | Action | Observação |
|----------|-------|--------|------------|
| 10 | `rate-limit-per-ip` | Block | 1000 req/5min/IP — funcional |
| 20 | `geo-block-high-risk-countries` | Block | CN, RU, KP — funcional |
| 30 | `aws-managed-owasp-common` | **Count** (não bloqueia) | Precisa mudar para Block |
| 40 | `aws-managed-sqli` | **Count** (não bloqueia) | Precisa mudar para Block |
| 50 | `aws-managed-known-bad-inputs` | **Count** (não bloqueia) | Precisa mudar para Block |

**Ação imediata necessária no staging:** Mudar regras 30/40/50 de `Count` para `Block`.

### Regras WAF recomendadas para produção (novo WebACL)

```hcl
resource "aws_wafv2_web_acl" "prod" {
  name  = "waf-k8s-platform-prod"
  scope = "REGIONAL"

  default_action { allow {} }

  # P10: Rate limiting
  rule {
    name     = "rate-limit-per-ip"
    priority = 10
    action { block {} }
    statement {
      rate_based_statement {
        limit              = 2000  # Prod: mais permissivo que staging (1000)
        aggregate_key_type = "IP"
      }
    }
    visibility_config { ... }
  }

  # P20: Geo block
  rule {
    name     = "geo-block-high-risk-countries"
    priority = 20
    action { block {} }
    statement {
      geo_match_statement {
        country_codes = ["CN", "RU", "KP", "IR", "BY"]  # + Belarus e Iran em prod
      }
    }
    visibility_config { ... }
  }

  # P30: OWASP — BLOCK em produção (vs Count no staging)
  rule {
    name     = "aws-managed-owasp-common"
    priority = 30
    override_action { none {} }  # Block (managed rule default)
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config { ... }
  }

  # P40: SQLi — BLOCK em produção
  rule {
    name     = "aws-managed-sqli"
    priority = 40
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config { ... }
  }

  # P50: Known bad inputs — BLOCK em produção
  rule {
    name     = "aws-managed-known-bad-inputs"
    priority = 50
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config { ... }
  }

  # P60 (NOVO para prod): AWS Managed Rules Bot Control
  rule {
    name     = "aws-managed-bot-control"
    priority = 60
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
    visibility_config { ... }
  }
}
```

### Regras adicionais recomendadas para prod vs staging

| Regra | Staging | Produção | Motivo |
|-------|---------|----------|--------|
| OWASP Common | Count | **Block** | Exposição real a ameaças |
| SQLi | Count | **Block** | RDS com dados financeiros |
| Known Bad Inputs | Count | **Block** | Log4Shell/RCE prevention |
| Bot Control | Não existe | **Adicionar** | Proteção contra scraping |
| Países bloqueados | CN, RU, KP | CN, RU, KP, IR, BY | Conformidade BACEN |
| Rate limit | 1000/5min | 2000/5min | Ajustar para tráfego real |

**Custo WAF prod estimado:** ~R$ 80-120/mês (WebACL + regras + S3 logs 90d)

## 3.3 Ingresses Públicos por Serviço

| Serviço | Hostname Prod | Certificado | WAF | Observações |
|---------|---------------|-------------|-----|-------------|
| Keycloak | `keycloak.prod.alvocard.com.br` | ACM wildcard | Sim | OIDC endpoint público obrigatório para Entra ID federation |
| GitLab | `gitlab.prod.alvocard.com.br` | ACM wildcard | Sim | SSH git via NLB separado (porta 22) |
| GitLab KAS | `kas.prod.alvocard.com.br` | ACM wildcard | Sim | WebSocket — verificar WAF timeout |
| Harbor | `harbor.prod.alvocard.com.br` | ACM wildcard | Sim | OCI registry — ajustar rate limit para push/pull |
| Hatch ETL API | `hatch-api.prod.alvocard.com.br` | ACM wildcard | Sim | API pública com auth via Keycloak |
| Hatch Web UI | `hatch.prod.alvocard.com.br` | ACM wildcard | Sim | SPA estática |

**Nota Harbor:** A anotação WAF no ALB bloqueia o WAF para TODAS as rotas do IngressGroup. Para Harbor, monitorar falsos positivos no upload de imagens grandes (regra OWASP pode bloquear payloads multipart). Usar `rule_action_override` se necessário.

**Nota GitLab KAS:** WebSocket precisa de `alb.ingress.kubernetes.io/target-group-attributes: stickiness.enabled=true,stickiness.lb_cookie.duration_seconds=86400` para sessões persistentes.

## 3.4 Serviços que NÃO devem ser públicos

### Serviços — somente via VPN (ALB internal)

| Serviço | Motivo | Risco se público |
|---------|--------|-----------------|
| **ArgoCD** | Controle de deployments do cluster — acesso a todos os manifests | Execução remota de código via sync |
| **Grafana** | Métricas de infraestrutura, capacidade, erros | Intelligence gathering sobre arquitetura |
| **Vault** | Secrets de toda a plataforma | Vazamento de credenciais críticas (P0) |
| **SonarQube** | Código fonte, análises de segurança | Exposição de vulnerabilidades conhecidas |
| **Backstage** | Catálogo de serviços, templates de scaffolding | Scaffolding não autorizado, SSRF via templates |
| **RabbitMQ Management** | Mensagens em trânsito, configuração de filas | Injeção de mensagens maliciosas |
| **Prometheus** | Métricas detalhadas de infraestrutura | Intelligence gathering |
| **AlertManager** | Configurações de alertas e integrações | SSRF via webhooks |

### Network Policies necessárias para produção

**Situação atual:** Network Policies implementadas em `cert-manager`, `data-services`, `kube-system`, `staging-security-vault`. Faltam políticas nos namespaces de plataforma mais críticos.

**GAPs de Network Policy (alto risco):**

```
staging-platform-argocd    → SEM NetworkPolicy
staging-platform-gitlab     → SEM NetworkPolicy
staging-platform-keycloak   → SEM NetworkPolicy
staging-platform-sonarqube  → SEM NetworkPolicy
harbor-system               → SEM NetworkPolicy
```

**Prioridade de implementação (ordem de criticidade):**

1. `staging-platform-keycloak` — SSO de toda a plataforma (P0)
2. `staging-security-vault` — já tem políticas, revisar completude
3. `harbor-system` — registry contém imagens de produção
4. `staging-platform-argocd` — acesso ao K8s API server
5. `staging-platform-gitlab` — código fonte + CI/CD secrets
6. `staging-platform-sonarqube` — análises de segurança

**Referência:** ADR-070 define padrão de 20 políticas para Marco 4 (argocd, sonarqube, keycloak, gitlab). Arquivos em `domains/security/network-policies/marco4/`.

**Ação requerida:** Executar `kubectl apply -f domains/security/network-policies/marco4/` em modo audit (annotation `policy.cilium.io/audit-mode: "true"`) antes de enforcement.

---

---

## Resumo Executivo — GAPs de Segurança para Produção

### P0 — Bloqueadores (devem ser resolvidos antes do go-live de produção)

| GAP | Descrição | Impacto | Ação |
|-----|-----------|---------|------|
| **GAP-SEC-01** | Certificado ACM prod não existe (IMPORTED auto-assinado no staging) | Sem browser trust em produção | Provisionar ACM wildcard `*.prod.alvocard.com.br` |
| **GAP-SEC-02** | Sem hosted zone pública Route53 para produção | Domínios prod não resolvem | Criar `prod.alvocard.com.br` + NS delegation |
| **GAP-SEC-03** | ~~WAF regras 30/40/50 em mode Count~~ **RESOLVIDO 2026-03-19** — Todas regras em Block + 3 ALBs internet-facing associados (GitLab + Keycloak + platform). Zero drift TF. | ~~OWASP/SQLi/Log4Shell nao protegidos~~ RESOLVIDO | ~~Mudar para Block~~ FEITO |
| **GAP-SEC-04** | ~~ALB gitlab-staging e keycloak sem WAF~~ **RESOLVIDO 2026-03-19** — 3/3 ALBs internet-facing protegidos pelo WAF. | ~~2 ALBs desprotegidos~~ RESOLVIDO | ~~Associar WAF~~ FEITO |

### P1 — Alta prioridade (resolver no sprint seguinte)

| GAP | Descrição | Ação |
|-----|-----------|------|
| **GAP-SEC-05** | Sem VPN — acesso interno só via port-forward | Provisionar AWS Client VPN (módulo Terraform) |
| **GAP-SEC-06** | ~~Network Policies ausentes em 5 namespaces criticos~~ **RESOLVIDO 2026-03-19** — 24 policies em 5 namespaces (audit mode, ADR-070). Harbor 7 policies criadas. | ~~Aplicar politicas ADR-070~~ FEITO (audit mode) |
| **GAP-SEC-07** | Linkerd Phase 2 incompleta — namespaces sem mTLS | Completar injeção via annotate-namespaces.sh |
| **GAP-SEC-08** | External-DNS não instalado — DNS manual | Instalar ExternalDNS para automação Route53 |

### P2 — Médio prazo

| GAP | Descrição | Ação |
|-----|-----------|------|
| **GAP-SEC-09** | Entra ID Federation não implementada | Executar ADR-095 Fase 1 (após Keycloak com URL pública) |
| **GAP-SEC-10** | Bot Control WAF não configurado | Adicionar regra AWSManagedRulesBotControlRuleSet |
| **GAP-SEC-11** | Session lifetime Keycloak nao reduzida (risco R-100) | SSO idle 15min, max 4h (ADR-095) |

### P1-REGISTRY — Container Registry Security (detectados 2026-03-19 — Mesa Tecnica Docker Hub Rate Limit)

| GAP | Descricao | Acao |
|-----|-----------|------|
| **GAP-SEC-REGISTRY-01** | ECR scan_on_push nao habilitado nos repositorios ECR mirror | Habilitar `image_scanning_configuration { scan_on_push = true }` em todos os ECR repos |
| **GAP-SEC-REGISTRY-02** | Sem Kyverno policy para restringir registries permitidos | Criar ClusterPolicy `restrict-image-registries` — permitir apenas ECR + Harbor (bloquear Docker Hub direto) |
| **GAP-SEC-REGISTRY-03** | Imagens sem digest pinning — tags mutaveis em uso | Migrar de tag para digest (`@sha256:...`) em todos os deployments prod |
| **GAP-SEC-REGISTRY-04** | Sem image signing (Cosign/Notation) | Implementar Cosign signing no CI/CD + Kyverno policy `verify-image-signature` |

**Contexto:** Mesa tecnica Docker Hub rate limit (2026-03-19) identificou 48 pods ImagePullBackOff, 30 imagens Docker Hub unicas. Harbor Proxy Cache inviavel para kubelet (containerd no host != pod network). Solucao imediata: ECR mirror para SonarQube. Solucao longo prazo: ECR Pull-Through Cache para todas as imagens Docker Hub.

---

## Referências de Arquitetura

- **ADR-008** — TLS Strategy for ALB Ingresses (padrão ACM + Route53)
- **ADR-046** — Keycloak SSO Strategy (OIDC clients, HA)
- **ADR-070** — Network Policies Marco 4 (arquivos em `domains/security/network-policies/marco4/`)
- **ADR-086** — Linkerd Service Mesh mTLS (namespace injection roadmap)
- **ADR-095** — Entra ID Identity Federation (Keycloak OIDC brokering)
- **ADR-098** — DNS e Controle de Acesso Staging (alvocard.com.br strategy)
- **ADR-099** — WAF Strategy iPaaS (regras existentes, Terraform module)
- **Módulo WAF Terraform:** `platform-provisioning/aws/kubernetes/terraform/modules/waf/`
- **Network Policies Marco 4:** `domains/security/network-policies/marco4/`
- **Linkerd Namespace Scripts:** `domains/service-mesh/infra/linkerd/namespace-annotations/`
