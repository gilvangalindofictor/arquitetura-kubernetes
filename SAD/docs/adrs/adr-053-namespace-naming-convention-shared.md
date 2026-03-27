# ADR-053: Namespace Naming Convention — Prefixo shared- Obrigatorio

## Status
ACCEPTED

## Contexto
O cluster utiliza a convencao `{env}-{domain}-{service}` para namespaces (ex: `staging-platform-keycloak`, `prod-observability-loki`). Servicos classificados como PLATFORM-SHARED (Tier 2 — ADR-050) sao consumidos por multiplos ambientes mas residem fisicamente em um unico namespace. Sem convencao explicita:
- Servicos compartilhados ficam "escondidos" em prefixos de ambiente (ex: `staging-platform-harbor` serve producao mas o nome sugere exclusividade staging)
- Automacoes FinOps baseadas em prefixo `staging-*` podem atingir servicos compartilhados por engano
- Novos membros da equipe nao conseguem distinguir servicos dedicados de compartilhados pela nomenclatura

## Decisao
Novos servicos PLATFORM-SHARED (Tier 2) DEVEM usar o prefixo `shared-` no namespace.

### Convencao

```
PATTERN:  shared-{domain}-{service}
REGEX:    ^shared-[a-z]+-[a-z0-9-]+$
EXEMPLOS: shared-platform-gitlab
          shared-platform-harbor
          shared-platform-sonarqube
          shared-security-vault
```

### Regras

1. **OBRIGATORIO para novos servicos**: Todo novo servico classificado como Tier 2 (ADR-050) DEVE usar prefixo `shared-`
2. **REGEX de validacao**: `^shared-[a-z]+-[a-z0-9-]+$` — dominio lowercase, service lowercase com hifens
3. **Excecoes documentadas**: Servicos Tier 2 existentes que NAO usam prefixo `shared-` sao excecoes aceitas neste ADR
4. **Labels obrigatorias**: Todos os namespaces Tier 2 (inclusive excecoes) DEVEM ter label `s6c.io/tier: platform-shared`

### Tabela Completa — Namespaces Tier 2

| Servico | Namespace Atual | Convencao shared- | Status | Justificativa Excecao |
|---------|----------------|-------------------|--------|----------------------|
| GitLab | staging-platform-gitlab | shared-platform-gitlab | EXCECAO | ADR-051 — custo migracao PVC desproporcional |
| Harbor | staging-platform-harbor | shared-platform-harbor | EXCECAO | PVCs RWO, DNS/certs consolidados |
| SonarQube | staging-platform-sonarqube | shared-platform-sonarqube | EXCECAO | Stateful, DNS consolidado |
| Vault (prod) | prod-security-vault | shared-security-vault | EXCECAO | 51 ESOs dependem do endpoint atual |
| ArgoCD (staging) | staging-platform-argocd | — | NAO APLICA | ENV-DEDICATED (Tier 3), nao shared |
| ArgoCD (prod) | prod-platform-argocd | — | NAO APLICA | ENV-DEDICATED (Tier 3), nao shared |
| ESO | external-secrets | shared-platform-eso | EXCECAO | Helm chart default namespace, CRDs cluster-scoped |

### Kyverno Policy — Enforcement

```yaml
# Planejado — sera implementado como ClusterPolicy
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: validate-shared-namespace-naming
spec:
  validationFailureAction: Audit
  rules:
    - name: shared-prefix-required
      match:
        any:
          - resources:
              kinds:
                - Namespace
              selector:
                matchLabels:
                  s6c.io/tier: platform-shared
      validate:
        message: "Namespaces with label s6c.io/tier=platform-shared must use prefix 'shared-' unless listed as exception in ADR-053"
        pattern:
          metadata:
            name: "shared-*"
      exclude:
        any:
          - resources:
              names:
                - staging-platform-gitlab
                - staging-platform-harbor
                - staging-platform-sonarqube
                - prod-security-vault
                - external-secrets
```

### Convencao Completa de Namespaces (Consolidada)

```
TIER 1 (CLUSTER-WIDE):    kube-system | {service}-system | {service}
                           Regex: ^(kube-system|[a-z-]+-system|linkerd(-viz|-cni)?|kyverno|calico-system)$

TIER 2 (PLATFORM-SHARED): shared-{domain}-{service}
                           Regex: ^shared-[a-z]+-[a-z0-9-]+$
                           Excecoes: staging-platform-{gitlab,harbor,sonarqube}, prod-security-vault, external-secrets

TIER 3 (ENV-DEDICATED):   {env}-{domain}-{service}
                           Regex: ^(staging|prod)-(platform|security|observability)-[a-z0-9-]+$

TIER 4 (WORKLOAD):         {env}-{domain}-{app}
                           Regex: ^(staging|prod)-(integration|etl|banking|api)-[a-z0-9-]+$
```

## Consequencias
- **Positivo**: Servicos compartilhados identificaveis por nome — `kubectl get ns | grep shared-`
- **Positivo**: Automacoes FinOps podem excluir `shared-*` com seguranca
- **Positivo**: Regex validavel por Kyverno — enforcement automatizado para novos namespaces
- **Negativo**: 5 excecoes existentes nao seguem a convencao — requer label como fallback
- **Negativo**: Migracao de namespaces existentes e cara (PVCs, DNS, certs, state) e nao sera realizada
- **Mitigacao**: Label `s6c.io/tier=platform-shared` como mecanismo universal de discovery, independente do nome
- **Mitigacao**: Excecoes listadas explicitamente neste ADR e na Kyverno policy exclude

## Condicao de Revisao
- Quando cluster for dividido em staging/prod dedicados, excecoes serao eliminadas naturalmente
- Novos servicos Tier 2 que nao usarem `shared-` devem abrir ADR de excecao

## Validacao
- `kubectl get ns -l s6c.io/tier=platform-shared` retorna todos os namespaces Tier 2
- Kyverno policy em modo Audit sem violacoes para novos namespaces
- Regex testada contra todos os namespaces existentes

## Referencias
- ADR-050: Classificacao de Servicos do Cluster em 4 Tiers
- ADR-051: GitLab Shared Namespace Staging
- ADR-052: FinOps Safety Shared System Nodes
- ADR-015: Multi-Tenancy

Data: 2026-03-27
