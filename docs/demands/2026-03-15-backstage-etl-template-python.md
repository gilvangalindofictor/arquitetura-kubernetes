# Demanda: Template Backstage ETL/DATA Python — Originadoras, APIs Externas, Secrets e Deploy Automático EKS

**Data:** 2026-03-15
**Prioridade:** HIGH (plataforma / developer experience)
**Status:** EM ANDAMENTO — F2/F3/F4 100% CONCLUÍDAS — F1 aguarda execução (scripts prontos, cluster UP) — F5 aguarda F1
**ADRs:** ADR-104 (onboarding declarativo), ADR-047 (domínio data), ADR-048 (naming kebab-case)
**Referencias:** 2026-03-11-cicd-onboarding-manifesto-base.md, 2026-03-13-hatch-etl-onboarding-eks.md, ADR-104, ADR-047, ADR-048
**Agentes:** Orquestrador, Documentation, Security, Performance, AWS
**Marco:** Marco 2 — Self-Service Platform (Sprint S6-C+)

---

## Problema

O template `etl-service` do Backstage entrega um ponto de partida funcional, mas apresenta lacunas críticas que impedem o onboarding autônomo de serviços ETL/DATA com múltiplas fontes de dados:

1. **Originadoras ausentes**: nenhum passo no formulário do scaffolder cobre a declaração de data sources externos com autenticação JWT multi-tenant (padrão do domínio data). Developer precisa configurar manualmente após o scaffold.

2. **APIs Externas não cobertas**: o template não suporta a declaração de APIs de terceiros com os diferentes tipos de autenticação em uso na plataforma (apikey, oauth2, basic, none).

3. **Secrets externas não declarativas**: o skeleton atual não gera a seção `secretKeys` dinamicamente nem cria `ExternalSecret` CRs a partir dos inputs do formulário. Developer precisa escrever YAML Kubernetes manualmente.

4. **Skeleton sem estrutura Python**: o skeleton não entrega `src/`, `tests/`, `Dockerfile`, `docker-compose.yml`, `pyproject.toml` nem `requirements.txt`. O repositório gerado exige setup manual completo antes do primeiro commit funcional.

5. **provision.sh genérico ausente**: o skeleton não inclui script de provisionamento que leia o `manifest.yaml` e crie DB/Vault paths/ExternalSecret de forma idempotente — fluxo manual, propenso a desvios.

6. **`.gitlab-ci.yml` não configurado**: o skeleton não gera o arquivo de pipeline. Developer copia manualmente de outro repo, introduzindo divergências em relação ao template canônico da plataforma.

7. **manifest-schema.json com `additionalProperties: false` bloqueador**: o JSON Schema atual (`schemas/v1/manifest-schema.json`) rejeita qualquer campo não previsto na v1 inicial, bloqueando a adição declarativa de `externalAPIs` e `originadoras` no manifest.yaml. Este é o **GAP P0 TÉCNICO** da demanda.

---

## Objetivo

Evoluir o template ETL/DATA do Backstage para que:

- Um developer preencha um formulário com originadoras, APIs externas e secrets externas;
- O scaffolder crie o repositório GitLab com estrutura Python completa e manifesto declarativo;
- Ao fazer push para a branch `staging`, o deploy suba automaticamente no EKS criando todos os acessos internos (Vault paths, ExternalSecret, namespace) via `provision.sh` idempotente;
- 0 configuração manual pós-scaffold seja necessária para o primeiro deploy funcionar.

**Meta de tempo**: onboarding de novo serviço ETL em < 30 minutos (formulário → pods Running no EKS).

---

## Fluxo Alvo (Pós-Entrega)

```
Developer → Backstage /create → Template "ETL/DATA Python Service"
  → Passo 1-6: metadados (nome, domínio, owner, recursos, dependências)
  → Passo 7: Originadoras (array: codigo, apiUrl, authType, multiTenant, secretKeyRef)
  → Passo 8: APIs Externas (array: name, url, authType, secretKeyRef, timeout)
  → Passo 9: Secrets Externas (envVarName, vaultPath, secretProperty)
  → Scaffolder executa:
      └─ Cria repo GitLab com skeleton Python completo
      └─ Gera .platform/manifest.yaml com seções externalAPIs + originadoras
      └─ Gera .gitlab-ci.yml com 8 stages
      └─ Gera config/originadoras.yaml com Nunjucks (credenciais via env vars)
      └─ Gera scripts/provision.sh genérico
      └─ Abre MR com checklist Vault no corpo
  → Developer faz merge do MR → push para staging
  → Pipeline GitLab:
      stage validate → test → build → security-scan → quality-gate → provision → migrate → deploy
      └─ provision: executa provision.sh → cria namespace + Vault paths + ExternalSecret
      └─ deploy: helm upgrade → ArgoCD sync → pods Running
  → Resultado: serviço ETL saudável no EKS em < 30 minutos
```

---

## Escopo

23 tarefas distribuídas em 5 fases. Fases 1 e 5 requerem cluster disponível (pós-AWS-recovery). Fases 2, 3 e 4 podem ser executadas localmente.

