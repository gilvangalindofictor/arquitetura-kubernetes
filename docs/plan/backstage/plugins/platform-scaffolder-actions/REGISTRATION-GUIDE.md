# REGISTRATION-GUIDE — platform-scaffolder-actions (GAP-S6C-02)

**Sprint S6-C | Backstage 1.48.0 | ADR-104**
**Gerado em:** 2026-03-15

---

## Status

O arquivo `packages/backend/src/index.ts` do workspace Backstage local já está configurado corretamente
(ver `docs/plan/backstage/docker/packages/backend/src/index.ts`).

Este guia documenta o que foi feito e fornece o bloco para aplicar no repositório GitLab
`platform/backstage` após `git clone` em produção (Fase 6 do playbook).

---

## 1. Modificar `packages/backend/src/index.ts`

### Bloco completo para copiar-colar

```typescript
/**
 * Backstage Backend — packages/backend/src/index.ts
 *
 * Registro de todos os plugins usando o new backend system (Backstage 1.34+).
 * Backstage 1.48.0 | ADR-055 | Sprint S6-C
 *
 * GAP-S6C-02: registrado o plugin platform-scaffolder-actions
 *   (custom action platform:manifest:validate para validação de .platform/manifest.yaml)
 */

import { createBackend } from '@backstage/backend-defaults';
import { createBackendModule } from '@backstage/backend-plugin-api';
import { scaffolderActionsExtensionPoint } from '@backstage/plugin-scaffolder-node/alpha';
import { createValidateManifestAction } from '@internal/plugin-platform-scaffolder-actions';

// ---------------------------------------------------------------------------
// Módulo que registra as custom actions da plataforma no Scaffolder
// GAP-S6C-02: necessário para expor a action platform:manifest:validate
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Backend principal
// ---------------------------------------------------------------------------
const backend = createBackend();

// Core
backend.add(import('@backstage/plugin-app-backend'));
backend.add(import('@backstage/plugin-proxy-backend'));

// Auth
backend.add(import('@backstage/plugin-auth-backend'));
backend.add(import('@backstage/plugin-auth-backend-module-guest-provider'));
backend.add(import('@backstage/plugin-auth-backend-module-oidc-provider'));

// Catalog
backend.add(import('@backstage/plugin-catalog-backend'));
backend.add(import('@backstage/plugin-catalog-backend-module-scaffolder-entity-model'));
backend.add(import('@backstage/plugin-catalog-backend-module-unprocessed'));
backend.add(import('@backstage/plugin-catalog-backend-module-gitlab'));
backend.add(import('@backstage-community/plugin-catalog-backend-module-keycloak'));

// Scaffolder — GitLab module + custom platform actions (GAP-S6C-02)
backend.add(import('@backstage/plugin-scaffolder-backend'));
backend.add(import('@backstage/plugin-scaffolder-backend-module-gitlab'));
backend.add(platformScaffolderActionsModule);

// Search
backend.add(import('@backstage/plugin-search-backend'));
backend.add(import('@backstage/plugin-search-backend-module-catalog'));
backend.add(import('@backstage/plugin-search-backend-module-explore'));
backend.add(import('@backstage/plugin-search-backend-module-techdocs'));

// TechDocs
backend.add(import('@backstage/plugin-techdocs-backend'));

// Kubernetes
backend.add(import('@backstage/plugin-kubernetes-backend'));

// Permissions
backend.add(import('@backstage/plugin-permission-backend'));
backend.add(import('@backstage/plugin-permission-backend-module-allow-all-policy'));

// Community plugins
backend.add(import('@backstage-community/plugin-vault-backend'));
backend.add(import('@backstage-community/plugin-sonarqube-backend'));
backend.add(import('@roadiehq/backstage-plugin-argo-cd-backend'));

backend.start();
```

### Pontos críticos

| Ponto | Detalhe |
|-------|---------|
| Import do plugin | `import { createValidateManifestAction } from '@internal/plugin-platform-scaffolder-actions'` — depende da dependência `link:` no package.json |
| Extension point | `scaffolderActionsExtensionPoint` vem de `@backstage/plugin-scaffolder-node/alpha` — pacote já é dependência indireta do `@backstage/plugin-scaffolder-backend` |
| `moduleId` | `'platform-actions'` — deve ser único no pluginId `scaffolder` |
| Posição no arquivo | O módulo deve ser declarado ANTES do bloco `backend.add(...)`. A linha `backend.add(platformScaffolderActionsModule)` deve vir APÓS `backend.add(import('@backstage/plugin-scaffolder-backend'))` |

