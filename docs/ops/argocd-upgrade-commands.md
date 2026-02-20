# ArgoCD Upgrade — Runbook (staging → production)

Resumo: passos prontos para execução local/CI. Execute em ambiente com acesso à internet e ao cluster kubeconfig apropriado.

1) Preparação

```bash
# add repo
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# backup ArgoCD resources
kubectl -n argocd get applications -o yaml > backup-argocd-apps-$(date +%Y%m%d).yaml
kubectl -n argocd get appprojects -o yaml > backup-argocd-projects-$(date +%Y%m%d).yaml
kubectl -n argocd get configmap argocd-cm -o yaml > backup-argocd-cm-$(date +%Y%m%d).yaml
kubectl -n argocd get secret -o yaml > backup-argocd-secrets-$(date +%Y%m%d).yaml
```

2) Test deployment (namespace `argocd-test`)

```bash
kubectl create namespace argocd-test || true
helm install argocd-test argo/argo-cd --namespace argocd-test --version 7.10.0 --values values-test.yaml
# test OIDC login flow, logs and metrics
kubectl logs -n argocd-test -l app.kubernetes.io/name=argocd-server --tail=200
```

3) Terraform plan (domains/cicd-platform)

Run from repo root or CI runner with proper vars (cluster endpoint/ca and domains):

```bash
cd domains/cicd-platform/infra/terraform
terraform init
terraform plan -var-file=secrets.tfvars -out=tfplan
terraform show -json tfplan > tfplan.json
```

4) Production upgrade (dry-run → apply)

```bash
# get current Helm values
helm get values argocd -n argocd > values-current.yaml
# merge PKCE/oidc changes into values-current.yaml (manual edit)
helm upgrade argocd argo/argo-cd --namespace argocd --version 7.10.0 --values values-current.yaml --dry-run
helm upgrade argocd argo/argo-cd --namespace argocd --version 7.10.0 --values values-current.yaml --wait --timeout 10m
```

5) Enable PKCE in Keycloak (prefer Terraform Keycloak Provider)

Example (SQL fallback shown in TASK-001): use Terraform if available, else run SQL to set `pkce.code.challenge.method` => `S256` for client_id `argocd`.

6) Validation & rollback

```bash
# validate logins, sync apps, metrics
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --since=1h | grep -i error || true
curl -s http://argocd-server.argocd:8083/metrics | grep argocd_app_sync_total || true

# rollback if needed
helm rollback argocd -n argocd
```

Observação: nesta sessão o ambiente de execução não permitiu baixar assets remotos (DNS/rede restrita). Os artefatos de chart foram preparados localmente quando possível; se houver necessidade, execute os comandos acima em uma máquina com acesso à internet.
