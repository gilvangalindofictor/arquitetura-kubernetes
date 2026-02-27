# [GAP-011] Linkerd Service Mesh Deployment — BLOQUEADO (Staging Offline)

**Data**: 2026-02-26
**Agente**: Network & Service Mesh Specialist
**Status**: ⏸️ BLOCKED — AWS/Kubernetes cluster offline
**Demanda**: GAP-011: Linkerd Service Mesh (mTLS End-to-End) — BACEN BCB 85/2021 Compliance

---

## Executive Summary

**Execução bloqueada devido a ambiente staging DESLIGADO.**

Todos os artefatos Terraform para deploy de Linkerd 2.16.x estão **PRONTOS e revisados**:
- ✅ Módulo Terraform `modules/linkerd/` completo (438 linhas)
- ✅ Integração em `environments/staging/main.tf` configurada
- ✅ PKI TLS provider (trust anchor + issuer certificate)
- ✅ Helm charts: linkerd-crds, linkerd-control-plane, linkerd-viz
- ✅ Outputs para monitoramento e compliance
- ✅ README.md com guia de uso e annotation patterns

**Bloqueio detectado**:
```bash
$ aws sts get-caller-identity
Error: Unable to locate credentials. You can configure credentials by running "aws login".
```

**Próximos passos**:
1. Aguardar ambiente staging retornar online
2. Executar runbook de deployment (abaixo)
3. Validar control plane readiness
4. Testar proxy injection em namespace de teste
5. Documentar compliance mapping BACEN BCB 85/2021

**Custo adicional estimado**: +$5/mês (overhead de proxy CPU — ~100mCPU por workload)

---

## 1. PRE-CHECK Status

| Item | Status | Detalhes |
|------|--------|----------|
| AWS Session | ❌ FAILED | `aws sts get-caller-identity`: credentials não disponíveis |
| Kubernetes Cluster | ⚠️ NOT TESTED | Depende de AWS session ativa |
| Terraform Module | ✅ PRONTO | `/modules/linkerd/` (main.tf, variables.tf, outputs.tf, versions.tf, README.md) |
| Staging Integration | ✅ PRONTO | `/environments/staging/main.tf` linhas 2298-2374 |
| Helm Repo Availability | ⚠️ NOT TESTED | https://helm.linkerd.io/stable (deve ser validado durante apply) |

---

## 2. Terraform Module Architecture Review

### 2.1 Componentes Principais

O módulo `modules/linkerd/` implementa a seguinte arquitetura:

```
┌─────────────────────────────────────────────────────────────┐
│                Linkerd Control Plane (namespace: linkerd)   │
├─────────────────────────────────────────────────────────────┤
│ 1. PKI (TLS Provider)                                       │
│    - tls_private_key.trust_anchor (ECDSA P256)              │
│    - tls_self_signed_cert.trust_anchor (365 days validity)  │
│    - tls_private_key.issuer (ECDSA P256)                    │
│    - tls_locally_signed_cert.issuer (8760h validity)        │
│                                                             │
│ 2. Helm Releases (ordem sequencial via depends_on):        │
│    a) linkerd-crds (chart v1.8.0)                           │
│       └─> ServiceProfile, AuthorizationPolicy CRDs          │
│    b) linkerd-control-plane (chart v1.16.11)                │
│       └─> identity, proxy-injector, destination             │
│    c) linkerd-viz (chart v30.12.11) [se enable_viz=true]   │
│       └─> dashboard, Tap API, Metrics API                   │
│                                                             │
│ 3. Namespace Annotations (opt-in proxy injection):         │
│    - kubernetes_annotations.linkerd_inject                  │
│    - Apply to: ipaas, integration namespaces                │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│          Linkerd Viz Extension (namespace: linkerd-viz)     │
├─────────────────────────────────────────────────────────────┤
│ - Dashboard: http://web.linkerd-viz.svc:8084                │
│ - Tap API: real-time L7 traffic inspection                 │
│ - Prometheus integration: external (kube-prometheus-stack)  │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│               Data Plane (per pod, opt-in)                  │
├─────────────────────────────────────────────────────────────┤
│ Annotation: linkerd.io/inject=enabled                       │
│ Result: linkerd-proxy sidecar (100m CPU / 64Mi MEM)        │
│ mTLS: automatic via SPIFFE identity                         │
│ Certificate TTL: 24h (auto-rotated by identity component)  │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Critical Configuration (staging environment)

Extraído de `environments/staging/main.tf` (linhas 2319-2373):

```hcl
module "linkerd" {
  source = "../../modules/linkerd"

