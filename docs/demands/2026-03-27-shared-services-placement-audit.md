# Shared Services Placement Audit

> **Data**: 2026-03-27
> **Auditor**: Platform Compliance Auditor
> **Cluster**: k8s-platform-prod (18 nodes: 5 system, 2 critical, 11 workloads)
> **Evidencia**: kubectl live (2026-03-27)

---

## 1. Resumo Executivo

O cluster opera com 52 namespaces e 363+ pods. A analise identificou **7 inconsistencias criticas** onde servicos shared (consumidos por staging+prod) estao posicionados em namespaces com prefixo `staging-*`, criando risco real de indisponibilidade caso o FinOps Lambda ou uma acao operacional desligue ou escale down recursos staging.

**Score de Conformidade**: 14/21 servicos conformes (67%) | **7 inconsistencias** (33%)

---

## 2. Tabela Principal de Posicionamento

### 2.1 Servicos CLUSTER-WIDE (DaemonSets / Singleton sem env prefix)

| Servico | Namespace(s) | Pods | Tipo | Consumidores | Problema? | Severidade |
|---------|-------------|------|------|-------------|-----------|------------|
| Calico (CNI) | `kube-system` | 19 (18 node + 1 controller + 1 typha) | DaemonSet | Todo cluster | NAO | - |
| Linkerd Control Plane | `linkerd` | 3 | Deployment | Todo cluster | NAO | - |
| Linkerd CNI | `linkerd-cni` | 19 | DaemonSet | Todo cluster | NAO | - |
| Linkerd Viz | `linkerd-viz` | 4 | Deployment | Todo cluster | NAO | - |
| Velero | `velero` | 19 (1 server + 18 node-agent) | DaemonSet + Deploy | Todo cluster | NAO | - |
| Cluster Autoscaler | `kube-system` | 1 | Deployment | Todo cluster | NAO | - |
| RabbitMQ Operator | `rabbitmq-system` | 1 | Deployment | staging + prod | NAO | - |
| Platform Operator | `platform-system` | 2 | Deployment | Todo cluster | NAO | - |
| AWS LB Controller | `kube-system` | 2 | Deployment | Todo cluster | NAO | - |

**Veredicto**: Todos conformes. Namespaces neutros sem prefixo de ambiente.

### 2.2 Servicos SEPARADOS POR AMBIENTE (instancias independentes)

| Servico | Namespace Staging | Namespace Prod | Pods STG | Pods PRD | Problema? | Severidade |
|---------|------------------|----------------|----------|----------|-----------|------------|
| ArgoCD | `staging-platform-argocd` | `prod-platform-argocd` | 11 | 5 | NAO | - |
| Keycloak | `staging-platform-keycloak` | `prod-platform-keycloak` | 1 | 2 | NAO | - |
| Vault | `staging-security-vault` | `prod-security-vault` | 2 | 3 | NAO | - |
| Harbor (prod) | - | `prod-platform-harbor` | - | 15 | NAO | - |
| External-DNS | `staging-platform-externaldns` | `prod-platform-externaldns` | 1 | 1 | NAO | - |
| SonarQube | `staging-platform-sonarqube` | `prod-platform-sonarqube` (ESVAZIADO) | 1 | 0 (namespace esvaziado 2026-03-27, reclassificado PLATFORM-SHARED ADR-050) | RESOLVIDO | - |
| Backstage | `staging-platform-backstage` | `prod-platform-backstage` (ESVAZIADO) | 1 | 0 (namespace esvaziado 2026-03-27, reclassificado PLATFORM-SHARED ADR-050) | RESOLVIDO | - |
| Redis (infra) | `staging-data-infrastructure` | `prod-data-infrastructure` | 1 | 1 | NAO | - |
| RabbitMQ (data) | `staging-data-rabbitmq` | `prod-data-rabbitmq` | 1 | 3 | NAO | - |
| Observability (Grafana+Prometheus+Loki+Tempo) | `staging-observability-monitoring` | `prod-observability-monitoring` | 78 | 48 | **SIM** (ver 2.3) | **P1** |

