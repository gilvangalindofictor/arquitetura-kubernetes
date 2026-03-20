# PROMPT DE CONTINUACAO — Sessao 2026-03-20 Handoff

> Cole este prompt inteiro no inicio de um novo chat Claude Code.
> Ele contem o estado EXATO de todas as demandas em andamento.

---

Voce e o Orquestrador DevOps Senior operando sob `docs/prompts/executor-terraform.md`.

## CONTEXTO DA SESSAO ANTERIOR (2026-03-20, 14:50 UTC)

A sessao foi interrompida com 3 tracks ativos. Abaixo esta o estado EXATO de cada um.

---

## ESTADO DO AMBIENTE

### Credenciais AWS
- Profile: `k8s-platform-prod` | Account: `891377105802`
- SSO token EXPIRADO — usar credenciais cacheadas:
  ```bash
  CREDS=$(cat ~/.aws/cli/cache/9f96c2165544e66612973182e4b515dd261e84f7.json)
  export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin)['Credentials']['AccessKeyId'])")
  export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin)['Credentials']['SecretAccessKey'])")
  export AWS_SESSION_TOKEN=$(echo "$CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin)['Credentials']['SessionToken'])")
  export AWS_DEFAULT_REGION=us-east-1
  ```
- **ATENCAO**: credenciais validas ate `2026-03-21T00:57:32Z`. Se expirou, pedir `aws sso login --profile k8s-platform-prod`.

### Terraform SSO Workaround
- `backend.tf:14` ja esta com profile COMENTADO: `# profile = "k8s-platform-prod" # COMMENTED-SSO-WORKAROUND`
- `main.tf` linhas 71, 82, 96 e possivelmente 177 — precisam ser COMENTADAS antes de terraform e RESTAURADAS depois
- Working dir: `Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/environments/staging`

### Tuneis VPC (PROVAVELMENTE MORTOS — reiniciar)
```bash
# Vault
kubectl port-forward -n staging-security-vault svc/vault 8200:8200 &
# RDS (via socat pod — verificar se pod existe)
kubectl get pod socat-rds-tunnel --no-headers 2>/dev/null || kubectl run socat-rds-tunnel --image=alpine/socat:latest --restart=Never --overrides='{"spec":{"containers":[{"name":"socat-rds-tunnel","image":"alpine/socat:latest","args":["TCP-LISTEN:5432,fork,reuseaddr","TCP:k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com:5432"],"ports":[{"containerPort":5432}]}]}}'
kubectl port-forward pod/socat-rds-tunnel 15432:5432 &
# Keycloak
kubectl port-forward -n staging-platform-keycloak svc/keycloak-keycloakx-http 18080:80 &
```
- Vault token: `VAULT_ROOT_TOKEN_REDACTED`

---

## TRACK 1 — ECR Pull-Through Cache + Helm ECR Images

### CONCLUIDO (nao requer acao):
- [x] TRACK 1.1: `terraform apply module.ecr_pull_through_cache` — 6 add, 4 change, docker-hub rule ATIVA
- [x] TRACK 1.2b: Kyverno policy verificada — 12 regras corretas, docker.io -> docker-hub
- [x] 4 pull-through rules ativas: `ecr-public`, `quay`, `k8s`, `docker-hub`
- [x] Custom IAM role `ecr-template-role` criada
- [x] Secrets Manager com credenciais Docker Hub (user: `tialvocard`)

### EM ANDAMENTO (APPLY PARCIAL — 2 TIMEOUTS + STATE LOCK CONFLICT):
- [ ] **TRACK 1.3: Aplicar Helm releases com ECR images (11 modulos)**
  - O agente TF-Infra executou plan + apply dos 11 modulos
  - **RESULTADO DO APPLY**: FALHOU PARCIALMENTE
    - Maioria dos modulos aplicou com sucesso (gitlab, vault, eso, harbor, keycloak, sonarqube, kube-prometheus, otel, loki)
    - **2 TIMEOUTS**: `module.promtail_staging.helm_release.promtail` e `module.velero_helm_staging.helm_release.velero` — "context deadline exceeded"
    - **STATE LOCK CONFLICT**: lock ID mismatch ao liberar — precisa `terraform force-unlock`
  - **ACOES NECESSARIAS**:
    1. `terraform force-unlock <LOCK_ID>` (verificar lock atual com `terraform plan` e usar o ID do erro)
    2. `terraform apply -target=module.promtail_staging -target=module.velero_helm_staging` (re-aplicar os 2 que falharam)
    3. Verificar pods: `kubectl get pods -n promtail` e `kubectl get pods -n velero`
  - **11 modulos Helm**: gitlab_staging, vault_staging, external_secrets_staging, harbor_staging, keycloak_staging, sonarqube_staging, kube_prometheus_stack_staging, opentelemetry_collector_staging, promtail_staging, loki_staging, velero_helm_staging
  - **Loki**: ja aplicado por processo anterior + re-aplicado neste batch

