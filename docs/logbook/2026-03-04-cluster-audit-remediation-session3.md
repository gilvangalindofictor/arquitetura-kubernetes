# Logbook: Cluster Audit Remediation — Sessão 3

**Data**: 2026-03-04 (noite)
**Duração**: ~3h
**Executor**: Orquestrador + 5 agentes especializados (executor-terraform.md framework)
**Resultado**: ✅ 6/6 discrepâncias do Cluster Audit resolvidas

---

## Contexto

Cluster Audit executado no início da sessão revelou 6 discrepâncias entre documentação e estado real do cluster. Agentes especializados foram disparados em paralelo para resolver cada demanda.

---

## Discrepâncias Resolvidas

### 1. Velero — Helm FAILED + Zero Schedules → ✅ RESOLVIDO

**Root causes:**
- IRSA ARN malformed: `:role:` → deve ser `/role/` no ARN
- Role name errado: `k8s-platform-prod-velero-role` → `k8s-platform-prod-velero-dr-role`
- nodeSelector saturado: `workload: platform` (17/17 pods) → `workload: applications`
- CPU request reduzido: 100m → 50m

**Fix aplicado:** `helm upgrade vmware-tanzu/velero --reuse-values` + correções de values
**Resultado:** Helm `deployed`, schedules `daily-full-backup` (02:00 UTC, 30d) + `hourly-incremental` (24h) ativos

---

### 2. Harbor — Sem Linkerd Proxy → ✅ RESOLVIDO

**Root cause:** namespace `harbor-system` sem annotation `linkerd.io/inject: enabled` após redeploy harbor rev 4

**Fix aplicado:**
```bash
kubectl annotate ns harbor-system linkerd.io/inject=enabled
kubectl rollout restart deployment -n harbor-system
```
**Resultado:** 7/7 pods 2/2 Running com mTLS proxy Linkerd

---

### 3. ArgoCD — v2.9.3 (não v2.10.0) → ✅ RESOLVIDO (v2.10.9)

**Root cause:** Upgrade via `kubectl set image` (2026-02-20) foi revertido pelo Helm state quando namespace recriado. Chart 5.x→6.x breaking changes não foram tratados.

**Breaking changes chart 5.x→6.x (6 categorias):**
- `server.config` ignorado → usar `configs.cm`
- Ingress template migrado (nova estrutura)
- OIDC config (`oidc.config`) não persistido no ConfigMap
- Nil pointer em 6 templates sem valores explícitos

**Fix aplicado:** `helm upgrade argo-cd-6.7.18` com values file completo + PKCE + ingress

**PKCE S256:**
- `enablePKCEAuthentication: true` no values
- `pkce_code_challenge_method = "S256"` em `modules/keycloak-clients/clients/argocd.tf`

**Resultado:** v2.10.9, 8/8 pods Running, PKCE S256 ativo, ingress funcional, Keycloak OIDC operacional

---

### 4. Kyverno — 48% compliance / staging-data-hatch → ✅ RESOLVIDO

**Root cause:** Namespace `staging-data-hatch` (5d) sem labels corporate. Kyverno ENFORCE bloqueava novos pods.

**Fix aplicado:**
1. Labels aplicados nos 9 deployments (`domain/environment/owner/app.kubernetes.io/name`)
2. `kubectl rollout restart` em todos os deployments
3. MutatingClusterPolicy `inject-corporate-labels-staging-platform-gitlab` criada para auto-inject no namespace GitLab

**Resultado:** staging-data-hatch 9/9 Running, compliance geral ~90%+

---

### 5. VPA — Day 7 Validation → ✅ RESOLVIDO

**Resultado:** Report `docs/reports/vpa-day7-report-2026-03-04.md` criado

**Sumário VPA Day 7:**
- 7 VPAs com dados, 4 com recomendações ativas
- Net savings: R$1.170/ano (harbor-core + redis + sidekiq)
- ⚠️ WARNING: `gitlab-webservice` memory under-provisioned (1.5Gi config vs 2.49Gi actual)
- updateMode: Off em todos (coleta apenas, sem auto-scale)

