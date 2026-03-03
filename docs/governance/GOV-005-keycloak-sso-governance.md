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

## Identity Federation — Entra ID (Planejado)

> **Status**: 📝 Planejado (2026-03-03) — INFRA-003
> **ADRs**: ADR-095, ADR-096, ADR-097

### Arquitetura Futura

```
Microsoft Entra ID (Corporate Identity Source)
        │ OIDC v2.0
        ▼
Keycloak (Authorization Hub)
├── Identity Brokering (Entra ID → local user JIT)
├── Group Sync (Entra ID Security Groups → Keycloak Groups)
├── Realm Roles (platform-admin, platform-developer, platform-viewer)
├── Client Roles (per-app: order-manager, report-viewer)
├── Authorization Services (Resources, Scopes, Policies, Permissions)
└── Token Enrichment (custom claims: department, cost_center)
        │
        ├── OIDC/SAML → Platform Tools (GitLab, ArgoCD, Grafana, etc.)
        └── AuthZ API (UMA 2.0) → Business Applications
```

### Princípios de Governança para Federation

1. **Groups = Identidade organizacional** (fonte: Entra ID, sync automático)
2. **Roles = Permissão técnica** (fonte: Keycloak, gerenciado via Terraform)
3. **Break-glass accounts**: Manter contas locais com MFA TOTP para emergências
4. **Session lifetimes**: SSO idle 15min, SSO max 4h (reduzir de 8h para mitigar sync lag)
5. **Backchannel logout**: Obrigatório em todos os clients OIDC
6. **Audit logging**: Obrigatório — eventos Keycloak → Loki (BACEN BCB 85/2021)
7. **Entra ID client secret**: Incluir na rotação trimestral (ADR-083)

### Naming Conventions — Roles

```yaml
Realm Roles:
  Formato: {escopo}-{nível}
  Exemplos: platform-admin, deploy-viewer

Client Roles:
  Formato: {recurso}-{ação}
  Exemplos: order-manager, report-exporter

Groups (sync Entra ID):
  Formato: {equipe}-team
  Exemplos: platform-team, integration-team, data-team
```

### Onboarding de Aplicação de Negócio (com Authorization Services)

1. Criar OIDC client com `authorization_services_enabled = true` (Terraform)
2. Definir Resources (ex: `api:/orders`, `api:/reports`)
3. Definir Scopes (ex: `read`, `write`, `approve`)
4. Criar Policies (role-based, group-based, time-based)
5. Criar Permissions (bind resources + scopes + policies)
6. App consome via `POST /token` com `grant_type=uma-ticket`
7. Armazenar client secret no Vault KV `secret/keycloak/{produto}`

---

## Referências

- [ADR-046: Keycloak SSO Strategy](../adr/adr-046-keycloak-sso-strategy.md)
- [ADR-055: Disable PKCE ArgoCD](../adr/adr-055-disable-pkce-argocd-v293.md)
- [ADR-095: Entra ID Identity Federation](../adr/adr-095-entra-id-identity-federation.md)
- [ADR-096: Keycloak Authorization Services](../adr/adr-096-keycloak-authorization-services.md)
- [ADR-097: Role vs Group Strategy](../adr/adr-097-role-vs-group-strategy.md)
- [Bootstrap Guide](../../platform-provisioning/aws/kubernetes/terraform/scripts/keycloak/BOOTSTRAP_GUIDE.md)
- [Keycloak Client Creation Runbook](../runbooks/keycloak-client-creation.md)
- [Vendor: Keycloak](../vendor/keycloak.md)
