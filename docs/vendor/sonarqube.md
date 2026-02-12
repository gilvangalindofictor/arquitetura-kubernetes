# SonarQube — trechos pinados

version: 10.3.0 (chart/release)
source: https://docs.sonarsource.com/sonarqube/latest/
link: https://docs.sonarqube.org/latest/

Trechos úteis:

- Helm chart: `SonarSource/sonarqube` — chart reference in `modules/sonarqube` with `version = var.sonarqube_version`
- JDBC: `sonar.jdbc.url: jdbc:postgresql://<rds-endpoint>:5432/sonarqube`
- OIDC: Keycloak integration examples in `docs/workflows/gap-004-sonarqube-deployment-prompt.md`

Referências locais:
- `domains/cicd-platform/infra/terraform/main.tf` (helm_release sonarqube)
- `docs/workflows/gap-004-sonarqube-deployment-prompt.md`
