# Conventions Template

> **Responsabilidade**: Usuário + AI (inferido do código + refinamentos)
> **Quando atualizar**: Setup inicial + quando convenções mudam
> **Prioridade de leitura**: 3

---

## Naming Conventions

### Código

**[Linguagem Principal]**: [Ex: Python, TypeScript, Go, etc.]

**Variáveis**:
- Estilo: [snake_case / camelCase / PascalCase]
- Exemplo: `user_profile`, `isAuthenticated`

**Funções**:
- Estilo: [snake_case / camelCase]
- Padrão: [verbo_substantivo]
- Exemplo: `get_user_by_id()`, `calculateTotal()`

**Classes**:
- Estilo: [PascalCase]
- Exemplo: `UserRepository`, `AuthService`

**Constantes**:
- Estilo: [UPPER_SNAKE_CASE]
- Exemplo: `MAX_RETRIES`, `API_TIMEOUT`

**Files**:
- Estilo: [kebab-case / snake_case]
- Exemplo: `user-service.ts`, `auth_handler.py`

---

### Infrastructure as Code

**Terraform**:

**Resources**:
- Padrão: `<tipo>_<ambiente>_<nome>_<sufixo>`
- Exemplo: `aws_eks_staging_cluster`, `helm_release_production_gitlab`

**Modules**:
- Pasta: [kebab-case]
- Exemplo: `modules/kube-prometheus-stack/`

**Variables**:
- Estilo: [snake_case]
- Exemplo: `cluster_name`, `enable_monitoring`

**Kubernetes**:

**Resources**:
- Naming: `<app>-<component>-<environment>`
- Exemplo: `gitlab-webservice-production`, `prometheus-server-staging`

**Labels obrigatórias**:
```yaml
labels:
  app.kubernetes.io/name: [app-name]
  app.kubernetes.io/component: [component]
  app.kubernetes.io/instance: [release-name]
  app.kubernetes.io/managed-by: [terraform/helm]
  environment: [staging/production]
```

**Namespaces**:
- Padrão: `<purpose>-<environment>`
- Exemplo: `gitlab-production`, `monitoring-staging`

---

## Estrutura de Pastas

```
project-root/
├── docs/                      # Toda documentação
│   ├── context/               # Docs de contexto (este arquivo, etc.)
│   ├── adr/                   # Architecture Decision Records
│   ├── logbook/               # Diários de bordo
│   ├── planning/              # Markdowns de planejamento
│   ├── agents/                # Perfis de agentes AI
│   ├── skills/                # Skills por domínio
│   ├── checklists/            # Checklists de qualidade
│   └── templates/             # Templates de documentos
│
├── [infrastructure-code]/     # Terraform, K8s manifests
├── [application-code]/        # Código da aplicação (se houver)
├── tests/                     # Testes organizados por tipo
│   ├── unit/
│   ├── integration/
│   ├── e2e/
│   └── performance/
│
└── scripts/                   # Scripts utilitários
```

---

## Git

**Branches**:
- Main: `main`
- Feature: `feature/<nome>` ou `feat/<nome>`
- Fix: `fix/<nome>`
- Hotfix: `hotfix/<nome>`

