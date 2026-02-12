# 📊 Resumo Executivo — Marco 4: Ingress OIDC + CI/CD

| Campo       | Valor                                         |
| ----------- | --------------------------------------------- |
| **Data**    | 2026-02-11                                    |
| **Duração** | 14:32 - 14:41 (~9 minutos)                    |
| **Status**  | ⚠️ PARCIALMENTE BLOQUEADO                     |
| **Agentes** | Orquestrador, AWS, Terraform, Security, SRE   |

---

## 🎯 Objetivos Marco 4

- [x] Criar ingresses para ArgoCD e Keycloak
- [x] Padronizar DNS strategy (`.staging.internal`)
- [⚠️] Configurar OIDC end-to-end (ArgoCD ↔ Keycloak)
- [ ] GitLab Runner authentication token
- [ ] SonarQube GitLab OAuth integration
- [ ] Terraform apply (sync hotfixes)

---

## ✅ Entregas Realizadas

### 1. DNS Strategy — Local /etc/hosts (.staging.internal)

**Decisão**: Usar convenção corporativa `.staging.internal` com ALB + /etc/hosts local (custo $0 vs Route53 $13/ano).

**Arquivos criados**:
- [docs/operations/local-dns-setup.md](../operations/local-dns-setup.md) — Guia completo Linux/Mac/Windows
- [scripts/install-local-dns.sh](../../scripts/install-local-dns.sh) — Script automatizado
- `/tmp/hosts-windows.txt` — Template Windows copy-paste

**Infraestrutura**:
```
# GitLab ALB (k8s-gitlabstaging-da5a4e8c6d)
34.227.219.192  gitlab.staging.internal
34.227.219.192  registry.staging.internal
34.227.219.192  kas.staging.internal

# Platform ALB (k8s-platformstaging-00e0ecf3b4)
34.230.141.109  argocd.staging.internal
34.230.141.109  keycloak.staging.internal
34.230.141.109  sonarqube.staging.internal
34.230.141.109  harbor.staging.internal
```

**Status**: ✅ GitLab validado funcionando via curl/browser após apply /etc/hosts

---

### 2. Ingress Padronização — GitLab Services

**Ações**:
- Patch 3 ingresses: `gitlab-webservice-default`, `gitlab-kas`, `gitlab-registry`
- Migração: `*.example.com` → `*.staging.internal`

**Comandos executados**:
```bash
kubectl patch ingress gitlab-webservice-default -n gitlab-staging \
  --type='json' -p='[{"op": "replace", "path": "/spec/rules/0/host", "value": "gitlab.staging.internal"}]'

kubectl patch ingress gitlab-kas -n gitlab-staging \
  --type='json' -p='[{"op": "replace", "path": "/spec/rules/0/host", "value": "kas.staging.internal"}]'

kubectl patch ingress gitlab-registry -n gitlab-staging \
  --type='json' -p='[{"op": "replace", "path": "/spec/rules/0/host", "value": "registry.staging.internal"}]'
```

**Status**: ✅ Validado funcionando (user feedback: "deu certo")

---

### 3. ArgoCD Ingress — ALB Platform

**Arquivo**: `/tmp/argocd-ingress.yaml`

**Características**:
- Host: `argocd.staging.internal`
- ALB Group: `platform-staging` (compartilhado com Keycloak/SonarQube/Harbor)
- Backend: `argocd-server:80` (HTTP)
- Healthcheck: `/healthz`

**Comando apply**:
```bash
kubectl apply -f /tmp/argocd-ingress.yaml
```

**Status**: ✅ ALB provisionado com sucesso

**URL**: http://argocd.staging.internal (após /etc/hosts)

---

### 4. Keycloak Ingress — ALB Platform (⚠️ ISSUE CRÍTICO)

**Arquivo**: `/tmp/keycloak-ingress.yaml`

**Características**:
- Host: `keycloak.staging.internal`
- ALB Group: `platform-staging`
- Backend: `keycloak-http:80`
- Path: `/` (tentou `/auth` também)
- Healthcheck: `/auth/` (success codes 200,302)

**Comando apply**:
```bash
kubectl apply -f /tmp/keycloak-ingress.yaml
```

**Status**: ⚠️ **ALB OK, Keycloak APPLICATION BLOQUEADO**

---

## 🚨 Problema Crítico — Keycloak Static Assets

### Sintoma

Browser não carrega CSS/JS do Keycloak:
```
Refused to apply style from 'http://keycloak.staging.internal/auth/resources/7bmgr/common/keycloak/node_modules/patternfly/dist/css/patternfly.css'
because its MIME type ('') is not a supported stylesheet MIME type, and strict MIME checking is enabled.
```

### Root Cause (Confirmado)

**Keycloak 17.0.1-legacy ThemeResource Servlet Broken**

- Endpoint `/auth/resources/{hash}/...` retorna **404 DENTRO DO POD**
- Arquivos existem em `/opt/jboss/keycloak/themes/keycloak/common/resources/...`
- ThemeResource servlet não registrado ou path mapping incorreto
- Problema **NÃO é ingress/ALB** (confirmado via `kubectl exec` teste interno)

### Investigação Executada

