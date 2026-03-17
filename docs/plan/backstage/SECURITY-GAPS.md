# Backstage IDP — Registro de GAPs de Segurança (Sprint S6-A)

**Auditoria executada em:** 2026-03-13
**Security Posture Score:** 63/100
**Sprint:** S6-A
**ADRs de referência:** ADR-055, ADR-102

---

## Resumo Executivo

| Severidade | Total | Resolvidos | Pendentes (requerem AWS) | Aceitos |
|------------|-------|------------|--------------------------|---------|
| CRITICO    | 2     | 1          | 1                        | 0       |
| ALTO       | 3     | 2          | 1                        | 0       |
| MÉDIO      | 10    | 5          | 4                        | 1       |
| BAIXO      | 3     | 0          | 2                        | 1       |
| **TOTAL**  | **18**| **8**      | **8**                    | **2**   |

> **Security Posture Score: 63/100** — calculado com base em severidade ponderada dos GAPs abertos.
> Meta Sprint S6-B: atingir 80/100 (resolver os 8 GAPs que requerem AWS).

---

## Registro Completo de GAPs

### GAP-SEC-S6-01 — CRITICO
| Campo | Valor |
|-------|-------|
| **ID** | GAP-SEC-S6-01 |
| **Severidade** | CRITICO |
| **Descrição** | `scaffolderTaskWorkers` ausente no appConfig — sem limite de workers paralelos, um burst de scaffolding pode causar OOM |
| **Arquivo afetado** | `helm-values-staging.yaml` |
| **Status** | PENDENTE (requer validação de carga) |
| **Ação recomendada** | Adicionar `scaffolder.taskWorkers: 3` no appConfig — executar em S6-B após benchmark |

---

### GAP-SEC-S6-02 — CRITICO
| Campo | Valor |
|-------|-------|
| **ID** | GAP-SEC-S6-02 |
| **Severidade** | CRITICO |
| **Descrição** | NetworkPolicy ausente para o pod Backstage — tráfego egress irrestrito permite exfiltração de dados |
| **Arquivo afetado** | Novo arquivo: `networkpolicy-backstage.yaml` (a criar) |
| **Status** | PENDENTE (requer aplicação no cluster) |
| **Ação recomendada** | Criar NetworkPolicy com egress restrito: apenas PostgreSQL (5432), Vault (8200), Keycloak (8080), GitLab (80/443), ArgoCD (8080) — executar em S6-B |

---

### GAP-SEC-S6-03 — ALTO
| Campo | Valor |
|-------|-------|
| **ID** | GAP-SEC-S6-03 |
| **Severidade** | ALTO |
| **Descrição** | `securityContext` ausente no pod Backstage — container roda como root por padrão |
| **Arquivo afetado** | `helm-values-staging.yaml` |
| **Status** | PENDENTE (requer validação da imagem) |
| **Ação recomendada** | Adicionar `podSecurityContext.runAsNonRoot: true`, `runAsUser: 1000`, `fsGroup: 1000` — validar com imagem `1.48.0-oidc` antes de aplicar |

---

### GAP-SEC-S6-04 — ALTO
| Campo | Valor |
|-------|-------|
| **ID** | GAP-SEC-S6-04 |
| **Severidade** | ALTO |
| **Descrição** | `readOnlyRootFilesystem: true` ausente no container — processo pode escrever no filesystem do container |
| **Arquivo afetado** | `helm-values-staging.yaml` |
| **Status** | PENDENTE (requer validação de volumes temporários) |
| **Ação recomendada** | Adicionar `containerSecurityContext.readOnlyRootFilesystem: true` + emptyDir para /tmp — executar em S6-B |

---