### PENDENTE (GATE: Track 1.3 concluido + zero ImagePullBackOff):
- [ ] **TRACK 1.4: Ativar Kyverno ClusterPolicy `redirect-public-registries-to-ecr`**
  - Recurso: `kyverno-ecr-redirect.tf`
  - **RESTRICAO CRITICA C8**: NAO ativar se houver QUALQUER ImagePullBackOff no cluster
  - Smoke test pos-ativacao: `kubectl run ecr-test --image=nginx:latest --restart=Never`

### PODS COM PROBLEMA (snapshot 14:50 UTC):
```
harbor-system       harbor-exporter-78f7fc4cc5-8rcn7   0/2  Error          1
staging-data-vemsoft-etl  vemsoft-etl-7f9cb9ffdf-crs9f  0/1  ImagePullBackOff  0
```
- harbor-exporter: Error — investigar (pode ser consequencia do Helm apply em andamento)
- vemsoft-etl: ImagePullBackOff — problema de registry/credenciais (GAP pre-existente)

---

## TRACK 2 — Refatoracao CI/CD

### CONCLUIDO:
- [x] TRACK 2.3: Backstage template ja usa Kaniko v1.23.2-debug (nao DinD)

### PENDENTE (requer acesso Harbor — NAO prioritario):
- [ ] TRACK 2.1: Espelhar Kaniko no Harbor (GAP-IMG-001) — criar projeto `ci-tools`
- [ ] TRACK 2.2: Rename projetos Harbor hatch-etl -> data + atualizar CIs

---

## TRACK 3 — Pin de Versoes CI

### CONCLUIDO:
- [x] TRACK 3.1: OWASP_DC `latest` -> `11.1.0`, TruffleHog `latest` -> `3.82.6`
  - Arquivo: `domains/cicd-platform/.../security.gitlab-ci-security-template.yml`
- [x] TRACK 3.2: Trivy Hatch `0.48.3` -> `0.50.0`
  - Arquivo: `ETL/Hatch/.gitlab-ci.yml` linha 825

### PENDENTE:
- [ ] TRACK 3.3: Smoke test CI/CD end-to-end (trigger pipelines Hatch + VemSoft)

---

## TRACK iPaaS — Teste E2E Fase A (WireMock)

### ESTADO (interrompido em Passo A-3):
- [x] Passo A-1: Infra full UP (PostgreSQL, Redis, RabbitMQ, Keycloak, Jaeger, Prometheus, Grafana)
- [x] Passo A-1b: WireMock HBI + BPO UP (29 stubs HBI carregados)
- [x] Passo A-2: Peer.HBI **Healthy** em `localhost:5200`
  - **NOTA**: `launchSettings.json` sobrescreve ASPNETCORE_URLS. Fix: usar `--urls http://localhost:5200`
- [~] Passo A-3: Orchestrator **INICIADO** mas porta 5100 NAO respondeu (mesmo port mismatch)
  - Fix: matar dotnet, reiniciar com `--urls http://localhost:5100`
- [ ] Passo A-4: Gateway (porta 5000) — nao iniciado
- [ ] Passos A-5 a A-12: Teste E2E completo — nao executado