  cluster_name = "k8s-platform-prod"
  environment  = "staging"

  # Helm Chart Versions (stable-2.16.x channel)
  linkerd_crds_chart_version = "1.8.0"
  linkerd_version            = "1.16.11"
  linkerd_viz_chart_version  = "30.12.11"

  # PKI Configuration
  trust_domain              = "cluster.local"
  certificate_validity_days = 365  # Trust anchor expires in 1 year

  # Proxy Resources (staging minimal limits)
  proxy_cpu_request    = "100m"
  proxy_memory_request = "64Mi"
  proxy_cpu_limit      = "500m"
  proxy_memory_limit   = "256Mi"

  # High Availability: DISABLED for staging
  ha_mode = false  # 1 replica per component

  # Viz Extension: ENABLED with external Prometheus
  enable_viz              = true
  viz_prometheus_enabled  = false  # Use existing kube-prometheus-stack
  external_prometheus_url = "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"

  # Grafana Dashboards: DISABLED (JSONs not downloaded yet)
  enable_grafana_dashboards = false

  # Jaeger/Tracing: DISABLED for staging
  enable_jaeger = false

  # Opt-in Proxy Injection by Namespace
  proxy_inject_namespaces = [
    "ipaas",        # iPaaS core services — primary scope for GAP-011
    "integration",  # Integration workers (RabbitMQ consumers, etc.)
  ]
}
```

### 2.3 Key Design Decisions

| Decisão | Justificativa |
|---------|---------------|
| **PKI 100% Terraform TLS Provider** | Zero dependência externa: trust anchor + issuer gerados via `tls_private_key` + `tls_self_signed_cert` |
| **Opt-in proxy injection** | Blast radius controlado: apenas namespaces listados em `proxy_inject_namespaces` recebem sidecar automático |
| **External Prometheus** | Aproveita kube-prometheus-stack existente: `viz_prometheus_enabled=false` evita duplicação de stack |
| **HA Mode OFF (staging)** | 1 replica por componente: reduz custos em staging, production deve usar `ha_mode=true` (3 replicas + PDB) |
| **Certificate Validity 365d** | Trust anchor expira em 1 ano: workload certs (24h TTL) são auto-rotacionados pelo identity component |

### 2.4 Compliance Mapping — BACEN BCB 85/2021

| Artigo BCB 85/2021 | Controle Linkerd | Artefato |
|--------------------|------------------|----------|
| Art. 6º SS IV — Criptografia em trânsito | mTLS automático SPIFFE/SPIRE | `identityTrustAnchorsPEM` (main.tf:161) |
| Art. 6º SS V — Autenticação mútua | Certificados x.509 por ServiceAccount | `identity.issuer.tls.crtPEM` (main.tf:166-167) |
| Art. 9º — Rotação de credenciais | Certificate TTL 24h (auto-rotação) | `issuanceLifetime: "24h0m0s"` (main.tf:221) |
| Art. 11º — Auditoria de comunicações | Tap API + métricas L7 Prometheus | `tap: enabled: true` (main.tf:281) |
| Art. 15º — Segregação de tráfego | AuthorizationPolicy CRDs | CRDs instalados via `helm_release.linkerd_crds` |

---

## 3. RUNBOOK de Deployment — Quando Ambiente Subir

### Fase 1: Terraform Plan (5-10 minutos)

```bash
# 1.1. Validar AWS session
aws sts get-caller-identity
# Esperado: {"UserId": "...", "Account": "...", "Arn": "..."}

# 1.2. Validar cluster Kubernetes
kubectl cluster-info --context=k8s-platform-prod
# Esperado: Kubernetes control plane is running at https://...

# 1.3. Verificar providers Helm
helm repo list | grep linkerd || echo "Repo Linkerd não configurado ainda (Terraform adicionará)"

# 1.4. Navegar para staging environment
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/environments/staging

# 1.5. Terraform init (atualizar providers)
terraform init -upgrade
# Esperado: Initializing provider plugins... tls ~> 4.0, helm ~> 2.12, kubernetes ~> 2.20

