# GAP-005: GitLab CI/CD Integration Completa — 2026-02-19

## Resumo

GAP-005 concluído: runner id=115 agora tem credenciais Harbor + SonarQube injetadas via ESO ExternalSecret, RBAC mínima, namespace do executor corrigido e templates .gitlab-ci.yml criados.

## Timeline

| Horário | Ação | Resultado |
|---------|------|-----------|
| 12:49 | Harbor robot account `robot$gitlab-ci` criado via API | HTTP:201, secret gerado |
| 12:49 | SonarQube GLOBAL_ANALYSIS_TOKEN `gitlab-ci` criado | HTTP:200, token gerado |
| 12:50 | Vault KV seed: `secret/harbor/robot-account` + `secret/gitlab/ci-variables` | 2 secrets criados (v1) |
| ~12:50 | Vault policy `eso-reader` atualizada: + `secret/data/gitlab/*` | Policy aplicada via kubectl cp + vault write |
| ~12:51 | TF: ESO ExternalSecret + null_resource envFrom + RBAC + namespace fix (main.tf) | Código escrito |
| 13:04 | ESO sync: `gitlab-ci-credentials` K8s Secret criado (5 keys) | SecretSynced/Ready:True |
| 13:04 | Runner restartado com envFrom | envFrom=[{secretRef: gitlab-ci-credentials}] |
| 13:04 | Configmap executor namespace: `gitlab` → `gitlab-staging` | Corrigido |
| ~13:05 | RBAC Role tightened: `resources:['*'],verbs:['*']` → least-privilege | RBAC aplicada |
| 13:10 | Validação end-to-end | Todos os checks ✅ |
| 13:15 | .gitlab-ci.yml templates criados em `domains/cicd-platform/infra/gitlab-ci/` | 5 arquivos |

## Componentes Criados/Modificados

### Terraform (environments/staging/main.tf)
- `kubernetes_manifest.gitlab_ci_credentials_eso` — ESO ExternalSecret Vault→K8s
- `null_resource.gitlab_runner_envfrom` — kubectl patch deployment envFrom
- `null_resource.gitlab_runner_namespace_fix` — python3 patch configmap namespace
- `kubernetes_manifest.gitlab_runner_role_least_privilege` — RBAC Role least-privilege
- Provider `hashicorp/null` adicionado ao required_providers

### Vault
- `secret/harbor/robot-account`: name=`robot$gitlab-ci`, secret=`CoDgiJ4...`
- `secret/gitlab/ci-variables`: 5 keys (harbor_registry_url, harbor_robot_user, harbor_robot_password, sonar_host_url, sonar_token)
- Policy `eso-reader`: `+secret/data/gitlab/*`, `+secret/metadata/gitlab/*`

### HCL
- `modules/vault-config/vault_policies/eso-reader.hcl`: atualizado com sonarqube/*, grafana/*, gitlab/* (drift fix)

### GitLab CI Templates
- `domains/cicd-platform/infra/gitlab-ci/templates/base.gitlab-ci.yml`
- `domains/cicd-platform/infra/gitlab-ci/templates/build.gitlab-ci.yml`
- `domains/cicd-platform/infra/gitlab-ci/templates/scan.gitlab-ci.yml`
- `domains/cicd-platform/infra/gitlab-ci/templates/deploy.gitlab-ci.yml`
- `domains/cicd-platform/infra/gitlab-ci/examples/complete.gitlab-ci.yml`

## Bugs Descobertos e Corrigidos

### Executor Namespace Errado
- **Problema**: `config.template.toml` tinha `namespace = "gitlab"` (namespace não existe)
- **Impacto**: CI jobs falhariam ao tentar criar pods em namespace inexistente
- **Fix**: `null_resource.gitlab_runner_namespace_fix` com python3 interpreter

### Vault Policy Drift
- **Problema**: `eso-reader.hcl` no repo tinha apenas keycloak/* e harbor/* mas Vault real já tinha sonarqube/* e grafana/*
- **Fix**: HCL atualizado para refletir estado real + adicionar gitlab/*

### Terraform HCL - Single Quotes no Heredoc
- **Problema**: `<<-'EOT'` (single quotes no heredoc marker) é inválido em HCL
- **Fix**: Usar `<<-EOT` + `interpreter = ["python3", "-c"]` para comandos com quoting complexo

## Validação

| Check | Resultado |
|-------|-----------|
| ESO ExternalSecret `gitlab-ci-credentials` | SecretSynced / Ready=True ✅ |
| Runner envFrom (5 vars) | HARBOR_*, SONAR_* injetadas ✅ |
| Harbor `robot$gitlab-ci` auth | HTTP:200 /api/v2.0/projects ✅ |
| SonarQube token `gitlab-ci` | HTTP:200 /api/authentication/validate ✅ |
| RBAC: create pods | yes ✅ |
| RBAC: delete deployments | no ✅ (least-privilege) |
| Executor namespace | `gitlab-staging` (corrigido de `gitlab`) ✅ |
| GitLab API reachable | HTTP:401 (up, auth expected) ✅ |

## Credenciais (Vault paths)

```
Vault:
  secret/harbor/robot-account
    name: robot$gitlab-ci
    secret: CoDgiJ41zFRsyOcRsp4GKZ6R5xtdfAc6

  secret/gitlab/ci-variables
    harbor_registry_url: harbor.staging.internal
    harbor_robot_user: robot$gitlab-ci
    harbor_robot_password: CoDgiJ41zFRsyOcRsp4GKZ6R5xtdfAc6
    sonar_host_url: http://sonarqube.staging.internal
    sonar_token: sqa_6efac477a6e652bcb1be88483b74155778d4e022
```

## Padrões Documentados

### python3 interpreter para comandos complexos em Terraform
```hcl
provisioner "local-exec" {
  interpreter = ["python3", "-c"]
  command     = <<-EOT
    import json, subprocess
    # Python puro — sem problemas de quoting bash/HCL
  EOT
}
```

### ESO ExternalSecret sem template (simples)
```hcl
resource "kubernetes_manifest" "NAME_eso" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    # ...
    spec = {
      target = {
        name           = "secret-name"
        creationPolicy = "Owner"
        # Sem template block = segredos mapeados diretamente (secretKey → data key)
      }
    }
  }
  field_manager { force_conflicts = true }
}
```
