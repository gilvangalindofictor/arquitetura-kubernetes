# ArgoCD Module

GitOps deployment engine with Keycloak OIDC authentication and RBAC.

## Features

- ✅ Keycloak OIDC integration (SSO)
- ✅ RBAC with no secret enumeration
- ✅ ApplicationSets support
- ✅ Prometheus metrics
- ✅ Multi-replica HA (server, repo-server)

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

1. Get initial admin password:
   ```bash
   kubectl get secret argocd-initial-admin-secret -n argocd \
     -o jsonpath='{.data.password}' | base64 -d
   ```

2. Create Keycloak client (client-id: argocd)
3. Configure AppProjects (see `projects/` directory)
4. Create ApplicationSets for GitOps workflow

## TODO

- [ ] Implement AppProject CRDs via kubectl_manifest
- [ ] Add Slack notifications
- [ ] Add ApplicationSet examples
