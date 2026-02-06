# Test Gate

> NENHUMA task é considerada DONE sem seus testes obrigatórios passando

## Matriz de Testes por Tipo de Task

| Tipo         | Unit          | Integration   | Performance   | RPA (E2E)     | Security      |
| ------------ | ------------- | ------------- | ------------- | ------------- | ------------- |
| backend      | ✅ obrigatório | ✅ obrigatório | ○ recomendado | —             | ✅ obrigatório |
| frontend     | ✅ obrigatório | ○ recomendado | ○ recomendado | ✅ obrigatório | ✅ obrigatório |
| database     | ○ recomendado | ✅ obrigatório | ✅ obrigatório | —             | ✅ obrigatório |
| devops/infra | —             | ✅ obrigatório | ○ recomendado | —             | ✅ obrigatório |
| docs         | —             | —             | —             | —             | —             |

**Legenda**: ✅ obrigatório | ○ recomendado | — não aplicável

## 1. Unit Tests

**Quando**: Backend, Frontend

**Padrão**:
- Happy path + edge cases
- Mocks para dependências externas
- Nomes descritivos: `test_should_{ação}_when_{condição}`
- AAA pattern: Arrange, Act, Assert

**Cobertura mínima**:
- Global: 80%
- Lógica de negócio: 90%
- Controllers/Handlers: 70%

**Comandos**:
```bash
# Python
pytest --cov=. --cov-report=html

# Node/TypeScript
npm test -- --coverage

# Go
go test -cover ./...
```

**Checklist**:
- [ ] Testes unitários existem
- [ ] Cobrem happy path e edge cases
- [ ] Mocks de dependências externas implementados
- [ ] Cobertura atinge mínimo definido
- [ ] Todos os testes passam

## 2. Integration Tests

**Quando**: Backend, Database, DevOps/Infra

**Padrão**:
- Testar com dependências reais (banco, APIs, infraestrutura)
- Cleanup entre testes (dados de teste isolados)
- Usar containers quando possível (testcontainers)

**Para Terraform/IaC**:
```bash
# Terratest ou similar
cd tests/integration/
go test -v -timeout 30m
```

**Checklist**:
- [ ] Testes de integração existem
- [ ] Testam com dependências reais
- [ ] Cleanup entre testes implementado
- [ ] Todos os testes passam

## 3. Performance Tests

**Quando**: Database (obrigatório), Backend/DevOps (recomendado)

**Padrão**:
- Definir baseline de performance
- Testar sob carga esperada
- Identificar gargalos

**Exemplo (banco)**:
- Query time < 100ms para 95th percentile
- Index usage verificado

**Exemplo (API)**:
```bash
# k6 ou similar
k6 run load-test.js
```

**Checklist**:
- [ ] Baseline de performance definido
- [ ] Testes de carga executados
- [ ] Performance atende baseline
- [ ] Gargalos identificados e documentados (se houver)

## 4. RPA / E2E (Playwright)

**Quando**: Frontend (obrigatório)

**Padrão**:
- Page Object Model
- Seletores via `data-testid` (nunca CSS classes)
- Screenshots em falha
- Testes isolados (setup/teardown)

**Estrutura**:
```
tests/e2e/
├── pages/          # Page Objects
│   ├── login.page.ts
│   └── dashboard.page.ts
├── fixtures/       # Test data
└── specs/          # Test specs
    ├── auth.spec.ts
    └── user-flow.spec.ts
```

**Checklist**:
- [ ] Testes E2E escritos usando Playwright
- [ ] Page Object Model implementado
- [ ] Seletores via `data-testid`
- [ ] Screenshots configurados para falhas
- [ ] Todos os testes passam

## 5. Security Check

**Quando**: Todas as tasks que geram código

Consultar: `docs/checklists/security_inline.md`

**Checklist**:
- [ ] Security inline check executado e passou

## Execução dos Test Gates

### Antes de Marcar Task como Done

1. Identificar tipo da task
2. Executar testes obrigatórios da matriz
3. Verificar que TODOS passam
4. Se algum falhar: corrigir ANTES de marcar done

### Registro no Logbook

Formato:
```
[HH:MM:SS] TestGate | Tester | <tipo>: <N> unit, <M> integ | ✅ 100% | <tempo>
```

Exemplo:
```
[14:33:50] TestGate | Tester | 12 unit + 4 integ | ✅ 100% | 15s
```

## AÇÃO: Bloqueador

Task NÃO pode ser marcada como completa até test gates obrigatórios passarem.
