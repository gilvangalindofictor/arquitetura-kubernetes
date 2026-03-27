# ADR-051: GitLab Permanece em staging-platform-gitlab como Servico Shared

## Status
ACCEPTED

## Contexto
O GitLab (v18.9.1) esta deployado no namespace `staging-platform-gitlab` e serve como SCM/CI-CD tanto para pipelines staging quanto para pipelines de producao. Isso viola a convencao ADR-053 que define prefixo `shared-` para servicos compartilhados entre ambientes.

Alternativas avaliadas na mesa tecnica de 2026-03-27:
1. **Migrar para `shared-platform-gitlab`** — correto pela convencao, porem exige: re-deploy completo, migracao de PVCs (Git repos, LFS, CI artifacts), atualizacao de DNS/certs, reconfiguracao de todos os runners, downtime de CI/CD
2. **Instancia dedicada prod** — custo alto (RDS adicional, 8+ GB RAM, storage duplicado), baixo beneficio (GitLab nao e multi-tenant por natureza neste cluster)
3. **Manter em `staging-platform-gitlab` com mitigacoes** — zero downtime, custo zero, risco mitigavel

## Decisao
GitLab permanece no namespace `staging-platform-gitlab` como excecao documentada a ADR-053. Esta e uma decisao intencional, nao um debito tecnico.

### Justificativas
1. **Custo de migracao desproporcional**: PVCs (Git repos, CI artifacts, container registry) nao podem ser movidos entre namespaces sem downtime completo
2. **Servico stateful critico**: GitLab e o unico ponto de CI/CD — migracao implica em janela de indisponibilidade para todos os pipelines
3. **Sem beneficio funcional**: Renomear namespace nao altera isolamento, RBAC ou blast radius
4. **Precedente arquitetural**: O namespace ja esta consolidado em DNS, certificados ACM, ArgoCD Applications e Terraform state

### Mitigacoes Aplicadas
1. **nodeAffinity para system nodes**: GitLab pods executam exclusivamente em nodes `node-type=system` via `nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution`, garantindo isolamento de workloads
2. **NetworkPolicy**: Ingress restrito a namespaces autorizados (ArgoCD, runners, Backstage)
3. **ResourceQuota**: Limits definidos para prevenir resource starvation de outros servicos no mesmo node group
4. **Documentacao explicita**: Este ADR e a unica fonte de verdade para a decisao; referenciado em ADR-050 (Tier 2) e ADR-053 (excecoes)

### Configuracao nodeAffinity

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: node-type
              operator: In
              values:
                - system
```

## Consequencias
- **Positivo**: Zero downtime, zero custo de migracao, zero risco operacional
- **Positivo**: nodeAffinity garante que GitLab roda em system nodes isolados de workloads
- **Negativo**: Nome do namespace nao segue convencao `shared-` — pode causar confusao para novos membros
- **Negativo**: Blast radius inclui staging e prod CI/CD no mesmo namespace
- **Mitigacao**: Label `s6c.io/tier=platform-shared` aplicada ao namespace para discovery automatizada
- **Mitigacao**: Kyverno policy futura pode validar label de tier independente do nome do namespace

## Condicao de Revisao
Esta excecao sera reavaliada quando:
- GitLab for migrado para SaaS (GitLab.com ou Dedicated)
- Cluster sofrer split staging/prod em clusters dedicados
- Custo de migracao PVC cair significativamente (ex: Velero namespace-rename)

## Validacao
- `kubectl get pods -n staging-platform-gitlab -o wide` confirma nodes system
- NetworkPolicy auditada via `kubectl get netpol -n staging-platform-gitlab`
- Terraform state referencia namespace correto

## Referencias
- ADR-050: Classificacao de Servicos do Cluster em 4 Tiers
- ADR-053: Namespace Naming Convention Shared
- GitLab Helm Chart: nodeAffinity support

Data: 2026-03-27
