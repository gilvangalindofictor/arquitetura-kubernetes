# DEPLOYMENT CHECKLIST — Hatch ETL Onboarding + Backstage S6 Deploy
**Data**: 2026-03-15
**Responsavel**: DevOps/Platform Team
**Demanda**: Deploy Backstage S6 + Onboarding Hatch ETL EKS
**Documento principal**: `docs/demands/2026-03-13-hatch-etl-onboarding-eks.md`
**Playbook base**: `docs/plan/backstage/BACKSTAGE-IMPLEMENTATION-PLAN.md`

---

## PRE-REQUISITOS (Validar ANTES de iniciar qualquer fase)

### Acesso AWS/Kubernetes
- [ ] AWS SSO ativo: `aws sso login --profile k8s-platform-prod`
- [ ] kubeconfig atualizado: `aws eks update-kubeconfig --name <cluster-name> --region us-east-1 --profile k8s-platform-prod`
- [ ] kubectl funcional: `kubectl get nodes` retorna nodes Ready
- [ ] Acesso correto: `kubectl config current-context` aponta para cluster staging

### Variaveis de Ambiente
- [ ] `VAULT_TOKEN` exportado (token admin temporario)
- [ ] `DB_PASSWORD` exportado (senha PostgreSQL hatch_user)
- [ ] `REDIS_PASSWORD` exportado (senha Redis Sentinel)
- [ ] `KEYCLOAK_SECRET` exportado (OIDC client secret)
- [ ] `KEYCLOAK_ADMIN_PASSWORD` exportado (senha admin Keycloak)

### Validacoes Locais
- [ ] Scripts com permissao de execucao:
  ```bash
  chmod +x vault-setup-hatch-etl.sh configmap-setup.sh
  ```
- [ ] Arquivos presentes no diretorio `docs/plan/backstage/`:
  ```bash
  ls -la hatch-etl-external-secret.yaml vault-setup-hatch-etl.sh configmap-setup.sh
  ```
- [ ] Schema JSON presente:
  ```bash
  ls -la Arquitetura/Kubernetes/domains/platform-core/app-provisioning/schemas/v1/manifest-schema.json
  ```

---

## SEQUENCIA DE EXECUCAO

### FASE 1 — Validacao do Cluster (estimativa: 5-10 min)

**Objetivo**: Confirmar que a infraestrutura esta operacional pos-AWS-recovery.

```bash
# 1.1 Verificar namespaces criticos
kubectl get namespaces | grep -E "staging-(security-vault|platform-backstage|data-hatch-etl)"

# 1.2 Verificar Vault
kubectl get pods -n staging-security-vault
# GATE: vault-0 deve estar Running 1/1 (ou 2/2 com sidecar)

# 1.3 Verificar ExternalSecrets Operator
kubectl get pods -n staging-platform-operator  # ou namespace onde roda o ESO
kubectl get clustersecretstore vault-backend
# GATE: ClusterSecretStore vault-backend deve estar READY=True

# 1.4 Verificar ArgoCD
kubectl get pods -n staging-platform-argocd
# GATE: argocd-server e argocd-application-controller Running

# 1.5 Verificar GitLab Runner
kubectl get pods -n staging-platform-cicd | grep runner
# GATE: 2/2 runners Running (conforme MEMORY.md)

# 1.6 Verificar Backstage existente
kubectl get pods -n staging-platform-backstage
kubectl get externalsecret backstage-secrets -n staging-platform-backstage
# GATE: Backstage pod Running, ExternalSecret SecretSynced
```

**Criterio de conclusao Fase 1**:
- [ ] Vault pod Running
- [ ] ClusterSecretStore vault-backend READY
- [ ] ArgoCD operacional
- [ ] GitLab Runner 2/2 Running
- [ ] Backstage pod Running

**Se algum gate falhar**: Investigar antes de continuar. Nao executar Fase 2 com Vault inacessivel.

---