---

## 2. Adicionar dependência em `packages/backend/package.json`

Na seção `dependencies`, adicionar:

```json
"@internal/plugin-platform-scaffolder-actions": "link:../../plugins/platform-scaffolder-actions"
```

**NOTA:** O path `link:../../plugins/platform-scaffolder-actions` é relativo ao `packages/backend/`.
A estrutura esperada no repositório é:

```
<backstage-repo>/
├── packages/
│   └── backend/
│       ├── package.json          ← adicionar a dependência link: aqui
│       └── src/
│           └── index.ts          ← bloco de registro acima
└── plugins/
    └── platform-scaffolder-actions/
        ├── package.json          ← @internal/plugin-platform-scaffolder-actions
        ├── tsconfig.json
        └── src/
            ├── index.ts
            └── actions/
                └── validateManifest.ts
```

---

## 3. Copiar o plugin para o repositório Backstage

```bash
# Executar após clonar o repositório platform/backstage
PLUGIN_SRC="/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/plan/backstage/plugins/platform-scaffolder-actions"
BACKSTAGE_REPO="/tmp/backstage-app"   # ajustar conforme clone

mkdir -p "${BACKSTAGE_REPO}/plugins"
cp -r "${PLUGIN_SRC}/." "${BACKSTAGE_REPO}/plugins/platform-scaffolder-actions/"
```

---

## 4. Sequência completa de build

```bash
cd /tmp/backstage-app

# 1. Instalar dependências (resolve o link: do plugin)
yarn install

# 2. Build do backend (compila TypeScript + plugin)
yarn workspace @backstage/backend build

# 3. Verificar que o build passou sem erros TypeScript
echo "Build status: $?"

# 4. Build da imagem Docker com tag versionada
NEW_TAG="1.48.0-s6c-$(date +%Y%m%d%H%M)"

docker build \
  -t harbor.staging.internal/platform/backstage:${NEW_TAG} \
  -t harbor.staging.internal/platform/backstage:latest-s6c \
  --build-arg NODE_ENV=production \
  .

# 5. Push para Harbor
docker push harbor.staging.internal/platform/backstage:${NEW_TAG}
docker push harbor.staging.internal/platform/backstage:latest-s6c

echo "Imagem publicada: harbor.staging.internal/platform/backstage:${NEW_TAG}"
```

---

## 5. Validação após deploy

### 5.1 — Verificar action registrada via API do Scaffolder

```bash
# Substituir <TOKEN> por um Bearer token válido (Keycloak client_credentials ou token de usuário)
curl -sk -H "Authorization: Bearer <TOKEN>" \
  https://backstage.staging.internal/api/scaffolder/v2/actions \
  | python3 -m json.tool \
  | grep "platform:manifest:validate"
```

**Saída esperada:**
```json
"id": "platform:manifest:validate",
```

### 5.2 — Verificar detalhes da action

```bash
curl -sk -H "Authorization: Bearer <TOKEN>" \
  https://backstage.staging.internal/api/scaffolder/v2/actions \
  | python3 -c "
import sys, json
actions = json.load(sys.stdin)
for a in actions:
    if 'platform' in a.get('id', ''):
        print(json.dumps(a, indent=2))
"
```

**Saída esperada:**
```json
{
  "id": "platform:manifest:validate",
  "description": "Validates .platform/manifest.yaml against the platform JSON Schema (ADR-104, GAP-003)",
  "schema": {
    "input": { ... },
    "output": { ... }
  }
}
```

### 5.3 — Verificar logs do backend ao iniciar

```bash
kubectl logs -n staging-platform-backstage \
  $(kubectl get pod -n staging-platform-backstage -l app.kubernetes.io/name=backstage \
    -o jsonpath='{.items[0].metadata.name}') \
  --container backstage \
  | grep -i "platform-actions\|scaffolder\|platform:manifest"
```

**Saída esperada (sem erros):** Linha indicando que o módulo `platform-actions` foi inicializado.

---

## 6. ATENCAO — Diferenca de path link: entre local e build Docker

### Contexto (NC-07 — AUDIT-F3)

