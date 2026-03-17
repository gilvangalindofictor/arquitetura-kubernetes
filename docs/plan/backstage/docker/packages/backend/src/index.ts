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
