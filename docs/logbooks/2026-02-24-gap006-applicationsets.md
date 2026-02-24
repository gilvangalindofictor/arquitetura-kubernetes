# Logbook — GAP-006: ArgoCD ApplicationSets GitOps Automation

**Data:** 2026-02-24  
**Duração:** ~35 minutos  
**Executor:** Agente Especialista Terraform/GitOps GAP-006  
**Status:** CONCLUÍDO ✅

---

## Objetivo

Implementar ArgoCD ApplicationSets para substituir criação manual de Applications,
habilitando GitOps zero-touch para onboarding de novos serviços.

---

## Reconhecimento Inicial

| Item | Valor |
|------|-------|
| ArgoCD versão | v2.10.0 |
| Namespace | argocd |
| ApplicationSet Controller | Ativo (2 réplicas) |
| Applications existentes antes | 0 |
| ApplicationSets existentes antes | 0 |
| Git repo | https://github.com/gilvangalindofictor/arquitetura-kubernetes.git |
| ArgoCD URL | http://argocd.staging.internal |
| Namespaces plataforma | 25+ namespaces staging |

---

## Execução

### FASE 1: Estrutura de Diretórios

Criada convenção `apps/<environment>/<domain>/<service>/` com stubs para 10 serviços:

```
apps/staging/
  monitoring/  grafana | loki | tempo
  security/    vault | keycloak
  platform/    harbor | argocd | new-service (teste)
  data/        rabbitmq | redis
  governance/  kyverno
apps/production/
  monitoring/ | security/ | data/ | platform/  (reservado)
```

### FASE 2: ApplicationSets criados

**cluster-services** (Git Directory Generator):
- Path: `apps/staging/*/*/app.yaml`
- Naming: `staging-{domain}-{service}`
- Sync: automated + prune + selfHeal
- Status: Aguardando push ao GitHub

**multi-env-services** (Matrix Generator):
- 7 serviços × 1 environment (staging) = 7 Applications
- Naming: `{environment}-{service}`
- Status: 7 Applications criados imediatamente

### FASE 3: Validação cluster

```
NAME               SYNC STATUS   HEALTH STATUS
staging-grafana    Unknown       Healthy
staging-harbor     Unknown       Healthy
staging-keycloak   Unknown       Healthy
staging-kyverno    Unknown       Healthy
staging-rabbitmq   Unknown       Healthy
staging-redis      Unknown       Healthy
staging-vault      Unknown       Healthy
```

Sync Unknown = path ainda não pushed ao GitHub. Health Healthy = Application object válido.

### FASE 4: Teste auto-discovery

`apps/staging/platform/new-service/` criado com `app.yaml` + `deployment.yaml`.
Será validado após `git push` — Application `staging-platform-new-service` deve aparecer em ~3min.

---

## Artifacts Criados

| Arquivo | Tipo |
|---------|------|
| `argocd/applicationsets/cluster-services.yaml` | ApplicationSet (Git Directory Generator) |
| `argocd/applicationsets/multi-env-services.yaml` | ApplicationSet (Matrix Generator) |
| `apps/staging/monitoring/grafana/app.yaml` | App stub |
| `apps/staging/monitoring/loki/app.yaml` | App stub |
| `apps/staging/monitoring/tempo/app.yaml` | App stub |
| `apps/staging/security/vault/app.yaml` | App stub |
| `apps/staging/security/keycloak/app.yaml` | App stub |
| `apps/staging/platform/harbor/app.yaml` | App stub |
| `apps/staging/data/rabbitmq/app.yaml` | App stub |
| `apps/staging/data/redis/app.yaml` | App stub |
| `apps/staging/governance/kyverno/app.yaml` | App stub |
| `apps/staging/platform/new-service/` | Teste auto-discovery |
| `docs/adr/adr-077-applicationsets-gitops-automation.md` | ADR DEC-077 |
| `docs/governance/argocd-applicationset-onboarding.md` | Onboarding Guide |

---

## Métricas de Sucesso

| Critério | Status |
|----------|--------|
| ApplicationSet cluster-services criado | ✅ |
| ApplicationSet multi-env-services criado | ✅ |
| Applications auto-gerados (>=1) | ✅ (7 gerados) |
| Teste auto-discovery preparado | ✅ (pendente git push) |
| Zero erros no cluster | ✅ |
| ADR documentado | ✅ |
| Onboarding Guide criado | ✅ |

---

## Próximos Passos

1. `git push` para ativar cluster-services (Git Directory Generator)
2. Aguardar ~3min → verificar `kubectl get application staging-platform-new-service -n argocd`
3. Configurar ArgoCD repo credentials se repositório for privado (Secret tipo repository)
4. Quando cluster production for provisionado: descomentar production no multi-env-services.yaml
5. Migrar para Helm values reais em cada `apps/staging/DOMAIN/SERVICE/` (substituir app.yaml stubs)

---

## Decisões Tomadas

| Decisão | Razão |
|---------|-------|
| `app.yaml` como marcador (não `kustomization.yaml`) | Mais simples; stubs informativos sem processar pelo K8s |
| Matrix Generator para multi-env | Permite adicionar production descomentando 2 linhas |
| Git Directory Generator para cluster-services | Auto-discovery zero-touch |
| ServerSideApply habilitado | Evita field manager conflicts com operators |
| RespectIgnoreDifferences habilitado | Operators podem modificar resources sem trigger loop |
| `apps/staging/*/*/app.yaml` (3 níveis) | Obriga domain layer — evita serviços sem categorização |

