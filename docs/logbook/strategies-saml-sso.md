
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
