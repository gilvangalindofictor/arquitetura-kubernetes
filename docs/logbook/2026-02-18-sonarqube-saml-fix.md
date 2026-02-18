# SonarQube SAML SP Certificate Fix — 2026-02-18

## Root Cause
`sonar.auth.saml.signature.enabled=true` exige SP cert + private key.  
Nem cert nem key estavam configurados → `Service provider certificate is missing`.

## Aprendizados Críticos (helm chart sonarqube v10.7.0)

| Campo helm | Propósito | Chave do K8s Secret |
|---|---|---|
| `sonarSecretKey` | Chave AES para decrypt de `.secured` no DB | `sonar-secret.txt` |
| `sonarSecretProperties` | Injeta sonar.properties extras via `concat-properties` init | `secret.properties` |

**ERRO COMUM:** usar `sonarSecretKey` quando o objetivo é injetar propriedades adicionais.  
**CORRETO:** `sonarSecretProperties` para injetar `sonar.auth.saml.sp.privateKey.secured`.

## Solução Aplicada

```
Vault KV: secret/sonarqube/saml
  → sp_certificate (base64 no headers)
  → sp_private_key_pkcs8 (PKCS8 base64 no headers)

ESO ExternalSecret: sonarqube-sp-saml (ns: sonarqube)
  → template: secret.properties = "sonar.auth.saml.sp.certificate.secured={{ .sp_certificate }}\n..."

helm sonarSecretProperties: sonarqube-sp-saml
  → concat-properties init: /tmp/props/secret.properties → /tmp/result/sonar.properties

Keycloak client sonarqube:
  → saml.client.signature = true
  → saml.signing.certificate = SP cert (1156 chars)
```

## Vault Policy
- `eso-reader` policy atualizada com `secret/data/sonarqube/*` (read/list)

## Validação
- `sonar.properties` tem 2 ocorrências de `privateKey` ✅
- SAML init → Location: `http://keycloak.../protocol/saml?SAMLRequest=...&Signature=...` ✅
- Sem erros `Service provider certificate/private key is missing` ✅

## Arquivos modificados
- `modules/sonarqube/values.yaml.tpl` — sonarSecretKey → sonarSecretProperties
- `modules/sonarqube/variables.tf` — doc atualizado para saml_sp_secret_name
- `environments/staging/main.tf` — kubernetes_manifest ExternalSecret + comentários
- `/tmp/sonarqube-sp-externalsecret.yaml` — aplicado manualmente (agora em TF)
- Vault KV: `secret/sonarqube/saml` criado
- Keycloak client: `saml.client.signature=true`, `saml.signing.certificate` SET

## Fix 2: ACS URL localhost → external hostname

**Erro:** Keycloak "Invalid redirect uri"  
**SAMLRequest ACS URL:** `http://localhost:9000/oauth2/callback/saml` (ERRADO)  
**Esperado:** `http://sonarqube.staging.internal/oauth2/callback/saml`

**Causa:** `sonar.core.serverBaseURL` não configurado → SonarQube usa `localhost:9000` como base URL no AuthnRequest

**Fix:** `sonar.core.serverBaseURL=http://sonarqube.staging.internal` em `sonarProperties`

**Pattern (ver logbook grafana-sso):** "All OIDC/SAML URLs exposed to browser MUST use external hostname"

**Validação:**
```
ACS URL novo: http://sonarqube.staging.internal/oauth2/callback/saml ✅
Keycloak redirectUri match: http://sonarqube.staging.internal/oauth2/callback/saml ✅
```