---

## Tabela de Tarefas

| ID | Fase | Título | Arquivo Principal | Prio | Dep | Status |
|----|------|--------|-------------------|------|-----|--------|
| TAREFA-001 | F1 | GAP-VAULT-HATCH: executar vault-setup-hatch-etl.sh | `docs/plan/backstage/vault-setup-hatch-etl.sh` | P0 | Cluster | PENDENTE — script pronto, aguarda execução |
| TAREFA-002 | F1 | GAP-S6C-01: executar configmap-setup.sh | `docs/plan/backstage/configmap-setup.sh` | P0 | Cluster | PENDENTE — script pronto, aguarda execução |
| TAREFA-003 | F1 | GAP-S6C-02: helm upgrade Backstage com plugin gitlab | `docs/plan/backstage/helm-values-staging.yaml` | P0 | Cluster | PARCIAL — Backstage Running, aguarda validação pós-helm |
| TAREFA-004 | F1 | GAP-S6C-03: publicar templates no GitLab | `templates/PUBLISH-TO-GITLAB.sh` | P0 | TAREFA-003 | PENDENTE — script pronto, aguarda GITLAB_TOKEN + execução |
| TAREFA-005 | F2 | Passo 7 template — Originadoras | `templates/etl-service/template.yaml` | P1 | — | ✅ CONCLUÍDA — 2026-03-16 |
| TAREFA-006 | F2 | Passo 8 template — APIs Externas | `templates/etl-service/template.yaml` | P1 | — | ✅ CONCLUÍDA — 2026-03-16 |
| TAREFA-007 | F2 | Passo 9 template — Secrets Externas | `templates/etl-service/template.yaml` | P1 | — | ✅ CONCLUÍDA — 2026-03-16 |
| TAREFA-008 | F2 | Atualizar MR description + output com checklist Vault | `templates/etl-service/template.yaml` | P2 | TAREFA-005..007 | ✅ CONCLUÍDA — 2026-03-16 |
| TAREFA-009 | F3 | skeleton manifest.yaml — externalAPIs + originadoras + secretKeys dinâmicos | `skeleton/.platform/manifest.yaml` | P1 | TAREFA-010 | ✅ CONCLUÍDA — 2026-03-16 |
| TAREFA-010 | F3 | **[P0 BLOQUEADOR]** manifest-schema.json — adicionar externalAPIs + originadoras | `schemas/v1/manifest-schema.json` | P0 | — | ✅ CONCLUÍDA — 2026-03-16 |
| TAREFA-011 | F3 | skeleton/config/originadoras.yaml (Nunjucks) | `skeleton/config/originadoras.yaml` | P1 | TAREFA-005 | ✅ CONCLUÍDA — 2026-03-16 |
| TAREFA-012 | F3 | Estrutura Python: src/, tests/, Dockerfile, docker-compose.yml, pyproject.toml, requirements.txt | `skeleton/` | P1 | — | ✅ CONCLUÍDA — 2026-03-16 |
| TAREFA-013 | F3 | **[P0]** scripts/provision.sh genérico — lê manifest, cria DB/Vault/ExternalSecret idempotente | `skeleton/scripts/provision.sh` | P0 | TAREFA-009 | ✅ CONCLUÍDA — 2026-03-16 |
| TAREFA-014 | F3 | skeleton/catalog-info.yaml — observabilidade, links Grafana/ArgoCD/Vault, tags originadoras | `skeleton/catalog-info.yaml` | P2 | TAREFA-005..007 | ✅ CONCLUÍDA — 2026-03-16 |
| TAREFA-015 | F3 | skeleton/.gitlab-ci.yml — 8 stages, push staging = deploy | `skeleton/.gitlab-ci.yml` | P1 | TAREFA-013 | ✅ CONCLUÍDA — 2026-03-16 |
| TAREFA-016 | F4 | Documentar variáveis CI/CD obrigatórias | `skeleton/docs/ONBOARDING.md` | P2 | TAREFA-015 | ✅ CONCLUÍDA — 2026-03-16 |
| TAREFA-017 | F4 | ExternalSecret dinâmico — gerado por provision.sh para originadoras + secrets externas | `skeleton/scripts/provision.sh` | P1 | TAREFA-013 | ✅ CONCLUÍDA — 2026-03-16 |
| TAREFA-018 | F4 | skeleton/docs/ONBOARDING.md — fluxo completo pós-scaffold | `skeleton/docs/ONBOARDING.md` | P2 | TAREFA-015..017 | ✅ CONCLUÍDA — 2026-03-16 |
| TAREFA-019 | F4 | skeleton/helm/values.yaml — values genérico + staging overlay | `skeleton/helm/values.yaml` | P1 | TAREFA-009 | ✅ CONCLUÍDA — 2026-03-16 |
| TAREFA-020 | F5 | Atualizar ConfigMap platform-manifest-schema no cluster | cluster: `staging-platform-backstage` | P0 | Cluster, TAREFA-010 | ⏳ AGUARDA CLUSTER |
| TAREFA-021 | F5 | Republicar templates atualizados no GitLab backstage-catalog | GitLab: `platform/backstage-catalog` | P0 | TAREFA-020 | ⏳ AGUARDA CLUSTER |
| TAREFA-022 | F5 | Teste E2E scaffold — criar app test-etl-smoketest via template | Backstage /create | P0 | TAREFA-021 | ⏳ AGUARDA CLUSTER |
| TAREFA-023 | F5 | Teste deploy — push para staging, verificar pipeline + pods + ArgoCD | EKS: `staging-data-test-etl-smoketest` | P0 | TAREFA-022 | ⏳ AGUARDA CLUSTER |

