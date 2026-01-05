# ADR-001: Estrutura Inicial do Domínio Secrets Management

**Status**: ✅ Aceito  
**Data**: 2026-01-05  

---

## Contexto

O domínio **secrets-management** fornece cofre centralizado com integração CI/CD, rotação automática e auditoria.

## Decisão

### Stack (Decisão Pendente ADR-002)
- **Opção 1**: HashiCorp Vault (preferencial)
- **Opção 2**: External Secrets Operator + Cloud KMS

### Prioridade
- Crítico para cicd-platform e todos os domínios

## Referências
- [SAD v1.2](../../../../SAD/docs/sad.md)
- [ADR-005: Segurança Sistêmica](../../../../SAD/docs/adrs/adr-005-seguranca-sistemica.md)

---
**Versão**: 1.0