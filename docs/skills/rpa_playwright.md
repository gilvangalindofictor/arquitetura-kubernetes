# Skill: RPA Playwright

## Aplicabilidade

**Nota**: Este projeto é IaC/plataforma. RPA se aplica a futuras aplicações web que rodarão na plataforma, não à infraestrutura em si.

Para smoke tests manuais da plataforma (GitLab UI, Harbor UI, Grafana), Playwright pode ser usado.

## Setup

```bash
npm init playwright@latest
npx playwright install
```

## Structure

```
tests/e2e/
├── playwright.config.ts
├── pages/              # Page Objects
│   └── gitlab-login.page.ts
├── fixtures/           # Test data
└── specs/              # Tests
    └── gitlab-smoke.spec.ts
```

## Page Object Pattern

```typescript
// pages/gitlab-login.page.ts
export class GitLabLoginPage {
  constructor(private page: Page) {}

  async goto() {
    await this.page.goto('https://gitlab.example.com');
  }

  async login(username: string, password: string) {
    await this.page.getByTestId('username-input').fill(username);
    await this.page.getByTestId('password-input').fill(password);
    await this.page.getByTestId('login-button').click();
  }

  async isLoggedIn() {
    return await this.page.getByTestId('dashboard').isVisible();
  }
}
```

## Test Spec

```typescript
// specs/gitlab-smoke.spec.ts
import { test, expect } from '@playwright/test';
import { GitLabLoginPage } from '../pages/gitlab-login.page';

test('GitLab login and dashboard access', async ({ page }) => {
  const loginPage = new GitLabLoginPage(page);

  await loginPage.goto();
  await loginPage.login('root', process.env.GITLAB_ROOT_PASSWORD!);

  const isLoggedIn = await loginPage.isLoggedIn();
  expect(isLoggedIn).toBeTruthy();
});
```

## Regras

1. **Seletores via `data-testid`** (nunca CSS classes)
2. **Page Object Model** obrigatório
3. **Screenshots em falha** automáticos
4. **Testes isolados** (setup/teardown por teste)

---

_Skill v1.0 - Para smoke tests de UIs_
