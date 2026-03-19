# Sessao 2026-03-19 — Producao Fases 1, 2, 3 Concluidas

**Data:** 2026-03-19 | **Status:** CONCLUIDO | **Cluster:** k8s-platform-prod
**Conta AWS:** 891377105802 | **Regiao:** us-east-1
**Referencia:** `2026-03-18-plano-ambiente-producao.md` (plano original 7 fases)

---

## Resumo Executivo

Sessao de execucao das Fases 1, 2 e 3 do plano de producao. Todas 3 fases concluidas com sucesso. Mesa tecnica Docker Hub rate limit resolvida com ECR mirror. 4 novos GAPs de seguranca de registry detectados (GAP-SEC-REGISTRY-01 a 04).

**Resultado:** Ambiente de producao com Vault HA, ESO, Keycloak, ArgoCD, Harbor e SonarQube operacionais.

---

## Fase 1 — Correcoes Imediatas (100%)

| Item | Status | Detalhe |
|------|--------|---------|
| WAF Block mode | CONCLUIDO | 3/3 ALBs internet-facing protegidos (GitLab + Keycloak + platform). Regras 30/40/50 em Block. |
| NetworkPolicies | CONCLUIDO | 24 policies em 5 namespaces (audit mode, ADR-070). Harbor 7 policies criadas. |
| TF prod providers | CONCLUIDO | 4 providers + OIDC data source + namespace fixes + 14 variaveis sensiveis |
| BUG fix postgresql | CONCLUIDO | Modulo postgresql prefixo hardcoded `staging/` corrigido para `var.environment` |
| DNS WSL2 | CONCLUIDO | resolv.conf corrigido (8.8.8.8 primeiro) |
| Credenciais estaticas | CONCLUIDO | Credenciais expiradas removidas do ~/.aws/credentials |

**Zero drift TF confirmado pos-apply.**

---

## Fase 2 — Segredos e Identidade (100%)

| Item | Status | Detalhe |
|------|--------|---------|
| Namespaces prod | CONCLUIDO | 12 namespaces criados (DEC-074 convention) |
| Modulos parametrizados | CONCLUIDO | 4 modulos: vault, external-secrets, keycloak, vault-config (var.environment) |
| Vault prod | CONCLUIDO | HA 3/3 Raft peers, KMS auto-unseal, root token revogado |
| ESO prod | CONCLUIDO | ClusterSecretStore vault-backend-prod (Valid, ReadWrite) |
| Vault Config prod | CONCLUIDO | K8s auth + policies + secrets seeded |
| Keycloak prod | CONCLUIDO | HA 2/2 Running (v26.5.1, RDS prod) |
| Kyverno labels | CONCLUIDO | inject-corporate-labels-prod-namespaces policy criada |

**NOTA:** Keycloak deployado via Helm direto — TF bloqueado por postgresql provider VPC-only constraint. Codificar no TF quando tunnel VPC disponivel.

---

## Fase 3 — GitOps e Qualidade (100%)

| Item | Status | Detalhe |
|------|--------|---------|
| ArgoCD prod | CONCLUIDO | 10/10 Running (HA: 3 app-controller + 2 server + 2 repo + 2 appset + 1 redis) |
| Harbor prod | CONCLUIDO | 9/9 Running (core 2/2 + registry 2/2 + portal 2/2 + jobservice + exporter + trivy) |
| SonarQube prod | CONCLUIDO | 1/1 Running (imagem via ECR mirror — Docker Hub rate limit workaround) |

**NOTA:** Deploy via Helm direto — TF bloqueado por postgresql provider VPC-only. Codificar no TF quando tunnel disponivel.

---

## Mesa Tecnica — Docker Hub Rate Limit

**Problema:** 48 pods ImagePullBackOff, 30 imagens Docker Hub unicas. Rate limit anonimo (100 pulls/6h) excedido.

**Analise:**

- Harbor Proxy Cache NAO viavel para kubelet — containerd no host != pod network (kubelet nao resolve Harbor via ClusterIP)
- ECR Pull-Through Cache — solucao ideal para longo prazo, mas requer configuracao por upstream registry

**Decisao:**

- **Imediato:** ECR mirror manual para SonarQube (imagem copiada para ECR, deployment atualizado)
- **Longo prazo:** ECR Pull-Through Cache para todas as imagens Docker Hub

**Licao aprendida:** Clusters com muitos pods Docker Hub atingem rate limit rapidamente apos restart massivo. Sempre usar registry mirror (ECR ou Harbor proxy) para imagens de terceiros.

---

## GAPs Novos Detectados

### GAP-SEC-REGISTRY-01 a 04 (Container Registry Security)

| GAP | Descricao | Prioridade |
|-----|-----------|------------|
| GAP-SEC-REGISTRY-01 | ECR scan_on_push nao habilitado nos repos ECR mirror | P1 |
| GAP-SEC-REGISTRY-02 | Sem Kyverno policy para restringir registries permitidos (bloquear Docker Hub direto) | P1 |
| GAP-SEC-REGISTRY-03 | Imagens sem digest pinning — tags mutaveis em uso | P2 |
| GAP-SEC-REGISTRY-04 | Sem image signing (Cosign/Notation) | P2 |

**Registrados em:** `2026-03-18-security-domain-vpn-prod.md` (secao P1-REGISTRY)

---

## Artefatos Produzidos

- PrometheusRules para monitoramento de registry/image pull
- Grafana dashboard para Container Registry
- Runbook dt005 atualizado

---

## Commits desta Sessao

```text
3a5912b fix(platform): Fase 1 correcoes imediatas — WAF ALBs + NetworkPolicies DEC-074 + TF prod gaps
0e51582 feat(platform): Fase 2 — modulos parametrizados + blocos prod (Vault, ESO, Keycloak)
b46c064 feat(platform): Vault prod HA deployed — 3/3 Raft peers, KMS auto-unseal, root token revoked
```

---

## Proximos Passos (Fases 4-7)

| Fase | Descricao | Bloqueador |
|------|-----------|------------|
| Fase 4 | Observabilidade (Prometheus + Loki + Tempo + WAF prod) | Nenhum — pode iniciar |
| Fase 5 | DNS + Certificados + ALBs prod | EXTERNO — delegacao NS prod.alvocard.com.br |
| Fase 6 | Resiliencia e DR (Velero + Linkerd + VPA) | Fase 5 |
| Fase 7 | VPN + Backstage prod | Fase 5 (Keycloak com URL publica) |

**Pendente TF:** Keycloak, ArgoCD, Harbor e SonarQube prod deployados via Helm direto. Codificar no Terraform quando tunnel VPC-only disponivel (postgresql provider requer acesso direto ao RDS).

**ECR Pull-Through Cache:** Configurar para eliminar dependencia de Docker Hub em pulls futuros.

---

*Documento produzido pelo Documentation Specialist — Sessao 2026-03-19*
*Referencia: `2026-03-18-plano-ambiente-producao.md`*