# 1.6. Terraform plan (gerar arquivo de plan)
terraform plan -out=gap011-linkerd.tfplan -target=module.linkerd 2>&1 | tee /tmp/gap011-plan.log

# 1.7. Revisar plan output
grep -E "(tls_private_key|tls_self_signed_cert|helm_release|kubernetes_namespace)" /tmp/gap011-plan.log

# Recursos esperados no plan:
# + module.linkerd.tls_private_key.trust_anchor
# + module.linkerd.tls_self_signed_cert.trust_anchor
# + module.linkerd.tls_private_key.issuer
# + module.linkerd.tls_locally_signed_cert.issuer
# + module.linkerd.kubernetes_namespace.linkerd
# + module.linkerd.helm_release.linkerd_crds
# + module.linkerd.helm_release.linkerd_control_plane
# + module.linkerd.kubernetes_namespace.linkerd_viz[0]
# + module.linkerd.helm_release.linkerd_viz[0]
# + module.linkerd.kubernetes_annotations.linkerd_inject["ipaas"]
# + module.linkerd.kubernetes_annotations.linkerd_inject["integration"]
```

**Validação Crítica Pré-Apply**:
- ✅ Plan deve criar **~11 resources** (PKI + namespaces + Helm releases)
- ✅ Verificar `certificate_validity_days = 365` no output do plan
- ✅ Confirmar `proxy_inject_namespaces = ["ipaas", "integration"]`
- ❌ Se plan falhar com erro de cluster inacessível: pausar e reportar

---

### Fase 2: Terraform Apply com Active Monitoring Loop (15-25 minutos)

```bash
# 2.1. Apply com monitoramento ativo
terraform apply gap011-linkerd.tfplan > /tmp/gap011-apply.log 2>&1 &
APPLY_PID=$!

# 2.2. Active Monitoring Loop (AML-C)
CYCLE=0
echo "[AML-C] Iniciando monitoramento ativo - PID: $APPLY_PID"

while kill -0 $APPLY_PID 2>/dev/null; do
  clear
  echo "=========================================="
  echo "[AML-C-$CYCLE] GAP-011 Linkerd Deployment"
  echo "Time: $(date '+%H:%M:%S')"
  echo "=========================================="

  # 2.2.1. Terraform apply log (últimas 25 linhas)
  echo ">>> TERRAFORM APPLY LOG:"
  tail -25 /tmp/gap011-apply.log | grep -E "(Creating|Still creating|Creation complete|Error)"
  echo ""

  # 2.2.2. Linkerd CRDs
  echo ">>> LINKERD CRDs:"
  kubectl get crd | grep linkerd.io || echo "CRDs não instaladas ainda"
  echo ""

  # 2.2.3. Linkerd namespace
  echo ">>> LINKERD NAMESPACE:"
  kubectl get ns linkerd --context=k8s-platform-prod 2>/dev/null || echo "Namespace linkerd não existe ainda"
  echo ""

  # 2.2.4. Linkerd control plane pods
  echo ">>> LINKERD CONTROL PLANE PODS:"
  kubectl get pods -n linkerd --context=k8s-platform-prod --no-headers 2>/dev/null | awk '{print $1, $2, $3}' || echo "Namespace linkerd não existe ainda"
  echo ""

  # 2.2.5. Linkerd Viz pods
  echo ">>> LINKERD VIZ PODS:"
  kubectl get pods -n linkerd-viz --context=k8s-platform-prod --no-headers 2>/dev/null | awk '{print $1, $2, $3}' || echo "Namespace linkerd-viz não existe ainda"
  echo ""

  # 2.2.6. Helm releases
  echo ">>> HELM RELEASES:"
  helm list -n linkerd --kube-context k8s-platform-prod 2>/dev/null || echo "Helm releases não listados ainda"
  helm list -n linkerd-viz --kube-context k8s-platform-prod 2>/dev/null || echo "linkerd-viz não listado ainda"
  echo ""

  # 2.2.7. Progress indicator
  echo "Próximo refresh: 15 segundos | Ctrl+C para parar AML (apply continua em background)"
  echo "=========================================="

  sleep 15
  ((CYCLE++))
done

# 2.3. Wait for apply completion
wait $APPLY_PID
APPLY_EXIT_CODE=$?

# 2.4. Report apply result
if [ $APPLY_EXIT_CODE -eq 0 ]; then
  echo "[AML-C] ✅ Terraform apply COMPLETO com sucesso"
  echo "[AML-C] Exit code: 0"
