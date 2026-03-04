# ADR-092 — GitLab Version Upgrade Strategy

**Data:** 2026-03-03
**Status:** Implementado
**Decider:** Gilvan Galindo (Platform Architect)
**Contexto:** Upgrade GitLab CE v17.7.0 → v18.9.1 (9 minor versions, 9 breaking changes)
**Demanda:** INFRA-001

---

## Contexto

GitLab v17.7.0 (chart 8.7.0) estava em operacao desde 2026-02-13, aproximadamente 14 meses
defasado em relacao a release corrente v18.9.1. O upgrade era necessario por:

- **Security patches criticos acumulados** — 14 meses de CVEs sem aplicacao
- **Runner authentication token (17.x+)** — compatibilidade com fluxo glrt- obrigatoria
- **PostgreSQL 16 upgrade (INFRA-002 prerequisite)** — GitLab 18.x requer PG >= 16
- **Enterprise maturity target: 4.5/5.0** — manutencao de versao suportada

O upgrade foi executado em 2026-03-02 e 2026-03-03, atingindo v18.9.1 (chart 9.9.1, Revision 36)
com todos os 11 pods Running.

---

## Constraint: Upgrade Path Obrigatorio

GitLab NAO suporta pular minor versions. Cada minor version deve ser upgradada sequencialmente.
Referencia: https://docs.gitlab.com/ee/update/

Esta constraint e valida tanto para o GitLab application version quanto para o Helm chart version
(que segue versionamento paralelo: chart 8.x = GitLab 17.x, chart 9.x = GitLab 18.x).

---

## Decisao: Helm Sequential Upgrade com Breaking Change Registry

**Principio:** Um step por vez, aguardar 11/11 pods Running antes do proximo step.
Cada upgrade intermediario e uma oportunidade de descoberta e documentacao de breaking changes.

**Alternativas consideradas:**

| Alternativa | Razao da rejeicao |
|-------------|-------------------|
| Fresh install v18.9.1 | Perda de dados/secrets/estado acumulado — inaceitavel |
| Pular minor versions | Proibido pelo GitLab (docs oficiais) |
| Upgrade unico multi-version | Causa estado inconsistente irrecuperavel no Helm |

---

## Upgrade Path Executado

| Step | Chart  | GitLab   | Revision | Status          | Observacoes Criticas |
|------|--------|----------|----------|-----------------|----------------------|
| 0    | 8.7.0  | 17.7.0   | 2        | ORIGEM          | Estado inicial |
| 1    | 8.8.7  | 17.8.7   | 5        | COMPLETO        | PVC Gitaly Lost + job stale fix |
| 2    | 8.9.8  | 17.9.8   | 12       | COMPLETO        | Sem breaking changes |
| 3    | 8.10.8 | 17.10.8  | 13       | COMPLETO        | `cell.enabled: false` obrigatorio |
| 4    | 8.11.8 | 17.11.7  | 18       | COMPLETO        | `oidcProvider` obrigatorio + rollback stale jobs |
| 5    | 9.0.6  | 18.0.6   | -        | COMPLETO        | MAJOR: openbao+workspaces+ciIdTokens |
| 6    | 9.2.8  | 18.2.8   | -        | COMPLETO        | 2 retries por timeout |
| 7    | 9.5.5  | 18.5.5   | -        | COMPLETO        | `relativeUrlRoot: ""` fix |
| 8    | 9.8.x  | 18.8.x   | SKIPPED  | SKIPPED         | Bug envoy-gateway nil pointer — confirmado skip seguro |
| 9    | 9.9.1  | 18.9.1   | 36       | COMPLETO (FINAL) | 11/11 pods Running |

**Total:** 9 steps efetivos, 1 step pulado (bug confirmado upstream).

---

## Breaking Changes Registry (9 Descobertos e Resolvidos)

### BC-001: `relativeUrlRoot` nil Go template corrompe KAS URI

