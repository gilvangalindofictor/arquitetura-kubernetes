# GitLab CI/CD Templates — K8s Platform Staging

Templates reutilizáveis para pipelines CI/CD no cluster staging.

## Credenciais (injetadas automaticamente)

O runner injeta via `envFrom` o Secret `gitlab-ci-credentials` (gerenciado por ESO → Vault):

| Variável | Origem Vault | Descrição |
|---|---|---|
| `HARBOR_REGISTRY` | `secret/gitlab/ci-variables.harbor_registry_url` | Registry Harbor |
| `HARBOR_USER` | `secret/gitlab/ci-variables.harbor_robot_user` | Robot account CI |
| `HARBOR_PASSWORD` | `secret/gitlab/ci-variables.harbor_robot_password` | Robot secret |
| `SONAR_HOST_URL` | `secret/gitlab/ci-variables.sonar_host_url` | SonarQube URL |
| `SONAR_TOKEN` | `secret/gitlab/ci-variables.sonar_token` | Analysis token |

## Templates disponíveis

| Arquivo | Uso |
|---|---|
| `templates/base.gitlab-ci.yml` | Stages, variáveis e defaults base |
| `templates/build.gitlab-ci.yml` | Job `.build` (Docker + Harbor push) |
| `templates/scan.gitlab-ci.yml` | Job `.sonarqube-check` |
| `templates/deploy.gitlab-ci.yml` | Job `.deploy-staging` (kubectl rollout) |

## Exemplos completos

- `examples/java-springboot.gitlab-ci.yml` — Maven + SonarQube + Harbor + kubectl

## Uso rápido

```yaml
# .gitlab-ci.yml do projeto

include:
  - local: '/gitlab-ci/templates/base.gitlab-ci.yml'
  - local: '/gitlab-ci/templates/build.gitlab-ci.yml'
  - local: '/gitlab-ci/templates/scan.gitlab-ci.yml'

build-job:
  extends: .build

scan-job:
  extends: .sonarqube-check
```

## Notas

- Runner usa Kubernetes executor → jobs criam pods temporários em `gitlab-staging`
- Cache S3: bucket `k8s-platform-gitlab-artifacts-891377105802`
- Harbor robot account: `robot$gitlab-ci` (system-level, acesso a todos os projetos)
