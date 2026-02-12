# 📌 Referência Rápida — Keycloak & SonarQube

**Última atualização**: 2026-02-11

---

## 🎯 Versões (Terraform = Source of Truth)

### Keycloak SSO

```hcl
Versão Atual:    26.5.1 (Quarkus 3.27.1)
Helm Chart:      7.1.7 (codecentric/keycloakx)
Namespace:       keycloak
Replicas:        1/2 (2ª pending - cluster CPU capacity)
Database:        PostgreSQL RDS 16.4 (shared, SSL required)
HA Status:       ⚠️ Partial (1/2 replicas - acceptable STAGING)
Startup Time:    27s (Quarkus optimized, was 60-80s WildFly)
OIDC Validated:  ✅ Discovery endpoint + /auth prefix OK

# Terraform: modules/keycloak/variables.tf
variable "keycloak_chart_version" {
  default = "7.1.7"  # Quarkus runtime deployed
}

# Upgrade Completed: 2026-02-11
Previous:        17.0.1-legacy (WildFly)
Migration:       Liquibase 3.5.5 → 4.6.2 (seamless)
Improvements:    +65% startup speed, HA enablement, CVE patches
```

### SonarQube Code Quality

```hcl
Versão Atual:    10.3.0-community
Helm Chart:      10.7.0 (SonarSource official)
Namespace:       sonarqube
Replicas:        1 (Community edition only)
Database:        PostgreSQL RDS 16.4 (shared)
Storage:         20Gi PVC (gp3)
Monitoring:      🟡 Prometheus disabled (Maven timeout)

# Terraform: modules/sonarqube/variables.tf
variable "sonarqube_chart_version" {
  default = "10.7.0"
}

# Upgrade Plan: Incremental +1 month
Target:          10.4.0+ (safe, same edition)
Expected Impact: Better quality gate handling, stability
Future (Q2 2026):11.0 (major release, plan migration)
```

---

## 🔗 Tipos de Problemas & Documentação