---

## Sequência de Execução

### Fase 1 — Pré-Requisitos (requer cluster ativo)

> Bloqueada por AWS-recovery. Executar assim que o cluster estiver disponível.

1. **TAREFA-001** — Executar `vault-setup-hatch-etl.sh`: cria paths `secret/staging/hatch-etl/{database,redis,keycloak}`, AppRole `hatch-etl`, policy de leitura restrita ao namespace `staging-data-hatch-etl`.
2. **TAREFA-002** — Executar `configmap-setup.sh`: aplica ConfigMap `platform-manifest-schema` no namespace `staging-platform-backstage` com o schema JSON atual (base para TAREFA-020 posterior).
3. **TAREFA-003** — `helm upgrade` do Backstage com `scaffolder-backend-module-gitlab` habilitado em `helm-values-staging.yaml`. Verificar pods healthy pós-upgrade.
4. **TAREFA-004** — Executar `PUBLISH-TO-GITLAB.sh`: publica os 3 templates (new-service, etl-service, api-service) + catalog entities no repositório `platform/backstage-catalog`. Dependência: `GITLAB_TOKEN` com escopos `api + write_repository`.

**Gate Fase 1:** `kubectl get pods -n staging-platform-backstage` retorna Backstage `Running`; templates visíveis em Backstage `/create`.

---

### Fase 2 — Evolução do Template (pode executar localmente)

> Arquivo alvo: `Arquitetura/Kubernetes/docs/plan/backstage/templates/etl-service/template.yaml`

5. **TAREFA-005** — Adicionar **Passo 7 — Originadoras** ao `spec.steps` do template:
   - Tipo de input: `array` com items do tipo `object`
   - Campos por item: `codigo` (string, required), `apiUrl` (string, uri), `authType` (enum: `jwt_multi_tenant` | `apikey` | `oauth2` | `basic` | `none`, default: `jwt_multi_tenant`), `multiTenant` (boolean, default: true), `secretKeyRef` (string — referência à secret K8s que contém as credenciais)
   - UI: `ui:ArrayFieldTemplate` com adição/remoção dinâmica; `ui:order` após passo de dependências

6. **TAREFA-006** — Adicionar **Passo 8 — APIs Externas**:
   - Campos: `name` (string, required, kebab-case), `url` (string, uri), `authType` (enum: `apikey` | `bearer` | `oauth2` | `basic` | `none`), `secretKeyRef` (string), `timeout` (integer, default: 30, min: 1, max: 300)

7. **TAREFA-007** — Adicionar **Passo 9 — Secrets Externas**:
   - Campos: `envVarName` (string, pattern: `^[A-Z][A-Z0-9_]*$` — UPPER_SNAKE_CASE obrigatório), `vaultPath` (string, ex: `secret/staging/meu-servico/campo`), `secretProperty` (string — chave dentro do secret Vault)
   - Validação client-side: `envVarName` deve ser único no array

8. **TAREFA-008** — Atualizar `output` do template:
   - Adicionar `checklist` no corpo do MR com itens Vault pendentes (originadoras + secrets externas)
   - Formato: lista Markdown com `[ ]` para cada `secretKeyRef` declarado nos passos 7/8/9
   - Adicionar link direto para `ONBOARDING.md` gerado no skeleton

**Gate Fase 2:** `backstage-cli template:validate` retorna 0 erros para o template atualizado.

---

### Fase 3 — Evolução do Skeleton (pode executar localmente)

> Diretório alvo: `Arquitetura/Kubernetes/docs/plan/backstage/templates/etl-service/skeleton/`

9. **TAREFA-010** (executar ANTES de TAREFA-009) — **Atualizar `manifest-schema.json`** (BLOQUEADOR P0):
   - Arquivo: `Arquitetura/Kubernetes/domains/platform-core/app-provisioning/schemas/v1/manifest-schema.json`
   - Adicionar `$defs.originadora` (object: codigo, apiUrl, authType, multiTenant, secretKeyRef)
   - Adicionar `$defs.externalAPI` (object: name, url, authType, secretKeyRef, timeout)
   - Adicionar `$defs.externalSecret` (object: envVarName, vaultPath, secretProperty)
   - Adicionar em `properties`: `originadoras` (array de `$defs.originadora`), `externalAPIs` (array de `$defs.externalAPI`), `externalSecrets` (array de `$defs.externalSecret`)
   - `additionalProperties: false` deve permanecer nas seções existentes — as novas seções ficam no nível raiz com `additionalProperties: false` próprio
   - Bump de schema: adicionar `$comment: "v1.1.0 — originadoras + externalAPIs + externalSecrets"` no topo

