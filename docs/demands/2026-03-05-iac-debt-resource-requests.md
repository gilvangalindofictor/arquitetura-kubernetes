# IaC Debt — Resource Requests Rightsize (Staging)

**Data:** 2026-03-05
**Prioridade:** MEDIUM (IaC drift, não bloqueante)
**Contexto:** Nós workload us-east-1b com CPU 97-100% alocada. Patches manuais aplicados para liberar scheduling.

## Patches Aplicados Manualmente (kubectl)

### SonarQube (staging-platform-sonarqube)

```bash
kubectl patch statefulset sonarqube-sonarqube -n staging-platform-sonarqube --type='json' -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/cpu","value":"200m"},
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"1Gi"}
]'
kubectl delete pod sonarqube-sonarqube-0 -n staging-platform-sonarqube
```

| | Antes | Depois |
|---|---|---|
| CPU request | 500m | 200m |
| MEM request | 2Gi | 1Gi |
| CPU limit | 2000m | 2000m (sem alteração) |
| MEM limit | 4Gi | 4Gi (sem alteração) |

### GitLab Sidekiq (staging-platform-gitlab)

```bash
kubectl patch deployment gitlab-sidekiq-all-in-1-v2 -n staging-platform-gitlab --type='json' -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/cpu","value":"200m"},
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"768Mi"}
]'
# Pod recriado automaticamente pelo Deployment controller
```

| | Antes | Depois |
|---|---|---|
| CPU request | 500m | 200m |
| MEM request | 1Gi | 768Mi |
| CPU limit | 1500m | 1500m (sem alteração) |
| MEM limit | 2Gi | 2Gi (sem alteração) |

### Loki results-cache (staging-observability-monitoring)

```bash
kubectl patch statefulset loki-results-cache -n staging-observability-monitoring --type='json' -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/cpu","value":"100m"},
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"512Mi"}
]'
kubectl delete pod loki-results-cache-0 -n staging-observability-monitoring
```

| | Antes | Depois |
|---|---|---|
| CPU request | 500m | 100m |
| MEM request | 1229Mi | 512Mi |
| MEM limit | 1229Mi | 1229Mi (sem alteração) |

## Arquivos Terraform a Atualizar

### 1. SonarQube — JA ATUALIZADO no template

Arquivo: `platform-provisioning/aws/kubernetes/terraform/modules/sonarqube/values.yaml.tpl`

O template já foi atualizado com os novos valores (2026-03-05). Porém o `terraform apply` NÃO foi executado porque o `main.tf` contém um bug pré-existente (null_resource parcialmente comentado na linha 1096-1224) que impede qualquer `terraform plan`. O template está correto — ao corrigir o bug do main.tf, o próximo apply sincronizará automaticamente.

### 2. GitLab Sidekiq — JA ATUALIZADO no template

Arquivo: `platform-provisioning/aws/kubernetes/terraform/modules/gitlab/values.yaml.tpl`

Mesma situação: template atualizado, apply bloqueado pelo mesmo bug pré-existente no main.tf.

### 3. Loki results-cache — PENDENTE no Terraform

Arquivo: `platform-provisioning/aws/kubernetes/terraform/modules/loki/main.tf`

O módulo Loki configura recursos via `set` blocks para os componentes `read`, `write`, `backend`, `gateway` — mas NÃO tem blocos de resource para `resultsCache` (Memcached sub-chart). Precisa adicionar:

```hcl
set {
  name  = "resultsCache.resources.requests.cpu"
  value = "100m"
}

set {
  name  = "resultsCache.resources.requests.memory"
  value = "512Mi"
}

# Manter limit de memória para não colapsar em picos
set {
  name  = "resultsCache.resources.limits.memory"
  value = "1229Mi"
}
```

## Bug Pré-Existente no main.tf (Bloqueador do Terraform)

**Arquivo:** `platform-provisioning/aws/kubernetes/terraform/environments/staging/main.tf`
**Linha:** 1096-1224

O comentário `# resource "null_resource" "keycloak_grafana_admins_group" {` não fechou o bloco corretamente. O corpo do resource (depends_on, triggers, provisioner) ainda está ativo fora de qualquer resource block, causando erros de parse:

```
Error: Unsupported argument — depends_on (line 1098)
Error: Unsupported argument — triggers (line 1103)
Error: Unsupported block type — provisioner (line 1109)
```

**Fix necessário:** Adicionar `# ` prefix em todas as linhas 1097-1224, ou envolver o bloco em um heredoc comentado.

## Resultado Obtido

- Nó `ip-10-0-159-43`: CPU 97% → 76% (liberou 21 pontos percentuais)
- `loki-write-0`: estava Pending 50min, passou a Running após liberação
- Todos os 3 serviços: pods Running com novos requests validados
