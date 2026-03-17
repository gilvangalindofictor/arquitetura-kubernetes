/**
 * Unit tests — platform:manifest:validate action
 *
 * Sprint S6-C | GAP-S6C-02 | ADR-104
 *
 * Cobre:
 *  1. Happy path: manifest válido → action passa sem erro
 *  2. Error path: manifest inválido (schema violation) → erro com detalhes dos campos
 *  3. Error path: schema não encontrado → erro específico de PLATFORM_SCHEMA_PATH
 *  4. Edge case: manifest vazio → erro "não é um objeto YAML válido"
 *  5. Edge case: arquivo manifest ausente → erro "Manifest não encontrado"
 */

import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

// ---------------------------------------------------------------------------
// Helpers — scaffold a minimal createTemplateAction context
// ---------------------------------------------------------------------------

/**
 * Cria um ctx mínimo compatível com a assinatura esperada pelo handler da action.
 * Não depende do runtime real do Backstage — apenas simula a interface necessária.
 */
function makeCtx(
  workspaceDir: string,
  input: Record<string, string | undefined> = {},
) {
  const outputs: Record<string, unknown> = {};
  const logs: string[] = [];

  return {
    input,
    workspacePath: workspaceDir,
    logger: {
      info: (msg: string) => logs.push(msg),
      warn: (msg: string) => logs.push(`WARN: ${msg}`),
      error: (msg: string) => logs.push(`ERROR: ${msg}`),
    },
    output: (key: string, value: unknown) => {
      outputs[key] = value;
    },
    // Expõe internals para asserções nos testes
    _outputs: outputs,
    _logs: logs,
  };
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/** Schema JSON mínimo que valida o manifest de teste (draft-2020-12). */
const VALID_SCHEMA = JSON.stringify({
  $schema: 'https://json-schema.org/draft/2020-12/schema',
  type: 'object',
  required: ['apiVersion', 'kind', 'metadata'],
  properties: {
    apiVersion: { type: 'string' },
    kind: { type: 'string', enum: ['Service', 'ETL', 'API'] },
    metadata: {
      type: 'object',
      required: ['name', 'domain', 'type'],
      properties: {
        name: { type: 'string', pattern: '^[a-z][a-z0-9-]{2,62}$' },
        domain: { type: 'string', enum: ['platform', 'data', 'integration', 'operations', 'shared-services'] },
        type: { type: 'string', enum: ['api', 'worker', 'etl', 'frontend', 'library'] },
      },
    },
  },
});

/** Manifest YAML mínimo válido conforme VALID_SCHEMA. */
const VALID_MANIFEST_YAML = `
apiVersion: platform.internal/v1
kind: Service
metadata:
  name: hatch-etl-core
  domain: data
  type: etl
`;

/** Manifest YAML inválido: campo 'kind' fora do enum permitido. */
const INVALID_KIND_MANIFEST_YAML = `
apiVersion: platform.internal/v1
kind: InvalidKind
metadata:
  name: hatch-etl-core
  domain: data
  type: etl
`;

/** Manifest YAML inválido: campo obrigatório 'domain' ausente em metadata. */
const MISSING_DOMAIN_MANIFEST_YAML = `
apiVersion: platform.internal/v1
kind: Service
metadata:
  name: hatch-etl-core
  type: etl
`;

// ---------------------------------------------------------------------------
// Extrai o handler diretamente da factory — sem precisar do Backstage runtime
// ---------------------------------------------------------------------------

/**
 * Executa o handler da action isoladamente em um workspace temporário.
 *
 * @param manifestYaml - Conteúdo YAML a ser escrito em .platform/manifest.yaml
 * @param schemaContent - Conteúdo JSON do schema (null = não criar schema)
 * @param manifestPath - Path relativo a usar como input (default: .platform/manifest.yaml)
 */
async function runAction(opts: {
  manifestYaml: string | null;
  schemaContent: string | null;
  manifestPath?: string;
}): Promise<ReturnType<typeof makeCtx>> {
  const { manifestYaml, schemaContent, manifestPath } = opts;

  // 1. Criar workspace temporário
  const workspaceDir = fs.mkdtempSync(path.join(os.tmpdir(), 'backstage-test-'));

  // 2. Criar .platform/manifest.yaml (se fornecido)
  if (manifestYaml !== null) {
    const platformDir = path.join(workspaceDir, '.platform');
    fs.mkdirSync(platformDir, { recursive: true });
    const targetPath = manifestPath ?? '.platform/manifest.yaml';
    fs.writeFileSync(path.join(workspaceDir, targetPath), manifestYaml, 'utf-8');
  }

  // 3. Criar schema temporário (ou apontar para inexistente)
  let schemaPath: string;
  if (schemaContent !== null) {
    schemaPath = path.join(workspaceDir, 'manifest-schema.json');
    fs.writeFileSync(schemaPath, schemaContent, 'utf-8');
  } else {
    schemaPath = path.join(workspaceDir, 'nonexistent-schema.json');
  }

  // 4. Sobrescrever PLATFORM_SCHEMA_PATH para apontar para o schema do teste
  const originalSchemaPath = process.env.PLATFORM_SCHEMA_PATH;
  process.env.PLATFORM_SCHEMA_PATH = schemaPath;

  // 5. Re-importar o módulo com cache limpo para pegar o novo PLATFORM_SCHEMA_PATH
  //    Como SCHEMA_PATH é resolvido no topo do módulo (fora do handler), precisamos
  //    usar jest.resetModules() + require() dinâmico para cada variação de schema.
  //    Como não temos esse controle aqui, usamos a variável de ambiente e avaliamos
  //    o comportamento via re-execução do handler diretamente.
  //
  //    NOTA: Para testes de integração reais, usar jest.resetModules().
  //    Aqui testamos o handler de forma isolada via importação direta.

  // Importação dinâmica limpa (isolada por Jest module isolation)
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { createValidateManifestAction } = require('./validateManifest');
  const action = createValidateManifestAction();

  const ctx = makeCtx(workspaceDir, { manifestPath });

  try {
    await action.handler(ctx);
  } finally {
    // Restaurar variável de ambiente
    if (originalSchemaPath !== undefined) {
      process.env.PLATFORM_SCHEMA_PATH = originalSchemaPath;
    } else {
      delete process.env.PLATFORM_SCHEMA_PATH;
    }

    // Limpar workspace temporário
    fs.rmSync(workspaceDir, { recursive: true, force: true });
  }

  return ctx;
}

// ---------------------------------------------------------------------------
// Testes
// ---------------------------------------------------------------------------

describe('platform:manifest:validate action', () => {
  beforeEach(() => {
    // Limpar cache de módulo para isolar a PLATFORM_SCHEMA_PATH entre testes
    jest.resetModules();
  });

  // -------------------------------------------------------------------------
  // 1. Happy path — manifest válido
  // -------------------------------------------------------------------------
  describe('happy path — manifest válido', () => {
    it('deve passar sem erro quando o manifest é válido', async () => {
      const ctx = await runAction({
        manifestYaml: VALID_MANIFEST_YAML,
        schemaContent: VALID_SCHEMA,
      });

      // Verificar outputs
      expect(ctx._outputs['valid']).toBe(true);
      expect(ctx._outputs['appName']).toBe('hatch-etl-core');
      expect(ctx._outputs['domain']).toBe('data');
      expect(ctx._outputs['type']).toBe('etl');
    });

    it('deve logar mensagem de sucesso com nome do app', async () => {
      const ctx = await runAction({
        manifestYaml: VALID_MANIFEST_YAML,
        schemaContent: VALID_SCHEMA,
      });

      const successLog = ctx._logs.find(l =>
        l.includes('valido') && l.includes('hatch-etl-core'),
      );
      expect(successLog).toBeDefined();
    });

    it('deve aceitar manifestPath customizado como input', async () => {
      // Criar o manifest em path customizado dentro de .platform/
      const customPath = '.platform/custom-manifest.yaml';

      // runAction escreve o YAML no path customizado quando manifestPath é definido
      const ctx = await runAction({
        manifestYaml: VALID_MANIFEST_YAML,
        schemaContent: VALID_SCHEMA,
        manifestPath: customPath,
      });

      expect(ctx._outputs['valid']).toBe(true);
    });
  });

  // -------------------------------------------------------------------------
  // 2. Error path — manifest inválido (schema violation)
  // -------------------------------------------------------------------------
  describe('error path — manifest inválido', () => {
    it('deve lançar erro descritivo quando "kind" viola o enum do schema', async () => {
      await expect(
        runAction({
          manifestYaml: INVALID_KIND_MANIFEST_YAML,
          schemaContent: VALID_SCHEMA,
        }),
      ).rejects.toThrow(/manifest\.yaml INVÁLIDO/);
    });

    it('deve incluir o nome do campo inválido no erro', async () => {
      await expect(
        runAction({
          manifestYaml: INVALID_KIND_MANIFEST_YAML,
          schemaContent: VALID_SCHEMA,
        }),
      ).rejects.toThrow(/Campo ".+"/);
    });

    it('deve incluir a contagem de erros no erro', async () => {
      await expect(
        runAction({
          manifestYaml: INVALID_KIND_MANIFEST_YAML,
          schemaContent: VALID_SCHEMA,
        }),
      ).rejects.toThrow(/\d+ erro\(s\) encontrado\(s\)/);
    });

    it('deve lançar erro quando campo obrigatório "domain" está ausente em metadata', async () => {
      await expect(
        runAction({
          manifestYaml: MISSING_DOMAIN_MANIFEST_YAML,
          schemaContent: VALID_SCHEMA,
        }),
      ).rejects.toThrow(/manifest\.yaml INVÁLIDO/);
    });

    it('deve reportar múltiplos erros quando o manifest tem várias violações', async () => {
      const multipleViolationsYaml = `
apiVersion: platform.internal/v1
kind: InvalidKind
metadata:
  name: "NOME_INVALIDO_MAIUSCULO"
  domain: "dominio-inexistente"
  type: etl
`;

      let caughtError: Error | undefined;
      try {
        await runAction({
          manifestYaml: multipleViolationsYaml,
          schemaContent: VALID_SCHEMA,
        });
      } catch (err) {
        caughtError = err as Error;
      }

      expect(caughtError).toBeDefined();
      expect(caughtError!.message).toMatch(/manifest\.yaml INVÁLIDO/);
      // Deve listar mais de um erro (kind + name + domain violam o schema)
      const match = caughtError!.message.match(/(\d+) erro\(s\)/);
      expect(match).not.toBeNull();
      const errorCount = parseInt(match![1], 10);
      expect(errorCount).toBeGreaterThanOrEqual(2);
    });
  });

  // -------------------------------------------------------------------------
  // 3. Error path — schema não encontrado
  // -------------------------------------------------------------------------
  describe('error path — schema não encontrado', () => {
    it('deve lançar erro específico quando o JSON Schema não existe no path configurado', async () => {
      await expect(
        runAction({
          manifestYaml: VALID_MANIFEST_YAML,
          schemaContent: null,   // não cria o arquivo de schema
        }),
      ).rejects.toThrow(/JSON Schema da plataforma não encontrado/);
    });

    it('deve mencionar PLATFORM_SCHEMA_PATH na mensagem de erro do schema ausente', async () => {
      await expect(
        runAction({
          manifestYaml: VALID_MANIFEST_YAML,
          schemaContent: null,
        }),
      ).rejects.toThrow(/PLATFORM_SCHEMA_PATH/);
    });
  });

  // -------------------------------------------------------------------------
  // 4. Edge case — manifest vazio
  // -------------------------------------------------------------------------
  describe('edge case — manifest vazio', () => {
    it('deve lançar erro "não é um objeto YAML válido" para YAML vazio (null)', async () => {
      const emptyYaml = '';   // yaml.load('') retorna undefined → null check falha

      await expect(
        runAction({
          manifestYaml: emptyYaml,
          schemaContent: VALID_SCHEMA,
        }),
      ).rejects.toThrow(/não é um objeto YAML válido/);
    });

    it('deve lançar erro "não é um objeto YAML válido" para YAML com apenas comentários', async () => {
      const commentOnlyYaml = '# apenas um comentário\n';

      await expect(
        runAction({
          manifestYaml: commentOnlyYaml,
          schemaContent: VALID_SCHEMA,
        }),
      ).rejects.toThrow(/não é um objeto YAML válido/);
    });

    it('deve lançar erro "não é um objeto YAML válido" para YAML escalar (string pura)', async () => {
      const scalarYaml = 'apenas-uma-string-nao-um-objeto\n';

      await expect(
        runAction({
          manifestYaml: scalarYaml,
          schemaContent: VALID_SCHEMA,
        }),
      ).rejects.toThrow(/não é um objeto YAML válido/);
    });
  });

  // -------------------------------------------------------------------------
  // 5. Edge case — arquivo manifest ausente no workspace
  // -------------------------------------------------------------------------
  describe('edge case — arquivo manifest ausente', () => {
    it('deve lançar erro "Manifest não encontrado" quando o arquivo não existe', async () => {
      await expect(
        runAction({
          manifestYaml: null,   // não cria o arquivo
          schemaContent: VALID_SCHEMA,
        }),
      ).rejects.toThrow(/Manifest não encontrado/);
    });

    it('deve incluir o path do manifest na mensagem de erro de arquivo ausente', async () => {
      await expect(
        runAction({
          manifestYaml: null,
          schemaContent: VALID_SCHEMA,
        }),
      ).rejects.toThrow(/\.platform\/manifest\.yaml/);
    });
  });
});