10. **TAREFA-009** — Atualizar `skeleton/.platform/manifest.yaml`:
    - Adicionar seção `originadoras` com Nunjucks: `{% for orig in values.originadoras %}...{% endfor %}`
    - Adicionar seção `externalAPIs` com Nunjucks: `{% for api in values.externalAPIs %}...{% endfor %}`
    - Adicionar seção `config.secretKeys` gerado dinamicamente: union dos `secretKeyRef` de originadoras + APIs + `envVarName` de secrets externas
    - Adicionar seção `extraSecretVolumes` referenciando cada ExternalSecret gerado

11. **TAREFA-011** — Criar `skeleton/config/originadoras.yaml`:
    - Gerado via Nunjucks a partir dos valores do passo 7
    - Cada originadora renderiza bloco com URL da API e referência a env var (`{{ orig.secretKeyRef | upper }}_TOKEN`)
    - Comentário inline: `# Credencial via ExternalSecret — não hardcode aqui`

12. **TAREFA-012** — Criar estrutura Python no skeleton:
    ```
    skeleton/
      src/
        __init__.py
        main.py          # entrypoint com health check /health e /metrics
        config.py        # lê env vars; valida na inicialização
        originadoras/
          __init__.py
          client.py      # cliente base com retry + timeout + auth strategy
        apis/
          __init__.py
          external.py    # cliente APIs externas
      tests/
        __init__.py
        conftest.py
        test_main.py
        test_config.py
      Dockerfile         # multi-stage: builder python:3.12-slim + runner distroless
      docker-compose.yml # serviço app + postgres local + redis local
      pyproject.toml     # [tool.poetry] + [tool.pytest.ini_options] + [tool.ruff]
      requirements.txt   # gerado via `poetry export`
      .python-version    # 3.12
    ```
    - `Dockerfile`: stage `builder` instala dependências, stage `runner` copia apenas o necessário (distroless/python3)
    - `config.py`: lê todas as env vars declaradas em `externalSecrets` + vars padrão da plataforma (DATABASE_URL, REDIS_URL, etc.)

13. **TAREFA-013** (P0) — Criar `skeleton/scripts/provision.sh`:
    - Lê `.platform/manifest.yaml` via `yq` (sem dependência de Python)
    - Para cada originadora: cria path Vault `secret/${ENV}/${APP_NAME}/originadora-${CODIGO}` + ExternalSecret CR idempotente
    - Para cada externalSecret: cria ExternalSecret CR mapeando `vaultPath` → `envVarName`
    - Cria banco de dados via `provision-postgresql.sh` se `dependencies.database.enabled: true`
    - Idempotência: `check-before-create` em todos os recursos (Vault path, K8s secret, ExternalSecret)
    - Integra com `lib/common.sh` e `lib/vault-auth.sh` do repo `app-provisioning`
    - Argumento obrigatório: `--env staging|prod`; falha explícita se omitido

14. **TAREFA-014** — Atualizar `skeleton/catalog-info.yaml`:
    - Anotações de observabilidade: `backstage.io/techdocs-ref`, `grafana/dashboard-url`, `argocd/app-name`
    - Links: Grafana dashboard, ArgoCD application, Vault path da aplicação
    - Tags dinâmicas: `{% for orig in values.originadoras %}originadora-{{ orig.codigo }}{% endfor %}`
    - `spec.dependsOn`: sistemas das originadoras declaradas

15. **TAREFA-015** — Criar `skeleton/.gitlab-ci.yml` com **8 stages**:
    ```
    stages: [validate, test, build, security-scan, quality-gate, provision, migrate, deploy]
    ```
    - `validate`: executa `validate-manifest.sh`, `validate-naming.sh`, `validate-resource-approval.sh`
    - `test`: `pytest` com coverage ≥ 80%; falha se cobertura menor
    - `build`: `docker build` + push para Harbor com tag `${CI_COMMIT_SHORT_SHA}`
    - `security-scan`: Trivy image scan (`--exit-code 1` para CRITICAL)
    - `quality-gate`: SonarQube (include template canônico da plataforma)
    - `provision`: executa `scripts/provision.sh --env staging` — somente na branch `staging`
    - `migrate`: executa migrations de banco (somente se `dependencies.database.enabled: true`)
    - `deploy`: `helm upgrade --install` no namespace `${ENV}-data-${APP_NAME}`
    - Variáveis obrigatórias documentadas com `# REQUIRED:` em cada job
    - `rules:changes` para detecção monorepo se aplicável

**Gate Fase 3:** `validate-manifest.sh` aceita o skeleton gerado sem erros; `backstage-cli template:validate` passa; Dockerfile faz `docker build` local sem erro.

