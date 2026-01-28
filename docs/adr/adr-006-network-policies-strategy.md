# ADR-006: Network Policies Strategy

**Status:** ✅ APPROVED
**Data:** 2026-01-28
**Decisores:** DevOps Team + Claude Sonnet 4.5
**Tags:** `security`, `networking`, `kubernetes`, `zero-trust`

---

## Contexto

Com a plataforma Kubernetes operacional (Marco 2 Fases 1-4 completas), precisávamos implementar **isolamento de rede entre namespaces** para:
- Prevenir lateral movement em caso de comprometimento de um pod
- Seguir princípios Zero Trust (default deny + allow explícito)
- Atender requisitos de compliance (CIS Kubernetes Benchmark 5.3.2)
- Proteger serviços críticos (monitoring, cert-manager)

---

## Decisão

**Implementar Network Policies usando Calico policy-only mode + Terraform kubernetes_manifest**

### Componentes da Solução

| Componente | Tecnologia | Justificativa |
|------------|------------|---------------|
| **Policy Engine** | Calico v3.27.0 (policy-only mode) | Não substitui VPC CNI, mantém integração AWS (ENI, Security Groups for Pods) |
| **IaC** | Terraform kubernetes_manifest | Versionamento, diff, rollback controlado |
| **Estratégia** | Default allow → Incremental deny | Reduz risco de breaking changes |

---

## Alternativas Consideradas

### ❌ Opção 1: Cilium (Substituir VPC CNI)
**Rejeitada:**
- Muito invasivo - quebra integração AWS (ENI direto, Security Groups for Pods)
- Overhead de migração alto
- Perda de funcionalidades AWS nativas

### ❌ Opção 2: kubectl apply (sem Terraform)
**Rejeitada:**
- Sem diff antes de aplicar (aplica cegamente)
- Rollback manual complexo
- Difícil rastreamento (precisaria GitOps adicional)

### ⏳ Opção 3: Service Mesh (Istio/Linkerd)
**Futuro (Marco 4?):**
- Oferece L7 policies + mTLS
- Overhead alto (sidecars, controle plane)
- Complexidade operacional significativa

### ✅ Opção 4: Calico policy-only + Terraform (ESCOLHIDA)
**Aprovada:**
- ✅ Não invasivo (coexiste com VPC CNI)
- ✅ IaC completo (plan/apply/destroy)
- ✅ Suporte Kubernetes nativo (CRDs padrão)
- ✅ Custo zero (apenas configuração)

---

## Políticas Implementadas

### Fase 1: Políticas Básicas (Aplicadas PRIMEIRO)

**1. allow-dns.yaml** - DNS Resolution
```yaml
# Permite todos os pods → CoreDNS (porta 53 UDP/TCP)
# Aplicado em: monitoring, cert-manager, kube-system
```

**2. allow-api-server.yaml** - Kubernetes API Access
```yaml
# Permite todos os pods → Kubernetes API (porta 443 TCP)
# Essencial para: controllers, operators, service discovery
```

### Fase 2: Políticas Específicas (Observabilidade)

**3. allow-prometheus-scraping.yaml**
```yaml
# Prometheus → targets (portas 9100, 8080, 9090, 3100, 9093)
# Permite scraping de métricas de todos os namespaces
```

**4. allow-fluent-bit-to-loki.yaml**
```yaml
# Fluent Bit DaemonSet → Loki Gateway (porta 80 TCP)
# Permite envio de logs para backend centralizado
```

**5. allow-grafana-datasources.yaml**
```yaml
# Grafana → Prometheus (9090) + Loki (80, 3100)
# Permite queries para dashboards e alertas
```

**6. allow-monitoring-ingress.yaml**
```yaml
# Ingress em portas de métricas (9100, 8080, 9090, 3100, 9093)
# Permite comunicação interna do stack de monitoring
```

**7. allow-cert-manager-egress.yaml**
```yaml
# Cert-Manager → Let's Encrypt (porta 443 HTTPS)
# Permite ACME challenge para renovação automática de certificados
```

### Fase 3: Default Deny (Aplicada POR ÚLTIMO - DESABILITADA)

**8. default-deny-all.yaml**
```yaml
# ⚠️ CRÍTICO: Bloqueia TUDO exceto o que foi explicitamente permitido
# Status: DESABILITADO (enable_default_deny = false)
# Para habilitar: Mudar variável no Terraform e executar apply
# Pré-requisito: Validar que TODAS as allow policies funcionam
```

---

## Implementação Terraform

### Estrutura do Módulo

```
platform-provisioning/aws/kubernetes/terraform/envs/marco2/
├── modules/
│   └── network-policies/
│       ├── main.tf                      # Recursos Terraform
│       ├── variables.tf                 # Configuração de políticas
│       ├── outputs.tf                   # Outputs do módulo
│       ├── versions.tf                  # Provider requirements
│       └── policies/
│           ├── allow-dns.yaml
│           ├── allow-api-server.yaml
│           ├── allow-prometheus-scraping.yaml
│           ├── allow-fluent-bit-to-loki.yaml
│           ├── allow-grafana-datasources.yaml
│           ├── allow-monitoring-ingress.yaml
│           ├── allow-cert-manager-egress.yaml
│           └── default-deny-all.yaml
└── main.tf (adiciona module "network_policies")
```