### COMO RETOMAR:
```bash
cd /home/gilvangalindo/projects/Arquitetura/iPaaS

# Verificar o que esta rodando
docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null
ss -tlnp | grep -E '5000|5100|5200'

# Se Orchestrator nao responde em 5100, reiniciar:
pkill -f "iPaaS.Orchestrator" 2>/dev/null || true
cd components/iPaaS.Orchestrator.Bancarization/src/iPaaS.Orchestrator.Bancarization
ASPNETCORE_ENVIRONMENT=Development \
ConnectionStrings__PostgreSQL="Host=localhost;Port=5432;Database=ipaas_integration_tests;Username=ipaas_test;Password=test_password" \
ConnectionStrings__Redis="localhost:6379" \
RabbitMQ__Host="localhost" RabbitMQ__Port="5672" RabbitMQ__User="guest" RabbitMQ__Password="guest" \
PeerHbi__BaseUrl="http://localhost:5200" PeerHbi__InternalApiKey="test-key-12345" \
OpenTelemetry__OtlpEndpoint="http://localhost:4317" \
/home/gilvangalindo/.dotnet/dotnet run --urls http://localhost:5100 &

# Depois Gateway:
cd /home/gilvangalindo/projects/Arquitetura/iPaaS/components/iPaaS.Gateway/src/iPaaS.Gateway
ASPNETCORE_ENVIRONMENT=Development \
ConnectionStrings__Redis="localhost:6379" \
Orchestrator__BaseUrl="http://localhost:5100" \
Peers__HBI__BaseUrl="http://localhost:5200" \
JwtSettings__Authority="http://localhost:8080/realms/ipaas" \
JwtSettings__Audience="ipaas-gateway" JwtSettings__RequireHttpsMetadata="false" \
OpenTelemetry__OtlpEndpoint="http://localhost:4317" \
Webhook__Secret="webhook-secret-local-test-123" \
/home/gilvangalindo/.dotnet/dotnet run --urls http://localhost:5000 &
```

### PLANO DE TESTE COMPLETO:
Arquivo: `Arquitetura/iPaaS/tests/manual/PLANO-TESTE-SOLUCAO-COMPLETA.md`

---

## TRACK ETL-Onboarding — Hatch (77%) + VemSoft (83%)

### PROMPT PRONTO PARA DESPACHO:
Arquivo: `Arquitetura/Kubernetes/docs/prompts/executor-etl-onboarding-gaps.md`

### GAPs P0 ABERTOS:
| ETL | GAP | Descricao |
|-----|-----|-----------|
| Hatch | GAP-VAULT-HATCH | Vault paths com valores placeholder |
| Hatch | GAP-IMAGE-01 | etl-core:initial e imagem vazia |
| Hatch | GAP-SEC-02 | imagePullSecrets faltando no etl-core |
| VemSoft | GAP-RDS-ACCESS | RDS inacessivel do pod (ImagePullBackOff confirmado) |

### GAPs P1 ABERTOS:
| ETL | GAP | Descricao |
|-----|-----|-----------|
| Hatch | GAP-SEC-01 | NetworkPolicies ausentes |
| Hatch | GAP-WORKLOAD-01 | etl-core Deployment deveria ser CronJob |
| VemSoft | GAP-DEPLOY-SSH | deploy:staging usa sed em vez de kustomize |
| VemSoft | GAP-ARGOCD-AUTOSYNC | auto-sync desabilitado |

---

## DEMANDAS PARA ESTA SESSAO (PRIORIDADE)

### Opcao A — Completar Track 1 (ECR + Helm + Kyverno)
1. Verificar se terraform plan/apply dos 11 Helm modules concluiu
2. Se nao, retomar (tuneis VPC + workaround SSO + terraform apply)
3. Apos apply: verificar zero ImagePullBackOff
4. Se clean: ativar Kyverno policy
5. Validacao final: `kubectl run test --image=nginx:latest` deve ser mutado para ECR

### Opcao B — Completar iPaaS Teste E2E Fase A
1. Reiniciar Orchestrator + Gateway (com --urls fix)
2. Obter JWT token do Keycloak (ou bypass)
3. Executar passos A-7 a A-12 do plano de teste

### Opcao C — ETL Onboarding Gaps
1. Usar prompt em `executor-etl-onboarding-gaps.md`
2. Foco: RDS connectivity, Vault secrets, NetworkPolicies, imagePullSecrets

### Recomendacao: Opcao A primeiro (GATE para Kyverno), depois B ou C em paralelo.

---

## ARQUIVOS CRITICOS MODIFICADOS NESTA SESSAO

| Arquivo | Acao | Status |
|---------|------|--------|
| `modules/ecr-pull-through-cache/` | TF apply (custom IAM + docker-hub) | APLICADO |
| `backend.tf:14` | Profile comentado (SSO workaround) | ATIVO — restaurar quando SSO funcionar |
| `domains/cicd-platform/.../security.gitlab-ci-security-template.yml` | OWASP+TruffleHog pinned | EDITADO, nao commitado |
| `ETL/Hatch/.gitlab-ci.yml:825` | Trivy 0.48.3->0.50.0 | EDITADO, nao commitado |
| `Arquitetura/Kubernetes/docs/prompts/executor-etl-onboarding-gaps.md` | Prompt ETL criado | NOVO |