### FASE 2 — Vault + ExternalSecret Hatch ETL (estimativa: 10-15 min)

**Objetivo**: Resolver GAP-VAULT-HATCH — criar paths Vault e sincronizar secrets.

```bash
# 2.1 Criar namespace hatch-etl (se nao existir)
kubectl create namespace staging-data-hatch-etl --dry-run=client -o yaml | kubectl apply -f -

# 2.2 Executar script de setup Vault
cd Arquitetura/Kubernetes/docs/plan/backstage
./vault-setup-hatch-etl.sh
# GATE: Script finaliza com "GAP-VAULT-HATCH: CONCLUIDO"

# 2.3 Verificar ExternalSecret sincronizado
kubectl get externalsecret hatch-etl-secrets -n staging-data-hatch-etl
# GATE: READY=True, SecretSynced

# 2.4 Verificar Secret K8s criado
kubectl get secret hatch-etl-secrets -n staging-data-hatch-etl
kubectl get secret hatch-etl-secrets -n staging-data-hatch-etl \
  -o go-template='{{range $k,$v := .data}}{{$k}}{{"\n"}}{{end}}'
# GATE: 6 chaves presentes (DATABASE_URL, DATABASE_PASSWORD, REDIS_URL,
#        REDIS_PASSWORD, KEYCLOAK_CLIENT_SECRET, KEYCLOAK_ADMIN_PASSWORD)
```

**Criterio de conclusao Fase 2**:
- [ ] 3 paths Vault criados (database, redis, keycloak)
- [ ] ExternalSecret hatch-etl-secrets READY=True
- [ ] Secret K8s hatch-etl-secrets com 6 chaves
- [ ] GAP-VAULT-HATCH: FECHADO

**Rollback Fase 2**:
```bash
# Remover ExternalSecret (Secret K8s tem deletionPolicy: Retain — preservado)
kubectl delete externalsecret hatch-etl-secrets -n staging-data-hatch-etl
# Remover paths Vault (somente se necessario recriar do zero)
# vault kv delete secret/staging/hatch-etl/database
# vault kv delete secret/staging/hatch-etl/redis
# vault kv delete secret/staging/hatch-etl/keycloak
```

---

### FASE 3 — ConfigMap Schema + Vault Policy Scaffolder (estimativa: 5-10 min)

**Objetivo**: Resolver GAP-S6C-01 — ConfigMap schema e policy Vault para Backstage Scaffolder.

```bash
# 3.1 Executar script de setup ConfigMap
cd Arquitetura/Kubernetes/docs/plan/backstage
./configmap-setup.sh
# GATE: Script finaliza com "GAP-S6C-01: CONCLUIDO"

# 3.2 Verificar ConfigMap criado
kubectl get configmap platform-manifest-schema -n staging-platform-backstage
kubectl get configmap platform-manifest-schema -n staging-platform-backstage \
  -o jsonpath='{.data.manifest-schema\.json}' | python3 -m json.tool > /dev/null
# GATE: ConfigMap existe e contem JSON valido

# 3.3 Verificar Vault policy
kubectl exec -n staging-security-vault vault-0 \
  -- env VAULT_TOKEN="${VAULT_TOKEN}" VAULT_ADDR="http://127.0.0.1:8200" \
  vault policy list | grep backstage-scaffolder
# GATE: "backstage-scaffolder" aparece na lista

# 3.4 Reiniciar Backstage para montar ConfigMap
kubectl rollout restart deployment/backstage -n staging-platform-backstage
kubectl rollout status deployment/backstage -n staging-platform-backstage --timeout=120s
# GATE: deployment "backstage" successfully rolled out
```

**Criterio de conclusao Fase 3**:
- [ ] ConfigMap platform-manifest-schema criado com JSON valido
- [ ] Policy backstage-scaffolder criada no Vault
- [ ] Role kubernetes/backstage com ambas policies (backstage-policy + backstage-scaffolder)
- [ ] Backstage pod reiniciado e Running
- [ ] GAP-S6C-01: FECHADO