**Versao afetada:** chart 9.5.x (GitLab 18.4+)
**Sintoma:**
```
KAS URI validation failed: "gitlab.external_url: value must be a valid URI"
external_url = "http://gitlab.staging.internal%!s(<nil>)"
```
**Root cause:** O template Helm Go usa `relativeUrlRoot` sem default. Quando ausente das values,
Go renderiza `%!s(<nil>)` literalmente na URL.
**Fix aplicado em values-staging-working.yaml:**
```yaml
global:
  appConfig:
    relativeUrlRoot: ""
```
**Referencia:** Helm chart 9.5.x changelog — template expression bug

---

### BC-002: `global.openbao.enabled` — substituiu HashiCorp Vault no 18.x

**Versao afetada:** chart 9.0.x (GitLab 18.0+)
**Sintoma:** Template errors ao renderizar subcharts de Vault/OpenBao.
**Root cause:** GitLab 18.x substituiu HashiCorp Vault pelo OpenBao (fork open-source).
O subchart agora referencia `global.openbao` e falha se nao configurado.
**Fix aplicado:**
```yaml
global:
  openbao:
    enabled: false

# Tambem necessario: OpenBao host (mesmo quando disabled)
global:
  hosts:
    openbao:
      name: openbao.staging.internal
      https: false

# Subchart top-level
openbao:
  install: false
```

---

### BC-003: `global.workspaces.enabled` — novo subchart com erros

**Versao afetada:** chart 9.0.x (GitLab 18.0+)
**Sintoma:** CrashLoopBackOff no workspaces subchart durante startup.
**Root cause:** Feature Workspaces introduzida no 18.x como subchart. Falha se nao
explicitamente desabilitada em ambientes sem o agente de workspaces configurado.
**Fix aplicado:**
```yaml
global:
  workspaces:
    enabled: false
```

---

### BC-004: `global.gatewayApi.enabled` — nil pointer em httproute.yaml

**Versao afetada:** chart 9.8.x+ (GitLab 18.8+)
**Sintoma:**
```
Error: template: gitlab/templates/gitlab/gateway/httproute.yaml:15:22:
executing "gitlab/templates/gitlab/gateway/httproute.yaml" at <.Values.global.gatewayApi.gatewayRef.name>:
nil pointer evaluating interface {}.name
```
**Root cause:** O template `httproute.yaml` foi adicionado no chart 9.8.x com referencias
a `gatewayApi.gatewayRef.name` sem guards de nil check. Mesmo com `enabled: false`, o
template ainda avalia as referencias.
**Fix aplicado:**
```yaml
global:
  gatewayApi:
    enabled: false
    installEnvoy: false
    gatewayRef:
      name: ""
      namespace: ""
    class:
      name: "gitlab-gw"
```

---

### BC-005: `global.gatewayApi.gatewayRef.name/namespace` — obrigatorio mesmo quando disabled

**Versao afetada:** chart 9.9.x (GitLab 18.9+)
**Sintoma:** Mesmo com `gatewayApi.enabled: false`, o template falha se `gatewayRef` ausente.
**Root cause:** Bug no template — valores sao avaliados antes do check de `enabled`.
**Fix:** Incluido em BC-004 (mesmo fix cobre ambos).

---

### BC-006: `global.gatewayApi.class.name` — template requer valor

**Versao afetada:** chart 9.9.x (GitLab 18.9+)
**Sintoma:** Template rendering failure por valor nil em `class.name`.
**Root cause:** O template `gitlab-gw` e o valor default esperado pelo chart, mas nao
e definido automaticamente quando `gatewayApi.enabled: false`.
**Fix:** Incluido em BC-004 (mesmo fix cobre ambos com `class.name: "gitlab-gw"`).

---

### BC-007: `global.appConfig.cell.enabled` — chart 8.10.x desabilita por default incorretamente

**Versao afetada:** chart 8.10.x (GitLab 17.10.x)
**Sintoma:** Subchart cell falha ao tentar inicializar sem configuracao.
**Root cause:** O chart 8.10.x introduziu o feature flag `cell` mas nao definiu default `false`
de forma confiavel. A ausencia da chave nas user values causava comportamento imprevisivel.
**Fix aplicado:**
```yaml
global:
  appConfig:
    cell:
      enabled: false
```