(*) Backstage prod: RESOLVIDO 2026-03-27. Namespace esvaziado (workloads, secrets, ExternalSecrets, Ingress deletados). Reclassificado como PLATFORM-SHARED (Tier 2) no ADR-050. Instancia unica em staging-platform-backstage.

(**) SonarQube prod: RESOLVIDO 2026-03-27. Namespace esvaziado (helm uninstall + ExternalSecret deletado). Reclassificado como PLATFORM-SHARED (Tier 2) no ADR-050. Instancia unica em staging-platform-sonarqube. TF module sonarqube_prod comentado. FinOps target list atualizada. GAP-CONF-021 FECHADO.

**Veredicto**: Modelo correto de separacao. POREM a observabilidade staging tem DaemonSets cluster-wide (ver abaixo).

### 2.3 Servicos INCONSISTENTES (shared em namespace staging)

| # | Servico | Namespace | Pods | Consumidores Reais | Problema | Severidade |
|---|---------|-----------|------|--------------------|----------|------------|
| **INC-01** | **GitLab** | `staging-platform-gitlab` | 15 (incl. runners) | staging + prod (CI/CD source, ArgoCD repos) | **CRITICO** -- instancia UNICA, namespace "staging" | **P0** |
| **INC-02** | **Harbor (staging)** | `harbor-system` | 9 | staging + prod (5 ExternalSecrets) | **ALTO** -- namespace neutro, mas ExternalSecrets prod dependem de vault-backend (staging Vault) | **P1** |
| **INC-03** | **ESO (External Secrets Operator)** | `staging-security-externalsecrets` | 3 | **TODO O CLUSTER** (60 ExternalSecrets em 20+ namespaces, incl. prod) | **CRITICO** -- controlador UNICO em namespace staging | **P0** |
| **INC-04** | **Kyverno** | `staging-governance-kyverno` | 6 | **TODO O CLUSTER** (12 ClusterPolicies, 7 ValidatingWebhooks) | **CRITICO** -- controlador UNICO em namespace staging | **P0** |
| **INC-05** | **cert-manager** | `staging-security-certmanager` | 3 | **TODO O CLUSTER** (ClusterIssuers, Certificates em harbor-system + staging) | **ALTO** -- controlador UNICO em namespace staging | **P1** |
| **INC-06** | **Observability DaemonSets (promtail + node-exporter)** | `staging-observability-monitoring` | 36 (18+18) | **TODOS OS NODES** (inclusive critical e system) | **MEDIO** -- DaemonSets cluster-wide em namespace staging | **P2** |
| **INC-07** | **Observability DaemonSet (loki-canary staging)** | `staging-observability-monitoring` | 11 | Todos os workload nodes | **BAIXO** -- duplicado (prod tambem tem loki-canary) | **P3** |

---

## 3. Analise Detalhada das Inconsistencias

### INC-01: GitLab em `staging-platform-gitlab` (P0)

**Fatos**:
- Instancia UNICA do GitLab no cluster (15 pods)
- ArgoCD staging referencia `http://gitlab.staging.internal/` para 3 repos (hatch-etl, vemsoft-etl, ccbcreator)
- 11 ExternalSecrets no namespace dependem do ClusterSecretStore `vault-backend` (staging Vault)
- GitLab Runners executam CI/CD para TODOS os projetos (staging + prod)
- NAO existe `prod-platform-gitlab`

**Risco FinOps**: O namespace `staging-platform-gitlab` NAO esta na lista `finops_prod_target_namespaces` e ESTA na lista `finops_prod_excluded_namespaces` (L73 de `finops-automation-prod.tf`). Portanto, a Lambda prod NAO o desliga. POREM, o FinOps staging opera por ASG scale-down (workload nodes -> 0). Se GitLab pods estiverem em workload nodes (confirmado: varios pods em workload nodes), o scale-down de workload nodes PODE evacuar GitLab se nao houver nodeAffinity para system/critical.