---

### Fase 4 — Automação do Deploy (pode executar localmente)

16. **TAREFA-016** — Documentar variáveis CI/CD obrigatórias:
    - Arquivo: `skeleton/docs/ONBOARDING.md` (seção "Configuração GitLab CI/CD")
    - Variáveis: `KUBECONFIG_STAGING` (base64 do kubeconfig), `VAULT_ADDR`, `VAULT_ROLE_ID`, `VAULT_SECRET_ID`, `CI_REGISTRY_USER`, `CI_REGISTRY_PASSWORD`, `SONAR_TOKEN`, `SONAR_HOST_URL`
    - Para cada originadora com `authType != none`: `<SECRETKEYREF>_TOKEN` ou `<SECRETKEYREF>_API_KEY` conforme tipo
    - Instruções: onde configurar no GitLab (Settings → CI/CD → Variables), quais devem ser `Masked`, quais `Protected`

17. **TAREFA-017** — Evoluir `provision.sh` com ExternalSecret dinâmico para originadoras:
    - Gera `ExternalSecret` CR para cada originadora com `authType != none`
    - Nome do CR: `${APP_NAME}-originadora-${CODIGO}` (kebab-case)
    - `spec.data` mapeando as chaves necessárias por `authType`:
      - `jwt_multi_tenant`: `token`, `jwks-url`, `issuer`
      - `apikey`: `api-key`
      - `oauth2`: `client-id`, `client-secret`, `token-url`
      - `basic`: `username`, `password`
    - Gera ExternalSecret separado para cada item de `externalSecrets` declarado no manifest
    - Aplica via `kubectl apply -f` após geração; verifica `status.conditions` Ready

18. **TAREFA-018** — Criar `skeleton/docs/ONBOARDING.md` completo:
    - Seções: Pré-Requisitos, Fluxo Pós-Scaffold, Variáveis CI/CD, Vault Paths Esperados, Testando Localmente, Troubleshooting
    - Checklist pós-scaffold com itens verificáveis (`- [ ]`)
    - Diagrama ASCII do fluxo: developer → Backstage → GitLab → EKS
    - Links para: Grafana, ArgoCD, Vault UI, Backstage catalog entity

19. **TAREFA-019** — Criar `skeleton/helm/values.yaml` e overlay staging:
    ```
    skeleton/helm/
      values.yaml           # values genérico com Nunjucks (image, replicas, resources)
      values-staging.yaml   # overlay: replicas 1, resources 0.5x presets etl
    ```
    - `values.yaml`: `image.repository`, `image.tag`, `replicaCount`, `resources` (referencia preset etl da mesa técnica), `env` (lista de envFrom ExternalSecrets gerados), `livenessProbe`, `readinessProbe`
    - `values-staging.yaml`: sobrescreve `replicaCount: 1`, `resources.requests.cpu: 100m`, `resources.requests.memory: 128Mi`

**Gate Fase 4:** `helm template` com os values gerados produz YAML válido; `provision.sh --dry-run` imprime plano sem erros.

---

### Fase 5 — Publicação e Ativação (requer cluster ativo)

20. **TAREFA-020** — Atualizar ConfigMap `platform-manifest-schema` no cluster:
    - Namespace: `staging-platform-backstage`
    - Aplica o `manifest-schema.json` atualizado (TAREFA-010) via `kubectl apply`
    - Verifica que o Backstage relê o ConfigMap (restart do pod scaffolder se necessário)
    - Gate: `kubectl get configmap platform-manifest-schema -o jsonpath='{.data.schema}' | python3 -m json.tool` retorna JSON válido com campos `originadoras` e `externalAPIs` presentes

21. **TAREFA-021** — Republicar templates atualizados no GitLab:
    - Executa `templates/PUBLISH-TO-GITLAB.sh` com o template `etl-service` atualizado (passos 7/8/9)
    - Executa `catalog/PUBLISH-TO-GITLAB.sh` para atualizar catalog entities
    - Aguarda Backstage reprocessar o Location entity (polling `/api/catalog/refresh`)
    - Gate: template `etl-service-template` visível em Backstage `/create` com os 3 novos passos

22. **TAREFA-022** — Teste E2E scaffold:
    - Criar aplicação `test-etl-smoketest` via Backstage `/create` preenchendo:
      - 1 originadora: `{ codigo: "src-test", apiUrl: "https://api.test.internal", authType: "jwt_multi_tenant", multiTenant: true, secretKeyRef: "src-test-creds" }`
      - 1 API externa: `{ name: "ext-api-test", url: "https://ext.test.internal", authType: "apikey", secretKeyRef: "ext-api-test-key", timeout: 30 }`
      - 1 secret externa: `{ envVarName: "FEATURE_FLAG_KEY", vaultPath: "secret/staging/test-etl-smoketest/flags", secretProperty: "feature-flag-key" }`
    - Verificar: repo GitLab criado, MR aberto com checklist Vault, estrutura Python presente, `.gitlab-ci.yml` gerado, `manifest.yaml` com seções corretas
    - Gate: `validate-manifest.sh` passa no manifest gerado; `python -m pytest tests/` passa no skeleton gerado