---

### BC-008: `global.appConfig.oidcProvider.*` — obrigatorio no chart 8.11.x

**Versao afetada:** chart 8.11.x (GitLab 17.11.x)
**Sintoma:** Template rendering failure por campos de oidcProvider ausentes.
**Root cause:** Chart 8.11.x adicionou subcampos de oidcProvider como obrigatorios no template,
sem defaults retrocompativeis.
**Fix aplicado:**
```yaml
global:
  appConfig:
    oidcProvider:
      openidIdTokenExpireInSeconds: 120
```

---

### BC-009: `global.appConfig.ciIdTokens.issuerUrl` — explicito no 18.x

**Versao afetada:** chart 9.0.x (GitLab 18.0+)
**Sintoma:** CI/CD ID tokens invalidos — issuerUrl nao configurado causa falha na validacao JWT.
**Root cause:** GitLab 18.x tornou o campo `ciIdTokens.issuerUrl` obrigatorio (antes era inferido
automaticamente). Ausencia causa tokens com issuer invalido.
**Fix aplicado:**
```yaml
global:
  appConfig:
    ciIdTokens:
      issuerUrl: "https://gitlab.staging.internal"
```

---

## Runner Configuration — 3 Root Causes

### RC-1: `runnerRegistrationToken: ""` — isAuthToken=true

**Problema:** O template Helm do GitLab Runner avalia `isAuthToken` baseado na **presenca** da
chave `runnerRegistrationToken` nas values. Quando a chave estava ausente, o template assumia
`isAuthToken=false` e gerava `REGISTER_LOCKED=false` nas env vars. Esta flag e incompativel
com authentication token (glrt-) e causava FATAL error no registro.

**Fix:**
```yaml
gitlab-runner:
  runnerRegistrationToken: ""  # Chave presente (mesmo que vazia) -> isAuthToken=true -> sem REGISTER_LOCKED
```

**Mecanismo:** O token real (`glrt-...`) permanece no secret `gitlab-gitlab-runner-secret`
na key `runner-token`, gerenciado pelo job `shared-secrets` do chart.

---

### RC-2: `gitlabUrl` porta explicita sem nginx-ingress

**Problema:** O valor computado padrao para `CI_SERVER_URL` aponta para porta 80, mas o
nginx-ingress estava desabilitado no ambiente staging. O GitLab Workhorse escuta na porta `:8181`.

**Fix:**
```yaml
gitlab-runner:
  gitlabUrl: "http://gitlab.staging.internal:8181"
```

---

### RC-3: `global.gitlabVersion` — evitar imagens stuck

**Problema:** O parametro `--reuse-values` do Helm nao garante que `global.gitlabVersion` sera
atualizado se o valor estava cached de uma revision anterior. Pods continuavam puxando imagens
da versao anterior apos o upgrade do chart.

**Fix:** Especificar `global.gitlabVersion` explicitamente nas values e no comando de upgrade:
```yaml
global:
  gitlabVersion: "18.9.1"  # Atualizar a cada upgrade step
```

```bash
helm upgrade gitlab gitlab/gitlab \
  --version <NEW_CHART_VERSION> \
  --reuse-values \
  --set global.gitlabVersion=<NEW_APP_VERSION>
```

---

## Incidentes Durante o Upgrade

### Incidente 1: PVC Gitaly Lost (Step 1)

**Causa:** PVC `repo-data-gitlab-gitaly-0` estava em estado `Lost` ha 18 dias (PV nao existia mais).
**Resolucao:**
```bash
kubectl delete pvc repo-data-gitlab-gitaly-0 -n gitlab-staging
kubectl delete job gitlab-gitlab-upgrade-check -n gitlab-staging  # job stale
helm upgrade gitlab gitlab/gitlab -n gitlab-staging --version 8.8.7 \
  --reuse-values --set global.gitlabVersion=17.8.7 --timeout 10m --wait
```
**Resultado:** Novo PVC gp3 50Gi criado pelo chart automaticamente.

