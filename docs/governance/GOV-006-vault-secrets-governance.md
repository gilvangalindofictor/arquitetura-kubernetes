# GOV-006: Vault & Secrets Management Governance

> **Versão**: 1.0
> **Data**: 2026-02-27
> **Status**: Ativo
> **Referências**: ADR-003, ADR-083, domains/secrets-management
> **Audiência**: Desenvolvedores, Platform Team, Security Team

---

## Visão Geral

HashiCorp Vault é o secrets management centralizado. Integração com Kubernetes via **External Secrets Operator (ESO)** para injetar secrets como Kubernetes Secrets.

**Decisão Arquitetural**: Vault + ESO — [ADR-003](../adr/adr-003-secrets-management-strategy.md).

---

## Arquitetura

```
┌──────────────────┐     ┌─────────────────────┐     ┌──────────────┐
│ HashiCorp Vault  │────>│ External Secrets     │────>│ K8s Secret   │
│ (KV v2 engine)   │     │ Operator (ESO)       │     │ (auto-sync)  │
│                  │     │ ClusterSecretStore   │     │              │
│ secret/data/...  │     │ ExternalSecret CR    │     │ Pods mount   │
└──────────────────┘     └─────────────────────┘     └──────────────┘
```

---

## Naming Conventions

### Vault KV Paths

```yaml
Formato: secret/{domain}/{produto}/{secret-name}
Regex: ^secret/(platform|integration|data|operations|shared-services)/[a-z0-9-]+/[a-z0-9-]+$

Exemplos:
✅ secret/data/rpa-exemplo/db-password
✅ secret/data/rpa-exemplo/redis-auth
✅ secret/integration/ipaas/api-key
✅ secret/platform/argocd/oidc-secret
✅ secret/platform/grafana/admin-password

❌ secret/rpa-exemplo/db-password       # Falta domain
❌ secret/Data/RPA/password             # Uppercase proibido
```

### ExternalSecret Names

```yaml
Formato: {produto}-{secret-type}
Regex: ^[a-z0-9-]+-[a-z0-9-]+$

Exemplos:
✅ rpa-exemplo-db-credentials
✅ ipaas-redis-auth
✅ argocd-oidc-secret
✅ grafana-admin-secret
```

### Kubernetes Secret Names (Target)

```yaml
Formato: {produto}-{secret-type}-secret
Exemplos:
✅ rpa-exemplo-db-credentials-secret
✅ ipaas-redis-auth-secret
```

---

## ExternalSecret Template

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: {produto}-{secret-type}
  namespace: {namespace}
  labels:
    domain: {domain}
    product: {produto}
    managed-by: external-secrets
spec:
  refreshInterval: 1h                    # Sync interval
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: {produto}-{secret-type}-secret
    creationPolicy: Owner                # ESO owns the secret
  data:
    - secretKey: username
      remoteRef:
        key: secret/data/{domain}/{produto}/{secret-type}
        property: username
    - secretKey: password
      remoteRef:
        key: secret/data/{domain}/{produto}/{secret-type}
        property: password
```

---

## Vault Policies

### Policy per Domain

```hcl
# policy: {domain}-read
path "secret/data/{domain}/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/{domain}/*" {
  capabilities = ["read", "list"]
}
```

### Policy per Product

```hcl
# policy: {domain}-{produto}-read
path "secret/data/{domain}/{produto}/*" {
  capabilities = ["read", "list"]
}
```

### IRSA Authentication

```yaml
# Kubernetes ServiceAccount → Vault Role → Policy
# IAM Role ARN → Vault auth/kubernetes role

Vault Role: {domain}-{produto}
Bound SA: {produto}-sa
Bound NS: {namespace}
Policies: [{domain}-{produto}-read]
```

---

## Secret Rotation

**Referência**: [ADR-083: Automated Secret Rotation](../adr/adr-083-automated-secret-rotation-strategy.md)

### Rotation Schedule

| Secret Type | Rotation Period | Method |
|-------------|----------------|--------|
| Database passwords | 90 dias | Automated (Vault dynamic secrets) |
| API keys | 180 dias | Manual + notification |
| OIDC client secrets | 365 dias | Manual (Keycloak admin) |
| TLS certificates | Auto-renewal | cert-manager |

### Emergency Rotation

- [Secret Rotation Emergency Manual](../runbooks/secret-rotation-emergency-manual.md)
- [Secret Rotation Troubleshooting](../runbooks/secret-rotation-troubleshooting.md)

---

## Proibições

```yaml
NUNCA:
  - Hardcode secrets em código fonte
  - Commit secrets em Git (TruffleHog detecta)
  - Usar Kubernetes Secrets sem ESO (não criptografados at rest)
  - Compartilhar secrets entre environments (staging ≠ prod)
  - Usar secrets de plataforma em aplicações de domínio

SEMPRE:
  - Vault KV v2 + ExternalSecrets
  - Secrets com TTL/rotation
  - Audit trail via Vault audit log
  - Least-privilege policies
```

---

## Monitoring

| Métrica | Alerta | Threshold |
|---------|--------|-----------|
| Vault sealed | `VaultSealed` | sealed = true |
| Secret sync failures | `ESOSyncFailed` | > 0 failures/5min |
| Lease expiration | `VaultLeaseExpiring` | < 7 days |
| Auth failures | `VaultAuthFailures` | > 10/min |

### Runbooks

- [Vault Sealed](../../domains/observability/docs/runbooks/dt005-vault-sealed.md)
- [Secret Rotation Policy](../runbooks/secret-rotation-policy.md)

---

## Best Practices

1. **Least-privilege**: Cada app acessa apenas seus próprios secrets
2. **RefreshInterval**: 1h para secrets estáticos; 15min para secrets dinâmicos
3. **CreationPolicy: Owner**: ESO gerencia lifecycle do K8s Secret
4. **Audit Vault logs**: `vault audit list` — todo acesso é logado
5. **Backup Vault**: Raft snapshots diários via Velero
6. **Nunca usar `root` token**: Criar tokens com policies específicas
7. **ExternalSecret por secret**: 1 ExternalSecret = 1 Kubernetes Secret (não agrupar)

---

## Referências

- [ADR-003: Secrets Management Strategy](../adr/adr-003-secrets-management-strategy.md)
- [ADR-083: Automated Secret Rotation](../adr/adr-083-automated-secret-rotation-strategy.md)
- [Vault Architecture ADR](../../domains/secrets-management/docs/adr/adr-002-vault-architecture.md)
- [Secret Rotation Policy](../runbooks/secret-rotation-policy.md)
