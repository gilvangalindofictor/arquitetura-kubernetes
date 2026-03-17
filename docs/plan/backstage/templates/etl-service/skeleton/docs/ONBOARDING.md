# Onboarding: ${{ values.name }}

Guia pós-scaffold para configurar e fazer o primeiro deploy do ETL `${{ values.name }}` no EKS staging.

## Pré-requisitos

- [ ] Acesso ao Vault (`vault.staging.internal`) com permissão de escrita em `secret/staging/${{ values.name }}/*`
- [ ] Variáveis CI/CD configuradas no GitLab (ver `docs/CI-CD-VARIABLES.md`)
- [ ] `kubectl` configurado para o cluster EKS staging
- [ ] Branch `staging` criada no repositório

---

## Passo 1 — Configurar credenciais das Originadoras no Vault

**Obrigatório antes do primeiro push para `staging`.**

Para cada originadora declarada no template, você precisa inserir as credenciais reais no Vault. O pipeline CI **não cria** essas credenciais automaticamente — elas devem ser inseridas manualmente.

### Originadoras configuradas neste serviço:
{%- if values.originadoras and (values.originadoras | length) > 0 %}
{%- for orig in values.originadoras %}
**`{{ orig.codigo }}`** — {{ orig.nome }} (`{{ orig.authType }}`)

```bash
vault kv put secret/staging/${{ values.name }}/{{ orig.secretKeyRef | default(orig.codigo) }} \
  username="SEU_USUARIO_{{ orig.codigo | upper }}" \
  password="SUA_SENHA_{{ orig.codigo | upper }}"
```

{%- endfor %}
{%- else %}
Nenhuma originadora configurada neste serviço.
{%- endif %}

### APIs Externas configuradas:
{%- if values.externalAPIs and (values.externalAPIs | length) > 0 %}
{%- for api in values.externalAPIs %}
{%- if api.secretKeyRef %}
**`{{ api.name }}`** — `{{ api.authType }}`

```bash
vault kv put secret/staging/${{ values.name }}/{{ api.secretKeyRef }} \
  # Insira as credenciais específicas desta API
  api_key="SUA_API_KEY"  # ou client_id/client_secret para OAuth2
```

{%- endif %}
{%- endfor %}
{%- else %}
Nenhuma API externa com credenciais configurada.
{%- endif %}

---

## Passo 2 — Verificar ExternalSecret após primeiro deploy

Após o primeiro push para `staging` e execução do stage `provision`:

```bash
# Verificar status do ExternalSecret
kubectl get externalsecret ${{ values.name }}-secrets -n staging-data-${{ values.name }}

# Output esperado:
# NAME                         STORE           REFRESH INTERVAL   STATUS   READY
# ${{ values.name }}-secrets   vault-backend   1h                 SecretSynced   True

# Verificar Secret K8s criado
kubectl get secret ${{ values.name }}-secrets -n staging-data-${{ values.name }} -o jsonpath='{.data}' | jq 'keys'
```

Se o status for `SecretSyncedError`, verifique:
1. O path Vault existe: `vault kv get secret/staging/${{ values.name }}/{secretKeyRef}`
2. A policy tem acesso: `vault policy read ${{ values.name }}-policy`

---

## Passo 3 — Fluxo de Deploy

```
developer
    │
    ▼
git push origin staging
    │
    ▼
GitLab Pipeline (automático)
    ├── validate    ← Valida .platform/manifest.yaml
    ├── test        ← pytest tests/unit/
    ├── build       ← Docker build + push para Harbor
    ├── provision   ← Cria namespace, Vault paths, ExternalSecret
    ├── migrate     ← Migrações de banco (se aplicável)
    └── deploy      ← helm upgrade → staging-data-${{ values.name }}
    │
    ▼
ArgoCD (opcional, se Application criada)
    └── Sync automático após deploy
    │
    ▼
Serviço disponível em:
    https://${{ values.name }}.staging.internal
```

---

## Passo 4 — Verificar saúde do deploy

```bash
# Pods em execução
kubectl get pods -n staging-data-${{ values.name }}

# Logs do serviço
kubectl logs -l app=${{ values.name }} -n staging-data-${{ values.name }} --tail=50

# Health check
curl -s https://${{ values.name }}.staging.internal/healthz

# Métricas Prometheus
curl -s https://${{ values.name }}.staging.internal:9090/metrics | head -20
```

---

## Passo 5 — Configurar observabilidade (opcional)

