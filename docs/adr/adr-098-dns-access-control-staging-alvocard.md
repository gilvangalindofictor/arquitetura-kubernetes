# ADR-098 — DNS e Controle de Acesso Staging: alvocard.com.br

## Data
2026-03-03

## Status
Proposto 📋

## Contexto

O ambiente de staging da plataforma EKS opera com domínios fictícios `*.staging.internal` resolvidos exclusivamente via CoreDNS split-horizon. Todos os serviços usam HTTP-only (porta 80) em ALBs internet-facing. A empresa não possui VPN atualmente.

**Problemas Identificados:**

1. **DNS não externo:** Domínios `*.staging.internal` não resolvem publicamente — acesso ao staging requer estar na mesma rede do cluster ou usar kubectl port-forward. Isso bloqueia testes realistas e colaboração remota.

2. **HTTP expõe credenciais:** Tokens OAuth2, cookies de sessão e credenciais GitLab trafegam em texto claro. Isso viola requisitos mínimos de segurança mesmo em ambiente staging.

3. **Sem controle de acesso por IP:** ALBs internet-facing aceitam conexões de qualquer origem. Qualquer pessoa com o DNS name do ALB pode tentar ataques de força bruta ou exploração.

4. **OIDC federation bloqueada:** URLs fictícias (`http://keycloak.staging.internal/...`) impedem configuração real de federation com Entra ID (Microsoft) e outros IdPs corporativos, pois IdPs externos precisam de URLs publicamente resolvíveis para OIDC discovery.

5. **Incompatibilidade GitLab CI/CD:** Runners externos ao cluster não conseguem resolver `*.staging.internal`, bloqueando pipelines que precisam de callbacks para o GitLab.

**Contexto Organizacional:**
- Equipe pequena (1-3 pessoas), sem times de redes dedicados
- IPs fixos disponíveis para a equipe técnica atual
- Sem VPN hoje — roadmap prevê avaliação de VPN em 2026-Q2/Q3
- Domínio `alvocard.com.br` é propriedade da empresa

## Problema

Como expor serviços de staging com DNS real, HTTPS, e controle de acesso progressivo, considerando:
- Ausência atual de VPN
- Custo incremental mínimo (~$1/mês)
- Compatibilidade com cenários futuros (VPN híbrida → VPN completa)
- Não bloquear fluxos de OIDC federation com Entra ID e Keycloak

## Decisão

**Implementar Route53 zone delegation + ACM wildcard + WAF IP whitelist para `*.staging.alvocard.com.br`, com cenários progressivos de segurança conforme maturidade de acesso da empresa.**

### Arquitetura da Solução

```
Internet
    │
    ├─ IPs autorizados ──────────────────────────────────────────────┐
    │                                                                 │
    │  ┌─────────────────────────────────────────────────────────┐   │
    │  │  Route53: staging.alvocard.com.br                       │   │
    │  │  - A-alias: *.staging.alvocard.com.br → ALB DNS name   │   │
    │  └───────────────────────┬─────────────────────────────────┘   │
    │                          │                                      │
    │  ┌───────────────────────▼─────────────────────────────────┐   │
    │  │  WAF WebACL: IP Whitelist (Priority 5)                  │◄──┘
    │  │  default_action: block                                  │
    │  └───────────────────────┬─────────────────────────────────┘
    │                          │ (apenas IPs autorizados passam)
    │  ┌───────────────────────▼─────────────────────────────────┐
    │  │  ALB internet-facing                                     │
    │  │  HTTPS 443 ← ACM *.staging.alvocard.com.br              │
    │  │  HTTP 80 → redirect 443                                  │
    │  └───────────────────────┬─────────────────────────────────┘
    │                          │
    │  ┌───────────────────────▼─────────────────────────────────┐
    │  │  Kubernetes Ingresses                                    │
    │  │  gitlab / harbor / keycloak / grafana / argocd          │
    │  └─────────────────────────────────────────────────────────┘
    │
    └─ IPs não autorizados ──► WAF 403 Forbidden
```

### Componentes da Decisão

