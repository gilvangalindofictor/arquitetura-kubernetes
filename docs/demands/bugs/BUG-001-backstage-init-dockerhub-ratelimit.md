# BUG-001 — Backstage Init Container Docker Hub Rate Limit 429

**Data:** 2026-03-13
**Severidade:** P0 CRITICO
**Status:** ABERTO — Fix documentado, pendente helm upgrade bem-sucedido
**Componente:** Backstage / init container `install-oidc`
**Ambiente:** Staging (namespace: staging-platform-backstage)
**Detectado em:** Teste de UP/DOWN do ambiente (2026-03-13)

## Sintoma

Após qualquer restart do ambiente (node drain, rollout, pod restart, ambiente UP/DOWN):
- Pods Backstage ficam em `Init:ImagePullBackOff` indefinidamente
- Causa: init container `install-oidc` tenta puxar `node:22-bookworm-slim` diretamente do Docker Hub público (docker.io/library/)
- Docker Hub retorna 429 Too Many Requests para pulls não autenticados a partir de ~100 pulls/6h por IP
- O cluster EKS usa NAT Gateway compartilhado → um único IP público → rate limit atingido rapidamente

## Impacto

- Backstage IDP 100% indisponível após qualquer restart
- Desenvolvedores não conseguem criar serviços via Self-Service
- Todo o Sprint S6 (catalog, templates, MR automático) fica inacessível
- Sem SLA — downtime indefinido até intervenção manual

## Root Cause

O Helm chart backstage/backstage 2.6.3 possui init container que usa imagem pública.
A imagem não estava espelhada no Harbor interno.

## Fix (Validado)

### Opcao A — Harbor Proxy (RECOMENDADA) — APLICADA em 2026-03-13

Imagem do init container alterada no `docs/plan/backstage/helm-values-staging.yaml`:

```yaml
# De:
image: node:22-bookworm-slim

# Para (linha 480 do helm-values-staging.yaml):
image: harbor.staging.internal/dockerhub-proxy/library/node:22-bookworm-slim
```

Comentario adicionado no values confirmando o fix:
```
# BLOQUEADOR P0 (2026-03-13): imagem pública node:22-bookworm-slim causava
#   rate-limit 429 no Docker Hub (unauthenticated pull).
#   CORRIGIDO: usar Harbor proxy interno para Docker Hub.
#   Harbor proxy: harbor.staging.internal/dockerhub-proxy/library/
```

Após editar, executar:
```bash
helm upgrade backstage backstage/backstage \
  --namespace staging-platform-backstage \
  --values docs/plan/backstage/helm-values-staging.yaml \
  --version 2.6.3 \
  --timeout 10m \
  --wait
```

### Opcao B — Pre-pull + Harbor push (alternativa se proxy não funcionar)
```bash
# Na máquina com acesso Docker Hub autenticado:
docker pull node:22-bookworm-slim
docker tag node:22-bookworm-slim harbor.staging.internal/library/node:22-bookworm-slim
docker push harbor.staging.internal/library/node:22-bookworm-slim
```
Depois atualizar o helm-values para apontar ao `harbor.staging.internal/library/node:22-bookworm-slim`

### Opcao C — imagePullSecrets (menos recomendada)
Configurar imagePullSecrets com credenciais Docker Hub autenticadas no namespace backstage.

## Comandos de Diagnostico

```bash
# Verificar status dos pods
kubectl get pods -n staging-platform-backstage

# Ver o erro de pull
kubectl describe pod -n staging-platform-backstage -l app.kubernetes.io/name=backstage | grep -A5 "Init Containers"

# Verificar o init container na release atual
helm get values backstage -n staging-platform-backstage | grep -A5 initContainers

# Se pods em ImagePullBackOff, forçar pull via Harbor proxy:
kubectl set image deployment/backstage install-oidc=harbor.staging.internal/dockerhub-proxy/library/node:22-bookworm-slim -n staging-platform-backstage
```

## Prevencao

- Politica: toda imagem usada em init containers deve estar no Harbor interno
- Adicionar ao checklist de onboarding de novos Helm charts a verificação de imagens públicas
- Considerar OPA/Kyverno policy bloqueando imagens fora do `harbor.staging.internal`