else
  echo "[AML-C] ❌ Terraform apply FALHOU"
  echo "[AML-C] Exit code: $APPLY_EXIT_CODE"
  echo "[AML-C] Ver log completo: /tmp/gap011-apply.log"
  exit 1
fi
```

**Troubleshooting Durante Apply**:

| Problema Observado | Causa Possível | Ação |
|--------------------|---------------|------|
| `helm_release.linkerd_crds` timeout após 300s | Helm repo inacessível | Verificar `helm repo list`, executar `helm repo update` |
| Pods `linkerd-destination` em `ImagePullBackOff` | Docker Hub rate limit | Aguardar retry automático ou configurar image pull secret |
| `linkerd-proxy-injector` CrashLoopBackOff | Certificados TLS inválidos | Verificar outputs do Terraform: `trust_anchor_certificate`, `issuer_certificate` |
| Namespace `linkerd-viz` criado mas pods não sobem | Dependência `helm_release.linkerd_control_plane` não concluída | Aguardar control plane ficar Ready (2-3 min após CRDs) |

---

### Fase 3: Validação Pós-Deploy (10-15 minutos)

```bash
# 3.1. Control Plane Pods (namespace: linkerd)
echo ">>> VALIDAÇÃO 1/7: Linkerd Control Plane Pods"
kubectl get pods -n linkerd --context=k8s-platform-prod
# Esperado (staging com ha_mode=false):
# NAME                                      READY   STATUS    AGE
# linkerd-destination-xxxxxxxxxx-xxxxx      4/4     Running   5m
# linkerd-identity-xxxxxxxxxx-xxxxx         2/2     Running   5m
# linkerd-proxy-injector-xxxxxxxxxx-xxxxx   2/2     Running   5m

# 3.2. Linkerd CLI Check (requer linkerd CLI instalado localmente)
echo ">>> VALIDAÇÃO 2/7: Linkerd CLI Check"
if command -v linkerd &> /dev/null; then
  linkerd check --context=k8s-platform-prod
  # Esperado: All checks passed ✅
  # Se FALHOU: revisar erros específicos (geralmente certificados ou conectividade)
else
  echo "⚠️  linkerd CLI não instalado. Instalar: curl -sL https://run.linkerd.io/install-edge | sh"
fi

# 3.3. CRDs Instalados
echo ">>> VALIDAÇÃO 3/7: Linkerd CRDs"
kubectl get crd --context=k8s-platform-prod | grep linkerd.io
# Esperado:
# authorizationpolicies.policy.linkerd.io
# httproutes.policy.linkerd.io
# meshtlsauthentications.policy.linkerd.io
# serverauthorizations.policy.linkerd.io
# servers.policy.linkerd.io
# serviceprofiles.linkerd.io

# 3.4. Linkerd Viz Pods (namespace: linkerd-viz)
echo ">>> VALIDAÇÃO 4/7: Linkerd Viz Extension Pods"
kubectl get pods -n linkerd-viz --context=k8s-platform-prod
# Esperado:
# metrics-api-xxxxxxxxxx-xxxxx      2/2     Running
# tap-xxxxxxxxxx-xxxxx              2/2     Running
# tap-injector-xxxxxxxxxx-xxxxx     2/2     Running
# web-xxxxxxxxxx-xxxxx              2/2     Running

# 3.5. PKI Certificates (via Terraform outputs)
echo ">>> VALIDAÇÃO 5/7: PKI Certificates"
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/environments/staging
terraform output linkerd_trust_anchor_certificate_expiry
# Esperado: 8760 (365 dias * 24 horas)

terraform output -raw linkerd_trust_anchor_certificate | openssl x509 -noout -text | grep -E "(Subject:|Not After)"
# Esperado:
# Subject: CN=root.linkerd.cluster.local, O=Linkerd
# Not After : <data daqui a 1 ano>

# 3.6. Helm Releases Status
echo ">>> VALIDAÇÃO 6/7: Helm Releases"
helm list -n linkerd --kube-context k8s-platform-prod
helm list -n linkerd-viz --kube-context k8s-platform-prod
# Esperado:
# NAME                    NAMESPACE    STATUS     CHART                        APP VERSION
# linkerd-crds            linkerd      deployed   linkerd-crds-1.8.0           stable-2.16.x
# linkerd-control-plane   linkerd      deployed   linkerd-control-plane-1.16.11 stable-2.16.11
# linkerd-viz             linkerd-viz  deployed   linkerd-viz-30.12.11         stable-2.16.11

