# Home Office Access — Acesso Externo Staging + Prod

**Data**: 2026-03-27
**Status**: CONCLUIDO (parcial — veja pendencias)
**IP Residencial**: 187.34.187.109/32
**IP Escritorio**: 201.28.188.130/32

---

## Mesa Tecnica Virtual — Decisoes

### Participantes
- Security Specialist: WAF rules, IP allowlisting
- Network Specialist: DNS, Route53, ALB, TLS
- DevOps Lead: Terraform IaC, reproducibilidade

### Decisoes

| # | Questao | Decisao |
|---|---------|---------|
| 1 | IP Management | Opcao A: IP Set manual com IPs fixos (office + home). VPN nao disponivel. |
| 2 | WAF Strategy | WebACLs separadas (staging + prod). Mesma politica IP allowlist para ambos. |
| 3 | DNS Strategy | `*.hml.alvocard.com.br` (staging) + `*.prod.alvocard.com.br` (prod). Route53 alias para ALBs. |
| 4 | TLS | ALB termination com ACM wildcard certs. End-to-end mTLS via Linkerd no cluster. |
| 5 | Acesso | IP allowlist via WAF (temporario). VPN recomendada para futuro. |

---

## Auditoria — Estado Encontrado

### WAF
- 2 WebACLs: `waf-k8s-platform-prod-staging` + `waf-k8s-platform-prod-production`
- Default action: BLOCK em ambas
- Rule 0: AllowOfficeIP (priority 0) — IP Set reference
- IP Sets: ambos JA continham 187.34.187.109/32 + 201.28.188.130/32

### Terraform IaC Drift
- `staging/main.tf` L2590: `office_ip_cidrs = ["201.28.188.130/32"]` — DESATUALIZADO
- `prod/waf.tf` L43: `office_ip_cidrs = ["201.28.188.130/32"]` — DESATUALIZADO
- **CORRIGIDO**: Ambos atualizados para incluir `187.34.187.109/32` (home IP)

### DNS — Route53
- **hml.alvocard.com.br**: 15 A records (alias) — todos apontando para ALBs corretos
- **prod.alvocard.com.br**: 5 A records (antes) → 9 records (depois)
  - Criados: sonarqube, grafana, vault, backstage

### ALBs
| ALB | Scheme | WAF | Ingresses |
|-----|--------|-----|-----------|
| k8s-platformstaging | internet-facing | staging WAF | argocd, keycloak, sonarqube, vault, grafana, rabbitmq, harbor |
| k8s-gitlabstaging | internet-facing | staging WAF | gitlab, kas, minio |
| k8s-platformprod | internet-facing | prod WAF | keycloak, argocd, sonarqube |
| k8s-datainternal | internal | nenhum | hatch-api, hatch, vemsoft-etl |
| k8s-backstagestaging | internal | nenhum | backstage (ArgoCD-managed) |
| k8s-sharedinternal | internal | nenhum | ccb-api, ccb-backoffice |
| k8s-platformprodinter | internal | nenhum | harbor-prod |

### ACM Certificates
| Cert | Domain | Status |
|------|--------|--------|
| 3bfc603d | *.hml.alvocard.com.br | ISSUED |
| da133107 | *.prod.alvocard.com.br | ISSUED |
| 6aa5140b | keycloak.staging.internal | ISSUED |
| 342cd0ee | harbor.staging.internal | ISSUED |

---

## Acoes Executadas

### 1. Terraform IaC — Correcao Drift WAF IP
- **staging/main.tf** L2588-2594: `office_ip_cidrs` atualizado para 2 IPs
- **prod/waf.tf** L41-47: `office_ip_cidrs` atualizado para 2 IPs
- **TF apply pendente** — IPs ja estavam no AWS via CLI anterior

### 2. Ingress Patches — Hosts Publicos
- **ArgoCD prod**: Adicionado host `argocd.prod.alvocard.com.br` + HTTPS listener
- **Keycloak prod**: Adicionado host `keycloak.prod.alvocard.com.br`
- **SonarQube prod**: Adicionado host `sonarqube.prod.alvocard.com.br` + HTTPS listener
- **Harbor staging**: Adicionado host `harbor.hml.alvocard.com.br` + HTTPS listener

### 3. DNS Records Criados (Route53)
- `sonarqube.prod.alvocard.com.br` → ALB platform-prod
- `grafana.prod.alvocard.com.br` → ALB platform-prod
- `vault.prod.alvocard.com.br` → ALB platform-prod
- `backstage.prod.alvocard.com.br` → ALB platform-prod
- `backstage.hml.alvocard.com.br` → ALB platform-staging (atualizado de internal para internet-facing)

---

## Resultado Final — Conectividade

### STAGING (*.hml.alvocard.com.br) — 8/9 OK

