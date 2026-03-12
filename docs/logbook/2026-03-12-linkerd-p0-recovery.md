# Logbook — Linkerd P0 Recovery (2026-03-12)

**Data:** 2026-03-12
**Duração do incidente:** ~15:00 BRT (detecção) → ~19:00 BRT (resolução)
**Severidade:** P0 — cascata completa (GitLab, Vault alerts, RDS alerts)
**Cluster:** k8s-platform-prod (EKS 1.34, us-east-1)
**Responsável:** Platform Team

---

## 1. Contexto

O cluster estava operacional até ~15:00 BRT quando o audit do estado de saúde revelou 58 alertas
firing (11 CRITICAL). A causa raiz era a ausência do secret `linkerd-trust-anchor` no namespace
`linkerd`, provocando uma cascata de CrashLoop em todos os pods injetados com o proxy Linkerd.

O secret havia sido inadvertidamente removido em operação anterior de limpeza. Sem o trust anchor,
o proxy de cada pod não conseguia validar o certificado mTLS do identity service → InvalidContentType
loop → todo workload com `linkerd.io/inject=enabled` entrava em CrashLoop.

---

## 2. Root Causes (3 encadeados)

### RC-1 — linkerd-trust-anchor ausente

O secret `linkerd-trust-anchor` no namespace `linkerd` foi removido. Sem esse secret:

- O `identity` service não consegue servir certificados mTLS
- O `destination` não consegue resolver políticas mTLS
- Todos os proxies injetados falham no handshake → CrashLoopBackOff

**Pods afetados:** GitLab (11 pods), Linkerd control plane (destination, identity, proxy-injector),
além de qualquer workload com Linkerd inject ativo.

### RC-2 — SHA256 trailing newline bug (descoberto durante o fix)

Na primeira tentativa de recriar o secret, o hash SHA256 do certificado estava errado.

**Por quê:** Ao extrair o cert via variável shell e usar `echo "$CERT" | sha256sum`, o comando `echo`
stripa o trailing newline (`\n`) do conteúdo da variável. O certificado PEM termina com `\n`, então
o hash calculado difere do hash do arquivo original. O Linkerd valida o hash durante o proxy inject
— qualquer divergência causa `CertificateInvalid`.

**Fix:** Usar `--from-file=ca.crt=<arquivo>` ao criar o secret, que preserva o conteúdo exato do
arquivo incluindo o trailing newline. Alternativamente, extrair o cert direto do Terraform state via
`terraform output` que também preserva o conteúdo exato.

### RC-3 — CNI deadlock: porta 8080 (identity headless) interceptada pelo próprio proxy

Após recriar o trust anchor corretamente, o `destination` e o `proxy-injector` ainda falhavam com
`InvalidContentType` ao tentar comunicar com o `identity` service.

**Por quê:** Com o Linkerd CNI em modo iptables, todo tráfego outbound do pod é redirecionado pelo
proxy antes de sair da rede do pod. A porta 8080 é usada internamente pelo `identity` service como
porta headless para comunicação do control plane. O proxy do `destination` tentava conectar em
`identity:8080` → iptables redirecionava para o próprio proxy local → loopback impossível →
`InvalidContentType` em loop.

**Fix:** Adicionar a annotation `config.linkerd.io/skip-outbound-ports: "8080"` nos deployments
`destination` e `proxy-injector`. Isso instrui o CNI a não interceptar tráfego outbound na porta
8080, permitindo comunicação direta com o identity service.

### RC-4 (contribuinte) — System ASG max=4 insuficiente

Com o control plane do Linkerd tentando escalar (recriar pods), o node group `system` atingiu o
limite de 4 nós (17/17 pods por nó). O pod `identity` ficou `Unschedulable`.

**Fix:** Executar `terraform apply` no `module.linkerd` com `max_size=5` para o node group `system`.
O `node-groups.tf` já tinha `max_size=6` configurado desde 2026-03-05 — a mudança foi elevar o
limite operacional de 4 para 5 nós (1 changed).

---

## 3. Linha do Tempo

