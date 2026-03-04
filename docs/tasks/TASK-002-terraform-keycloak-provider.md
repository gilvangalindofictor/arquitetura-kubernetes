# TASK-002: Implementar Terraform Keycloak Provider

**Prioridade:** ✅ CONCLUÍDA (era 🟡 ALTA)
**Estimativa:** 3-4 horas
**Esforço Real:** ~4h (import + 4 bug fixes)
**Responsável:** Agente TF Specialist (executor-terraform.md framework)
**Criado:** 2026-02-12
**Devido:** 2026-02-15 (3 dias)
**Concluído:** 2026-03-04
**Dependências:** Nenhuma
**Bloqueio para:** TASK-001 (ArgoCD upgrade - preferencial usar TF para PKCE)

> ✅ **CONCLUÍDO 2026-03-04**: 11/11 recursos importados, zero drift. Módulo `module.keycloak_clients_staging`
> re-enabled em `environments/staging/main.tf`. 4 bugs estruturais fixados.

---

## ✅ RESULTADO FINAL (2026-03-04)

**11/11 recursos importados com zero drift:**
1. `keycloak_realm.platform`
2. `keycloak_openid_client.gitlab[0]`
3. `keycloak_openid_client.argocd[0]` (com `pkce_code_challenge_method = "S256"`)
4. `keycloak_openid_client.grafana[0]`
5. `keycloak_openid_client.harbor[0]` (PKCE S256)
6. `keycloak_openid_client.vault[0]` (PKCE S256)
7. `keycloak_saml_client.sonarqube[0]`
8. `keycloak_group.grafana_admins[0]`
9. `keycloak_generic_protocol_mapper.grafana_groups[0]`
10. `keycloak_saml_user_attribute_protocol_mapper.sonarqube_email[0]`
11. `keycloak_saml_user_property_protocol_mapper.sonarqube_name[0]`

**4 Bugs estruturais fixados:**
1. **TF não inclui subdirs**: `.tf` files em `clients/` e `realms/` ignorados → symlinks criados no root do módulo
2. **base_path errado**: `""` → `"/auth"` (keycloakx 7.1.7 requer `/auth` prefix)
3. **SAML mapper type errado**: `keycloak_saml_user_attribute_protocol_mapper` para `email` (propriedade, não atributo) → `keycloak_saml_user_property_protocol_mapper`
4. **Import format mappers**: deve ser `realm/client/{clientUUID}/{mapperUUID}` (não `realm/{clientUUID}/{mapperUUID}`)

---

---

## 📋 Contexto

**Problema Atual:**
- Clients Keycloak (gitlab, argocd) criados manualmente via SQL INSERT (2026-02-11)
- Causou bugs: `not_before` NULL, PKCE attributes faltando
- Zero Infrastructure as Code para identity management
- Drift não detectado entre state desejado vs realidade

**Motivação:**
- **Eliminação de erro humano:** Schema validation automática
- **Auditabilidade:** Git history de mudanças em clients
- **Idempotência:** Safe to re-apply, state tracking
- **Consistency:** Padrões aplicados a todos clients

**Referências:**
- [Logbook OIDC Troubleshooting](../logbook/2026-02-12-keycloak-oidc-integration-troubleshooting.md) - Manual SQL causou produção issue
- [MEMORY.md](/.claude/memory/MEMORY.md) - "NUNCA criar clients via SQL manual"

---

## 🎯 Objetivos

### Objetivo Principal
Implementar Terraform module para gerenciar Keycloak realms, clients, users e roles via Infrastructure as Code.

### Objetivos Secundários
- [ ] Migrar clients existentes (gitlab, argocd) para Terraform state
- [ ] Criar workflow CI/CD para Terraform apply automático
- [ ] Documentar padrões de criação de OIDC clients
- [ ] Validar state contra database (drift detection)

---

## 📝 Tarefas

### 1. Setup Provider e Módulo Base (1h)