# 3.7. Namespace Annotations (opt-in proxy injection)
echo ">>> VALIDAÇÃO 7/7: Namespace Annotations"
kubectl get ns ipaas integration --context=k8s-platform-prod -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.linkerd\.io/inject}{"\n"}{end}'
# Esperado:
# ipaas        enabled
# integration  enabled
```

**Critérios de Sucesso Pós-Deploy**:
- ✅ **Control Plane**: 3 pods Ready (linkerd-destination 4/4, linkerd-identity 2/2, linkerd-proxy-injector 2/2)
- ✅ **Viz Extension**: 4 pods Ready (metrics-api, tap, tap-injector, web — todos 2/2)
- ✅ **CRDs**: 6 CRDs instalados (authorizationpolicies, httproutes, meshtlsauthentications, servers, serverauthorizations, serviceprofiles)
- ✅ **PKI**: Trust anchor válido por 365 dias, issuer cert assinado pelo trust anchor
- ✅ **Helm Releases**: 3 releases deployed (linkerd-crds, linkerd-control-plane, linkerd-viz)
- ✅ **Namespace Annotations**: ipaas + integration com `linkerd.io/inject=enabled`

---

### Fase 4: Proxy Injection Test (5 minutos)

```bash
# 4.1. Criar namespace de teste com annotation
cat <<EOF | kubectl apply --context=k8s-platform-prod -f -
apiVersion: v1
kind: Namespace
metadata:
  name: linkerd-test
  annotations:
    linkerd.io/inject: enabled
EOF

# 4.2. Deploy workload de teste (nginx)
kubectl run nginx-linkerd-test \
  --image=nginx:alpine \
  --namespace=linkerd-test \
  --context=k8s-platform-prod \
  --port=80

# 4.3. Aguardar pod subir (30 segundos)
kubectl wait --for=condition=Ready pod/nginx-linkerd-test -n linkerd-test --timeout=60s --context=k8s-platform-prod

# 4.4. Verificar proxy injetado
echo ">>> TESTE: Containers no pod (esperado: nginx + linkerd-proxy)"
kubectl get pod nginx-linkerd-test -n linkerd-test --context=k8s-platform-prod \
  -o jsonpath='{.spec.initContainers[*].name} | {.spec.containers[*].name}{"\n"}'
# Esperado: linkerd-init | nginx linkerd-proxy

# 4.5. Verificar identidade mTLS
echo ">>> TESTE: Identidade SPIFFE do pod"
kubectl exec -n linkerd-test nginx-linkerd-test --context=k8s-platform-prod -c linkerd-proxy -- \
  wget -qO- localhost:4191/metrics | grep 'identity_cert_expiration_timestamp_seconds'
# Esperado: métrica com timestamp futuro (certificado válido por 24h)

# 4.6. Linkerd CLI Tap (real-time traffic inspection)
if command -v linkerd &> /dev/null; then
  echo ">>> TESTE: Linkerd Tap (tráfego L7 em tempo real)"
  linkerd tap pod/nginx-linkerd-test -n linkerd-test --context=k8s-platform-prod --max-rps 1
  # Esperado: tráfego mTLS entre nginx e linkerd-proxy
fi

# 4.7. Cleanup namespace de teste
kubectl delete namespace linkerd-test --context=k8s-platform-prod
```

**Critérios de Sucesso Proxy Injection Test**:
- ✅ Pod `nginx-linkerd-test` possui 3 containers: `linkerd-init` (initContainer), `nginx`, `linkerd-proxy`
- ✅ Métrica `identity_cert_expiration_timestamp_seconds` retorna timestamp futuro (válido)
- ✅ `linkerd tap` mostra tráfego L7 com status `tls="true"`

---

## 4. Documentação Pós-Deploy

### 4.1. Logbook Entry

Criar: `/docs/logbook/2026-02-26-gap011-linkerd-deployment-success.md`

Template:
```markdown
# [GAP-011] Linkerd Service Mesh Deployment — SUCCESS

**Data**: 2026-02-26
**Duração Total**: <X minutos>
**Status**: ✅ COMPLETO

## Timeline

