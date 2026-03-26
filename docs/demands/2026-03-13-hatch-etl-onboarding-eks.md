# Demanda: Onboarding Hatch ETL → EKS Staging

**Data**: 2026-03-13
**Status**: EM ANDAMENTO
**Responsável**: Orquestrador DevOps Sênior

---

## Objetivo

Onboarding declarativo do serviço Hatch ETL no cluster EKS staging via `.platform/manifest.yaml`, integrando CI/CD pipeline (GitLab) e sincronização via ArgoCD no namespace `staging-data-hatch-etl`.

---

## Artefatos Principais

| Artefato | Caminho |
| --- | --- |
| Manifest principal | `/home/gilvangalindo/projects/ETL/Hatch/.platform/manifest.yaml` |
| Helm values staging | `Arquitetura/Kubernetes/platform-provisioning/helm/backstage/helm-values-staging.yaml` |
| Namespace alvo | `staging-data-hatch-etl` |

---

## Dependências

| Dependência | Status |
| --- | --- |
| S6 Backstage Deploy | S6-A+B CONCLUÍDOS — S6-C PENDENTE — Backstage Running 1/2 réplicas |
| AWS SSO sessão ativa | ATIVA |
| GitLab CI/CD pipeline funcional | Dependente do S6-C (MR Automático) |
| ArgoCD configurado no cluster staging | Dependente do S6 Deploy |
| Vault AppRole paths hatch-etl | PENDENTE — GAP-VAULT-HATCH |

---

## Etapas de Execução

### Fase 1 — Validação do Cluster

- [ ] Confirmar acesso kubectl ao cluster EKS staging
- [ ] Verificar namespaces existentes
- [ ] Validar ArgoCD running + acessível
- [ ] Confirmar GitLab Runner operacional (2/2 Running)

### Fase 2 — Vault + ConfigMap

- [ ] Criar paths Vault para hatch-etl (`secret/staging/hatch-etl/*`)
- [ ] Configurar AppRole para o serviço
- [ ] Gerar ConfigMap base a partir do manifest.yaml
- [ ] Resolver GAP-S6C-01 (ConfigMap schema validation)

### Fase 3 — Helm Backstage Upgrade

- [ ] Aplicar helm-values-staging.yaml com novos plugins
- [ ] Resolver GAP-S6C-02 (plugin scaffolder-backend-module-gitlab)
- [ ] Verificar Backstage pods healthy pós-upgrade

### Fase 4-8 — Templates + Publish

- [ ] Resolver GAP-S6C-03 (templates ETL no Backstage)
- [ ] Publicar template etl-service no Backstage catalog
- [ ] Registrar entity `hatch-etl` via catalog-info.yaml
- [ ] Validar scaffold end-to-end

### Fase 9 — Onboarding CI/CD Pipeline

- [ ] Registrar `.platform/manifest.yaml` no pipeline de onboarding
- [ ] Gerar `.gitlab-ci.yml` via template etl-service
- [ ] Configurar variáveis de ambiente no GitLab
- [ ] Executar pipeline de validação (lint + test)

### Fase 10 — ArgoCD Sync

- [ ] Criar Application manifest ArgoCD para `staging-data-hatch-etl`
- [ ] Configurar sync policy (auto-sync + self-heal)
- [ ] Primeiro sync e validação dos pods
- [ ] Verificar health checks + readiness probes

---

## Artefatos Pré-Deploy Validados

> Auditoria executada em 2026-03-15 — GAP-S6C-03 resolvido localmente.
> Scripts de publicação prontos para execução pós-AWS-recovery.

### Templates Golden Path (3/3 validados)

| Template | Arquivo | apiVersion | kind | name | owner | type | platform:manifest:validate | publish:gitlab MR | mergeRequestUrl |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| new-service | `templates/new-service/template.yaml` | scaffolder.backstage.io/v1beta3 | Template | new-service-template | platform-team | service | PRESENTE (id: validate-manifest) | PRESENTE (branchName != defaultBranch) | PRESENTE (output.mergeRequestUrl) |
| etl-service | `templates/etl-service/template.yaml` | scaffolder.backstage.io/v1beta3 | Template | etl-service-template | platform-team | service | PRESENTE (id: validate-manifest) | PRESENTE (branchName != defaultBranch) | PRESENTE (output.mergeRequestUrl) |
| api-service | `templates/api-service/template.yaml` | scaffolder.backstage.io/v1beta3 | Template | api-service-template | platform-team | service | PRESENTE (id: validate-manifest) | PRESENTE (branchName != defaultBranch) | PRESENTE (output.mergeRequestUrl) |

