# SonarQube GitLab Authentication via Keycloak Federation — 2026-02-18

## Objetivo

Habilitar login no SonarQube com conta GitLab via Keycloak como Identity Broker.

## Arquitetura Implementada

```
Usuário → SonarQube (SAML SP) → Keycloak (SAML IdP + GitLab Social Provider) → GitLab OAuth2
```

## Por que não OAuth2 direto SonarQube ↔ GitLab

- `sonarqube:10.3.0-community` image NÃO inclui `sonar-auth-gitlab-plugin.jar`
- Community Build != Developer Edition (que tem o plugin built-in)
- Diagnóstico confirmado: `find /opt/sonarqube -name '*gitlab*'` retorna apenas SVG icons
- Erro definitivo: `Identity provider gitlab does not exist or is not enabled`

## O que foi implementado

### 1. Terraform Infrastructure (módulo sonarqube)

**Vault KV:** `secret/sonarqube/gitlab`
```
application_id     = b7bb4042666e99848f17c88a809a186eccb7aaa1e56def407fb03ff68dda9220
application_secret = gloas-a33d9b696ab3458985f3fd88b5f00d0867db4b8a0e4be79798ca80ad980457a5
```

**ESO ExternalSecret `sonarqube-sp-saml`** expandido — `secret.properties` agora contém 4 keys:
```
sonar.auth.saml.sp.certificate.secured=<cert>
sonar.auth.saml.sp.privateKey.secured=<key>
sonar.auth.gitlab.applicationId=<id>    ← novo (pronto para plugin futuro)
sonar.auth.gitlab.secret=<secret>       ← novo (pronto para plugin futuro)
```

**Vault policy `eso-reader`** atualizada (era drift não aplicado):
- `secret/data/sonarqube/*` ← adicionado
- `secret/data/grafana/*` ← adicionado

**Fix:** `field_manager { force_conflicts = true }` adicionado no `kubernetes_manifest.sonarqube_sp_saml_externalsecret` (resource existia via kubectl apply, TF state não tinha).

**Novos módulo variables:** `gitlab_oauth_enabled`, `gitlab_url`, `gitlab_allow_signup`, `gitlab_groups_sync`

### 2. Keycloak Identity Provider (configurado via API)

**Realm:** platform
**Alias:** gitlab
**Provider ID:** gitlab (built-in Keycloak 26 social provider)

```json
{
  "alias": "gitlab",
  "displayName": "GitLab",
  "providerId": "gitlab",
  "enabled": true,
  "trustEmail": true,
  "config": {
    "clientId": "b7bb4042...",
    "clientSecret": "gloas-...",
    "baseUrl": "http://gitlab.staging.internal",
    "defaultScope": "openid profile email read_user",
    "syncMode": "IMPORT"
  }
}
```

**Broker Redirect URI** (adicionada ao GitLab OAuth App):
```
http://keycloak.staging.internal/auth/realms/platform/broker/gitlab/endpoint
```

**Mappers (4):**
- `email` → oidc-user-attribute-idp-mapper (claim: email)
- `name` → oidc-user-attribute-idp-mapper (claim: name → firstName)
- `username` → hardcoded-user-session-attribute-idp-mapper
- `username-mapper` → oidc-username-idp-mapper (template: ${CLAIM.nickname})

### 3. GitLab OAuth Application (atualizada manualmente)

Redirect URIs:
- `http://sonarqube.staging.internal/oauth2/callback/gitlab` (mantida, para plugin futuro)
- `http://keycloak.staging.internal/auth/realms/platform/broker/gitlab/endpoint` ← NOVA

## Fluxo de Login (após configuração)

```
1. Usuário acessa http://sonarqube.staging.internal
2. SonarQube → SAML AuthnRequest → Keycloak
3. Keycloak login page exibe botão "GitLab"
4. Usuário clica → Keycloak redireciona para GitLab OAuth
5. GitLab autentica usuário → callback → Keycloak broker endpoint
6. Keycloak cria/atualiza usuário → SAML assertion → SonarQube
7. SonarQube autentica usuário (login = GitLab username)
```

## Validação Realizada

```
✅ Vault KV: version=1, keys=[application_id, application_secret]
✅ ESO Ready=True: 4 keys em secret.properties
✅ Vault policy eso-reader: sonarqube/* + grafana/* paths adicionados
✅ Keycloak IdP: alias=gitlab, enabled=True, baseUrl=http://gitlab.staging.internal
✅ 4 mappers criados
✅ Broker endpoint ativo (logs confirmam processamento)
⚡ Validação browser pendente: SonarQube login → botão GitLab → fluxo OAuth
```

## Pré-requisito para Primeiro Login

Antes do primeiro login via GitLab, o usuário GitLab deve existir ou:
1. Ter um usuário local no SonarQube com o mesmo username/email (para vincular conta)
2. OU `gitlab_allow_signup=false` → criar usuário manualmente no SonarQube antes

## Notas de Produção

- `syncMode: IMPORT` → apenas importa na 1ª autenticação, não sincroniza atualizações
- `trustEmail: true` → emails GitLab são automaticamente verificados (ok para staging)
- Para produção: configurar HTTPS nas URIs e habilitar verificação de email

## Referências

- ADR: SonarQube GitLab via Keycloak federation (não OAuth2 direto — CE limitation)
- strategies-history.md → "GitLab OAuth Direto — FALHA" + "SonarQube GitLab via Keycloak Federation"
