# Runbook: ExternalSecretSyncFailure

- **Alert Name**: `ExternalSecretSyncFailure` / `ExternalSecretSyncFailureCritical` / `MultipleExternalSecretsNotReady`
- **Severity**: `warning` (>10 min) / `critical` (>30 min or multiple failures)
- **Source**: DT-005 Security Alerts
- **Description**: The External Secrets Operator (ESO) has failed to sync one or more secrets from the backend store (Vault). The Kubernetes Secret may contain stale or missing credentials.

---

## 1. Initial Triage

1. **Check ExternalSecret status**:
   ```bash
   kubectl get externalsecret <name> -n <namespace> -o yaml
   kubectl get externalsecret -A | grep -v "SecretSynced"
   ```

2. **Check ESO controller pods**:
   ```bash
   kubectl get pods -n external-secrets
   kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=100
   ```

3. **Check the ClusterSecretStore**:
   ```bash
   kubectl get clustersecretstore -o wide
   kubectl describe clustersecretstore vault-backend
   ```

## 2. Diagnostic Steps

1. **Check ExternalSecret conditions**:
   ```bash
   kubectl get externalsecret <name> -n <namespace> -o jsonpath='{.status.conditions}' | jq .
   ```
   Look for the error message in the `Ready` condition.

2. **Common failure causes**:

   - **Vault sealed/down**: Check Vault status (see Vault runbook)
   - **Secret path not found**: The secret was deleted or moved in Vault
   - **Permission denied**: Vault policy changed, denying access
   - **Network error**: ESO cannot reach Vault service
   - **ESO controller crash**: Check ESO pod health

3. **Check Vault directly** to verify the secret exists:
   ```bash
   kubectl exec -n vault vault-0 -- vault kv get <secret-path>
   ```

4. **Check IRSA/authentication**:
   ```bash
   kubectl describe sa external-secrets -n external-secrets | grep "eks.amazonaws.com/role-arn"
   ```

5. **Check the Kubernetes Secret** (is it stale?):
   ```bash
   kubectl get secret <target-secret-name> -n <namespace> -o jsonpath='{.metadata.annotations}'
   kubectl get secret <target-secret-name> -n <namespace> -o jsonpath='{.metadata.creationTimestamp}'
   ```

## 3. Mitigation / Resolution

- **Force sync**:
  ```bash
  kubectl annotate externalsecret <name> -n <namespace> force-sync=$(date +%s) --overwrite
  ```

- **Vault is sealed/down**: Follow the Vault runbook to unseal or restart Vault.

- **Secret path changed**: Update the ExternalSecret manifest with the correct path:
  ```bash
  kubectl edit externalsecret <name> -n <namespace>
  ```

- **Permission denied**: Update the Vault policy:
  ```bash
  vault policy write <policy-name> <policy-file.hcl>
  ```

- **ESO controller issues**: Restart the controller:
  ```bash
  kubectl rollout restart deployment/external-secrets -n external-secrets
  ```

- **Emergency: Manual secret creation** (if ESO cannot be fixed immediately):
  ```bash
  # Get the secret value from Vault directly
  vault kv get -format=json <secret-path> | jq -r '.data.data'

  # Create/update the Kubernetes secret manually
  kubectl create secret generic <secret-name> -n <namespace> \
    --from-literal=<key>=<value> --dry-run=client -o yaml | kubectl apply -f -
  ```
  NOTE: This is a temporary workaround. Fix ESO to resume automated sync.

## 4. Post-Mortem

- Document which secrets were affected and for how long
- Review Vault policies and access patterns
- Consider lowering the refreshInterval for critical secrets
- Implement monitoring for ClusterSecretStore health
- Set up alerts for ESO controller pod health
- Review ExternalSecret error handling and retry policies
