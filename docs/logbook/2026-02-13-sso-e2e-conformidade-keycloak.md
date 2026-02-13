# Diario de Bordo - SSO E2E Conformidade Keycloak

| Campo       | Valor                                                    |
| ----------- | -------------------------------------------------------- |
| **Data**    | 2026-02-13                                               |
| **Demanda** | SSO E2E - Conformidade de todos os servicos com Keycloak |
| **Impacto** | alto                                                     |
| **Agentes** | Orquestrador, TF Specialist, Security                    |
| **Status**  | planejamento                                             |

---

## Diagnostico Inicial

### Mapa de ALBs Staging (Ingress Groups)

| ALB Group               | IP Atual        | Servicos                                    |
| ----------------------- | --------------- | ------------------------------------------- |
| `platform-staging`      | 34.230.141.109  | ArgoCD, Keycloak*, Vault, Harbor, SonarQube |
| GitLab (proprio ALB)    | 98.87.249.125   | GitLab, Registry, KAS                       |
| `observability-staging` | **A DESCOBRIR** | Grafana                                     |
| `data-staging`          | **A DESCOBRIR** | RabbitMQ Management                         |

> *Keycloak NAO tem Ingress no Terraform. Provavel config manual via kubectl.

### Status SSO por Servico

| Servico   | SSO Atual                | Status  | Acao Necessaria                      |
| --------- | ------------------------ | ------- | ------------------------------------ |
| Keycloak  | Provider central (OIDC)  | PARCIAL | Adicionar Ingress ALB ao modulo TF   |
| ArgoCD    | Keycloak OIDC            | OK      | Nenhuma (OIDC configurado)           |
| GitLab    | Keycloak OIDC (OmniAuth) | OK      | Nenhuma (OIDC configurado)           |
| SonarQube | OIDC env vars SEM plugin | FALHO   | Trocar para GitLab OAuth nativo      |
| Grafana   | Sem SSO (adminPassword)  | FALHO   | Adicionar generic_oauth com Keycloak |
| Harbor    | Sem SSO (adminPassword)  | FALHO   | Adicionar OIDC auth mode             |
| Vault     | Sem SSO (token auth)     | FALHO   | Adicionar OIDC auth method (P2)      |

### Decisao: SonarQube Community + Autenticacao

| Aspecto       | Detalhe                                                 |
| ------------- | ------------------------------------------------------- |
| SAML 2.0      | NAO disponivel (Developer Edition+)                     |
| OIDC generico | Requer plugin `sonar-auth-oidc` (nao instalado)         |
| GitLab OAuth  | NATIVO na Community Edition (`sonar.auth.gitlab.*`)     |
| Decisao       | Usar GitLab OAuth nativo (chain: SonarQube->GitLab->KC) |
| Justificativa | Sem dependencia de plugin 3rd party, feature nativa     |

---

## Plano de Execucao

### Fase 1: Pre-requisitos (P0 - Blocker)

#### 1.1 Keycloak - Adicionar Ingress ALB ao modulo Terraform

**Problema**: Keycloak tem `service.type: ClusterIP` sem Ingress definido no TF.
Para OIDC funcionar E2E, o browser precisa acessar Keycloak externamente.

**Arquivos a alterar**:
- `platform-provisioning/aws/kubernetes/terraform/modules/keycloak/variables.tf` - Adicionar variaveis de ingress
- `platform-provisioning/aws/kubernetes/terraform/modules/keycloak/values.yaml.tpl` - Adicionar bloco ingress
- `platform-provisioning/aws/kubernetes/terraform/environments/staging/main.tf` - Passar parametros de ingress

**Variaveis a adicionar** (`variables.tf`):
```hcl
variable "ingress_enabled" {
  description = "Enable ALB ingress for Keycloak"
  type        = bool
  default     = false
}

variable "ingress_host" {
  description = "Hostname for Keycloak Ingress (e.g., keycloak.staging.internal)"
  type        = string
  default     = ""
}

variable "ingress_group_name" {
  description = "ALB Ingress group name para compartilhar ALB entre servicos"
  type        = string
  default     = ""
}
```

**Bloco Ingress** (`values.yaml.tpl` - apos `service:`):
```yaml
%{ if ingress_enabled }
ingress:
  enabled: true
  ingressClassName: alb
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/backend-protocol: HTTP
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}]'
    alb.ingress.kubernetes.io/healthcheck-path: /auth/health/ready
    alb.ingress.kubernetes.io/healthcheck-port: "8080"
    alb.ingress.kubernetes.io/success-codes: "200"
    %{ if ingress_group_name != "" }alb.ingress.kubernetes.io/group.name: ${ingress_group_name}%{ endif }
  rules:
    - host: ${ingress_host}
      paths:
        - path: /
          pathType: Prefix
%{ endif }
```

