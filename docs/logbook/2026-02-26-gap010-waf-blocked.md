# GAP-010 WAF Deployment - BLOCKED

**Data**: 2026-02-26 14:49-15:05 BRT
**Agente**: AWS Infrastructure Specialist
**Status**: ⛔ **BLOQUEADO** - Dependências quebradas

---

## Resumo Executivo

Deploy do módulo WAF está **BLOQUEADO** devido a erros críticos em outros módulos Terraform no mesmo workspace (linkerd e keycloak-clients). Terraform valida TODOS os módulos mesmo quando usando `-target`, impedindo plan/apply.

---

## Timeline Detalhada

### 14:49 - Análise Inicial ✅
- Módulo WAF revisado: estrutura OK (main.tf, variables.tf, outputs.tf, README.md)
- Integration em staging/main.tf: OK
- ALB target existe e está ACTIVE:
  - ARN: `arn:aws:elasticloadbalancing:us-east-1:891377105802:loadbalancer/app/k8s-platformstaging-00e0ecf3b4/1ef072a48e958803`
  - DNS: `k8s-platformstaging-00e0ecf3b4-279144409.us-east-1.elb.amazonaws.com`
  - State: active
- Cluster EKS: ACTIVE
- WAF WebACL existente: NENHUM (deploy fresh OK)

### 14:52 - Terraform Init ✅
```bash
Terraform has been successfully initialized!
```

### 14:53-15:02 - Terraform Plan ⛔ FAILED

**Tentativa 1**: Plan full
- Erro: Variável `vault_root_token` required sem valor

**Tentativa 2**: Plan com `-var="vault_root_token=dummy"`
- 3 erros críticos detectados em módulos não-relacionados:

#### Erro 1: Módulo linkerd - Dashboards faltando
```
Error: Invalid function argument
  on ../../modules/linkerd/main.tf line 430-433
  no file exists at:
    - ../../modules/linkerd/dashboards/linkerd-top-line.json
    - ../../modules/linkerd/dashboards/linkerd-service-mesh.json
    - ../../modules/linkerd/dashboards/linkerd-deployment.json
    - ../../modules/linkerd/dashboards/linkerd-namespace.json
```

#### Erro 2: Módulo keycloak-clients - Recursos não declarados
```
Error: Reference to undeclared resource
  on ../../modules/keycloak-clients/main.tf line 49
  keycloak_realm.platform not declared (+ 16 outros erros similares)
```

#### Erro 3: Módulo WAF - Warning (não bloqueante)
```
Warning: Invalid Attribute Combination
  with module.waf_staging.aws_s3_bucket_lifecycle_configuration.waf_logs
  No attribute specified when one of [rule[0].filter, rule[0].prefix] is required
  This will be an error in a future version
```

**Tentativa 3**: Plan com `-target=module.waf_staging`
- Mesmo erro: Terraform valida todos os módulos antes de aplicar targeting

---

## Root Cause Analysis

### Linkerd Module
- **Causa**: Dashboards JSON não criados
- **Localização**: `/modules/linkerd/dashboards/` (diretório vazio ou inexistente)
- **Impacto**: BLOQUEIA plan/apply global
- **Fix**: Criar os 4 arquivos JSON de dashboard OU comentar o ConfigMap no module

### Keycloak Clients Module
- **Causa**: Código refatorado incompletamente (realm e clients não declarados)
- **Localização**: `/modules/keycloak-clients/main.tf` linha 49 + outputs.tf
- **Impacto**: BLOQUEIA plan/apply global
- **Fix**: Corrigir estrutura do módulo (adicionar keycloak_realm.platform, etc.) OU comentar module call

### WAF Module S3 Lifecycle
- **Causa**: Deprecation no provider AWS - lifecycle rule sem filter/prefix
- **Localização**: `/modules/waf/main.tf` linha 72-90
- **Impacto**: WARNING apenas (não bloqueia), mas será erro em versão futura
- **Fix**: Adicionar `filter {}` no bloco rule

---

## Estado da Infraestrutura

### EKS Cluster
- Name: k8s-platform-prod
- Region: us-east-1
- Status: **ACTIVE**