**Impacto se cair**: ArgoCD staging perde acesso aos repos GitLab-hosted -> apps ficam "Unknown". CI/CD para de funcionar para todos os projetos. Prod ArgoCD usa repos GitHub (nao afetado diretamente), mas pipelines de build param.

**Recomendacao**:
1. IMEDIATO: Verificar se GitLab tem nodeAffinity para critical/system nodes
2. MEDIO PRAZO: Renomear namespace para `shared-platform-gitlab` ou criar ADR documentando que GitLab e shared-by-design em namespace staging

### INC-02: Harbor staging em `harbor-system` com dependencias prod (P1)

**Fatos**:
- `harbor-system` namespace tem 9 pods (Harbor staging)
- 5 ExternalSecrets neste namespace usam `vault-backend` (staging Vault)
- Prod Harbor esta separado em `prod-platform-harbor` (15 pods) - CORRETO
- Harbor staging serve como registry para builds CI/CD que podem ser promovidos a prod
- `harbor-system` esta na `finops_prod_excluded_namespaces` (L72) - protegido

**Risco**: Baixo-medio. O namespace `harbor-system` nao segue a naming convention `{env}-{domain}-{product}` do SAD (L275). Se Harbor staging cair, builds CI/CD param, mas prod Harbor continua operando independentemente.

**Recomendacao**: Renomear para `staging-cicd-harbor` ou `shared-cicd-harbor` para alinhar com naming convention. Baixa urgencia.

### INC-03: ESO em `staging-security-externalsecrets` (P0)

**Fatos**:
- Instancia UNICA do External Secrets Operator (3 pods)
- Serve 60 ExternalSecrets em 20+ namespaces, incluindo:
  - 10 ExternalSecrets em namespaces `prod-*` (via ClusterSecretStore `vault-backend-prod`)
  - 50 ExternalSecrets em namespaces `staging-*` + `harbor-system` + `velero`
- Namespace `prod-security-externalsecrets` EXISTE mas esta VAZIO (0 pods)
- Namespace `external-secrets-system` EXISTE mas esta VAZIO (0 pods)
- O ESO controller e CLUSTER-SCOPED (processa ClusterSecretStores e ExternalSecrets em qualquer namespace)

**Risco FinOps**: O namespace esta na `finops_prod_excluded_namespaces` (L81). Protegido contra Lambda prod. Para Lambda staging, o ESO roda em workload nodes (confirmado: pod em `ip-10-0-138-21` workload + `ip-10-0-130-41` workload). Se workload nodes forem escalados para 0 no weekend, o ESO para e NENHUM ExternalSecret (staging NEM prod) sera reconciliado.

**Impacto se cair**: Secrets nao sao reconciliados. Se um secret expirar ou rotar enquanto ESO estiver down, pods prod que dependem desse secret falharao no restart. Vault tokens, DB passwords, OIDC credentials de prod ficam sem reconciliacao.

**Recomendacao**:
1. CRITICO: Mover ESO para namespace `shared-security-externalsecrets` ou `external-secrets-system` (ja existe, vazio)
2. CRITICO: Adicionar nodeAffinity para system nodes (sobrevive a scale-down de workloads)
3. ALTERNATIVA: Instanciar segundo ESO em `prod-security-externalsecrets` para servir apenas ClusterSecretStore `vault-backend-prod`

### INC-04: Kyverno em `staging-governance-kyverno` (P0)

**Fatos**:
- Instancia UNICA (6 pods: 3 admission + 1 background + 1 cleanup + 1 reports)
- 12 ClusterPolicies ATIVAS aplicadas a TODO o cluster
- 7 ValidatingWebhookConfigurations registradas (afetam admission de TODOS os namespaces)
- NAO existe `prod-governance-kyverno`

**Risco FinOps**: O namespace esta na `finops_prod_excluded_namespaces` (L100, como "kyverno"). POREM a exclusao lista "kyverno" e nao "staging-governance-kyverno" -- verificar se ha mismatch. Pods estao em workload nodes. Scale-down de workloads pode evacuar Kyverno.

