#!/bin/bash
set -e

OLD_NS="gitlab-staging"
NEW_NS="staging-platform-gitlab"

echo "Importing resources to $NEW_NS..."

# Function to clean and import resources
clean_and_import() {
    local resource_type=$1
    echo "Importing $resource_type..."

    kubectl get $resource_type -n $OLD_NS -o yaml | \
      grep -v "uid:" | \
      grep -v "resourceVersion:" | \
      grep -v "selfLink:" | \
      grep -v "creationTimestamp:" | \
      grep -v "clusterIP:" | \
      grep -v "clusterIPs:" | \
      grep -v "ownerReferences:" -A 10 | \
      sed "s/namespace: $OLD_NS/namespace: $NEW_NS/g" | \
      sed '/^status:/,/^[a-z]/{ /^[a-z]/!d; }' | \
      kubectl apply -n $NEW_NS --validate=false -f - 2>&1 | grep -v "Warning:" || true
}

# Import in order
clean_and_import "serviceaccount"
clean_and_import "secret"
clean_and_import "configmap"

# Import ExternalSecrets
echo "Importing ExternalSecrets..."
kubectl get externalsecrets -n $OLD_NS -o yaml 2>/dev/null | \
  grep -v "uid:" | \
  grep -v "resourceVersion:" | \
  grep -v "selfLink:" | \
  grep -v "creationTimestamp:" | \
  sed "s/namespace: $OLD_NS/namespace: $NEW_NS/g" | \
  sed '/^status:/,/^[a-z]/{ /^[a-z]/!d; }' | \
  kubectl apply -n $NEW_NS -f - 2>&1 | grep -v "Warning:" || echo "No ExternalSecrets or error"

sleep 5

clean_and_import "role"
clean_and_import "rolebinding"
clean_and_import "service"

echo "Importing Deployments..."
kubectl get deployment -n $OLD_NS -o yaml | \
  grep -v "uid:" | \
  grep -v "resourceVersion:" | \
  grep -v "selfLink:" | \
  grep -v "creationTimestamp:" | \
  grep -v "deployment.kubernetes.io/revision:" | \
  sed "s/namespace: $OLD_NS/namespace: $NEW_NS/g" | \
  sed '/^status:/,/^[a-z]/{ /^[a-z]/!d; }' | \
  kubectl apply -n $NEW_NS -f - 2>&1 | grep -v "Warning:" || true

echo "Importing StatefulSets..."
kubectl get statefulset -n $OLD_NS -o yaml | \
  grep -v "uid:" | \
  grep -v "resourceVersion:" | \
  grep -v "selfLink:" | \
  grep -v "creationTimestamp:" | \
  sed "s/namespace: $OLD_NS/namespace: $NEW_NS/g" | \
  sed '/^status:/,/^[a-z]/{ /^[a-z]/!d; }' | \
  kubectl apply -n $NEW_NS -f - 2>&1 | grep -v "Warning:" || true

clean_and_import "ingress"

echo "Importing NetworkPolicies..."
kubectl get networkpolicy -n $OLD_NS -o yaml 2>/dev/null | \
  grep -v "uid:" | \
  grep -v "resourceVersion:" | \
  grep -v "selfLink:" | \
  grep -v "creationTimestamp:" | \
  sed "s/namespace: $OLD_NS/namespace: $NEW_NS/g" | \
  kubectl apply -n $NEW_NS -f - 2>&1 | grep -v "Warning:" || echo "No network policies"

echo "✓ Resources imported"
