# GOV-005: Keycloak SSO Governance & Best Practices

> **Versão**: 1.0
> **Data**: 2026-02-27
> **Status**: Ativo
> **Referências**: ADR-046, ADR-055
> **Audiência**: Desenvolvedores, Platform Team, Security Team

---

## Visão Geral

Keycloak é a plataforma SSO centralizada para autenticação e autorização via OIDC/SAML.
Integra ArgoCD, SonarQube, GitLab e Grafana em um único identity provider.

**Decisão Arquitetural**: Keycloak self-hosted — [ADR-046](../adr/adr-046-keycloak-sso-strategy.md).

---

## Arquitetura

```
┌─────────────────────────────────────────────┐
│              Keycloak (SSO)                  │
│         keycloak.platform.svc               │
│                                             │
│  Realm: k8s-platform                        │
│  ├── Client: argocd          (OIDC)         │
│  ├── Client: sonarqube       (OIDC)         │
│  ├── Client: grafana         (OIDC)         │
│  ├── Client: gitlab          (OIDC)         │
│  └── Client: {nova-app}     (OIDC/SAML)    │
│                                             │
│  Identity Provider: PostgreSQL RDS          │
│  HA: StatefulSet (2 replicas)               │
└─────────────────────────────────────────────┘
```

---

## Naming Conventions

### Realm

```yaml
Formato: k8s-platform (único realm para toda a plataforma)
Nota: Não criar realms adicionais sem aprovação explícita
```

### Client IDs

```yaml
Formato: {produto}
Regex: ^[a-z0-9-]+$

Exemplos:
✅ argocd
✅ sonarqube
✅ grafana
✅ rpa-exemplo

❌ ArgoCD                # CamelCase proibido
❌ rpa_exemplo           # Underscore proibido (usar hyphen)
```

### Roles

```yaml
Formato: {escopo}:{ação}
Exemplos:
✅ admin:full-access
✅ developer:read-write
✅ viewer:read-only

Group Mapping:
  platform-team     → admin:full-access
  {domain}-team     → developer:read-write (próprio domínio)
  {domain}-team     → viewer:read-only (outros domínios)
```

---

## Onboarding de Novo Client OIDC

### Pré-requisitos

- Keycloak operacional no realm `k8s-platform`
- Vault configurado com path `secret/keycloak/{produto}`

### Processo

1. **Criar Client no Keycloak**:
   ```
   Client ID: {produto}
   Protocol: openid-connect
   Access Type: confidential
   Valid Redirect URIs: https://{produto}.{domain}/callback
   Web Origins: https://{produto}.{domain}
   ```

2. **Armazenar Client Secret no Vault**:
   ```bash
   vault kv put secret/keycloak/{produto} \
     client-id="{produto}" \
     client-secret="$(keycloak-admin get-client-secret {produto})"
   ```

3. **Criar ExternalSecret**:
   ```yaml
   apiVersion: external-secrets.io/v1beta1
   kind: ExternalSecret
   metadata:
     name: {produto}-oidc
     namespace: {namespace}
   spec:
     refreshInterval: 1h
     secretStoreRef:
       name: vault-backend
       kind: ClusterSecretStore
     target:
       name: {produto}-oidc-secret
     data:
       - secretKey: client-id
         remoteRef:
           key: secret/data/keycloak/{produto}
           property: client-id
       - secretKey: client-secret
         remoteRef:
           key: secret/data/keycloak/{produto}
           property: client-secret
   ```

4. **Configurar aplicação** para usar OIDC endpoints:
   ```yaml
   OIDC_ISSUER: https://keycloak.{domain}/realms/k8s-platform
   OIDC_CLIENT_ID: {produto}
   OIDC_CLIENT_SECRET: (via ExternalSecret)
   ```

### Runbook

- [Keycloak Client Creation](../runbooks/keycloak-client-creation.md)

---

## PKCE Configuration

**Decisão**: PKCE desabilitado para ArgoCD v2.9.3+ — [ADR-055](../adr/adr-055-disable-pkce-argocd-v293.md).

Para novos clients:
- **SPA/Frontend**: Habilitar PKCE (public client)
- **Backend/Server**: Desabilitar PKCE (confidential client)

---

## Group/Role Mapping

| Keycloak Group | ArgoCD Role | Grafana Role | SonarQube | Kubernetes |
|----------------|-------------|--------------|-----------|------------|
| `platform-admins` | admin | Admin | admin | cluster-admin |
| `{domain}-leads` | proj:admin | Editor | group-admin | namespace-admin |
| `{domain}-devs` | proj:read-only | Viewer | user | namespace-developer |
| `viewers` | read-only | Viewer | user | view-only |

---

## Security Best Practices

1. **Confidential clients**: Sempre usar `Access Type: confidential` para backends
2. **Redirect URI specificity**: Nunca usar wildcards (`*`) em redirect URIs
3. **Token lifetimes**: Access token = 5min, Refresh token = 30min, SSO session = 8h
4. **Brute force protection**: Habilitar (max 5 attempts, lockout 5min)
5. **Password policies**: Mínimo 12 chars, uppercase, lowercase, digit, special char
6. **Secrets via Vault**: Nunca hardcode client secrets (GOV-006)
7. **HTTPS only**: Keycloak acessível apenas via HTTPS (TLS termination no ALB)

---

## Monitoring

| Métrica | Alerta | Threshold |
|---------|--------|-----------|
| Login failures | `KeycloakLoginFailures` | > 50/min |
| Active sessions | `KeycloakHighSessions` | > 1000 |
| Token issuance latency | `KeycloakSlowTokens` | > 2s p99 |
| Pod restarts | `KeycloakPodRestart` | > 0 |

---

## Referências

- [ADR-046: Keycloak SSO Strategy](../adr/adr-046-keycloak-sso-strategy.md)
- [ADR-055: Disable PKCE ArgoCD](../adr/adr-055-disable-pkce-argocd-v293.md)
- [Bootstrap Guide](../../platform-provisioning/aws/kubernetes/terraform/scripts/keycloak/BOOTSTRAP_GUIDE.md)
- [Keycloak Client Creation Runbook](../runbooks/keycloak-client-creation.md)
- [Vendor: Keycloak](../vendor/keycloak.md)