23. **TAREFA-023** — Teste de deploy completo:
    - Merge do MR de `test-etl-smoketest` para branch `staging`
    - Monitorar pipeline GitLab: todos os 8 stages devem passar
    - Stage `provision`: namespace `staging-data-test-etl-smoketest` criado; ExternalSecrets aplicados
    - Stage `deploy`: `helm upgrade` concluído sem erro
    - Verificar ArgoCD: Application `test-etl-smoketest-staging` em estado `Healthy + Synced`
    - Verificar pods: `kubectl get pods -n staging-data-test-etl-smoketest` retorna `Running`
    - Gate final: 0 GAPs P0 abertos; 0 ressalvas do auditor geral

---

## Mapa de Agentes

| Fase | Tarefas | Agente Responsável | Modo |
|------|---------|-------------------|------|
| F1 — Pré-Requisitos | 001..004 | Orquestrador + AWS | Sequencial (pós-recovery) |
| F2 — Template | 005..008 | Documentation | Local, paralelo 005/006/007 |
| F3 — Skeleton (schema) | 010 | Security + Documentation | Local, antes de TAREFA-009 |
| F3 — Skeleton (restante) | 009, 011..015 | Documentation + Performance | Local, 012 paralelo com 011/013 |
| F4 — Automação | 016..019 | Documentation | Local, 016/018 após 015 |
| F5 — Publicação | 020..021 | AWS + Orquestrador | Sequencial (pós-recovery) |
| F5 — Testes | 022..023 | Orquestrador + Performance | Sequencial após 021 |

---

## Arquivos Principais

| Papel | Caminho Absoluto |
|-------|-----------------|
| Template Backstage (evoluir) | `Arquitetura/Kubernetes/docs/plan/backstage/templates/etl-service/template.yaml` |
| Skeleton manifest (evoluir) | `Arquitetura/Kubernetes/docs/plan/backstage/templates/etl-service/skeleton/.platform/manifest.yaml` |
| Skeleton catalog-info (evoluir) | `Arquitetura/Kubernetes/docs/plan/backstage/templates/etl-service/skeleton/catalog-info.yaml` |
| Skeleton .gitlab-ci.yml (criar) | `Arquitetura/Kubernetes/docs/plan/backstage/templates/etl-service/skeleton/.gitlab-ci.yml` |
| Skeleton provision.sh (criar) | `Arquitetura/Kubernetes/docs/plan/backstage/templates/etl-service/skeleton/scripts/provision.sh` |
| Skeleton estrutura Python (criar) | `Arquitetura/Kubernetes/docs/plan/backstage/templates/etl-service/skeleton/src/` |
| Skeleton helm values (criar) | `Arquitetura/Kubernetes/docs/plan/backstage/templates/etl-service/skeleton/helm/` |
| Skeleton ONBOARDING.md (criar) | `Arquitetura/Kubernetes/docs/plan/backstage/templates/etl-service/skeleton/docs/ONBOARDING.md` |
| **Schema BLOQUEADOR** (atualizar) | `Arquitetura/Kubernetes/domains/platform-core/app-provisioning/schemas/v1/manifest-schema.json` |
| Pipeline de referência | `ETL/Hatch/.gitlab-ci.yml` |
| Vault setup referência | `Arquitetura/Kubernetes/docs/plan/backstage/vault-setup-hatch-etl.sh` |
| Publish script templates | `Arquitetura/Kubernetes/docs/plan/backstage/templates/PUBLISH-TO-GITLAB.sh` |
| Publish script catalog | `Arquitetura/Kubernetes/docs/plan/backstage/catalog/PUBLISH-TO-GITLAB.sh` |
| lib/common.sh (referência) | `Arquitetura/Kubernetes/domains/platform-core/app-provisioning/scripts/lib/common.sh` |
| lib/vault-auth.sh (referência) | `Arquitetura/Kubernetes/domains/platform-core/app-provisioning/scripts/lib/vault-auth.sh` |

---

## GAPs Identificados

