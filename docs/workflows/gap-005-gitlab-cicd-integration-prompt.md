# GAP-005: GitLab CI/CD Integration - Workflow Prompt

**Status**: 🟢 PRONTO PARA EXECUÇÃO
**Pré-requisitos**: ✅ GAP-002 (GitLab Fix) + ✅ GAP-004 (SonarQube) completos
**Duração Estimada**: 3h
**Custo**: $0 (já provisionado)

---

## 📋 Prompt para o Agente

```
Implemente o GAP-005: GitLab CI/CD Integration conforme especificação abaixo.

CONTEXTO:
- GitLab já está deployado em staging
- GitLab Runner precisa estar funcional (GAP-002 deve estar resolvido)
- SonarQube já está operacional (GAP-004)
- Harbor registry já está operacional
- Keycloak SSO já está operacional

OBJETIVO:
Integrar GitLab CI/CD com SonarQube e Harbor para pipeline completa (build → test → scan → deploy).

REQUISITOS TÉCNICOS:

1. GitLab Runner Validation:
   - Verificar pods gitlab-gitlab-runner running
   - Verificar registration no GitLab
   - RBAC namespace-scoped (não cluster-admin)
   - Testar job simples (echo "hello world")

2. CI/CD Variables Configuration:

   A. Harbor Registry:
   - HARBOR_URL: harbor.staging.svc.cluster.local
   - HARBOR_USER: <robot account>
   - HARBOR_PASSWORD: <from vault ou secret>

   B. SonarQube:
   - SONAR_HOST_URL: http://sonarqube.sonarqube.svc.cluster.local:9000
   - SONAR_TOKEN: <generate via SonarQube UI>

   C. ArgoCD (opcional):
   - ARGOCD_SERVER: argocd-server.argocd.svc.cluster.local
   - ARGOCD_AUTH_TOKEN: <from argocd>

3. Pipeline Templates (.gitlab-ci.yml):

   Criar 4 templates reusáveis:

   A. Build Template:
   ```yaml
   .build_template:
     stage: build
     image: docker:24-dind
     services:
       - docker:24-dind
     variables:
       DOCKER_TLS_CERTDIR: "/certs"
     script:
       - docker login $HARBOR_URL -u $HARBOR_USER -p $HARBOR_PASSWORD
       - docker build -t $HARBOR_URL/$CI_PROJECT_PATH:$CI_COMMIT_SHORT_SHA .
       - docker push $HARBOR_URL/$CI_PROJECT_PATH:$CI_COMMIT_SHORT_SHA
   ```

   B. Test Template:
   ```yaml
   .test_template:
     stage: test
     image: node:18-alpine  # ou maven:3.8-jdk-11, python:3.11, etc
     script:
       - npm install  # ou mvn test, pytest, etc
       - npm test
   ```

   C. Scan Template (SonarQube):
   ```yaml
   .sonar_scan_template:
     stage: scan
     image: sonarsource/sonar-scanner-cli:latest
     variables:
       SONAR_USER_HOME: "${CI_PROJECT_DIR}/.sonar"
       GIT_DEPTH: "0"
     script:
       - sonar-scanner
         -Dsonar.projectKey=$CI_PROJECT_PATH_SLUG
         -Dsonar.sources=.
         -Dsonar.host.url=$SONAR_HOST_URL
         -Dsonar.login=$SONAR_TOKEN
   ```

   D. Deploy Template (ArgoCD - opcional):
   ```yaml
   .deploy_template:
     stage: deploy
     image: argoproj/argocd:latest
     script:
       - argocd app sync $APP_NAME --server $ARGOCD_SERVER --auth-token $ARGOCD_AUTH_TOKEN
   ```

4. Example Project:
   - Criar projeto exemplo "hello-world-app"
   - Linguagem: Node.js ou Python (simples)
   - Dockerfile
   - .gitlab-ci.yml usando os 4 templates
   - sonar-project.properties

5. End-to-End Validation:
   - Commit → Trigger pipeline
   - Build: Docker image pushed to Harbor
   - Test: Unit tests passed
   - Scan: SonarQube analysis success
   - Quality Gate: Pass/Fail visible
   - Deploy: (opcional) ArgoCD sync

ENTREGÁVEIS:

1. GitLab Runner RBAC:
   - manifests/gitlab-runner-rbac.yaml
   - Role (não ClusterRole) com permissões mínimas
   - RoleBinding namespace-scoped

2. CI/CD Variables:
   - Documentar como configurar (GitLab UI ou API)
   - Script helper: scripts/gitlab/configure-ci-variables.sh

3. Pipeline Templates:
   - .gitlab/ci-templates/build.yml
   - .gitlab/ci-templates/test.yml
   - .gitlab/ci-templates/scan.yml
   - .gitlab/ci-templates/deploy.yml

4. Example Project:
   - examples/hello-world-app/
     - Dockerfile
     - .gitlab-ci.yml
     - sonar-project.properties
     - src/ (código exemplo)
     - tests/ (testes exemplo)

5. Documentação:
   - docs/guides/gitlab-ci-pipeline-setup.md
   - Logbook: docs/logbook/2026-02-0X-gitlab-ci-integration.md
   - Atualizar: modules/gitlab/README.md com CI/CD section

6. Validation Report:
   - Pipeline execution log
   - Harbor: image visible
   - SonarQube: analysis visible
   - Quality Gate status

CONSTRAINTS:

- GitLab Runner RBAC: namespace-scoped (não cluster-admin)
- Secrets: usar GitLab CI/CD variables (masked)
- Docker-in-Docker: usar dind service (não privileged host)
- SonarQube: quality gate deve bloquear merge se falhar
- Harbor: usar robot accounts (não admin)

WORKFLOW:

1. Validar GitLab Runner functional (GAP-002 resolvido)
2. Criar Harbor robot account para CI/CD
3. Gerar SonarQube token
4. Configurar GitLab CI/CD variables
5. Criar pipeline templates (.gitlab/ci-templates/)
6. Criar projeto exemplo hello-world-app
7. Commit código → Trigger pipeline
8. Validar build (Harbor image)
9. Validar test (logs GitLab)
10. Validar scan (SonarQube UI)
11. Validar quality gate (pass/fail)
12. Troubleshoot se necessário
13. Criar documentação
14. Atualizar demands-backlog.md (GAP-005 completo)

HARBOR ROBOT ACCOUNT:

```bash
# Criar robot account via Harbor UI
# Projects → library → Robot Accounts → New Robot Account
# Name: gitlab-ci
# Expiration: 365 days
# Permissions: Pull + Push images
# Copy token → armazenar em GitLab CI/CD variables
```

SONARQUBE TOKEN:

```bash
# Criar token via SonarQube UI
# Login → My Account → Security → Generate Tokens
# Name: gitlab-ci
# Type: Global Analysis Token
# Expiration: No expiration
# Copy token → armazenar em GitLab CI/CD variables
```

GITLAB CI/CD VARIABLES:

```bash
# Via UI: Settings → CI/CD → Variables → Add variable
# Ou via API:
curl --request POST \
  --header "PRIVATE-TOKEN: <gitlab-root-token>" \
  --form "key=HARBOR_URL" \
  --form "value=harbor.staging.svc.cluster.local" \
  --form "masked=false" \
  "https://gitlab.example.com/api/v4/admin/ci/variables"