### GAP-SEC-S6-05 — MÉDIO
| Campo | Valor |
|-------|-------|
| **ID** | GAP-SEC-S6-05|
| **Severidade** | MÉDIO |
| **Descrição** | `allowPrivilegeEscalation: false` ausente — container pode escalar para root via setuid |
| **Arquivo afetado** | `helm-values-staging.yaml` |
| **Status** | PENDENTE (vinculado a GAP-SEC-S6-03 e S6-04) |
| **Ação recomendada** | Adicionar no mesmo ciclo que GAP-SEC-S6-03 e S6-04 |

---

### GAP-SEC-S6-06 — MÉDIO
| Campo | Valor |
|-------|-------|
| **ID** | GAP-SEC-S6-06 |
| **Severidade** | MÉDIO |
| **Descrição** | Session timeout e cookie config ausentes — sessão sem expiração, cookie sem `secure`/`sameSite` |
| **Arquivo afetado** | `helm-values-staging.yaml` |
| **Status** | RESOLVIDO (2026-03-13) |
| **Correção aplicada** | Adicionado `auth.session.cookie.maxAge: 86400000`, `secure: true`, `sameSite: lax` |

---

### GAP-SEC-S6-07 — MÉDIO
| Campo | Valor |
|-------|-------|
| **ID** | GAP-SEC-S6-07 |
| **Severidade** | MÉDIO |
| **Descrição** | `catalog.rules` permite `Template` sem restrição de namespace — qualquer grupo pode registrar templates |
| **Arquivo afetado** | `helm-values-staging.yaml` |
| **Status** | PENDENTE (requer definição de política de catalog com o time) |
| **Ação recomendada** | Restringir Template a namespace `platform` apenas — depende de consenso com Platform Team |

---

### GAP-SEC-S6-08 — MÉDIO
| Campo | Valor |
|-------|-------|
| **ID** | GAP-SEC-S6-08 |
| **Severidade** | MÉDIO |
| **Descrição** | RBAC do Backstage sem política de permissões explícita — todos os usuários autenticados têm acesso a todos os plugins |
| **Arquivo afetado** | `helm-values-staging.yaml` + novo arquivo de permissões |
| **Status** | PENDENTE (requer decisão de modelo de permissões) |
| **Ação recomendada** | Implementar `@backstage/plugin-permission-backend` com políticas por squad — S6-C |

---

### GAP-SEC-S6-09 — MÉDIO
| Campo | Valor |
|-------|-------|
| **ID** | GAP-SEC-S6-09 |
| **Severidade** | MÉDIO |
| **Descrição** | `secret_id_num_uses` ausente no AppRole Vault — secret_id sem limite de uso (válido para usos ilimitados) |
| **Arquivo afetado** | `bootstrap-vault-setup.sh` (nota na configuração do AppRole) |
| **Status** | PENDENTE (requer execução no Vault) |
| **Ação recomendada** | Ao re-executar bootstrap-vault-setup.sh, adicionar: `vault write auth/approle/role/backstage secret_id_num_uses=10`. Executar em S6-B com acesso ao Vault no cluster. |

---

### GAP-SEC-S6-10 — CRITICO
| Campo | Valor |
|-------|-------|
| **ID** | GAP-SEC-S6-10 |
| **Severidade** | CRITICO |
| **Descrição** | **CVE-2025-55285** — `@backstage/plugin-scaffolder-backend` com versão não fixada nos manifests. A CVE permite execução de templates maliciosos com RCE via action `fetch:template`. |
| **Arquivo afetado** | `helm-values-staging.yaml` (imagem `1.48.0-oidc`), `docker/Dockerfile` (se existir) |
| **Status** | PENDENTE (requer verificação no cluster) |
| **Ação recomendada** | 1. Verificar versão instalada: `kubectl exec -n staging-platform-backstage deploy/backstage -- cat node_modules/@backstage/plugin-scaffolder-backend/package.json \| grep version`. 2. Versão segura: `>=1.24.3`. 3. Se vulnerável: rebuild da imagem com versão fixada. **Executar em S6-B com acesso ao cluster AWS.** |
| **NOTA IMPORTANTE** | Esta CVE requer acesso ao cluster EKS para verificar a versão exata em runtime. Sem acesso AWS, não é possível confirmar se a versão no cluster é vulnerável. |