| ID | Categoria | Descrição | Prio | Fase | Status |
|----|-----------|-----------|------|------|--------|
| GAP-VAULT-HATCH | Vault | Paths `secret/staging/hatch-etl/{database,redis,keycloak}` e AppRole não criados no cluster | P0 | F1 | ABERTO — script pronto, aguarda execução |
| GAP-S6C-01 | ConfigMap | ConfigMap `platform-manifest-schema` ausente no cluster — schema validation do scaffolder falha | P0 | F1 | ABERTO — script pronto, aguarda execução |
| GAP-S6C-02 | Plugin | `scaffolder-backend-module-gitlab` não configurado no Backstage — publish:gitlab não funciona | P0 | F1 | ABERTO — Backstage Running, aguarda validação helm |
| GAP-S6C-03 | Templates | Templates etl-service validados localmente — publicação no GitLab pendente | P0 | F1 | RESOLVIDO LOCAL (publicação aguarda AWS-recovery) |
| GAP-ETL-TMPL-01 | Template | Passos 7/8/9 (originadoras, APIs, secrets) ausentes no template.yaml atual | P1 | F2 | ✅ RESOLVIDO — 2026-03-16 |
| GAP-ETL-TMPL-02 | Schema | `manifest-schema.json` com `additionalProperties:false` bloqueia campos `externalAPIs` e `originadoras` — BLOQUEADOR TÉCNICO | P0 | F3 | ✅ RESOLVIDO — 2026-03-16 |
| GAP-ETL-SKEL-01 | Skeleton | Skeleton sem estrutura Python — developer configura manualmente após scaffold | P1 | F3 | ✅ RESOLVIDO — 2026-03-16 |
| GAP-ETL-SKEL-02 | Skeleton | provision.sh genérico ausente no skeleton — sem automação de infra pós-scaffold | P0 | F3 | ✅ RESOLVIDO — 2026-03-16 |
| GAP-ETL-SKEL-03 | Skeleton | .gitlab-ci.yml não gerado pelo scaffold — developer copia manualmente com risco de divergência | P1 | F3 | ✅ RESOLVIDO — 2026-03-16 |
| GAP-ETL-SKEL-04 | Skeleton | config/originadoras.yaml ausente — sem forma declarativa de registrar data sources no repositório | P1 | F3 | ✅ RESOLVIDO — 2026-03-16 |
| GAP-ETL-CICD-01 | CI/CD | Variáveis obrigatórias do CI não documentadas no repo gerado pelo scaffold | P2 | F4 | ✅ RESOLVIDO — 2026-03-16 |
| GAP-AUTOMATE-CONFIGMAP-01 | CI/CD | Automação do ConfigMap schema e Vault policy backstage-scaffolder no pipeline CI/CD do Backstage — `configmap-setup.sh` é manual; drift possível quando `manifest-schema.json` evolui sem re-execução | BAIXA | — | MELHORIA FUTURA |

### Resumo por Prioridade

| Prioridade | Total | Abertos | Resolvidos |
|------------|-------|---------|------------|
| P0 Bloqueante | 6 | 1 | 5 |
| P1 Alta | 4 | 0 | 4 |
| P2 Média | 1 | 0 | 1 |
| Baixa (Melhoria futura) | 1 | 1 | 0 |
| **TOTAL** | **12** | **2** | **10** |

---

## Definition of Done

- [ ] Template `etl-service-template` visível no Backstage `/create` com passos 7 (originadoras), 8 (APIs externas) e 9 (secrets externas) funcionais
- [ ] Scaffold cria repositório GitLab com estrutura Python completa (`src/`, `tests/`, `Dockerfile`, `docker-compose.yml`, `pyproject.toml`)
- [ ] `manifest.yaml` gerado contém seções `originadoras`, `externalAPIs`, `externalSecrets` com os valores do formulário
- [ ] `scripts/provision.sh` gerado lê o manifest e cria recursos Vault + ExternalSecret de forma idempotente
- [ ] `.gitlab-ci.yml` gerado com os 8 stages canônicos da plataforma
- [ ] MR aberto automaticamente com checklist Vault no corpo da descrição
- [ ] Push para branch `staging` dispara pipeline GitLab; todos os 8 stages passam
- [ ] Pods do serviço de teste em estado `Running` no EKS
- [ ] ArgoCD Application em estado `Healthy + Synced`
- [ ] `validate-manifest.sh` aceita o manifest gerado pelo scaffold sem erros
- [ ] 0 GAPs P0 abertos
- [ ] 0 ressalvas do auditor geral

---

## Critérios de Rollback

| Cenário | Ação de Rollback |
|---------|-----------------|
| TAREFA-003 (helm upgrade) — Backstage unhealthy pós-upgrade | `helm rollback backstage` para a revisão anterior; verificar pods healthy; abrir GAP com diff dos values |
| TAREFA-010 (schema) — manifest-schema.json atualizado quebra validações existentes | `git revert` do commit no schema; republicar ConfigMap com versão anterior via `configmap-setup.sh --version v1.0.0` |
| TAREFA-020 (ConfigMap cluster) — Backstage scaffolder falha ao ler schema novo | `kubectl rollout restart deployment/backstage -n staging-platform-backstage`; se persistir, `kubectl apply` da versão anterior do ConfigMap |
| TAREFA-021 (publicação GitLab) — templates com erro após publicação | Re-executar `PUBLISH-TO-GITLAB.sh` após corrigir template local; Backstage reprocessa via `/api/catalog/refresh` |
| TAREFA-022/023 (teste E2E) — scaffold ou deploy com falha | Deletar namespace `staging-data-test-etl-smoketest`; arquivar repo GitLab de teste; corrigir GAP detectado; repetir a partir de TAREFA-022 |
| provision.sh cria recurso parcial (falha no meio) — Vault path criado mas ExternalSecret não | Reexecutar `provision.sh --env staging` (idempotente); recursos já existentes são ignorados pelo check-before-create |

