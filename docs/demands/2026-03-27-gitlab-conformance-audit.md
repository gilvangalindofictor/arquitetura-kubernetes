# GitLab Conformance Audit — DNS `hml` e Shared Service

**Data**: 2026-03-27
**Autor**: Platform Architect + Compliance Auditor
**Classificacao**: Auditoria de conformidade
**Componente**: GitLab CE v18.9.1 (chart 9.10.0)
**Namespace**: `staging-platform-gitlab`
**DNS Publico**: `gitlab.hml.alvocard.com.br`
**DNS Interno**: `gitlab.staging.internal`

---

## 1. Estado Atual

### 1.1 Topologia

| Item | Valor |
|------|-------|
| Namespace | `staging-platform-gitlab` |
| Pods Running | 13 (+ runner job pods efemeros) |
| Version | GitLab CE v18.9.1 (chart gitlab/gitlab 9.10.0) |
| TF State | `environments/prod/main.tf` L303 (module "gitlab") |
| Environment var | `shared` (L317) |
| DNS Publico | `gitlab.hml.alvocard.com.br` (Route53 zona `hml.alvocard.com.br`) |
| DNS Interno | `gitlab.staging.internal` (Route53 zona privada `staging.internal`) |
| ALB | `k8s-gitlabstaging-da5a4e8c6d` (internet-facing, grupo `gitlab-staging`) |
| ACM Certs | `*.staging.internal` + `*.hml.alvocard.com.br` (ambos ISSUED) |
| WAF | `waf-k8s-platform-prod-staging` associado ao ALB |
| Ingress | 3 Ingresses (webservice, kas, minio) com dual-host (staging.internal + hml.alvocard.com.br) |
| ArgoCD | NAO gerenciado (nenhuma Application encontrada) |
| Linkerd | NAO injetado (namespace sem annotation `linkerd.io/inject`) |
| Backup | Coberto via Velero (daily-full + hourly-incremental, includedNamespaces: `*`) |

### 1.2 Componentes

| Deployment/StatefulSet | Replicas | HPA | PDB | Limits |
|------------------------|----------|-----|-----|--------|
| gitlab-webservice-default | 1/1 | min=1 max=3 (CPU 70%) | 3 PDBs (sobreposicao) | CPU:2 Mem:4Gi |
| gitlab-sidekiq-all-in-1-v2 | 1/1 | min=1 max=1 | 2 PDBs | CPU:1 Mem:2Gi |
| gitlab-gitlab-shell | 2/2 | min=2 max=10 | 1 PDB | SEM limits |
| gitlab-kas | 2/2 | min=2 max=10 | 1 PDB | SEM limits |
| gitlab-gitlab-runner | 1/1 | Nao | Nao | CPU:500m Mem:512Mi |
| gitlab-minio | 1/1 | Nao | 1 PDB | SEM limits |
| gitlab-toolbox | 1/1 | Nao | Nao | SEM limits |
| gitlab-gitlab-exporter | 1/1 | Nao | Nao | SEM limits |
| gitlab-gitaly-0 (STS) | 1/1 | Nao | 1 PDB | CPU:500m Mem:1Gi |

### 1.3 Quem Usa o GitLab

GitLab e uma **instancia unica shared** servindo TODOS os ambientes:

- **Staging workloads**: CI/CD pipelines (Hatch ETL, VemSoft, CCBCreator)
- **Prod workloads**: Backstage prod consome GitLab via PAT `glpat-Kv8iaiVnr3gaOusxXIdqEm86MQp1OjEH`
- **Backstage staging**: Integracao GitLab catalog
- **GitLab Runners**: Executam jobs no proprio namespace `staging-platform-gitlab`
- **Harbor CI/CD**: Robot account `robot$gitlab-ci` para push/pull de imagens

### 1.4 Dependencias Externas

- **PostgreSQL**: RDS prod (`k8s-platform-prod-postgresql`) — database `gitlab`
- **Redis**: Cluster Redis prod (`redis.data-services.svc.cluster.local:6379`)
- **S3**: `k8s-platform-gitlab-artifacts-891377105802` (IRSA)
- **Keycloak**: OIDC (realm platform, secret `gitlab-oidc-keycloak`)
- **Vault**: 11 ExternalSecrets (todos SecretSynced via `vault-backend`)

