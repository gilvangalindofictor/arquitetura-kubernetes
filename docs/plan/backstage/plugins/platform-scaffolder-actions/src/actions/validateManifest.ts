/**
 * platform:manifest:validate
 *
 * Custom Scaffolder action — valida o .platform/manifest.yaml gerado pelo template
 * contra o JSON Schema da plataforma (ADR-104, GAP-003).
 *
 * Compatível com Backstage 1.48.0 (new backend system — backend.add() API).
 * Sprint S6-C — platform-scaffolder-actions plugin.
 */

import { createTemplateAction } from '@backstage/plugin-scaffolder-node';
import Ajv2020, { type ErrorObject } from 'ajv/dist/2020';
import addFormats from 'ajv-formats';
import * as fs from 'fs';
import * as path from 'path';
import * as yaml from 'js-yaml';

// O schema é carregado em tempo de execução a partir do path canônico no repositório.
// Isso evita duplicação e mantém a única source-of-truth em:
//   domains/platform-core/app-provisioning/schemas/v1/manifest-schema.json
//
// O path abaixo é resolvido em relação à raiz do workspace do Backstage (process.cwd()).
// Em produção, garanta que o arquivo esteja disponível no container sob:
//   /app/schemas/v1/manifest-schema.json  (montado via ConfigMap ou copiado no Dockerfile)
// Ajuste SCHEMA_PATH via variável de ambiente PLATFORM_SCHEMA_PATH se necessário.
const SCHEMA_PATH =
  process.env.PLATFORM_SCHEMA_PATH ??
  path.resolve(
    __dirname,
    '../../../../../../domains/platform-core/app-provisioning/schemas/v1/manifest-schema.json',
  );

const DEFAULT_MANIFEST_RELATIVE_PATH = '.platform/manifest.yaml';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Formata erros do Ajv em mensagem legível para o operador.
 */
function formatAjvErrors(errors: ErrorObject[]): string {
  return errors
    .map(err => {
      const field = err.instancePath || '(root)';
      return `  • Campo "${field}": ${err.message ?? 'erro desconhecido'} (keyword: ${err.keyword})`;
    })
    .join('\n');
}

// ---------------------------------------------------------------------------
// Action factory
// ---------------------------------------------------------------------------

/**
 * Cria a custom action `platform:manifest:validate`.
 *
 * Uso no template YAML:
 * ```yaml
 * - id: validate-manifest
 *   name: "Validar manifest.yaml"
 *   action: platform:manifest:validate
 *   input:
 *     manifestPath: .platform/manifest.yaml   # opcional — este é o default
 * ```
 */