| Fase | Duração | Status |
|------|---------|--------|
| Terraform Plan | <X min> | ✅ |
| Terraform Apply | <X min> | ✅ |
| Control Plane Ready | <X min> | ✅ |
| Viz Extension Ready | <X min> | ✅ |
| Proxy Injection Test | <X min> | ✅ |

## Recursos Criados

### Kubernetes Namespaces
- `linkerd` — Control Plane
- `linkerd-viz` — Observability Extension

### Helm Releases
- `linkerd-crds` v1.8.0
- `linkerd-control-plane` v1.16.11
- `linkerd-viz` v30.12.11

### CRDs Instalados
- authorizationpolicies.policy.linkerd.io
- httproutes.policy.linkerd.io
- meshtlsauthentications.policy.linkerd.io
- serverauthorizations.policy.linkerd.io
- servers.policy.linkerd.io
- serviceprofiles.linkerd.io

### PKI Certificates
- Trust Anchor (root CA): Validade 365 dias (expira em 2027-02-26)
- Issuer Certificate: Validade 365 dias (auto-assinado pelo trust anchor)
- Workload Certificates: TTL 24h (auto-rotacionados pelo identity component)

## Compliance Mapping — BACEN BCB 85/2021

| Artigo | Status | Evidência |
|--------|--------|-----------|
| Art. 6º SS IV — Criptografia em trânsito | ✅ | mTLS automático via SPIFFE (test: `linkerd tap` mostra tls="true") |
| Art. 6º SS V — Autenticação mútua | ✅ | Certificados x.509 por ServiceAccount (identity component) |
| Art. 9º — Rotação de credenciais | ✅ | Workload cert TTL 24h + auto-rotação (identity_cert_expiration_timestamp_seconds) |
| Art. 11º — Auditoria de comunicações | ✅ | Tap API + Prometheus metrics L7 (linkerd-viz instalado) |
| Art. 15º — Segregação de tráfego | ✅ | AuthorizationPolicy CRDs disponíveis (pending: criar policies específicas) |

## Próximos Passos

1. **Anotar namespaces de produção** (quando aplicações forem migradas):
   ```bash
   kubectl annotate namespace <namespace> linkerd.io/inject=enabled
   kubectl rollout restart deployment -n <namespace>
   ```

2. **Criar AuthorizationPolicies** para segregação de tráfego:
   - Exemplo: permitir apenas `integration-worker` chamar API interna do iPaaS
   - Ver: `/modules/linkerd/README.md#authorization-policies-identity-based`

3. **Criar ServiceProfiles** para observabilidade por rota HTTP:
   - Breakdown de latência por endpoint (POST /api/v1/eventos, GET /api/v1/health, etc.)
   - Ver: `/modules/linkerd/README.md#serviceprofile-observabilidade-por-rota`

4. **Configurar Grafana Dashboards** (opcional):
   - Baixar JSONs oficiais: `curl https://raw.githubusercontent.com/linkerd/linkerd2/stable-2.16.0/grafana/dashboards/...`
   - Habilitar: `enable_grafana_dashboards = true` em `main.tf`

5. **Monitorar custo adicional** (FinOps):
   - Baseline: +$5/mês estimado
   - Métricas: `kube_pod_container_resource_requests{container="linkerd-proxy"}`

## Custo Real vs Estimado

- **Estimado pré-deploy**: +$5/mês
- **Real pós-deploy**: <X/mês> (verificar após 7 dias de métricas VPA)
- **Savings potenciais**: Zero (overhead necessário para compliance)

## Lessons Learned

- <anotar problemas técnicos resolvidos durante apply>
- <performance do AML-C: ciclos até conclusão>
- <tempo real de Helm releases vs timeout configurado>
```

### 4.2. Update MEMORY.md

Adicionar em `/docs/memory/MEMORY.md` seção **Realizados por categoria**:

```markdown
| GAP-011: Linkerd Service Mesh (mTLS BACEN) | +$5/mês | COMPLETO (2026-02-26) |
```

Atualizar seção **Compliance Coverage**:

```markdown
### BACEN BCB 85/2021 — Criptografia em Trânsito
- ✅ **Art. 6º SS IV**: mTLS end-to-end via Linkerd 2.16.x (GAP-011 completo)
- ✅ **Art. 9º**: Rotação automática de certificados workload (24h TTL)
- ✅ **Art. 11º**: Auditoria L7 via Linkerd Tap API + Prometheus
```

### 4.3. Update demands-backlog.md

Marcar GAP-011 como completo:

```markdown
| GAP-011 | Linkerd Service Mesh | mTLS End-to-End | ✅ COMPLETO | 2026-02-26 | 3 semanas | +$5/mês | BACEN BCB 85/2021 compliance |
```

---

## 5. Rollback Plan (Se Apply Falhar)

Se `terraform apply` falhar durante execução:

```bash
# 5.1. Identificar recurso que falhou
grep -E "(Error|failed)" /tmp/gap011-apply.log | tail -20