| Horário (BRT) | Evento |
|---------------|--------|
| ~15:00 | Audit detecta 58 alertas firing. P0: linkerd-trust-anchor AUSENTE. P1: VaultDown + RDSPostgreSQLPlatformWideOutage (cascata Linkerd). |
| ~15:30 | Diagnóstico confirmado: `kubectl get secret linkerd-trust-anchor -n linkerd` → NotFound |
| ~16:00 | Primeira tentativa: secret recriado com cert extraído via variável shell (`echo "$CERT"`) → hash SHA256 errado → identity ainda em CrashLoop |
| ~16:30 | RC-2 identificado: SHA256 trailing newline bug. Nova estratégia: extrair cert do TF state + recriar com `--from-file` |
| ~17:00 | Secret recriado corretamente. Identity service Up. Porém destination + proxy-injector ainda em loop `InvalidContentType` |
| ~17:30 | RC-3 identificado: CNI deadlock porta 8080. Annotation `skip-outbound-ports=8080` adicionada em destination + proxy-injector |
| ~18:00 | Linkerd control plane estabilizando. System ASG atingiu max=4 → identity Unschedulable |
| ~18:30 | `terraform apply module.linkerd` executado — max_size: 4→5 (1 changed). Zero drift pós-apply. |
| ~18:45 | `terraform apply module.vault_staging` executado — unauthenticated_metrics_access=true (1 changed). VaultDown falso positivo eliminado. Zero drift pós-apply. |
| ~19:00 | Linkerd OPERATIONAL: destination 4/4, identity 2/2, proxy-injector 2/2. GitLab 11/11 pods 2/2 ou 3/3 Running. Root token Vault revogado. |

---

## 4. Ações Executadas

### 4.1 linkerd-trust-anchor — Recriação correta

```bash
# Extrair o cert do TF state (preserva trailing newline):
terraform output -raw linkerd_trust_anchor_cert > /tmp/trust-anchor.crt

# Recriar o secret com --from-file (preserva conteúdo exato):
kubectl create secret generic linkerd-trust-anchor \
  --from-file=ca.crt=/tmp/trust-anchor.crt \
  --namespace=linkerd \
  --dry-run=client -o yaml | kubectl apply -f -

# Verificar:
kubectl get secret linkerd-trust-anchor -n linkerd
kubectl rollout restart deployment/linkerd-destination -n linkerd
kubectl rollout restart deployment/linkerd-identity -n linkerd
```

### 4.2 CNI deadlock — skip-outbound-ports

```bash
# Adicionar annotation nos deployments do control plane:
kubectl annotate deployment linkerd-destination -n linkerd \
  config.linkerd.io/skip-outbound-ports=8080 --overwrite

kubectl annotate deployment linkerd-proxy-injector -n linkerd \
  config.linkerd.io/skip-outbound-ports=8080 --overwrite

kubectl rollout restart deployment/linkerd-destination deployment/linkerd-proxy-injector -n linkerd
```

### 4.3 System ASG max_size — terraform apply module.linkerd

Alteração em `platform-provisioning/aws/kubernetes/terraform/modules/eks/node-groups.tf`:
- `system` node group: `max_size` operacional elevado de 4 para 5

```bash
terraform apply -target=module.linkerd
# Resultado: 1 changed (system ASG max_size: 4 → 5)
# terraform plan pós-apply: No changes — ZERO DRIFT
```

### 4.4 Vault telemetry — terraform apply module.vault_staging

Alteração em `platform-provisioning/aws/kubernetes/terraform/modules/vault/values.yaml.tpl`:

```hcl
telemetry {
  unauthenticated_metrics_access = true
}
```

```bash
terraform apply -target=module.vault_staging
# Resultado: 1 changed (Vault helm values atualizado)
# terraform plan pós-apply: No changes — ZERO DRIFT
```

### 4.5 Keycloak backup endpoints — /auth/ prefix removido

Keycloak 17+ eliminou o prefixo `/auth/` de todos os endpoints. O cluster roda KC 26.5.1.
O script de backup usava URLs com `/auth/realms/...` → 404. Corrigido nos 4 endpoints do script.

### 4.6 Root token Vault — revogado pós-apply

```bash
vault token revoke -self
# HTTP 204 confirmado → token inválido
# K8s secret vault-root-token no namespace staging-security-vault: verificado e removido
```

---

## 5. Verificação Final (~19:00 BRT)

```bash
# Linkerd control plane:
kubectl get pods -n linkerd
# destination-xxx    2/2  Running  (4 replicas)
# identity-xxx       2/2  Running  (2 replicas)
# proxy-injector-xxx 2/2  Running  (2 replicas)

# GitLab pods:
kubectl get pods -n staging-platform-gitlab
# webservice-xxx     2/2  Running  (2/2 = app + linkerd-proxy)
# gitaly-xxx         3/3  Running  (3/3 = app + linkerd-proxy + linkerd-proxy-init)
# ... 11/11 Running

# Vault:
kubectl get pods -n staging-security-vault
# vault-0/1/2: 2/2 Running

# RDS: AVAILABLE (confirmado via AWS console — falso positivo da cascata Linkerd)
```

---

## 6. Lições Aprendidas

### LL-1 — Nunca usar `echo "$VAR"` para calcular hash de certificados PEM

`echo` stripa o trailing newline. Certificados PEM terminam com `\n`. O hash resultante difere do
arquivo original. Sempre usar `--from-file` ou redirecionar o arquivo diretamente.