**Nota de automacao (GAP-AUTOMATE-CONFIGMAP-01)**: Este passo e manual. Quando o `manifest-schema.json`
for atualizado no futuro, re-executar `./configmap-setup.sh` para sincronizar o ConfigMap no cluster.
Automacao futura: job `post-deploy` no pipeline CI/CD do Backstage.

**Rollback Fase 3**:
```bash
# Remover ConfigMap
kubectl delete configmap platform-manifest-schema -n staging-platform-backstage
# Restaurar role Vault sem a nova policy
# vault write auth/kubernetes/role/backstage policies=backstage-policy ...
# Rollback Backstage para versao anterior
kubectl rollout undo deployment/backstage -n staging-platform-backstage
```

---

### FASE 4 — Helm Backstage Upgrade (estimativa: 15-20 min)

**Objetivo**: Resolver GAP-S6C-02 — plugin scaffolder-backend-module-gitlab configurado.

```bash
# 4.1 Verificar helm-values-staging.yaml atualizado
cat Arquitetura/Kubernetes/platform-provisioning/helm/backstage/helm-values-staging.yaml \
  | grep -A5 scaffolder

# 4.2 Dry-run do upgrade
helm upgrade backstage backstage/backstage \
  --version 2.6.3 \
  --namespace staging-platform-backstage \
  --values Arquitetura/Kubernetes/platform-provisioning/helm/backstage/helm-values-staging.yaml \
  --dry-run 2>&1 | head -50
# GATE: dry-run sem erros

# 4.3 Executar upgrade
helm upgrade backstage backstage/backstage \
  --version 2.6.3 \
  --namespace staging-platform-backstage \
  --values Arquitetura/Kubernetes/platform-provisioning/helm/backstage/helm-values-staging.yaml \
  --timeout 5m \
  --wait

# 4.4 Verificar pods apos upgrade
kubectl get pods -n staging-platform-backstage
kubectl logs deployment/backstage -n staging-platform-backstage --tail=50 | grep -i error
# GATE: Pod Running, sem erros criticos nos logs
```

**Criterio de conclusao Fase 4**:
- [ ] Helm upgrade sem erros
- [ ] Backstage pod Running apos upgrade
- [ ] Plugin scaffolder-backend-module-gitlab carregado (verificar logs)
- [ ] GAP-S6C-02: FECHADO

**Rollback Fase 4**:
```bash
helm rollback backstage -n staging-platform-backstage
kubectl rollout status deployment/backstage -n staging-platform-backstage
```

---

### FASE 5 — Templates ETL + Catalog Entity (estimativa: 20-30 min)

**Objetivo**: Resolver GAP-S6C-03 — templates ETL e entity Hatch ETL no Backstage.

```bash
# 5.1 Verificar templates ETL presentes no repositorio backstage-catalog
# GitLab repo: platform/backstage-catalog (ID=7, criado em Sprint S6-0)
ls Arquitetura/Kubernetes/docs/plan/backstage/templates/

# 5.2 Publicar templates no GitLab (se necessario)
# (via MR automatico — depende de GAP-S6C-03)

# 5.3 Registrar entity hatch-etl no Backstage catalog
kubectl exec -n staging-platform-backstage deployment/backstage -- \
  wget -qO- http://localhost:7007/api/catalog/entities?filter=metadata.name=hatch-etl
# GATE: Entity hatch-etl visivel no catalogo

# 5.4 Verificar health do Backstage
curl -s https://backstage.staging.internal/healthcheck | python3 -m json.tool
# GATE: status: "ok"
```

**Criterio de conclusao Fase 5**:
- [ ] Templates ETL disponiveis no Backstage UI
- [ ] Entity hatch-etl registrada no catalogo
- [ ] GAP-S6C-03: FECHADO

---

### FASE 6 — ArgoCD Application + Sync Hatch ETL (estimativa: 15-20 min)