**Impacto se cair**:
- Webhooks ficam ativos MAS o backend nao responde -> pod creation BLOQUEIA (failPolicy depende da config)
- Se failPolicy=Fail: deployments param em TODO o cluster
- Se failPolicy=Ignore: policies deixam de ser enforced, podendo criar resources non-compliant

**Recomendacao**:
1. CRITICO: Mover para namespace `shared-governance-kyverno` ou `kyverno-system`
2. CRITICO: Adicionar nodeAffinity para system nodes
3. Verificar failPolicy dos webhooks para entender impacto do downtime

### INC-05: cert-manager em `staging-security-certmanager` (P1)

**Fatos**:
- Instancia UNICA (3 pods)
- 2 ClusterIssuers ativos (`selfsigned-issuer`, `staging-internal-ca-issuer`)
- Certificates em `harbor-system`, `staging-platform-gitlab`, `staging-platform-keycloak`
- Pods em system node `ip-10-0-155-11` (BOA pratica - sobrevive a scale-down)
- NAO existem Certificates em namespaces prod (prod usa ACM/ALB para TLS)

**Risco FinOps**: Baixo. Pods estao em system nodes que NAO sao escalados para 0 pelo FinOps (min_system_nodes=2). Risco residual: se system nodes caem, cert-manager para, mas isso afeta todo o cluster anyway.

**Impacto se cair**: Certificados nao renovam. Se um cert expirar enquanto cert-manager estiver down, servicos com TLS interno falham (GitLab, Harbor staging, Keycloak staging). Prod nao usa cert-manager diretamente.

**Recomendacao**:
1. MEDIO PRAZO: Renomear para `shared-security-certmanager` ou `cert-manager` (naming padrao)
2. Baixa urgencia pois pods ja estao em system nodes e prod nao depende diretamente

### INC-06: Observability DaemonSets staging sao cluster-wide (P2)

**Fatos**:
- `promtail` (18 pods, namespace `staging-observability-monitoring`): roda em TODOS os 18 nodes
- `kube-prometheus-stack-prometheus-node-exporter` (18 pods): roda em TODOS os 18 nodes
- Esses DaemonSets coletam metricas/logs de nodes prod tambem (critical + workloads com pods prod)
- Prod TEM seu proprio `promtail-prod` (18 pods) mas **NAO tem node-exporter proprio**

**Risco**: Metricas de node (CPU, memory, disk) dos nodes que hospedam pods prod sao coletadas APENAS pelo stack staging. Se staging-observability cair, perde-se visibilidade de infra dos nodes prod.

**Impacto**: Perda de observabilidade infra-level para prod. Logs de pods prod sao coletados por ambos promtail (staging) e promtail-prod, entao ha redundancia para logs. Mas metricas de node nao tem redundancia.

**Recomendacao**:
1. Adicionar `kube-prometheus-stack-prometheus-node-exporter` no stack `prod-observability-monitoring`
2. Verificar se promtail staging pode ser restrito apenas a namespaces staging (node selector ou label selector)

### INC-07: loki-canary duplicado (P3)

**Fatos**:
- `staging-observability-monitoring/loki-canary`: 11 pods (workload nodes)
- `prod-observability-monitoring/loki-canary`: 11 pods (workload nodes)
- Ambos coexistem nos mesmos nodes

**Risco**: Nenhum risco de disponibilidade. E ate desejavel ter canary por stack. Custo marginal.

**Recomendacao**: Manter como esta. Sem acao necessaria.

---

## 4. Classificacao Consolidada

### CLUSTER-WIDE (conformes)
| Servico | Namespace | Status |
|---------|-----------|--------|
| Calico | `kube-system` | OK |
| Linkerd | `linkerd` / `linkerd-cni` / `linkerd-viz` | OK |
| Velero | `velero` | OK |
| Cluster Autoscaler | `kube-system` | OK |
| RabbitMQ Operator | `rabbitmq-system` | OK |
| Platform Operator | `platform-system` | OK |
| AWS LB Controller | `kube-system` | OK |

