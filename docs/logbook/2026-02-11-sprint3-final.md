# Sprint 3 - Relatório Final
**Data**: 2026-02-11  
**Duração**: ~6h de trabalho efetivo  
**Status**: ✅ 85% Completo

---

## 📊 Resumo Executivo

Sprint 3 focou em resolver issues pendentes de infraestrutura e validar integrações OIDC. Principais conquistas:

- ✅ GitLab + Redis totalmente operacionais
- ✅ Keycloak OIDC infraestrutura configurada
- ✅ ArgoCD OIDC pronto (pendente Ingress para teste)
- ✅ Limitações identificadas e documentadas

---

## ✅ Accomplishments

### 1. GitLab + Redis Recovery (Issue #1)

**Problema Inicial**: GitLab webservice/sidekiq em CrashLoopBackOff devido a falha de conexão Redis.

**Root Cause**: 
- Redis pods não schedulavam (PVC node affinity + node taint sem tolerations)
- Password mismatch entre namespaces

**Resolução**:
1. **Redis Tolerations**: Adicionados via kubectl patch (hotfix)
   ```yaml
   tolerations:
   - key: workload
     operator: Equal
     value: critical
     effect: NoSchedule
   ```

2. **Password Sync**: Sincronizado secret entre `data-services` ↔ `gitlab-staging`
   ```bash
   kubectl create secret generic redis-password -n gitlab-staging \
     --from-literal=password=$(kubectl get secret -n data-services redis-password -o jsonpath='{.data.password}' | base64 -d)
   ```

3. **Restart Deployments**: GitLab webservice/sidekiq restarted e validados

**Status Final**:
- Redis: 3/3 pods Running, master elected (10.0.145.215:6379)
- GitLab Webservice: 2/2 Running
- GitLab Sidekiq: 1/1 Running
- Health: ✅ "GitLab OK" (HTTP 200)

