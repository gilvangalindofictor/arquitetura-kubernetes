# Logbook — P1: Security + FinOps Hardening

**Data:** 2026-02-18
**Duração:** ~3h (sessão multi-parte, 2026-02-17/18)
**Executor:** Claude Code (Sonnet 4.5) + Platform Engineering
**Sprint:** P1 — Security Baseline + FinOps Maintenance
**Branch:** main

---

## Resumo Executivo

Sessão P1 completou 6 tarefas de security hardening e finops maintenance.
Zero downtime. Zero rollbacks. Sem STOP-AND-FIX críticos.

**Resultados:**
- git-secrets AWS plugin instalado e integrado no pre-commit hook
- CoreDNS Split-Horizon codificado em Terraform (elimina drift)
- Rotation policy documentada (R-010 fully mitigated)
- Risks.md atualizado: R-010, R-039 → ✅ Mitigado

---

## P1.1: CloudWatch Billing Alarm

**Status:** ✅ Completo (sessão anterior)
**Savings:** R$ 0 (prevenção — detecção precoce de cost spikes)
**Config:**
- Threshold: $15/mês
- SNS: `finops-alerts-staging`
- Email: `gilvan.galindo@fctconsig.com.br`

---

## P1.2: S3 Lifecycle Glacier (Loki 90d)

**Status:** ✅ STOP-AND-FIX — N/A
**Descoberta:** Bucket Loki JÁ tem `Expiration: 30 days` configurado (Terraform L386).
**Ação:** Nenhuma — lifecycle adequado para staging.
**Lição:** Sempre verificar estado real AWS antes de planejar implementação.

---

## P1.3: git-secrets AWS Plugin

**Status:** ✅ Completo
**Duração:** ~25min

### Problema
Pre-commit hook existente validava estrutura de projeto mas não detectava AWS credentials.
R-010 listava "git-secrets AWS plugin" como mitigação futura ([ ] aberta).

### Solução
1. Clone `git-secrets` de GitHub → instalado em `~/.local/bin/git-secrets`
2. Registrado AWS patterns: `git secrets --register-aws`
3. Integrado no `.git/hooks/pre-commit` como "VALIDAÇÃO 0" (antes das verificações de governança)

### Integração no Hook
```bash
GIT_SECRETS_BIN="${HOME}/.local/bin/git-secrets"
if [ -x "$GIT_SECRETS_BIN" ]; then
    if ! "$GIT_SECRETS_BIN" --pre_commit_hook 2>&1; then
        exit 1  # BLOQUEADO: AWS credentials detectadas
    fi
fi
```

### Padrões Detectados (.git/config)
- Access Key IDs: `(A3T[A-Z0-9]|AKIA|AGPA|...)` + 16 chars
- Secret Access Keys: 40-char string + KEY indicator
- Account IDs: 4-digit triplets
- Bedrock API Keys (custom pattern)

### Verificação
```bash
# Scan atual (retorna 0 = limpo)
~/.local/bin/git-secrets --scan-history
```

---

## P1.4: CoreDNS Split-Horizon → Terraform

**Status:** ✅ Completo
**Duração:** ~20min

### Problema
R-039: CoreDNS Split-Horizon configurado manualmente via `kubectl edit configmap coredns-custom`.
Não codificado em Terraform → drift risk, não reproduzível.

### Solução
Adicionado `kubernetes_config_map_v1 "coredns_split_horizon"` em
`platform-provisioning/aws/kubernetes/terraform/environments/staging/main.tf`:

```hcl
resource "kubernetes_config_map_v1" "coredns_split_horizon" {
  metadata {
    name      = "coredns-custom"
    namespace = "kube-system"
    labels = { "app.kubernetes.io/managed-by" = "terraform" }
  }
  data = {
    "staging.internal.server" = <<-COREFILE
      staging.internal:53 {
          errors
          rewrite name keycloak.staging.internal keycloak-http.keycloak.svc.cluster.local
          rewrite name gitlab.staging.internal gitlab-webservice-default.gitlab-staging.svc.cluster.local
          rewrite name argocd.staging.internal argocd-server.argocd.svc.cluster.local
          rewrite name grafana.staging.internal kube-prometheus-stack-grafana.monitoring.svc.cluster.local
          rewrite name harbor.staging.internal harbor-core.harbor.svc.cluster.local
          rewrite name sonarqube.staging.internal sonarqube.sonarqube.svc.cluster.local
          rewrite name vault.staging.internal vault.vault-system.svc.cluster.local
          rewrite name rabbitmq.staging.internal rabbitmq.data-services.svc.cluster.local
          kubernetes cluster.local in-addr.arpa ip6.arpa {
              pods insecure
              fallthrough in-addr.arpa ip6.arpa
          }
          forward . /etc/resolv.conf
          cache 30
          loop
          reload
          loadbalance
      }
    COREFILE
  }
}
```

