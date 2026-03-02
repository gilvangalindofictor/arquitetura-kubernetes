# GAP-007: Kyverno Enforcement Mode Activation
**Date:** 2026-03-02
**Operator:** K8s Expert + Security Specialist Agent
**Duration:** ~10 min
**Status:** COMPLETO

---

## Contexto

- GAP-007 agendado para ativação em 2026-03-03 (após 7 dias de audit com 0 violations)
- Kyverno compliance: 100% (80/80 PASS) validado 2026-03-02 (baseline limpo)
- Pré-condição cumprida: 0 violations em todos os clusterpolicyreports

---

## Estado Pré-Mudança

| Policy | Action Anterior |
|--------|----------------|
| require-corporate-labels | audit |
| validate-namespace-naming | audit |
| validate-label-values | audit |
| validate-service-naming | audit (mantido) |
| allow-governance-exceptions | audit (mantido) |

**Violations:** 0 (confirmado via `kubectl get clusterpolicyreport --all-namespaces`)
**Kyverno pods:** 6/6 Running (3 admission-controller, 1 background, 1 cleanup, 1 reports)

---

## Ações Realizadas

1. Leitura do arquivo `docs/governance/validation-rules.yaml`
2. Edit cirúrgico nas 3 policies-alvo: `audit` → `Enforce` (capitalizado, padrão Kyverno 1.11+)
3. Audit policies não-alvo atualizadas para `Audit` (capitalizado, sem mudança funcional)
4. `kubectl apply -f validation-rules.yaml` — 5 policies configured, 0 errors
5. Re-apply com casing capitalizado — sem deprecation warning
6. Validação de enforcement via `--dry-run=server`

---

## Resultado

| Policy | Action Final |
|--------|-------------|
| require-corporate-labels | **Enforce** |
| validate-namespace-naming | **Enforce** |
| validate-label-values | **Enforce** |
| validate-service-naming | Audit |
| allow-governance-exceptions | Audit |

**Teste de enforcement:**
- `kubectl create namespace invalid-namespace-test --dry-run=server` → BLOQUEADO (admission webhook denied)
- `kubectl create namespace staging-integration-test2 --dry-run=server` → BLOQUEADO (padrão {env}-{domain}-{product} não satisfeito)
- Mensagem de erro exibida ao usuário conforme ADR-048

---

## Kubectl Apply Output

```
clusterpolicy.kyverno.io/require-corporate-labels configured
clusterpolicy.kyverno.io/validate-namespace-naming configured
clusterpolicy.kyverno.io/validate-service-naming configured
clusterpolicy.kyverno.io/validate-label-values configured
clusterpolicy.kyverno.io/allow-governance-exceptions configured
```

---

## Arquivo Modificado

`docs/governance/validation-rules.yaml` — linhas 18, 61, 90, 120, 194
- Lines 18, 61, 120: `audit` → `Enforce`
- Lines 90, 194: `audit` → `Audit` (capitalização apenas, sem mudança funcional)

---

## Rollback Procedure

Se necessário reverter para audit mode:

```bash
# Editar validation-rules.yaml: Enforce → Audit nas 3 policies
sed -i 's/validationFailureAction: Enforce/validationFailureAction: Audit/g' \
  docs/governance/validation-rules.yaml

kubectl apply -f docs/governance/validation-rules.yaml

# Confirmar rollback
kubectl get clusterpolicy -o custom-columns='NAME:.metadata.name,ACTION:.spec.validationFailureAction'
```

**Tempo estimado de rollback:** < 2 minutos

---

## Riscos Identificados

- **validate-namespace-naming** com `background: false` — só atua na admission (não re-avalia recursos existentes). Namespaces existentes não conformes não são afetados retroativamente. Novo impacto apenas em CREATE/UPDATE de Namespaces.
- **require-corporate-labels** e **validate-label-values** com `background: true` — podem gerar policy reports para recursos existentes sem labels corretas, mas NÃO bloqueiam retroativamente (só novos recursos na admission).
- Deploys de workloads sem labels corporativas em namespaces `staging-*` ou `prod-*` serão **BLOQUEADOS** a partir desta data.

---

## Impacto

- Governança de labels: Obrigatória e bloqueante para novos workloads em staging-* e prod-*
- Governança de namespaces: Obrigatória e bloqueante para novos namespaces
- Times de desenvolvimento devem garantir labels `domain`, `owner`, `environment`, `app.kubernetes.io/name`, `app.kubernetes.io/part-of` em todos os manifestos

---

## Referências

- ADR-048: Naming Conventions Determinísticas
- `docs/governance/validation-rules.yaml`
- `docs/demands-backlog.md` — item GAP-007 marcado como concluído
