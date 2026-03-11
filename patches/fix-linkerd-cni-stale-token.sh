#!/usr/bin/env bash
# =============================================================================
# FIX: Linkerd CNI "Unauthorized" — Stale ServiceAccount Token in Kubeconfig
# =============================================================================
#
# ROOT CAUSE:
#   The Linkerd CNI DaemonSet writes a kubeconfig file to each node at
#   /etc/cni/net.d/ZZZ-linkerd-cni-kubeconfig containing the pod's projected
#   ServiceAccount token. This token is ONLY written at pod startup and has a
#   ~24h TTL (Kubernetes projected token default). When the CNI pod runs for
#   longer than the token lifetime WITHOUT being restarted, the kubeconfig on
#   the node retains the STALE (expired) token. The CNI binary (invoked by
#   kubelet for every new pod sandbox) uses this expired token to call the K8s
#   API, resulting in "Unauthorized".
#
#   Affected nodes (token expired 2026-03-10 11:31 -03):
#     - ip-10-0-148-204.ec2.internal  (linkerd-cni-5zh2n, age 46h)
#     - ip-10-0-130-167.ec2.internal  (linkerd-cni-ph95m, age 46h)
#
#   The node ip-10-0-130-167 hosts both affected pods:
#     - redis-0 (ContainerCreating 14h)
#     - k8s-platform-prod-rabbitmq-server-0 (Init:0/1 18h)
#
# FIX:
#   Rolling restart of the linkerd-cni DaemonSet. Each new CNI pod will:
#   1. Get a fresh projected ServiceAccount token
#   2. Re-write the kubeconfig with the new valid token
#   3. The kubelet will then succeed calling the CNI plugin
#
# IMPACT:
#   - Rolling restart means one node at a time loses CNI (briefly)
#   - Existing running pods are NOT affected (CNI only runs at pod creation)
#   - Only new pod sandbox creation is momentarily paused on the restarting node
#
# =============================================================================
set -euo pipefail

echo "============================================="
echo "PHASE 1: Pre-flight checks"
echo "============================================="

echo "[1/4] Checking CNI DaemonSet status..."
kubectl get daemonset linkerd-cni -n linkerd-cni -o wide
echo ""

echo "[2/4] Identifying nodes with EXPIRED tokens..."
for pod in $(kubectl get pods -n linkerd-cni -o jsonpath='{.items[*].metadata.name}'); do
  node=$(kubectl get pod -n linkerd-cni "$pod" -o jsonpath='{.spec.nodeName}')
  token_exp=$(kubectl exec -n linkerd-cni "$pod" -- cat /host/etc/cni/net.d/ZZZ-linkerd-cni-kubeconfig 2>/dev/null \
    | grep token | awk '{print $2}' | cut -d. -f2 \
    | base64 -d 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['exp'])" 2>/dev/null) || true
  if [ -n "$token_exp" ]; then
    now=$(date +%s)
    if [ "$token_exp" -lt "$now" ]; then
      echo "  EXPIRED: $pod ($node) - expired $(date -d @$token_exp '+%Y-%m-%d %H:%M:%S')"
    else
      echo "  VALID:   $pod ($node) - expires $(date -d @$token_exp '+%Y-%m-%d %H:%M:%S')"
    fi
  fi
done
echo ""

echo "[3/4] Checking affected pods in data-services..."
kubectl get pods -n data-services -o wide
echo ""

echo "[4/4] Pre-flight complete."
echo ""

echo "============================================="
echo "PHASE 2: Rolling restart linkerd-cni DaemonSet"
echo "============================================="

echo "Executing: kubectl rollout restart daemonset/linkerd-cni -n linkerd-cni"
kubectl rollout restart daemonset/linkerd-cni -n linkerd-cni

echo ""
echo "Waiting for rollout to complete (timeout 300s)..."
kubectl rollout status daemonset/linkerd-cni -n linkerd-cni --timeout=300s

echo ""
echo "============================================="
echo "PHASE 3: Validation - Token freshness"
echo "============================================="

echo "Waiting 15s for new pods to write kubeconfig..."
sleep 15

echo "Checking token status on all nodes..."
ALL_VALID=true
for pod in $(kubectl get pods -n linkerd-cni -o jsonpath='{.items[*].metadata.name}'); do
  node=$(kubectl get pod -n linkerd-cni "$pod" -o jsonpath='{.spec.nodeName}')
  token_exp=$(kubectl exec -n linkerd-cni "$pod" -- cat /host/etc/cni/net.d/ZZZ-linkerd-cni-kubeconfig 2>/dev/null \
    | grep token | awk '{print $2}' | cut -d. -f2 \
    | base64 -d 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['exp'])" 2>/dev/null) || true
  if [ -n "$token_exp" ]; then
    now=$(date +%s)
    if [ "$token_exp" -lt "$now" ]; then
      echo "  STILL EXPIRED: $pod ($node)"
      ALL_VALID=false
    else
      echo "  OK: $pod ($node) - new token expires $(date -d @$token_exp '+%Y-%m-%d %H:%M:%S')"
    fi
  fi
done

if [ "$ALL_VALID" = true ]; then
  echo ""
  echo "All tokens are valid."
else
  echo ""
  echo "WARNING: Some tokens are still expired. Investigate manually."
  exit 1
fi

echo ""
echo "============================================="
echo "PHASE 4: Recover stuck pods in data-services"
echo "============================================="

echo "Deleting stuck pods to trigger re-creation with fresh CNI..."
kubectl delete pod redis-0 -n data-services --grace-period=0 --force 2>/dev/null || echo "redis-0 not found or already deleted"
kubectl delete pod k8s-platform-prod-rabbitmq-server-0 -n data-services --grace-period=0 --force 2>/dev/null || echo "rabbitmq-server-0 not found or already deleted"

echo ""
echo "Waiting 30s for pods to be recreated..."
sleep 30

echo ""
echo "Current pod status in data-services:"
kubectl get pods -n data-services -o wide
echo ""

echo "============================================="
echo "PHASE 5: Final validation"
echo "============================================="

echo "Checking for any FailedCreatePodSandBox events in data-services (last 5 min)..."
kubectl get events -n data-services --sort-by='.lastTimestamp' --field-selector type=Warning 2>/dev/null | grep -i "linkerd-cni" | tail -5 || echo "No linkerd-cni errors found - FIX SUCCESSFUL"

echo ""
echo "Done. Monitor pods with: kubectl get pods -n data-services -w"