---

## 2. Analise de Conformidade — DNS `hml`

### 2.1 Por que GitLab esta em `gitlab.hml.alvocard.com.br`?

**Causa raiz: restricao de infraestrutura DNS, nao decisao arquitetural.**

Evidencias coletadas:

1. **Route53 possui apenas 3 hosted zones:**
   - `hml.alvocard.com.br` (publica)
   - `prod.alvocard.com.br` (publica)
   - `staging.internal` (privada)

2. **NAO existe zona `alvocard.com.br` no Route53.** O apex `alvocard.com.br` e gerenciado pelo registrar externo (fora do controle da equipe). A equipe possui autonomia apenas dentro de `*.hml.alvocard.com.br` e `*.prod.alvocard.com.br` (via delegacao NS).

3. **NAO existe registro `gitlab.prod.alvocard.com.br`** na zona prod. GitLab foi alocado na zona `hml` porque:
   - O namespace real e `staging-platform-gitlab` (heranca DEC-074)
   - A zona `hml` e tratada como o dominio dos servicos de staging
   - Colocar em `prod.alvocard.com.br` seria semanticamente pior (implicaria servico de producao)

4. **Decisao documentada (DEC-2026-03-24-GITLAB)**: "GitLab CE = 1 instancia shared, managed no state staging". A decisao reconhece que e shared, mas mantem no contexto staging.

5. **Doc de dominio** (`2026-03-18-setup-dominio-producao.md` L90) lista explicitamente `gitlab.hml.alvocard.com.br` e `gitlab.prod.alvocard.com.br` como equivalentes em ambos os ambientes — porem apenas o record `hml` foi criado porque so existe UMA instancia.

### 2.2 Inconsistencia Identificada

| Aspecto | Valor Atual | Valor Esperado (shared service) |
|---------|-------------|-------------------------------|
| Namespace | `staging-platform-gitlab` | `shared-platform-gitlab` ou `platform-gitlab` |
| DNS | `gitlab.hml.alvocard.com.br` | `gitlab.alvocard.com.br` (ideal) |
| TF State | `environments/prod/main.tf` | Correto (prod state gerencia o shared) |
| Environment label | `production` (namespace label) | `shared` |
| Ingress group | `gitlab-staging` | `gitlab-shared` ou `gitlab` |
| WAF | `waf-k8s-platform-prod-staging` | OK (WAF staging protege o ALB) |
| Helm lifecycle | `ignore_changes = all` | Atencao: upgrades sao manuais |

### 2.3 Impacto Real

**Baixo impacto operacional, medio impacto de governanca.**

- Usuarios externos que acessam `gitlab.hml.alvocard.com.br` podem inferir que e um ambiente de testes/staging, reduzindo confianca no servico como fonte de verdade de codigo
- Equipes de auditoria/compliance podem questionar por que codigo de producao e gerenciado em um servico rotulado como "homologacao"
- Desenvolvedores novos podem se confundir sobre qual GitLab usar (nao ha outro)

---

## 3. Recomendacoes

### 3.1 Opcoes

| Opcao | DNS | Namespace | Esforco | Pros | Contras |
|-------|-----|-----------|---------|------|---------|
| **A** (Status quo) | `gitlab.hml.alvocard.com.br` | `staging-platform-gitlab` | Zero | Funciona, sem risco de mudanca | Confuso — "hml" implica staging |
| **B** (DNS neutro) | `gitlab.alvocard.com.br` | `shared-platform-gitlab` | Alto | Correto semanticamente | Requer zona `alvocard.com.br` no Route53 OU record no registrar externo + novo ACM cert |
| **C** (DNS dedicado) | `git.alvocard.com.br` | `shared-platform-gitlab` | Alto | Padrao industria (GitHub/GitLab SaaS) | Requer zona `alvocard.com.br` no Route53 OU delegacao adicional |
| **D** (Manter + ADR) | `gitlab.hml.alvocard.com.br` | `staging-platform-gitlab` | Minimo | Documenta decisao, zero risco | Nao resolve semantica |
| **E** (CNAME alias) | `gitlab.prod.alvocard.com.br` CNAME -> ALB | `staging-platform-gitlab` | Baixo | Ambos os dominios funcionam | Adiciona complexidade, 2 URLs para mesmo servico |

