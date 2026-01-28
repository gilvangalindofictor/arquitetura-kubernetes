# ADR-007: Cluster Autoscaler Strategy

**Status:** ✅ APPROVED
**Data:** 2026-01-28
**Decisores:** DevOps Team + Claude Sonnet 4.5
**Tags:** `autoscaling`, `kubernetes`, `cost-optimization`, `eks`

---

## Contexto

Com a plataforma Kubernetes operacional (Marco 2 Fases 1-5 completas), precisávamos implementar **auto-scaling de nodes** para:
- Reduzir custos durante períodos de baixa demanda (noites, fins de semana)
- Escalar automaticamente quando workloads exigirem mais recursos
- Manter alta disponibilidade sem provisionamento excessivo
- Otimizar utilização de nodes (FinOps)

**Situação Atual:**
- 7 nodes rodando 24/7 (2 system + 3 workloads + 2 critical)
- Node group "workloads" com demanda variável (3 nodes fixos)
- Custo mensal: ~$550 (nodes sempre ligados)
- Possibilidade de economia: ~15-30% com scale-down inteligente

---

## Decisão

**Implementar Cluster Autoscaler com escopo limitado ao node group "workloads"**

### Componentes da Solução

| Componente | Tecnologia | Justificativa |
|------------|------------|---------------|
| **Autoscaler** | Kubernetes Cluster Autoscaler v1.31.x | Maturidade, não invasivo, compatível com ASGs existentes |
| **IAM** | IRSA (IAM Roles for Service Accounts) | Least privilege, sem access keys |
| **IaC** | Terraform Helm module | Versionamento, reprodutibilidade |
| **Escopo** | Node group "workloads" apenas | Minimizar risco, proteger nodes críticos |

---

## Alternativas Consideradas

### ❌ Opção 1: Karpenter (Substituir Cluster Autoscaler)

**Rejeitada:**
- 🔴 **Invasivo:** Substitui Auto Scaling Groups por Custom Resources (CRDs)
- 🔴 **Migração complexa:** Requer refatoração dos node groups existentes
- 🟡 **Maturidade:** Relativamente novo (2 anos em produção)
- ✅ **Performance:** Excelente (< 10s para provisionar nodes)
- ✅ **Spot Instances:** Suporte nativo avançado

**Decisão:** Considerar Karpenter em Marco 4 (futuro) após validar Cluster Autoscaler

---

### ❌ Opção 2: Manual Scaling (AWS CLI/Scripts)

**Rejeitada:**
- 🔴 **Overhead operacional:** Requer monitoramento manual
- 🔴 **Reativo:** Não escala automaticamente baseado em pending pods
- 🟡 **Scheduled Scaling:** Funciona apenas para padrões previsíveis
- ✅ **Custo zero:** Sem componentes adicionais

**Decisão:** Insuficiente para demanda dinâmica de workloads

---

### ✅ Opção 3: Cluster Autoscaler (ESCOLHIDA)

**Aprovada:**
- ✅ **Não invasivo:** Trabalha com ASGs existentes sem refatoração
- ✅ **Maturidade:** Produção-ready há 5+ anos (CNCF graduated project)
- ✅ **Simplicidade:** Configuração via Helm chart + IAM policy
- ✅ **Reversível:** Pode desabilitar sem breaking changes
- ✅ **Observabilidade:** Métricas Prometheus integradas
- 🟡 **Performance:** Bom (30-60s para provisionar nodes)

---

## Configuração Implementada

### Node Groups e Autoscaling

| Node Group | Tipo | Min | Max | Desired | Autoscaling | Razão |
|------------|------|-----|-----|---------|-------------|-------|
| **system** | t3.medium | 2 | 4 | 2 | ❌ DESABILITADO | Serviços de sistema precisam estar sempre disponíveis |
| **workloads** | t3.large | 2 | 6 | 3 | ✅ HABILITADO | Carga variável, pode escalar com demanda |
| **critical** | t3.xlarge | 2 | 4 | 2 | ❌ DESABILITADO | Stateful workloads (bancos de dados, Prometheus) |

### Políticas de Scaling

```yaml
Scale-Up:
  Trigger: Pods em Pending por falta de recursos
  Timing: 30-60 segundos
  Strategy: least-waste (escolhe tipo de node mais econômico)

Scale-Down:
  Trigger: Node com < 50% utilização por 10 minutos
  Timing: Após 10 minutos de baixa utilização
  Delay após scale-up: 10 minutos (evita flapping)
  Max graceful termination: 600 segundos (10 minutos)
```

### IAM Policy (Least Privilege)

```json
{
  "Effect": "Allow",
  "Action": [
    "autoscaling:SetDesiredCapacity",
    "autoscaling:TerminateInstanceInAutoScalingGroup"
  ],
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/k8s-platform-prod": "owned"
    }
  }
}
```

**Segurança:** Policy só permite modificar ASGs com tag específica do cluster.

---

## Tagging de Auto Scaling Groups

### ASG "workloads" (Autoscaling ENABLED)

```hcl
tags = {
  "k8s.io/cluster-autoscaler/enabled"                = "true"
  "k8s.io/cluster-autoscaler/k8s-platform-prod"      = "owned"
}
```

### ASGs "system" e "critical" (Autoscaling DISABLED)

```hcl
tags = {
  "k8s.io/cluster-autoscaler/enabled"                = "false"
  "k8s.io/cluster-autoscaler/k8s-platform-prod"      = "disabled"
}
```

---

## Impacto

### Custo (Economia Esperada)