---

## Riscos

| Risco | Prob | Impacto | Mitigação |
|-------|------|---------|-----------|
| `manifest-schema.json` com `additionalProperties:false` — evolução complexa sem quebrar apps existentes | Alta | Crítico | Adicionar novas seções no nível raiz com seus próprios `additionalProperties:false`; bump de `$comment` para v1.1.0; testar com manifests existentes antes de aplicar no cluster |
| Nunjucks template rendering — campos opcionais (array vazio) causam YAML inválido | Média | Alto | Usar `{% if values.originadoras | length > 0 %}` guards em todo bloco condicional; teste com payload mínimo (arrays vazios) |
| Backstage scaffolder timeout — scaffold com arrays grandes (>10 itens) excede timeout do job | Baixa | Médio | Configurar `scaffolder.jobMaxAge` nos helm values; limite de 10 itens por array documentado no formulário |
| ExternalSecret gerado pelo provision.sh — ClusterSecretStore não disponível no momento do apply | Média | Alto | provision.sh verifica pré-requisitos (CRD + ClusterSecretStore Ready) antes de criar ESO resources; falha explícita com mensagem de erro acionável |
| .gitlab-ci.yml gerado — divergência com template canônico evolui ao longo do tempo | Média | Médio | Skeleton usa `include:` para templates canônicos da plataforma (`/templates/security.gitlab-ci.yml`); apenas os stages customizados ficam no skeleton |
| AWS-recovery atrasada — Fases 1 e 5 bloqueadas além do esperado | Média | Médio | Fases 2, 3 e 4 são executáveis localmente sem cluster; maximizar trabalho local enquanto o cluster está indisponível |

---

## Dependências Externas

| Dependência | Status | Impacto se ausente |
|-------------|--------|--------------------|
| Cluster EKS staging disponível | AGUARDANDO (pós-AWS-recovery) | Bloqueia Fases 1 e 5 |
| Backstage S6 Deploy concluído | EM ANDAMENTO | Bloqueia TAREFA-003/004/020/021 |
| GitLab `platform/backstage-catalog` repo acessível | ATIVO | Bloqueia TAREFA-004/021 |
| `GITLAB_TOKEN` com escopos `api + write_repository` | PENDENTE — gerar pós-recovery | Bloqueia TAREFA-004/021 |
| ESO (External Secrets Operator) instalado no cluster | OPERACIONAL (pre-existente) | Bloqueia TAREFA-017/023 |
| ArgoCD configurado no cluster staging | DEPENDENTE do S6 Deploy | Bloqueia TAREFA-023 |
| `lib/common.sh` e `lib/vault-auth.sh` do `app-provisioning` | DISPONÍVEL | Ausência obriga provision.sh a reimplementar lógica |

---

## Histórico de Progresso

| Timestamp | Evento |
|-----------|--------|
| 2026-03-15 | Demanda criada — análise dos GAPs existentes (S6C-01, S6C-02, S6C-03, VAULT-HATCH) |
| 2026-03-15 | GAP-S6C-03 resolvido localmente (2026-03-15, docs/demands/2026-03-13) — templates validados, scripts prontos |
| 2026-03-15 | Identificados GAPs adicionais: GAP-ETL-TMPL-01/02, GAP-ETL-SKEL-01/02/03/04, GAP-ETL-CICD-01 |
| 2026-03-15 | BLOQUEADOR P0 identificado: `manifest-schema.json` com `additionalProperties:false` — TAREFA-010 criada |
| 2026-03-15 | Sequência de execução definida: Fases 2/3/4 executáveis localmente enquanto cluster indisponível |
| 2026-03-16 | Auditoria profunda — 19/23 tarefas confirmadas CONCLUÍDAS — F2/F3/F4 100% completas localmente — Cluster EKS disponível — Aguardam execução: TAREFA-001 (vault), TAREFA-002 (configmap), TAREFA-004 (publish templates), TAREFA-020-023 (cluster) |

---

## Referências

- Demanda CI/CD base: `docs/demands/2026-03-11-cicd-onboarding-manifesto-base.md`
- Demanda Hatch ETL EKS: `docs/demands/2026-03-13-hatch-etl-onboarding-eks.md`
- Playbook S6 Backstage: `docs/demands/backstage-s6-deploy-playbook-2026-03-13.md`
- Deployment Checklist: `docs/plan/backstage/DEPLOYMENT-CHECKLIST.md`
- Vault setup Hatch: `docs/plan/backstage/vault-setup-hatch-etl.sh`
- ExternalSecret Hatch: `docs/plan/backstage/hatch-etl-external-secret.yaml`
- ConfigMap setup: `docs/plan/backstage/configmap-setup.sh`
- manifest-schema.json atual: `domains/platform-core/app-provisioning/schemas/v1/manifest-schema.json`
- Pipeline ETL referência: `ETL/Hatch/.gitlab-ci.yml`
- ADR-104: `docs/adr/ADR-104-onboarding-declarativo.md`
