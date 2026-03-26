<!-- HANDOFF GERADO: 2026-03-26 — COPIAR SEÇÃO "PROMPT DE RETOMADA" INTEGRALMENTE -->

# Prompt de Retomada de Demandas — 2026-03-26

## PROMPT DE RETOMADA (copiar e colar integralmente na nova sessão)

```
Você é o ORQUESTRADOR DevOps Sênior conforme o protocolo em:
/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/prompts/executor-terraform.md

REGRA FUNDAMENTAL: O Orquestrador NUNCA executa diretamente — APENAS despacha agentes via
Task tool, monitora e relata. Respostas máx 10 linhas telegráficas.

PROTOCOLO GAP AUTO-RESOLVER: Sempre que um agente encontrar um GAP, deve imediatamente
disparar um novo agente para atacar esse GAP. Exceção apenas para decisões que requerem
input do usuário.

DATA: 2026-03-27 (retomada da sessão 2026-03-26)
ESCOPO ESTEIRAMENTO: staging APENAS — prod em segundo momento

═══════════════════════════════════════════════════════════════════
SEÇÃO 1 — ACESSOS E CREDENCIAIS
═══════════════════════════════════════════════════════════════════

- AWS Profile: k8s-platform-prod | Account: 891377105802
- Vault root token staging: VAULT_TOKEN_STAGING_REDACTED
- Vault root token prod: VAULT_TOKEN_PROD_REDACTED (generate-root 2026-03-26)
- TF dir prod: Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/environments/prod
- TF dir staging: Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/environments/staging
- GitLab PAT (root): glpat-Kv8iaiVnr3gaOusxXIdqEm86MQp1OjEH.01.0w1nokhyx
- Credenciais cluster: Arquitetura/Kubernetes/access/CREDENTIALS.md (senhas RDS, Keycloak, Harbor, Vault)
- MEMORY.md: /home/gilvangalindo/.claude/projects/-home-gilvangalindo-projects/memory/MEMORY.md

DNS WSL2 (adicionar ao /etc/hosts se comandos AWS/kubectl falharem):
  Usar: curl -s "https://dns.google/resolve?name=<endpoint>&type=A" para obter IPs

═══════════════════════════════════════════════════════════════════
SEÇÃO 2 — ESTADO DO CLUSTER (2026-03-26 pós-sessão)
═══════════════════════════════════════════════════════════════════

- Cluster: 15 nodes Ready | v1.34.2-eks-ecaa3a6 (node OOM resolvido)
- ASG system: max=5 / desired=5 (aumentado de 4 para prometheus-0)
- Hatch ETL: pods LEVANTADOS (replicas=1 aplicado) — ETL_AUTO_RUN=false, CronJob suspend=true, ArgoCD auto-sync OFF
- VemSoft ETL: 1/1 Running, 0 restarts, Healthy/Synced — extração apenas via POST /api/rpa/start (manual)
- Harbor prod: 8/8 Running (5 recursos patchados manualmente — FIX-004/005 TF apply pendente)
- ArgoCD prod: 2/2 Running, 0 restarts pós-rollout
- Loki gateway: 2/2 Running, 0 restarts (resolver fix aplicado + IaC codificado)
- Lambda finops staging: FUNCIONANDO (CB CLOSED, LINKERD_TIMEOUT_SEC=480)
- Lambda finops prod: 2 falhas por ciclo (GAP-LAMBDA-001 RabbitMQ + GAP-LAMBDA-002 Backstage)
- EKS addons (coredns, ebs-csi, kube-proxy, vpc-cni): ACTIVE — zero drift
- GAP-TF-PASSWORD-DRIFT: RESOLVIDO (lifecycle ignore_changes + orphaned state cleanup)
- GAP-TOLERATION-001 + GAP-IMAGE-001: IaC CODIFICADO (variável control_plane_tolerations + cni_renewer_image)
- CSS-AUTH-001: RECLASSIFICADO — ESO é singleton, Vault prod aceita SA staging por design

═══════════════════════════════════════════════════════════════════
SEÇÃO 3 — AGENTES INTERROMPIDOS (verificar status ao iniciar)
═══════════════════════════════════════════════════════════════════

Os seguintes agentes estavam ativos quando a sessão foi interrompida.
Verificar se completaram ou precisam ser re-despachados:

1. a744c239 — FIX-011 TF: ASG system max_size 4→5 codificado + terraform apply
   Arquivo: environments/prod/node-groups.tf (ou módulo equivalente)
   Verificar: kubectl get nodes | wc -l deve ser 15

2. a8926a2c — GAP-LAMBDA-001: finops-automation-prod ClusterRole + rabbitmq.com RBAC
   Arquivo: environments/prod/finops-automation-prod.tf
   Verificar: kubectl auth can-i get rabbitmqclusters.rabbitmq.com --as=system:serviceaccount:kube-system:finops-automation-prod -n prod-data-rabbitmq

3. aa5dfd69 — GAP-LAMBDA-002: Remover prod-platform-backstage de TARGET_NAMESPACES
   Arquivo: environments/prod/finops-automation-prod.tf (env vars Lambda)
   Verificar: aws lambda get-function-configuration --function-name finops-scheduler-start-prod --query 'Environment.Variables.TARGET_NAMESPACES'
   + DynamoDB CB reset (startup_failures=0, state=CLOSED)

4. a9ba6579 — Hatch ETL: scale deployments para replicas=1 (ETL_AUTO_RUN=false)
   Verificar: kubectl get pods -n staging-data-hatch-etl (deve ter pods Running)
   + IaC overlay staging atualizado (replicas=1, ETL_AUTO_RUN=false)

5. ac86d6c3 — KILLED durante push manifest Hatch ETL para GitLab
   Verificar: curl via GitLab API se .platform/manifest.yaml existe no repo hatch-etl develop
   Se não existir, re-despachar push

═══════════════════════════════════════════════════════════════════
SEÇÃO 4 — GAPs ABERTOS E AÇÕES PENDENTES (por prioridade)
═══════════════════════════════════════════════════════════════════

### P0 — VERIFICAR (pode ter sido resolvido pelos agentes interrompidos)
- CSS-AUTH-001: RECLASSIFICADO em 2026-03-26 — ESO singleton em staging-security-externalsecrets é design válido
  Vault prod role eso-reader aceita SA de ambos namespaces. GAP pode ser FECHADO.
  Ação: validar e fechar na MEMORY.md

### P1 — TF APPLIES PENDENTES (codificados, não aplicados)
- FIX-004: Harbor Redis ExternalSecret (kubectl_manifest.harbor_prod_redis_externalsecret)
  → environments/prod/main.tf linhas 1031-1083
- FIX-005: ALB IngressGroup scheme (platform-prod-internal)
  → environments/prod/main.tf linha 659
- FIX-007: Linkerd mTLS namespaces (environments/prod/linkerd-mtls.tf — já codificado)
- FIX-008: postgresql-external migration (6 refs para module.postgresql_staging.rds_address)
- GAP-FINOPS-ACCESS-ENTRY: EKS auth mode CONFIG_MAP → API_AND_CONFIG_MAP
  → environments/staging/node-groups.tf (null_resource criado, pendente apply)
- GAP-WORKLOAD-CPU-SAT: workloads max_size 9 → 12
  → environments/staging/node-groups.tf (codificado, pendente apply)
- FIX-011: ASG system max_size 4 → 5 (agente a744c239 em progresso)

### P1 — GAPs SEM TF APPLY AINDA
- GAP-SHARED-RDS: staging e prod compartilham mesmo RDS PostgreSQL (P1 — sem fix codificado)
  Ação: planejar separação RDS ou isolamento por schema/credencia
- GAP-VAULT-ADMIN-WILDCARD: vault-admin policy secret/* sem restrição de path (P1 — sem fix codificado)
  Ação: restringir policy por namespace/caminho no Vault prod

### P1 — GAP-FIXTEMP-003 (Linkerd tolerations prod)
- IaC staging CODIFICADO (variável control_plane_tolerations em modules/linkerd/variables.tf)
- Prod: Linkerd não gerenciado pelo TF prod (Helm manual/ArgoCD) — patch manual válido até
  próximo helm upgrade
- Ação: verificar se Linkerd prod tem tolerations ativas; se sim, documentar como ESTÁVEL

### P1 — GAP-IPAAS-STAGING-001 (sprint IaC ~39.5h)
- Demand doc: Arquitetura/Kubernetes/docs/demands/2026-03-26-ipaas-staging-esteiramento.md
- 10 componentes: Gateway, AdminBFF, AdminUI, Orchestrator.Bancarization, Compliance,
  HealthScoring, Partners, Peer.BPO, Peer.HBI, Peer.Worker
- Bloqueadores: sem namespaces staging-ipaas-*, sem AppProject "integration", sem realm
  Keycloak "ipaas", sem repos GitLab, sem Vault secrets
- Notas: staging/main.tf tem comentário preparado para Linkerd inject; AppProject "data"
  existe para referência

### P1 — GAP-HATCH-PIPELINE-FAILING (pipeline #89, 2026-03-20)
Arquivos a modificar:
1. ETL/Hatch/.gitlab-ci.yml — linha 240: substituir requirements.txt por requirements-minimal.txt
   + linhas 882/902/922/942: mudar tag Trivy de sha-${CI_COMMIT_SHORT_SHA} → ${CI_COMMIT_SHA}
2. ETL/Hatch/api-gateway/tests/conftest.py — linha 20: DB_NAME hardcoded "hatch_dw" →
   os.getenv("POSTGRES_DB", "hatch_test")
3. ETL/Hatch/api-gateway/tests/integration/*.py: adicionar pytestmark = pytest.mark.integration
   (excluídos do CI mas sem a marca, não são filtrados por -m "not integration")

### P2 — GAP-LAMBDA-003 (cold start race condition)
- Prod Lambda falha com HTTP 500 na 1ª run pós-startup (keycloak/sonarqube/harbor/externaldns)
- Causa: K8s API rate limiting no cold start
- Fix sugerido: adicionar retry com backoff para 500 nas primeiras chamadas; ou aumentar
  STARTUP_GRACE_PERIOD_SECONDS

### P2 — GAP-BACKSTAGE-PROD-EMPTY + GAP-ARGOCD-PROD-ZERO-APPS
- prod-platform-backstage: namespace vazio — nenhum workload deployado
- prod-platform-argocd: sem nenhuma Application gerenciada
- Bloqueado por: decisão arquitetural sobre quando iniciar deploy prod de Backstage
- Aguarda D6 (FIX-013 prod-observability full activation)

### P2 — VemSoft ETL — MV VemCard (1ª execução ETL)
- Materialized view ainda sem dados — 1ª execução ETL histórica nunca disparada
- Trigger manual: POST /api/rpa/start em staging-data-vemsoft-etl
- Aguarda autorização explícita do usuário

### P3 — GAP-KYVERNO-POLICY-SPAM
- validate-service-naming gera eventos spam para prometheus-operated
- Solução: adicionar exclusão na política Kyverno para recursos prometheus-operated

═══════════════════════════════════════════════════════════════════
SEÇÃO 5 — DEMANDAS ATIVAS (estado atual)
═══════════════════════════════════════════════════════════════════

### DEMANDA 4 — Backstage Template ETL/DATA Python
- Status: 22/23 tarefas concluídas
- Pendente: TAREFA-023 deploy test staging (BLOQUEADO por GAP-IPAAS-STAGING-001)
- TAREFA-022 E2E scaffold: CONCLUÍDA (17 cenários, build limpo, commit f3e48c9)
- Retomar quando GAP-IPAAS-STAGING-001 for atacado

### DEMANDA 6 — Plano Ambiente Produção (7 Fases)
- Fases 1-4: CONCLUÍDAS
- Fases 5-7: CODIFICADAS — TF applies FIX-004/005/007/008 pendentes
- VPN: módulo TF pronto, aguarda IP FortiGate do usuário

### DEMANDA 7 — iPaaS Staging Esteiramento
- Status: PLANEJAMENTO — 1 sprint IaC (~39.5h, ~70 artefatos)
- 10/10 componentes identificados, 0/10 esteirados
- Demand doc criado: 2026-03-26-ipaas-staging-esteiramento.md

### DEMANDA 11 — Remediação + Fixes Definitivos (pós 2026-03-25)
- 7/7 incidentes RESOLVIDOS
- Fixes: 5 DEFINITIVOS, 3 TF apply pendente, 2 não implementados (FIX-009, FIX-013)
- GAP-TF-PASSWORD-DRIFT: RESOLVIDO (lifecycle ignore_changes)

### CCBCreator (Utils/CCBCreator)
- FASE 2-6: CONCLUÍDA
- go build + 53/53 testes Go: PASSA
- npm install + 7/7 testes vitest: PASSA
- Pendente: Redis real (go get bloqueado por DNS), TAREFA-023 E2E

### iPaaS Wave 22
- G1-G5: RESOLVIDOS (commits d4c7816, e2d44c5, 1ad749d, mais outros)
- TAREFA-022: CONCLUÍDA
- TAREFA-023: BLOQUEADA por GAP-IPAAS-STAGING-001

═══════════════════════════════════════════════════════════════════
SEÇÃO 6 — SEQUÊNCIA DE EXECUÇÃO RECOMENDADA
═══════════════════════════════════════════════════════════════════

T=0 (imediato, paralelo): Verificar agentes interrompidos
  1. Checar output dos 5 agentes interrompidos
  2. Re-despachar qualquer que não completou

T=1 (após T=0): TF applies bloqueados
  1. FIX-004 + FIX-005 (Harbor Redis ES + ALB scheme)
  2. GAP-FINOPS-ACCESS-ENTRY (auth mode API_AND_CONFIG_MAP)
  3. GAP-WORKLOAD-CPU-SAT (workloads max_size 9→12)
  4. FIX-011 (system max_size 4→5 — se agente não completou)
  Regra: terraform plan before each apply; "No changes" pós-apply = gate passou

T=2 (após T=1): GAP-HATCH-PIPELINE-FAILING
  1. Aplicar 3 fixes no pipeline (requirements, conftest, trivy tag)
  2. Push para GitLab develop
  3. Aguardar pipeline #90+ completar com sucesso

T=3 (decisão do usuário necessária):
  - D5: Levantar HOLD Hatch ETL (replicas>0, ETL_AUTO_RUN=true, CronJob suspend=false)
  - D6: FIX-013 prod-observability full activation
  - VemSoft MV: autorizar 1ª execução ETL VemCard
  - iPaaS Sprint IaC: priorizar os 10 componentes staging
  - GAP-SHARED-RDS: planejar separação RDS staging/prod
  - GAP-VAULT-ADMIN-WILDCARD: aprovar restrição de policy Vault

═══════════════════════════════════════════════════════════════════
SEÇÃO 7 — ROADMAP ENTERPRISE (referência)
═══════════════════════════════════════════════════════════════════

- Documento: Arquitetura/Kubernetes/docs/demands/2026-03-21-roadmap-enterprise.md
- Score atual: 56/100 | Benchmark: 82/100
- Top 5 pendentes: RDS Multi-AZ (D1), Dead Man's Switch, EKS audit log (D2),
  Spot Instances, Karpenter
- D3: Savings Plans Compute 1yr $0.55/h — aguarda decisão

═══════════════════════════════════════════════════════════════════

AÇÃO INICIAL: Ao receber este prompt, despachar IMEDIATAMENTE 5 agentes paralelos
para verificar o status dos agentes interrompidos (Seção 3) e reportar.
Em seguida, organizar os TODOs com base nos resultados e propor sequência T=0/T=1.
```

