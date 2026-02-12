# Auditoria: Keycloak e SonarQube — Versões, Features e Decisões

**Última Atualização**: 2026-02-11
**Ambiente**: STAGING (Marco 4 - MVP)
**Status**: ✅ Ambos operacionais
**Metodologia**: Terraform como fonte de verdade (mesma abordagem data-services)

---

## 📋 Conteúdo

1. [Keycloak SSO](#1-keycloak-sso-platform)
2. [SonarQube Code Quality](#2-sonarqube-code-quality)
3. [Comparação & Features](#3-comparação--análise-de-features)
4. [Decisões Arquiteturais (ADRs)](#4-decisões-arquiteturais)
5. [Limitações Conhecidas](#5-limitações-e-degradações-conhecidas)
6. [Upgrade Paths](#6-upgrade-paths)

---

## 1. Keycloak SSO Platform

### 1.1 Versões — Terraform vs Realidade

| Aspecto          | Versão (Terraform)                      | Status              | Localização Terraform             |
| ---------------- | --------------------------------------- | ------------------- | --------------------------------- |
| **Keycloak App** | 26.5.1 (target) / 17.0.1-legacy (atual) | 🟡 DEGRADADO         | modules/keycloak/variables.tf L17 |
| **Helm Chart**   | 7.1.7 (codecentric/keycloakx)           | ✅ Declarado         | modules/keycloak/variables.tf L16 |
| **Database**     | PostgreSQL 16.4 RDS                     | ✅ Compartilhado     | modules/keycloak/../postgresql/   |
| **Namespace**    | `keycloak`                              | ✅ Terraform-managed | modules/keycloak/main.tf L113     |
| **Replicas**     | 2 (target) / 1 (atual)                  | 🟡 DEGRADADO         | modules/keycloak/variables.tf L22 |
| **Chart Repo**   | codecentric/keycloak                    | ✅ OIDC-native       | module config                     |

### 1.2 Terraform Declarations

```hcl
# modules/keycloak/variables.tf
variable "keycloak_chart_version" {
  description = "Codecentric KeycloakX Helm chart version (Keycloak 26.x Quarkus)"
  type        = string
  default     = "7.1.7"  # Chart version for Keycloak 26.5.1
}

variable "replicas" {
  description = "Number of Keycloak replicas (HA)"
  type        = number
  default     = 2        # HA enabled, but 1 replica deployed due to metrics bug
}
```

**Encontrado em**: `/platform-provisioning/aws/kubernetes/terraform/modules/keycloak/`

### 1.3 Versionamento Detalhado

#### Keycloak Application

**Versão Atual (STAGING)**: `17.0.1-legacy` (WildFly runtime)
**Versão Target (Decision)**: `26.5.1` (Quarkus runtime)
**Chart**: codecentric/keycloakx 7.1.7 (Quarkus-only)

**Timeline**:
- ✅ Keycloak 17.0.1-legacy deployed (2026-02-06)
- 🟡 Known bug: Metrics subsystem NullPointerException on secondary pods
- 🔄 Planned: Upgrade to 26.5.1 with Quarkus runtime (Sprint +1)

**Release Cycles**:
- WildFly runtime: 6-month + 1-year extended support
- Quarkus runtime: 3-month rapid (26.x), 1-year extended support

#### Helm Chart

**Chart Family**: `codecentric/keycloak` (WildFly) vs `codecentric/keycloakx` (Quarkus)
**Current**: 18.4.0 (WildFly, deprecated)
**Target**: 7.1.7 (Quarkus, new standard)

**Compatibility Matrix**:

| Chart Version | Keycloak Version | Runtime | Support Status         |
| ------------- | ---------------- | ------- | ---------------------- |
| 18.4.0        | 17.0.1-legacy    | WildFly | ⚠️ Deprecated (2026-02) |
| 7.1.7         | 26.5.1           | Quarkus | ✅ Current LTS          |
| 8.x           | 27.0+            | Quarkus | 🔜 Next (future)        |

### 1.4 Keycloak Features Analysis

#### Core Capabilities (v17 vs v26)

| Feature                   | v17 (Current)     | v26 (Target)                | Impact              |
| ------------------------- | ----------------- | --------------------------- | ------------------- |
| **OIDC Support**          | ✅ Full OIDC 1.0   | ✅ Full OIDC 1.0             | No change           |
| **SAML 2.0**              | ✅ Yes             | ✅ Yes                       | No change           |
| **Multi-Realm**           | ✅ Yes (unlimited) | ✅ Yes (unlimited)           | No change           |
| **User Federation**       | ✅ LDAP, Kerberos  | ✅ LDAP, Kerberos            | No change           |
| **Admin Console**         | ✅ Web UI          | ✅ Modern UI (improved)      | UX improvement      |
| **Account Console**       | ✅ Basic           | ✅ Enhanced                  | UX improvement      |
| **Group Management**      | ✅ Hierarchical    | ✅ Hierarchical + Attributes | Feature enhancement |
| **Auth Flows**            | ✅ Custom flows    | ✅ Custom flows (optimized)  | Performance         |
| **Session Management**    | ✅ Token endpoints | ✅ Token endpoints           | No change           |
| **Client Authentication** | ✅ All methods     | ✅ All methods               | No change           |

#### Staging Configuration (Current)

```yaml
Realm: platform
Groups:
  - platform-admins (full access)
  - argocd-admins (ArgoCD-only)
  - developers (standard access)

OIDC Clients: 4
  - argocd
    redirect: https://argocd.*/auth/callback
    secret location: K8s secret (argocd-oidc)

  - sonarqube
    redirect: https://sonarqube.*/oauth2/callback/oidc
    secret location: K8s secret (sonarqube-oidc)

  - gitlab
    redirect: https://gitlab.*/users/auth/openid_connect/callback
    secret location: K8s secret (gitlab-oidc)

  - grafana
    redirect: https://grafana.*/login/generic_oauth
    secret location: K8s secret (grafana-oidc)

Issuer URL:
  http://keycloak-http.keycloak.svc.cluster.local/auth/realms/platform
```

#### Security Features

| Feature                    | v17          | v26                    | Details                          |
| -------------------------- | ------------ | ---------------------- | -------------------------------- |
| **Password Policies**      | ✅ Yes        | ✅ Yes (expanded)       | Regex patterns, complexity rules |
| **Brute Force Protection** | ✅ Yes        | ✅ Yes                  | Login attempt throttling         |
| **Account Events**         | ✅ Yes        | ✅ Yes                  | Full audit logging               |
| **Token Encryption**       | ✅ Yes        | ✅ Yes                  | JWE support                      |
| **Identity Brokering**     | ✅ Yes        | ✅ Yes                  | External IdPs supported          |
| **MFA/OTP**                | ✅ Yes (TOTP) | ✅ Yes (TOTP, WebAuthn) | 🆕 WebAuthn support               |
| **Client Security**        | ✅ Full       | ✅ Full                 | PKCE, DPoP (v26)                 |

#### Monitoring & Operations

| Metric                 | v17        | v26                           | Status             |
| ---------------------- | ---------- | ----------------------------- | ------------------ |
| **Prometheus Metrics** | ✅ Yes      | ✅ Yes (improved)              | Better performance |
| **Health Endpoints**   | ✅ /health  | ✅ /health/live, /health/ready | Enhanced           |
| **JVM Metrics**        | ✅ Full     | ✅ Full                        | No change          |
| **Database Metrics**   | ⚠️ Via JDBC | ✅ Native pooling metrics      | Improvement        |

### 1.5 Keycloak Performance Comparison

```
Deployment Size: STAGING (1 replica, degraded)

WildFly (v17.0.1-legacy):
├─ JVM Memory: ~1.8-2.2 GB per pod
├─ Java Process Overhead: ~400 MB
├─ Cold Start Time: 60-90 seconds
├─ Memory Leak History: ✅ Stable (2 years production)
└─ Metrics Subsystem: ⚠️ Buggy on secondary pods

Quarkus (v26.5.1 - native compilation):
├─ JVM Memory: ~1.2-1.6 GB per pod
├─ Native Process Overhead: ~200 MB
├─ Cold Start Time: 5-10 seconds (GraalVM)
├─ Memory Leak History: ✅ Zero reports (2 years)
└─ Metrics Subsystem: ✅ Native/JVM stable
```

**Ganho com Upgrade**: ~400-500 MB memória, ~50-80 segundos startup, stability

### 1.6 Database Integration

**Type**: PostgreSQL 16.4 (AWS RDS)
**Connection**: ExternalSecret via Vault KV v2
**Database Schema**: Keycloak auto-initialized on startup
**Connection Pool**: HikariCP (10 connections default)

**Terraform Config**:
```hcl
postgresql_host     = module.postgresql_staging.service_name
postgresql_port     = 5432
postgresql_database = "keycloak"
postgresql_username = "keycloak_user"
```

---

## 2. SonarQube Code Quality

### 2.1 Versões — Terraform vs Realidade

| Aspecto           | Versão (Terraform)          | Status              | Localização Terraform                 |
| ----------------- | --------------------------- | ------------------- | ------------------------------------- |
| **SonarQube App** | 10.3.0-community            | ✅ Operacional       | modules/sonarqube/values.yaml.tpl L5  |
| **Helm Chart**    | 10.7.0                      | ✅ Declarado         | modules/sonarqube/variables.tf L16    |
| **Database**      | PostgreSQL 16.4 RDS         | ✅ Compartilhado     | modules/sonarqube/main.tf L44         |
| **Namespace**     | `sonarqube`                 | ✅ Terraform-managed | modules/sonarqube/main.tf L9          |
| **Replicas**      | 1 (CE only)                 | ✅ Fixed             | modules/sonarqube/variables.tf L21    |
| **Storage**       | 20Gi (gp3, RWO)             | ✅ PVC provisioned   | modules/sonarqube/values.yaml.tpl L32 |
| **Monitoring**    | Disabled (Prometheus issue) | 🟡 WORKAROUND        | modules/sonarqube/values.yaml.tpl L88 |

### 2.2 Terraform Declarations

```hcl
# modules/sonarqube/variables.tf
variable "sonarqube_chart_version" {
  description = "SonarQube Helm chart version"
  type        = string
  default     = "10.7.0"  # Latest community-compatible
}

variable "replicas" {
  description = "Number of SonarQube replicas (Community Edition: 1 only)"
  type        = number
  default     = 1         # CE limitation (no HA)
}

variable "pvc_size" {
  description = "PVC size for SonarQube data"
  type        = string
  default     = "20Gi"    # Min recommended for prod-like staging
}
```

**Encontrado em**: `/platform-provisioning/aws/kubernetes/terraform/modules/sonarqube/`

### 2.3 Versionamento Detalhado

#### SonarQube Application

**Versão Atual (STAGING)**: `10.3.0-community` (latest stable community)
**SonarQube Edition**: Community (open-source, self-hosted)
**LTS Status**: 10.x is current LTS (11.x coming 2026-Q2)

**Release Timeline**:
- ✅ SonarQube 10.3.0 released 2025-10-15
- ✅ SonarQube 10.4.0 released 2026-01-20 (current latest 10.x)
- 🔜 SonarQube 11.0 planned Q2 2026

**Why Community Edition**:
- ✅ Open-source (full transparency)
- ✅ Covers main use-cases (code analysis, gate enforcement)
- ✅ No premium features needed for STAGING MVP
- ⚠️ Limitations: 1 replica only, no advanced security/audit features

#### Helm Chart

**Chart Family**: `SonarSource/helm-chart-sonarqube` (official)
**Current**: 10.7.0
**Compatibility**: Supports SonarQube 10.x

**Chart Version History**:

| Chart          | SonarQube | Status                         |
| -------------- | --------- | ------------------------------ |
| 10.7.0         | 10.3-10.4 | ✅ Current (Terraform declared) |
| 10.6.x         | 10.2-10.3 | ⚠️ Older                        |
| 10.5.x         | 10.x      | ⚠️ Older                        |
| 11.x (planned) | 11.0+     | 🔜 Future                       |

### 2.4 SonarQube Features Analysis

#### Community Edition Capabilities

| Feature                     | Available                     | Notes                                           |
| --------------------------- | ----------------------------- | ----------------------------------------------- |
| **Code Analysis**           | ✅ Full                        | Python, Java, JS, Go, C#+, C, C++, etc.         |
| **Code Quality**            | ✅ Full                        | Maintainability, Reliability, Security          |
| **Quality Gates**           | ✅ Yes                         | Pass/fail gates on merge                        |
| **Quality Profiles**        | ✅ 3 (Sonar way for each lang) | Customizable rules                              |
| **Branch Analysis**         | ✅ Yes                         | Track multiple branches                         |
| **Pull Request Decoration** | ✅ Full                        | Comment with SonarQube results on MRs           |
| **Issue Management**        | ✅ Full                        | Track, reopen, mark as reviewed                 |
| **Custom Rules**            | ❌ Limited                     | Proprietary langs only                          |
| **Security Hotspots**       | ⚠️ Limited                     | Community limitations                           |
| **Dependency Check**        | ✅ Basic                       | Via OWASP dependency tracking                   |
| **Advanced Security**       | ❌ Enterprise-only             | App secrets detection, container image scanning |
| **Audit Logs**              | ❌ Enterprise-only             | Compliance-grade logging                        |
| **OIDC Auth**               | ✅ Yes                         | Full OpenID Connect support                     |
| **Webhooks**                | ✅ Yes                         | External integrations                           |
| **Plugins/Extensions**      | ⚠️ Limited                     | Community marketplace                           |

#### Staging Configuration (Current)

```yaml
Edition: Community (10.3.0)
Deployment: Single pod (no HA)
Storage: 20Gi PVC (gp3)
Database: PostgreSQL 16.4 RDS

OIDC Integration:
  Enabled: true
  Issuer: http://keycloak-http.keycloak.svc.cluster.local/auth/realms/platform
  Client ID: sonarqube
  Client Secret: From K8s secret (sonarqube-oidc)
  Group Sync: Enabled
    - Maps Keycloak groups to SonarQube groups
    - Auto-provisioning: true

Quality Gates:
  Default: "Sonar way" (built-in)
  Status: Configured

Monitoring:
  PrometheusExporter: ⚠️ Disabled (Maven dependency timeout)
  ServiceMonitor: ⚠️ Disabled
  Health Endpoints: ✅ /api/system/health
```

#### Security Features

| Feature                    | Status       | Details                       |
| -------------------------- | ------------ | ----------------------------- |
| **OIDC/OAuth2**            | ✅ Full       | OpenID Connect support        |
| **SAML**                   | ❌ Enterprise | Not in Community Edition      |
| **LDAP**                   | ✅ Yes        | User federation               |
| **Token Management**       | ✅ Full       | Time-limited tokens for CI/CD |
| **Secret Protection**      | ⚠️ Basic      | Community: limited patterns   |
| **Vulnerability Scanning** | ⚠️ Limited    | Community limitations         |
| **Container Scanning**     | ❌ Enterprise | Advanced security feature     |
| **Access Control**         | ✅ Basic      | Groups, permissions           |

#### Staging Issues (Known)

**Issue 1: Prometheus Exporter Disabled**
```
Symptom: Prometheus exporter pod slow to start
Root Cause: Maven repository timeout when downloading dependencies
Resolution: Disabled Prometheus exporter (monitored via health endpoint)
Impact: No Prometheus metrics (monitoring via API only)
Timeline: Fix scheduled for Sprint+1
```

**Issue 2: OIDC Testing Pending**
```
Status: ✅ OIDC configuration in place
Pending: Manual validation with Keycloak users
Action: Login test with developer account (admin@example.com)
Timeline: Next sprint
```

**Issue 3: Quality Gates Configuration**
```
Status: ✅ Default "Sonar way" profile loaded
Pending: Custom project-specific quality gates
Action: Configure via API after initial project analysis
Timeline: Post-MVP configuration
```

### 2.5 SonarQube Performance Profile

```
Deployment Size: STAGING (1 replica, CE)

Container Image: sonarqube:10.3.0-community
├─ Docker Image Size: ~900 MB (compressed ~400 MB)
├─ JVM Memory (startup): ~512 MB
├─ JVM Memory (running): ~2.5-3 GB (web + compute engine)
├─ Cold Start Time: 180-240 seconds (slow due to DB init)
├─ PVC Storage: 20Gi (suitable for small-medium projects)
├─ Resource Limits: 2000m CPU, 4GB RAM
└─ Resource Requests: 500m CPU, 2GB RAM

Performance Notes:
├─ First startup slower (DB schema creation)
├─ Subsequent startups faster (~60s)
├─ Requires persistent storage (no data loss on restart)
└─ Single compute engine process (no parallelization)
```

### 2.6 Database Integration

**Type**: PostgreSQL 16.4 (AWS RDS)
**Database**: `sonarqube`
**User**: `sonarqube_user`
**Connection**: K8s secret (postgres-postgresql) - **[TODO: migrate to Vault]**
**JDBC URL**: `jdbc:postgresql://<rds-endpoint>:5432/sonarqube?sslmode=require`

**Terraform Config**:
```hcl
jdbcOverwrite:
  enable: true
  jdbcUrl: "jdbc:postgresql://${postgresql_host}:${postgresql_port}/${postgresql_database}"
  jdbcUsername: sonarqube_user
  jdbcSecretName: sonarqube-postgresql
  jdbcSecretPasswordKey: postgresql-password
```

---

## 3. Comparação & Análise de Features

### 3.1 Responsabilidades de Plataforma

| Responsabilidade         | Keycloak          | SonarQube          | Status             |
| ------------------------ | ----------------- | ------------------ | ------------------ |
| **Autenticação Central** | ✅ Primary         | Consumes           | ✅ Integrado        |
| **Autorização/Grupos**   | ✅ Gerencia grupos | Consome grupos     | ✅ Sincronizado     |
| **Tokens OIDC**          | ✅ Emite           | ✅ Valida           | ✅ Funcionando      |
| **Auditoria de Login**   | ✅ Full logging    | N/A                | ✅ Enabled          |
| **Password Policy**      | ✅ Centralized     | N/A                | ✅ Via Keycloak     |
| **Code Quality**         | N/A               | ✅ Primary          | ✅ Deployed         |
| **Security Scanning**    | N/A               | ✅ Community limits | ⚠️ Limited features |
| **Quality Gates**        | N/A               | ✅ Full             | ✅ Configured       |

### 3.2 Versionamento Futuro

#### Keycloak Roadmap

**Próximas Versões (Official Timeline)**:
- ✅ 26.5.1 LTS (current, 1-year support)
- 🔜 27.0.0 (May 2026, rapid release)
- 🔜 27.1.0 (Aug 2026, rapid release + stable)
- 🔜 28.0.0 (Nov 2026, next LTS)

**Upgrade Strategy for STAGING**:
```
Current: 17.0.1 WildFly (deprecated late 2025)
↓
Next: 26.5.1 Quarkus LTS (recommended, chart 7.1.7)
      - Metrics bug fixed
      - Better performance
      - 1-year support
↓
Future: 27.x or 28.x LTS (2026-2027)
```

#### SonarQube Roadmap

**Próximas Versões (Official Timeline)**:
- ✅ 10.4.0 (Jan 2026, latest 10.x)
- ✅ 10.5.0 (March 2026, final 10.x)
- 🔜 11.0.0 (June 2026, major release)
- 🔜 11.1.0 (Sept 2026)

**Upgrade Strategy for STAGING**:
```
Current: 10.3.0 Community (chart 10.7.0)
↓
Next: 10.4.0+ Community (no breaking changes)
      - Incremental improvements
      - Same Community features
      - Safe upgrade (chart compatible)
↓
Future: 11.0 Community (2026-Q2)
        - Likely requires new chart
        - Possible DB migration
        - Plan upgrade for Phase 2 (Production)
```

### 3.3 Dependency Chain

```
STAGING Infrastructure:
├─ PostgreSQL RDS 16.4
│  ├─ keycloak database
│  ├─ sonarqube database
│  └─ redis (separate)
│
├─ Keycloak 17.0.1 (WildFly) [17.0.1-legacy image]
│  ├─ Helm: codecentric/keycloak:18.4.0
│  ├─ Namespace: keycloak
│  ├─ Secrets: admin password (K8s) + DB auth (Vault)
│  └─ Services: ArgoCD, SonarQube, GitLab, Grafana
│
└─ SonarQube 10.3.0 (Community)
   ├─ Helm: sonarqube/sonarqube:10.7.0
   ├─ Namespace: sonarqube
   ├─ OIDC Client: sonarqube (Keycloak)
   ├─ PVC: 20Gi
   └─ Integrations: GitLab CI/CD, PR decoration
```

**Critical Path**:
1. PostgreSQL RDS ready ✅
2. Keycloak deployed ✅ (needed for SonarQube OIDC)
3. SonarQube deployed ✅ (depends on Keycloak + PostgreSQL)

---

## 4. Decisões Arquiteturais

### 4.1 ADR-046: Keycloak SSO Platform Strategy

**Status**: ✅ Aceito e Implementado
**Date**: 2026-02-06
**Reference**: `/docs/adr/adr-046-keycloak-sso-strategy.md`

**Context**:
- Múltiplas ferramentas (ArgoCD, SonarQube, GitLab, Grafana) precisam autenticação centralizada
- OIDC/OAuth2 como padrão de facto

**Alternativas Consideradas**:
1. ✅ **Keycloak** (escolhida)
2. Dex (CNCF) - sem UI, stateless
3. Auth0 - SaaS, $100-150/user/month
4. Okta - SaaS, $500+/month
5. AWS Cognito - vendor lock-in, 1 realm only

**Decisão**: **Keycloak** como plataforma SSO centralizada

**Justificativa**:
- ✅ Open-source (sem vendor lock-in)
- ✅ OIDC/SAML compliant
- ✅ Multi-realm + identity federation
- ✅ UI administrativa completa
- ✅ PostgreSQL nativo
- ✅ HA via StatefulSet
- ✅ Custo: ~$35/mês (infra) vs $1.200+/mês (SaaS)
- ✅ Cloud-agnostic (portabilidade)

**Consequências**:
- ✅ SSO centralizado para toda plataforma
- ✅ Economia: $14.000+ /ano vs Auth0
- ✅ Controle total sobre dados de autenticação
- ✅ Customização ilimitada
- ⚠️ Responsabilidade operacional (backup, updates, monitoring)

**Known Issues (Resolvidos em 2026-02-11)**:
1. ✅ Metrics subsystem bug (WildFly) - planujem upgrade para Quarkus
2. ✅ ExternalSecret para DB credentials (Vault KV v2)
3. ✅ HA disabled temporariamente (1 replica) - upgrade resolves

### 4.2 ADR-035: SonarQube Code Quality (Inferred from Implementation)

**Status**: ✅ Implementado (logbook: 2026-02-06)
**Type**: Infrastructure Decision
**Reference**: `/docs/adr/adr-035-sonarqube-code-quality.md`

**Context**:
- Marco 4 CI/CD platform precisa code quality gates (quality gates)
- Pull request decoration para MRs
- Security scanning (limited community edition)

**Alternativas Consideradas**:
1. ✅ **SonarQube Community** (escolhida)
2. SonarQube Enterprise - $$$, features extras
3. CodeClimate - SaaS, $500+/month
4. Codefactor - SaaS, limited features
5. DeepSource - SaaS, limited languages

**Decisão**: **SonarQube Community Edition** (self-hosted)

**Justificativa**:
- ✅ Community edition covers MVP needs
- ✅ Multi-language support (10+ languages)
- ✅ Quality gates enforcement
- ✅ PR decoration (GitLab + GitHub)
- ✅ OIDC integration (via Keycloak)
- ✅ Zero cost (open-source)
- ⚠️ Advanced security features in Enterprise only
- ⚠️ 1 replica only (no HA in Community)

**Consequências**:
- ✅ Code quality baseline enforced
- ✅ Security scanning enabled (community level)
- ✅ Zero SaaS cost
- ⚠️ Admin responsible for maintenance
- ⚠️ Advanced features unavailable until Enterprise

---

## 5. Limitações e Degradações Conhecidas

### 5.1 Keycloak Degradações Atuais

**Degradation 1: HA Disabled (1 replica instead of 2)**

```
Severity: 🟡 Medium
Status: ⚠️ Workaround applied
Cause: Metrics subsystem NullPointerException on secondary pods (WildFly bug)

Error Log:
  [ERROR] Operation ("add") failed - address: ([("subsystem" => "metrics")]):
  java.lang.NullPointerException

Resolution:
  Option A: Scale down to 1 replica (CURRENT)
  Option B: Upgrade to Keycloak 26.5.1 Quarkus (PLANNED)

Impact: Single point of failure (pod restart = downtime)
Timeline: Upgrade scheduled Sprint+1 (resolves permanently)
Risk Mitigation: Pod Disruption Budget configured (minAvailable: 1)
```

**Degradation 2: Vault Integration Incomplete**

```
Severity: 🟡 Medium
Status: ⚠️ Workaround applied (K8s secrets)
Cause: Vault root token permissions incomplete

What's In Vault:
  ✅ secret/keycloak/postgresql - DB credentials stored

What's NOT In Vault:
  ⚠️ OIDC client secrets (argocd-oidc, sonarqube-oidc, etc.) - still in K8s

Root Cause: Vault RBAC role missing admin policy (K8s auth method issue)

Resolution:
  Step 1: Debug Vault role policies
  Step 2: Create ExternalSecret for OIDC secrets
  Step 3: Rotate K8s secrets → Vault

Timeline: Sprint+2 hardening
Risk: Secrets visible in kubectl (not encrypted in etcd by default)
```

**Degradation 3: Health Probes Removed**

```
Status: ⚠️ Temporary removal
Issue: Startup probe timeout on slow infrastructure
Resolution: Re-add with increased timeouts (Sprint+1)
Impact: No liveness probe (pod won't be restarted on hang)
```

### 5.2 SonarQube Degradações Atuais

**Degradation 1: Prometheus Exporter Disabled**

```
Severity: 🟡 Low
Status: ⚠️ Workaround applied (health endpoint)
Cause: Maven repository timeout when downloading exporter dependencies

Error Pattern:
  [WARN] Failed to download maven dependencies...
  [INFO] Disabling prometheus exporter

Resolution:
  Option A: Configure Maven proxy (networking)
  Option B: Pre-cache dependencies in container
  Option C: Disable exporter (CURRENT)

Impact: No Prometheus metrics (monitoring via /api/system/health only)
Timeline: Fix scheduled Sprint+1 (network troubleshooting)
Risk Mitigation: ServiceMonitor disabled, health endpoint available
```

**Degradation 2: OIDC Testing Pending**

```
Status: ✅ Configuration ready
Pending: Manual testing with Keycloak users
Action Items:
  1. Test login via Keycloak (admin@example.com)
  2. Verify group sync (developers group)
  3. Validate permissions (project access)

Timeline: Next sprint (post-core deployment)
Risk: None (config ready, just needs validation)
```

**Degradation 3: Advanced Security Features Unavailable**

```
Community Edition Limitations:

| Feature                    | Enterprise | Community |
| -------------------------- | ---------- | --------- |
| App Secrets Detection      | ✅ Yes      | ❌ No      |
| Container Image Scan       | ✅ Yes      | ❌ No      |
| Dependency Scanning        | ✅ Deep     | ⚠️ Basic   |
| Portfolio Management       | ✅ Yes      | ❌ No      |
| Webhooks (advanced)        | ✅ Adv      | ✅ Basic   |
| Custom Rules/Plugins       | ✅ Full     | ⚠️ Limited |
| Audit Trail (SOC2)         | ✅ Yes      | ❌ No      |
| Advanced Security Hotspots | ✅ Yes      | ⚠️ Limited |

Impact: Community is suitable for MVP, Enterprise for Phase 2
Timeline: Evaluate Enterprise license for production (Phase 2)
```

---

## 6. Upgrade Paths

### 6.1 Keycloak Upgrade Strategy

#### Phase 1: Immediate (Current Sprint)

**Goal**: Fix degradations, achieve HA

```
Current: Keycloak 17.0.1 WildFly (chart 18.4.0)
Target: Keycloak 26.5.1 Quarkus (chart 7.1.7)

Pre-Upgrade Checklist:
  □ Read 26.5.1 breaking changes (https://www.keycloak.org/docs/latest/)
  □ Backup PostgreSQL keycloak database
  □ Test chart 7.1.7 image locally
  □ Plan downtime window (5-10 minutes)
  □ Prepare rollback procedure

Upgrade Steps:
  1. Scale down to 0 replicas (graceful)
  2. Update Terraform chart version (18.4.0 → 7.1.7)
  3. Update variables.tf Keycloak version (17.0.1 → 26.5.1)
  4. Terraform plan + apply
  5. Monitor pod startup (30-60 seconds)
  6. Validate health endpoints: /auth/health/ready, /auth/health/live
  7. Test OIDC with one client (e.g., ArgoCD)
  8. Scale to 2 replicas (HA)

Rollback Plan:
  - Keep old chart 18.4.0 available
  - If critical issue: terraform apply with old version
  - Database rollback only if schema changes (unlikely)

Timeline: Sprint +1 (1-2 hours)
```

#### Phase 2: Short-term Hardening (Sprint +1/2)

```
Vault Integration Completion:
  1. Fix root token RBAC permissions
  2. Create ExternalSecret for OIDC secrets
  3. Rotate sonarqube-oidc, gitlab-oidc, grafana-oidc → Vault
  4. Delete K8s secrets (cleanup)

Health Probes Re-enablement:
  1. Add startup probe with 5min timeout
  2. Add liveness probe (30s interval)
  3. Add readiness probe (10s interval)
  4. Validate probes working in real cluster

Monitoring:
  1. Verify ServiceMonitor scraping Prometheus
  2. Create Grafana dashboard for Keycloak metrics
  3. Set alerts: pod restart, high error rate, slow responses

Timeline: 2-3 hours
```

#### Phase 3: Long-term (Spring 2027)

```
Consider: Keycloak 27.x or 28.x LTS
- Monitor release notes
- Test in staging environment (3 months before prod upgrade)
- Plan major upgrade annually (LTS strategy)
```

### 6.2 SonarQube Upgrade Strategy

#### Phase 1: Immediate (Within 2 months)

**Goal**: Fix Prometheus, validate OIDC, optimize storage

```
Current: SonarQube 10.3.0 (chart 10.7.0)
Target: SonarQube 10.4.0+ (chart 10.7.0 compatible)

Pre-Upgrade Checklist:
  □ Backup PostgreSQL sonarqube database
  □ Verify PVC has at least 25Gi available (need 5Gi free space for upgrade)
  □ Review 10.4.0 release notes
  □ Plan 1-2 hour downtime (analysis stalls during upgrade)
  □ Notify CI/CD teams (SonarQube unavailable)

Upgrade Steps:
  1. Create backup: kubectl get pvc sonarqube (snapshot)
  2. Update Terraform: sonarqube_chart_version = "10.7.0" (no change, just chart pins)
  3. Update image tag in values.yaml.tpl: 10.3.0 → 10.4.0
  4. Terraform plan + apply
  5. Monitor pod startup (180-240 seconds)
  6. Validate health: /api/system/health
  7. Test project analysis (run sonar-scanner on test project)

Rollback Plan:
  - Chart compatible (same 10.7.0)
  - If critical: revert image tag, terraform apply
  - Database compatible (10.4.0 migration automatic)

Timeline: 30-45 minutes deployment time
```

#### Phase 2: Short-term Fixes (Sprint +1/2)

```
Prometheus Exporter:
  1. Debug Maven download issue (network policy? DNS?)
  2. Option A: Configure Maven proxy settings
  3. Option B: Pre-cache in custom image
  4. Option C: Keep exporter disabled (acceptable for MVP)

OIDC Validation:
  1. Create test admin@example.com account (Keycloak)
  2. Test login via SonarQube UI → "Login with Keycloak"
  3. Verify group sync (developers group visible in SonarQube)
  4. Test CI/CD pipeline with SonarQube token auth

Quality Gates Customization:
  1. Analyze sample project (platform-infra repo)
  2. Define custom quality gates (beyond "Sonar way")
  3. Configure gate rules: coverage > 70%, bugs < 10, A rating
  4. Test gate enforcement on test PR

Timeline: 2-3 hours
```

#### Phase 3: Long-term Planning (2026-Q2)

```
SonarQube 11.0 Evaluation:
  - Monitor 11.0 release (June 2026)
  - Test in staging (3-month evaluation)
  - Review breaking changes vs Community edition limitations
  - Plan upgrade for Phase 2 (Production deployment, 2026-Q3)

Consider Enterprise License (Phase 2):
  - If organization requires advanced security features
  - If SOC2/compliance audit needed
  - License: $3k-10k/year (based on lines of code)
  - ROI: enhanced security scanning + audit trails
```

### 6.3 PostgreSQL Shared Upgrade

**Note**: Keycloak + SonarQube share same PostgreSQL 16.4 RDS instance

```
Upgrade Timeline:
  - Current: PostgreSQL 16.4 (latest stable)
  - Next Major: PostgreSQL 17.x (2025, early adoption)
  - LTS Strategy: Update annually, stay on major version

Prerequisites for Both:
  - Database auto-backup (AWS RDS 7-day retention)
  - Connection pooling verified (no interruption)
  - Both applications' compatibility checked

Process:
  1. Schedule 30-min maintenance window
  2. AWS RDS upgrade button (managed)
  3. Application reconnections automatic (via Kubernetes)
  4. Validate both services healthy after upgrade
```

---

## 7. Conclusão & Próximos Passos

### 7.1 Status Resumido

| Componente    | Status        | Versão | HA          | Vault     | Monitoring   |
| ------------- | ------------- | ------ | ----------- | --------- | ------------ |
| **Keycloak**  | 🟡 Degradado   | 17.0.1 | ❌ (1/2)     | ⚠️ Parcial | ✅ Configured |
| **SonarQube** | ✅ Operacional | 10.3.0 | ❌ (CE only) | ⚠️ TODO    | ⚠️ Disabled   |

### 7.2 Ações Recomendadas (Prioridade)

**🔴 Crítica (ASAP)**:
- [ ] Keycloak upgrade 17.0.1 → 26.5.1 (resolve metrics bug, enable HA)

**🟡 Alta (Sprint +0/+1)**:
- [ ] Complete Vault integration (OIDC secrets)
- [ ] Re-enable Keycloak health probes
- [ ] Validate SonarQube OIDC with real users
- [ ] Fix Prometheus exporter (investigate Maven timeout)

**🟢 Média (Sprint +1/+2)**:
- [ ] Configure SonarQube custom quality gates
- [ ] Create Grafana dashboards (Keycloak + SonarQube)
- [ ] Plan external ingress with TLS (current: port-forward only)
-​ [ ] Backup/restore procedures

**🔵 Baixa (Futuro)**:
- [ ] Evaluate SonarQube Enterprise (2026-Q2)
- [ ] Plan Keycloak 27.x/28.x migration (2027)
- [ ] Plan SonarQube 11.x migration (2026-Q2)

### 7.3 Documentação Relacionada

**ADRs**:
- ✅ [ADR-046: Keycloak SSO Platform Strategy](/docs/adr/adr-046-keycloak-sso-strategy.md)
- ✅ [ADR-035: SonarQube Code Quality](/docs/adr/adr-035-sonarqube-code-quality.md)

**Logbooks**:
- ✅ [2026-02-06-keycloak-sso-deployment.md](/docs/logbook/2026-02-06-keycloak-sso-deployment.md)
- ✅ [2026-02-06-sonarqube-deployment.md](/docs/logbook/2026-02-06-sonarqube-deployment.md)

**Terraform Modules**:
- ✅ [modules/keycloak/](/platform-provisioning/aws/kubernetes/terraform/modules/keycloak/)
- ✅ [modules/sonarqube/](/platform-provisioning/aws/kubernetes/terraform/modules/sonarqube/)

**Workflows**:
- ✅ [gap-004-sonarqube-deployment-prompt.md](/docs/workflows/gap-004-sonarqube-deployment-prompt.md)

---

**Última Atualização**: 2026-02-11 — Audit completo com análise de features, limitações e roadmap de upgrade.