### "Qual é a versão do Keycloak em STAGING?"
→ Veja [KEYCLOAK-SONARQUBE-AUDIT.md § 1.1](KEYCLOAK-SONARQUBE-AUDIT.md#11-versões--terraform-vs-realidade)

### "Por que Keycloak tem só 1 replica?"
→ Veja [KEYCLOAK-SONARQUBE-AUDIT.md § 5.1 - Degradation 1](KEYCLOAK-SONARQUBE-AUDIT.md#keycloak-degradações-atuais)

### "Qual é o upgrade path para Keycloak?"
→ Veja [KEYCLOAK-SONARQUBE-AUDIT.md § 6.1](KEYCLOAK-SONARQUBE-AUDIT.md#61-keycloak-upgrade-strategy)

### "SonarQube Community Edition suporta X?"
→ Veja [KEYCLOAK-SONARQUBE-AUDIT.md § 2.4](KEYCLOAK-SONARQUBE-AUDIT.md#24-sonarqube-features-analysis)

### "Por que foi escolhido Keycloak e não Auth0?"
→ Veja [ADR-046](adr/adr-046-keycloak-sso-strategy.md) (Decision context)

### "Como SonarQube foi deployed?"
→ Veja [Logbook: 2026-02-06-sonarqube-deployment.md](logbook/2026-02-06-sonarqube-deployment.md)

### "Qual é a conformidade de STAGING?"
→ Veja [AUDIT-INDEX.md § Métricas de Conformidade](AUDIT-INDEX.md#-métricas-de-conformidade)

---

## 📋 Checklist de Próximas Ações

**This Sprint (Imediato)**
- [ ] Ler [KEYCLOAK-SONARQUBE-AUDIT.md](KEYCLOAK-SONARQUBE-AUDIT.md)
- [ ] Planejar Keycloak upgrade (17.0.1 → 26.5.1)

**Sprint +1**
- [ ] Executar Keycloak upgrade (3h)
- [ ] Validar SonarQube OIDC com usuários reais (1h)
- [ ] Completar Keycloak Vault integration (2h)

**Sprint +2**
- [ ] Configure custom SonarQube quality gates (1h)
- [ ] Setup Grafana dashboards (1h)

---

## 📑 Índice de Documentos

### Master Audits
| Documento                                                  | Escopo      | Páginas | Uso                                        |
| ---------------------------------------------------------- | ----------- | ------- | ------------------------------------------ |
| [KEYCLOAK-SONARQUBE-AUDIT.md](KEYCLOAK-SONARQUBE-AUDIT.md) | Completo    | 6+      | **[👈 Start here]** Deep technical analysis |
| [AUDIT-INDEX.md](AUDIT-INDEX.md)                           | Consolidado | 3+      | Navigation guide                           |

### ADRs
| Documento                                        | Componente | Decisão                      | Status     |
| ------------------------------------------------ | ---------- | ---------------------------- | ---------- |
| [ADR-046](adr/adr-046-keycloak-sso-strategy.md)  | Keycloak   | Why Keycloak vs alternatives | ✅ Accepted |
| [ADR-035](adr/adr-035-sonarqube-code-quality.md) | SonarQube  | Why Community Edition        | ✅ Accepted |

### Logbooks (Real Deployments)
| Documento                                                                              | O quê                | Quando | Status     |
| -------------------------------------------------------------------------------------- | -------------------- | ------ | ---------- |
| [2026-02-06-keycloak-sso-deployment.md](logbook/2026-02-06-keycloak-sso-deployment.md) | Keycloak deployment  | 6h     | ✅ Complete |
| [2026-02-06-sonarqube-deployment.md](logbook/2026-02-06-sonarqube-deployment.md)       | SonarQube deployment | 2h     | ✅ Complete |

### Terraform (Source of Truth)
| Módulo    | Localização          | Status              |
| --------- | -------------------- | ------------------- |
| Keycloak  | `modules/keycloak/`  | ✅ Terraform-managed |
| SonarQube | `modules/sonarqube/` | ✅ Terraform-managed |

---

## 🚀 Atalhos Diretos

**Terraform Declarations**:
```bash
# Keycloak versions
cat modules/keycloak/variables.tf | grep -A2 "keycloak_chart_version\|replicas"

# SonarQube versions
cat modules/sonarqube/variables.tf | grep -A2 "sonarqube_chart_version\|replicas"
```

**What's Deployed**:
```bash
# Check running versions
kubectl get deployment -n keycloak -o yaml | grep image:
kubectl get deployment -n sonarqube -o yaml | grep image:

# Check replicas
kubectl get deployment -n keycloak --no-headers | awk '{print $2}'
kubectl get statefulset -n sonarqube --no-headers | awk '{print $2}'
```

**OIDC Clients**:
```bash
# Keycloak OIDC clients
kubectl get secret -n keycloak | grep -oidc

# SonarQube OIDC secret
kubectl get secret -n sonarqube sonarqube-oidc -o yaml
```

---

## ⚠️ Critical Issues (Known)

| Issue                                           | Severity | Impact                              | Fix Timeline                  |
| ----------------------------------------------- | -------- | ----------------------------------- | ----------------------------- |
| Keycloak 2ª replica pending (CPU capacity)      | 🟢 Low    | Acceptable for STAGING              | Sprint +2 (add cluster nodes) |
| Keycloak Vault OIDC secrets in K8s              | 🟢 Low    | DB secrets OK, OIDC manual          | Sprint +2                     |
| SonarQube Prometheus disabled                   | 🟡 Low    | No metrics (health endpoint OK)     | Sprint +2 (investigate Maven) |
| SonarQube OIDC clients not tested               | 🟢 Low    | Discovery OK, login test pending    | This sprint                   |

---

## 💡 Facts & Success Metrics

### Keycloak
✅ **26.5.1 Quarkus** deployed (upgraded from 17.0.1 WildFly)
✅ 4 OIDC clients configured (ArgoCD, SonarQube, GitLab, Grafana)
✅ **OIDC discovery endpoint validated** (backward compatibility OK)
✅ PostgreSQL RDS with SSL/TLS (sslmode=require)
✅ Realm `platform` with 3 groups created
✅ Vault K8s auth functional (ExternalSecret syncing DB creds)
✅ **Startup time: 27s** (65% faster than WildFly)
⚠️ HA partial (1/2 replicas - 2ª pending cluster CPU)

### SonarQube
✅ 10.3.0 Community Edition running
✅ OIDC configuration in place (Keycloak integration)
✅ PostgreSQL RDS database functional
✅ 20Gi PVC provisioned
⚠️ Prometheus exporter disabled (Maven issue)
⚠️ OIDC login test pending (discovery validated)

---

**Last Updated**: 2026-02-11