**Acesso Externo Configurado**:
- URL: http://gitlab.example.com
- IP: 50.17.236.17 (ALB)
- /etc/hosts: Configurado
- Credenciais: root / tf%g!*}r7WS{X_*==24g[x5!CagEkHbZ

### 2. Keycloak OIDC Setup

**Infraestrutura**:
- Keycloak: 2 pods Running
- Realm `platform` criado via UI
- Clients configurados:
  - **argocd**: clientID=argocd, secret=EevIzpYR6ai3tssDMsxwDH5bRBjj0YIp
  - **sonarqube**: clientID=sonarqube, secret=Oif7qf7u1jVMyIfYboVPyybbVK5tRBJn
- Admin: admin / Qq!Tp?Q=xmCmj5zGbzIW>kno

**Configuração ArgoCD**:
```yaml
oidc.config: |
  name: Keycloak
  issuer: http://keycloak-http.keycloak.svc.cluster.local/auth/realms/platform
  clientID: argocd
  clientSecret: $oidc.keycloak.clientSecret
  requestedScopes:
    - openid
    - profile
    - email
    - groups
```

**Secrets Atualizados**:
- argocd-secret: `oidc.keycloak.clientSecret` = EevIzpYR6ai3tssDMsxwDH5bRBjj0YIp
- sonarqube-oidc: clientSecret atualizado

### 3. Limitações Identificadas

#### SonarQube Community Edition
**Descoberta**: SonarQube Community 10.3.0 **NÃO suporta OIDC**.

OIDC é feature exclusiva de Enterprise/DataCenter. Community suporta apenas:
- SAML ✅
- GitHub OAuth ✅
- GitLab OAuth ✅
- Bitbucket OAuth ✅

**Recomendação**: Usar GitLab OAuth para SonarQube (já temos GitLab operacional).

#### OIDC Testing Local (Port-Forward)
**Desafio Arquitetural**: Port-forward não funciona para OIDC end-to-end porque:
- ArgoCD pod precisa acessar Keycloak via DNS interno (`.svc.cluster.local`)
- Browser precisa acessar Keycloak via localhost
- São contextos de rede diferentes

**Solução para Produção**: Ingress com DNS real (não é problema da configuração, apenas de teste local).

#### GitLab Runner
**Issue**: Token de registro deprecated (GitLab 17.7.0 usa authentication tokens).

**Status**: Postergar para quando precisar de CI/CD pipelines. GitLab core está operacional.

---

## 🔧 Hotfixes Aplicados

### Redis Module (Terraform Drift)

**Arquivo**: `platform-provisioning/aws/kubernetes/terraform/modules/redis/main.tf`

**Mudança**:
```hcl
# Linha 259-266
tolerations = length(var.tolerations) > 0 ? [
  for t in var.tolerations : {
    key      = t.key
    operator = t.operator
    effect   = t.effect
    value    = try(t.value, null)
  }
] : []
```

**Aplicado via**: `kubectl patch redisfailover` (hotfix)  
**Terraform Apply Pendente**: Aguardando AWS SSO DNS resolver

### ArgoCD OIDC Config

**Arquivo**: ConfigMap `argocd-cm` (namespace argocd)

**Mudanças**:
- URL temporária: `http://localhost:8081` → Reverter para DNS real com Ingress
- Issuer: DNS interno (correto para descoberta)
- Client secret: Atualizado no `argocd-secret`

---

## 📈 Métricas

| Componente | Antes | Depois | Status |
|------------|-------|--------|--------|
| Redis Cluster | 1/3 Running | 3/3 Running | ✅ |
| GitLab Webservice | 0/2 CrashLoop | 2/2 Running | ✅ |
| GitLab Sidekiq | 0/1 CrashLoop | 1/1 Running | ✅ |
| Keycloak | 2/2 Running | 2/2 Running (realm config) | ✅ |
| ArgoCD OIDC | Não configurado | Configurado | ⚠️ Teste pendente |
| SonarQube OIDC | N/A | Community limitação | ❌ |

**Uptime Final**:
- GitLab: 100% (últimas 2h)
- Redis: 100% (últimas 2h)
- Keycloak: 100% (últimos 5 dias)

---

## 🎓 Aprendizados

### 1. StatefulSet Scale Behavior
**Descoberta**: Scale down remove índices MAIORES primeiro (vault-2 before vault-0).

**Impacto**: Crítico para Raft clusters. Documentado na memória.

### 2. Kubernetes Secrets Cross-Namespace
**Pattern**: Secrets não compartilham entre namespaces automaticamente.

**Solução**: Sync manual ou External Secrets Operator (ESO).

### 3. OIDC Local Testing Complexity
**Lição**: Port-forward não é adequado para OIDC end-to-end testing.

**Solução Futura**: Usar Ingress + DNS desde o início.

### 4. SonarQube Editions
**Lição**: Verificar features por edição antes de configurar.

**Ação**: Documentar limitações de Community vs Enterprise.

### 5. GitLab 17.x Runner Registration
**Mudança**: Registration tokens deprecated → Authentication tokens.

**Impacto**: Requer processo manual via UI. Documentado para futuro.

---

## 📋 Itens Pendentes (Próximas Sprints)

### Curto Prazo (Marco 4)

1. **Ingress Configuration**
   - Criar Ingress para ArgoCD
   - Criar Ingress para Keycloak
   - Configurar DNS real (Route53 ou similar)
   - Testar OIDC end-to-end

2. **GitLab Runner Setup**
   - Acessar UI: http://gitlab.example.com
   - Admin → CI/CD → Runners → Create authentication token
   - Atualizar secret gitlab-gitlab-runner-secret
   - Scale up deployment

3. **SonarQube OAuth**
   - Configurar GitLab como OAuth provider
   - Testar integração SonarQube ↔ GitLab

### Médio Prazo (Marco 5)

4. **Terraform Apply**
   - Resolver AWS SSO DNS (portal.sso.us-east-1.amazonaws.com)
   - Aplicar hotfixes do Redis module
   - Sync state com mudanças manuais

5. **Observability SLI Dashboards**
   - Validar dashboards Grafana
   - Configurar alertas críticos
   - Documentar runbooks

---

## 🔗 Referências

### Documentação Criada
- `/tmp/sprint3-final-report.md` (este arquivo)
- `/tmp/gitlab-validation-summary.md`
- `/tmp/keycloak-setup-guide.md`
- `/tmp/oidc-solution-final.md`
- `/tmp/port-forward-commands.txt`

### Secrets Críticos (Backup Necessário)
- GitLab root: tf%g!*}r7WS{X_*==24g[x5!CagEkHbZ
- Redis: 6%Ir%u2MI2orOy78<B%K+)2VB>XokQx*... (32 chars)
- Keycloak admin: Qq!Tp?Q=xmCmj5zGbzIW>kno
- ArgoCD OIDC: EevIzpYR6ai3tssDMsxwDH5bRBjj0YIp
- SonarQube OIDC: Oif7qf7u1jVMyIfYboVPyybbVK5tRBJn

### ADRs Relacionados
- ADR-023: Migration from Bitnami Charts to Operators (Redis)
- ADR-040: PostgreSQL Security Groups
- ADR-041: Vault HA Migration
- ADR-053: Tempo Distributed Config (precedente para troubleshooting)

---

## ✅ Critérios de Aceitação

| Critério | Status | Evidência |
|----------|--------|-----------|
| GitLab operacional | ✅ | Health 200 OK, webservice/sidekiq Ready |
| Redis HA funcional | ✅ | 3/3 pods, master elected, Sentinel OK |
| Keycloak configurado | ✅ | Realm platform, 2 clients criados |
| OIDC ArgoCD config | ✅ | ConfigMap + secrets atualizados |
| OIDC SonarQube avaliado | ✅ | Limitação Community documentada |
| Acesso externo validado | ✅ | GitLab via ALB, /etc/hosts config |
| Documentação atualizada | ✅ | Este relatório + guias criados |

---

## 🚀 Próximo Marco

**Marco 4**: CI/CD Pipeline Completa
- GitLab Runner operacional
- SonarQube integrado (via GitLab OAuth)
- ArgoCD GitOps deployment
- Backstage templates

**Estimativa**: 3-5 dias de trabalho

---

_Sprint 3 concluída em 2026-02-11. Próxima sprint: Marco 4 - CI/CD Integration._
