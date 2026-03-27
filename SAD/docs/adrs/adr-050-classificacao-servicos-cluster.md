# ADR-050: Classificacao de Servicos do Cluster em 4 Tiers

## Status
ACCEPTED

## Contexto
O cluster EKS opera 32+ servicos de plataforma (Linkerd, ArgoCD, Keycloak, Harbor, Loki, Tempo, Kyverno, ESO, etc.) sem uma taxonomia formal que distinga escopo, blast radius e regras de afinidade. Isso causa:
- Ambiguidade sobre quais servicos podem compartilhar nodes/namespaces e quais devem ser isolados
- Dificuldade em definir politicas FinOps (scale-to-zero, node affinity) por categoria
- Falta de criterios objetivos para decidir se um novo servico deve ser cluster-wide ou dedicado por ambiente

A mesa tecnica de 2026-03-27 deliberou a necessidade de um modelo de classificacao formal para servicos de infraestrutura.

## Decisao
Adotamos 4 tiers de classificacao para todos os servicos do cluster:

### Tier 1 — CLUSTER-WIDE
**Criterios**: Singleton no cluster, afeta todos os namespaces, falha = indisponibilidade total.
- Executa em system nodes com tolerations `node-type=system:NoSchedule`
- Namespace pattern: `kube-system` ou `{service-name}-system`
- Nao possui replica por ambiente (staging/prod)

| Servico | Namespace | Justificativa |
|---------|-----------|---------------|
| Calico (CNI) | kube-system | Networking L3/L4 cluster-wide |
| CoreDNS | kube-system | Resolucao DNS obrigatoria |
| Linkerd (control plane) | linkerd | Service mesh mTLS cluster-wide |
| Linkerd CNI | linkerd-cni | DaemonSet em todos os nodes |
| linkerd-viz | linkerd-viz | Metricas mesh cluster-wide |
| Kyverno | kyverno | Admission controller cluster-wide |
| Cluster Autoscaler | kube-system | Scaling de nodes |
| AWS EBS CSI | kube-system | Storage provisioner |
| AWS VPC CNI | kube-system | Pod networking AWS |
| metrics-server | kube-system | HPA/VPA dependency |

### Tier 2 — PLATFORM-SHARED
**Criterios**: Instancia unica consumida por multiplos ambientes (staging + prod), nao duplicavel sem custo significativo.
- Executa em system nodes (ADR-052)
- Namespace pattern: `shared-{service}` (ADR-053) ou excecao documentada
- Compartilhamento intencional, mitigado por RBAC/tenancy

| Servico | Namespace | Consumidores |
|---------|-----------|-------------|
| GitLab | staging-platform-gitlab | staging + prod pipelines (ADR-051) |
| Harbor | staging-platform-harbor | staging + prod image registry |
| SonarQube | staging-platform-sonarqube | staging + prod code analysis |
| Vault (prod) | prod-security-vault | staging + prod secrets via ESO |
| ArgoCD (staging) | staging-platform-argocd | staging apps |
| ArgoCD (prod) | prod-platform-argocd | prod apps |
| External Secrets Operator | external-secrets | staging + prod secret sync |
| Backstage | staging-platform-backstage | staging + prod developer portal/catalogo (reclassificado 2026-03-27 — instancia unica, prod-platform-backstage esvaziado) |

### Tier 3 — ENV-DEDICATED
**Criterios**: Uma instancia por ambiente (staging, prod), estado proprio, sem compartilhamento cross-env.
- Namespace pattern: `{env}-{domain}-{service}` (ex: `staging-platform-keycloak`)
- Pode executar em workload nodes se nao for critico