### Prometheus
O serviço já expõe métricas em `:${{ values.metricsPort | default(9090) }}${{ values.metricsPath | default('/metrics') }}`.
O ServiceMonitor é criado automaticamente pelo chart Helm se `metrics.enabled: true`.

### OpenTelemetry
O OTEL exporter está pré-configurado para o collector do namespace `staging-observability-monitoring`.
Verifique os traces em: `https://jaeger.staging.internal`

### Grafana
Dashboard template disponível em: `https://grafana.staging.internal/d/${{ values.name }}`

---

## Troubleshooting

### Pod em CrashLoopBackOff
```bash
kubectl describe pod -l app=${{ values.name }} -n staging-data-${{ values.name }}
kubectl logs -l app=${{ values.name }} -n staging-data-${{ values.name }} --previous
```

Causas comuns:
1. **ExternalSecret não sincronizado** — verifique credenciais no Vault (Passo 2)
2. **ConfigMap ausente** — verifique se `provision.sh` criou o ConfigMap
3. **Imagem não encontrada no Harbor** — verifique se o stage `build` passou

### ExternalSecret em SecretSyncedError
```bash
kubectl describe externalsecret ${{ values.name }}-secrets -n staging-data-${{ values.name }}
```

### Pipeline provision falhou
```bash
# Execute em DRY_RUN para diagnóstico (local, com kubeconfig configurado):
DRY_RUN=true VAULT_ADDR=https://vault.staging.internal VAULT_TOKEN=$(vault token create -field=token) \
  KUBECONFIG=~/.kube/config CI_PROJECT_DIR=. bash scripts/provision.sh
```

---

## Rollback

### Rollback do deploy (Helm)
```bash
helm history ${{ values.name }} -n staging-data-${{ values.name }}
helm rollback ${{ values.name }} [REVISION] -n staging-data-${{ values.name }} --wait
```

### Remover todos os recursos do staging
```bash
helm uninstall ${{ values.name }} -n staging-data-${{ values.name }}
kubectl delete namespace staging-data-${{ values.name }}
# Nota: ExternalSecret com deletionPolicy=Retain mantém o Secret K8s
```

---

## Referências

- [Documento de demanda](../../../Arquitetura/Kubernetes/docs/demands/2026-03-15-backstage-etl-template-python.md)
- [ADR-104 — Onboarding declarativo](../../../Arquitetura/Kubernetes/docs/adrs/ADR-104.md)
- [Checklist de deploy](../../../Arquitetura/Kubernetes/docs/plan/backstage/DEPLOYMENT-CHECKLIST.md)
- [Manifest schema](../../../Arquitetura/Kubernetes/domains/platform-core/app-provisioning/schemas/v1/manifest-schema.json)

---

## Referência Técnica — Escape de Chaves Nunjucks em `originadoras.yaml`

O arquivo `originadoras.yaml` (e outros arquivos de configuração gerados pelo scaffold) utiliza a sintaxe de escape `${{"{{"}}` / `{{"}"}}` em determinados valores. Essa sintaxe é necessária para renderizar chaves literais `{` e `}` no output do Backstage Scaffolder, que usa Nunjucks como engine de templates.

**Por que esse escape é necessário:**

O Backstage Scaffolder processa todos os arquivos skeleton com Nunjucks. Qualquer sequência `{{ ... }}` é interpretada como uma expressão de template. Para emitir chaves literais no arquivo gerado — como as usadas em variáveis de ambiente shell (`${VAR}`) — é preciso escapar cada chave individualmente:

| Escape no skeleton | Output gerado |
| --- | --- |
| `${{"{{"}}ORIGINADORA_API_USERNAME{{"}}"}}` | `${ORIGINADORA_API_USERNAME}` |
| `${{"{{"}}DATABASE_URL{{"}}"}}` | `${DATABASE_URL}` |

**Resolução em runtime:**

Os valores no formato `${NOME_VAR}` **não são resolvidos pelo Kubernetes nem pelo Helm**. Eles são substituídos pela própria aplicação em runtime, que lê as variáveis de ambiente injetadas pelo ExternalSecret/ConfigMap no pod. Exemplo:

```yaml
# originadoras.yaml gerado pelo scaffold (valor literal no arquivo):
username: ${ORIGINADORA_API_USERNAME}

# Em runtime, a aplicação resolve para o valor real injetado pelo ExternalSecret:
# username: usuario_real_da_originadora
```

Isso permite que o arquivo `originadoras.yaml` seja versionado no repositório sem expor credenciais, delegando a resolução ao mecanismo de secrets do cluster (ExternalSecret + Vault).
