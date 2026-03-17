# manifest-schema — nota de importação

NÃO copie o JSON Schema aqui. A única source-of-truth é:

  domains/platform-core/app-provisioning/schemas/v1/manifest-schema.json

O arquivo `validateManifest.ts` carrega o schema em runtime via `fs.readFileSync`
usando o path resolvido pela constante `SCHEMA_PATH`.

Em produção (container), monte o schema via ConfigMap ou copie-o no Dockerfile para:
  /app/schemas/v1/manifest-schema.json

e configure:
  PLATFORM_SCHEMA_PATH=/app/schemas/v1/manifest-schema.json

Referências: ADR-104, GAP-003, Sprint S6-C.