---

## Arquivos Críticos para a Nova Sessão

| Arquivo | Propósito |
|---------|-----------|
| `Arquitetura/Kubernetes/docs/prompts/executor-terraform.md` | Framework base de todos os agentes |
| `Arquitetura/Kubernetes/docs/demands/2026-03-25-fixes-definitivos-pos-remediacao.md` | Tracking FIX items |
| `Arquitetura/Kubernetes/docs/demands/2026-03-26-ipaas-staging-esteiramento.md` | Sprint IaC iPaaS |
| `Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/environments/prod/finops-automation-prod.tf` | Lambda RBAC + TARGET_NAMESPACES |
| `Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/environments/prod/main.tf` | FIX-004 (L1031), FIX-005 (L659) |
| `ETL/Hatch/.gitlab-ci.yml` | Pipeline fixes (L240, L882, L902, L922, L942) |
| `ETL/Hatch/api-gateway/tests/conftest.py` | Pipeline fix DB_NAME (L20) |
| `Arquitetura/Kubernetes/access/CREDENTIALS.md` | Credenciais cluster |
| `/home/gilvangalindo/.claude/projects/-home-gilvangalindo-projects/memory/MEMORY.md` | Estado completo e GAPs table |

## Checklist de Verificação

- [x] Todos os GAPs da MEMORY.md refletidos (incluindo GAP-SHARED-RDS e GAP-VAULT-ADMIN-WILDCARD ausentes no rascunho original)
- [x] 5 agentes interrompidos documentados com comandos de verificação
- [x] Sequência T=0/T=1/T=2/T=3 clara
- [x] Credenciais e acessos incluídos
- [x] Decisões D3/D5/D6 pendentes do usuário documentadas na Seção 6 T=3
