# Tests Directory

## Estrutura

```
docs/tests/
├── unit/              # Testes unitários
├── integration/       # Testes de integração
├── e2e/              # Testes end-to-end (RPA com Playwright)
└── performance/      # Testes de performance/carga
```

## Organização por Tipo

### Unit Tests

**Propósito**: Testar unidades individuais de código em isolamento.

**Características**:
- Rápidos (< 1s por teste)
- Sem dependências externas (mocks/stubs)
- Alta cobertura (80%+ global, 90%+ lógica de negócio)

**Naming**: `test_<função>_<cenário>`

**Exemplo**:
```python
# tests/unit/test_user_service.py
def test_get_user_returns_user_when_exists():
    # Arrange
    mock_repo = Mock()
    mock_repo.find_by_id.return_value = User(id=1, name="Test")
    service = UserService(mock_repo)

    # Act
    user = service.get_user(1)

    # Assert
    assert user.name == "Test"
    mock_repo.find_by_id.assert_called_once_with(1)
```

---

### Integration Tests

**Propósito**: Testar integração entre componentes com dependências reais.

**Características**:
- Mais lentos (segundos a minutos)
- Usa dependências reais (banco, APIs, infra)
- Cleanup entre testes (dados isolados)

**Naming**: `test_<fluxo>_<cenário>`

**Para Terraform/IaC**:
- Usar Terratest ou similar
- Testar aplicação + destroy idempotência
- Validar outputs e estado

**Exemplo (Go + Terratest)**:
```go
// tests/integration/terraform_test.go
func TestTerraformVaultModule(t *testing.T) {
    terraformOptions := &terraform.Options{
        TerraformDir: "../../modules/vault",
    }

    defer terraform.Destroy(t, terraformOptions)
    terraform.InitAndApply(t, terraformOptions)

    vaultAddr := terraform.Output(t, terraformOptions, "vault_address")
    assert.NotEmpty(t, vaultAddr)
}
```

---

### E2E Tests (RPA)

**Propósito**: Testar fluxos completos de usuário via interface.

**Tecnologia**: Playwright

**Características**:
- Mais lentos (segundos por fluxo)
- Testa comportamento real do usuário
- Page Object Model
- Seletores via `data-testid`

**Naming**: `<feature>.<cenário>.spec.ts`

**Estrutura**:
```
tests/e2e/
├── pages/              # Page Objects
│   ├── login.page.ts
│   └── dashboard.page.ts
├── fixtures/           # Test data
│   └── users.json
└── specs/              # Test specs
    ├── auth.login.spec.ts
    └── user.crud.spec.ts
```

**Exemplo**:
```typescript
// tests/e2e/specs/auth.login.spec.ts
import { test, expect } from '@playwright/test';
import { LoginPage } from '../pages/login.page';

test('should login successfully with valid credentials', async ({ page }) => {
  const loginPage = new LoginPage(page);

  await loginPage.goto();
  await loginPage.login('user@example.com', 'password123');

  await expect(page.getByTestId('dashboard-header')).toBeVisible();
});
```

**Page Object**:
```typescript
// tests/e2e/pages/login.page.ts
export class LoginPage {
  constructor(private page: Page) {}

  async goto() {
    await this.page.goto('/login');
  }

  async login(email: string, password: string) {
    await this.page.getByTestId('email-input').fill(email);
    await this.page.getByTestId('password-input').fill(password);
    await this.page.getByTestId('login-button').click();
  }
}
```

---

### Performance Tests

**Propósito**: Validar performance e identificar gargalos.

**Ferramentas**:
- k6 (carga de APIs)
- JMeter (carga geral)
- Locust (Python-based)
- Custom benchmarks

**Características**:
- Define baselines
- Testa sob carga esperada
- Identifica degradação

**Exemplo (k6)**:
```javascript
// tests/performance/api-load.js
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  stages: [
    { duration: '2m', target: 100 },  // Ramp up
    { duration: '5m', target: 100 },  // Stay
    { duration: '2m', target: 0 },    // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<200'],  // 95% < 200ms
  },
};

export default function () {
  let response = http.get('https://api.example.com/users');
  check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 200ms': (r) => r.timings.duration < 200,
  });
  sleep(1);
}
```

---

## Executando Testes

### Unit
```bash
# Python
pytest tests/unit/ --cov=. --cov-report=html

# Node/TypeScript
npm test -- tests/unit/

# Go
go test ./tests/unit/... -cover
```

### Integration
```bash
# Terratest
cd tests/integration/
go test -v -timeout 30m

# Python
pytest tests/integration/ -v
```

### E2E
```bash
# Playwright
npx playwright test tests/e2e/

# Com UI mode
npx playwright test --ui

# Debug
npx playwright test --debug
```

### Performance
```bash
# k6
k6 run tests/performance/api-load.js

# Com metrics
k6 run --out influxdb=http://localhost:8086 tests/performance/api-load.js
```

---

## CI/CD Integration

Os testes devem ser executados no pipeline:

```yaml
# .github/workflows/tests.yml (exemplo)
name: Tests

on: [push, pull_request]

jobs:
  unit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run unit tests
        run: pytest tests/unit/ --cov

  integration:
    runs-on: ubuntu-latest
    needs: unit
    steps:
      - uses: actions/checkout@v3
      - name: Run integration tests
        run: go test ./tests/integration/... -v

  e2e:
    runs-on: ubuntu-latest
    needs: unit
    steps:
      - uses: actions/checkout@v3
      - name: Install Playwright
        run: npx playwright install
      - name: Run E2E tests
        run: npx playwright test tests/e2e/
```

---

## Test Gates

Consultar: `docs/checklists/test_gate.md`

Nenhuma task é DONE sem seus testes obrigatórios passando.

---

## Notas

- **Isolation**: Testes devem ser isolados (não dependem de ordem)
- **Cleanup**: Dados de teste devem ser limpos após execução
- **Idempotência**: Testes devem passar múltiplas vezes sem modificação
- **Fast Feedback**: Unit tests rápidos, integration/e2e podem ser mais lentos
- **Flakiness**: Evitar testes flaky (timeouts generosos, waits explícitos)

---

_Para este projeto IaC (Terraform/Kubernetes), foco em integration tests via Terratest._
