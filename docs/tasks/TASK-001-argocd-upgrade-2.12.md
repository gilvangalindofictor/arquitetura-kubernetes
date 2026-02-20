# TASK-001: Upgrade ArgoCD 2.9.3 → 2.12+ com PKCE Support

**Prioridade:** 🔴 CRÍTICA
**Estimativa:** 4-6 horas
**Responsável:** TBD
**Criado:** 2026-02-12
**Devido:** 2026-02-19 (1 semana)
**Dependências:** Nenhuma
**Bloqueios:** Nenhum

---

## 📋 Contexto

**Problema Atual:**
- ArgoCD v2.9.3 (Dec 2023) não suporta PKCE (Proof Key for Code Exchange)
- Keycloak OIDC client "argocd" configurado **SEM PKCE** para backward compatibility
- Reduz segurança da autenticação OAuth 2.0 (vulnerável a auth code interception)

**Motivação:**
- PKCE é obrigatório em OAuth 2.1 (RFC 7636)
- ArgoCD v2.10.0+ (Feb 2024) tem PKCE nativo
- Latest stable: v2.12.x (Jan 2025) com múltiplas security fixes

**Referências:**
- [ArgoCD PKCE PR](https://github.com/argoproj/argo-cd/pull/12234) - Implementação v2.10.0
- [Logbook OIDC Fix](../logbook/2026-02-12-keycloak-oidc-integration-troubleshooting.md) - Decisão PKCE desabilitado
- [MEMORY.md Pattern](/.claude/memory/MEMORY.md) - Keycloak OIDC Database NULL Values + PKCE Compatibility

---

## 🎯 Objetivos

### Objetivo Principal
Upgrade ArgoCD de v2.9.3 para v2.12+ e habilitar PKCE no Keycloak client para melhorar segurança OIDC.

### Objetivos Secundários
- [ ] Zero downtime durante upgrade (Blue-Green deployment)
- [ ] Validar todas integrações OIDC (Keycloak, GitHub, GitLab)
- [ ] Manter configurações de RBAC e applications existentes
- [ ] Atualizar documentação e runbooks

---

## 📝 Tarefas

### 1. Planejamento e Preparação (1h)

- [ ] **1.1** Revisar [ArgoCD Release Notes v2.10-v2.12](https://github.com/argoproj/argo-cd/releases)
  - Breaking changes
  - New features
  - Security fixes
  - CRD updates

- [ ] **1.2** Backup completo ArgoCD state
  ```bash
  # Backup applications
  kubectl get applications -n argocd -o yaml > backup-argocd-apps-$(date +%Y%m%d).yaml

  # Backup projects
  kubectl get appprojects -n argocd -o yaml > backup-argocd-projects-$(date +%Y%m%d).yaml

  # Backup configmaps
  kubectl get configmap -n argocd -o yaml > backup-argocd-cm-$(date +%Y%m%d).yaml

  # Backup secrets
  kubectl get secret -n argocd -o yaml > backup-argocd-secrets-$(date +%Y%m%d).yaml
  ```

- [ ] **1.3** Identificar custom resources e CRDs
  ```bash
  kubectl get crd | grep argoproj.io
  kubectl api-resources --api-group=argoproj.io
  ```

- [ ] **1.4** Verificar compatibilidade Helm chart
  - Atual: `argo-cd-5.51.6` (app v2.9.3)
  - Target: `argo-cd-7.x.x` (app v2.12.x)
  - Diff: `helm show values argo/argo-cd --version 7.x.x > values-new.yaml`

### 2. Teste em Staging (2h)

- [ ] **2.1** Deploy ArgoCD v2.12 em namespace separado
  ```bash
  # Create test namespace
  kubectl create namespace argocd-test

  # Deploy v2.12
  helm install argocd-test argo/argo-cd \
    --namespace argocd-test \
    --version 7.x.x \
    --values values-test.yaml
  ```

- [ ] **2.2** Configurar OIDC com PKCE no teste
  ```yaml
  # values-test.yaml
  configs:
    cm:
      url: http://argocd-test.staging.internal
      oidc.config: |
        name: Keycloak
        issuer: http://keycloak.staging.internal/auth/realms/platform
        clientID: argocd-test
        clientSecret: $oidc.keycloak.clientSecret
        requestedScopes: [openid, profile, email, roles]
  ```

- [ ] **2.3** Criar client Keycloak "argocd-test" com PKCE S256
  ```sql
  -- Via Terraform (preferido) ou SQL
  INSERT INTO client_attributes (client_id, name, value)
  VALUES (
    (SELECT id FROM client WHERE client_id = 'argocd-test'),
    'pkce.code.challenge.method',
    'S256'
  );
  ```

- [ ] **2.4** Testar login OIDC com PKCE
  - [ ] Acesso: http://argocd-test.staging.internal
  - [ ] Login via Keycloak
  - [ ] Verificar logs: `kubectl logs -n argocd-test -l app.kubernetes.io/name=argocd-server`
  - [ ] Validar PKCE parameters em URL: `code_challenge`, `code_challenge_method=S256`

- [ ] **2.5** Smoke tests funcionalidades críticas
  - [ ] Sync application
  - [ ] Create new application
  - [ ] RBAC enforcement
  - [ ] Webhooks GitLab/GitHub

### 3. Upgrade Production (1-2h)

- [ ] **3.1** Change Window: Agendar janela de manutenção (off-hours)
  - Data: ___________
  - Horário: 02:00-04:00 BRT (low traffic)
  - Comunicar: CTO, DevOps team

- [ ] **3.2** Pre-upgrade checklist
  - [ ] Backup completo realizado (Task 1.2)
  - [ ] Teste em staging bem-sucedido (Task 2.4)
  - [ ] Database PostgreSQL backup (se usar external DB)
  - [ ] Git push de todos valores Helm

- [ ] **3.3** Executar upgrade Helm
  ```bash
  # Get current values
  helm get values argocd -n argocd > values-current.yaml

  # Merge with new values (PKCE config)
  # Edit values-current.yaml...

  # Upgrade (dry-run first)
  helm upgrade argocd argo/argo-cd \
    --namespace argocd \
    --version 7.x.x \
    --values values-current.yaml \
    --dry-run

  # Actual upgrade
  helm upgrade argocd argo/argo-cd \
    --namespace argocd \
    --version 7.x.x \
    --values values-current.yaml \
    --wait --timeout 10m
  ```

- [ ] **3.4** Monitorar rollout
  ```bash
  # Watch pods
  kubectl get pods -n argocd -w

  # Check deployment status
  kubectl rollout status deployment/argocd-server -n argocd
  kubectl rollout status deployment/argocd-repo-server -n argocd
  kubectl rollout status statefulset/argocd-application-controller -n argocd

  # Check logs
  kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=100 -f
  ```

- [ ] **3.5** Validar health
  - [ ] UI acessível: http://argocd.staging.internal
  - [ ] Applications sincronizadas
  - [ ] Webhooks funcionais
  - [ ] Metrics endpoint: http://argocd-server:8083/metrics

### 4. Habilitar PKCE no Keycloak (30min)

- [ ] **4.1** Atualizar client "argocd" com PKCE S256
  ```sql
  -- Via Terraform (PREFERIDO - ver TASK-002)
  -- OU via SQL temporário:
  INSERT INTO client_attributes (client_id, name, value)
  VALUES (
    (SELECT id FROM client WHERE client_id = 'argocd'),
    'pkce.code.challenge.method',
    'S256'
  )
  ON CONFLICT (client_id, name) DO UPDATE SET value = 'S256';
  ```

- [ ] **4.2** Restart Keycloak pod (cache flush)
  ```bash
  kubectl delete pod -n keycloak keycloak-0 --grace-period=5
  kubectl wait --for=condition=Ready pod/keycloak-0 -n keycloak --timeout=120s
  ```

- [ ] **4.3** Validar configuração
  ```sql
  -- Verificar PKCE ativo
  SELECT c.client_id, a.name, a.value
  FROM client c
  LEFT JOIN client_attributes a ON c.id = a.client_id
  WHERE c.client_id = 'argocd'
    AND a.name = 'pkce.code.challenge.method';

  -- Expected: argocd | pkce.code.challenge.method | S256
  ```

### 5. Testes Pós-Upgrade (1h)

- [ ] **5.1** Teste OIDC login com PKCE
  - [ ] Logout do ArgoCD (clear session)
  - [ ] Login via Keycloak
  - [ ] Verificar URL contém: `code_challenge=...&code_challenge_method=S256`
  - [ ] Callback bem-sucedido
  - [ ] User roles/permissions mantidos

- [ ] **5.2** Testes funcionais críticos
  - [ ] Sync 3 applications aleatórias
  - [ ] Create new application via UI
  - [ ] Create new application via CLI (`argocd app create`)
  - [ ] Trigger webhook GitLab/GitHub
  - [ ] RBAC enforcement (user sem permissão não vê apps)

- [ ] **5.3** Monitoramento 2h pós-upgrade
  ```bash
  # Logs sem erros
  kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --since=2h | grep -i error

  # Keycloak logs OIDC
  kubectl logs -n keycloak keycloak-0 --since=2h | grep argocd | grep LOGIN

  # Metrics check
  curl -s http://argocd-server.argocd:8083/metrics | grep argocd_app_sync_total
  ```

- [ ] **5.4** Performance baseline
  - [ ] Application sync time: _____ seconds (antes: ~X seconds)
  - [ ] UI load time: _____ seconds (antes: ~Y seconds)
  - [ ] Memory usage: _____ MB (antes: ~Z MB)

### 6. Documentação e Comunicação (30min)

- [ ] **6.1** Atualizar documentação
  - [ ] Logbook: `docs/logbook/2026-02-XX-argocd-upgrade-2.12.md`
  - [ ] MEMORY.md: Atualizar padrão PKCE com ArgoCD v2.12
  - [ ] Runbook: Procedimento de upgrade ArgoCD

- [ ] **6.2** Atualizar ADR-XXX (ver TASK-004)
  - Adicionar seção: "Post-Upgrade: PKCE Habilitado em 2026-02-XX"

- [ ] **6.3** Comunicar sucesso
  - [ ] Slack #devops: "ArgoCD upgrade v2.12 completo, PKCE habilitado"
  - [ ] Email CTO: Resumo upgrade + security improvements
  - [ ] Wiki: Atualizar página "Platform Services Versions"

---

## ✅ Critérios de Sucesso

- [ ] ArgoCD v2.12+ rodando em produção
- [ ] PKCE S256 habilitado no Keycloak client "argocd"
- [ ] Login OIDC funcional com PKCE parameters
- [ ] Todas applications sincronizadas sem erros
- [ ] Zero downtime durante upgrade
- [ ] Documentação atualizada
- [ ] Equipe comunicada

---

## ⚠️ Rollback Plan

### Se upgrade falhar durante Task 3:

1. **Rollback Helm**
   ```bash
   helm rollback argocd -n argocd
   ```

2. **Restaurar backups (se necessário)**
   ```bash
   kubectl apply -f backup-argocd-apps-YYYYMMDD.yaml
   kubectl apply -f backup-argocd-cm-YYYYMMDD.yaml
   ```

3. **Reverter PKCE no Keycloak**
   ```sql
   DELETE FROM client_attributes
   WHERE client_id = (SELECT id FROM client WHERE client_id = 'argocd')
     AND name = 'pkce.code.challenge.method';
   ```

4. **Restart Keycloak**
   ```bash
   kubectl delete pod -n keycloak keycloak-0
   ```

### Se PKCE causar problemas pós-upgrade:

1. **Desabilitar PKCE temporariamente** (Task 4.1 reverso)
2. **Investigar logs ArgoCD + Keycloak**
3. **Abrir issue GitHub ArgoCD** (se bug upstream)

---

## 🔗 Referências

### Documentação Oficial
- [ArgoCD v2.12 Release Notes](https://github.com/argoproj/argo-cd/releases/tag/v2.12.0)
- [ArgoCD Upgrade Guide](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/)
- [ArgoCD OIDC Configuration](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/#keycloak)
- [Helm Chart Documentation](https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd)

### Documentação Interna
- [Logbook OIDC Troubleshooting](../logbook/2026-02-12-keycloak-oidc-integration-troubleshooting.md)
- [MEMORY.md PKCE Pattern](/.claude/memory/MEMORY.md)
- TASK-002: Implementar Terraform Keycloak Provider
- TASK-003: Implementar Backup Automático Keycloak

### External Resources
- [RFC 7636 - PKCE](https://datatracker.ietf.org/doc/html/rfc7636)
- [OAuth 2.1 Draft](https://datatracker.ietf.org/doc/html/draft-ietf-oauth-v2-1-07)

---

**Status:** 📋 TODO
**Última Atualização:** 2026-02-12
**Tracking Issue:** #TBD
 
---

## Registro de Ações (resumido)

- [2026-02-20] Pre-check AWS SSO session realizado (orquestrador) — sessão ativa
- [2026-02-20] Histórico e logbook consultados — referências encontradas (v2.9.3 PKCE issue)
- [2026-02-20] `argocd_version` (Helm chart) atualizado para `7.10.0` no Terraform (preparação de upgrade)

**Status:** 📋 Em Progresso
**Última Atualização:** 2026-02-20
