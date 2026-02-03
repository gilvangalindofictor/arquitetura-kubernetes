# 📓 Marco 2 Fase 4 - Implementação Loki + Fluent Bit (Logging)

| Campo          | Valor                                    |
|----------------|------------------------------------------|
| **Data**       | 2026-01-28                               |
| **Demanda**    | Implementar stack de logging com Loki + Fluent Bit |
| **Impacto**    | Médio (Observabilidade completa)         |
| **Agentes**    | DevOps Team, Terraform Specialist        |
| **Status**     | ✅ Código Implementado (Aguardando Deploy) |
| **Duração**    | ~4-5 horas (implementação completa)      |

---

## Contexto

Marco 2 Fase 4 focou na implementação da stack de logging centralizado usando Loki (armazenamento) + Fluent Bit (coleta). Esta fase complementa o monitoramento já implementado (Prometheus + Grafana) adicionando capacidade de agregação e análise de logs.

---

## Estado Atual da Plataforma

- ✅ **Marco 0:** VPC baseline + Backend Terraform S3/DynamoDB (COMPLETO)
- ✅ **Marco 1:** Cluster EKS `k8s-platform-prod` com 7 nodes (COMPLETO)
- ✅ **Marco 2 Fase 1:** AWS Load Balancer Controller v1.11.0 (COMPLETO)
- ✅ **Marco 2 Fase 2:** Cert-Manager v1.16.3 (COMPLETO)
- ✅ **Marco 2 Fase 3:** Kube-Prometheus-Stack v69.4.0 - 13 pods monitoring (COMPLETO)
- 📝 **Marco 2 Fase 4:** Loki + Fluent Bit - **CÓDIGO IMPLEMENTADO, AGUARDANDO DEPLOY**
- ⏳ **Marco 2 Fases 5-7:** Network Policies, Autoscaler, Apps de Teste (PENDENTE)

---

## Trabalho Realizado

### ADR-005: Logging Strategy

**Decisão:** Loki (S3 backend) como solução primária vs CloudWatch Logs

**Justificativa:**
- **Economia:** $423/ano vs CloudWatch (64% de economia)
- **Integração:** Native com Grafana (já instalado)
- **Custos estimados:**
  - S3 Storage: $11.50/mês
  - EBS PVCs: $3.20/mês (20Gi write + 20Gi backend)
  - S3 API requests: $5.00/mês
  - **Total:** $19.70/mês

### Módulo Terraform Loki (495 linhas)

**Componentes:**
- S3 bucket para logs (`k8s-platform-loki-891377105802`)
- IAM Role + Policy (IRSA pattern - sem Access Keys)
- Loki SimpleScalable mode: 8 pods
  - 2 read replicas
  - 2 write replicas
  - 2 backend replicas
  - 2 gateway replicas
- **Retenção:** 30 dias

### Módulo Terraform Fluent Bit (375 linhas)

**Componentes:**
- DaemonSet (1 pod por node = 7 pods)
- **Parsers:**
  - Docker JSON
  - CRI-O
  - Multiline
- **Output:** Loki Gateway (http://loki-gateway.monitoring:3100)

### Arquivos Criados/Modificados

- `docs/adr/adr-005-logging-strategy.md` (450 linhas)
- `modules/loki/` (main.tf, variables.tf, outputs.tf, versions.tf)
- `modules/fluent-bit/` (main.tf, variables.tf, outputs.tf, versions.tf)
- `marco2/main.tf` (+60 linhas: módulos loki e fluent_bit)
- `marco2/outputs.tf` (+40 linhas: outputs loki e fluent_bit)
- `scripts/validate-fase4.sh` (300 linhas)

---

## Próximos Passos para Deploy

1. Configurar credenciais AWS (`aws sso login --profile k8s-platform-prod`)
2. Ligar cluster EKS (via `startup-full-platform.sh`)
3. Executar `terraform plan` no diretório `marco2`
4. Revisar recursos a serem criados (~10-15 recursos)
5. Executar `terraform apply fase4.tfplan`
6. Validar deployment (`./scripts/validate-fase4.sh`)
7. Verificar logs no Grafana Explore
8. Atualizar documentação

---

## Estimativas

| Métrica | Valor |
|---------|-------|
| Tempo de Deploy | 10-15 minutos |
| Custo Adicional Mensal | +$19.70 |
| Economia vs CloudWatch | $423/ano (64%) |
| ROI | Positivo desde o primeiro ano |

---

## Riscos Identificados e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|---------------|-----------|
| Loki pods Pending (RAM insuficiente) | MÉDIO | Verificar recursos disponíveis nos nodes system |
| S3 Access Denied (IAM incorreto) | BAIXO | IAM Role trust policy validado no código |
| Fluent Bit não envia logs | BAIXO | Endpoint Loki configurado corretamente |

---

## Validações Planejadas

- [ ] 8 pods Loki Running (2+2+2+2)
- [ ] 7 pods Fluent Bit Running (DaemonSet)
- [ ] S3 bucket criado com encryption
- [ ] IAM IRSA pattern implementado (sem Access Keys)
- [ ] Logs visíveis no Grafana Explore: `{namespace="monitoring"}`
- [ ] Query LogQL funcionando
- [ ] Correlação Logs ↔ Métricas testada

---

## Lições Aprendidas

### 💰 FinOps

| # | Lição | Impacto |
|---|-------|---------|
| 1 | Loki com S3 backend é 64% mais barato que CloudWatch Logs para workloads DevOps | 🟡 Médio |
| 2 | SimpleScalable mode do Loki oferece boa relação custo/benefício para clusters <100 nodes | 🟢 Baixo |

### 🏗️ Arquitetura

| # | Lição | Impacto |
|---|-------|---------|
| 3 | IRSA (IAM Roles for Service Accounts) elimina necessidade de Access Keys em pods | 🔴 Crítico |
| 4 | Integração nativa Loki-Grafana simplifica correlação logs-métricas | 🟡 Médio |
| 5 | DaemonSet do Fluent Bit garante cobertura completa de logs de todos os nodes | 🟡 Médio |

### 📋 Processo

| # | Lição | Impacto |
|---|-------|---------|
| 6 | ADR para decisões de logging ajuda a justificar escolha técnica e financeira | 🟢 Baixo |
| 7 | Scripts de validação (validate-fase4.sh) aceleram troubleshooting pós-deploy | 🟡 Médio |

---

## Referências

- [ADR-005: Logging Strategy](../adr/adr-005-logging-strategy.md)
- [Módulo Terraform Loki](../../platform-provisioning/aws/kubernetes/terraform/modules/loki/)
- [Módulo Terraform Fluent Bit](../../platform-provisioning/aws/kubernetes/terraform/modules/fluent-bit/)
- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Fluent Bit Documentation](https://docs.fluentbit.io/)