# 5.2. Destroy recursos parciais (se control plane não ficou Ready)
terraform destroy -target=module.linkerd -auto-approve

# 5.3. Limpar namespaces órfãos (se destroy parcial falhar)
kubectl delete namespace linkerd linkerd-viz --context=k8s-platform-prod --force --grace-period=0

# 5.4. Limpar CRDs (CUIDADO: remove CRDs globais)
kubectl get crd | grep linkerd.io | awk '{print $1}' | xargs kubectl delete crd --context=k8s-platform-prod

# 5.5. Verificar Helm releases órfãos
helm list --all-namespaces --kube-context k8s-platform-prod | grep linkerd
# Se existir, remover manualmente:
helm uninstall linkerd-crds -n linkerd --kube-context k8s-platform-prod
helm uninstall linkerd-control-plane -n linkerd --kube-context k8s-platform-prod
helm uninstall linkerd-viz -n linkerd-viz --kube-context k8s-platform-prod

# 5.6. Retry apply (após cleanup completo)
terraform init -reconfigure
terraform plan -out=gap011-linkerd-retry.tfplan -target=module.linkerd
terraform apply gap011-linkerd-retry.tfplan
```

**Cenários Críticos de Rollback**:

| Problema | Rollback Action | Downtime Impact |
|----------|-----------------|-----------------|
| Control plane pods CrashLoopBackOff | `terraform destroy -target=module.linkerd` | Zero (serviços sem proxy não são afetados) |
| CRDs duplicados (conflito com instalação manual anterior) | `kubectl delete crd <crd-name>` + retry apply | Zero |
| Helm release FAILED status | `helm uninstall <release>` + `terraform apply` | Zero (opt-in: sem proxies ativos ainda) |
| PKI certificates inválidos | `terraform taint module.linkerd.tls_private_key.trust_anchor` + `terraform apply` | Restart control plane (~2 min downtime) |

---

## 6. Cost Analysis

### 6.1. Baseline Costs (Sem Linkerd)

| Recurso | Custo Mensal |
|---------|--------------|
| EKS Nodes (t3.medium×2 + t3.large×3 + t3.xlarge×3) | $456/mês |
| EBS gp3 (575GB) | $46/mês |
| **Total Baseline** | **$502/mês** |

### 6.2. Incremental Costs (Com Linkerd)

| Recurso Adicional | Especificação | Custo Estimado |
|-------------------|---------------|----------------|
| Linkerd Control Plane pods (ha_mode=false) | 3 pods: destination (200mCPU, 100Mi), identity (100mCPU, 50Mi), proxy-injector (100mCPU, 50Mi) | +$2/mês |
| Linkerd Viz pods | 4 pods: metrics-api, tap, tap-injector, web (total ~300mCPU, 200Mi) | +$1/mês |
| Linkerd Proxy sidecars (2 namespaces injetados) | ipaas: ~10 pods × 100mCPU = 1000mCPU; integration: ~5 pods × 100mCPU = 500mCPU | +$2/mês |
| **Total Incremental** | — | **+$5/mês** |

**ROI de Compliance**:
- **Custo adicional**: +$5/mês (+1% sobre baseline)
- **Benefício**: Compliance BACEN BCB 85/2021 Art. 6º/9º/11º/15º
- **Risco evitado**: Multas regulatórias (estimado: $10K-$50K por não-conformidade)
- **Payback**: Imediato (requisito mandatório, não opcional)

### 6.3. Production Scaling (HA Mode)

Quando migrar para production com `ha_mode=true`:

| Recurso | Staging (ha_mode=false) | Production (ha_mode=true) | Delta |
|---------|-------------------------|---------------------------|-------|
| Control Plane pods | 3 pods (1 replica cada) | 9 pods (3 replicas cada) | +$4/mês |
| PodDisruptionBudgets | 0 | 3 PDBs (minAvailable=2) | $0 (custo zero, apenas controle) |
| **Total Production** | +$5/mês | +$9/mês | +$4/mês |

---

## 7. Next Actions (Quando Ambiente Subir)

**Prioridade ALTA** (executar imediatamente):
1. ✅ Validar AWS session ativa (`aws sts get-caller-identity`)
2. ✅ Validar cluster Kubernetes UP (`kubectl cluster-info`)
3. ✅ Executar Fase 1: Terraform Plan (seção 3)
4. ✅ Executar Fase 2: Terraform Apply com AML (seção 3)
5. ✅ Executar Fase 3: Validação Pós-Deploy (seção 3)
6. ✅ Executar Fase 4: Proxy Injection Test (seção 3)
7. ✅ Criar logbook de sucesso (seção 4.1)

**Prioridade MÉDIA** (dentro de 7 dias):
1. Criar ADR para GAP-011 (`docs/adr/adr-086-linkerd-service-mesh.md`)
2. Documentar AuthorizationPolicy patterns para iPaaS (segregação de tráfego)
3. Criar ServiceProfiles para top 5 APIs críticas (observabilidade por rota)
4. Configurar alertas Prometheus para `linkerd_proxy_http_request_duration_seconds_bucket` (SLO)

**Prioridade BAIXA** (futuro):
1. Baixar Grafana dashboards oficiais (habilitar `enable_grafana_dashboards=true`)
2. Avaliar Linkerd Jaeger integration (`enable_jaeger=true`) se tracing distribuído for demandado
3. Migration plan para production: `ha_mode=true` + 3 replicas control plane

---

## 8. Arquivos Críticos — Quick Reference

### Terraform Module
- `/platform-provisioning/aws/kubernetes/terraform/modules/linkerd/main.tf` (438 linhas)
- `/platform-provisioning/aws/kubernetes/terraform/modules/linkerd/variables.tf` (208 linhas)
- `/platform-provisioning/aws/kubernetes/terraform/modules/linkerd/outputs.tf` (99 linhas)
- `/platform-provisioning/aws/kubernetes/terraform/modules/linkerd/versions.tf` (32 linhas)
- `/platform-provisioning/aws/kubernetes/terraform/modules/linkerd/README.md` (302 linhas)

### Staging Environment Integration
- `/platform-provisioning/aws/kubernetes/terraform/environments/staging/main.tf` (linhas 2298-2374)
- `/platform-provisioning/aws/kubernetes/terraform/environments/staging/outputs.tf` (linhas 278-314)

### Documentation
- `/docs/logbook/2026-02-26-gap011-linkerd-blocked-staging-down.md` ← **ESTE ARQUIVO**
- `/docs/demands-backlog.md` (GAP-011 entry — pending update)
- `/docs/memory/MEMORY.md` (pending update pós-deploy)

---

## 9. Contact & Escalation

**Se apply falhar com erros críticos**:
- Verificar `/tmp/gap011-apply.log` para stacktrace completo
- Executar rollback plan (seção 5)
- Reportar ao orquestrador com:
  - Exit code do `terraform apply`
  - Últimas 50 linhas do `/tmp/gap011-apply.log`
  - Output de `kubectl get pods -n linkerd -o wide`
  - Output de `helm list -n linkerd`

**Se proxy injection test falhar**:
- Verificar MutatingWebhookConfiguration: `kubectl get mutatingwebhookconfiguration linkerd-proxy-injector -o yaml`
- Verificar certificados do webhook: `kubectl get secret -n linkerd linkerd-proxy-injector-k8s-tls -o yaml`
- Inspecionar eventos do pod: `kubectl describe pod nginx-linkerd-test -n linkerd-test`

**Se cluster Kubernetes permanecer offline >24h**:
- Considerar deploy em ambiente de desenvolvimento local (kind/minikube) para validação de módulo
- Preparar demo/PoC em ambiente isolado para apresentação de compliance BACEN

---

**STATUS FINAL**: ⏸️ BLOQUEADO — Aguardando ambiente staging online para executar deployment
**READY TO DEPLOY**: ✅ SIM — Todos os artefatos Terraform revisados e prontos
**ESTIMATED DEPLOYMENT TIME**: 30-40 minutos (Terraform apply + validações + proxy injection test)