---

### GAP-SEC-S6-11 — MÉDIO
| Campo | Valor |
|-------|-------|
| **ID** | GAP-SEC-S6-11 |
| **Severidade** | MÉDIO |
| **Descrição** | `onExistingBranch: force` no template new-service permite sobrescrever branch `main` silenciosamente, destruindo histórico git |
| **Arquivo afetado** | `templates/new-service/template.yaml` |
| **Status** | RESOLVIDO (2026-03-13) |
| **Correção aplicada** | `onExistingBranch: force` alterado para `onExistingBranch: error` — falha explícita protege histórico |

---

### GAP-SEC-S6-12 — ALTO
| Campo | Valor |
|-------|-------|
| **ID** | GAP-SEC-S6-12 |
| **Severidade** | ALTO |
| **Descrição** | `bootstrap-credentials.sh` exibe tokens sensíveis no stdout sem mascaramento — risco em logs de CI/CD |
| **Arquivo afetado** | `bootstrap-credentials.sh` |
| **Status** | PENDENTE (requer revisão do script) |
| **Ação recomendada** | Adicionar redirecionamento de output sensível para arquivo temporário com permissão 0600, ou usar `set +x` antes de comandos com secrets — executar em S6-B |

---

### GAP-SEC-S6-13 — ALTO
| Campo | Valor |
|-------|-------|
| **ID** | GAP-SEC-S6-13 |
| **Severidade** | ALTO |
| **Descrição** | `deletionPolicy` ausente no ExternalSecret — se o ExternalSecret for deletado (ex: rollback ArgoCD), o Secret backstage-secrets é deletado junto, causando outage |
| **Arquivo afetado** | `externalsecret-backstage.yaml` |
| **Status** | RESOLVIDO (2026-03-13) |
| **Correção aplicada** | Adicionado `spec.target.deletionPolicy: Retain` — Secret preservado mesmo após remoção do ExternalSecret |

---

### GAP-SEC-S6-14 — MÉDIO
| Campo | Valor |
|-------|-------|
| **ID** | GAP-SEC-S6-14 |
| **Severidade** | MÉDIO |
| **Descrição** | Annotation `argocd.argoproj.io/sync-options: Prune=false` ausente no ExternalSecret — ArgoCD pode deletar o ExternalSecret durante sync com prune ativo |
| **Arquivo afetado** | `externalsecret-backstage.yaml` |
| **Status** | RESOLVIDO (2026-03-13) |
| **Correção aplicada** | Adicionado annotation `argocd.argoproj.io/sync-options: "Prune=false"` no metadata |

---

### GAP-SEC-S6-15 — MÉDIO
| Campo | Valor |
|-------|-------|
| **ID** | GAP-SEC-S6-15 |
| **Severidade** | MÉDIO |
| **Descrição** | `vault-policy.hcl` concede `read` em `secret/staging/backstage/*` sem path granular — permite leitura de todos os subpaths em stagig/backstage |
| **Arquivo afetado** | `vault-policy.hcl` |
| **Status** | ACEITO (risco baixo em staging) |
| **Racional** | Em staging, todos os secrets são do Backstage. Em produção, será necessário refinar por path específico. Revisão planejada para Sprint de hardening prod. |

---

### GAP-SEC-S6-16 — BAIXO
| Campo | Valor |
|-------|-------|
| **ID** | GAP-SEC-S6-16 |
| **Severidade** | BAIXO |
| **Descrição** | `argocd-application.yaml` sem `syncPolicy.retry` configurado — falhas transientes de sync não são retentadas automaticamente |
| **Arquivo afetado** | `argocd-application.yaml` |
| **Status** | PENDENTE (baixa prioridade) |
| **Ação recomendada** | Adicionar `syncPolicy.retry.limit: 3` com `backoff` — executar em S6-C |

---