| Servico | Namespaces | Justificativa |
|---------|------------|---------------|
| Keycloak | staging-platform-keycloak, prod-platform-keycloak | Realms/users por ambiente |
| ~~Backstage~~ | ~~staging-platform-backstage, prod-platform-backstage~~ | ~~Catalog por ambiente~~ — **RECLASSIFICADO para Tier 2 PLATFORM-SHARED (2026-03-27)** |
| Loki | staging-observability-loki, prod-observability-loki | Logs isolados por env |
| Tempo | staging-observability-tempo, prod-observability-tempo | Traces isolados por env |
| Grafana | staging-observability-grafana, prod-observability-grafana | Dashboards por env |
| Prometheus | staging-observability-prometheus, prod-observability-prometheus | Metricas por env |

### Tier 4 — WORKLOAD
**Criterios**: Servico de aplicacao (nao infraestrutura), ciclo de vida gerido pelo time de produto.
- Namespace pattern: `{env}-{domain}-{app}` (ex: `staging-integration-api-gateway`)
- Executa em workload nodes, sem acesso a system nodes
- Gerido por ArgoCD Application, nao por Terraform

| Servico | Namespace pattern | Exemplo |
|---------|-------------------|---------|
| Hatch ETL | {env}-etl-hatch | staging-etl-hatch |
| VemSoft ETL | {env}-etl-vemsoft | staging-etl-vemsoft |
| iPaaS | {env}-integration-* | staging-integration-api-gateway |
| Backstage templates | {env}-{domain}-{app} | Por scaffolding |

### Criterios de Classificacao (Decision Tree)

```
O servico afeta TODOS os namespaces/pods?
  ├─ SIM → CLUSTER-WIDE (Tier 1)
  └─ NAO
      └─ E consumido por multiplos ambientes (staging+prod)?
          ├─ SIM → PLATFORM-SHARED (Tier 2)
          └─ NAO
              └─ E infraestrutura de plataforma?
                  ├─ SIM → ENV-DEDICATED (Tier 3)
                  └─ NAO → WORKLOAD (Tier 4)
```

## Consequencias
- **Positivo**: Criterios objetivos para node affinity, RBAC, FinOps policies e blast radius analysis
- **Positivo**: Novos servicos seguem decision tree — elimina debates caso a caso
- **Positivo**: Kyverno pode enforcar regras por tier (ex: Tier 4 proibido em system nodes)
- **Negativo**: Servicos existentes que nao seguem a convencao precisam de migracao gradual
- **Negativo**: Tier 2 (PLATFORM-SHARED) carrega risco de blast radius cross-env — requer mitigacao via ADR-051 e ADR-052
- **Mitigacao**: Excecoes ao tier assignment documentadas inline neste ADR e revisadas trimestralmente

## Validacao
- Todos os 32+ servicos classificados na tabela acima
- Kyverno policy `validate-tier-node-affinity` planejada (ADR-052)
- Revisao trimestral do tier assignment na mesa tecnica

## Changelog

| Data | Alteracao |
|------|-----------|
| 2026-03-27 | Criacao do ADR-050 com classificacao inicial de 32+ servicos |
| 2026-03-27 | Backstage reclassificado de Tier 3 (ENV-DEDICATED) para Tier 2 (PLATFORM-SHARED). Justificativa: developer portal/catalogo serve ambos ambientes com uma unica instancia. Namespace prod-platform-backstage esvaziado (workloads, secrets, ExternalSecrets deletados). TF module backstage_prod comentado. GAP-BACKSTAGE-PROD-INTEGRATION (P2) aberto: Backstage staging nao integra com ArgoCD prod nem Keycloak prod. |
| 2026-03-27 | SonarQube prod consolidado como PLATFORM-SHARED. Namespace prod-platform-sonarqube esvaziado (helm uninstall + ExternalSecret deletado). TF module sonarqube_prod comentado em sonarqube-prod.tf. FinOps target list atualizada. Instancia unica em staging-platform-sonarqube serve staging+prod. GitLab CI ja aponta para sonarqube.staging.internal. GAP-CONF-021 FECHADO. |

## Referencias
- ADR-015: Multi-Tenancy
- ADR-051: GitLab Shared Namespace Staging
- ADR-052: FinOps Safety Shared System Nodes
- ADR-053: Namespace Naming Convention Shared

Data: 2026-03-27