### Incidente 2: Jobs Stale Bloqueando Rollback (Step 4)

**Causa:** Revision 15 ficou em estado `pending-upgrade`. Jobs com imagem `v17.11.8` inexistente
bloqueavam o rollback.
**Resolucao:**
```bash
kubectl delete job gitlab-gitlab-upgrade-check gitlab-issuer-fe132fa -n gitlab-staging
helm rollback gitlab 14 -n gitlab-staging --wait  # Resultado: Rev 17
kubectl delete job gitlab-issuer-d39acef -n gitlab-staging  # Job com v17.11.8
helm upgrade gitlab gitlab/gitlab -n gitlab-staging --version 8.11.8 \
  --reuse-values --set 'global.gitlabVersion=17.11.7' --timeout 12m --wait  # Rev 18
```

### Incidente 3: Skip do Chart 9.8.x

**Causa:** Bug envoy-gateway nil pointer no chart 9.8.x causava falha irrecuperavel durante
o upgrade. O bug foi identificado como conhecido upstream.
**Decisao:** Skip direto de 9.5.5 para 9.9.1 confirmado como seguro apos pesquisa no changelog.
**Referencia:** GitLab Helm chart issue tracker — envoy-gateway nil pointer 9.8.x.

---

## Procedimento Padrao para Proximos Upgrades

### Pre-upgrade checklist

- [ ] Snapshot RDS `gitlab` database (AWS Console ou Terraform)
- [ ] Verificar GitLab upgrade path obrigatorio: https://gitlab-com.gitlab.io/support/toolbox/upgrade-path/
- [ ] Checar breaking changes no CHANGELOG do chart: https://gitlab.com/gitlab-org/charts/gitlab/-/blob/master/CHANGELOG.md
- [ ] Backup do values file: `helm get values gitlab -n gitlab-staging > /tmp/gitlab-values-backup-$(date +%Y%m%d).yaml`
- [ ] Verificar se versao alvo requer PostgreSQL superior ao atual

### Comando de upgrade (template)

```bash
helm upgrade gitlab gitlab/gitlab \
  --version <NEW_CHART_VERSION> \
  --namespace gitlab-staging \
  --reuse-values \
  --set global.gitlabVersion=<NEW_APP_VERSION> \
  -f platform-provisioning/aws/kubernetes/terraform/modules/gitlab/values-staging-working.yaml \
  --timeout 600s \
  --wait
```

**Nota:** O parametro `-f values-staging-working.yaml` garante que todos os overrides de
breaking changes sao aplicados mesmo apos `--reuse-values`.

### Validacao pos-upgrade

```bash
# Aguardar 11/11 pods Running antes de prosseguir para proximo step
kubectl get pods -n gitlab-staging --watch

# Verificar versao deployada
helm list -n gitlab-staging

# Verificar runner online
kubectl logs -n gitlab-staging deploy/gitlab-gitlab-runner --tail=20
```

### Rollback (se necessario)

```bash
# Listar revisions disponiveis
helm history gitlab -n gitlab-staging

# Limpar jobs stale antes do rollback (previne bloqueio)
kubectl delete jobs -n gitlab-staging -l app=gitlab-upgrade-check 2>/dev/null || true

# Executar rollback
helm rollback gitlab <PREVIOUS_REVISION> -n gitlab-staging --wait --timeout 600s

# Verificar estado apos rollback
helm list -n gitlab-staging
kubectl get pods -n gitlab-staging
```

### Limpeza pos-rollback/upgrade

```bash
# Remover jobs stale (comuns apos upgrades parcialmente aplicados)
kubectl delete jobs -n gitlab-staging \
  $(kubectl get jobs -n gitlab-staging --no-headers | grep -v Running | awk '{print $1}') \
  2>/dev/null || true
```

---

## Licoes Aprendidas

1. **Nunca usar `--force` com GitLab chart:** Jobs e PVCs sao imutaveis. O `--force` tenta
   recriar objetos e falha invariavelmente.