| App | URL | Status | Notas |
|-----|-----|--------|-------|
| GitLab | gitlab.hml.alvocard.com.br | 302 OK | Redirect para login |
| Keycloak | keycloak.hml.alvocard.com.br | 302 OK | Redirect para login |
| Harbor | harbor.hml.alvocard.com.br | 200 OK | Portal acessivel |
| ArgoCD | argocd.hml.alvocard.com.br | 200 OK | UI acessivel |
| Grafana | grafana.hml.alvocard.com.br | 302 OK | Redirect para login |
| SonarQube | sonarqube.hml.alvocard.com.br | 200 OK | UI acessivel |
| Vault | vault.hml.alvocard.com.br | 307 OK | Redirect para UI |
| RabbitMQ | rabbitmq.hml.alvocard.com.br | 200 OK | Management UI |
| Backstage | backstage.hml.alvocard.com.br | 404 PENDENTE | ALB internal (ArgoCD gerencia Ingress) |

### PRODUCTION (*.prod.alvocard.com.br) — 1/3 OK + 2 app-level

| App | URL | Status | Notas |
|-----|-----|--------|-------|
| Keycloak | keycloak.prod.alvocard.com.br/auth/ | 302 OK | Redirect para login |
| ArgoCD | argocd.prod.alvocard.com.br | 403 APP | WAF permite, app retorna 403 (RBAC/config) |
| SonarQube | sonarqube.prod.alvocard.com.br | 403 APP | WAF permite, app retorna 403 (config) |

---

## Pendencias

### P1 — Backstage Staging (ALB Internal)
- Backstage Ingress gerenciado pelo ArgoCD, nao aceita patch manual
- Solucao: Alterar values.yaml do Helm chart Backstage para usar group `platform-staging` + scheme `internet-facing`
- Arquivo: manifests do ArgoCD Application `backstage`

### P2 — ArgoCD Prod (403)
- ArgoCD prod retorna 403 em todas as rotas (app-level, nao WAF)
- Provavelmente falta `--insecure` flag no argocd-server ou server.rootpath config
- Verificar: `argocd-cm` ConfigMap em `prod-platform-argocd`

### P3 — SonarQube Prod (403)
- SonarQube prod retorna 403 (app-level)
- Pode ser proxy/reverse proxy config ou force authentication
- Verificar: SonarQube admin settings

### P4 — Prod Apps sem Ingress
- grafana.prod, vault.prod, backstage.prod: DNS criado mas sem Ingress no cluster
- Precisa: criar Ingresses nos namespaces prod (prod-observability, prod-security-vault, prod-platform-backstage)

### P5 — Apps em ALBs Internos (Inacessiveis)
- hatch-api, hatch, vemsoft-etl: ALB `data-internal` (internal)
- ccb-api, ccb-backoffice: ALB `shared-internal` (internal)
- Acesso requer VPN ou mudanca de ALB group para internet-facing + WAF

### P6 — TF Apply
- staging/main.tf e prod/waf.tf alterados com novo IP
- Executar `terraform plan` + `terraform apply` para zero drift

---

## Como Revogar Acesso

1. Remover IP `187.34.187.109/32` dos IP Sets AWS:
```bash
# Staging
aws wafv2 update-ip-set --scope REGIONAL \
  --name "k8s-platform-prod-staging-office-allowlist" \
  --id "aa68c9d4-92b1-4fd2-993a-53cef1f5c753" \
  --addresses '["201.28.188.130/32"]' \
  --lock-token "<CURRENT_LOCK_TOKEN>" \
  --profile k8s-platform-prod

# Prod
aws wafv2 update-ip-set --scope REGIONAL \
  --name "k8s-platform-prod-production-office-allowlist" \
  --id "0aa19e3b-b17e-4efd-b24e-82d4f29e355c" \
  --addresses '["201.28.188.130/32"]' \
  --lock-token "<CURRENT_LOCK_TOKEN>" \
  --profile k8s-platform-prod
```

2. Reverter Terraform:
- Remove `"187.34.187.109/32"` de `office_ip_cidrs` em staging/main.tf e prod/waf.tf
- `terraform apply`

---

## Para Outros Desenvolvedores

1. Obter seu IP publico: `curl -s https://api.ipify.org`
2. Adicionar ao IP Set staging (e prod se necessario):
```bash
aws wafv2 get-ip-set --scope REGIONAL --name "k8s-platform-prod-staging-office-allowlist" --id "aa68c9d4-92b1-4fd2-993a-53cef1f5c753" --profile k8s-platform-prod
# Anotar LockToken e Addresses atuais
# Adicionar seu IP ao array Addresses
aws wafv2 update-ip-set --scope REGIONAL \
  --name "k8s-platform-prod-staging-office-allowlist" \
  --id "aa68c9d4-92b1-4fd2-993a-53cef1f5c753" \
  --addresses '["201.28.188.130/32","187.34.187.109/32","SEU_IP/32"]' \
  --lock-token "<LOCK_TOKEN>" \
  --profile k8s-platform-prod
```
3. Atualizar `office_ip_cidrs` no Terraform para manter IaC sincronizado
4. Acessar apps via `https://APP.hml.alvocard.com.br`
