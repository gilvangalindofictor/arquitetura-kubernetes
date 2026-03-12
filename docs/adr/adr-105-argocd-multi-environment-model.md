# ADR-105: Modelo ArgoCD Multi-Environment

**Data:** 2026-03-11
**Status:** Aceito
**Decisores:** Mesa Técnica (AWS Specialist, Security, SRE, Architecture)
**Contexto:** GAP-AUDIT-01 — AppProject do domínio `data` cobria staging-data-\* e prod-data-\*
numa única instância ArgoCD em staging. Mesa técnica convocada para definir o modelo canônico.

## Contexto

Plataforma Kubernetes single-cluster (`k8s-platform-prod`, conta AWS 891377105802).
Staging e prod são namespaces distintos no mesmo cluster EKS — não há cluster separado de prod.
ArgoCD atual: `staging-platform-argocd` namespace, v2.10.x.
Cluster de produção EKS: **não provisionado** (apps/production/ vazio, Terraform environments/prod/ sem cluster ArgoCD).

## Decisão

OPÇÃO A — 1 instância ArgoCD por ambiente (GitOps ortodoxo com namespace separação).

Quando o cluster/namespace de produção for provisionado:

- ArgoCD staging: namespace `staging-platform-argocd` — gerencia `staging-*` namespaces
- ArgoCD prod: namespace `prod-platform-argocd` (ou cluster EKS dedicado) — gerencia `prod-*` namespaces
- Cada instância usa `destination.server: https://kubernetes.default.svc` do seu próprio cluster
- AppProjects criados por ambiente via `appproject-template.yaml` parametrizado com `${ENV}`
- Nenhum AppProject cobre destinations de múltiplos ambientes

## Votos da Mesa Técnica

| Especialista | Voto | Razão Principal |
| --- | --- | --- |
| AWS Specialist | OPÇÃO A | ADR-050 já define cluster compartilhado; 2 instâncias ArgoCD no mesmo cluster ou clusters separados é overhead justificado quando prod for provisionado |
| Security Specialist | OPÇÃO A | Opção B coloca credenciais de prod em staging (lateral movement via CVE ArgoCD); segregação arquitetural > mitigações compensatórias |
| SRE Specialist | OPÇÃO A | Staging como canary de upgrade ArgoCD; blast radius controlado; `monitoring-multi-cluster` já usa Cluster Generator concebido para este modelo |
| Architecture Specialist | OPÇÃO A | `appproject-template.yaml` já parametrizado com `${ENV}`; ApplicationSets têm bloco `production` comentado pronto para descomentar; custo de migração B→A seria maior que adotar A desde o primeiro deploy de prod |

Resultado: 4-0 pela OPÇÃO A.

## Justificativa Consolidada

1. **Segurança (razão primária):** Uma instância ArgoCD em `staging-platform-argocd` com credenciais de prod representa privilege escalation path real — CVE ArgoCD → SA argocd-application-controller → Cluster Secret de prod → lateral movement para namespaces `prod-*`. Para plataforma financeira (FCT Consig), inadmissível.

2. **Infraestrutura já preparada:** O repositório foi inconscientemente construído para Opção A — `appproject-template.yaml` com `${ENV}`, `multi-env-services` ApplicationSet com production comentado, `monitoring-multi-cluster` com Cluster Generator. Custo de adoção é zero até prod ser provisionado.

3. **SRE:** Staging como canary platform para upgrades ArgoCD — versão nova validada em staging antes de prod. Blast radius isolado por instância. MTTR de prod não afetado por incidentes em staging.

4. **Custo atual:** Prod não existe ainda — não há overhead imediato. A decisão é prospectiva: quando prod for criado, usar `prod-platform-argocd`.

## Consequências

### Imediatas (hoje)

- **Remover destinations `prod-data-*` do appproject-data.yaml** — prod cluster não existe; destinations para namespaces inexistentes são noise de configuração e risco latente
- **Remover verbo `escalate`** do ClusterRole `platform-provisioner` (recomendação Security)
- **Restringir `sourceRepos: ['*']`** nos AppProjects legados `platform.yaml` e `applications.yaml`

### Quando prod for provisionado

- Criar namespace `prod-platform-argocd` com Helm release ArgoCD dedicado
- Descomentar bloco `production` nos ApplicationSets `cluster-services` e `multi-env-services`
- Registrar cluster prod no ArgoCD staging **SOMENTE durante migração** — remover após prod ArgoCD estar operacional
- Atualizar `ARGOCD_SERVER` nas variáveis CI/CD de cada projeto para apontar para instância prod
- Duplicar `ARGOCD_TOKEN` por projeto (1 token staging + 1 token prod)

### Backstage S6

- Plugin `@backstage-community/plugin-argocd` configurado com `instances:` multi (staging + prod)
- 2 tokens ArgoCD armazenados no Vault: `secret/staging/platform/argocd/token` e `secret/prod/platform/argocd/token`

## GAPs de Segurança Identificados pela Mesa (a resolver)

| GAP-ID | Descrição | Prioridade |
| --- | --- | --- |
| GAP-SEC-01 | Verbo `escalate` no ClusterRole `platform-provisioner` — privilege escalation path | P1 CRÍTICO |
| GAP-SEC-02 | `sourceRepos: ['*']` nos AppProjects `platform.yaml` e `applications.yaml` | P1 ALTA |
| GAP-SEC-03 | Sem Kyverno ClusterPolicies para validar AppProject destinations/sourceRepos | P2 MÉDIA |
| GAP-SEC-04 | Sem ServiceMonitor dedicado para ArgoCD server (apenas cobertura via job label) | P3 BAIXA |

## Referências

- ADR-050: Shared EKS cluster decision
- ADR-077: ApplicationSet controller HA (2 réplicas)
- ADR-102: Backstage IDP stack (plugin ArgoCD)
- ADR-104: CI/CD Onboarding via Manifesto Base
- `appproject-template.yaml`: `domains/platform-core/app-provisioning/templates/appproject-template.yaml`
- `monitoring-multi-cluster.yaml`: ApplicationSet com Cluster Generator já preparado para Opção A
