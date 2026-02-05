# SonarQube Module

Code quality and security scanning platform with PostgreSQL backend.

## Features

- ✅ Community Edition (free, full-featured)
- ✅ PostgreSQL RDS external database
- ✅ Persistent storage (20Gi default)
- ✅ Prometheus metrics exporter
- ✅ GitLab webhook integration
- ✅ Quality gates enforcement

## Usage

```hcl
module "sonarqube_staging" {
  source = "../../modules/sonarqube"
  
  cluster_name          = "k8s-platform-staging"
  namespace             = "sonarqube"
  replicas              = 1  # Community Edition: 1 only
  postgresql_host       = module.postgresql_staging.endpoint
  postgresql_port       = 5432
  postgresql_database   = "sonarqube"
  storage_class         = "gp2"
  pvc_size              = "20Gi"
  ingress_enabled       = true
  domain                = "sonarqube.k8s-platform.example.com"
  enable_monitoring     = true
  common_tags           = local.common_tags
}
```

## Pre-Deployment

1. Bootstrap PostgreSQL database:
   ```bash
   ./scripts/bootstrap-database.sh <RDS_ENDPOINT> <MASTER_PASSWORD>
   ```

2. Store credentials in Vault (see script output)

3. Create ExternalSecret for database connection

## Post-Deployment

1. Login with default credentials: `admin/admin`
2. Change admin password
3. Configure GitLab webhook for MR decoration
4. Create Quality Gate rules
5. Install plugins (optional)

## GitLab Integration

1. Generate SonarQube token: User → Security → Generate Token
2. Configure GitLab CI/CD variables:
   - `SONAR_HOST_URL`: https://sonarqube.example.com
   - `SONAR_TOKEN`: <generated_token>
3. Add `.gitlab-ci.yml` job:
   ```yaml
   sonarqube-check:
     image: sonarsource/sonar-scanner-cli:latest
     script:
       - sonar-scanner
   ```

## TODO

- [ ] Bootstrap database automation (Terraform null_resource)
- [ ] ExternalSecret for PostgreSQL connection
- [ ] Quality Gate API configuration
- [ ] GitLab webhook setup automation
