# 🚨 PRIORITY 1 ACTION REQUIRED: Start RDS PostgreSQL

**Status:** BLOCKED - Manual intervention needed
**Impact:** GitLab platform down for 2h 40min+
**Action:** Start RDS instance via AWS Console

---

## Quick Fix (2 minutes)

1. **Open AWS Console:**
   https://us-east-1.console.aws.amazon.com/rds/home?region=us-east-1

2. **Find Database:**
   - Name: `k8s-platform-prod-postgresql`
   - Status should show: **Stopped**

3. **Start It:**
   - Select checkbox
   - Actions → Start
   - Confirm

4. **Wait:**
   - 5-10 minutes for status → "Available"

5. **Verify:**
   - GitLab pods will auto-recover within 5 minutes
   - Run: `kubectl get pods -n staging-platform-gitlab`
   - Should see: `gitlab-webservice-* 2/2 Running`

---

## Why This Happened

**Root Cause:** RDS weekend shutdown automation affected production database

**Evidence:**
- Connectivity test from pod: TIMEOUT (not connection refused)
- Weekend timing
- Project has RDS shutdown automation for cost savings

---

## After RDS Starts

**Auto-Recovery (No Action Needed):**
- GitLab dependencies init container will complete
- Webservice pods will start (2/2 Running)
- Sidekiq will start (1/1 Running)
- Runner will stop crashlooping
- Sprint 3 unblocked

**Validation:**
```bash
# Watch recovery
kubectl get pods -n staging-platform-gitlab -w

# Test GitLab UI
kubectl port-forward -n staging-platform-gitlab svc/gitlab-webservice-default 8080:8080
curl -I http://localhost:8080  # Should get HTTP 200 or 302
```

---

## Prevention (After Recovery)

1. **Tag RDS to exclude from shutdown:**
   ```bash
   aws rds add-tags-to-resource \
     --resource-name arn:aws:rds:us-east-1:ACCOUNT:db:k8s-platform-prod-postgresql \
     --tags Key=AutoShutdown,Value=false
   ```

2. **Add RDS state monitoring:**
   - CloudWatch alarm on instance stopped
   - Alert to Slack/PagerDuty

3. **Separate staging/prod RDS:**
   - Create dedicated staging RDS
   - Keep production always-on

---

## Documents Created

1. **Incident Report (Detailed):**
   `/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/logbook/2026-02-27-rds-postgresql-outage-incident.md`
   - Full timeline, root cause analysis, prevention steps

2. **Runbook (Future Reference):**
   `/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/runbooks/rds-emergency-start.md`
   - Step-by-step recovery procedure
   - Validation steps
   - Common issues

---

## Current Pod Status

```
NAMESPACE: staging-platform-gitlab

NAME                                          READY   STATUS     RESTARTS
gitlab-webservice-default-67db8fc7d4-69zzn    0/2     Init:2/3   3
gitlab-webservice-default-67db8fc7d4-dx2fm    0/2     Init:2/3   3
gitlab-sidekiq-all-in-1-v2-684876b4bf-clrdp   0/1     Init:2/3   3
gitlab-gitlab-runner-5cc8c8d67b-rgrgq         0/1     Running    42 ⚠️

✅ Working: gitaly, registry, kas, gitlab-shell, gitlab-exporter
❌ Blocked: webservice, sidekiq (waiting for DB)
⚠️  Crashloop: runner (can't reach GitLab API)
```

---

**Next Step:** Start RDS, then validate with `kubectl get pods -n staging-platform-gitlab`

**ETA to Recovery:** 15 minutes after RDS start initiated