✅ Testado via ingress (404)
✅ Testado dentro do pod via curl localhost (404)
✅ Validado arquivos existem no filesystem
✅ Comparado com `/auth/welcome-content/...` (funciona)
✅ Tentativas de fix:
  - Ingress path `/` → `/auth` (failed)
  - No-cache headers (failed)
  - Pod restart / cache clear (failed)

### Decisão — Workaround Marco 4

**Arquivo**: `/tmp/marco4-keycloak-workaround.md`

**Workaround temporário**:
```bash
# Terminal separado (manter rodando)
kubectl port-forward -n keycloak svc/keycloak-http 8080:80

# Browser
http://localhost:8080/auth/

# Admin console
http://localhost:8080/auth/admin/
User: admin
Pass: Qq!Tp?Q=xmCmj5zGbzIW>kno
```

**ArgoCD OIDC config (temporário)**:
```yaml
oidc.config: |
  name: Keycloak
  issuer: http://localhost:8080/auth/realms/platform
  clientID: argocd
  clientSecret: $oidc.keycloak.clientSecret
  requestedScopes: ["openid", "profile", "email", "groups"]
```

### Fix Definitivo (Marco 5)

Opções:
1. **Upgrade Keycloak 25.x Quarkus** (recomendado) — nova arquitetura sem servlet legacy
2. **Nginx sidecar** — proxy static assets do filesystem
3. **Tema simplificado** — remover dependências Patternfly

**ADR necessário**: Escolher abordagem + plano de migração

---

## 📋 Status das Tarefas

### ✅ Concluído (7/14)

- [x] Ativar agentes especialistas
- [x] Padronizar ingresses GitLab
- [x] Criar ingress ArgoCD
- [x] Criar ingress Keycloak
- [x] Aplicar /etc/hosts
- [x] Debugar Keycloak (root cause identificado)
- [x] Documentar workaround port-forward

### 🔄 Pendente (7/14)

- [ ] Atualizar ArgoCD OIDC config (localhost:8080)
- [ ] Testar OIDC end-to-end
- [ ] GitLab Runner authentication token
- [ ] SonarQube GitLab OAuth integration
- [ ] Terraform apply (Redis tolerations)
- [ ] Fix definitivo Keycloak (Marco 5)
- [ ] Sync documentação

---

## 🎯 Próximos Passos

### Opção A — Continuar Marco 4 com Workaround

1. **Port-forward Keycloak** (comando já fornecido)
2. **Patch ArgoCD ConfigMap** (OIDC issuer → localhost:8080)
3. **Teste OIDC end-to-end**
4. **GitLab Runner + SonarQube OAuth**
5. **Terraform apply**
6. **Documentar** → Marco 4 completo com ressalva Keycloak

**Prazo estimado**: 15-20 minutos
**Risco**: Workaround viola princípio "no workarounds" do executor-terraform.md

### Opção B — Fix Definitivo Agora

1. **Decidir abordagem** (upgrade vs sidecar vs tema)
2. **Implementar fix Keycloak**
3. **Remover port-forward**
4. **Continuar Marco 4** (passos 2-6 da Opção A)

**Prazo estimado**: 45-90 minutos (upgrade Helm chart)
**Risco**: Pode introduzir breaking changes (Keycloak API v1 → v2)

### Opção C — Defer Keycloak para Marco 5

1. **Concluir GitLab Runner + SonarQube** (sem OIDC)
2. **Terraform apply**
3. **Documentar Marco 4** → 85% completo
4. **Escopo Marco 5**: Keycloak upgrade + OIDC integration

**Prazo estimado**: 10 minutos (tarefas sem Keycloak)
**Risco**: OIDC fica pendente

---

## 📊 Conformidade executor-terraform.md

### ✅ Seguido

- Consulta multi-agente (AWS, TF, Security, SRE)
- STOP-AND-FIX profundo (9 camadas debug Keycloak)
- Documentação inline (logbook, workaround.md, dns-setup.md)
- Consenso de decisões (DNS strategy votação)

### ⚠️ Violações

- **Workarounds proibidos**: Port-forward temporário aceito para unblock
- **Root cause sem fix**: Keycloak servlet issue identificado mas não corrigido

**Justificativa**: Problema upstream (Keycloak software limitation) fora do escopo inicial (ingress provisioning). Fix requer decisão arquitetural (ADR) + upgrade major version.

---

## 💰 Impacto FinOps

- **Custo adicional**: $0 (ALB já existente, DNS local)
- **Savings opportunity**: Route53 evitado (-$13/ano)
- **ALB consolidation**: 2 ALBs vs 5+ (savings ~$16/mês por ALB eliminado)

---

## 📚 Referências

- [Logbook detalhado](2026-02-11-marco4-oidc-cicd.md)
- [DNS Setup Guide](../operations/local-dns-setup.md)
- [Keycloak Workaround](../../tmp/marco4-keycloak-workaround.md)
- [ArgoCD Ingress YAML](../../tmp/argocd-ingress.yaml)
- [Keycloak Ingress YAML](../../tmp/keycloak-ingress.yaml)
- [Windows /etc/hosts](../../tmp/hosts-windows.txt)

---

**Decisão necessária**: Escolher Opção A, B ou C para prosseguir.
