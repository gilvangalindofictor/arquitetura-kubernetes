# Demanda: GAP IaC — Harbor jobservice: codificar `skip-outbound-ports` Linkerd permanentemente

**Data**: 2026-03-17
**Prioridade**: P1
**Tipo**: IaC Compliance / Platform Reliability
**Componentes afetados**: `harbor-jobservice` (Deployment), módulo Terraform `modules/harbor/`, `values.yaml.tpl`
**Origem**: Incidente pós-UP 2026-03-17 — harbor-jobservice CrashLoopBackOff após helm upgrade
**Status**: BACKLOG
**Arquivo**: `docs/demands/2026-03-17-harbor-linkerd-skip-outbound-ports.md`
**ADRs relacionados**: ADR-100 (IaC Compliance), ADR-TBD (Linkerd Annotations Policy)
**Relacionado a**: `docs/demands/2026-03-17-harbor-helm-linkerd-audit.md` (DEM-2026-03-17-05)

---

## 1. Contexto e Motivação

Em 2026-03-17, durante sessão de monitoramento pós-UP do cluster, o `harbor-jobservice` entrou em
`CrashLoopBackOff` após rollout para revisão 26 de um `helm upgrade harbor`. A investigação
identificou a causa raiz estrutural:

**A annotation `config.linkerd.io/skip-outbound-ports: "80"` estava ausente no `values.yaml.tpl`
do módulo Terraform Harbor**, embora estivesse presente no Deployment anterior (revisão 25).

Sem essa annotation, o sidecar Linkerd intercepta as conexões de saída do `harbor-jobservice` para
`harbor-core:80`. O protocolo HTTP/1.1 usado pelo jobservice nessa rota não é reconhecido
corretamente pelo proxy Linkerd nesse contexto, causando timeout HTTP 504 — independente do estado
do `harbor-core`.

### Fix paliativo aplicado (2026-03-17)

```bash
kubectl rollout undo deployment/harbor-jobservice -n harbor-system --to-revision=25
```

O rollback restaurou a annotation do Deployment anterior. Porém, o `values.yaml.tpl` permanece
sem a annotation, e **qualquer `helm upgrade harbor` futuro reproduzirá o mesmo crash**.

---

## 2. Problema Atual

### 2.1 — GAP IaC identificado

| Arquivo | Estado atual | Estado desejado |
|---|---|---|
| `modules/harbor/values.yaml.tpl` | Seção `jobservice:` sem `podAnnotations` | `podAnnotations` com `skip-outbound-ports: "80"` |
| Deployment `harbor-jobservice` (cluster) | Annotation presente (via rollback rev 25) | Annotation presente (via IaC permanente) |

### 2.2 — Localização exata do GAP no IaC

Arquivo: `platform-provisioning/aws/kubernetes/terraform/modules/harbor/values.yaml.tpl`

Seção atual (linhas 109–132):

```yaml
jobservice:
  serviceAccountName: ${service_account}
  replicas: 1  # FIXED: RWO PVC doesn't support multiple replicas (ADR-039)
  strategy:
    type: Recreate  # ADR-044
  podLabels:
    domain: platform
  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 768Mi
      cpu: 500m
  tolerations:
    - key: node-type
      operator: Equal
      value: system
      effect: NoSchedule
    - key: workload
      operator: Equal
      value: critical
      effect: NoSchedule
```

**Falta**: bloco `podAnnotations` com a annotation Linkerd.

### 2.3 — Impacto do incidente

| Métrica | Valor |
|---|---|
| Componente afetado | `harbor-jobservice` — namespace `harbor-system` |
| Sintoma | CrashLoopBackOff após `helm upgrade harbor` (revisão 26) |
| Causa raiz | Annotation `config.linkerd.io/skip-outbound-ports: "80"` ausente no IaC |
| Fix paliativo | `kubectl rollout undo` para revisão 25 |
| Risco residual | Qualquer `helm upgrade harbor` futuro reproduz o crash |
| MTTD | Detectado durante monitoramento pós-UP (sessão 2026-03-17) |
| MTTR | ~5 minutos após diagnóstico (rollback) |

---

## 3. Solução Definitiva

### 3.1 — Codificar annotation no values.yaml.tpl

Adicionar o bloco `podAnnotations` na seção `jobservice:` do arquivo
`platform-provisioning/aws/kubernetes/terraform/modules/harbor/values.yaml.tpl`:

```yaml
jobservice:
  serviceAccountName: ${service_account}
  replicas: 1  # FIXED: RWO PVC doesn't support multiple replicas (ADR-039)
  strategy:
    type: Recreate  # ADR-044: RWO PVC requires Recreate to avoid attach conflict
  podAnnotations:
    # IaC-FIX 2026-03-17: Linkerd intercepta conexões jobservice→harbor-core:80 via HTTP/1.1
    # sem skip-outbound-ports, o proxy causa HTTP 504 timeout → CrashLoopBackOff
    # Qualquer helm upgrade sem esta annotation reproduz o incidente
    config.linkerd.io/skip-outbound-ports: "80"
  podLabels:
    domain: platform
    # ADR-048: Kyverno label enforcement (2026-03-04)
  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 768Mi  # OOMKill fix 2026-03-04
      cpu: 500m
  tolerations:
    - key: node-type
      operator: Equal
      value: system
      effect: NoSchedule
    - key: workload
      operator: Equal
      value: critical
      effect: NoSchedule
```

