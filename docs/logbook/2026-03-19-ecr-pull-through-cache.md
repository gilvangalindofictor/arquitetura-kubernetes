# Logbook — ECR Pull-Through Cache: Modelo Hibrido com Harbor (2026-03-19)

**Data:** 2026-03-19
**Sessao:** Analise de especialistas + plano de implementacao
**Cluster:** k8s-platform-prod (EKS 1.34, us-east-1, conta 891377105802)
**Responsavel:** Platform Team
**Agentes:** AWS Specialist + Security Specialist + SRE/Observability

---

## 1. Contexto

Docker Hub rate limit (429 Too Many Requests) atingiu 30 imagens simultaneamente, causando ImagePullBackOff em 48 pods do cluster. A mesa tecnica foi convocada com 3 agentes especialistas (AWS, Security, SRE) para avaliar a arquitetura de registry e definir a solucao permanente.

A tentativa anterior de usar Harbor Proxy Cache como registry mirror foi descartada apos analise — Harbor opera dentro do pod network (CoreDNS), mas containerd/kubelet roda no host e nao resolve DNS do cluster.

---

## 2. Decisoes Tomadas

### D-1 — Harbor-only REJEITADO (3 motivos)

Avaliacao de usar Harbor como unico registry (substituir ECR e Docker Hub) foi rejeitada pelos 3 agentes:

1. **DNS:** containerd no node nao resolve `svc.cluster.local` — Harbor so e acessivel via CoreDNS (dentro do cluster)
2. **Bootstrap deadlock:** Harbor precisa de imagens para subir (registry, core, jobservice, trivy, portal), mas se Harbor E a unica fonte, nao ha como fazer o primeiro pull
3. **SPOF:** Harbor registry e jobservice sao single-replica sem PDB — outage do Harbor = outage de todos os pulls do cluster

### D-2 — Modelo hibrido aceito: Harbor (custom) + ECR Pull-Through (publico)

Divisao de responsabilidades:

- **Harbor:** imagens custom da organizacao (builds internos, CI/CD artifacts)
- **ECR Pull-Through Cache:** imagens publicas (Docker Official Library, vendors como HashiCorp, Grafana, etc)

### D-3 — ECR Public Gallery como upstream (sem Docker Hub)

Usar `public.ecr.aws` como upstream em vez de Docker Hub. Beneficios:

- Zero credenciais necessarias (sem PAT Docker Hub)
- Zero rate limit (ECR Public nao impoe limites para pulls via ECR Pull-Through)
- AWS mantem mirror de todas as Docker Official Library images
- Vendors (HashiCorp, Grafana, Bitnami, etc) publicam diretamente no ECR Public

### D-4 — 4 pull-through rules sem credenciais

| Regra | Upstream Registry | ECR Prefix | Credenciais |
|-------|-------------------|------------|-------------|
| ECR Public | public.ecr.aws | ecr-public | Nenhuma |
| Kubernetes (registry.k8s.io) | registry.k8s.io | k8s | Nenhuma |
| Quay.io | quay.io | quay | Nenhuma |
| GitHub Container Registry | ghcr.io | ghcr | Nenhuma |

### D-5 — Kyverno MutatingPolicy como safety net

ClusterPolicy do Kyverno para reescrever automaticamente image references de Docker Hub (`docker.io/*`) para ECR Pull-Through Cache (`891377105802.dkr.ecr.us-east-1.amazonaws.com/ecr-public/*`). Funciona como safety net para workloads que ainda nao foram migrados manualmente.

---

## 3. Artefatos Criados

### Modulo Terraform

- **Path:** `modules/ecr-pull-through-cache/`
- **Conteudo:** Pull-through cache rules + IAM policy para nodes EKS
- **Parametros:** 4 upstreams configurados sem credenciais

### ADRs

- **ADR-0XX:** Decisao de modelo hibrido Harbor + ECR Pull-Through Cache
- **ADR-0YY:** Decisao de usar ECR Public Gallery como upstream principal

---

## 4. GAPs — Status

| GAP | Descricao | Status |
|-----|-----------|--------|
| GAP-SEC-REGISTRY-01 | Harbor Proxy Cache != node-level mirror | RESOLVIDO (design) |
| GAP-SEC-REGISTRY-02 | Docker Hub rate limit 429 | RESOLVIDO (design) |
| GAP-SEC-REGISTRY-03 | ECR Pull-Through Cache como solucao | RESOLVIDO (design) |
| GAP-SEC-REGISTRY-04 | 48 pods ImagePullBackOff | PENDENTE (aguarda terraform apply) |

---

## 5. Proximos Passos

1. `terraform apply` do modulo `ecr-pull-through-cache` — criar rules + IAM
2. Rollout de imagens ECR nos 11 modulos Helm afetados (menor risco primeiro)
3. Deploy Kyverno MutatingPolicy (safety net para imagens nao migradas)
4. Validar 48 pods ImagePullBackOff resolvidos (GAP-SEC-REGISTRY-04)
5. Confirmar zero drift pos-apply (`terraform plan` → "No changes")

---

## 6. Licoes Aprendidas

### LL-1 — ECR Public Gallery elimina dependencia de Docker Hub

ECR Pull-Through Cache para Docker Hub requer PAT (Personal Access Token) — bloqueador operacional. Usando `public.ecr.aws` como upstream, zero credenciais sao necessarias. AWS mantem mirror de todas Docker Official Library images. Vendors publicam diretamente no ECR Public.

**Regra:** Sempre preferir ECR Public Gallery sobre Docker Hub para pull-through cache. Zero credenciais, zero rate limit.

### LL-2 — Harbor Proxy Cache: 3 bloqueadores arquiteturais para node-level mirror

Harbor nao serve como registry mirror para containerd/kubelet: (1) DNS nao resolve no host, (2) deadlock circular no bootstrap, (3) SPOF sem PDB.

**Regra:** Harbor serve pods (via CoreDNS). ECR serve nodes (via DNS AWS). Nunca misturar papeis.

---

**Preparado em:** 2026-03-19
**Session:** ECR Pull-Through Cache — Analise de especialistas + plano de implementacao
