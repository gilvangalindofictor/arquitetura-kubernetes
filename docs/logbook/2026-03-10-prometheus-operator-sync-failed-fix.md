# Logbook: PrometheusOperatorSyncFailed — Fix AlertmanagerConfig Secret Name

**Data:** 2026-03-10
**Tipo:** Incidente / Fix
**Severidade:** P1 (alerta FIRING em producao de monitoramento)
**Status:** RESOLVIDO — aguardando `kubectl apply`
**Componentes:** Alertmanager, PrometheusOperator, AlertmanagerConfig CRD, DT-005

---

## 1. Descricao do Incidente

**Alerta recebido:**
```
[FIRING] PrometheusOperatorSyncFailed
Namespace: staging-observability-monitoring
```

O PrometheusOperator nao conseguia sincronizar a configuracao do Alertmanager porque o CRD `AlertmanagerConfig` referenciava um secret inexistente: `alertmanager-teams-webhook`.

O secret correto no namespace e `alertmanager-slack-webhook` (criado via ESO + Vault, persistido com nome legado pre-migracao DT-005).

---

## 2. Root Cause Analysis

**Causa raiz:** Inconsistencia no nome do secret apos migracao Slack→Teams (DT-005).

Durante a migracao DT-005 (2026-03-09), 308+ referencias foram atualizadas de Slack para Teams. O arquivo `dt005-alertmanager-config-crd.yaml` teve seu conteudo de payload atualizado (`slackConfigs`→`msteamsConfigs`, `apiURL`→`webhookUrl`), mas o **nome do secret referenciado** foi alterado de `alertmanager-slack-webhook` para `alertmanager-teams-webhook`.

O secret `alertmanager-teams-webhook` nunca foi criado no cluster. O secret existente continua sendo `alertmanager-slack-webhook` (contendo o webhook Teams, apesar do nome legado).

**Cadeia causal:**
```
DT-005 migra payload Slack→Teams
  ↓
Renomeia secret ref: slack-webhook → teams-webhook
  ↓
Secret teams-webhook nao existe no cluster
  ↓
PrometheusOperator falha ao montar config do Alertmanager
  ↓
[FIRING] PrometheusOperatorSyncFailed
```

**Arquivo com bug:**
```
domains/observability/infra/alerts/dt005-alertmanager-config-crd.yaml
```

**4 receivers afetados** (todos com `secretKeyRef.name: alertmanager-teams-webhook`):
- `teams-critical`
- `teams-warning`
- `teams-finops`
- `teams-security`

---

## 3. Fix Aplicado

**Substituicao em 4 receivers no CRD:**

```yaml
# ANTES (incorreto — secret nao existe)
secretKeyRef:
  name: alertmanager-teams-webhook
  key: webhookUrl

# DEPOIS (correto — secret existente no cluster)
secretKeyRef:
  name: alertmanager-slack-webhook
  key: webhookUrl
```

**Arquivo alterado:**
```
domains/observability/infra/alerts/dt005-alertmanager-config-crd.yaml
```

---

## 4. Comando para Aplicar o Fix

```bash
kubectl apply -f domains/observability/infra/alerts/dt005-alertmanager-config-crd.yaml \
  -n staging-observability-monitoring

# Verificar sincronizacao (aguardar ~30s):
kubectl get alertmanagerconfig -n staging-observability-monitoring
kubectl describe alertmanagerconfig -n staging-observability-monitoring

# Confirmar que alerta nao esta mais firing:
# Acessar Alertmanager UI ou verificar no Teams
```

**Verificacao pos-apply esperada:**
- `kubectl get alertmanagerconfig` retorna STATUS `Ready`
- PrometheusOperator logs sem erros de sync
- Alerta `PrometheusOperatorSyncFailed` para de disparar

---

## 5. Impacto

| Item | Valor |
|------|-------|
| Duracao do incidente | Durante sessao 2026-03-10 |
| Alertas afetados | 4 receivers Teams (critical, warning, finops, security) |
| Entrega de alertas durante incidente | DEGRADADA — sem entrega via Teams |
| Dados perdidos | Nenhum — Prometheus coletou normalmente |
| Fix aplicado em | dt005-alertmanager-config-crd.yaml |
| Requer restart | Nao — `kubectl apply` suficiente |

---

## 6. Licao Aprendida

**Regra critica pos-migracao de secrets:**

Ao executar qualquer migracao que altere **nomes de secrets** (mesmo que apenas renomeie o secret de destino), e obrigatorio:

1. Auditar TODOS os CRDs que referenciam o secret por nome (`secretKeyRef.name`)
2. Verificar `AlertmanagerConfig`, `ExternalSecret`, `SecretStore`, `Ingress` com TLS, etc.
3. Garantir que o secret com o novo nome EXISTE no cluster antes de aplicar o CRD
4. Ou manter o nome do secret existente e apenas atualizar o conteudo (chaves/valores)

**Checklist pos-migracao DT-style:**
```bash
# Buscar referencias ao secret antigo em todos os CRDs aplicados:
grep -r "secretKeyRef" domains/ | grep -v ".git"

# Verificar secrets existentes no namespace afetado:
kubectl get secrets -n staging-observability-monitoring | grep -E "slack|teams|webhook"

# Confirmar que PrometheusOperator esta sincronizado:
kubectl logs -n staging-observability-monitoring \
  deployment/kube-prometheus-stack-operator | grep -i "error\|sync" | tail -20
```

---

## 7. Artefatos Relacionados

| Artefato | Localizacao |
|----------|-------------|
| CRD corrigido | `domains/observability/infra/alerts/dt005-alertmanager-config-crd.yaml` |
| Logbook DT-005 | `docs/logbook/` (commits 2026-03-09) |
| Secret existente | `alertmanager-slack-webhook` em `staging-observability-monitoring` |
| Vault path | `secret/alertmanager/teams-webhook` |

---

**Preparado por:** Documentation Specialist
**Revisado por:** Platform Team
**Proximo passo:** `kubectl apply` do CRD corrigido + verificar alerta RESOLVED no Alertmanager

---

## Resolução Final — 2026-03-10 18:38

**Status:** RESOLVIDO ✅

**Ação executada:**

- Vault path correto identificado: `secret/monitoring/alertmanager` (não `secret/alertmanager/teams-webhook`)
- URL Microsoft Teams populada em 4 keys (mesmo URL para todas):
  - `critical_webhook_url`, `warning_webhook_url`, `data_services_webhook_url`, `security_webhook_url`
  - URL: `https://fctconsig.webhook.office.com/webhookb2/...` (fctconsig tenant)
- ESO resincronizado via `force-sync` annotation
- Root token Vault gerado (3/5 recovery keys) e REVOGADO após uso

**Resultado:**

- Alertmanager: `RECONCILED=True`, `AVAILABLE=True`
- PrometheusOperatorSyncFailed: CLEARED
- Alertas Teams: OPERACIONAIS

**Correção de documentação:**

- `MEMORY.md` registrava Vault path como `secret/alertmanager/teams-webhook` — path real é `secret/monitoring/alertmanager`
- Keys usam underscore (não hífen): `critical_webhook_url` (não `critical-webhook-url`)