### 3.2 — Validação pós-fix

Após o fix IaC e próximo `terraform plan` + `apply`:

```bash
# Gate 1: Annotation presente no Deployment após helm upgrade
kubectl get deployment harbor-jobservice -n harbor-system \
  -o jsonpath='{.spec.template.metadata.annotations}' | python3 -m json.tool

# Gate 2: Terraform plan sem drift
terraform plan -target=module.harbor_staging
# Resultado esperado: "No changes"

# Gate 3: Dry-run do helm para confirmar annotation no template
helm upgrade harbor harbor/harbor \
  --dry-run \
  --namespace harbor-system \
  --values <(terraform output -raw harbor_values) \
  | grep -A5 "skip-outbound"

# Gate 4: Teste de regressão — rollout restart não causa crash
kubectl rollout restart deployment/harbor-jobservice -n harbor-system
kubectl rollout status deployment/harbor-jobservice -n harbor-system
# Aguardar: "successfully rolled out"
kubectl get pods -n harbor-system -l component=jobservice
# Resultado esperado: 1/1 Running (sem CrashLoop)
```

---

## 4. Artefatos a Modificar

| Artefato | Tipo de modificação | Criticidade |
|---|---|---|
| `platform-provisioning/aws/kubernetes/terraform/modules/harbor/values.yaml.tpl` | Adicionar `podAnnotations` na seção `jobservice:` | **OBRIGATÓRIO** |

Nenhum arquivo novo precisa ser criado. A correção é cirúrgica: 4 linhas adicionadas no template.

---

## 5. Critérios de Aceite

| Gate | Como verificar | Status |
|---|---|---|
| Annotation no values.yaml.tpl | `grep -A5 "podAnnotations" modules/harbor/values.yaml.tpl` retorna `skip-outbound-ports: "80"` | ⏳ PENDENTE |
| Terraform plan zero drift | `terraform plan -target=module.harbor_staging` → "No changes" após apply | ⏳ PENDENTE |
| Helm dry-run confirma annotation | `helm upgrade harbor --dry-run` mostra annotation no Deployment template | ⏳ PENDENTE |
| Teste de regressão rollout restart | `kubectl rollout restart deployment/harbor-jobservice` → 1/1 Running sem CrashLoop | ⏳ PENDENTE |
| Annotation live no cluster | `kubectl get deployment harbor-jobservice -n harbor-system -o jsonpath='{.spec.template.metadata.annotations}'` mostra `skip-outbound-ports: "80"` | ⏳ PENDENTE |

---

## 6. Riscos e Mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|---|---|---|---|
| `helm upgrade` durante execução do fix causa novo CrashLoop | Baixa | Alto | Executar fix IaC ANTES do próximo upgrade Harbor planejado; rollback disponível |
| Outros componentes Harbor com o mesmo GAP (core, registry, portal, trivy) | Média | Alto | Auditoria completa coberta pela DEM-2026-03-17-05 (harbor-helm-linkerd-audit) |
| `terraform plan` mostra mudanças inesperadas além da annotation | Baixa | Médio | Revisar o plan completo antes do apply; escopo cirúrgico do fix reduz risco |
| Annotation `skip-outbound-ports: "80"` bloqueia tráfego legítimo via mTLS | Muito Baixa | Médio | Porta 80 é usada apenas internamente jobservice→core via HTTP plain; Linkerd não espera mTLS nessa rota |

---

## 7. Estimativa de Esforço

| Fase | Descrição | Esforço estimado |
|---|---|---|
| Fix IaC (values.yaml.tpl) | 4 linhas no template — cirúrgico | 10 min |
| terraform plan + apply | Validar zero drift + aplicar | 20 min |
| Testes de regressão | Rollout restart + verificação annotation | 15 min |
| Documentação logbook | Registrar fix no strategies-history.md | 10 min |
| **Total** | | **~1h** |

---

## 8. Dependências

| Dependência | Status | Bloqueador? |
|---|---|---|
| Harbor operacional em `harbor-system` | Ativo (rev 25 via rollback) | Não |
| Linkerd operacional | Ativo — destination/identity/proxy-injector Running | Não |
| Terraform state desbloqueado (staging) | Disponível | Não |
| Janela de manutenção para `helm upgrade harbor` | A agendar | Sim — o apply TF + helm upgrade deve ser feito em horário de baixo tráfego |
| DEM-2026-03-17-05 (auditoria completa) | BACKLOG | Não — este fix pode ser aplicado independentemente |

**Nota de urgência**: Este é um fix IaC mínimo e cirúrgico (P1) que deve ser aplicado antes do
próximo `helm upgrade harbor`. A DEM-2026-03-17-05 cobre a auditoria completa de annotations
Linkerd (P2) e pode ser executada em paralelo ou após.

---

## Histórico de Alterações

| Data | Autor | Alteração |
|---|---|---|
| 2026-03-17 | Agente Documentation Specialist | Criação da demanda a partir do incidente pós-UP harbor-jobservice CrashLoopBackOff |
