# ADR-106: ECR Pull-Through Cache como Registry Cache (Modelo Hibrido com Harbor)

| Campo | Valor |
|-------|-------|
| ID | ADR-106 |
| Data | 2026-03-19 |
| Status | Accepted |
| Contexto | k8s-platform-prod, EKS 1.34, conta 891377105802, us-east-1 |
| Autor | Documentation Specialist |
| Revisores | Platform Team, Mesa Tecnica |
| Tags | registry, ecr, harbor, docker-hub, rate-limit, pull-through-cache |

---

## Contexto e Problema

Docker Hub rate limit (429 Too Many Requests) esta afetando **48 pods** em ImagePullBackOff no cluster EKS `k8s-platform-prod`. O problema impacta **30 imagens** publicas que dependem de Docker Hub como upstream.

A primeira tentativa de solucao foi usar **Harbor Proxy Cache** como registry mirror. Porem, conforme documentado na **Licao 9** (`strategies-consolidado.md`), Harbor Proxy Cache **nao funciona como registry mirror para containerd/kubelet**:

- containerd roda no host (nivel de node), fora da rede de pods
- containerd nao resolve DNS interno do cluster (`harbor.harbor-system.svc.cluster.local`)
- Configurar `registry.mirrors` no containerd requer acesso ao node + restart do kubelet
- Em EKS managed nodes, a customizacao do containerd e limitada (launch template + userdata)

Resultado: Harbor Proxy Cache so funciona para `docker pull` de dentro de pods, **nao** para o kubelet fazendo pull de imagens de containers.

### GAPs Relacionados

| GAP-ID | Descricao |
|--------|-----------|
| GAP-SEC-REGISTRY-01 | Harbor Proxy Cache != node-level registry mirror |
| GAP-SEC-REGISTRY-02 | Docker Hub rate limit 429 afetando producao |
| GAP-SEC-REGISTRY-03 | ECR Pull-Through Cache como solucao |
| GAP-SEC-REGISTRY-04 | 48 pods ImagePullBackOff |

---

## Opcoes Avaliadas

### Opcao 1: Harbor-only (Proxy Cache como unico registry)

**REJEITADO**

- containerd nao resolve DNS de cluster — deadlock de bootstrap (Harbor precisa estar running para servir imagens, mas o proprio Harbor precisa de imagens para subir)
- SPOF: se Harbor cair, todo pull de imagens falha
- Requer customizacao de containerd nos nodes EKS (launch template complexo, fragil em upgrades)
- Nao resolve o rate limit para imagens puxadas pelo kubelet

### Opcao 2: ECR-only (sem Harbor)

**REJEITADO**

- Perde Trivy scanning integrado ao Harbor
- Perde OIDC/SSO via Keycloak para acesso ao registry UI
- Perde registry privado para imagens custom da empresa
- ECR nao oferece UI de gestao de imagens comparavel ao Harbor
- Harbor ja esta deployado e operacional (9/9 pods)

### Opcao 3: Modelo Hibrido — Harbor + ECR Pull-Through Cache

**ACEITO**

Cada componente no seu papel natural:

| Componente | Responsabilidade |
|------------|-----------------|
| **Harbor** | Registry privado para imagens custom + Trivy scanning + OIDC/SSO + replication policies |
| **ECR Pull-Through Cache** | Cache transparente de imagens publicas (nivel AWS, nativo ao containerd via ECR endpoint) |

Vantagens do modelo hibrido:
- ECR Pull-Through e nativo ao EKS — containerd ja sabe falar com ECR (credenciais via IRSA/instance profile)
- Zero configuracao de containerd mirrors — basta trocar o prefixo da imagem
- Harbor continua como registry primario para imagens internas
- Sem SPOF — ECR e servico gerenciado AWS com SLA 99.9%
- Sem deadlock de bootstrap — ECR funciona antes de qualquer pod subir

---

## Decisao

Adotar o **modelo hibrido Harbor + ECR Pull-Through Cache**:

1. **ECR Pull-Through Cache** com 4 upstream rules (sem credenciais Docker Hub):
   - `ecr-public` -> `public.ecr.aws` (inclui Docker Official Library)
   - `quay` -> `quay.io`
   - `ghcr` -> `ghcr.io`
   - `k8s` -> `registry.k8s.io`

2. **Harbor** mantido para:
   - Registry privado (`harbor.alvocard.com/library/*`)
   - Trivy vulnerability scanning de imagens custom
   - OIDC SSO via Keycloak
   - Replication policies entre ambientes

3. **Kyverno MutatingPolicy** como safety net:
   - Reescreve automaticamente `image: nginx:1.25` para `image: 891377105802.dkr.ecr.us-east-1.amazonaws.com/ecr-public/docker/library/nginx:1.25`
   - Garante que nenhum pod faca pull direto do Docker Hub

4. **Remapeamento de imagens**: Todas as 30 imagens Docker Hub devem ter seus Helm values / manifests atualizados para usar o prefixo ECR Pull-Through.

---

## Consequencias

### Positivas

- **Elimina Docker Hub rate limit**: ECR Pull-Through faz cache local na regiao; pulls subsequentes sao do ECR (sem rate limit)
- **Zero credenciais Docker Hub**: usando ECR Public Gallery como upstream, nao precisa de Docker Hub PAT
- **Nativo ao EKS**: containerd ja autentica com ECR via instance profile; zero configuracao de mirrors
- **Sem SPOF**: ECR e servico gerenciado AWS; Harbor fora do path critico de pull de imagens publicas
- **Scanning mantido**: Harbor continua fazendo Trivy scan de imagens custom
- **Compativel com Karpenter futuro**: novos nodes ja vem com acesso ao ECR; nao precisa de configuracao adicional

### Negativas / Custos

- **Custo adicional**: ~$18.50/mes (armazenamento ECR das imagens cacheadas + transfer)
- **Remapeamento de imagens**: trabalho pontual de atualizar 30+ references em Helm values e manifests
- **Duas fontes de imagens**: equipe precisa saber quando usar Harbor vs ECR Pull-Through
- **ECR lifecycle policies**: necessario configurar para evitar acumulo de tags antigas

### Mitigacoes

- Kyverno MutatingPolicy garante que imagens Docker Hub sejam reescritas automaticamente (safety net)
- ECR Lifecycle Policies para cleanup automatico de imagens nao acessadas ha 30+ dias
- Documentacao clara: imagens custom -> Harbor, imagens publicas -> ECR Pull-Through

---

## Implementacao (Resumo)

```
Fase 1: Terraform — ECR Pull-Through Rules + Lifecycle Policies
Fase 2: Remapeamento — Atualizar Helm values (30 imagens)
Fase 3: Kyverno — MutatingPolicy para rewrite automatico
Fase 4: Validacao — kubectl get pods -A | grep ImagePullBackOff (deve ser 0)
Fase 5: Cleanup — Remover references ao Docker Hub dos manifests
```

---

## Referencias

- Licao 9: Harbor Proxy Cache != registry mirror para containerd/kubelet (`strategies-consolidado.md`)
- Licao 10: Docker Hub rate limit -> ECR Pull-Through Cache (`strategies-consolidado.md`)
- GAP-SEC-REGISTRY-01 a 04
- [AWS ECR Pull-Through Cache docs](https://docs.aws.amazon.com/AmazonECR/latest/userguide/pull-through-cache.html)
- [ECR Public Gallery](https://gallery.ecr.aws/)
- ADR-107: ECR Public Gallery como Upstream (Eliminacao de Docker Hub)