**Staging main.tf** (modulo `keycloak_staging`):
```hcl
  # ALB Ingress for Keycloak SSO UI
  ingress_enabled    = true
  ingress_host       = "keycloak.staging.internal"
  ingress_group_name = "platform-staging"
```

**Validacao**: `terraform plan` deve mostrar apenas mudanca no helm_release.keycloak

---

#### 1.2 ArgoCD - Corrigir issuer URL para usar hostname externo do Keycloak

**Problema**: `keycloak_url` usa URL interna `http://keycloak-http.keycloak.svc.cluster.local/auth`.
Isso funciona server-to-server mas o browser NAO resolve `svc.cluster.local`.

**Arquivo**: `environments/staging/main.tf` linha 492
```hcl
# ANTES (broken para browser redirect):
keycloak_url = "http://keycloak-http.keycloak.svc.cluster.local/auth"

# DEPOIS (acessivel pelo browser):
keycloak_url = "http://keycloak.staging.internal/auth"
```

**NOTA**: A URL interna TAMBEM funciona para operacoes server-side (token validation).
O ArgoCD values.yaml.tpl ja usa `${keycloak_url}/realms/platform` como issuer.
O browser precisa resolver esse hostname, entao deve ser o hostname externo.

---

### Fase 2: SonarQube - Migrar para GitLab OAuth (P1)

#### 2.1 Atualizar SonarQube values.yaml.tpl

**Arquivo**: `modules/sonarqube/values.yaml.tpl`
**Acao**: Remover config OIDC quebrada, adicionar GitLab OAuth nativo

```yaml
# REMOVER (linhas 82-98):
# env:
#   - name: SONAR_AUTH_OIDC_ENABLED ...
#   - name: SONAR_AUTH_OIDC_ISSUERURI ...
#   - name: SONAR_AUTH_OIDC_CLIENTID_SECURED ...
#   - name: SONAR_AUTH_OIDC_CLIENTSECRET_SECURED ...
#   - name: SONAR_AUTH_OIDC_GROUPSSYNC ...
#   - name: SONAR_AUTH_OIDC_GROUPSSYNC_CLAIMNAME ...

# ADICIONAR:
sonarProperties:
  sonar.auth.gitlab.enabled: "true"
  sonar.auth.gitlab.url: "${gitlab_url}"
  sonar.auth.gitlab.applicationId.secured: "${gitlab_app_id}"
  sonar.auth.gitlab.secret.secured: "${gitlab_app_secret}"
  sonar.auth.gitlab.allowUsersToSignUp: "true"
  sonar.auth.gitlab.groupsSync: "true"
```

#### 2.2 Adicionar variaveis GitLab ao modulo SonarQube

**Arquivo**: `modules/sonarqube/variables.tf`
```hcl
variable "gitlab_url" {
  description = "GitLab URL for OAuth authentication"
  type        = string
  default     = ""
}

variable "gitlab_oauth_app_id" {
  description = "GitLab OAuth Application ID for SonarQube"
  type        = string
  default     = ""
}

variable "gitlab_oauth_app_secret" {
  description = "GitLab OAuth Application Secret for SonarQube"
  type        = string
  default     = ""
  sensitive   = true
}
```

#### 2.3 Atualizar main.tf do modulo SonarQube

**Arquivo**: `modules/sonarqube/main.tf` - Passar novas variaveis para o template

#### 2.4 Atualizar staging main.tf

**Arquivo**: `environments/staging/main.tf` modulo `sonarqube_staging`
```hcl
  # GitLab OAuth (SonarQube Community native)
  gitlab_url              = "http://gitlab.staging.internal"
  gitlab_oauth_app_id     = "CRIAR_APP_NO_GITLAB"
  gitlab_oauth_app_secret = "CRIAR_APP_NO_GITLAB"
```

#### 2.5 Criar GitLab OAuth Application

**Acao manual no GitLab** (Admin > Applications):
- Name: `SonarQube`
- Redirect URI: `http://sonarqube.staging.internal/oauth2/callback/gitlab`
- Scopes: `read_user`, `api` (para groups sync)
- Trusted: Yes
- Confidential: Yes

Salvar `Application ID` e `Secret` para uso no Terraform.

---

### Fase 3: Grafana - Adicionar SSO com Keycloak (P1)

#### 3.1 Atualizar kube-prometheus-stack modulo

**Arquivo**: `modules/kube-prometheus-stack/main.tf`
Adicionar blocos `set` para `grafana.ini` auth.generic_oauth:

```hcl
  # Grafana OIDC with Keycloak
  dynamic "set" {
    for_each = var.grafana_oidc_enabled ? [1] : []
    content {
      name  = "grafana.grafana\\.ini.auth\\.generic_oauth.enabled"
      value = "true"
    }
  }
  # ... (name, client_id, client_secret, scopes, auth_url, token_url, api_url, role_attribute_path)
```

#### 3.2 Adicionar variaveis

**Arquivo**: `modules/kube-prometheus-stack/variables.tf`
```hcl
variable "grafana_oidc_enabled" { default = false }
variable "grafana_keycloak_url" { default = "" }
variable "grafana_keycloak_client_id" { default = "grafana" }
variable "grafana_keycloak_client_secret" { default = "" ; sensitive = true }
```

#### 3.3 Criar client no Keycloak

**Acao manual no Keycloak** (Realm: platform > Clients):
- Client ID: `grafana`
- Client Protocol: openid-connect
- Root URL: `http://grafana.staging.internal`
- Valid Redirect URIs: `http://grafana.staging.internal/login/generic_oauth`
- Client Authentication: On

#### 3.4 Atualizar staging main.tf

```hcl
  # Grafana OIDC with Keycloak
  grafana_oidc_enabled           = true
  grafana_keycloak_url           = "http://keycloak.staging.internal/auth"
  grafana_keycloak_client_id     = "grafana"
  grafana_keycloak_client_secret = "SECRET_DO_KEYCLOAK"
```

---

### Fase 4: Harbor - Adicionar OIDC (P1)

#### 4.1 Atualizar Harbor values.yaml.tpl

**Arquivo**: `modules/harbor/values.yaml.tpl`
Adicionar apos `harborAdminPassword`:

```yaml
%{ if oidc_enabled }
# OIDC Authentication (Keycloak)
authMode: oidc_auth
oidc:
  name: Keycloak
  endpoint: ${oidc_endpoint}
  clientId: ${oidc_client_id}
  clientSecret: ${oidc_client_secret}
  groupsClaim: groups
  adminGroup: harbor-admins
  scope: openid,profile,email,groups
  autoOnboard: true
  userClaim: preferred_username
%{ endif }
```

#### 4.2 Variavies e staging main.tf

Similar a Fase 3: adicionar variaveis + criar client `harbor` no Keycloak.

---

### Fase 5: Vault OIDC (P2 - Opcional)

Vault usa auth method diferente (nao Helm values). Requer:
1. `vault auth enable oidc`
2. `vault write auth/oidc/config` com parametros do Keycloak
3. Configurar role mappings

Pode ser feito via modulo `vault-config` (atualmente comentado no staging main.tf).

---

## Keycloak - Clients a Criar (Realm: platform)

| Client ID   | Redirect URI                                                          | Status  |
| ----------- | --------------------------------------------------------------------- | ------- |
| `argocd`    | `http://argocd.staging.internal/auth/callback`                        | EXISTE  |
| `gitlab`    | `http://gitlab.staging.internal/users/auth/openid_connect/callback`   | EXISTE  |
| `sonarqube` | N/A (usa GitLab OAuth nativo, nao Keycloak direto)                    | REMOVER |
| `grafana`   | `http://grafana.staging.internal/login/generic_oauth`                 | CRIAR   |
| `harbor`    | `http://harbor.staging.internal/c/oidc/callback`                      | CRIAR   |
| `vault`     | `http://vault.staging.internal:8200/ui/vault/auth/oidc/oidc/callback` | P2      |

---

## Ordem de Execucao (TF Apply)

```
1. TF Apply: Keycloak Ingress (Fase 1.1)
   Validar: keycloak.staging.internal acessivel no browser

2. Criar clients no Keycloak UI (grafana, harbor)
   Anotar: client_id + client_secret de cada

3. TF Apply: ArgoCD issuer URL fix (Fase 1.2)
   Validar: login OIDC no ArgoCD via browser

4. Criar GitLab OAuth App para SonarQube (Fase 2.5)
   Anotar: Application ID + Secret

5. TF Apply: SonarQube GitLab OAuth (Fase 2)
   Validar: login GitLab no SonarQube via browser

6. TF Apply: Grafana OIDC (Fase 3)
   Validar: login Keycloak no Grafana via browser

7. TF Apply: Harbor OIDC (Fase 4)
   Validar: login Keycloak no Harbor via browser

8. (P2) Vault OIDC via vault-config module (Fase 5)
```

---

## Timeline

[13:00:00] Analise | Orq | Diagnostico SSO E2E completo | impacto: alto
[13:00:00] Decisao | SonarQube Community: GitLab OAuth nativo (OIDC nao nativo sem plugin)
[13:00:00] Planejamento | 5 fases, 7 servicos, 3 ALB groups mapeados