### 3.2 Recomendacao Pragmatica

**Opcao D (curto prazo) + Opcao B (medio prazo, quando apex estiver disponivel).**

**Curto prazo (Opcao D):**
- Custo: 0
- Risco: 0
- Acao: Criar ADR documentando que `gitlab.hml.alvocard.com.br` e o DNS do GitLab shared por restricao de infraestrutura DNS (apex `alvocard.com.br` nao esta no Route53)
- Justificativa: A equipe nao possui autonomia sobre o apex. Criar zona `alvocard.com.br` no Route53 exigiria migrar toda a gestao DNS (email, site) para AWS, o que esta fora de escopo

**Medio prazo (Opcao B, quando viavel):**
- Se/quando o apex `alvocard.com.br` for migrado para Route53, criar `gitlab.alvocard.com.br`
- Ou solicitar ao gestor de dominio que adicione um registro CNAME `gitlab.alvocard.com.br` apontando para o ALB do GitLab
- Renomear namespace para `shared-platform-gitlab` (requer migrar PVCs, secrets, IRSA)

**NAO recomendado agora:**
- Opcao B/C (alto risco): Renomear namespace envolve migrar PVCs Gitaly (50Gi de repositorios), todos os 11 ExternalSecrets, IRSA role, e reconfigurar TODOS os runners e pipelines
- Opcao E (confuso): Dois URLs para o mesmo servico cria mais confusao, nao menos

---

## 4. Checklist de Conformidade — GitLab como Shared Service

| # | Item | Status | Evidencia |
|---|------|--------|-----------|
| 1 | **Namespace naming** | PARCIAL | `staging-platform-gitlab` — nome implica staging, mas labels dizem `Environment: production`. Inconsistencia. |
| 2 | **NetworkPolicies isolam corretamente?** | PARCIAL | 20 policies existem, mas `gitlab-allow-internal` so permite `podSelector app=gitlab` (intra-namespace). Nao ha policy explicita permitindo acesso de namespaces prod. Acesso funciona via ALB (externo) e DNS interno (ClusterIP). |
| 3 | **Backup (Velero)** | OK | Velero daily-full + hourly-incremental cobrem `includedNamespaces: *` — GitLab incluido. PVCs Gitaly (50Gi) e Minio (10Gi) com snapshotVolumes=true no daily. |
| 4 | **TLS/HTTPS** | OK | ALB termina TLS com ACM wildcards (`*.hml.alvocard.com.br` + `*.staging.internal`). HTTPS:443 + HTTP:80 redirect. |
| 5 | **WAF** | OK | `waf-k8s-platform-prod-staging` associado ao ALB GitLab. Rules: AllowOfficeIP, rate-limit, geo-block, OWASP, SQLi, known-bad-inputs. |
| 6 | **Linkerd mesh** | NAO | Namespace sem annotation `linkerd.io/inject`. Pods sem sidecar proxy. mTLS nao ativo para trafego GitLab intra-cluster. |
| 7 | **HPA** | PARCIAL | webservice (1-3), shell (2-10), kas (2-10) tem HPA. Sidekiq fixo em 1, runner fixo em 1, gitaly sem HPA (StatefulSet). |
| 8 | **PDB** | OK | 9 PDBs configurados cobrindo todos os componentes criticos. Nota: sobreposicao (3 PDBs para webservice) — funcional mas redundante. |
| 9 | **ServiceMonitor** | OK | ServiceMonitor `gitlab` presente no namespace, metricas em `/-/metrics` a cada 30s. |
| 10 | **PrometheusRule** | NAO | Nenhuma PrometheusRule encontrada. Sem alertas automaticos para GitLab (ex: webservice 5xx rate, sidekiq queue depth, gitaly latency). |
| 11 | **ExternalSecrets** | OK | 11 ExternalSecrets, todos `SecretSynced` via `vault-backend`. Refresh 1h. |
| 12 | **ArgoCD gerenciado** | NAO | Nenhuma ArgoCD Application encontrada para GitLab em nenhum namespace. Deploy e 100% Helm manual (`lifecycle { ignore_changes = all }`). |
| 13 | **Resource limits/requests** | PARCIAL | webservice, sidekiq, runner, gitaly tem limits. Shell, kas, minio, toolbox, exporter SEM limits — risco de OOM/noisy neighbor. |
| 14 | **Pod Security Standards** | OK | Namespace enforce `baseline`, warn `restricted`. |
| 15 | **OIDC/SSO** | OK | OmniAuth OIDC com Keycloak configurado (realm platform, autoLinkUser enabled). |
| 16 | **Storage class** | OK | PVCs usam `gp3` (gitaly 50Gi, minio 10Gi). |