### SEPARADO POR ENV (conformes)
| Servico | Staging | Prod | Status |
|---------|---------|------|--------|
| ArgoCD | `staging-platform-argocd` | `prod-platform-argocd` | OK |
| Keycloak | `staging-platform-keycloak` | `prod-platform-keycloak` | OK |
| Vault | `staging-security-vault` | `prod-security-vault` | OK |
| Harbor prod | - | `prod-platform-harbor` | OK |
| External-DNS | `staging-platform-externaldns` | `prod-platform-externaldns` | OK |
| SonarQube | `staging-platform-sonarqube` | `prod-platform-sonarqube` | OK |
| Backstage | `staging-platform-backstage` | `prod-platform-backstage` (ESVAZIADO 2026-03-27) | RECLASSIFICADO -> PLATFORM-SHARED (ADR-050) |
| Redis | `staging-data-infrastructure` | `prod-data-infrastructure` | OK |
| RabbitMQ | `staging-data-rabbitmq` | `prod-data-rabbitmq` | OK |

### INCONSISTENTES (acao necessaria)
| Servico | Namespace Atual | Namespace Recomendado | Prioridade |
|---------|----------------|----------------------|------------|
| GitLab | `staging-platform-gitlab` | `shared-platform-gitlab` | **P0** |
| ESO | `staging-security-externalsecrets` | `shared-security-externalsecrets` ou `external-secrets-system` | **P0** |
| Kyverno | `staging-governance-kyverno` | `shared-governance-kyverno` ou `kyverno-system` | **P0** |
| cert-manager | `staging-security-certmanager` | `shared-security-certmanager` ou `cert-manager` | **P1** |
| Harbor staging | `harbor-system` | `staging-cicd-harbor` | **P2** |
| Observability node-exporter | `staging-observability-monitoring` | Adicionar ao `prod-observability-monitoring` | **P2** |

---

## 5. Analise de Risco: FinOps Weekend Shutdown

### Cenario: Lambda Staging executa scale-down de workload nodes para 0

| Servico Afetado | Node Type dos Pods | Sobrevive? | Consequencia |
|----------------|-------------------|------------|-------------|
| GitLab | workloads | **NAO** | CI/CD para, ArgoCD perde repos internos |
| ESO | workloads | **NAO** | Secrets nao reconciliam (staging E prod) |
| Kyverno | workloads | **NAO** | Admission webhooks falham ou ficam sem backend |
| cert-manager | **system** | **SIM** | Sobrevive (system min=2) |
| Observability staging | misto (system+workloads) | **PARCIAL** | DaemonSets em system sobrevivem, Deployments em workloads morrem |
| Harbor staging | misto (system+critical) | **PARCIAL** | Pods em system/critical sobrevivem |

### Cenario: Alguem deleta/drena namespace "staging-*" por engano

| Servico | Impacto em PROD |
|---------|----------------|
| `staging-security-externalsecrets` deletado | **CATASTROFICO** -- 10 ExternalSecrets prod param de reconciliar |
| `staging-governance-kyverno` deletado | **CRITICO** -- webhooks pendentes bloqueiam deployments ou ficam sem enforcement |
| `staging-platform-gitlab` deletado | **ALTO** -- CI/CD para, mas prod apps continuam rodando |
| `staging-security-certmanager` deletado | **MEDIO** -- certs nao renovam, prod usa ACM |

### Cenario: FinOps Prod Lambda escala down namespaces prod

| Servico | Protegido pela excluded list? | OK? |
|---------|------------------------------|-----|
| `staging-platform-gitlab` | SIM (L73) | OK |
| `staging-security-externalsecrets` | SIM (L81) | OK |
| `staging-governance-kyverno` | **PARCIAL** (lista tem "kyverno", nao nome completo) | **VERIFICAR** |
| `staging-security-certmanager` | NAO listado | **VERIFICAR** (cert-manager L90 lista "cert-manager" generico) |

