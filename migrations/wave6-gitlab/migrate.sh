#!/bin/bash
set -e

# GitLab Namespace Migration Script
# gitlab-staging → staging-platform-gitlab

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OLD_NS="gitlab-staging"
NEW_NS="staging-platform-gitlab"
EXPORT_DIR="/home/gilvangalindo/projects/Arquitetura/Kubernetes/migrations/wave6-gitlab/exports"
SNAPSHOT_NAME="gitlab-gitaly-snapshot-20260225-102034"

echo "=== GitLab Namespace Migration Started at $TIMESTAMP ==="
echo ""

# Step 1: Verify snapshot is ready
echo "[1/8] Verifying VolumeSnapshot..."
SNAPSHOT_READY=$(kubectl get volumesnapshot -n $OLD_NS $SNAPSHOT_NAME -o jsonpath='{.status.readyToUse}')
if [ "$SNAPSHOT_READY" != "true" ]; then
    echo "ERROR: Snapshot not ready!"
    exit 1
fi
echo "✓ Snapshot ready"
echo ""

# Step 2: Scale down GitLab workloads (minimize data changes)
echo "[2/8] Scaling down GitLab workloads..."
kubectl scale deployment -n $OLD_NS --all --replicas=0
kubectl scale statefulset -n $OLD_NS --all --replicas=0
echo "✓ Workloads scaled down"
echo ""

# Wait for pods to terminate
echo "Waiting for pods to terminate..."
kubectl wait --for=delete pod --all -n $OLD_NS --timeout=120s || echo "Some pods still terminating (continuing)"
echo ""

# Step 3: Process and clean exported resources
echo "[3/8] Processing exported resources..."
cd $EXPORT_DIR

# Remove namespace-specific fields and update namespace
cat all-resources.yaml | \
  grep -v "namespace: $OLD_NS" | \
  grep -v "uid:" | \
  grep -v "resourceVersion:" | \
  grep -v "selfLink:" | \
  grep -v "creationTimestamp:" | \
  grep -v "generation:" | \
  grep -v "pv.kubernetes.io/bind-completed:" | \
  grep -v "pv.kubernetes.io/bound-by-controller:" | \
  grep -v "volume.kubernetes.io/storage-provisioner:" | \
  sed "s/namespace: $OLD_NS/namespace: $NEW_NS/g" | \
  sed "/^status:/,/^[^ ]/d" > cleaned-resources.yaml

echo "✓ Resources processed"
echo ""

# Step 4: Create PVC from snapshot
echo "[4/8] Creating PVC from VolumeSnapshot in new namespace..."
cat > /tmp/new-gitaly-pvc.yaml <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: repo-data-gitlab-gitaly-0
  namespace: $NEW_NS
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gp3
  resources:
    requests:
      storage: 50Gi
  dataSource:
    name: $SNAPSHOT_NAME
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
EOF

kubectl apply -f /tmp/new-gitaly-pvc.yaml
echo "✓ PVC created from snapshot"
echo ""

# Wait for PVC to be bound
echo "Waiting for PVC to bind..."
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/repo-data-gitlab-gitaly-0 -n $NEW_NS --timeout=180s
echo "✓ PVC bound"
echo ""

# Step 5: Import resources to new namespace
echo "[5/8] Importing resources to $NEW_NS..."

# First, import secrets and configmaps
kubectl get secret -n $OLD_NS -o yaml | \
  grep -v "namespace: $OLD_NS" | \
  grep -v "uid:" | \
  grep -v "resourceVersion:" | \
  grep -v "selfLink:" | \
  grep -v "creationTimestamp:" | \
  sed "s/namespace: $OLD_NS/namespace: $NEW_NS/g" | \
  kubectl apply -n $NEW_NS -f - || echo "Some secrets already exist"

kubectl get configmap -n $OLD_NS -o yaml | \
  grep -v "namespace: $OLD_NS" | \
  grep -v "uid:" | \
  grep -v "resourceVersion:" | \
  grep -v "selfLink:" | \
  grep -v "creationTimestamp:" | \
  sed "s/namespace: $OLD_NS/namespace: $NEW_NS/g" | \
  kubectl apply -n $NEW_NS -f - || echo "Some configmaps already exist"

# Import ExternalSecrets
if [ -f externalsecrets.yaml ]; then
    cat externalsecrets.yaml | \
      sed "s/namespace: $OLD_NS/namespace: $NEW_NS/g" | \
      kubectl apply -f - || echo "ExternalSecrets import issues (may need manual intervention)"
