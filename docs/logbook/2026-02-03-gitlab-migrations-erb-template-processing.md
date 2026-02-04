# GitLab Migrations - Processamento de Templates ERB

**Data:** 2026-02-03  
**Autor:** Claude Code (Sonnet 4.5)  
**Namespace:** gitlab-staging  
**Status:** ✅ RESOLVIDO

## Problema Identificado

O Job `gitlab-migrations-manual` estava falhando ao executar migrations do GitLab com erro:

```
connection to server at "127.0.0.1", port 5432 failed: Connection refused
```

### Análise do Problema

1. **ConfigMap correto**: O ConfigMap `gitlab-migrations` tinha o template `database.yml.erb` com as configurações corretas do PostgreSQL externo.

2. **Template não processado**: O arquivo template em `/var/opt/gitlab/templates/database.yml.erb` NÃO estava sendo renderizado para `/srv/gitlab/config/database.yml`.

3. **Job executando comando direto**: O Job estava chamando `/scripts/db-migrate` DIRETAMENTE, pulando o entrypoint padrão da imagem que processa templates ERB.

4. **Resultado**: O arquivo `/srv/gitlab/config/database.yml` permanecia com valores padrão (localhost) ao invés de usar o PostgreSQL externo.

## Investigação Técnica

### Como o GitLab processa templates ERB

A imagem `gitlab-toolbox-ce` tem um processo de inicialização em `/scripts/entrypoint.sh` que:

1. Chama `/scripts/set-config` com as variáveis de ambiente:
   - `CONFIG_TEMPLATE_DIRECTORY` (templates .erb)
   - `CONFIG_DIRECTORY` (arquivos finais)

2. O script `set-config` processa todos os `.erb` files usando Ruby ERB:
   ```bash
   erb -U -r yaml -r json -r fileutils "$template" > "$output_file"
   ```

3. Depois executa o comando principal (ex: `/scripts/db-migrate`)

### Problema no ConfigMap

Além do Job não processar templates, o ConfigMap `gitlab-migrations` tinha um erro de sintaxe:

```yaml
database.yml.erb: |
  "\nproduction:\n  main:\n...  # ❌ Aspas extras causando YAML inválido
```

Deveria ser:

```yaml
database.yml.erb: |
  production:
    main:  # ✅ YAML válido
```

## Solução Implementada

### 1. Corrigir o ConfigMap

```bash
kubectl patch configmap gitlab-migrations -n gitlab-staging --patch-file database-yml-patch.yaml
```

**Arquivo:** `/tmp/database-yml-patch.yaml`
- Removeu aspas extras do início e fim do template
- Manteve configurações corretas do PostgreSQL externo:
  - host: "postgresql-external"
  - database: gitlab_staging
  - username: gitlab_user
  - password: (lida do Secret)

### 2. Modificar o Job para processar templates

Criado novo Job que:

1. **Init Containers** (mantidos):
   - `certificates`: Configura certificados SSL
   - `configure`: Copia secrets para volume compartilhado

2. **Main Container** (MODIFICADO):
   ```yaml
   command: ["/bin/bash", "-c"]
   args:
   - |
     set -e
     echo "Processing ERB templates..."
     /scripts/set-config "${CONFIG_TEMPLATE_DIRECTORY}" "${CONFIG_DIRECTORY}"
     echo "Templates processed successfully!"
     echo "Verifying database.yml..."
     head -20 /srv/gitlab/config/database.yml
     echo "Running migrations..."
     /scripts/db-migrate
   ```

**Arquivo criado:** `/tmp/gitlab-migrations-fixed.yaml`

### 3. Executar migrations

```bash
# Deletar Job antigo
kubectl delete job gitlab-migrations-manual -n gitlab-staging

# Aplicar Job corrigido
kubectl apply -f /tmp/gitlab-migrations-fixed.yaml

# Acompanhar logs
kubectl logs -f gitlab-migrations-manual-<pod> -n gitlab-staging
```

### 4. Reiniciar pods dependentes

Após migrations completas:

```bash
kubectl rollout restart deployment gitlab-webservice-default -n gitlab-staging
kubectl rollout restart deployment gitlab-sidekiq-all-in-1-v2 -n gitlab-staging
```

## Resultado

### Migrations executadas com sucesso

```
✅ Processing ERB templates...
✅ Writing /srv/gitlab/config/database.yml
✅ Templates processed successfully!
✅ Running db:schema:load rake task
✅ Seed from /srv/gitlab/db/fixtures/production/001_application_settings.rb
✅ Administrator account created
✅ Job Status: Complete (1/1)
```

### Pods funcionando

```
NAME                                    READY   STATUS      RESTARTS   AGE
gitlab-migrations-manual-srjdk          0/1     Completed   0          6m
gitlab-webservice-default-5c955fbcb8    2/2     Running     0          2m
gitlab-webservice-default-864cbf5cb5    2/2     Running     0          28m
gitlab-sidekiq-all-in-1-v2-5cffc6d468   1/1     Running     0          28m
```

## Lições Aprendidas

1. **Templates ERB precisam ser processados**: Jobs que usam imagens GitLab DEVEM processar templates `.erb` antes de executar comandos principais.

2. **Não pular o entrypoint**: Quando uma imagem tem processamento no entrypoint, use-o ou reimplemente sua lógica.

3. **YAML em ConfigMaps**: Cuidado com aspas e escaping ao criar templates em ConfigMaps. Use block scalar (`|`) para templates multilinhas.

4. **Ordem de execução**: Migrations devem completar ANTES de iniciar webservice/sidekiq.

## Arquivos Criados

- `/tmp/database-yml-patch.yaml` - Patch do ConfigMap
- `/tmp/gitlab-migrations-fixed.yaml` - Manifest do Job corrigido

## Referências

- Script de processamento: `/scripts/set-config` (imagem gitlab-toolbox-ce)
- Entrypoint: `/scripts/entrypoint.sh`
- GitLab Helm Chart Troubleshooting: https://docs.gitlab.com/charts/troubleshooting/