---

### 6. GitLab — Namespace `gitlab-staging` → `staging-platform-gitlab` → ✅ RESOLVIDO

**Root causes (múltiplos, resolvidos sequencialmente):**

1. **Kyverno webhook bloqueava todos os recursos GitLab** — chart cria recursos sem corporate labels
   - Fix: MutatingClusterPolicy `inject-corporate-labels-staging-platform-gitlab`

2. **cert-manager Issuer ACME falhou** — `email: platform-team@example.com` rejeitado pelo Let's Encrypt
   - Fix: `kubectl patch issuer gitlab-issuer -n staging-platform-gitlab --type=merge -p '{"spec":{"selfSigned":{}}}'`

3. **Helm `pending-upgrade` locked** — agentes interrompidos deixaram release travado
   - Fix: patch no helm secret + helm rollback

4. **linkerd-network-validator CrashLoop** — pods schedulados ANTES do CNI pod subir no novo nó
   - Fix: `kubectl delete pod` para recriar APÓS CNI Running
   - Annotation: `config.linkerd.io/skip-outbound-ports=5432,6379,8075` no namespace

5. **gitaly-0 Pending** — cluster saturado (max node group size reached)
   - Root cause: total pod = linkerd-network-validator (100m fixo) + linkerd-proxy (100m) + gitaly (100m) = 300m
   - Fix: `config.linkerd.io/proxy-cpu-request=10m` no STS annotation + gitaly requests 10m CPU/128Mi
   - Resultado: gitaly schedulado no nó ip-10-0-143-191 (100m livre)

6. **runner DNS failure** — `gitlab.staging.internal` não resolve em `staging-platform-gitlab`
   - Fix: URL atualizado para `gitlab-webservice-default.staging-platform-gitlab.svc.cluster.local:8181`
   - Arquivos: `values-staging-working.yaml` + helm upgrade `--reuse-values`

**Resultado Final:** 11/11 pods Running em `staging-platform-gitlab` | `gitlab-staging` namespace DELETADO

---

### 7. Keycloak TF — TASK-002 → ✅ RESOLVIDO (bônus desta sessão)

**4 bugs estruturais fixados:**
1. TF não inclui subdirs automaticamente → symlinks criados no root do módulo
2. `base_path = ""` → `"/auth"` (keycloakx 7.1.7 requer `/auth` prefix)
3. `keycloak_saml_user_attribute_protocol_mapper` para email (propriedade ≠ atributo) → `keycloak_saml_user_property_protocol_mapper`
4. Import format mappers: `realm/client/{clientUUID}/{mapperUUID}` (não `realm/{clientUUID}`)

**Resultado:** 11/11 recursos importados, `terraform plan` = 0 to add/change/destroy, módulo re-enabled em `environments/staging/main.tf`

---

## Commits

- `2aabcd7` — feat(platform): Cluster Audit 6/6 resolvidos (19 files, +1490 lines)
- `[pendente]` — docs: atualização demandas pós-execução

---

## Lições Aprendidas

| Área | Lição |
|------|-------|
| Linkerd CNI | Pods schedulados antes do CNI pod subir não recebem iptables rules → sempre recriar pods após CNI Ready |
| Cluster capacity | Com cluster saturado, considerar proxy-cpu-request annotation antes de escalar |
| Helm chart upgrades | `kubectl set image` não persiste contra helm state — sempre usar helm upgrade |
| ArgoCD chart 5→6 | `server.config` foi deprecated → `configs.cm` é obrigatório |
| cert-manager ACME | `example.com` é rejeitado pelo Let's Encrypt — usar selfSigned para staging interno |
| TF Keycloak | Módulos TF não incluem `.tf` de subdirs — estrutura flat ou symlinks necessários |
| Velero IRSA | ARN format crítico: `/role/` (não `:role:`) + nome exato do role TF-provisionado |
