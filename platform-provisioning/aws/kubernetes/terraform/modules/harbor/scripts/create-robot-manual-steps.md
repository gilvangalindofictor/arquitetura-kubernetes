# Harbor Robot Account - Manual Creation (UI)

**Context:** Harbor API robot creation endpoint returning 401 unauthorized despite valid credentials. Using UI as workaround.

## Prerequisites

- kubectl access to cluster
- Harbor admin password: stored in secret `harbor-admin-password`

## Steps

### 1. Get Admin Password

```bash
export HARBOR_ADMIN_PASSWORD=$(kubectl get secret harbor-admin-password \
  -n harbor-system -o jsonpath='{.data.password}' | base64 -d)
echo "Password: $HARBOR_ADMIN_PASSWORD"
```

### 2. Port-Forward Harbor UI

```bash
# Kill any existing port-forward
pkill -f "kubectl port-forward.*harbor"

# Forward harbor service to localhost
kubectl port-forward -n harbor-system svc/harbor 8080:80 &

# Wait for port-forward to be ready
sleep 3
curl -s http://localhost:8080 > /dev/null && echo "✓ Harbor UI accessible at http://localhost:8080"
```

### 3. Login to Harbor UI

1. Open browser: http://localhost:8080
2. Login with:
   - Username: `admin`
   - Password: `$HARBOR_ADMIN_PASSWORD`

### 4. Create Robot Account

1. Click on **Projects** → **library**
2. Go to **Robot Accounts** tab
3. Click **+ NEW ROBOT ACCOUNT**
4. Configure:
   - **Name:** `gitlab-ci`
   - **Description:** `GitLab CI/CD pipeline robot account`
   - **Expiration:** Never expire (or 365 days)
   - **Permissions:** Select **library** project
     - ✓ Push repository
     - ✓ Pull repository
     - ✓ Delete artifact
5. Click **ADD**
6. **IMPORTANT:** Copy the generated token immediately (shown once!)

### 5. Save Credentials

```bash
# Replace <TOKEN> with the generated token from UI
ROBOT_NAME="robot\$gitlab-ci"
ROBOT_TOKEN="<TOKEN>"

echo "Harbor Registry: harbor-core.harbor-system.svc.cluster.local"
echo "Robot Name: $ROBOT_NAME"
echo "Robot Token: $ROBOT_TOKEN"
```

### 6. Test Docker Login

```bash
# From within cluster (or with proper network access)
docker login harbor-core.harbor-system.svc.cluster.local \
  -u "$ROBOT_NAME" \
  -p "$ROBOT_TOKEN"
```

### 7. Add to GitLab CI/CD Variables

In GitLab project → Settings → CI/CD → Variables:

| Variable | Value | Masked |
|----------|-------|--------|
| `HARBOR_REGISTRY` | `harbor-core.harbor-system.svc.cluster.local` | No |
| `HARBOR_PROJECT` | `library` | No |
| `HARBOR_USER` | `robot$gitlab-ci` | No |
| `HARBOR_PASSWORD` | `<TOKEN from step 4>` | Yes |

### 8. GitLab CI Example

```yaml
# .gitlab-ci.yml
variables:
  HARBOR_REGISTRY: harbor-core.harbor-system.svc.cluster.local
  HARBOR_PROJECT: library

build:
  image: docker:latest
  services:
    - docker:dind
  script:
    - docker login $HARBOR_REGISTRY -u "$HARBOR_USER" -p "$HARBOR_PASSWORD"
    - docker build -t $HARBOR_REGISTRY/$HARBOR_PROJECT/myapp:$CI_COMMIT_SHA .
    - docker push $HARBOR_REGISTRY/$HARBOR_PROJECT/myapp:$CI_COMMIT_SHA
```

## Troubleshooting

### API Returns 401 Unauthorized

**Known Issue:** Harbor v2.10.0 robot account API endpoints may return unauthorized even with valid admin credentials.

**Root Cause:** Unclear - possibly password hash mismatch in PostgreSQL or permissions issue.

**Workaround:** Use UI-based creation (this document).

**Future Fix:** Investigate PostgreSQL harbor_user table password hash and Harbor authentication flow.

### Port-Forward Fails (Address Already in Use)

```bash
# Find and kill process using port 8080
lsof -ti:8080 | xargs kill -9

# Or use different port
kubectl port-forward -n harbor-system svc/harbor 8888:80
# Access: http://localhost:8888
```

### Cannot Access Harbor UI from Browser

Ensure port-forward is running and check firewall rules.

## Next Steps

- [ ] Create robot account `gitlab-ci` via UI
- [ ] Test docker login with robot credentials
- [ ] Add credentials to GitLab CI/CD variables
- [ ] Update GitLab CI pipelines to use Harbor
- [ ] Document robot account in architecture.md
- [ ] Investigate Harbor API auth issue (future sprint)