---

## 6. Recomendacoes

### Acao Imediata (Sprint Atual)

| # | Acao | Esforco | Impacto |
|---|------|---------|---------|
| R-01 | Adicionar nodeAffinity `system` ou `critical` ao ESO deployment | 30min | Impede scale-down evacuar ESO |
| R-02 | Adicionar nodeAffinity `system` ou `critical` ao Kyverno | 30min | Impede scale-down evacuar Kyverno |
| R-03 | Verificar nodeAffinity do GitLab (pods em workload nodes) | 15min | Mapear risco real |
| R-04 | Verificar `finops_prod_excluded_namespaces` contra nomes reais dos namespaces | 15min | L100 lista "kyverno" mas namespace e "staging-governance-kyverno" |

### Medio Prazo (Proximo Sprint)

| # | Acao | Esforco | Impacto |
|---|------|---------|---------|
| R-05 | Mover ESO para `external-secrets-system` (namespace ja existe) | 2h | Alinhamento arquitetural |
| R-06 | Mover Kyverno para `kyverno-system` ou `shared-governance-kyverno` | 2h | Alinhamento arquitetural |
| R-07 | Renomear `staging-platform-gitlab` para `shared-platform-gitlab` | 4h (reconfig ArgoCD + ESO + DNS) | Clareza operacional |
| R-08 | Adicionar node-exporter DaemonSet ao stack prod-observability | 1h | Eliminiar dependencia de staging para metricas de infra |
| R-09 | Criar ADR documentando quais servicos sao shared e por que | 2h | Governanca |

### Longo Prazo (Q2 2026)

| # | Acao | Esforco | Impacto |
|---|------|---------|---------|
| R-10 | Instanciar segundo ESO em `prod-security-externalsecrets` (apenas para ClusterSecretStore prod) | 4h | Isolamento total staging/prod |
| R-11 | Renomear `harbor-system` para `staging-cicd-harbor` | 4h | Naming convention compliance |
| R-12 | Revisar naming convention no SAD para incluir prefixo `shared-` como tier oficial | 1h | Ja consta no SAD L275 mas nao esta implementado |

---

## 7. Dependencia ESO: Mapa de Blast Radius

Se o ESO (`staging-security-externalsecrets`) parar:

```
ESO DOWN
  |
  +-- ClusterSecretStore vault-backend (50 refs)
  |     +-- staging-data-hatch-etl (13 secrets)
  |     +-- staging-platform-gitlab (11 secrets)
  |     +-- harbor-system (5 secrets)
  |     +-- staging-observability-monitoring (3 secrets)
  |     +-- staging-data-vemsoft-etl (3 secrets)
  |     +-- staging-shared-ccbcreator (2 secrets)
  |     +-- staging-platform-argocd (2 secrets)
  |     +-- staging-platform-backstage (2 secrets)
  |     +-- staging-platform-keycloak (2 secrets)
  |     +-- staging-platform-sonarqube (2 secrets)
  |     +-- staging-security-vault (2 secrets)
  |     +-- staging-integration-ipaas (1 secret)
  |     +-- velero (1 secret)
  |     +-- prod-platform-sonarqube (1 secret) *** PROD ***
  |
  +-- ClusterSecretStore vault-backend-prod (10 refs)
        +-- prod-platform-keycloak (2 secrets) *** PROD ***
        +-- prod-platform-argocd (2 secrets) *** PROD ***
        +-- prod-platform-harbor (3 secrets) *** PROD ***
        +-- prod-observability-monitoring (2 secrets) *** PROD ***
        +-- prod-platform-backstage (0 secrets — ExternalSecret deletado 2026-03-27)
```

**Total prod secrets sem reconciliacao**: 11 ExternalSecrets em 6 namespaces prod.

---

## 8. Conclusao