- [ ] **1.1** Criar estrutura Terraform
  ```bash
  cd platform-provisioning/aws/kubernetes/terraform/modules
  mkdir -p keycloak/{clients,realms,users}

  # Estrutura esperada:
  # keycloak/
  # ├── main.tf
  # ├── variables.tf
  # ├── outputs.tf
  # ├── versions.tf
  # ├── clients/
  # │   ├── gitlab.tf
  # │   └── argocd.tf
  # ├── realms/
  # │   └── platform.tf
  # └── users/
  #     └── service-accounts.tf
  ```

- [ ] **1.2** Configurar Keycloak provider
  ```hcl
  # versions.tf
  terraform {
    required_version = ">= 1.5.0"

    required_providers {
      keycloak = {
        source  = "mrparkers/keycloak"
        version = "~> 4.4.0"
      }
    }
  }

  # main.tf
  provider "keycloak" {
    client_id     = "terraform"
    client_secret = var.keycloak_terraform_client_secret
    url           = "http://keycloak-http.keycloak.svc.cluster.local"
    realm         = "master"
  }
  ```

- [ ] **1.3** Criar client Terraform no Keycloak
  ```bash
  # Via kcadm.sh CLI (one-time setup)
  kubectl exec -n keycloak keycloak-0 -- /opt/keycloak/bin/kcadm.sh config credentials \
    --server http://localhost:8080/auth \
    --realm master \
    --user admin \
    --password admin

  kubectl exec -n keycloak keycloak-0 -- /opt/keycloak/bin/kcadm.sh create clients \
    -r master \
    -s clientId=terraform \
    -s enabled=true \
    -s serviceAccountsEnabled=true \
    -s 'redirectUris=["http://localhost"]' \
    -s 'attributes={"access.token.lifespan":"3600"}'

  # Get client secret
  kubectl exec -n keycloak keycloak-0 -- /opt/keycloak/bin/kcadm.sh get clients/<client-uuid>/client-secret \
    -r master

  # Store in Vault or AWS Secrets Manager
  ```

- [ ] **1.4** Testar conectividade provider
  ```hcl
  # test.tf (temporary)
  data "keycloak_realm" "master" {
    realm = "master"
  }

  output "master_realm_id" {
    value = data.keycloak_realm.master.id
  }
  ```

  ```bash
  terraform init
  terraform plan
  # Expected: Successfully read realm data
  ```

### 2. Migrar Clients Existentes (1.5h)

- [ ] **2.1** Import realm "platform"
  ```hcl
  # realms/platform.tf
  resource "keycloak_realm" "platform" {
    realm             = "platform"
    enabled           = true
    display_name      = "Platform Services"
    display_name_html = "<b>Platform Services</b>"

    # Login settings
    login_with_email_allowed = true
    duplicate_emails_allowed = false

    # Session settings
    sso_session_idle_timeout = "30m"
    sso_session_max_lifespan = "10h"

    # Security
    password_policy = "length(12) and upperCase(1) and lowerCase(1) and digits(1) and specialChars(1)"
  }
  ```

  ```bash
  # Import existing realm
  terraform import 'keycloak_realm.platform' platform
  ```