| Componente | Tecnologia | Justificativa |
|------------|------------|---------------|
| **DNS** | Route53 Hosted Zone `staging.alvocard.com.br` | Delegação de subdomínio (sem custo de novo domínio), integração nativa ACM |
| **Certificado** | ACM wildcard `*.staging.alvocard.com.br` | Gratuito, auto-renewal, browser trust, 1 cert para todos os serviços |
| **Controle de acesso** | WAF WebACL IP Whitelist (Priority 5) | Toggle via Terraform variable, auditável via CloudWatch, sem overhead de VPN |
| **OIDC URLs** | Terraform locals centralizados | Single point of truth — alterar 1 variável propaga para todos os serviços |
| **CoreDNS** | Split-horizon atualizado | Resolução interna via ClusterIP (evita roundtrip externo, latência zero) |
| **Ingress** | Annotations `certificate-arn` + `wafv2-acl-arn` | Integração nativa ALB Controller, sem sync tools adicionais |

### Cenários Progressivos

**Cenário A — Imediato (sem VPN):**
- WAF IP Whitelist + ACM + OIDC real
- Nível de segurança: ⭐⭐⭐

**Cenário B — Transição (VPN Híbrida):**
- VPN para equipe + ALB público apenas para Keycloak (federation Entra ID)
- Nível de segurança: ⭐⭐⭐⭐

**Cenário C — Futuro (VPN Completa):**
- Tudo via VPN, ALBs internos, Route53 Private Hosted Zone
- Nível de segurança: ⭐⭐⭐⭐⭐

## Alternativas Consideradas

### Alternativa 1: VPN-first (AWS Client VPN)
**Rejeitada:**
- Custo: ~$72/mês (Client VPN Endpoint + VPC association + horas de conexão)
- Overhead de configuração para equipe atual (1-3 pessoas)
- Bloqueia OIDC federation externa que requer URLs publicamente resolvíveis
- **Decisão:** Custo e complexidade não justificados para equipe atual — reservado para Cenário C futuro

### Alternativa 2: Cloudflare Tunnels (vendor externo)
**Rejeitada:**
- Dependência de vendor externo (Cloudflare) para DNS crítico da empresa
- Complexidade de integração com ACM/ALB existentes
- Custo adicional (Cloudflare Teams)
- Viola princípio de infraestrutura gerenciada inteiramente na AWS
- **Decisão:** Vendor lock-in externo inaceitável — manter stack AWS nativo

### Alternativa 3: Security Groups com CIDR restriction
**Rejeitada:**
- Security Groups no ALB não funcionam para ALBs internet-facing compartilhados (IngressGroup)
- ALB é provisionado pelo AWS Load Balancer Controller — Security Groups são gerenciados automaticamente
- Mudanças manuais em Security Groups seriam sobrescritas pelo controller
- **Decisão:** Incompatível com arquitetura ALB Controller existente

### Alternativa 4: WAF IP Whitelist + ACM + Route53 (ESCOLHIDA)
**Aceita:**
- Custo incremental mínimo (~$1/mês)
- Toggle de IPs via Terraform variable (atualização em minutos)
- Compatível com Cenários B e C (WAF pode ser mantida ou removida progressivamente)
- Integração nativa com stack AWS existente (ALB Controller, ACM, Route53)
- OIDC federation funciona (URLs públicas resolvíveis)
- Auditável via CloudWatch Logs + WAF sampled requests

### Alternativa 5: HTTP-only com básico auth no Ingress
**Rejeitada:**
- Não criptografa tráfego — credenciais expostas em texto claro
- Incompatível com OIDC (OAuth2 requer HTTPS para redirect_uri)
- Não fornece controle de acesso robusto (basic auth bypassável)
- **Decisão:** Inaceitável — violação de requisitos de segurança básicos

## Consequências

### Positivas ✅

1. **Segurança imediata:** HTTPS elimina exposição de credenciais em HTTP; WAF bloqueia origens não autorizadas
2. **OIDC real:** URLs públicas habilitam federation com Entra ID sem workarounds
3. **Acesso remoto:** Equipe pode acessar staging de qualquer IP autorizado, sem VPN
4. **Custo mínimo:** ~$1/mês incremental (Route53 apenas — ACM gratuito)
5. **Progressividade:** Cenário A funciona hoje; B e C são extensões sem refatoração
6. **IaC completo:** Terraform gerencia Route53 + ACM + WAF — zero drift, auditável
7. **Toggle de IPs:** Adicionar/remover IP autorizado = atualizar variável + terraform apply (< 5 min)

