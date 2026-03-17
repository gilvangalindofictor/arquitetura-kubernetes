# @internal/plugin-platform-scaffolder-actions

Custom Scaffolder actions da plataforma Kubernetes.

Sprint S6-C | Backstage 1.48.0 | ADR-104 | GAP-003

---

## Actions disponíveis

| Action ID | Descrição |
|---|---|
| `platform:manifest:validate` | Valida `.platform/manifest.yaml` contra o JSON Schema da plataforma |

---

## Instalação

### 1. Adicionar ao workspace Yarn

No `packages/backend/package.json`, adicione a dependência:

```json
"@internal/plugin-platform-scaffolder-actions": "link:../../plugins/platform-scaffolder-actions"
```

Execute:

```bash
yarn install
```

### 2. Registrar no backend (`packages/backend/src/index.ts`)

O plugin usa a API **new backend system** do Backstage 1.48.0 (`backend.add()`):

```typescript
import { createBackend } from '@backstage/backend-defaults';
import { createValidateManifestAction } from '@internal/plugin-platform-scaffolder-actions';
import { scaffolderActionsExtensionPoint } from '@backstage/plugin-scaffolder-node/alpha';
import { createBackendModule } from '@backstage/backend-plugin-api';

// Módulo que registra as custom actions no Scaffolder
const platformScaffolderActionsModule = createBackendModule({
  pluginId: 'scaffolder',
  moduleId: 'platform-actions',
  register(reg) {
    reg.registerInit({
      deps: {
        scaffolderActions: scaffolderActionsExtensionPoint,
      },
      async init({ scaffolderActions }) {
        scaffolderActions.addActions(
          createValidateManifestAction(),
        );
      },
    });
  },
});

const backend = createBackend();

// ... outros plugins ...
backend.add(import('@backstage/plugin-scaffolder-backend'));
backend.add(import('@backstage/plugin-scaffolder-backend-module-gitlab'));

// Registrar custom actions da plataforma
backend.add(platformScaffolderActionsModule);

backend.start();
```

### 3. Variável de ambiente (opcional)

Por padrão, a action resolve o JSON Schema em:

```
<repo-root>/domains/platform-core/app-provisioning/schemas/v1/manifest-schema.json
```

Para sobrescrever, defina a variável de ambiente **antes** de iniciar o backend:

```bash
export PLATFORM_SCHEMA_PATH=/app/schemas/v1/manifest-schema.json
```

No Helm values (`helm-values-staging.yaml`), adicione em `backstage.extraEnvVars`:

```yaml
backstage:
  extraEnvVars:
    - name: PLATFORM_SCHEMA_PATH
      value: /app/schemas/v1/manifest-schema.json
```

Garanta que o arquivo schema seja montado no container (ConfigMap ou copiado no Dockerfile).

---

## Uso no template YAML

```yaml
steps:
  # Step 1: gera os arquivos (incluindo .platform/manifest.yaml)
  - id: fetch-template
    name: "Gerar estrutura do projeto"
    action: fetch:template
    input:
      url: ./skeleton
      values:
        name: ${{ parameters.name }}
        domain: ${{ parameters.domain }}
        type: ${{ parameters.type }}
        # ... outros valores

  # Step 2: valida o manifest gerado antes do publish
  - id: validate-manifest
    name: "Validar manifest.yaml"
    action: platform:manifest:validate
    input:
      manifestPath: .platform/manifest.yaml   # opcional — este é o default

  # Step 3: abre o MR apenas se a validação passou
  - id: publish-gitlab
    name: "Criar repositório no GitLab"
    action: publish:gitlab
    input:
      repoUrl: "gitlab.staging.internal?owner=${{ parameters.gitlab_group }}&repo=${{ parameters.name }}"
      description: ${{ parameters.description }}
      defaultBranch: main
      repoVisibility: ${{ parameters.repo_visibility }}
      onExistingBranch: error
```

### Acessando os outputs em steps seguintes

```yaml
  - id: notify
    name: "Log pós-validação"
    action: debug:log
    input:
      message: |
        Manifest válido!
        App: ${{ steps['validate-manifest'].output.appName }}
        Domain: ${{ steps['validate-manifest'].output.domain }}
        Type: ${{ steps['validate-manifest'].output.type }}
```

---

## Input / Output

### Input

| Campo | Tipo | Obrigatório | Default | Descrição |
|---|---|---|---|---|
| `manifestPath` | `string` | Não | `.platform/manifest.yaml` | Path relativo ao workspace do manifest a validar |

### Output

| Campo | Tipo | Descrição |
|---|---|---|
| `valid` | `boolean` | `true` se o manifest passou na validação |
| `appName` | `string` | `metadata.name` extraído do manifest |
| `domain` | `string` | `metadata.domain` extraído do manifest |
| `type` | `string` | `metadata.type` extraído do manifest |

---

## Schema de validação

O JSON Schema canônico está em:

```
domains/platform-core/app-provisioning/schemas/v1/manifest-schema.json
```

Referências: ADR-104 (Onboarding), ADR-047 (Domínios), ADR-048 (Naming kebab-case), GAP-003 (Sprint S1).

---

## Dependências npm

```
@backstage/plugin-scaffolder-node  ^0.7.1   — createTemplateAction, ctx.workspacePath
@backstage/backend-plugin-api      ^1.2.1   — createBackendModule (new backend system)
ajv                                ^8.17.1  — validação JSON Schema draft-2020-12
ajv-formats                        ^3.0.1   — suporte a format: "hostname", "uri"
js-yaml                            ^4.1.0   — parse de YAML
```

---

## Erros comuns

| Erro | Causa | Solução |
|---|---|---|
| `Manifest não encontrado` | O skeleton não gerou `.platform/manifest.yaml` | Verifique `skeleton/.platform/manifest.yaml.njk` |
| `JSON Schema da plataforma não encontrado` | Path do schema incorreto no container | Configure `PLATFORM_SCHEMA_PATH` |
| `manifest.yaml INVÁLIDO — N erro(s)` | Campos não conformes com o schema | Leia a lista de erros e corrija o skeleton |
| `Falha ao parsear YAML` | Sintaxe YAML inválida no manifest gerado | Verifique a template Nunjucks do manifest |