# Repetir para todas variables necessárias
```

TROUBLESHOOTING COMUM:

1. Runner não pega jobs: verificar registration token
2. Docker build falha: verificar dind service running
3. Harbor push falha: verificar robot account permissions
4. SonarQube scan falha: verificar token e network connectivity
5. Quality gate não bloqueia: configurar SonarQube webhook
```

---

## 🎯 Critérios de Sucesso

- [ ] GitLab Runner pods running e functional
- [ ] RBAC namespace-scoped (não cluster-admin)
- [ ] Harbor robot account criado
- [ ] SonarQube token gerado
- [ ] GitLab CI/CD variables configuradas (4+)
- [ ] Pipeline templates criados (4)
- [ ] Projeto exemplo hello-world-app criado
- [ ] Pipeline end-to-end executada com sucesso:
  - [ ] Build: Docker image em Harbor
  - [ ] Test: Unit tests passed
  - [ ] Scan: SonarQube analysis complete
  - [ ] Quality Gate: Visible em SonarQube UI
- [ ] Documentação criada (guia + logbook)
- [ ] GAP-005 marcado como completo

---

## 🔧 Comandos Úteis

```bash
# Validar GitLab Runner
kubectl get pods -n gitlab -l app=gitlab-runner
kubectl logs -n gitlab -l app=gitlab-runner --tail=50

# Testar runner com job simples
# .gitlab-ci.yml:
# test:
#   script: echo "Hello World"

# Criar Harbor robot account (via UI)
# Harbor → Projects → library → Robot Accounts → New

# Criar SonarQube token (via UI)
# SonarQube → My Account → Security → Generate Tokens

# Configurar GitLab variables (via UI)
# GitLab → Admin → Settings → CI/CD → Variables

# Trigger pipeline manualmente
git commit --allow-empty -m "trigger pipeline"
git push

# Verificar pipeline
# GitLab → Project → CI/CD → Pipelines

# Verificar image em Harbor
# Harbor → Projects → library → Repositories

# Verificar análise SonarQube
# SonarQube → Projects → hello-world-app

# Verificar quality gate
# SonarQube → Projects → hello-world-app → Quality Gate
```

