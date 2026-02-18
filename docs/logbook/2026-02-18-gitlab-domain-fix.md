# Logbook — 2026-02-18: GitLab domain fix (example.com → staging.internal)

**Data**: 2026-02-18
**Duração**: ~30min
**Impacto**: GitLab acessível via `/etc/hosts` strategy — HTTP 302 ✅

---

## Problema

`http://gitlab.staging.internal` retornava **HTTP 404** mesmo com IPs corretos no `/etc/hosts`.

O ALB responde 404 quando nenhuma regra de listener bate com o Host header da requisição.

## Root Cause

O Ingress do GitLab tinha regras com `host: gitlab.example.com` (e `.kas`, `.registry`), mas o
`/etc/hosts` aponta `gitlab.staging.internal → ALB IP`.

O ALB faz roteamento por **Host header** — os dois não coincidiam → 404.

**Origem do placeholder:** `values.yaml.tpl` linha 14 tinha `domain: example.com` hardcoded
(comentário: "Placeholder, will use ALB DNS" — ADR-021 Fase 1). A variável `domain_name`
já era passada ao `templatefile()` mas não era usada na linha crítica do template.

**Drift adicional:** Os values do Helm (revision 2, 2026-02-13) já tinham `domain: staging.internal`
salvo pelo `helm get values`, mas os objetos Ingress K8s nunca foram atualizados porque o
`helm upgrade` falha com erro de schema certmanager (`rbac`/`install` não são mais propriedades
válidas). O `lifecycle { ignore_changes = all }` no Terraform impede apply automático.

## Solução

### 1. Fix no código Terraform (permanente)

**`modules/gitlab/values.yaml.tpl:14`**
```yaml
# antes:
    domain: example.com  # Placeholder, will use ALB DNS
# depois:
    domain: ${domain_name}
```

**`environments/staging/main.tf:288`**
```hcl
# antes:
  domain_name = ""
# depois:
  domain_name = "staging.internal"
```

### 2. Patch direto nos Ingress (imediato, corrige o drift)

```bash
kubectl patch ingress gitlab-webservice-default -n gitlab-staging \
  --type=json -p='[{"op":"replace","path":"/spec/rules/0/host","value":"gitlab.staging.internal"}]'

kubectl patch ingress gitlab-kas -n gitlab-staging \
  --type=json -p='[{"op":"replace","path":"/spec/rules/0/host","value":"kas.staging.internal"}]'

kubectl patch ingress gitlab-registry -n gitlab-staging \
  --type=json -p='[{"op":"replace","path":"/spec/rules/0/host","value":"registry.staging.internal"}]'
```

## Resultado

```
kubectl get ingress -n gitlab-staging
NAME                        HOSTS                       ADDRESS
gitlab-kas                  kas.staging.internal        k8s-gitlabstaging-da5a4e8c6d-...
gitlab-registry             registry.staging.internal   k8s-gitlabstaging-da5a4e8c6d-...
gitlab-webservice-default   gitlab.staging.internal     k8s-gitlabstaging-da5a4e8c6d-...

curl -H "Host: gitlab.staging.internal" http://54.209.81.173/
→ HTTP 302 (redirect para login) ✅
```

## Pendências

- **Helm upgrade** com schema certmanager bloqueado: valores antigos têm `certmanager.install`
  e `certmanager.rbac.create` que o schema atual rejeita como "additional properties not allowed".
  Fix futuro: limpar esses keys dos user-values antes do próximo `helm upgrade`.
- **lifecycle { ignore_changes = all }** no `module.gitlab_staging` (main.tf:247) — qualquer
  mudança nos Helm values requer upgrade manual. Documentado no próprio código.

## Lição Aprendida

Ao usar `templatefile()` no Terraform, **sempre verificar se variáveis passadas estão de fato
usadas no template** — é fácil passar `domain_name = var.domain_name` no map mas ter um
literal hardcoded no `.tpl`. O `helm get values` mostra os user-supplied values (que podem
estar corretos) mas os objetos K8s podem estar desatualizados se o upgrade falhou silenciosamente.
