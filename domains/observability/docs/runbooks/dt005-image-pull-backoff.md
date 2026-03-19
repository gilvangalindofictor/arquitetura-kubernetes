# Runbook: ImagePullBackOff / Docker Hub Rate Limit

- **Alert Names**: `ImagePullBackOff`, `ErrImagePull`, `ImagePullBackOffNamespaceWide`, `ImagePullBackOffClusterWide`
- **Severity**: `warning` / `critical`
- **Source**: DT-005 Image Pull Alerts
- **Description**: Pods are unable to pull container images, most commonly due to Docker Hub rate limiting (HTTP 429). Docker Hub enforces 100 pulls/6h for anonymous and 200 pulls/6h for authenticated users per source IP.

---

## 1. Initial Triage

1. **Confirm scope of the incident**:
   ```bash
   # Count total affected pods
   kubectl get pods -A | grep -c -E "ImagePullBackOff|ErrImagePull"

   # Breakdown by namespace
   kubectl get pods -A | grep -E "ImagePullBackOff|ErrImagePull" | awk '{print $1}' | sort | uniq -c | sort -rn

   # List all affected pods with node info
   kubectl get pods -A -o wide | grep -E "ImagePullBackOff|ErrImagePull"
   ```

2. **Confirm root cause (rate limit vs other)**:
   ```bash
   # Look for "429 Too Many Requests" in events
   kubectl get events -A --field-selector reason=Failed | grep -i "429\|toomanyrequests\|rate"

   # Check specific pod events
   kubectl describe pod <pod-name> -n <namespace> | grep -A5 "Events:"
   ```

3. **Identify which images are failing**:
   ```bash
   # Get images from all failing pods
   kubectl get pods -A -o json | jq -r '
     .items[] |
     select(.status.containerStatuses[]?.state.waiting.reason == "ImagePullBackOff" or
            .status.initContainerStatuses[]?.state.waiting.reason == "ImagePullBackOff") |
     .spec.containers[].image, .spec.initContainers[]?.image' | sort -u
   ```

---

## 2. Diagnostic Steps

### 2.1 Docker Hub Rate Limit Confirmed

If events show `429 Too Many Requests` from `registry-1.docker.io`:

1. **Check current rate limit status from a node** (if SSH/SSM access):
   ```bash
   # Check remaining pulls (anonymous)
   TOKEN=$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:ratelimitpreview/test:pull" | jq -r .token)
   curl -s -I -H "Authorization: Bearer $TOKEN" https://registry-1.docker.io/v2/ratelimitpreview/test/manifests/latest 2>&1 | grep -i ratelimit
   # ratelimit-limit: 100;w=21600  (100 per 6 hours)
   # ratelimit-remaining: 0;w=21600  (0 remaining = rate limited)
   ```

2. **Identify all Docker Hub images in the cluster**:
   ```bash
   # Images with explicit docker.io prefix
   kubectl get pods -A -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' | sort -u | grep "docker.io"

   # Images with IMPLICIT docker.io (no registry prefix = Docker Hub)
   kubectl get pods -A -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' | sort -u | grep -v -E "ecr\.|gcr\.|ghcr\.|quay\.|cr\.l5d\.|registry\.|harbor\.|reg\.|oci\.|public\.ecr\."
   ```

### 2.2 Not Rate Limit

If no 429 errors found, check:

1. **Image does not exist**:
   ```bash
   kubectl describe pod <pod-name> -n <namespace> | grep "not found\|does not exist\|manifest unknown"
   ```

2. **Authentication failure** (private registry):
   ```bash
   kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.imagePullSecrets}'
   kubectl get secret <pull-secret> -n <namespace> -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq .
   ```

3. **Network/DNS failure**:
   ```bash
   kubectl run debug --rm -it --image=busybox:1.36 -- nslookup registry-1.docker.io
   ```

---

## 3. Immediate Workarounds

### 3.1 Use Node-Cached Images (fastest, 0 pulls)

If the image was previously pulled on some nodes, restart the pod on a node that has it cached:

```bash
# Find which nodes have the image cached (check node where a Running pod with same image exists)
kubectl get pods -A -o wide | grep <image-keyword> | grep Running

# Cordon other nodes, delete the stuck pod, uncordon
# OR: set nodeSelector/nodeAffinity to target the cached node
kubectl patch deployment <name> -n <ns> -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"<cached-node>"}}}}}'
```

### 3.2 Change imagePullPolicy to IfNotPresent

Prevents re-pulling if image is already on the node:

```bash
kubectl patch deployment <name> -n <ns> --type='json' -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"IfNotPresent"}
]'
```

### 3.3 Mirror Critical Images to Harbor/ECR (medium-term)

```bash
# Pull on a machine with Docker Hub access (or during off-peak)
docker pull docker.io/calico/node:v3.27.0
docker tag docker.io/calico/node:v3.27.0 harbor.staging.internal/mirror/calico-node:v3.27.0
docker push harbor.staging.internal/mirror/calico-node:v3.27.0

# OR: Use ECR public mirror
# Many Docker Hub images have ECR public mirrors at public.ecr.aws/docker/library/
```

### 3.4 Authenticate to Docker Hub (doubles limit to 200/6h)

```bash
# Create Docker Hub pull secret
kubectl create secret docker-registry dockerhub-auth \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=<username> \
  --docker-password=<token> \
  -n <namespace>

# Patch service account to use it
kubectl patch serviceaccount default -n <namespace> \
  -p '{"imagePullSecrets": [{"name": "dockerhub-auth"}]}'
```

### 3.5 Scale Down Non-Essential to Reduce Pull Pressure

```bash
# Reduce replicas on non-critical workloads to stop pull attempts
kubectl scale deployment <non-critical-app> -n <ns> --replicas=0
```

---

## 4. Permanent Fix: Image Mirroring Strategy

### Priority 1 (Critical Infrastructure):
| Image | Replacement |
|-------|------------|
| `docker.io/calico/*` | Mirror to Harbor or use Calico's official registry `quay.io/calico/*` |
| `hashicorp/vault:*` | Mirror to Harbor or ECR |
| `memcached:*` | Use `public.ecr.aws/docker/library/memcached:*` |
| `nginx:*` | Use `public.ecr.aws/docker/library/nginx:*` |
| `busybox:*` | Use `public.ecr.aws/docker/library/busybox:*` |

### Priority 2 (Observability):
| Image | Replacement |
|-------|------------|
| `docker.io/grafana/*` | Use `grafana/grafana` from Harbor mirror or Grafana's own registry |
| `prom/memcached-exporter:*` | Mirror to Harbor |
| `otel/opentelemetry-collector-contrib:*` | Mirror to Harbor |

### Priority 3 (Applications):
| Image | Replacement |
|-------|------------|
| `goharbor/*` | Mirror to ECR (Harbor images for Harbor itself) |
| `rabbitmq:*` | Use `public.ecr.aws/docker/library/rabbitmq:*` |
| `rabbitmqoperator/*` | Mirror to Harbor |
| `sonarqube:*` | Mirror to Harbor |
| `velero/velero:*` | Mirror to Harbor |
| `python:*` | Use `public.ecr.aws/docker/library/python:*` |

### Implementation: CronJob for Mirror Sync

Deploy a Kubernetes CronJob or CI pipeline that periodically mirrors critical Docker Hub images to Harbor/ECR, so the cluster never needs to pull directly from Docker Hub during operations.

---

## 5. Escalation Path

| Severity | Action | Who |
|----------|--------|-----|
| 1-5 pods affected | Fix via cached node or IfNotPresent | On-call SRE |
| 5-20 pods affected | Mirror critical images + authenticate | SRE team |
| 20+ pods / cluster-wide | Page SRE lead + stop deployments + mass mirror | SRE lead + Platform team |
| Calico/CNI affected | CRITICAL — network plane at risk | SRE lead + AWS support |

---

## 6. Post-Mortem Checklist

- [ ] Document which images caused the outage
- [ ] Confirm all critical images are mirrored to Harbor/ECR
- [ ] Verify Docker Hub authentication is configured cluster-wide
- [ ] Review CronJob mirror schedule covers all needed images
- [ ] Update Helm values to use mirrored image references
- [ ] Add imagePullPolicy: IfNotPresent where appropriate
- [ ] Validate alerts fired correctly and within expected latency
