
---

## ✅ SonarQube SAML + Keycloak — 2026-02-18

**Contexto:** SonarQube 10.3 Community Edition + Keycloak SAML 2.0

### Estratégia que funcionou

1. **SP cert/key**: `openssl req -x509 -newkey rsa:2048` + `openssl pkcs8 -topk8 -nocrypt` (PKCS8 obrigatório)
2. **Vault KV**: `secret/sonarqube/saml` → `sp_certificate` + `sp_private_key_pkcs8` (base64 sem headers)
3. **ESO**: template `secret.properties` com ambas as props (não `sonar-secret.txt`)
4. **Helm**: `sonarSecretProperties: <secret-name>` (NÃO `sonarSecretKey`)
5. **serverBaseURL**: `sonar.core.serverBaseURL=http://sonarqube.staging.internal` (ACS URL correta)
6. **Keycloak**: `saml.client.signature=true` + upload SP cert + eso-reader policy +`secret/data/sonarqube/*`

### Anti-patterns identificados

- ❌ `sonarSecretKey` = chave AES para decrypt DB, NÃO para injetar sonar.properties
- ❌ K8s Secret key `sonar-secret.txt` para sonarSecretProperties → deve ser `secret.properties`
- ❌ `sonar.core.serverBaseURL` não configurado → ACS URL = `localhost:9000` → Keycloak rejeita
- ❌ `saml.client.signature=true` no Keycloak sem SP cert → assinatura falha

### Pattern universal SSO (todos os serviços)

> "Qualquer URL que o browser precisa resolver DEVE usar hostname externo (`*.staging.internal`), nunca `svc.cluster.local` nem `localhost`"

### Referências

- DEC-062
- logbook: `2026-02-18-sonarqube-saml-fix.md`

---

## ❌ SonarQube GitLab OAuth Direto — 2026-02-18

**Contexto:** Tentativa de habilitar GitLab OAuth2 direto no SonarQube 10.3.0-community

### Falha identificada

- Image `sonarqube:10.3.0-community` NÃO inclui `sonar-auth-gitlab-plugin.jar`
- `IdentityProviderRepository` não registra o provider 'gitlab' → erro: "Identity provider gitlab does not exist or is not enabled"
- As propriedades `sonar.auth.gitlab.*` existem no schema mas o provider não é registrado sem o plugin

### Diagnóstico executado

1. `sonar.properties` com `sonar.auth.gitlab.enabled=true` → provider NÃO registrado
2. Insert direto no DB (tabela `properties`) → provider NÃO registrado (plugin ausente)
3. `find /opt/sonarqube -name '*gitlab*'` → apenas SVG icons (ALM UI), sem JAR
4. `grep -rl 'GitlabIdentityProvider' /opt/sonarqube/lib/` → 0 resultados

### Solução correta

**GitLab → Keycloak (Identity Provider federation) → SonarQube (SAML já configurado)**

- Keycloak 26 tem built-in GitLab Social Provider
- Usar a mesma OAuth App criada (Application ID + Secret)
- Fluxo: SonarQube SAML → Keycloak → GitLab OAuth → autenticação federada

### O que foi feito (a manter)

- TF infra: variables.tf + main.tf + values.yaml.tpl atualizados com `gitlab_oauth_enabled` flag
- Vault KV: `secret/sonarqube/gitlab` → application_id + application_secret
- ESO `sonarqube-sp-saml` expandido: inclui GitLab creds em `secret.properties` (útil para futura instalação do plugin)
- Vault policy `eso-reader`: agora cobre `secret/data/sonarqube/*` + `secret/data/grafana/*` (era drift, corrigido)
- field_manager `force_conflicts=true` adicionado no ESO kubernetes_manifest (fix para resource já criado via kubectl)

### Próximo passo

Configurar Keycloak Identity Provider → GitLab (Social Provider)

### Referências

- logbook: `2026-02-18-sonarqube-gitlab-keycloak-federation.md` (a criar)