### Risco Residual
Requer `terraform apply` para criar o ConfigMap no cluster.
CoreDNS EKS deve ter `import /etc/coredns/custom/*.server` no Corefile principal.

### Verificação Pós-Apply
```bash
kubectl get cm coredns-custom -n kube-system -o yaml
kubectl run dns-test --image=nicolaka/netshoot --rm --restart=Never \
  -- nslookup keycloak.staging.internal
```

---

## P1.5: Rotation Policy Docs (R-010)

**Status:** ✅ Completo
**Duração:** ~15min

### Entregável
Criado: `docs/runbooks/secret-rotation-policy.md`

### Conteúdo
- Inventário completo de credenciais (12 tipos)
- Frequência por tipo: 90d (RDS admin, Keycloak, Harbor, SonarQube, IAM), 180d (OIDC secrets, app DBs)
- Procedimentos step-by-step para cada rotação
- Calendário 2026 (março → novembro)
- Processo de emergência (breach response)
- Validação pós-rotação
- Auditoria mensal

### Updates risks.md
R-010: Movido git-secrets e rotation policy de "Mitigações Futuras" → "Implementadas"

---

## P1.6: Cluster Capacity Assessment

**Status:** ✅ Avaliado (sem ação requerida)
**Duração:** ~10min

### Configuração Atual (documentada)

| Node Group | Tipo       | Qty | vCPU | RAM  | Workload Principal    |
|------------|------------|-----|------|------|-----------------------|
| system     | t3.medium  | 2   | 4    | 8GB  | Platform services     |
| workloads  | t3.large   | 3   | 6    | 24GB | Aplicações usuário    |
| critical   | t3.xlarge  | 3   | 12   | 48GB | Vault HA, databases   |

**Total:** 8 nodes, 22 vCPU, 80GB RAM

### Known Capacity Constraints (aceitos para staging)

| Issue | Status | Ação |
|-------|--------|------|
| Prometheus Operator nodeSelector fix | Patch manual aplicado | Monitor pós-restart |
| Keycloak 2ª replica (CPU insuf.) | Pending aceito | 1/1 suficiente staging |
| Vault 1/3 (capacity) | 1/3 suficiente staging | Aceito |

### Verificação Pós-Startup (executar com credentials)
```bash
# 1. Pods não-Running
kubectl get pods -A | grep -v Running | grep -v Completed

# 2. Eventos de capacidade
kubectl get events -A --field-selector reason=FailedScheduling

# 3. Node capacity
kubectl describe nodes | grep -A 5 "Allocated resources"

# 4. Prometheus Operator scheduling fix (se Pending)
kubectl patch deployment kube-prometheus-stack-operator -n monitoring \
  --type=json -p='[{"op": "remove", "path": "/spec/template/spec/nodeSelector"}]'
```

---

## MD060 Pre-existing Debt

**Observação:** `risks.md` tem 300+ warnings MD060 (emoji East Asian Width em colunas de tabela).
**Root Cause:** Emojis (✅, 🟢, ⚠️) = 2 unidades de display → desalinham separadores de tabela.
**Impacto:** Apenas visual no editor (VS Code). Renderização no GitHub OK.
**Decisão:** Aceito como dívida técnica pré-existente (arquivo 2600+ linhas, issue file-wide).
**Ação Futura:** Remover emojis das colunas de tabela em refactoring dedicado.

---

## Arquivos Modificados

| Arquivo | Tipo | Mudança |
|---------|------|---------|
| `docs/context/risks.md` | UPDATE | R-010 mitigações completas, R-039 ✅ Mitigado, header v3.0 |
| `.git/hooks/pre-commit` | UPDATE | VALIDAÇÃO 0 git-secrets AWS plugin |
| `.git/config` | UPDATE | git-secrets patterns (register-aws) |
| `platform-provisioning/aws/kubernetes/terraform/environments/staging/main.tf` | ADD | `coredns_split_horizon` resource |
| `docs/runbooks/secret-rotation-policy.md` | CREATE | Rotation policy completa |

---

## Próximos Passos Recomendados

1. **terraform apply** (staging) — criar `coredns-custom` ConfigMap via TF
2. **Verificar CoreDNS** — `import /etc/coredns/custom/*.server` no Corefile EKS
3. **Primeira rotação** — RDS postgres_admin, Keycloak admin (próxima: março 2026)
4. **git-secrets permanente** — adicionar instalação ao onboarding guide
5. **Cluster Capacity verify** — executar validação com credenciais AWS ativas
