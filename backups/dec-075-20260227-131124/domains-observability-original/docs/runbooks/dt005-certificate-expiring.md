# Runbook: CertificateExpiringSoon

- **Alert Name**: `CertificateExpiringSoonWarning` / `CertificateExpiringSoonCritical`
- **Severity**: `warning` (<30 days) / `critical` (<7 days)
- **Source**: DT-005 Security Alerts
- **Description**: A TLS certificate managed by cert-manager is approaching expiration. cert-manager should auto-renew, so this alert usually indicates a renewal failure.

---

## 1. Initial Triage

1. **Check the certificate status**:
   ```bash
   kubectl get certificate <cert-name> -n <namespace>
   kubectl describe certificate <cert-name> -n <namespace>
   ```

2. **Check all certificates cluster-wide**:
   ```bash
   kubectl get certificates --all-namespaces -o wide
   ```

3. **Check cert-manager controller health**:
   ```bash
   kubectl get pods -n cert-manager
   kubectl logs -n cert-manager -l app=cert-manager --tail=100
   ```

## 2. Diagnostic Steps

1. **Check CertificateRequest status**:
   ```bash
   kubectl get certificaterequest -n <namespace>
   kubectl describe certificaterequest -n <namespace> <cert-request-name>
   ```

2. **Check the Issuer/ClusterIssuer**:
   ```bash
   kubectl get clusterissuer -o wide
   kubectl describe clusterissuer <issuer-name>
   ```

3. **Check for ACME challenge failures** (if using Let's Encrypt):
   ```bash
   kubectl get challenges -n <namespace>
   kubectl describe challenge -n <namespace> <challenge-name>
   # Check Orders
   kubectl get orders -n <namespace>
   ```

4. **Common failure causes**:
   - DNS not resolving to the correct IP (DNS-01 challenge)
   - HTTP-01 challenge endpoint not reachable (ingress misconfigured)
   - ACME account rate limited
   - cert-manager CRDs out of date
   - ClusterIssuer credentials expired

5. **Verify the actual certificate expiration**:
   ```bash
   kubectl get secret <tls-secret-name> -n <namespace> -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates
   ```

## 3. Mitigation / Resolution

- **Force certificate renewal**:
  ```bash
  # Delete the CertificateRequest to trigger re-issuance
  kubectl delete certificaterequest -n <namespace> -l cert-manager.io/certificate-name=<cert-name>

  # Or annotate the Certificate to force renewal
  kubectl annotate certificate <cert-name> -n <namespace> cert-manager.io/renew-before=720h --overwrite

  # Monitor renewal progress
  kubectl get certificate <cert-name> -n <namespace> -w
  ```

- **ACME account issues**:
  ```bash
  # Check ACME account
  kubectl get secret -n cert-manager -l cert-manager.io/private-key=true
  # Recreate the issuer if needed
  kubectl delete clusterissuer <issuer-name>
  kubectl apply -f <issuer-manifest.yaml>
  ```

- **Emergency: Manual certificate** (temporary):
  ```bash
  # Generate a self-signed certificate as a stopgap
  openssl req -x509 -newkey rsa:4096 -keyout tls.key -out tls.crt -days 30 -nodes -subj '/CN=<domain>'
  kubectl create secret tls <tls-secret-name> -n <namespace> --cert=tls.crt --key=tls.key --dry-run=client -o yaml | kubectl apply -f -
  ```

## 4. Post-Mortem

- Investigate why cert-manager failed to auto-renew
- Review cert-manager version and CRD compatibility
- Check for DNS or network issues that blocked ACME challenges
- Set up a separate monitoring for cert-manager health
- Consider using the cert-manager Prometheus exporter for better visibility
