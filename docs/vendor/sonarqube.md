# SonarQube — trechos pinados

version: 10.3.0 (chart/release)
source: https://docs.sonarsource.com/sonarqube/latest/
link: https://docs.sonarqube.org/latest/

Trechos uteis:

- Helm chart: `SonarSource/sonarqube` — chart reference in `modules/sonarqube` with `version = var.sonarqube_version`
- JDBC: `sonar.jdbc.url: jdbc:postgresql://<rds-endpoint>:5432/sonarqube`
- Autenticacao (Community Edition):
  - OIDC: NAO disponivel nativamente (requer plugin `sonar-auth-oidc`)
  - SAML 2.0: NATIVO desde SonarQube 9.7+ (`sonar.auth.saml.*`)
  - GitLab OAuth: NATIVO (`sonar.auth.gitlab.*`)
  - Decisao: Usar SAML nativo com GitLab (chain: SonarQube->SAML->GitLab->OIDC->Keycloak)
- Config SAML: `sonar.auth.saml.enabled`, `sonar.auth.saml.providerName`, `sonar.auth.saml.loginUrl`, etc.

Referencias locais:
- `domains/cicd-platform/infra/terraform/main.tf` (helm_release sonarqube)
- `docs/workflows/gap-004-sonarqube-deployment-prompt.md`
- `docs/logbook/2026-02-13-sso-e2e-conformidade-keycloak.md` (decisao SAML)