### Resumo Checklist

| Categoria | OK | PARCIAL | NAO |
|-----------|-----|---------|-----|
| Total | 9 | 4 | 3 |
| Percentual | 56% | 25% | 19% |

---

## 5. GAPs Identificados

| GAP ID | Descricao | Prioridade | Impacto |
|--------|-----------|------------|---------|
| GAP-GITLAB-DNS-001 | DNS `hml` para shared service — semanticamente incorreto, mas funcional | P3 | Governanca |
| GAP-GITLAB-NS-001 | Namespace `staging-platform-gitlab` com label `Environment: production` — inconsistencia | P3 | Governanca |
| GAP-GITLAB-LINKERD-001 | GitLab sem Linkerd mesh injection — sem mTLS intra-cluster | P2 | Seguranca |
| GAP-GITLAB-ALERTS-001 | Sem PrometheusRule — nenhum alerta automatico para falhas GitLab | P1 | Observabilidade |
| GAP-GITLAB-LIMITS-001 | 5/9 deployments sem resource limits (shell, kas, minio, toolbox, exporter) | P2 | Estabilidade |
| GAP-GITLAB-ARGOCD-001 | GitLab nao gerenciado por ArgoCD — deploy manual, sem GitOps | P2 | Governanca |
| GAP-GITLAB-PDB-OVERLAP | 3 PDBs sobrepostos para webservice — funcional mas pode causar conflito | P3 | Operacional |

---

## 6. Plano de Acao Recomendado

### Imediato (Sprint atual)

1. **GAP-GITLAB-ALERTS-001 (P1)**: Criar PrometheusRule com alertas basicos:
   - `GitLabWebserviceHighErrorRate` (5xx > 5% por 5min)
   - `GitLabSidekiqQueueDepth` (pending jobs > 100 por 10min)
   - `GitLabGitalyHighLatency` (p99 > 1s por 5min)
   - `GitLabRunnerFailureRate` (failed jobs > 20% por 15min)

### Proximo Sprint

2. **GAP-GITLAB-LIMITS-001 (P2)**: Adicionar resource limits para shell, kas, minio, toolbox, exporter
3. **GAP-GITLAB-LINKERD-001 (P2)**: Avaliar Linkerd injection (atencao: skip-outbound-ports ja configurado para PG/Redis/Gitaly)

### Backlog

4. **GAP-GITLAB-DNS-001 (P3)**: Criar ADR documentando decisao DNS `hml` como intencional
5. **GAP-GITLAB-NS-001 (P3)**: Padronizar labels (Environment: shared)
6. **GAP-GITLAB-ARGOCD-001 (P2)**: Avaliar migracao para ArgoCD (atencao: `ignore_changes = all` no Helm indica complexidade de upgrade)

---

## 7. Conclusao

**Por que `gitlab.hml.alvocard.com.br`?**

GitLab esta em `hml` por **restricao tecnica**, nao por decisao arquitetural. A equipe possui autonomia apenas sobre as zonas `hml.alvocard.com.br` e `prod.alvocard.com.br` no Route53. O apex `alvocard.com.br` e gerenciado externamente. Como GitLab e shared e nao pertence exclusivamente a nenhum ambiente, a zona `hml` foi escolhida por ser onde os servicos de plataforma staging residem — e GitLab foi originalmente provisionado no contexto staging (DEC-074 Wave 6).

**Risco real**: Baixo. O DNS `hml` nao afeta funcionalidade nem seguranca. O impacto e puramente semantico/governanca. A recomendacao pragmatica e documentar via ADR e, quando/se o apex migrar para Route53, criar `gitlab.alvocard.com.br`.

**Score de conformidade**: 56% OK, 25% parcial, 19% ausente. Os 3 itens ausentes (Linkerd, PrometheusRule, ArgoCD) sao gaps operacionais que podem ser enderecados incrementalmente sem downtime.
