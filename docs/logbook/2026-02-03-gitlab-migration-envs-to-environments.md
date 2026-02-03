# 📓 Diário de Bordo — Migração GitLab: envs/marco3 → environments/staging

| Campo          | Valor                                    |
|----------------|------------------------------------------|
| **Data**       | 2026-02-03                               |
| **Demanda**    | Consolidar estrutura TF e migrar GitLab para módulo centralizado |
| **Impacto**    | alto (define source of truth + depreca envs/marco3) |
| **Agentes**    | Orquestrador, AWS, Terraform, Security   |
| **Status**     | planejamento concluído                   |

---

## Timeline

[14:00:00] Análise | Orq | Demanda: consolidar envs/marco3 vs environments/staging | impacto: alto
[14:05:00] Estrutural | Orq | Detectado: módulos duplicados (local vs centralizado) | ⚠️
[14:08:00] Consenso | AWS,TF,Sec | environments/staging = source of truth | ✅
[14:08:30] Risco | Sec | Password hardcoded em marco3 linha 157 | 🚨 crítico
[14:09:00] Verificação | TF | Módulo GitLab centralizado existe | ✅
[14:09:30] Comparação | TF | md5sum idêntico: marco3 = centralizado | ✅ 783216af...
[14:10:00] Migração | TF | Adicionado module gitlab_staging em staging/main.tf | ✅
[14:10:30] TF Init | TF | terraform init -upgrade | ✅ modules installed
[14:11:00] TF Plan | TF | 17 add, 0 change, 0 destroy | ✅ staging-gitlab.tfplan
[14:11:30] Validação | TF | 1 warning (ignore_changes redis - não bloqueante) | ⚠️
[14:12:19] DocSync | Orq | Criando logbook migração GitLab | 🔄

---

## Decisões Técnicas

### ✅ Source of Truth: `environments/staging`

**Justificativa (consenso agentes):**
- ✅ Módulos centralizados `../../modules/` (reusabilidade)
- ✅ AWS Secrets Manager (vs hardcoded password)
- ✅ Tags completas (LGPD, CostCenter, DataClassification)
- ✅ FinOps automation (auto-shutdown staging)
- ✅ Observability (ServiceMonitors, Prometheus labels)

### ❌ Deprecar: `envs/marco3`

**Problemas identificados:**
- ❌ Módulos locais `./modules/` (anti-pattern)
- 🚨 Password hardcoded linha 157 (violação segurança crítica)
- ❌ Sem FinOps, tagging básica, observability limitada
- ❌ Duplicação = drift inevitável

---

## Mudanças Implementadas

### 1. Módulo GitLab Adicionado em Staging

**Arquivo:** `environments/staging/main.tf` (linhas 203-256)

**Configuração:**
```hcl
module "gitlab_staging" {
  source = "../../modules/gitlab"  # Centralizado

  # Cost-optimized
  gitlab_replicas        = 1
  gitlab_runner_replicas = 1

  # Integração
  postgresql_host = module.postgresql_staging.service_name
  redis_host      = module.redis_staging.redis_master_service
  s3_*            = module.s3_buckets_staging.*

  # Secrets Manager (não hardcoded)
  postgresql_password_secret = kubernetes_secret.gitlab_postgresql_password
}
```

**Recursos a criar (17):**
- Namespace `gitlab-staging`
- Helm release GitLab CE 8.7.0
- IAM Role + Policy (IRSA para S3)
- Service Account K8s
- Secrets (root password auto-gerado)
- Network Policies (isolamento staging)

---

## Próximos Passos

**PENDENTE:**
1. Criar ADR-XXX: Deprecação de envs/marco3
2. Executar `terraform apply staging-gitlab.tfplan` (⚠️ requer aprovação)
3. Validar deploy GitLab (pods Running, health checks)
4. Planejar `terraform destroy` em envs/marco3
5. Remover diretório `envs/` após destroy
6. Atualizar architecture.md, decisions.md

**BLOQUEADORES:**
- Nenhum (plan válido, pronto para apply)

---

## Métricas

| Métrica | Valor |
|---------|-------|
| Módulos analisados | 2 (marco3 local, centralizado) |
| Arquivos comparados | 5 (.tf no módulo GitLab) |
| Hash MD5 módulos | Idênticos (783216af...) |
| Recursos a adicionar | 17 (GitLab staging) |
| Terraform plan time | ~45s |
| Warnings | 1 (não bloqueante) |

---

## Riscos Mitigados

| Risco | Severidade | Mitigação |
|-------|-----------|-----------|
| Password hardcoded | 🚨 Crítico | Uso de AWS Secrets Manager em staging |
| Drift entre estruturas | ⚠️ Alta | Escolha única source of truth (environments/) |
| Duplicação módulos | ⚠️ Média | Módulos centralizados em ../../modules/ |

---

## Referências

- Prompt: `docs/prompts/executor-terraform.md`
- Estrutura antiga: `terraform/envs/marco3/`
- Source of truth: `terraform/environments/staging/`
- Módulos centralizados: `terraform/modules/`
- ADR relacionada: ADR-026 Multi-Environment Refactor (a atualizar)