- [ ] **2.2** Import client "gitlab"
  ```hcl
  # clients/gitlab.tf
  resource "keycloak_openid_client" "gitlab" {
    realm_id  = keycloak_realm.platform.id
    client_id = "gitlab"
    name      = "GitLab OIDC"

    enabled                      = true
    standard_flow_enabled        = true
    implicit_flow_enabled        = false
    direct_access_grants_enabled = false
    service_accounts_enabled     = false

    access_type = "CONFIDENTIAL"

    valid_redirect_uris = [
      "http://gitlab.staging.internal/users/auth/openid_connect/callback",
      "https://gitlab.prod.internal/users/auth/openid_connect/callback"
    ]

    web_origins = [
      "http://gitlab.staging.internal",
      "https://gitlab.prod.internal"
    ]

    # PKCE Configuration (CRITICAL for security)
    pkce_code_challenge_method = "S256"

    # Lifecycle
    lifecycle {
      prevent_destroy = true  # Safety: prevent accidental deletion
    }
  }

  # Client secret (managed separately via Vault)
  resource "keycloak_openid_client_secret" "gitlab" {
    realm_id  = keycloak_realm.platform.id
    client_id = keycloak_openid_client.gitlab.id
  }

  # Store secret in Kubernetes
  resource "kubernetes_secret" "gitlab_oidc" {
    metadata {
      name      = "gitlab-oidc-keycloak"
      namespace = "gitlab-staging"
    }

    data = {
      client_id     = keycloak_openid_client.gitlab.client_id
      client_secret = keycloak_openid_client_secret.gitlab.value
    }
  }
  ```

  ```bash
  # Get existing client ID
  CLIENT_ID=$(kubectl exec -n keycloak keycloak-0 -- psql \
    postgresql://postgres_admin:PASSWORD@HOST:5432/keycloak?sslmode=require \
    -tA -c "SELECT id FROM client WHERE client_id = 'gitlab'")

  # Import to Terraform
  terraform import 'keycloak_openid_client.gitlab' "platform/${CLIENT_ID}"
  ```

- [ ] **2.3** Import client "argocd"
  ```hcl
  # clients/argocd.tf
  resource "keycloak_openid_client" "argocd" {
    realm_id  = keycloak_realm.platform.id
    client_id = "argocd"
    name      = "ArgoCD OIDC"

    enabled                      = true
    standard_flow_enabled        = true
    implicit_flow_enabled        = false
    direct_access_grants_enabled = false
    service_accounts_enabled     = false

    access_type = "CONFIDENTIAL"

    valid_redirect_uris = [
      "http://argocd.staging.internal/auth/callback",
      "http://localhost:8080/auth/callback",
      "https://argocd.*.amazonaws.com/auth/callback"
    ]

    web_origins = [
      "http://argocd.staging.internal"
    ]

    # PKCE: DISABLED for ArgoCD v2.9.3 (no PKCE support)
    # TODO: Enable after TASK-001 (ArgoCD upgrade v2.12+)
    pkce_code_challenge_method = ""

    # Backchannel logout
    backchannel_logout_session_required = true
    backchannel_logout_revoke_offline_sessions = false

    # Lifecycle
    lifecycle {
      prevent_destroy = true
    }
  }

  resource "keycloak_openid_client_secret" "argocd" {
    realm_id  = keycloak_realm.platform.id
    client_id = keycloak_openid_client.argocd.id
  }

  resource "kubernetes_secret" "argocd_oidc" {
    metadata {
      name      = "argocd-oidc-keycloak"
      namespace = "argocd"
    }

    data = {
      client_id     = keycloak_openid_client.argocd.client_id
      client_secret = keycloak_openid_client_secret.argocd.value
    }
  }
  ```

- [ ] **2.4** Validar import completo
  ```bash
  # Plan should show zero changes (in-sync)
  terraform plan

  # Expected output:
  # No changes. Your infrastructure matches the configuration.
  ```

### 3. Criar Template de Client (30min)

