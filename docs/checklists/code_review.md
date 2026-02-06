# Code Review Checklist

> Usado pelo agente `reviewer` durante consenso

## 1. Funcionalidade

- [ ] **Requisito atendido**: Código resolve o problema proposto
- [ ] **Edge cases**: Casos extremos tratados
- [ ] **Error handling**: Erros tratados apropriadamente
- [ ] **Validações**: Inputs validados antes de processar

## 2. Qualidade do Código

- [ ] **Legibilidade**: Código claro e fácil de entender
- [ ] **Nomenclatura**: Nomes descritivos (variáveis, funções, classes)
- [ ] **Função única**: Cada função faz uma coisa só (Single Responsibility)
- [ ] **Tamanho**: Funções < 50 linhas, classes < 300 linhas (guideline)
- [ ] **Duplicação**: Sem código duplicado (DRY)
- [ ] **Complexidade**: Sem complexidade ciclomática excessiva

## 3. Manutenibilidade

- [ ] **Padrões**: Segue conventions do projeto (docs/context/conventions.md)
- [ ] **Estrutura**: Organização lógica dos arquivos
- [ ] **Dependências**: Sem dependências desnecessárias
- [ ] **Abstração**: Nível de abstração apropriado (não over-engineering)
- [ ] **Testabilidade**: Código fácil de testar

## 4. Performance

- [ ] **Algoritmos**: Complexidade algorítmica apropriada
- [ ] **Queries**: Queries otimizadas (índices, N+1)
- [ ] **Memory**: Sem vazamentos de memória óbvios
- [ ] **Recursos**: Recursos liberados corretamente (conexões, files)

## 5. Segurança

Consultar: `docs/checklists/security_inline.md`

- [ ] **Inputs**: Validados e sanitizados
- [ ] **Queries**: Parametrizadas
- [ ] **Secrets**: Sem hardcoded secrets
- [ ] **Auth/Authz**: Implementado onde necessário

## 6. Testes

Consultar: `docs/checklists/test_gate.md`

- [ ] **Cobertura**: Testes existem e cobrem casos importantes
- [ ] **Qualidade**: Testes não são frágeis
- [ ] **Isolamento**: Testes isolados (não dependem de ordem)

## 7. Documentação

- [ ] **Código complexo**: Lógica complexa tem comentários explicativos
- [ ] **API pública**: Funções públicas têm docstrings/JSDoc
- [ ] **Decisões**: Decisões arquiteturais documentadas (se relevante)
- [ ] **README**: Atualizado se necessário

## 8. Infrastructure as Code (Terraform)

- [ ] **Idempotência**: `terraform plan` pós-apply retorna "No changes"
- [ ] **Naming**: Recursos com naming convention consistente
- [ ] **Outputs**: Outputs definidos para valores reutilizáveis
- [ ] **Variables**: Variáveis com description e validation
- [ ] **Modules**: Módulos com README explicando uso
- [ ] **State**: Backend remoto configurado (não local)

## Formato de Avaliação

```
[REVIEWER] 🔍 Code Reviewer
AVALIAÇÃO: <1-2 frases sobre qualidade geral>
RISCOS: <lista inline ou "nenhum">
AÇÃO: <aprovar / bloquear / condicionar>
```

### Exemplos

**Aprovar**:
```
[REVIEWER] 🔍 Code Reviewer
AVALIAÇÃO: Código limpo, bem testado, segue conventions.
RISCOS: nenhum
AÇÃO: aprovar
```

**Condicionar**:
```
[REVIEWER] 🔍 Code Reviewer
AVALIAÇÃO: Lógica correta mas Service tem 280 linhas com 3 responsabilidades.
RISCOS: manutenibilidade, testabilidade
AÇÃO: condicionar — extrair AuthService e ValidationService antes de merge
```

**Bloquear**:
```
[REVIEWER] 🔍 Code Reviewer
AVALIAÇÃO: Query concatena input do usuário diretamente (SQL injection).
RISCOS: segurança CRÍTICO
AÇÃO: bloquear — usar parametrized queries
```

## Critérios de Aprovação

- ✅ **Aprovar**: Todos os itens críticos OK, pequenos ajustes podem ser feitos depois
- ⚠️ **Condicionar**: Issues significativas que devem ser resolvidas, mas não bloqueiam progresso
- ❌ **Bloquear**: Issues críticas (segurança, funcionalidade quebrada, violação de regras invioláveis)