**Commits**:
- Formato: [Conventional Commits](https://www.conventionalcommits.org/)
- Padrão: `<type>(<scope>): <description>`
- Tipos: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `perf`
- Exemplo: `feat(auth): add OAuth2 login flow`

**Co-authorship**:
- Incluir ao final de commits feitos por AI:
  ```
  Co-Authored-By: Claude <noreply@anthropic.com>
  ```

---

## Code Style

### [Linguagem Principal]

**Linter**: [Ex: eslint, pylint, golangci-lint]

**Formatter**: [Ex: prettier, black, gofmt]

**Regras Principais**:
- Indentação: [2 spaces / 4 spaces / tabs]
- Linha máxima: [80 / 100 / 120] caracteres
- Strings: [single quotes / double quotes]
- Trailing comma: [yes / no]

**Imports**:
- Ordenação: [alfabética / por tipo]
- Agrupamento: [stdlib → third-party → local]

---

### Terraform

**Formatter**: `terraform fmt`

**Estrutura de arquivo**:
```hcl
# 1. Terraform/Provider config
# 2. Data sources
# 3. Locals
# 4. Resources
# 5. Outputs
```

**Comentários**:
- Sempre explicar: por que (não o que)
- Exemplo:
  ```hcl
  # PostgreSQL in public subnet to allow unseal from Lambda
  # TODO: Move to private subnet after VPC endpoints implementation
  ```

---

## Testes

### Naming

- Unit: `test_<função>_<cenário>`
- Integration: `test_<fluxo>_<cenário>`
- E2E: `<feature>.<cenário>.spec.ts`

**Exemplos**:
- `test_get_user_returns_user_when_exists()`
- `test_create_order_validates_inventory()`
- `auth.login-flow.spec.ts`

### Organização

- Mirrors da estrutura de código
- Test fixtures em `tests/fixtures/`
- Test helpers em `tests/helpers/`

---

## Comentários e Documentação

### Quando comentar

✅ **Sempre**:
- Lógica complexa não óbvia
- Decisões de design (trade-offs)
- TODOs com contexto
- Workarounds temporários (com ticket/issue)
- Algorítimos complexos

❌ **Nunca**:
- O que o código faz (código deve ser auto-explicativo)
- Comentários óbvios (`i++; // incrementa i`)

### Formato de TODOs

```python
# TODO(usuario): Descrição curta do que fazer
# Context: Por que é TODO e não foi feito agora
# Related: #123 (issue number se aplicável)
```

### Docstrings / JSDoc

Obrigatório para:
- Funções públicas (APIs)
- Classes e métodos públicos
- Funções complexas

Formato:
```python
def calculate_discount(price: float, coupon: str) -> float:
    """
    Calculate final price after applying coupon discount.

    Args:
        price: Original price in USD
        coupon: Coupon code (case-insensitive)

    Returns:
        Final price after discount

    Raises:
        ValueError: If coupon is invalid
    """
```

---

## Error Handling

### Logs

**Níveis**:
- DEBUG: Informação detalhada para debugging
- INFO: Eventos normais (request recebido, job completado)
- WARN: Algo inesperado mas recuperável (retry, fallback)
- ERROR: Erros que impedem operação mas sistema continua
- CRITICAL: Falha catastrófica (sistema deve alertar imediatamente)

**Formato**:
```json
{
  "timestamp": "2026-02-06T12:34:56Z",
  "level": "ERROR",
  "service": "auth-service",
  "message": "Failed to authenticate user",
  "user_id": "12345",
  "error": "InvalidCredentials",
  "trace_id": "abc-123-def"
}
```

**⚠️ Segurança**:
- NUNCA logar: senhas, tokens, chaves, PII completo
- Logar: IDs, tipos de erro, trace IDs

### Propagação de Erros

[Descrever padrão do projeto - wrap errors, error types, etc.]

---

## Security

### Secrets

- NUNCA hardcoded no código
- SEMPRE via: [Vault / AWS Secrets Manager / Environment Variables]
- Formato de nome: [UPPER_SNAKE_CASE]

### Sensitive Data

**PII (Personally Identifiable Information)**:
- Em logs: mascarar ou usar IDs
- Em banco: encriptar campos sensíveis
- Em trânsito: TLS obrigatório

---

## Performance

**Guidelines**:
- Queries com índices apropriados
- Paginação para listas > 100 items
- Caching para dados frequentes e estáveis
- Lazy loading quando possível

**Benchmarks**:
- API response time: < 200ms p95
- Query time: < 100ms p95
- [Adicionar benchmarks específicos do projeto]

---

## Review

### Pull Requests

**Tamanho**: < 400 linhas (guideline, não bloqueador)

**Descrição obrigatória**:
```markdown
## Summary
[O que muda]

## Test Plan
- [ ] Unit tests passando
- [ ] Integration tests passando
- [ ] Testado manualmente: [descrever]

## Screenshots
[Se UI change]
```

**Aprovação**:
- Mínimo: 1 aprovação
- Crítico (infra, security): 2 aprovações

---

## Projeto Específico

[Adicionar convenções específicas deste projeto que não se encaixam nas categorias acima]

---

_Última atualização: YYYY-MM-DD_