- [ ] **3.1** Criar módulo reutilizável
  ```hcl
  # modules/keycloak/client-oidc/main.tf
  variable "realm_id" { type = string }
  variable "client_id" { type = string }
  variable "client_name" { type = string }
  variable "redirect_uris" { type = list(string) }
  variable "web_origins" { type = list(string) }
  variable "enable_pkce" { type = bool, default = true }
  variable "k8s_namespace" { type = string }

  resource "keycloak_openid_client" "this" {
    realm_id  = var.realm_id
    client_id = var.client_id
    name      = var.client_name

    enabled                      = true
    standard_flow_enabled        = true
    implicit_flow_enabled        = false
    direct_access_grants_enabled = false
    service_accounts_enabled     = false

    access_type = "CONFIDENTIAL"

    valid_redirect_uris = var.redirect_uris
    web_origins         = var.web_origins

    pkce_code_challenge_method = var.enable_pkce ? "S256" : ""

    lifecycle {
      prevent_destroy = true
    }
  }

  resource "keycloak_openid_client_secret" "this" {
    realm_id  = var.realm_id
    client_id = keycloak_openid_client.this.id
  }

  resource "kubernetes_secret" "this" {
    metadata {
      name      = "${var.client_id}-oidc-keycloak"
      namespace = var.k8s_namespace
    }

    data = {
      client_id     = keycloak_openid_client.this.client_id
      client_secret = keycloak_openid_client_secret.this.value
      issuer        = "http://keycloak.staging.internal/auth/realms/${var.realm_id}"
    }
  }

  output "client_id" { value = keycloak_openid_client.this.client_id }
  output "client_secret" { value = keycloak_openid_client_secret.this.value, sensitive = true }
  ```

- [ ] **3.2** Exemplo de uso
  ```hcl
  # Example: Grafana OIDC client
  module "grafana_oidc" {
    source = "../../modules/keycloak/client-oidc"

    realm_id      = keycloak_realm.platform.id
    client_id     = "grafana"
    client_name   = "Grafana OIDC"
    k8s_namespace = "monitoring"

    redirect_uris = [
      "http://grafana.staging.internal/login/generic_oauth"
    ]

    web_origins = [
      "http://grafana.staging.internal"
    ]

    enable_pkce = true  # Grafana 10+ supports PKCE
  }
  ```

### 4. CI/CD e Validação (1h)

- [ ] **4.1** Criar workflow GitHub Actions
  ```yaml
  # .github/workflows/terraform-keycloak.yml
  name: Terraform Keycloak

  on:
    pull_request:
      paths:
        - 'platform-provisioning/aws/kubernetes/terraform/modules/keycloak/**'
    push:
      branches: [main]
      paths:
        - 'platform-provisioning/aws/kubernetes/terraform/modules/keycloak/**'

  jobs:
    terraform:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4

        - name: Setup Terraform
          uses: hashicorp/setup-terraform@v3
          with:
            terraform_version: 1.5.0

        - name: Terraform Format
          run: terraform fmt -check -recursive

        - name: Terraform Init
          run: terraform init
          working-directory: platform-provisioning/aws/kubernetes/terraform/modules/keycloak

        - name: Terraform Validate
          run: terraform validate
          working-directory: platform-provisioning/aws/kubernetes/terraform/modules/keycloak

        - name: Terraform Plan
          if: github.event_name == 'pull_request'
          run: terraform plan -no-color
          working-directory: platform-provisioning/aws/kubernetes/terraform/modules/keycloak
          env:
            TF_VAR_keycloak_terraform_client_secret: ${{ secrets.KEYCLOAK_TERRAFORM_CLIENT_SECRET }}

        - name: Terraform Apply
          if: github.ref == 'refs/heads/main' && github.event_name == 'push'
          run: terraform apply -auto-approve
          working-directory: platform-provisioning/aws/kubernetes/terraform/modules/keycloak
          env:
            TF_VAR_keycloak_terraform_client_secret: ${{ secrets.KEYCLOAK_TERRAFORM_CLIENT_SECRET }}
  ```

- [ ] **4.2** Criar script drift detection
  ```bash
  # scripts/keycloak-drift-check.sh
  #!/bin/bash
  set -euo pipefail

  echo "🔍 Checking Keycloak Terraform drift..."

  cd platform-provisioning/aws/kubernetes/terraform/modules/keycloak

  # Terraform plan (detect drift)
  terraform plan -detailed-exitcode -no-color > /tmp/keycloak-plan.txt
  EXIT_CODE=$?

  if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ No drift detected - infrastructure matches state"
    exit 0
  elif [ $EXIT_CODE -eq 2 ]; then
    echo "⚠️  DRIFT DETECTED - changes required:"
    cat /tmp/keycloak-plan.txt
    exit 1
  else
    echo "❌ Terraform plan failed"
    cat /tmp/keycloak-plan.txt
    exit 1
  fi
  ```

