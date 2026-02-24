# ApplicationSets Quick Start Guide

**Status:** Ready to deploy (kubectl validation pending)
**Date:** 2026-02-24

---

## Deploy in 3 Steps

### Step 1: Renew AWS SSO
```bash
aws sso login --profile k8s-platform-staging
```

### Step 2: Deploy ApplicationSets
```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/domains/cicd-platform/infra/argocd/applicationsets
./VALIDATION.sh
```

### Step 3: Verify in ArgoCD UI
Open: `https://argocd.platform.internal`
- Navigate to **Settings → ApplicationSets**
- Verify 3 ApplicationSets created
- Check **Applications** tab for auto-generated apps (7-8 expected)

---

## Expected Results

**ApplicationSets created:** 3
- `platform-services-multi-env` (Git Generator)
- `data-services-catalog` (List Generator)
- `monitoring-multi-cluster` (Cluster Generator)

**Applications auto-generated:** 7-8
- `observability-staging` (namespace: observability-staging)
- `observability-production` (namespace: observability-production)
- `data-services-staging` (namespace: data-services-staging)
- `data-services-production` (namespace: data-services-production)
- `postgresql-connection` (namespace: data-services, syncWave: 1)
- `redis-cluster` (namespace: data-services, syncWave: 2)
- `rabbitmq-cluster` (namespace: data-services, syncWave: 3)

**Namespaces auto-created:** 4
- `observability-staging`, `observability-production`
- `data-services-staging`, `data-services-production`

---

## Add New Application (Self-Service)

### Git Generator Pattern (Auto-Discovery)

```bash
# 1. Create directory structure
mkdir -p domains/my-app/manifests/staging

# 2. Add Kubernetes manifests
cat > domains/my-app/manifests/staging/deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app
        image: my-app:v1.0.0
        ports:
        - containerPort: 8080
EOF

# 3. Commit and push
git add domains/my-app/
git commit -m "feat: add my-app staging deployment"
git push

# 4. Wait 3 minutes (ArgoCD polling interval)
# Application "my-app-staging" will be created automatically
```

**Result:** Application `my-app-staging` deployed to namespace `my-app-staging` automatically.

---

## Add Service to Catalog

### List Generator Pattern (Service Catalog)

```bash
# 1. Edit data-services-catalog.yaml
vim domains/cicd-platform/infra/argocd/applicationsets/data-services-catalog.yaml

# 2. Add new element to list (example: MongoDB)
# Under spec.generators[0].list.elements, add:
- name: mongodb-cluster
  service: mongodb
  namespace: data-services
  path: domains/data-services/infra/helm/mongodb
  syncWave: "4"
  description: "MongoDB cluster for document storage"

# 3. Commit and push
git add domains/cicd-platform/infra/argocd/applicationsets/data-services-catalog.yaml
git commit -m "feat(data-services): add MongoDB to catalog"
git push

# 4. Apply updated ApplicationSet
kubectl apply -f domains/cicd-platform/infra/argocd/applicationsets/data-services-catalog.yaml
```

**Result:** Application `mongodb-cluster` deployed to namespace `data-services` with syncWave 4.

---

## Enable Multi-Cluster Monitoring

### Cluster Generator Pattern (Multi-Cluster)

```bash
# 1. Label cluster for monitoring
argocd cluster set https://kubernetes.default.svc \
  --label monitoring=enabled \
  --label environment=staging

# 2. Verify cluster detected
kubectl get applicationset monitoring-multi-cluster -n argocd -o yaml | grep -A5 generators

# 3. Check Application generated
kubectl get application monitoring-stack-staging -n argocd
```

**Result:** Application `monitoring-stack-staging` deployed to namespace `monitoring`.

---

## Troubleshooting

### Applications Not Generated

```bash
# Check ApplicationSet status
kubectl describe applicationset platform-services-multi-env -n argocd

# Check controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller --tail=50

# Verify Git structure matches pattern
find domains -type d -path '*/manifests/staging' -o -path '*/manifests/production'
```

### Applications OutOfSync

```bash
# Check Application status
kubectl get applications -n argocd -o wide

# View diff
argocd app diff APPLICATION_NAME

# Force sync
argocd app sync APPLICATION_NAME
```

### Namespace Not Created

```bash
# Verify syncOptions in ApplicationSet
kubectl get applicationset platform-services-multi-env -n argocd -o yaml | grep -A3 syncOptions

# Expected: CreateNamespace=true
```

---

## Documentation

- **Quick Reference:** `SUMMARY.md` (this directory)
- **Complete Guide:** `README.md` (447 lines)
- **Implementation Log:** `/docs/logbook/2026-02-24-gap006-applicationsets.md`

---

## Support

- **Platform Team:** `#platform-team` Slack channel
- **ArgoCD Docs:** https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/
- **Issues:** Create issue in Git repo with label `applicationsets`

---

**Last Updated:** 2026-02-24
**Status:** Production-ready (validation pending)
