# Documentação - Data Services Domain

> **Domínio**: data-services
> **Última Atualização**: 2026-02-11

---

## 📚 Índice de Documentação

### 🚨 ACHADOS CRÍTICOS - LEITURA OBRIGATÓRIA (STAGING ENVIRONMENT)

| Documento                                                        | Descrição                                             | Leitura           |
| ---------------------------------------------------------------- | ----------------------------------------------------- | ----------------- |
| **[TERRAFORM-SOURCE-OF-TRUTH.md](TERRAFORM-SOURCE-OF-TRUTH.md)** | ✅ **TERRAFORM = FONTE VERDADE**. STAGING matches 100% | 📌 **COMECE AQUI** |
| [STAGING-ANALYSIS-FINDINGS.md](STAGING-ANALYSIS-FINDINGS.md)     | 🟡 Achados da análise STAGING (validação Terraform)    | 5 min (CTO)       |
| [STAGING-INVENTORY.md](STAGING-INVENTORY.md)                     | 📋 Reconciliação Terraform vs STAGING                  | 20 min            |
| [STAGING-BACKUP-STRATEGY.md](STAGING-BACKUP-STRATEGY.md)         | 💾 Análise de backup strategy (Velero não impl)        | 15 min            |
| [STAGING-AUDIT-SUMMARY.md](STAGING-AUDIT-SUMMARY.md)             | 📋 Sumário completo da auditoria STAGING               | 10 min            |

### �🔍 Status e Controle

| Documento                                    | Descrição                                    | Última Atualização |
| -------------------------------------------- | -------------------------------------------- | ------------------ |
| [VERSION-CONTROL.md](VERSION-CONTROL.md)     | 📊 Controle de versões e plano de atualização | 2026-02-11         |
| [EXECUTIVE-SUMMARY.md](EXECUTIVE-SUMMARY.md) | 📈 Resumo executivo para stakeholders         | 2026-02-11         |
| [VALIDATION-REPORT.md](VALIDATION-REPORT.md) | ✅ Relatório de validação do domínio          | 2026-01-05         |

### 🏗️ Arquitetura e Decisões

| Documento                                                            | Descrição                     | Status   |
| -------------------------------------------------------------------- | ----------------------------- | -------- |
| [adr/adr-001-estrutura-inicial.md](adr/adr-001-estrutura-inicial.md) | Decisões da estrutura inicial | ✅ Aceito |

### 🔧 Guias Operacionais

| Documento             | Descrição                     | Disponibilidade |
| --------------------- | ----------------------------- | --------------- |
| Runbook de Upgrade    | Procedimentos de atualização  | 🚧 Planejado     |
| Troubleshooting Guide | Resolução de problemas comuns | 🚧 Planejado     |
| Disaster Recovery     | Procedimentos de DR           | 🚧 Planejado     |

---

## 🎯 Quick Links

### Para Desenvolvedores
- [README Principal](../README.md) - Visão geral do domínio
- [Terraform](../infra/terraform/) - Infraestrutura como código
- [Scripts](../scripts/) - Ferramentas e automações

### Para Operações
- **Verificar Versões**: Execute `./scripts/check-versions.sh`
- **Status Atual**: Consulte [VERSION-CONTROL.md](VERSION-CONTROL.md)
- **Plano de Ação**: Veja [EXECUTIVE-SUMMARY.md](EXECUTIVE-SUMMARY.md)

### Para Gestão
- **Resumo Executivo**: [EXECUTIVE-SUMMARY.md](EXECUTIVE-SUMMARY.md)
- **Validação**: [VALIDATION-REPORT.md](VALIDATION-REPORT.md)
- **Decisões Arquiteturais**: [adr/](adr/)

---

## 📝 Convenções de Documentação

### Nomenclatura
- `VERSION-CONTROL.md` - Controle de versões e updates
- `EXECUTIVE-SUMMARY.md` - Resumos para stakeholders
- `VALIDATION-REPORT.md` - Relatórios técnicos de validação
- `adr/adr-XXX-nome.md` - Architecture Decision Records

### Status Icons
- ✅ Aceito/Completo
- 🚧 Em construção
- ⚠️ Requer atenção
- ❌ Rejeitado/Bloqueado
- 🔄 Em revisão

### Prioridades
- 🔴 **CRÍTICA** - Ação imediata requerida
- 🟡 **ALTA** - Atenção prioritária
- 🟢 **MÉDIA** - Planejamento necessário
- ⚪ **BAIXA** - Backlog

---

## 🔄 Processo de Atualização

### Documentos Técnicos
1. Atualizar documento relevante
2. Incrementar data de "Última Atualização"
3. Adicionar entry no histórico (se aplicável)
4. Criar PR para revisão

### ADRs (Architecture Decision Records)
1. Usar template padrão
2. Incluir contexto, decisão, consequências
3. Status: Proposto → Em Revisão → Aceito/Rejeitado
4. Não modificar ADRs aceitos (criar novos supersedendo)

---

## 📞 Contatos

**Platform Team**
- Email: platform-team@fctconsig.com.br
- Slack: #platform-team

**Domínio Owner**
- Responsável: Platform Lead
- Revisão: Mensal

---

**Última Revisão**: 2026-02-11
**Próxima Revisão**: 2026-03-11