---

## 📚 Arquivos de Referência

- [GAP-005 Spec](../demands-backlog.md#gap-005)
- [GAP-002 GitLab Fix](../demands-backlog.md#gap-002)
- [Harbor Module](../../platform-provisioning/aws/kubernetes/terraform/modules/harbor/README.md)
- [SonarQube Module](../../platform-provisioning/aws/kubernetes/terraform/modules/sonarqube/README.md)
- [GitLab CI/CD Docs](https://docs.gitlab.com/ee/ci/)

---

## 📋 Example Project Structure

```
examples/hello-world-app/
├── .gitlab-ci.yml                # Pipeline usando templates
├── Dockerfile                    # Multi-stage build
├── sonar-project.properties      # SonarQube config
├── package.json                  # Node.js dependencies
├── src/
│   └── app.js                   # Código exemplo
└── tests/
    └── app.test.js              # Testes exemplo
```

**Example .gitlab-ci.yml**:

```yaml
include:
  - project: 'platform/ci-templates'
    file: '/templates/build.yml'
  - project: 'platform/ci-templates'
    file: '/templates/test.yml'
  - project: 'platform/ci-templates'
    file: '/templates/scan.yml'

stages:
  - test
  - build
  - scan

test:
  extends: .test_template

build:
  extends: .build_template
  needs: [test]

sonar:
  extends: .sonar_scan_template
  needs: [test]
```

---

## ⚠️ Avisos Importantes

1. **GitLab Runner RBAC**: Usar Role (não ClusterRole) para segurança
2. **Docker-in-Docker**: Requer `services: docker:dind` e volume `/var/run/docker.sock`
3. **Harbor Robot Account**: Expiration 365 dias, renovar anualmente
4. **SonarQube Quality Gate**: Configurar para bloquear merge se falhar
5. **Secrets**: NUNCA commitar tokens/passwords em código

---

## 🔄 Pipeline Flow

```
┌─────────┐
│  COMMIT │
└────┬────┘
     │
     ▼
┌─────────────┐
│   TEST      │ ← Unit tests
│  (Node.js)  │
└─────┬───────┘
      │
      ▼
┌─────────────┐     ┌──────────────┐
│   BUILD     │────▶│   HARBOR     │ Push image
│  (Docker)   │     │  (Registry)  │
└─────┬───────┘     └──────────────┘
      │
      ▼
┌─────────────┐     ┌──────────────┐
│   SCAN      │────▶│  SONARQUBE   │ Analysis
│ (SonarQube) │     │ (Quality)    │
└─────┬───────┘     └──────────────┘
      │
      ▼
┌─────────────┐
│ QUALITY GATE│ ← Pass/Fail
└─────┬───────┘
      │
      ▼
┌─────────────┐     ┌──────────────┐
│   DEPLOY    │────▶│   ARGOCD     │ Sync (opcional)
│  (ArgoCD)   │     │   (GitOps)   │
└─────────────┘     └──────────────┘
```

---

_Preparado em: 2026-02-06_
