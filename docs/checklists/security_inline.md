# Security Check Inline

> Executar ANTES de marcar qualquer task que gera código como DONE

## Checklist Obrigatório

- [ ] **Input Validation**: Todos os inputs são validados e sanitizados
- [ ] **Parametrized Queries**: Queries usam parametrização (NUNCA concatenação de strings)
- [ ] **Output Encoding**: Outputs são encoded corretamente (prevenção XSS)
- [ ] **Authentication/Authorization**: Endpoints que precisam têm auth/authz implementados
- [ ] **No Hardcoded Secrets**: Sem senhas, tokens ou chaves hardcoded no código
- [ ] **CORS Configuration**: CORS configurado corretamente (não `*` em produção)
- [ ] **Rate Limiting**: Rate limiting considerado para endpoints públicos
- [ ] **Secure Logging**: Logs sem dados sensíveis (senhas, tokens, PII)
- [ ] **Security Headers**: Headers de segurança configurados (CSP, HSTS, X-Frame-Options)
- [ ] **Dependency Vulnerabilities**: Dependências sem CVEs conhecidas críticas

## Terraform/IaC Específico

- [ ] **Secrets Management**: Secrets via Vault/ESO, nunca em variáveis
- [ ] **Network Policies**: Network policies/Security groups configurados (least privilege)
- [ ] **Encryption**: Dados em trânsito e em repouso encriptados
- [ ] **IAM Policies**: Policies com least privilege (não `*`)
- [ ] **Public Exposure**: Recursos não expostos publicamente sem necessidade
- [ ] **Audit Logging**: CloudTrail/audit logs habilitados

## Se Algum Item Falhar

1. **Corrigir ANTES de marcar task como done**
2. Se houve trade-off de segurança justificado:
   - Registrar em `docs/context/decisions.md`
   - Incluir: qual item, por que, mitigação, quando será resolvido

## AÇÃO: Bloqueador

Task NÃO pode ser marcada como completa até este checklist passar 100%.