2. **`--set global.gitlabVersion=X.Y.Z` e obrigatorio em cada step:** `--reuse-values` sozinho
   nao garante que a versao de imagem sera atualizada se o valor foi cached de revision anterior.

3. **Job stale bloqueia pre-upgrade hook:** O job `gitlab-gitlab-upgrade-check` em estado Failed
   deve ser deletado antes de qualquer retry de `helm upgrade`.

4. **Dry-run nao detecta tudo:** O erro de CPU requests > limits no webservice container nao
   foi capturado pelo dry-run — apenas na aplicacao real.

5. **Rollback pode avançar estado:** O rollback do Helm nao necessariamente volta para a versao
   anterior — depende do historico de revisions. Verificar sempre antes de executar.

6. **`runnerRegistrationToken: ""` (chave vazia) vs ausente:** A presenca da chave, mesmo vazia,
   muda o comportamento do template Helm — afeta `isAuthToken` evaluation.

7. **CI_SERVER_URL porta explicita obrigatoria sem nginx-ingress:** Nunca assumir porta 80 padrao
   em ambiente minimal sem ingress controller.

8. **Bugs conhecidos no chart:** Chart 9.8.x tinha bug envoy-gateway. Sempre verificar issues
   abertas no repositorio do chart antes de cada upgrade.

---

## Consequencias

### Positivas

- GitLab atualizado para ultima versao estavel (v18.9.1, Rev 36)
- 11/11 pods Running em producao (staging)
- 9 breaking changes documentados como referencia futura — acelera proximos upgrades
- Runner online com authentication token (glrt-) — fluxo moderno sem legacy registration
- Processo reproduzivel e documentado para equipe

### Negativas

- Upgrade sequencial e lento (~8h para 9 steps)
- Breaking changes podem surgir a cada minor version — requer atencao ao CHANGELOG

### Riscos Residuais

- Chart 9.8.x contem bug envoy-gateway (skip confirmado — nao e bloqueador atual)
- Proximo upgrade major (10.x): verificar se requer migracao DB adicional
- `global.gitlabVersion` deve ser atualizado a cada upgrade — risco de imagens desatualizadas

---

## Arquivos Modificados

| Arquivo | Mudanca |
|---------|---------|
| `platform-provisioning/aws/kubernetes/terraform/modules/gitlab/variables.tf` | `default = "9.9.1"` |
| `platform-provisioning/aws/kubernetes/terraform/environments/staging/main.tf` | `gitlab_version = "9.9.1"` |
| `platform-provisioning/aws/kubernetes/terraform/modules/gitlab/values-staging-working.yaml` | 9 overrides breaking changes |

---

## Estado Final (2026-03-03)

```
Helm Release : gitlab | Revision 36 | Chart gitlab-9.9.1 | App Version v18.9.1
Namespace    : gitlab-staging
Status       : deployed

Pods (11/11 Running):
gitlab-gitaly-0                              1/1  Running
gitlab-gitlab-exporter-*                     1/1  Running
gitlab-gitlab-runner-*                       1/1  Running
gitlab-gitlab-shell-* (x2)                  2/2  Running
gitlab-kas-* (x2)                            2/2  Running
gitlab-minio-*                               1/1  Running
gitlab-sidekiq-all-in-1-v2-*                 1/1  Running
gitlab-toolbox-*                             1/1  Running
gitlab-webservice-default-* (2 containers)   2/2  Running
```

---

## Links

- Logbook upgrade: `docs/logbook/2026-03-02-infra-001-gitlab-upgrade.md`
- Demanda INFRA-001: `docs/demands-backlog.md` (secao INFRA-001)
- Values file: `platform-provisioning/aws/kubernetes/terraform/modules/gitlab/values-staging-working.yaml`
- GitLab Upgrade Path Tool: https://gitlab-com.gitlab.io/support/toolbox/upgrade-path/
- GitLab Helm Upgrade Docs: https://docs.gitlab.com/charts/installation/upgrade.html
- GitLab Helm Chart Changelog: https://gitlab.com/gitlab-org/charts/gitlab/-/blob/master/CHANGELOG.md
