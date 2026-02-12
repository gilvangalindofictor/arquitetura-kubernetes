# docs/vendor — trechos oficiais pinados por fornecedor

Uso: adicionar arquivos `docs/vendor/<tool>.md` com trechos relevantes da documentação oficial pinada por versão.

Padrão de conteúdo por arquivo `docs/vendor/<tool>.md`:

- Header com `version: x.y.z` e `source: <official url>`
- Trechos de configuração/flags/manifestos críticos
- Comandos de referência com a versão comentada
- Notas de breaking changes (se conhecido)

Exemplos de arquivos recomendados:
- `docs/vendor/terraform.md`
- `docs/vendor/aws.md`
- `docs/vendor/kubernetes.md`
- `docs/vendor/helm.md`
- `docs/vendor/keycloak.md`

Processo: PR de bump de versão deve atualizar o arquivo correspondente e `ai-contexts/official-docs.md`.