### Skeleton Manifests (3/3 validados)

| Template | Arquivo | apiVersion | kind | Nunjucks vars |
| --- | --- | --- | --- | --- |
| new-service | `templates/new-service/skeleton/.platform/manifest.yaml` | platform.k8s/v1 | ApplicationManifest | `{{ values.name }}`, `{{ values.domain }}`, `{{ values.owner }}`, `{{ values.type }}` — OK |
| etl-service | `templates/etl-service/skeleton/.platform/manifest.yaml` | platform.k8s/v1 | ApplicationManifest | `{{ values.name }}`, `{{ values.owner }}`, `{{ values.serviceType }}`, `{{ values.product }}` — OK |
| api-service | `templates/api-service/skeleton/.platform/manifest.yaml` | platform.k8s/v1 | ApplicationManifest | `{{ values.name }}`, `{{ values.domain }}`, `{{ values.owner }}`, `{{ values.port }}` — OK |

### Location Entity Templates

| Arquivo | Status | Targets |
| --- | --- | --- |
| `templates/catalog-info.yaml` | PRESENTE | `./new-service/template.yaml`, `./etl-service/template.yaml`, `./api-service/template.yaml`, `./frontend/template.yaml` |

### Catalog Entities (4/4 presentes)

| Arquivo | Tipo | Entities | Status |
| --- | --- | --- | --- |
| `catalog/catalog-info.yaml` | Location | Root — aponta para domains, systems, components, templates | PRESENTE |
| `catalog/entities/domains/catalog-info.yaml` | Domain x5 | platform, integration, data, operations, shared-services | PRESENTE |
| `catalog/entities/systems/data/catalog-info.yaml` | System | data-hatch-etl | PRESENTE |
| `catalog/ETL/Hatch/catalog-info.yaml` | Component x8 | hatch-api-gateway, hatch-worker, hatch-etl-core, hatch-data-processor, hatch-scheduler, hatch-dashboard, hatch-cronjob-etl-extraction, hatch-migration-runner | PRESENTE |

### Scripts de Publicação (prontos para execução pós-AWS-recovery)

| Script | Publica | Caminho |
| --- | --- | --- |
| `PUBLISH-TO-GITLAB.sh` (templates) | 3 templates + skeletons + catalog-info.yaml | `Arquitetura/Kubernetes/docs/plan/backstage/templates/PUBLISH-TO-GITLAB.sh` |
| `PUBLISH-TO-GITLAB.sh` (catalog) | 4 catalog entities (domains, systems, components, root) | `Arquitetura/Kubernetes/docs/plan/backstage/catalog/PUBLISH-TO-GITLAB.sh` |

**Execução pós-AWS-recovery:**

```bash
export GITLAB_TOKEN="<token-com-api+write_repository>"
bash /home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/plan/backstage/templates/PUBLISH-TO-GITLAB.sh
bash /home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/plan/backstage/catalog/PUBLISH-TO-GITLAB.sh
```

### Checklist GAP-S6C-03

- [x] 3 templates ETL validados localmente (new-service, etl-service, api-service)
- [x] Todos os campos obrigatórios presentes (apiVersion, kind, metadata, spec.owner, spec.type)
- [x] Step `platform:manifest:validate` presente nos 3 templates
- [x] Step `publish:gitlab` com MR automático (`branchName != defaultBranch`) presente nos 3
- [x] Output `mergeRequestUrl` mapeado nos 3 templates
- [x] Skeletons `.platform/manifest.yaml` com Nunjucks, `apiVersion: platform.k8s/v1`, `kind: ApplicationManifest`
- [x] Location entity `templates/catalog-info.yaml` presente com os 3 targets
- [x] Scripts de publicação criados e prontos
- [ ] Templates publicados no GitLab `platform/backstage-catalog` (PENDENTE — aguarda AWS-recovery)
- [ ] Templates visíveis em Backstage /create (PENDENTE — aguarda deploy S6)

---