- [ ] **4.3** Adicionar pre-commit hooks
  ```yaml
  # .pre-commit-config.yaml
  repos:
    - repo: https://github.com/antonbabenko/pre-commit-terraform
      rev: v1.83.5
      hooks:
        - id: terraform_fmt
          args:
            - --args=-recursive
        - id: terraform_validate
        - id: terraform_docs
          args:
            - --hook-config=--path-to-file=README.md
            - --hook-config=--add-to-existing-file=true
            - --hook-config=--create-file-if-not-exist=true
  ```

- [ ] **4.4** Documentar processo
  ```markdown
  # docs/runbooks/keycloak-client-creation.md

  ## Creating New OIDC Client

  ### 1. Use Terraform Module

  \`\`\`hcl
  module "myapp_oidc" {
    source = "../../modules/keycloak/client-oidc"

    realm_id      = keycloak_realm.platform.id
    client_id     = "myapp"
    client_name   = "My Application OIDC"
    k8s_namespace = "myapp"

    redirect_uris = ["http://myapp.staging.internal/callback"]
    web_origins   = ["http://myapp.staging.internal"]
    enable_pkce   = true  # Check app PKCE support first!
  }
  \`\`\`

  ### 2. Test Locally

  \`\`\`bash
  terraform plan
  terraform apply
  \`\`\`

  ### 3. Commit and PR

  \`\`\`bash
  git add .
  git commit -m "feat(keycloak): add OIDC client for myapp"
  git push
  # Create PR, wait for CI checks
  \`\`\`

  ### 4. Validate Post-Apply

  \`\`\`bash
  # Check client created
  kubectl get secret -n myapp myapp-oidc-keycloak

  # Test OIDC login
  curl -s http://keycloak.../auth/realms/platform/.well-known/openid-configuration
  \`\`\`
  ```

---

## ✅ Critérios de Sucesso

- [ ] Terraform Keycloak provider configurado e testado
- [ ] Clients "gitlab" e "argocd" importados para Terraform state
- [ ] `terraform plan` mostra zero drift (in-sync)
- [ ] Módulo reutilizável `client-oidc` criado
- [ ] CI/CD workflow funcional (plan em PR, apply em merge)
- [ ] Drift detection script criando e executando daily
- [ ] Documentação completa (runbook + README)
- [ ] Pre-commit hooks instalados

---

## ⚠️ Riscos e Mitigações

| Risco | Impacto | Mitigação |
|-------|---------|-----------|
| Import errado causa drift | ALTO | Dry-run import, validar plan antes de apply |
| Terraform apply quebra clients existentes | CRÍTICO | `lifecycle { prevent_destroy = true }` em todos clients |
| Client secret regenerado acidentalmente | ALTO | Usar `keycloak_openid_client_secret` com `ignore_changes = [value]` |
| CI/CD aplica mudanças não testadas | MÉDIO | Require PR approval, staging env primeiro |

---

## 🔗 Referências

- [Keycloak Terraform Provider Docs](https://registry.terraform.io/providers/mrparkers/keycloak/latest/docs)
- [Keycloak Admin CLI Guide](https://www.keycloak.org/docs/latest/server_admin/index.html#the-admin-cli)
- [Logbook OIDC Troubleshooting](../logbook/2026-02-12-keycloak-oidc-integration-troubleshooting.md)
- [MEMORY.md Pattern](/.claude/memory/MEMORY.md)

---

**Status:** 📋 TODO
**Última Atualização:** 2026-02-12
**Tracking Issue:** #TBD