### ALB Público (iPaaS)
- Name: k8s-platformstaging-00e0ecf3b4
- ARN: arn:aws:elasticloadbalancing:us-east-1:891377105802:loadbalancer/app/k8s-platformstaging-00e0ecf3b4/1ef072a48e958803
- DNS: k8s-platformstaging-00e0ecf3b4-279144409.us-east-1.elb.amazonaws.com
- State: **active**
- Tags: `kubernetes.io/cluster/k8s-platform-prod=owned`, `ingress.k8s.aws/stack=ipaas-public`

### WAF
- WebACL existente: **NENHUM**
- Módulo pronto: ✅ SIM
- Integration staging: ✅ SIM
- Bloqueio: ⛔ Dependências quebradas

---

## Opções de Desbloqueio

### OPÇÃO A: Fix Completo (Recomendada - 2-3h)
1. Criar dashboards JSON do Linkerd (4 arquivos)
2. Corrigir módulo keycloak-clients (estrutura realm + clients)
3. Corrigir warning WAF S3 lifecycle
4. Executar terraform plan + apply

**Prós**: Resolve problema raiz, desbloqueia futuro desenvolvimento
**Contras**: Tempo estimado 2-3h (fora do escopo GAP-010)

### OPÇÃO B: Bypass Temporário (Rápida - 15min)
1. Comentar `module "linkerd_staging"` em staging/main.tf
2. Comentar `module "keycloak_clients_staging"` em staging/main.tf
3. Aplicar fix WAF S3 lifecycle
4. Deploy WAF com terraform plan/apply
5. Descomentar módulos após deploy

**Prós**: Desbloqueia WAF imediatamente
**Contras**: Drift temporário, requer re-enable posterior

### OPÇÃO C: Workspace Isolado (Complexa - 1-2h)
1. Criar novo workspace Terraform apenas para WAF
2. Configurar backend S3 separado
3. Deploy isolado

**Prós**: Zero impacto em outros módulos
**Contras**: Overhead de gerenciamento, duplicação de state

---

## Recomendação

**ESCOLHER OPÇÃO B (Bypass Temporário)**:

1. Aplicar fix WAF S3 lifecycle (2min)
2. Comentar módulos quebrados temporariamente (1min)
3. Deploy GAP-010 WAF (10min terraform apply + validação)
4. Descomentar módulos (commit separado)
5. Abrir tickets para fix definitivo de linkerd + keycloak-clients

**Justificativa**:
- GAP-010 é demanda prioritária de segurança (DDoS protection)
- Módulos quebrados são problemas pré-existentes (não introduzidos por GAP-010)
- Fix completo está fora do escopo da demanda GAP-010
- Ambiente staging permite esse tipo de workaround controlado

---

## Próximos Passos (Aguardando Decisão Orquestrador)

1. **Se OPÇÃO A**: Criar demandas TASK-XXX para fix de linkerd e keycloak-clients
2. **Se OPÇÃO B**: Executar sequence de bypass + deploy WAF
3. **Se OPÇÃO C**: Setup de workspace isolado

---

## Artefatos

### Logs Terraform
- Plan log: `/tmp/gap010-plan-targeted.log`
- Error summary: Ver seção "Terraform Plan - Erro 1/2/3" acima

### Comandos Executados
```bash
# Init
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/environments/staging
terraform init -upgrade

# Unlock (após processo travado)
terraform force-unlock -force 249ec45d-a3d8-730e-e6b7-fed9508b6a57

# Plan attempts
terraform plan -target=module.waf_staging -var="vault_root_token=dummy" -out=gap010-waf.tfplan
```

### AWS Validations
```bash
# ALB check
aws elbv2 describe-load-balancers --region us-east-1 --profile k8s-platform-prod

# WAF check
aws wafv2 list-web-acls --scope REGIONAL --region us-east-1 --profile k8s-platform-prod

# EKS check
aws eks describe-cluster --name k8s-platform-prod --region us-east-1 --profile k8s-platform-prod
```

---

## Custo Estimado (Quando Deployado)

| Recurso | Custo Unitário | Estimativa Mensal |
|---------|----------------|-------------------|
| WAF WebACL | $5.00/mês | $5.00 |
| 5 Rule Groups | $1.00/rule/mês | $5.00 |
| Requests (10M) | $0.60/milhão | ~$1-3 |
| S3 Log Bucket | $0.023/GB | ~$1-2 |
| **TOTAL** | | **~$12-15/mês** |

---

**AGUARDANDO DECISÃO DO ORQUESTRADOR**