fi

# Import ServiceAccounts, Roles, RoleBindings
kubectl get sa -n $OLD_NS -o yaml | \
  grep -v "namespace: $OLD_NS" | \
  grep -v "uid:" | \
  grep -v "resourceVersion:" | \
  grep -v "selfLink:" | \
  grep -v "creationTimestamp:" | \
  sed "s/namespace: $OLD_NS/namespace: $NEW_NS/g" | \
  kubectl apply -n $NEW_NS -f - || true

kubectl get role,rolebinding -n $OLD_NS -o yaml | \
  sed "s/namespace: $OLD_NS/namespace: $NEW_NS/g" | \
  kubectl apply -n $NEW_NS -f - || true

# Import Services
kubectl get svc -n $OLD_NS -o yaml | \
  grep -v "namespace: $OLD_NS" | \
  grep -v "uid:" | \
  grep -v "resourceVersion:" | \
  grep -v "selfLink:" | \
  grep -v "creationTimestamp:" | \
  grep -v "clusterIP:" | \
  grep -v "clusterIPs:" | \
  sed "s/namespace: $OLD_NS/namespace: $NEW_NS/g" | \
  sed "/^status:/,/^[^ ]/d" | \
  kubectl apply -n $NEW_NS -f - || echo "Some services already exist"

# Import Deployments and StatefulSets
kubectl get deployment -n $OLD_NS -o yaml | \
  sed "s/namespace: $OLD_NS/namespace: $NEW_NS/g" | \
  sed "/^status:/,/^[^ ]/d" | \
  kubectl apply -n $NEW_NS -f - || echo "Some deployments already exist"

kubectl get statefulset -n $OLD_NS -o yaml | \
  sed "s/namespace: $OLD_NS/namespace: $NEW_NS/g" | \
  sed "/^status:/,/^[^ ]/d" | \
  kubectl apply -n $NEW_NS -f - || echo "Some statefulsets already exist"

# Import Ingress
kubectl get ingress -n $OLD_NS -o yaml | \
  sed "s/namespace: $OLD_NS/namespace: $NEW_NS/g" | \
  sed "/^status:/,/^[^ ]/d" | \
  kubectl apply -n $NEW_NS -f - || echo "Some ingresses already exist"

# Import Network Policies
kubectl get networkpolicy -n $OLD_NS -o yaml 2>/dev/null | \
  sed "s/namespace: $OLD_NS/namespace: $NEW_NS/g" | \
  kubectl apply -n $NEW_NS -f - || echo "No network policies or already exist"

echo "✓ Resources imported"
echo ""

# Step 6: Wait for GitLab pods to be ready
echo "[6/8] Waiting for GitLab pods to be ready..."
echo "This may take 5-15 minutes (database migrations, etc.)"

# Wait for Gitaly first (critical)
kubectl wait --for=condition=ready pod -l app=gitaly -n $NEW_NS --timeout=600s || echo "Gitaly pods still starting"

# Wait for webservice
kubectl wait --for=condition=ready pod -l app=webservice -n $NEW_NS --timeout=600s || echo "Webservice pods still starting"

# Wait for other workloads
kubectl wait --for=condition=ready pod --all -n $NEW_NS --timeout=900s || echo "Some pods still starting (checking details)"

echo "✓ Pods ready (or timed out, checking status)"
kubectl get pods -n $NEW_NS
echo ""

# Step 7: Validate critical components
echo "[7/8] Validating critical components..."

# Check ExternalSecrets sync
echo "Checking ExternalSecrets..."
kubectl get externalsecrets -n $NEW_NS -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[0].reason --no-headers

# Check if GitLab Runner is connected
echo ""
echo "Checking GitLab Runner..."
kubectl logs -n $NEW_NS -l app=gitlab-runner --tail=20 | grep -i "runner.*registered\|runner.*online" || echo "Check runner logs manually"

echo ""
echo "✓ Basic validation complete"
echo ""

# Step 8: Summary
echo "[8/8] Migration Summary"
echo "======================"
echo "Old namespace: $OLD_NS (ready to delete)"
echo "New namespace: $NEW_NS"
echo ""
echo "Next steps:"
echo "1. Validate GitLab UI access"
echo "2. Test Git operations (clone, push)"
echo "3. Test CI/CD pipeline"
echo "4. Test SSO login"
echo "5. If all OK, delete old namespace: kubectl delete namespace $OLD_NS"
echo ""
echo "=== Migration Complete ==="