**Regra:** Para qualquer operação com cert PEM → usar `--from-file=<key>=<arquivo>` no kubectl.

### LL-2 — CNI iptables + porta headless: configurar skip-outbound-ports no control plane

Ao ativar o Linkerd CNI em modo iptables, os componentes do control plane que comunicam entre si
via portas headless precisam ter essas portas explicitamente excluídas da interceptação do proxy.
Portas críticas: 8080 (identity), 8086 (destination), 8443 (proxy-injector webhook).

**Regra:** Ao fazer `terraform apply` do módulo Linkerd com CNI, verificar se os deployments do
control plane têm `skip-outbound-ports` configurado para as portas de comunicação interna.

### LL-3 — Keycloak 17+: sem prefixo /auth/ em nenhum endpoint

Desde o Keycloak 17 (Quarkus-based), o prefixo `/auth/` foi removido de todos os endpoints.
Scripts de backup, scripts de SSO e qualquer automação devem usar URLs sem `/auth/`:

```
# ERRADO (KC <17):
https://keycloak.example.com/auth/realms/master/...

# CORRETO (KC 17+):
https://keycloak.example.com/realms/master/...
```

**Cluster atual:** KC 26.5.1 — confirmar que todos os scripts não usam `/auth/`.

### LL-4 — VaultDown alert: sempre verificar se é falso positivo antes de escalar

O alert `VaultDown` disparou porque o Prometheus tentava scrape de `/sys/metrics` sem token de
autenticação → 403 Forbidden → Prometheus marca Vault como down. O Vault estava 100% operacional.

**Fix definitivo:** `unauthenticated_metrics_access = true` na stanza `telemetry {}` do Vault config.
Isso permite que o Prometheus scrape as métricas sem precisar de token.

**Regra:** Ao ver `VaultDown` alert, primeiro verificar `kubectl get pods -n staging-security-vault`
e `vault status` antes de escalar como incidente de infra.

### LL-5 — ASG max_size: dimensionar com folga para acomodar recovery de control plane

O sistema precisou de um nó adicional para acomodar a recuperação do Linkerd control plane. Se
o ASG estiver no limite, pods ficam `Unschedulable` durante o recovery → delay significativo.

**Regra:** Node groups que hospedam control plane de service mesh ou plataforma crítica devem ter
`max_size` com folga de pelo menos 1 nó acima do `desired_size` em produção.

---

## 7. IaC Changes — Terraform (zero drift confirmado)

| Módulo | Arquivo | Mudança | Apply Status |
|--------|---------|---------|-------------|
| module.linkerd | eks/node-groups.tf | system ASG max_size: 4 → 5 | APLICADO — No changes pós-apply |
| module.vault_staging | vault/values.yaml.tpl | telemetry.unauthenticated_metrics_access = true | APLICADO — No changes pós-apply |

**Nota:** A annotation `skip-outbound-ports=8080` foi aplicada diretamente via kubectl como
emergência. Deve ser codificada no módulo Linkerd como `podAnnotations` no próximo ciclo para
garantir que não seja perdida em reimplantações.

---

## 8. Impacto no Negócio

| Componente | Período Afetado | Status Final |
|------------|-----------------|--------------|
| Linkerd mTLS | ~15:00 → ~19:00 BRT (4h) | RESOLVIDO — OPERATIONAL |
| GitLab (CI/CD) | ~15:00 → ~19:00 BRT (4h) | RESOLVIDO — 11/11 pods Running |
| Vault (secrets) | Falso positivo | RESOLVIDO — AVAILABLE |
| RDS PostgreSQL | Falso positivo | RESOLVIDO — AVAILABLE |
| Pipeline CI/CD | Indisponível durante incidente | RECUPERADO |

---

## 9. Ações Pendentes (pós-recovery)

| Item | Prioridade | Responsável | Prazo |
|------|-----------|-------------|-------|
| Codificar `skip-outbound-ports=8080` no módulo Linkerd TF (podAnnotations) | P1 | Platform | Próximo sprint |
| Adicionar runbook de `linkerd-trust-anchor` ausente no Runbook Linkerd | P2 | Platform | Próximo sprint |
| Revisar todos os scripts com endpoints KC para remover `/auth/` remanescentes | P2 | Platform | Próximo sprint |
| Verificar eficácia `suspend_cluster_autoscaler()` no próximo weekend (2026-03-14/15) | P1 | FinOps | 2026-03-15 |

---

**Preparado em:** 2026-03-12 ~19:00 BRT
**Session:** P0 Recovery — Linkerd trust-anchor + CNI deadlock + ASG max + Vault telemetry
**Próximo logbook:** [2026-03-12-finops-code-review.md](2026-03-12-finops-code-review.md)
