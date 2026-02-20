# ArgoCD Module

GitOps deployment engine with Keycloak OIDC authentication and RBAC.

## Features

- Keycloak OIDC integration (SSO)
- RBAC with no secret enumeration
- ApplicationSets support
- Prometheus metrics
- Multi-replica HA (server, repo-server)
- Vault + ESO secrets management (V-002 remediation)

## Secrets Management (V-002)

ArgoCD secrets are managed via Vault KV v2 + External Secrets Operator:

| Secret                 | Vault Path                 | K8s Secret                      | Keys                                     |
| ---------------------- | -------------------------- | ------------------------------- | ---------------------------------------- |
| PostgreSQL credentials | `secret/argocd/postgresql` | `argocd-postgresql-credentials` | password, username, host, port, database |
| OIDC client secret     | `secret/argocd/oidc`       | `argocd-oidc-credentials`       | client_secret                            |

### Vault Policy Requirement

The `eso-reader` policy MUST include:

```hcl
path "secret/data/argocd/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/argocd/*" {
  capabilities = ["read", "list"]
}
```

### Vault KV Seeding

Secrets must be seeded via `vault-config` module (see `vault-config/main.tf`):
- `vault_kv_secret_v2.argocd_postgresql` (conditional on `argocd_postgresql_password != ""`)
- `vault_kv_secret_v2.argocd_oidc` (conditional on `argocd_oidc_client_secret != ""`)

### ArgoCD OIDC Secret Reference

The OIDC client secret uses ArgoCD's external secret reference syntax:
```yaml
clientSecret: $argocd-oidc-credentials:client_secret
```
This resolves to the `client_secret` key from the K8s Secret `argocd-oidc-credentials` in the `argocd` namespace.

## Usage

```hcl
module "argocd_staging" {
  source = "../../modules/argocd"

  cluster_name           = "k8s-platform-staging"
  namespace              = "argocd"
  replicas               = 2
  keycloak_url           = "https://keycloak.example.com"
  keycloak_client_id     = "argocd"
  ingress_enabled        = true
  domain                 = "argocd.k8s-platform.example.com"
  enable_monitoring      = true
  common_tags            = local.common_tags
}
```

## Post-Deploy Setup

1. Seed Vault secrets:
   ```bash
   vault kv put secret/argocd/postgresql \
     password="<password>" username="argocd_user" \
     host="postgresql-external.default.svc.cluster.local" \
     port="5432" database="argocd"

   vault kv put secret/argocd/oidc \
     client_id="argocd" client_secret="<keycloak-client-secret>"
   ```

2. Verify ExternalSecrets sync:
   ```bash
   kubectl get externalsecrets -n argocd
   kubectl get secrets argocd-postgresql-credentials -n argocd
   kubectl get secrets argocd-oidc-credentials -n argocd
   ```

3. Get initial admin password:
   ```bash
   kubectl get secret argocd-initial-admin-secret -n argocd \
     -o jsonpath='{.data.password}' | base64 -d
   ```

4. Create Keycloak client (client-id: argocd)
5. Configure AppProjects (see `projects/` directory)
6. Create ApplicationSets for GitOps workflow

## TODO

- [ ] Implement AppProject CRDs via kubectl_manifest
- [ ] Add Slack notifications
- [ ] Add ApplicationSet examples
