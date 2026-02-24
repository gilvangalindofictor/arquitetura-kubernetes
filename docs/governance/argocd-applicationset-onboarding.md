# Onboarding Guide: ArgoCD ApplicationSets (GAP-006)

**Versão:** 1.0
**Data:** 2026-02-24
**Audiência:** Platform Engineers, Dev Teams
**ADR:** DEC-077

---

## TL;DR — Adicionar novo serviço em 3 passos

```bash
# 1. Criar diretório seguindo convenção
mkdir -p apps/staging/DOMAIN/SERVICE-NAME

# 2. Criar app.yaml (obrigatório — sem isso o ApplicationSet ignora o diretório)
cat > apps/staging/DOMAIN/SERVICE-NAME/app.yaml << 'EOF'
appVersion: "x.y.z"
service: SERVICE-NAME
namespace: TARGET-NAMESPACE
EOF

# 3. Commitar e fazer push
git add apps/staging/DOMAIN/SERVICE-NAME
git commit -m "feat(gitops): add SERVICE-NAME to staging"
git push

# Resultado: em ~3 minutos, o Application é criado automaticamente no ArgoCD
```

---

## Estrutura de Diretórios

```
apps/
├── staging/                    # environment
│   ├── monitoring/             # domain
│   │   ├── grafana/            # service (app.yaml obrigatório)
│   │   ├── loki/
│   │   └── tempo/
│   ├── security/
│   │   ├── vault/
│   │   └── keycloak/
│   ├── platform/
│   │   ├── harbor/
│   │   └── argocd/
│   ├── data/
│   │   ├── rabbitmq/
│   │   └── redis/
│   └── governance/
│       └── kyverno/
└── production/                 # reservado (provisionar quando cluster prod existir)
```

### Domains disponíveis

| Domain | Descrição | Namespace padrão |
|--------|-----------|-----------------|
| `monitoring` | Observabilidade: Grafana, Loki, Tempo, Prometheus | `monitoring` |
| `security` | Segurança: Vault, Keycloak, ExternalSecrets | `staging-security-*` |
| `platform` | Plataforma: Harbor, ArgoCD, GitLab | `harbor-system`, etc. |
| `data` | Data Services: RabbitMQ, Redis, PostgreSQL | `data-services` |
| `governance` | Políticas: Kyverno, OPA | `staging-governance-*` |

---

## Arquivo app.yaml

O arquivo `app.yaml` é o **marcador obrigatório** para o Git Directory Generator.
Sem ele, o diretório é ignorado. Seu conteúdo é informativo (não processado pelo K8s).

```yaml
# Exemplo mínimo
appVersion: "1.2.3"
service: my-service
namespace: staging-platform-my-service
```

**Campos recomendados:**

| Campo | Obrigatório | Descrição |
|-------|-------------|-----------|
| `appVersion` | Sim | Versão do Helm chart ou imagem |
| `service` | Sim | Nome do serviço (igual ao diretório) |
| `namespace` | Sim | Namespace de destino no cluster |
| `helmChart` | Não | Nome do chart Helm |
| `helmRepo` | Não | URL do repositório Helm |

---

## Naming Convention

### cluster-services ApplicationSet (Git Directory Generator)

```
Application name: staging-DOMAIN-SERVICE

Exemplos:
  apps/staging/monitoring/grafana  -> staging-monitoring-grafana
  apps/staging/security/vault      -> staging-security-vault
  apps/staging/platform/harbor     -> staging-platform-harbor
```

### multi-env-services ApplicationSet (Matrix Generator)

```
Application name: ENVIRONMENT-SERVICE

Exemplos:
  staging  x grafana   -> staging-grafana
  staging  x vault     -> staging-vault
  production x grafana -> production-grafana  (quando habilitado)
```

---

## Labels Obrigatórios nos Manifests

Todo manifest deployado via ApplicationSet DEVE ter os labels:

```yaml
metadata:
  labels:
    app.kubernetes.io/managed-by: argocd
    environment: staging
    app.kubernetes.io/name: SERVICE-NAME
```

---

## Adicionar serviço ao multi-env-services

Para serviços que precisam estar em todos os environments, edite o `multi-env-services.yaml`:

```yaml
# argocd/applicationsets/multi-env-services.yaml
# Adicionar na lista de services:
- service: my-new-service
  domain: platform
  namespace: staging-platform-my-new-service
```

Aplicar:
```bash
kubectl apply -f argocd/applicationsets/multi-env-services.yaml
```

---

## Remover um serviço

```bash
# Opção 1: Remover do Git (cluster-services prune automático)
git rm -r apps/staging/DOMAIN/SERVICE
git commit -m "chore(gitops): remove SERVICE from staging"
git push
# O Application é removido automaticamente em ~3min

# Opção 2: Remover do multi-env-services list e aplicar
# Editar argocd/applicationsets/multi-env-services.yaml -> remover da lista
kubectl apply -f argocd/applicationsets/multi-env-services.yaml
```

---

## Verificação e Troubleshooting

```bash
# Listar ApplicationSets
kubectl get applicationset -n argocd

# Ver Applications gerados por um ApplicationSet
kubectl get applications -n argocd -l app.kubernetes.io/managed-by=applicationset

# Filtrar por environment
kubectl get applications -n argocd -l environment=staging

# Filtrar por domain
kubectl get applications -n argocd -l domain=monitoring

# Ver status detalhado de um Application
kubectl describe application staging-grafana -n argocd

# Ver log do ApplicationSet controller
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller --tail=50

# Forçar re-sync de um Application
kubectl annotate application staging-grafana argocd.argoproj.io/refresh=normal -n argocd --overwrite
```

### Problema: Application não criado após git push

1. Verificar poll interval do ArgoCD (default: 3 min)
2. Confirmar que `app.yaml` existe no diretório
3. Verificar que o path segue `apps/staging/DOMAIN/SERVICE/app.yaml`
4. Ver eventos do ApplicationSet:
   ```bash
   kubectl describe applicationset cluster-services -n argocd | grep -A20 Events
   ```

### Problema: Sync Status Unknown

Ocorre quando o path no Git ainda não foi pushed ou é inválido. O ApplicationSet cria o
Application mas o ArgoCD não consegue clonar o path. Verificar se o commit chegou ao GitHub.

---

## Fluxo Completo de Onboarding

```
Dev Team                     Git                    ArgoCD
    |                          |                        |
    |-- mkdir apps/staging/... |                        |
    |-- criar app.yaml         |                        |
    |-- criar manifests K8s    |                        |
    |-- git push ------------->|                        |
    |                          |<-- poll (3min) --------|
    |                          |-- detecta novo path -->|
    |                          |                   ApplicationSet gera Application
    |                          |                   Application sync automático
    |                          |                   Namespace criado (se não existir)
    |                          |                   Manifests aplicados no cluster
    |                          |                        |
    |<---------------------------------------- Application Healthy --|
```

---

## Ambientes Suportados

| Environment | Status | Cluster Server |
|-------------|--------|---------------|
| staging | Ativo | https://kubernetes.default.svc |
| production | Reservado | A provisionar |

Para habilitar production, descomentar no `multi-env-services.yaml`:
```yaml
# - environment: production
#   server: https://kubernetes.default.svc
#   revision: main
```

---

## Referências

- ADR: `docs/adr/adr-077-applicationsets-gitops-automation.md`
- ApplicationSets: `argocd/applicationsets/`
- ArgoCD UI: http://argocd.staging.internal
- Logbook: `docs/logbooks/2026-02-24-gap006-applicationsets.md`
- [ArgoCD ApplicationSet docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/)