## GAPs Conhecidos

| ID | Categoria | Descrição | Prioridade | Status |
| --- | --- | --- | --- | --- |
| GAP-S6C-01 | ConfigMap | Schema validation falha no manifest.yaml do Hatch | P1 | RESOLVIDO — policy backstage-scaffolder existe no Vault |
| GAP-S6C-02 | Plugin | `scaffolder-backend-module-gitlab` não configurado | P1 | RESOLVIDO NO ARTEFATO — pendente helm upgrade no cluster |
| GAP-S6C-03 | Templates | Templates ETL ausentes no Backstage | P1 | RESOLVIDO LOCAL (publicação pendente AWS-recovery) |
| GAP-VAULT-HATCH | Vault | Paths `secret/staging/hatch-etl/*` não criados | P0 | PATHS CRIADOS — VALORES PLACEHOLDER (credenciais reais pendentes) |
| GAP-AUTOMATE-CONFIGMAP-01 | CI/CD | `configmap-setup.sh` é manual — ConfigMap `platform-manifest-schema` e Vault policy `backstage-scaffolder` não são atualizados automaticamente quando `manifest-schema.json` evolui | BAIXA | MELHORIA FUTURA |
| GAP-IMAGE-01 | Imagem | `etl-core:initial` é imagem Python base sem código — container termina com Exit Code 0 | P0 | ABERTO |
| GAP-DNS-01 | Rede | DNS `hatch-etl-rds.staging.internal` não resolve no cluster — usar FQDN RDS direto | P1 | ABERTO |
| GAP-SG-01 | Rede | Security Group pode estar bloqueando porta 5432 do CIDR EKS pods ao RDS | P1 | ABERTO |
| GAP-WORKLOAD-01 | Arquitetura | etl-core deveria ser CronJob (schedule: `0 2 * * *`), não Deployment — cronjob-etl-extraction.yaml existe no repo mas não deployado | P1 | IaC CRIADO (2026-03-21) — `k8s/base/cronjob-etl-extraction.yaml` adicionado + referenciado no kustomization base e overlay staging. CronJob permanece `suspend: true` até imagem real estar disponível. Deployment hatch-etl mantido (serve API/worker). Pendente: push ao GitLab develop + ArgoCD sync |
| GAP-DEPLOY-01 | Deploy | 7 serviços não deployados: api-gateway, worker, poller, anexos-service, web, dashboard, prometheus-exporter — YAMLs existem em k8s/base/ | P2 | ABERTO |

---

## Critérios de Conclusão (Definition of Done)

- [ ] Hatch ETL deployado e saudável no namespace `staging-data-hatch-etl`
- [ ] ArgoCD Application sincronizado (Healthy + Synced)
- [ ] Pipeline GitLab passando (lint + test + deploy)
- [ ] Backstage catalog entity visível em staging
- [ ] 0 GAPs P0 abertos
- [ ] `kubectl get pods -n staging-data-hatch-etl` retorna pods Running
- [ ] Logbook atualizado com status CONCLUÍDO

---

## Histórico de Progresso

| Timestamp | Evento |
| --- | --- |
| 2026-03-13 18:00 | Demanda iniciada — Orquestrador — AWS SSO ativa |
| 2026-03-13 18:00 | Dependência S6 Backstage Deploy iniciada em paralelo |
| 2026-03-15 | GAP-S6C-03 resolvido localmente — templates validados, scripts de publicação criados |
| 2026-03-16 | Status auditado — cluster UP — hatch-etl CrashLoopBackOff (DATABASE_PASSWORD placeholder no Vault) — GAP-S6C-01 RESOLVIDO — GAP-S6C-02 artefato OK |
| 2026-03-16 | K8s/SRE Investigação — etl-core:initial = imagem placeholder (Python base sem código app) — Exit Code 0 confirmado — DNS hatch-etl-rds não resolve — 7 serviços não deployados — hatch_etl_user + DB criados no RDS |

---

## Referências

- Demanda CI/CD base: `docs/demands/2026-03-11-cicd-onboarding-manifesto-base.md`
- Logbook: `docs/logbook/strategies-history.md`
- Playbook S6: Sprint S6-A (CONCLUÍDO) + S6-B (CONCLUÍDO) + S6-C (PENDENTE) + Deploy (INICIADO)