O cluster tem um modelo hibrido onde a maioria dos servicos esta corretamente separada por ambiente, mas **3 controladores criticos cluster-wide** (ESO, Kyverno, cert-manager) e **1 servico shared** (GitLab) estao posicionados em namespaces com prefixo `staging-*`. Isso cria:

1. **Risco operacional**: scale-down de workload nodes no weekend pode evacuar ESO e Kyverno
2. **Risco cognitivo**: operadores podem assumir que "staging" pode ser desligado sem impacto em prod
3. **Risco de blast radius**: ESO down afeta 11 ExternalSecrets prod em 6 namespaces

As acoes R-01 e R-02 (nodeAffinity para system nodes) sao mitigacoes imediatas de baixo esforco. As acoes R-05 a R-07 (mover namespaces) sao a solucao definitiva.

---

## Apendice A: Pods por Namespace (snapshot 2026-03-27)

| Namespace | Pods | Classificacao |
|-----------|------|--------------|
| `kube-system` | 103 | CLUSTER-WIDE |
| `staging-observability-monitoring` | 78 | INCONSISTENTE (DaemonSets cluster-wide) |
| `prod-observability-monitoring` | 48 | PROD |
| `velero` | 19 | CLUSTER-WIDE |
| `linkerd-cni` | 19 | CLUSTER-WIDE |
| `staging-platform-gitlab` | 15 | INCONSISTENTE (shared) |
| `prod-platform-harbor` | 15 | PROD |
| `staging-platform-argocd` | 11 | STAGING |
| `harbor-system` | 9 | INCONSISTENTE (naming) |
| `staging-data-hatch-etl` | 8 | STAGING |
| `staging-governance-kyverno` | 6 | INCONSISTENTE (cluster-wide) |
| `prod-platform-argocd` | 5 | PROD |
| `linkerd-viz` | 4 | CLUSTER-WIDE |
| `linkerd` | 3 | CLUSTER-WIDE |
| `staging-security-certmanager` | 3 | INCONSISTENTE (cluster-wide) |
| `staging-security-externalsecrets` | 3 | INCONSISTENTE (cluster-wide) |
| `staging-shared-ccbcreator` | 3 | STAGING |
| `prod-data-rabbitmq` | 3 | PROD |
| `prod-security-vault` | 3 | PROD |
| `staging-security-vault` | 2 | STAGING |
| `staging-data-infrastructure` | 2 | STAGING |
| `prod-platform-keycloak` | 2 | PROD |
| `prod-platform-backstage` | 0 | ESVAZIADO (PLATFORM-SHARED 2026-03-27) |
| `platform-system` | 2 | CLUSTER-WIDE |
| `staging-platform-backstage` | 1 | STAGING |
| `staging-platform-keycloak` | 1 | STAGING |
| `staging-platform-externaldns` | 1 | STAGING |
| `staging-platform-sonarqube` | 1 | STAGING |
| `staging-platform-new-service` | 1 | STAGING |
| `staging-data-rabbitmq` | 1 | STAGING |
| `staging-data-redis-operator` | 1 | STAGING |
| `staging-data-vemsoft-etl` | 1 | STAGING |
| `prod-platform-externaldns` | 1 | PROD |
| `prod-platform-sonarqube` | 1 | PROD |
| `prod-data-infrastructure` | 1 | PROD |
| `rabbitmq-system` | 1 | CLUSTER-WIDE |
| `default` | 1 | DEFAULT |

## Apendice B: Referencia SAD

O SAD (L275) define o formato de namespaces como:
```
^(staging|prod|shared)-(platform|integration|data|operations|shared)(-[a-z0-9-]+)?$
```

O prefixo `shared-` JA esta previsto no SAD mas NAO foi implementado para nenhum namespace existente. Os namespaces `external-secrets-system`, `cert-manager`, `calico-system`, `linkerd`, `velero` usam o padrao upstream (sem prefixo env), o que e aceitavel para cluster-wide infra. O problema sao os servicos cluster-wide que foram criados com prefixo `staging-*` ao inves de `shared-*` ou sem prefixo.