O `packages/backend/package.json` no diretório de trabalho local (`docker/packages/backend/`) declara:

```json
"@internal/plugin-platform-scaffolder-actions": "link:../../../plugins/platform-scaffolder-actions"
```

Este path relativo (`../../../`) e valido **somente** quando o `package.json` esta em
`docs/plan/backstage/docker/packages/backend/`, pois sobe tres niveis e chega em
`docs/plan/backstage/plugins/platform-scaffolder-actions/`.

### Problema no build Docker

Dentro do container, a estrutura copiada pelo Dockerfile normalmente e:

```text
/app/
├── packages/
│   └── backend/
│       └── package.json   ← ponto de partida do link:
└── plugins/
    └── platform-scaffolder-actions/
```

Neste caso, o path correto seria `link:../../plugins/platform-scaffolder-actions`
(apenas dois niveis acima, nao tres).

### Correcao obrigatoria no Dockerfile

No `RUN` step de build, apos copiar os arquivos, ajustar o path via `sed` antes do `yarn install`:

```dockerfile
# Ajustar path link: para estrutura interna do container
RUN sed -i 's|link:../../../plugins/platform-scaffolder-actions|link:../../plugins/platform-scaffolder-actions|g' \
    packages/backend/package.json
RUN yarn install --frozen-lockfile
```

Alternativamente, manter dois `package.json` distintos: um para desenvolvimento local
e outro para o build Docker, copiando o correto no Dockerfile com `COPY`.

### Resumo de paths

| Contexto | Diretorio do package.json | Path correto para link: |
| -------- | ------------------------- | ----------------------- |
| Local (dev) | `docs/plan/backstage/docker/packages/backend/` | `link:../../../plugins/platform-scaffolder-actions` |
| Docker (container) | `/app/packages/backend/` | `link:../../plugins/platform-scaffolder-actions` |

> **IMPORTANTE**: Ignorar esta diferenca causa falha silenciosa no `yarn install`
> dentro do container — o link nao e resolvido e o backend sobe sem o plugin,
> gerando erro `Cannot find module '@internal/plugin-platform-scaffolder-actions'` em runtime.

---

## 6.3 — Instrucao para ajuste via sed no Dockerfile

Adicionar no `Dockerfile`, imediatamente antes do `RUN yarn install`:

```dockerfile
RUN sed -i \
  's|"@internal/plugin-platform-scaffolder-actions": "link:../../../plugins|"@internal/plugin-platform-scaffolder-actions": "link:../../plugins|g' \
  packages/backend/package.json
```

---

## 7. Variável de ambiente obrigatória no container

O plugin carrega o JSON Schema em runtime. O path padrão aponta para o workspace local
(desenvolvimento). Em produção, é obrigatório definir:

```bash
PLATFORM_SCHEMA_PATH=/app/schemas/v1/manifest-schema.json
```

Esta variável já está configurada no `helm-values-staging.yaml`:

```yaml
backstage:
  extraEnvVars:
    - name: PLATFORM_SCHEMA_PATH
      value: /app/schemas/v1/manifest-schema.json
```

O ConfigMap `platform-manifest-schema` (criado na Fase 2 do playbook) monta o schema neste path.

---

## 7. Troubleshooting

| Erro | Causa provável | Solução |
|------|---------------|---------|
| `Action not found: platform:manifest:validate` | Plugin não registrado ou build não incluiu o plugin | Verificar se `backend.add(platformScaffolderActionsModule)` está no `index.ts` e rebuild |
| `Cannot find module '@internal/plugin-platform-scaffolder-actions'` | Link `yarn workspaces` não resolvido | Rodar `yarn install` na raiz do monorepo |
| `JSON Schema da plataforma não encontrado` | `PLATFORM_SCHEMA_PATH` não configurada ou ConfigMap não montado | Verificar `kubectl describe pod` — seção Mounts — e o ConfigMap `platform-manifest-schema` |
| `Cannot read property 'addActions' of undefined` | Versão do `@backstage/plugin-scaffolder-node` incompatível | Verificar que `@backstage/plugin-scaffolder-node >= 0.7.1` está instalado |
| `Module 'scaffolder' already registered platform-actions` | `platformScaffolderActionsModule` registrado duas vezes | Remover duplicata no `index.ts` |

---

*GAP-S6C-02 | Sprint S6-C | ADR-104 | 2026-03-15*