**Cenário Base:** 3 nodes workloads 24/7
- Custo mensal: 3 nodes × $44 × 730h = $132/mês

**Cenário com Autoscaling:** Scale-down durante baixa demanda
- Horário comercial (8h-18h, seg-sex): 3 nodes (50 horas/semana)
- Noite/fim de semana: 2 nodes (118 horas/semana)
- **Economia:** ~1 node desligado 70% do tempo = ~$31/mês (**23% economia**)
- **Economia anual:** ~$372/ano

**ROI:**
- Custo de implementação: $0 (apenas configuração)
- Payback: Imediato
- Economia acumulada 12 meses: $372

### Segurança (Benefícios)

- ✅ IRSA pattern: Sem access keys expostas
- ✅ Least privilege: IAM policy restrita por tags
- ✅ Auditoria: CloudTrail registra todas as scaling actions
- ✅ Network Policies: Cluster Autoscaler respeitando egress rules

### Segurança (Riscos Mitigados)

| Risco | Probabilidade | Impacto | Mitigação Implementada |
|-------|---------------|---------|------------------------|
| **IAM sobre-permissivo** | BAIXO | ALTO | Policy com condition baseada em tags |
| **Scale-down agressivo (quebra serviços)** | MÉDIO | MÉDIO | Thresholds conservadores (50% utilização, 10min) |
| **Flapping (scale up/down rápido)** | BAIXO | MÉDIO | Delay de 10 min após scale-up antes de scale-down |
| **Cluster Autoscaler pod down (sem scaling)** | BAIXO | MÉDIO | Priority class: system-cluster-critical |

---

## Riscos e Limitações

### Limitações Conhecidas

1. **⚠️ Scale-up delay:** 30-60 segundos para provisionar novos nodes
   - **Impacto:** Pods ficam Pending temporariamente
   - **Mitigação:** Configurar min=2 nodes (sempre disponíveis)

2. **⚠️ Stateful pods bloqueiam scale-down:**
   - Pods com PersistentVolumeClaims ou local storage impedem remoção de nodes
   - **Mitigação:** Usar node affinity para fixar stateful pods em node group "critical"

3. **⚠️ Não otimiza custos de Spot Instances:**
   - Cluster Autoscaler funciona com On-Demand apenas
   - **Futuro:** Migrar para Karpenter (suporte nativo a Spot)

### Métricas de Monitoramento

```promql
# Nodes gerenciados pelo Cluster Autoscaler
cluster_autoscaler_nodes_count{state="ready"}

# Pods aguardando scale-up
cluster_autoscaler_unschedulable_pods_count

# Operações de scaling (success/fail)
cluster_autoscaler_scaled_up_nodes_total
cluster_autoscaler_scaled_down_nodes_total
cluster_autoscaler_failed_scale_ups_total
```

---

## Validação Pós-Deploy

### Checklist de Sucesso ✅

- [ ] Cluster Autoscaler pod Running em node group "system"
- [ ] Service Account com annotation `eks.amazonaws.com/role-arn`
- [ ] IAM Role com trust policy OIDC válida
- [ ] ASG "workloads" com tags corretas
- [ ] Logs sem erros de permissão IAM
- [ ] Prometheus ServiceMonitor criado
- [ ] Métricas `cluster_autoscaler_*` disponíveis

### Testes de Validação

**Teste 1: Scale-Up (Deploy workload que exige > 3 nodes)**
```bash
kubectl apply -f test-scale-up.yaml
# Esperar: New node provisionado em ~60s
kubectl get nodes --watch
```

**Teste 2: Scale-Down (Deletar workload, aguardar 10min)**
```bash
kubectl delete -f test-scale-up.yaml
# Esperar: Node removido após 10 min de baixa utilização
kubectl get nodes --watch
```

**Teste 3: Verificar Logs**
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=cluster-autoscaler --tail=100
# Buscar: "Expanding scale up" ou "Attempting to scale down"
```

---

## Próximos Passos

### Curto Prazo (1-2 semanas)
1. [ ] **Deploy Cluster Autoscaler via Terraform** (Marco 2 Fase 6)
2. [ ] **Aplicar tags nos ASGs do Marco 1** (habilitar discovery)
3. [ ] **Executar testes de scale-up e scale-down**
4. [ ] **Monitorar métricas por 7 dias** - Validar economia e estabilidade

### Médio Prazo (1-3 meses)
5. [ ] **Dashboard Grafana** - Visualizar scale events e economia
6. [ ] **Alertas Prometheus** - Notificar scale-up failures
7. [ ] **Scheduled Scaling (opcional)** - Pre-scaling durante horário comercial

### Longo Prazo (6+ meses)
8. [ ] **Avaliar Karpenter** - Migração quando Spot Instances forem necessários
9. [ ] **Cluster Autoscaler em nodes critical?** - Após validar estabilidade
10. [ ] **HPA (Horizontal Pod Autoscaler)** - Complementar com scaling de pods

---

## Referências

- [Kubernetes Cluster Autoscaler GitHub](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler)
- [Cluster Autoscaler AWS Provider](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md)
- [EKS Best Practices - Autoscaling](https://aws.github.io/aws-eks-best-practices/cluster-autoscaling/)
- [Cluster Autoscaler FAQ](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md)
- [Karpenter vs Cluster Autoscaler](https://aws.amazon.com/blogs/containers/amazon-eks-cluster-autoscaler-vs-karpenter/)

---

**Decisão tomada em:** 2026-01-28
**Implementado em:** Marco 2 - Fase 6
**Próxima revisão:** Após 7 dias de monitoramento (2026-02-04)
