# 📓 Marco 2 Fase 5 - Network Policies (Segurança L3/L4)

| Campo          | Valor                                    |
|----------------|------------------------------------------|
| **Data**       | 2026-01-28                               |
| **Demanda**    | Implementar microsegmentação L3/L4 no cluster |
| **Impacto**    | Alto (Segurança Zero Trust)              |
| **Agentes**    | Security Specialist, DevOps Team         |
| **Status**     | ✅ Concluído (Default deny pendente)     |
| **Duração**    | ~2 horas (design + implementação)        |

---

## Contexto

Com Marco 2 Fases 1-4 completas e observabilidade operacional, implementou-se isolamento de rede entre namespaces usando Network Policies para atender requisitos de segurança Zero Trust.

---

## Objetivo

Implementar microsegmentação L3/L4 no cluster Kubernetes seguindo princípio **Zero Trust**:
- Default deny-all (negar tudo por padrão)
- Allow explícito apenas para comunicação essencial
- Prevenir lateral movement em caso de comprometimento

---

## Escopo

**Namespaces Protegidos:**
- monitoring (Prometheus, Grafana, Alertmanager, Loki)
- cert-manager
- kube-system

**Objetivos de Segurança:**
- Isolamento entre namespaces
- Prevenir lateral movement
- Permitir apenas comunicação essencial

---

## Solução Implementada

### 1. Instalação Calico v3.27.0 (Policy-Only Mode)

**Decisão Técnica:** Calico em policy-only mode (não substitui VPC CNI)

**Justificativa:**
- ✅ Calico policy-only: Adiciona Network Policies sem substituir VPC CNI
- ✅ Mantém integração AWS: ENI direto, Security Groups for Pods
- ❌ Cilium rejeitado: Muito invasivo, quebra integrações AWS

**Resultado:**
- 7 pods Calico criados
- Coexistindo com 7 pods aws-node (VPC CNI)
- Total: 14 pods de rede (7 Calico + 7 aws-node)

### 2. Módulo Terraform Network Policies

**Criado:** `modules/network-policies/`

**Estrutura:**
- 11 Network Policies com feature flags individuais
- Políticas organizadas em 3 fases
- Default deny-all desabilitado inicialmente

### 3. Network Policies Criadas (11 total)

**Fase 1: Políticas Básicas (6 políticas)**
- allow-dns-monitoring
- allow-dns-cert-manager
- allow-dns-kube-system
- allow-api-server-monitoring
- allow-api-server-cert-manager
- allow-api-server-kube-system

**Fase 2: Políticas Específicas (5 políticas)**
- prometheus-scraping (permite Prometheus scrape de todos os namespaces)
- fluent-bit-to-loki (permite Fluent Bit enviar logs para Loki)
- grafana-datasources (permite Grafana consultar Prometheus e Loki)
- monitoring-ingress (permite ALB acessar Grafana)
- cert-manager-egress (permite Cert-Manager validar certificados)

**Fase 3: Default Deny (desabilitada)**
- default-deny-all (pendente validação completa)

---

## Resultado Final

### Terraform Apply

```
Apply complete! Resources: 11 added, 0 changed, 0 destroyed.

Time: 19 seconds
```

### Status das Políticas

```bash
kubectl get networkpolicies -A

NAMESPACE      NAME                         POD-SELECTOR
monitoring     allow-dns                    <all>
monitoring     allow-api-server             <all>
monitoring     prometheus-scraping          app=prometheus
monitoring     fluent-bit-to-loki           app=fluent-bit
monitoring     grafana-datasources          app=grafana
monitoring     monitoring-ingress           app=grafana
cert-manager   allow-dns                    <all>
cert-manager   allow-api-server             <all>
cert-manager   cert-manager-egress          app=cert-manager
kube-system    allow-dns                    <all>
kube-system    allow-api-server             <all>
```

### Estrutura Modular com Feature Flags

```terraform
variable "enable_default_deny" {
  type    = bool
  default = false  # Desabilitado até validação completa
}

variable "enable_prometheus_scraping" {
  type    = bool
  default = true
}

# ... mais feature flags
```

---

## Próximos Passos

1. ✅ Validar TODAS as allow policies funcionando
2. ⏳ Monitorar tráfego bloqueado via Calico audit logs
3. ⏳ Criar dashboard Grafana para visualizar Network Policy events
4. ⏳ Habilitar default-deny via feature flag quando validação completar

---

## Lições Aprendidas

### 🔒 Segurança

| # | Lição | Impacto |
|---|-------|---------|
| 1 | **Zero Trust deve ser implementado gradualmente** - default deny sem allow policies quebra tudo | 🔴 Crítico |
| 2 | Calico policy-only mode é ideal para adicionar Network Policies sem quebrar networking | 🔴 Crítico |
| 3 | Feature flags permitem enable/disable políticas individuais para troubleshooting | 🟡 Médio |
| 4 | DNS e API Server policies são sempre necessárias - sem elas pods não inicializam | 🔴 Crítico |

### 🏗️ Arquitetura

| # | Lição | Impacto |
|---|-------|---------|
| 5 | Cilium é muito invasivo para ambientes AWS - substitui VPC CNI completamente | 🟡 Médio |
| 6 | Calico coexiste pacificamente com aws-node (VPC CNI) | 🟡 Médio |
| 7 | Network Policies são namespace-scoped - não há policies cluster-wide | 🟢 Baixo |

### ⚙️ Operações

| # | Lição | Impacto |
|---|-------|---------|
| 8 | **Monitorar tráfego bloqueado ANTES de habilitar default deny** - evita quebras | 🔴 Crítico |
| 9 | Prometheus scraping requer Network Policy permitindo acesso cross-namespace | 🟡 Médio |
| 10 | Fluent Bit DaemonSet precisa de policy para enviar logs para Loki | 🟡 Médio |

---

## Métricas

| Métrica | Valor |
|---------|-------|
| Tempo de design | ~1 hora |
| Tempo de implementação | ~1 hora |
| **Tempo total** | **~2 horas** |
| Policies criadas | 11 |
| Namespaces protegidos | 3 (monitoring, cert-manager, kube-system) |
| Terraform apply | 19 segundos |
| Calico pods | 7 Running |

---

## Custo

| Item | Valor |
|------|-------|
| Calico (open source) | **$0/mês** |
| Network Policies | **$0/mês** |
| Overhead CPU/RAM | Negligível (<1% cluster resources) |

---

## Referências

- [Calico Documentation](https://docs.tigera.io/calico/latest/about/)
- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Zero Trust Architecture](https://www.nist.gov/publications/zero-trust-architecture)
- [Módulo Terraform](../../platform-provisioning/aws/kubernetes/terraform/modules/network-policies/)