export const createValidateManifestAction = () => {
  return createTemplateAction<{
    manifestPath?: string;
  }>({
    id: 'platform:manifest:validate',
    description:
      'Validates .platform/manifest.yaml against the platform JSON Schema (ADR-104, GAP-003)',

    schema: {
      input: {
        type: 'object',
        properties: {
          manifestPath: {
            type: 'string',
            title: 'Manifest path',
            description: `Caminho relativo ao workspace do arquivo manifest a validar. Default: "${DEFAULT_MANIFEST_RELATIVE_PATH}"`,
          },
        },
      },
      output: {
        type: 'object',
        properties: {
          valid: {
            type: 'boolean',
            description: 'true se o manifest passou na validação do schema',
          },
          appName: {
            type: 'string',
            description: 'metadata.name extraído do manifest',
          },
          domain: {
            type: 'string',
            description: 'metadata.domain extraído do manifest',
          },
          type: {
            type: 'string',
            description: 'metadata.type extraído do manifest',
          },
        },
      },
    },

    async handler(ctx) {
      const { manifestPath: inputPath } = ctx.input;
      const relativeManifestPath = inputPath ?? DEFAULT_MANIFEST_RELATIVE_PATH;

      // ------------------------------------------------------------------
      // 1. Resolver o path absoluto do manifest no workspace do Scaffolder
      // ------------------------------------------------------------------
      const workspaceDir = ctx.workspacePath;
      const absoluteManifestPath = path.resolve(workspaceDir, relativeManifestPath);

      ctx.logger.info(
        `platform:manifest:validate — lendo manifest em: ${absoluteManifestPath}`,
      );

      // ------------------------------------------------------------------
      // 2. Ler o arquivo manifest
      // ------------------------------------------------------------------
      if (!fs.existsSync(absoluteManifestPath)) {
        throw new Error(
          `Manifest não encontrado: "${relativeManifestPath}" (path absoluto: ${absoluteManifestPath}).\n` +
            `Verifique se o step fetch:template gerou o arquivo .platform/manifest.yaml corretamente.`,
        );
      }

      const rawYaml = fs.readFileSync(absoluteManifestPath, 'utf-8');

      // ------------------------------------------------------------------
      // 3. Parsear YAML → objeto JS
      // ------------------------------------------------------------------
      let manifest: unknown;
      try {
        manifest = yaml.load(rawYaml);
      } catch (parseError: unknown) {
        const msg = parseError instanceof Error ? parseError.message : String(parseError);
        throw new Error(
          `Falha ao parsear YAML do manifest "${relativeManifestPath}":\n${msg}`,
        );
      }

      if (typeof manifest !== 'object' || manifest === null) {
        throw new Error(
          `O manifest "${relativeManifestPath}" não é um objeto YAML válido (valor: ${JSON.stringify(manifest)}).`,
        );
      }

      // ------------------------------------------------------------------
      // 4. Carregar o JSON Schema da plataforma
      // ------------------------------------------------------------------
      if (!fs.existsSync(SCHEMA_PATH)) {
        throw new Error(
          `JSON Schema da plataforma não encontrado em: "${SCHEMA_PATH}".\n` +
            `Configure a variável de ambiente PLATFORM_SCHEMA_PATH apontando para o schema correto.`,
        );
      }

      let platformSchema: object;
      try {
        const rawSchema = fs.readFileSync(SCHEMA_PATH, 'utf-8');
        platformSchema = JSON.parse(rawSchema);
      } catch (schemaError: unknown) {
        const msg = schemaError instanceof Error ? schemaError.message : String(schemaError);
        throw new Error(`Falha ao carregar JSON Schema da plataforma:\n${msg}`);
      }

      // ------------------------------------------------------------------
      // 5. Validar com Ajv (draft-2020-12 + formatos)
      // ------------------------------------------------------------------
      const ajv = new Ajv2020({
        strict: false,        // permite $defs e keywords extras do draft-2020-12
        allErrors: true,      // coleta TODOS os erros, não apenas o primeiro
        verbose: true,        // inclui instancePath completo nas mensagens
      });
      addFormats(ajv);        // adiciona suporte a format: "hostname", "uri", etc.

      const validate = ajv.compile(platformSchema);
      const isValid = validate(manifest);

      // ------------------------------------------------------------------
      // 6. Tratar resultado
      // ------------------------------------------------------------------
      if (!isValid && validate.errors && validate.errors.length > 0) {
        const errorSummary = formatAjvErrors(validate.errors);
        throw new Error(
          `manifest.yaml INVÁLIDO — ${validate.errors.length} erro(s) encontrado(s):\n\n` +
            `${errorSummary}\n\n` +
            `Corrija os campos acima e execute o template novamente.`,
        );
      }

      // ------------------------------------------------------------------
      // 7. Extrair campos de saída do manifest validado
      // ------------------------------------------------------------------
      const manifestObj = manifest as Record<string, unknown>;
      const metadata = (manifestObj.metadata ?? {}) as Record<string, unknown>;

      const appName = typeof metadata.name === 'string' ? metadata.name : '';
      const domain = typeof metadata.domain === 'string' ? metadata.domain : '';
      const type = typeof metadata.type === 'string' ? metadata.type : '';

      ctx.logger.info(
        `manifest.yaml valido -- app="${appName}" domain="${domain}" type="${type}"`,
      );

      // ------------------------------------------------------------------
      // 8. Publicar outputs para steps subsequentes do template
      // ------------------------------------------------------------------
      ctx.output('valid', true);
      ctx.output('appName', appName);
      ctx.output('domain', domain);
      ctx.output('type', type);
    },
  });
};
