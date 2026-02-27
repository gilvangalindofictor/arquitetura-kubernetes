# Runbook: VaultSealedAlert / VaultDown

- **Alert Name**: `VaultSealedAlert` / `VaultDown`
- **Severity**: `critical`
- **Source**: DT-005 Security Alerts
- **Description**: HashiCorp Vault is either sealed (cannot process requests) or completely down. When Vault is sealed, no secrets can be read or written. All applications using Vault via External Secrets Operator (ESO) or direct API will be affected.

---

## 1. Initial Triage

1. **Check Vault pod status**:
   ```bash
   kubectl get pods -n vault -l app.kubernetes.io/name=vault -o wide
   ```

2. **Check Vault seal status**:
   ```bash
   kubectl exec -n vault vault-0 -- vault status
   ```

3. **Check Vault logs**:
   ```bash
   kubectl logs -n vault vault-0 --tail=200
   ```

4. **Check ExternalSecrets depending on Vault**:
   ```bash
   kubectl get externalsecret -A | grep -v "SecretSynced"
   ```

## 2. Diagnostic Steps

### Vault Sealed:

1. **Check why Vault was sealed**:
   ```bash
   kubectl logs -n vault vault-0 --tail=500 | grep -i "seal\|unseal\|barrier"
   ```

2. **Common causes of auto-seal**:
   - Pod restart (Vault seals on restart)
   - AWS KMS key access lost (if auto-unseal configured)
   - Storage backend (Raft/Consul) corruption
   - Manual seal command issued

3. **Check KMS auto-unseal** (if configured):
   ```bash
   # Check the Vault config for KMS settings
   kubectl exec -n vault vault-0 -- cat /vault/config/extraconfig-from-values.hcl | grep -A5 "seal"
   # Check IAM role permissions
   kubectl describe sa vault -n vault | grep "eks.amazonaws.com/role-arn"
   ```

### Vault Down:

1. **Check pod status and events**:
   ```bash
   kubectl describe pod vault-0 -n vault
   kubectl get events -n vault --sort-by='.lastTimestamp'
   ```

2. **Check storage backend**:
   ```bash
   # For Raft storage
   kubectl exec -n vault vault-0 -- vault operator raft list-peers
   # Check PVC
   kubectl get pvc -n vault
   ```

3. **Check node scheduling**:
   ```bash
   kubectl get node -o wide
   # Vault may have nodeAffinity or tolerations
   kubectl get pod vault-0 -n vault -o jsonpath='{.spec.nodeSelector}' | jq .
   ```

## 3. Mitigation / Resolution

### Vault Sealed:

- **Unseal with KMS** (auto-unseal should happen on restart):
  ```bash
  kubectl delete pod vault-0 -n vault
  # Wait for pod to restart and auto-unseal
  kubectl logs -n vault vault-0 -f | grep -i unseal
  ```

- **Manual unseal** (if Shamir keys are used):
  ```bash
  kubectl exec -n vault vault-0 -- vault operator unseal <key-1>
  kubectl exec -n vault vault-0 -- vault operator unseal <key-2>
  kubectl exec -n vault vault-0 -- vault operator unseal <key-3>
  ```

- **Fix KMS access** (if auto-unseal failure):
  1. Check IRSA role still exists and has KMS permissions
  2. Check KMS key is not disabled or deleted
  3. Verify the KMS key policy allows the Vault service account role

### Vault Down:

- **Restart pod**:
  ```bash
  kubectl delete pod vault-0 -n vault
  ```

- **Raft storage recovery**:
  ```bash
  kubectl exec -n vault vault-0 -- vault operator raft list-peers
  # If peers are disconnected, may need to rejoin
  ```

- **Emergency: Read-only mode**:
  If Vault cannot be recovered immediately, applications with cached secrets will continue to work until their secrets expire.

## 4. Post-Mortem

- Document why Vault sealed or went down
- Verify auto-unseal is properly configured and tested
- Ensure Vault HA is enabled (multiple replicas)
- Review Vault audit logs for any security events
- Test the unseal procedure regularly
- Document the location of Shamir keys (if applicable) in a secure vault
