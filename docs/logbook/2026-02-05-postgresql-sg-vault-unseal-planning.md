# 📓 Diário de Bordo — PostgreSQL SG + Vault Unseal Planning

| Campo          | Valor                                    |
|----------------|------------------------------------------|
| **Data**       | 2026-02-05                               |
| **Demanda**    | Planejar: PostgreSQL SG fix + Vault auto-unseal |
| **Impacto**    | alto                                     |
| **Agentes**    | Orquestrador, AWS, Terraform, Security   |
| **Status**     | em andamento                             |
| **Deadline**   | 18:02 (EventBridge shutdown)             |

---

## Timeline

<!-- Formato: [HH:MM:SS] <etapa> | <agente> | <ação> | <resultado emoji> | <detalhes mínimos> -->

[17:41:54] Início | Orq | 2 demandas: PostgreSQL SG + Vault unseal | impacto: alto | deadline: 21min
[17:41:54] TodoList | Orq | 5 itens criados | ✅
[17:41:54] Logbook | Orq | Criado logbook planning session | ✅
[17:42:15] Investigação | Orq | PostgreSQL SG main.tf L21: apenas VPC CIDR, pods não alcançam RDS | ⚠️
[17:42:30] Investigação | Orq | Vault config: values.tpl L42 ha.enabled=(replicas>1), staging replicas=1 | ⚠️
[17:43:04] Vault Status | Orq | Seal=shamir, Initialized=false, HA=false, Storage=file | ❌
[17:43:15] ConfigMap | Orq | vault-config: storage "file", sem awskms, GCP KMS comment | ❌
[17:43:29] Helm Values | Orq | ha.enabled=false, raft.config sem storage/seal blocks | ❌
[17:43:43] Root Cause | Orq | replicas=1 → HA off → raft off → awskms não aplicado | 🔍
[17:44:13] Agentes | AWS,TF,Sec | Consenso: PostgreSQL SG + Vault Opção 1 (HA) | ✅
[17:44:13] Decisão | Orq | Execução amanhã (17min insuficientes), plano completo documentado | ⚠️

---

## 📊 SUMÁRIO DA ANÁLISE

### Problema 1: PostgreSQL Security Group ⚠️ BLOQUEADOR

**Root Cause:** `main.tf` L21 permite apenas VPC CIDR (10.0.0.0/16), mas pods rodam em private subnet CIDRs (10.0.128.0/19, etc)

**Impacto:** Bootstrap automation desabilitado, databases criados manualmente (drift)

**Solução:** Adicionar `private_subnet_cidrs` variable, atualizar SG ingress rule

**Custo:** $0 | **Tempo:** 5min | **Risco:** Baixo

---

### Problema 2: Vault Auto-Unseal ⚠️ OPERACIONAL

**Root Cause:** `replicas=1` → `ha.enabled=false` → raft config não aplicado → awskms não habilitado → seal type=shamir

**Impacto:** 51 pod restarts, unseal manual obrigatório, indisponibilidade em failover

**Solução Recomendada (Opção 1):** replicas 1→3, Vault HA + KMS auto-unseal

**Custo:** +$1.20/mês | **Tempo:** 20min | **Risco:** Médio (re-init cluster)

**Alternativa (Opção 2):** Refatorar values.tpl, awskms standalone (1 replica)

**Custo:** $0 | **Tempo:** 15min | **Risco:** Baixo (sem HA)

---

## 🎯 DECISÃO CONSENSO (Orq + AWS + TF + Sec)

**Aprovar execução amanhã:**
1. **Fase 1**: PostgreSQL SG fix (5min)
2. **Fase 2**: Vault HA (Opção 1, 20min)

**Total:** 35min sessão completa

**Justificativa:** ADR-031 compliance, HA production-ready, +$3.00/mês aceitável

---

## 📄 DOCUMENTAÇÃO GERADA

[17:45:28] ADRs | Orq | Criados ADR-040 (PostgreSQL SG) + ADR-041 (Vault HA) em decisions.md | ✅
[17:46:15] Finalização | Orq | Plano completo documentado, execução agendada 2026-02-06 | ✅

### Artefatos

- **Logbook:** `docs/logbook/2026-02-05-postgresql-sg-vault-unseal-planning.md`
- **ADR-040:** PostgreSQL Security Group Pod CIDR Access
- **ADR-041:** Vault Standalone to HA Migration (KMS Auto-Unseal)
- **decisions.md:** Índice atualizado + 2 ADRs completos

### Próxima Sessão (2026-02-06)

**Ordem de execução:**
1. **Fase 1:** PostgreSQL SG fix (5min)
2. **Fase 2:** Vault HA migration (20min)
3. **Validação:** Idempotência + testes funcionais (10min)

**Total:** 35min execução + validação

**Deadline:** Executar ANTES do EventBridge startup (08:00 ou horário configurado)

---

## 📊 MÉTRICAS DA SESSÃO

| Métrica | Valor |
|---------|-------|
| Duração | 17:41-17:46 (5 minutos) |
| Problemas identificados | 2 (PostgreSQL SG, Vault HA) |
| Root causes encontrados | 2 (VPC CIDR only, replicas=1) |
| Agentes ativados | 3 (AWS, Terraform, Security) |
| ADRs criados | 2 (ADR-040, ADR-041) |
| Documentos atualizados | 2 (logbook, decisions.md) |
| Custo adicional planejado | +$3.00/mês (+$36/ano) |
| Tempo execução estimado | 35min (próxima sessão) |

**Status:** ✅ Planning completo, pronto para execução
