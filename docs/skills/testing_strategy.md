# Skill: Testing Strategy

## Testing Pyramid (IaC)

```
        🔺
       /│\
      / │ \
     /  │  \    E2E (Manual / Smoke)
    /───┼───\
   /    │    \
  /  Integration  \   Terratest, helm test
 /─────┼──────\
/      │       \
  Unit (Limited)    Validate, fmt
──────┴────────
```

## Test Types

### 1. Terraform Validation

**Fast feedback** (< 10s):
```bash
terraform fmt -check -recursive
terraform validate
```

**Quando**: Pre-commit, CI

### 2. Integration Tests (Terratest)

**Purpose**: Validar aplicação real de infra

**Framework**: Terratest (Go)

**Pattern**:
```go
func TestModule(t *testing.T) {
    // Setup
    opts := &terraform.Options{...}

    // Teardown
    defer terraform.Destroy(t, opts)

    // Apply
    terraform.InitAndApply(t, opts)

    // Assert
    output := terraform.Output(t, opts, "name")
    assert.NotEmpty(t, output)

    // Idempotency
    exitCode := terraform.PlanExitCode(t, opts)
    assert.Equal(t, 0, exitCode)
}
```

**Quando**: CI, antes de merge crítico

### 3. Helm Tests

```bash
helm test <release> -n <namespace>
```

**Quando**: Após deploy

### 4. Smoke Tests

**Manual validation**:
- GitLab UI acessível
- Harbor registry funcionando
- Prometheus metrics coletando
- Vault unsealed

**Automation** (futuro):
```bash
# Playwright ou similar
playwright test smoke/gitlab.spec.ts
```

##Regras

1. **Integration tests obrigatórios** para módulos Terraform críticos (network, cluster, databases)
2. **helm test** obrigatório após deploy de charts complexos
3. **Smoke tests manuais** após deployment de novos serviços

## Test Gate Matrix

Ver `docs/checklists/test_gate.md`

---

_Skill v1.0 - Testes para IaC_
