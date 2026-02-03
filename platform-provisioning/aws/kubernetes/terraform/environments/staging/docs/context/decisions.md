# Architecture Decision Records (ADRs)

Este documento registra decisões arquiteturais significativas para o projeto de plataforma Kubernetes na AWS.

---

## ADR-027 — Deprecação de envs/marco3 e Consolidação em environments/

| Campo       | Valor                              |
|-------------|-------------------------------------|
| Data        | 2026-02-03                          |
| Status      | ✅ aprovada                         |
| Agentes     | Orquestrador, AWS, TF, Security     |
| Demanda     | [Logbook 2026-02-03](../logbook/2026-02-03-gitlab-migration-envs-to-environments.md) |

### Contexto

Estrutura Terraform duplicada detectada:
- `terraform/envs/marco3/` — estrutura antiga com módulos locais
- `terraform/environments/staging/` — estrutura moderna com módulos centralizados

**Problemas da duplicação:**
1. Drift inevitável entre duas sources of truth
2. Módulos locais em `envs/marco3/modules/` vs centralizados em `modules/`
3. 🚨 Password hardcoded em `envs/marco3/main.tf:157` (violação segurança)
4. Falta de padronização: tagging, FinOps, observability

### Decisão

**Consolidar `environments/` como única source of truth e deprecar `envs/`.**

**Ações:**
1. ✅ Migrar módulo GitLab de `envs/marco3` para `environments/staging`
2. ✅ Usar módulos centralizados `../../modules/` (não `./modules/`)
3. ✅ Substituir secrets hardcoded por AWS Secrets Manager
4. 🔄 Executar `terraform apply` em `environments/staging` (GitLab)
5. 🔄 Executar `terraform destroy` em `envs/marco3`
6. 🔄 Remover diretório `terraform/envs/` completamente

### Alternativas Consideradas

| Alternativa | Decisão | Justificativa |
|-------------|---------|---------------|
| **Manter envs/ como source of truth** | ❌ Rejeitada | Estrutura antiga sem FinOps, tagging inadequada, módulos locais |
| **Manter ambas estruturas** | ❌ Rejeitada | Drift inevitável, complexidade operacional |
| **Consolidar em environments/** | ✅ **ESCOLHIDA** | Módulos centralizados, Secrets Manager, FinOps, observability |

### Riscos Aceitos

| Risco | Severidade | Mitigação |
|-------|-----------|-----------|
| Downtime GitLab durante migração | ⚠️ Média | Deploy em novo namespace `gitlab-staging`, teste antes de remover marco3 |
| Perda de histórico state marco3 | Baixa | State marco3 permanece em S3 (não deletar bucket) |

### Resultado

**Plan validado (2026-02-03 14:11):**
- ✅ 17 recursos a adicionar (GitLab staging)
- ✅ 0 mudanças em recursos existentes
- ✅ Idempotência preservada
- ⚠️ 1 warning não-bloqueante (ignore_changes redis)

**Benefícios:**
- Source of truth único: `terraform/environments/{env}/`
- Módulos reusáveis: `terraform/modules/{module}/`
- Segurança: AWS Secrets Manager (não hardcoded)
- FinOps: auto-shutdown staging (~70% economia)
- Observability: ServiceMonitors, Prometheus labels
- Compliance: tagging LGPD, CostCenter, DataClassification

**Arquitetura final:**
```
terraform/
├── modules/              # Centralizados, versionados
│   ├── gitlab/
│   ├── postgresql/
│   ├── redis/
│   ├── rabbitmq/
│   ├── s3-buckets/
│   └── finops-automation/
├── environments/         # Source of truth ÚNICO
│   ├── staging/
│   │   ├── main.tf       # ✅ usa ../../modules/
│   │   ├── backend.tf
│   │   └── variables.tf
│   └── prod/
└── envs/                 # ❌ DEPRECATED (remover após destroy)
    └── marco3/
```

### Referências

- [Logbook Migração GitLab](../logbook/2026-02-03-gitlab-migration-envs-to-environments.md)
- [Prompt Executor Terraform](../prompts/executor-terraform.md) — Seção "Estrutura de Pastas"
- ADR-026 Multi-Environment Refactor (a atualizar)
- Terraform Plan: `environments/staging/staging-gitlab.tfplan`

### Próximas Ações

- [ ] Apply GitLab em environments/staging
- [ ] Validar deploy (pods Running, health checks)
- [ ] Destroy resources em envs/marco3
- [ ] Remover diretório envs/
- [ ] Atualizar ADR-026
- [ ] Atualizar architecture.md