### Configuração

```terraform
module "network_policies" {
  source = "./modules/network-policies"

  namespaces = ["monitoring", "cert-manager", "kube-system"]

  # Fase 1: Básicas
  enable_dns_policy        = true
  enable_api_server_policy = true

  # Fase 2: Específicas
  enable_prometheus_scraping   = true
  enable_loki_ingestion        = true
  enable_grafana_datasources   = true
  enable_cert_manager_egress   = true

  # Fase 3: Default Deny (DESABILITADO)
  enable_default_deny = false  # ⚠️ Habilitar APENAS após validação
}
```

---

## Validação Pós-Deploy

### Checklist de Sucesso ✅

- [x] Calico instalado (7 pods Running, 1 por node)
- [x] VPC CNI coexistindo (7 pods aws-node Running)
- [x] 11 Network Policies criadas
- [x] 33 pods monitoring Running (nenhum impacto)
- [x] Prometheus scrapando todos os targets (health: up)
- [x] Fluent Bit enviando logs para Loki (HTTP 204)
- [x] Grafana acessando datasources (Prometheus + Loki)
- [x] Cert-Manager operacional (3 pods Running)

### Comandos de Validação

```bash
# Listar Network Policies
kubectl get networkpolicies -A

# Verificar pods Calico
kubectl get pods -n kube-system -l k8s-app=calico-node

# Verificar pods monitoring
kubectl get pods -n monitoring

# Testar Prometheus targets
kubectl exec -n monitoring deployment/kube-prometheus-stack-grafana -- \
  wget -qO- http://kube-prometheus-stack-prometheus:9090/api/v1/targets

# Verificar logs Loki
kubectl logs -n monitoring deployment/loki-gateway --tail=20
```

---

## Impacto

### Custo
- **Adicional:** $0/mês ✅
- Network Policies são recursos Kubernetes nativos (sem custo AWS)
- Calico policy-only roda em nodes existentes

### Segurança (Benefícios)
- ✅ Isolamento de namespaces (previne lateral movement)
- ✅ Compliance: CIS Kubernetes Benchmark 5.3.2
- ✅ Princípio Zero Trust implementado
- ✅ Superfície de ataque reduzida

### Segurança (Limitações)
- ⚠️ Network Policies são L3/L4 (IP/Port), não L7 (HTTP headers)
- ⚠️ Não protege contra ataques dentro do mesmo namespace
- 🔄 Futuro: Considerar Service Mesh (Istio/Linkerd) para mTLS + L7

---

## Riscos e Mitigações

| Risco | Probabilidade | Impacto | Mitigação Implementada |
|-------|---------------|---------|------------------------|
| **Default deny bloqueia tráfego essencial** | MÉDIO | ALTO | Aplicar incremental: allow policies ANTES de deny-all |
| **DNS resolution falha** | BAIXO | ALTO | Policy allow-dns aplicada em TODOS os namespaces |
| **Prometheus para de scrape** | BAIXO | MÉDIO | Policy allow-prometheus-scraping com todas as portas |
| **Fluent Bit não envia logs** | BAIXO | MÉDIO | Policy allow-fluent-bit-to-loki validada |
| **Cert-Manager não renova certificados** | BAIXO | ALTO | Policy allow-cert-manager-egress para HTTPS + HTTP |

---

## Próximos Passos

### Curto Prazo (1-2 semanas)
1. [ ] **Monitorar observabilidade por 7 dias** - Confirmar que não há breaking changes
2. [ ] **Mapear fluxos adicionais** - Quando GitLab for deployado (Marco 3)
3. [ ] **Habilitar default-deny** - Após validação completa (`enable_default_deny = true`)

### Médio Prazo (1-3 meses)
4. [ ] **Pod Security Standards** - Implementar restricted policy
5. [ ] **Network Policies para workloads** - GitLab, Redis, RabbitMQ
6. [ ] **Auditoria de tráfego** - Usar Calico logs para análise

### Longo Prazo (6+ meses)
7. [ ] **Avaliar Service Mesh** - Istio/Linkerd para mTLS + L7 policies
8. [ ] **Zero Trust completo** - mTLS entre TODOS os pods

---

## Referências

- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Project Calico Documentation](https://docs.tigera.io/calico/latest/about/)
- [CIS Kubernetes Benchmark 5.3.2](https://www.cisecurity.org/benchmark/kubernetes)
- [NSA Kubernetes Hardening Guide](https://media.defense.gov/2021/Aug/03/2002820425/-1/-1/1/CTR_KUBERNETES%20HARDENING%20GUIDANCE.PDF)

---

**Decisão tomada em:** 2026-01-28
**Implementado em:** Marco 2 - Fase 5
**Próxima revisão:** Após Marco 3 deployment (GitLab CE)