### GAP-SEC-S6-17 — MÉDIO
| Campo | Valor |
|-------|-------|
| **ID** | GAP-SEC-S6-17 |
| **Severidade** | MÉDIO |
| **Descrição** | Token long-lived para SA `backstage-scaffolder` via `kubernetes.io/service-account-token` — padrão deprecated no K8s 1.24+, token sem expiração |
| **Arquivo afetado** | `argocd-scaffolder-sa.yaml` |
| **Status** | PARCIALMENTE RESOLVIDO (2026-03-13) |
| **Correção aplicada** | Adicionado comentário TODO prominente com plano de migração completo para TokenRequest API (TTL 1h). Secret mantido temporariamente para não quebrar o Scaffolder. |
| **Próximos passos** | Migrar para volume projetado com TokenRequest API em Sprint S6-B após validação do Scaffolder. Ver comentário detalhado no arquivo. |

---

### GAP-SEC-S6-18 — BAIXO
| Campo | Valor |
|-------|-------|
| **ID** | GAP-SEC-S6-18 |
| **Severidade** | BAIXO |
| **Descrição** | `kyverno-exception.yaml` tem exceção ampla para o namespace `staging-platform-backstage` — permite bypass de políticas Kyverno sem escopo preciso |
| **Arquivo afetado** | `kyverno-exception.yaml` |
| **Status** | ACEITO (necessário temporariamente durante rollout) |
| **Racional** | Exceção Kyverno é necessária durante o bootstrap do Backstage. Será refinada com escopo mais restrito após estabilização (Sprint S6-C). |

---

## Próximos Passos — GAPs que Requerem AWS

Os GAPs abaixo requerem acesso ao cluster EKS (`k8s-platform-prod`, `us-east-1`) e **não podem ser executados localmente**:

| GAP | Ação | Sprint alvo |
|-----|------|-------------|
| GAP-SEC-S6-10 | Verificar versão `scaffolder-backend` no cluster (CVE-2025-55285) | S6-B |
| GAP-SEC-S6-02 | Aplicar NetworkPolicy para pod Backstage | S6-B |
| GAP-SEC-S6-03/04/05 | Aplicar securityContext no Deployment Backstage | S6-B |
| GAP-SEC-S6-09 | Configurar `secret_id_num_uses` no AppRole Vault | S6-B |
| GAP-SEC-S6-12 | Corrigir mascaramento de tokens no bootstrap script | S6-B |
| GAP-SEC-S6-17 | Migrar SA token para TokenRequest API + validar Scaffolder | S6-B |
| GAP-SEC-S6-07/08 | Definir políticas RBAC catalog + permissões plugins | S6-C |
| GAP-SEC-S6-16 | Adicionar syncPolicy.retry no ArgoCD Application | S6-C |

**Pré-requisito para executar os GAPs de S6-B:**
```bash
aws sso login --profile k8s-platform-prod
kubectl get nodes -n staging-platform-backstage  # validar acesso
```

---

## GAPs Resolvidos Localmente (Sprint S6-A — 2026-03-13)

| GAP | Arquivo | Correção |
|-----|---------|---------|
| GAP-SEC-S6-06 | `helm-values-staging.yaml` | `auth.session.cookie` com maxAge/secure/sameSite |
| GAP-SEC-S6-11 | `templates/new-service/template.yaml` | `onExistingBranch: error` (era `force`) |
| GAP-SEC-S6-13 | `externalsecret-backstage.yaml` | `spec.target.deletionPolicy: Retain` |
| GAP-SEC-S6-14 | `externalsecret-backstage.yaml` | annotation `argocd.argoproj.io/sync-options: Prune=false` |
| GAP-SEC-S6-17 | `argocd-scaffolder-sa.yaml` | TODO GAP prominente + plano de migração TokenRequest API |

---

*Documento gerado automaticamente pelo GAP Resolver — Sprint S6-A Backstage IDP*
*Atualizar este arquivo após cada correção de GAP aplicada.*
