# Contexto local: Documentação oficial (template)

Objetivo: centralizar trechos oficiais e links pinados por versão para uso offline pelos agentes.

Formato (obrigatório):

- `tool`: nome do produto (ex: terraform, aws, kubectl, helm, keycloak)
- `version`: versão utilizada no projeto (ex: 1.6.0)
- `source`: link oficial com versão (ex: https://www.terraform.io/docs/cli/commands/apply.html#v1.6.0)
- `excerpt`: trecho importante ou comando prático (1-3 linhas)
- `path`: arquivo local em `docs/vendor/<tool>.md` quando houver conteúdo maior

Exemplo:
---
---
tool: terraform
version: 1.14
source: https://www.terraform.io/
excerpt: |
  - `terraform apply -auto-approve <plan>` — consulte `required_version` em cada módulo; projeto contém módulos com `required_version >= 1.5` e `>= 1.14`.
path: docs/vendor/terraform.md
---
tool: aws-provider
version: ~>5.0
source: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
excerpt: |
  - Provider `hashicorp/aws` pinado como `~> 5.0` em módulos principais.
path: docs/vendor/aws.md
---
tool: kubernetes-provider
version: ~>2.35
source: https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs
excerpt: |
  - Provider `hashicorp/kubernetes` pinado `~> 2.35` no módulo kube-prometheus-stack.
path: docs/vendor/kubernetes.md
---
tool: helm-provider
version: ~>2.17
source: https://registry.terraform.io/providers/hashicorp/helm/latest/docs
excerpt: |
  - Provider `hashicorp/helm` pinado `~> 2.17` no módulo kube-prometheus-stack.
path: docs/vendor/helm.md
---
tool: tls-provider
version: ~>4.0
source: https://registry.terraform.io/providers/hashicorp/tls/latest/docs
excerpt: |
  - Provider `hashicorp/tls` pinado `~> 4.0` no `eks` module.
path: docs/vendor/terraform.md
---
tool: keycloak
version: 26.5.1
source: https://www.keycloak.org/
excerpt: |
  - Observed Keycloak runtime in cluster: `Keycloak 26.5.1` (Quarkus-based distribution).
path: docs/vendor/keycloak.md
---
tool: rabbitmq
operator_version: 2.19.0
server_version: 3.13-management
source: https://www.rabbitmq.com/
excerpt: |
  - RabbitMQ Operator `2.19.0` and Server `3.13-management` referenced in data-services docs.
path: docs/vendor/rabbitmq.md
---
tool: redis
operator_version: SpotaHome-3.3.0
source: https://redis.io/
excerpt: |
  - SpotaHome Redis Operator v3.3.0 referenced in `domains/data-services/docs/STAGING-BACKUP-STRATEGY.md`.
path: docs/vendor/redis.md
---
tool: sonarqube
version: 10.3.0
source: https://docs.sonarsource.com/sonarqube/latest/
excerpt: |
  - SonarQube chart/release v10.3.0 referenced in cicd validation reports and terraform modules.
path: docs/vendor/sonarqube.md

---
tool: data-services-docs
version: repo-context
source: ./domains/data-services/docs/
excerpt: |
  - Primary local docs: `TERRAFORM-SOURCE-OF-TRUTH.md`, `VERSIONS-AND-FEATURES.md`, `STAGING-BACKUP-STRATEGY.md`, `VALIDATION-REPORT.md`.
path: domains/data-services/docs/
---

Processo de atualização:

1. Ao fazer upgrade de `tool`/provider, atualizar `version` e `source` neste arquivo.
2. Colocar snippets longos em `docs/vendor/<tool>.md` e referenciar por `path`.
3. Agentes consultam este arquivo antes de buscar na web.

Responsabilidade: manter sincronizado durante PRs de bump de versão; usar CI para alertar docs stale quando `version` divergir do `tools.lock`.