**Objetivo**: Criar Application ArgoCD e primeiro sync do namespace staging-data-hatch-etl.

```bash
# 6.1 Verificar manifest ArgoCD
cat Arquitetura/Kubernetes/docs/plan/backstage/argocd-application.yaml | grep -A5 hatch-etl

# 6.2 Criar Application ArgoCD para hatch-etl
kubectl apply -f Arquitetura/Kubernetes/docs/plan/backstage/argocd-application.yaml
# OU via argocd CLI:
# argocd app create hatch-etl \
#   --repo https://gitlab.staging.internal/platform/hatch-etl.git \
#   --path k8s/overlays/staging \
#   --dest-namespace staging-data-hatch-etl \
#   --dest-server https://kubernetes.default.svc \
#   --sync-policy automated

# 6.3 Primeiro sync
argocd app sync hatch-etl --timeout 120
argocd app wait hatch-etl --health --timeout 180
# GATE: hatch-etl Healthy + Synced

# 6.4 Verificar pods
kubectl get pods -n staging-data-hatch-etl
# GATE: Pods Running (etl-core, api-gateway, worker, etc.)

# 6.5 Verificar health checks
kubectl get pods -n staging-data-hatch-etl -o wide
kubectl describe pod -n staging-data-hatch-etl | grep -A5 "Liveness\|Readiness"
```

**Criterio de conclusao Fase 6**:
- [ ] ArgoCD Application hatch-etl criada
- [ ] Application status: Healthy + Synced
- [ ] Pods Running no namespace staging-data-hatch-etl
- [ ] Health checks liveness/readiness passando

---

### FASE 7 — Pipeline GitLab + Validacao CI/CD (estimativa: 15-20 min)

```bash
# 7.1 Verificar .gitlab-ci.yml do Hatch ETL
cat ETL/Hatch/.gitlab-ci.yml | head -30

# 7.2 Triggar pipeline manualmente (validate stage apenas)
# Via GitLab UI: CI/CD > Pipelines > Run Pipeline (branch: main)

# 7.3 Verificar pipeline passando
# Stages esperados: validate:manifest, validate:naming, validate:labels, provision, deploy

# 7.4 Verificar variaveis no GitLab
# Settings > CI/CD > Variables: VAULT_TOKEN, KUBE_CONFIG, etc.
```

**Criterio de conclusao Fase 7**:
- [ ] Pipeline GitLab executado sem erros nos stages validate
- [ ] Stage provision concluido com sucesso
- [ ] Variaveis CI/CD configuradas no GitLab

---

## VALIDACOES POS-DEPLOY (Executar apos todas as fases)

```bash
# V1: Pods Running
kubectl get pods -n staging-data-hatch-etl
# Esperado: etl-core, api-gateway, worker, poller, anexos-service, web, dashboard, prometheus-exporter

# V2: ExternalSecret sincronizado
kubectl get externalsecret -n staging-data-hatch-etl
# Esperado: hatch-etl-secrets READY=True

# V3: ArgoCD Application saudavel
argocd app get hatch-etl
# Esperado: Health Status: Healthy, Sync Status: Synced

# V4: Health check api-gateway
kubectl exec -n staging-data-hatch-etl deployment/api-gateway -- \
  wget -qO- http://localhost:8000/healthz
# Esperado: HTTP 200

# V5: Backstage catalog entity
curl -s "https://backstage.staging.internal/api/catalog/entities?filter=metadata.name=hatch-etl" \
  -H "Authorization: Bearer <backstage-token>" | python3 -m json.tool | grep '"name"'
# Esperado: "name": "hatch-etl"

# V6: Metricas Prometheus
kubectl exec -n staging-data-hatch-etl deployment/prometheus-exporter -- \
  wget -qO- http://localhost:9090/metrics | head -20
# Esperado: metricas ETL disponiveis

# V7: Zero GAPs P0 abertos
# (verificar demanda principal: docs/demands/2026-03-13-hatch-etl-onboarding-eks.md)
```