### Negativas ⚠️

1. **Custo recorrente:** $6-10/ano Route53 (Route53 Hosted Zone + queries)
2. **IP fixo obrigatório (Cenário A):** Membros da equipe com IP dinâmico precisam de solução alternativa (VPN ou mobile hotspot com IP conhecido)
3. **NS delegation manual:** Requer acesso ao registrador de `alvocard.com.br` para configurar NS delegation — etapa fora do Terraform
4. **Keycloak migration:** Atualização de redirect URIs em todos os clients OIDC é etapa crítica que requer coordenação

### Riscos

🔴 **IP whitelist falha (IP muda):** Time é bloqueado do staging
🟢 **Mitigação:** Terraform variable list — atualização e re-apply em < 5 minutos; manter ao menos 2 IPs de backup (escritório + VPN pessoal)

🔴 **NS delegation incorreta:** ACM validation falha, certificado não é emitido
🟢 **Mitigação:** Validar NS delegation com `dig NS staging.alvocard.com.br` antes de prosseguir; timeout de 30 min no Terraform

🔴 **Keycloak redirect_uri mismatch:** Todos os clientes OIDC quebram após migração
🟢 **Mitigação:** Atualizar todos os Keycloak clients (Terraform IaC) ANTES de trocar URLs; testar em janela de manutenção

🟡 **CoreDNS split-horizon loop:** Pods do cluster resolvem externamente ao invés de internamente
🟢 **Mitigação:** Testar resolução interna com `nslookup` antes de merge; fallthrough configurado corretamente

## Métricas de Sucesso

- ✅ `dig NS staging.alvocard.com.br` retorna NS records do Route53
- ✅ `curl -vI https://gitlab.staging.alvocard.com.br` retorna certificado ACM válido
- ✅ HTTP → HTTPS redirect funciona (301)
- ✅ OIDC discovery: `curl https://keycloak.staging.alvocard.com.br/realms/staging/.well-known/openid-configuration` retorna `issuer: https://...`
- ✅ WAF bloqueia (403) requisições de IPs não autorizados
- ✅ WAF permite acesso de IPs autorizados
- ✅ CoreDNS resolve `gitlab.staging.alvocard.com.br` para ClusterIP (sem roundtrip externo)

## Referências

- **ADR-008:** TLS Strategy for ALB Ingresses — pattern ACM + Route53 (aprovado 2026-01-28)
- **ADR-046:** Keycloak SSO Strategy — requer HTTPS para OIDC redirect_uri
- **ADR-047:** Estrutura Corporativa de Domínios — organização `staging.alvocard.com.br`
- **Demanda:** `docs/demands/2026-03-03-dns-access-control-alvocard.md`
- **GOV-005:** Keycloak SSO Governance
- **AWS Docs:** [WAF IP Sets](https://docs.aws.amazon.com/waf/latest/developerguide/waf-ip-set-managing.html)
- **AWS Docs:** [ACM DNS Validation](https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html)
- **AWS Docs:** [Route53 Subdomain Delegation](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/CreatingNewSubdomain.html)

## Aprovações

- [ ] gilvangalindo (solicitante)
- [ ] Architect Guardian
- [ ] Security Review (WAF rules)

## Próximos Passos

1. 📋 Aprovar ADR-098
2. 📋 Executar Cenário A — Step 1: `terraform apply` (Route53 + ACM)
3. 📋 Configurar NS delegation no registrador `alvocard.com.br`
4. 📋 Executar Cenário A — Steps 2-7 (WAF → Keycloak → Ingresses → CoreDNS → OIDC → DNS records)
5. 📋 Validação completa (dig + curl + OIDC flow + WAF block test)
6. 📋 Avaliar VPN em 2026-Q2/Q3 para transição Cenário A → B
