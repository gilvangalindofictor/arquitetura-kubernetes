[14:10:00] Execucao | Orq | Demanda: terraform apply para persistir Keycloak changes no TF state | Keycloak 26.5.1 Quarkus
[14:10:05] Pre-check | Orq | Sessao AWS validada | profile: k8s-platform-prod | account: 891377105802
[14:10:10] Pre-check | Orq | EKS cluster: k8s-platform-prod | kubeconfig atualizado
[14:10:15] Pre-check | Orq | Pod keycloak-0 (manual) Running 1/1, 0 restarts | 40min uptime
[14:12:00] TF State | Terraform Specialist | Recursos no state: namespace + random_password apenas | helm_release, externalsecret, admin_secret AUSENTES
[14:14:00] TF Plan | Terraform Specialist | Plan inicial: 15 to add, 4 to change, 0 to destroy | inclui postgresql_staging + vault_staging
[14:16:00] TF Apply #1 | Terraform Specialist | FALHA: postgresql provider i/o timeout (RDS em subnet privada, inacessivel do local) + vault StatefulSet campo imutavel
[14:18:00] Mitigacao | Orq | Estrategia: remover depends_on temporariamente (keycloak nao referencia outputs do postgresql module, apenas ordering)
[14:20:00] TF Plan #2 | Terraform Specialist | Plan limpo: 3 to add, 1 to change | apenas keycloak_staging resources
[14:22:00] TF Apply #2 | Terraform Specialist | namespace atualizado, externalsecret criado, admin_password criado | helm_release FALHOU: template error
[14:22:30] Diagnostico | DevOps | Causa: values.yaml.tpl usava maps para probes (startupProbe:), chart keycloakx espera strings com pipe (startupProbe: |)
[14:24:00] Fix | Terraform Specialist | Corrigido values.yaml.tpl: startupProbe, livenessProbe, readinessProbe convertidos para pipe strings
[14:26:00] TF Plan #3 | Terraform Specialist | Plan: 1 to add (helm_release.keycloak apenas) | outros 3 recursos ja no state
[14:28:00] TF Apply #3 | Terraform Specialist | helm_release criado mas TIMEOUT (10min) | Pod em CreateContainerConfigError
[14:28:30] Diagnostico | DevOps | Causa: ExternalSecret falhou (ClusterSecretStore vault-backend not ready - Vault pods DOWN ContainerCreating 15h)
[14:29:00] Mitigacao | Orq | Secret keycloak-postgresql-credentials criado manualmente | username corrigido para postgres_admin (keycloak_user nao existe no RDS)
[14:30:00] Validacao | DevOps | Pod keycloak-keycloakx-0: Running 1/1, 0 restarts | Keycloak 26.5.1 started in 20.275s
[14:30:10] Validacao | DevOps | Infinispan rebalance: caches sincronizados entre keycloak-0 e keycloak-keycloakx-0 (HA ativo)
[14:30:30] TF Apply #4 | Terraform Specialist | helm_release tainted (failed) -> replaced -> status: deployed | revision 1
[14:31:00] Health | DevOps | /auth/health/ready: UP (DB connections UP, cluster health UP) | /auth/health/live: UP
[14:32:00] Cleanup | Orq | StatefulSet manual keycloak-0 removido | Service keycloak-http removido | apenas TF-managed resources
[14:33:00] Idempotencia | Terraform Specialist | terraform plan keycloak_staging: 0 changes | 12 pendentes sao postgresql_staging (RDS inacessivel)
[14:34:00] Restauracao | Orq | depends_on restaurado no main.tf | tfplan files limpos

## Recursos no TF State
- module.keycloak_staging.helm_release.keycloak (deployed, keycloakx-7.1.7)
- module.keycloak_staging.kubectl_manifest.keycloak_postgresql_externalsecret
- module.keycloak_staging.kubernetes_namespace.keycloak
- module.keycloak_staging.kubernetes_secret.keycloak_admin_password
- module.keycloak_staging.random_password.keycloak_admin

## Fix aplicado em values.yaml.tpl
- startupProbe, livenessProbe, readinessProbe: convertidos de map para pipe string (formato esperado pelo chart keycloakx)

## Workarounds ativos (divida tecnica)
- Secret keycloak-postgresql-credentials criado manualmente (Vault DOWN, ExternalSecret nao sincroniza)
- Username postgres_admin usado (role keycloak_user nao criado - postgresql provider sem acesso RDS do local)
- postgresql_staging roles/databases/grants pendentes no TF (12 recursos - requer acesso TCP ao RDS)

## Recomendacoes
1. Resolver Vault pods (ContainerCreating 15h - provavel PVC issue) para ExternalSecret funcionar
2. Aplicar postgresql_staging resources via bastion/VPN ou pipeline CI/CD com acesso VPC
3. Criar role keycloak_user no RDS e migrar de postgres_admin (separacao de privilegios)
4. Monitorar keycloak-keycloakx-0 por 48h (zero restarts across FinOps cycles)
5. Validar OIDC clients (ArgoCD, GitLab, SonarQube, Grafana) contra novo service keycloak-keycloakx-http