---

## CRITERIOS DE ROLLBACK

### Rollback Total (reverter tudo)

Executar apenas se multiplas fases falharem e nao houver caminho de correcao rapido.

```bash
# 1. Remover ArgoCD Application (para o sync)
argocd app delete hatch-etl --cascade

# 2. Rollback Backstage Helm
helm rollback backstage -n staging-platform-backstage

# 3. Remover ExternalSecret hatch-etl
kubectl delete externalsecret hatch-etl-secrets -n staging-data-hatch-etl

# 4. Remover ConfigMap schema
kubectl delete configmap platform-manifest-schema -n staging-platform-backstage

# 5. Vault paths (manter — dados, nao aplicar delete sem aprovacao)
# Discutir com o time antes de apagar paths Vault
```

### Rollback Parcial por Fase

| Fase | Rollback |
|------|----------|
| Fase 2 (Vault/ESO) | `kubectl delete externalsecret hatch-etl-secrets -n staging-data-hatch-etl` |
| Fase 3 (ConfigMap) | `kubectl delete configmap platform-manifest-schema -n staging-platform-backstage` + `kubectl rollout undo deployment/backstage -n staging-platform-backstage` |
| Fase 4 (Helm) | `helm rollback backstage -n staging-platform-backstage` |
| Fase 6 (ArgoCD) | `argocd app delete hatch-etl` |

---

## DEFINITION OF DONE

A demanda e considerada **CONCLUIDA** quando:

- [ ] GAP-VAULT-HATCH: FECHADO (3 paths Vault + ExternalSecret READY)
- [ ] GAP-S6C-01: FECHADO (ConfigMap schema + policy scaffolder)
- [ ] GAP-S6C-02: FECHADO (plugin scaffolder-backend-module-gitlab)
- [ ] GAP-S6C-03: FECHADO (templates ETL no Backstage)
- [ ] `kubectl get pods -n staging-data-hatch-etl` retorna todos os pods Running
- [ ] ArgoCD Application hatch-etl: Healthy + Synced
- [ ] Pipeline GitLab passando (lint + validate + deploy)
- [ ] Backstage catalog entity hatch-etl visivel
- [ ] 0 GAPs P0 abertos
- [ ] MEMORY.md atualizado com status CONCLUIDO

---

## CONTATOS DE EMERGENCIA

| Papel | Contato | Disponibilidade |
|-------|---------|-----------------|
| Platform Lead | [PLACEHOLDER] | [PLACEHOLDER] |
| AWS/Infra | [PLACEHOLDER] | [PLACEHOLDER] |
| DevOps On-call | [PLACEHOLDER] | [PLACEHOLDER] |
| Equipe Hatch ETL | [PLACEHOLDER] | [PLACEHOLDER] |

---

## REFERENCIAS

| Documento | Caminho |
|-----------|---------|
| Demanda principal | `docs/demands/2026-03-13-hatch-etl-onboarding-eks.md` |
| Manifest Hatch ETL | `ETL/Hatch/.platform/manifest.yaml` |
| Schema JSON | `domains/platform-core/app-provisioning/schemas/v1/manifest-schema.json` |
| ExternalSecret Hatch | `docs/plan/backstage/hatch-etl-external-secret.yaml` |
| Script Vault setup | `docs/plan/backstage/vault-setup-hatch-etl.sh` |
| Script ConfigMap | `docs/plan/backstage/configmap-setup.sh` |
| Backstage Impl Plan | `docs/plan/backstage/BACKSTAGE-IMPLEMENTATION-PLAN.md` |
| Vault Policy | `docs/plan/backstage/vault-policy.hcl` |
| MEMORY.md | `~/.claude/projects/.../memory/MEMORY.md` |

---

*Gerado em: 2026-03-15 | Sprint: S6-C (pos-AWS-recovery) | Status: PRONTO PARA EXECUCAO*
