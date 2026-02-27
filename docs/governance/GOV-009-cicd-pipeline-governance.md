# GOV-009: CI/CD Pipeline Governance & Standards

> **Versão**: 1.0
> **Data**: 2026-02-27
> **Status**: Ativo
> **Referências**: ADR-081, ADR-082, ADR-084, CICD-001
> **Audiência**: Desenvolvedores, Tech Leads, Platform Team

---

## Visão Geral

CI/CD é operado via **GitLab CI** (build, test, security) + **ArgoCD** (deploy via GitOps).
Toda aplicação DEVE usar os templates de pipeline padronizados com security scanning obrigatório.

---

## Pipeline Architecture

```
┌──────────┐   ┌──────────┐   ┌──────────────┐   ┌──────────┐   ┌──────────┐
│  Build   │──>│  Test    │──>│ Security Scan│──>│ Publish  │──>│  Deploy  │
│          │   │          │   │ (CICD-001)   │   │ (Harbor) │   │ (ArgoCD) │
└──────────┘   └──────────┘   └──────────────┘   └──────────┘   └──────────┘
                                    │
                              ┌─────┴─────┐
                              │ SonarQube  │
                              │ Trivy      │
                              │ OWASP DC   │
                              │ TruffleHog │
                              └────────────┘
```

---

## Setup Mínimo (.gitlab-ci.yml)

```yaml
include:
  - project: 'platform/templates'
    file: '/gitlab-ci/templates/security.gitlab-ci-security-template.yml'

stages:
  - build
  - test
  - security-scan    # Obrigatório (CICD-001)
  - publish
  - deploy
```

**Referência completa**: [CICD-001 Developer Guide](../CICD-001-DEVELOPER-GUIDE.md)

---

## Security Scanners (Obrigatórios)

| Scanner | O que verifica | Bloqueia em |
|---------|---------------|-------------|
| **SonarQube** | Code quality + SAST | Quality Gate ERROR |
| **Trivy** | Container image CVEs | HIGH ou CRITICAL |
| **OWASP Dependency-Check** | Library CVEs | CVSS >= 7.0 |
| **TruffleHog** | Secrets no git history | Qualquer secret verificado |

**Regra**: `allow_failure: false` em todos os scanners. Sem bypass sem aprovação do Platform SRE.

---

## Quality Gates (SonarQube)

**Referência**: [ADR-082: SonarQube Quality Gate Policy](../adr/adr-082-sonarqube-quality-gate-policy.md)

### Thresholds

| Métrica | Threshold (New Code) | Ação |
|---------|---------------------|------|
| Bugs | 0 | Block merge |
| Vulnerabilities | 0 | Block merge |
| Code Smells | < 10 | Warning |
| Coverage | > 80% | Block merge |
| Duplications | < 3% | Warning |
| Security Hotspots | 0 reviewed | Block merge |

---

## Image Tagging

**Referência**: [ADR-084: Immutable Image Tags Enforcement](../adr/adr-084-immutable-image-tags-enforcement.md)

```yaml
PERMITIDO:
✅ harbor.{domain}/{produto}:v1.2.3              # Semver
✅ harbor.{domain}/{produto}:sha-abc123def        # Git SHA
✅ harbor.{domain}/{produto}:v1.2.3-rc1           # Pre-release

PROIBIDO:
❌ harbor.{domain}/{produto}:latest               # Mutable tag
❌ harbor.{domain}/{produto}:dev                   # Mutable tag
❌ harbor.{domain}/{produto}:test                  # Mutable tag
```

**Kyverno enforcement**: Policy bloqueia deploy de `:latest` tags.

---

## Pipeline por Linguagem

### Python

```yaml
build:
  image: python:3.11-slim
  script:
    - pip install -r requirements.txt
    - python -m pytest tests/ --cov --cov-report=xml

security-scan:
  # Incluído automaticamente via template
```

### Go

```yaml
build:
  image: golang:1.22-alpine
  script:
    - go build -o app ./cmd/...
    - go test -v -cover -coverprofile=coverage.out ./...
```

### Java

```yaml
build:
  image: maven:3.9-eclipse-temurin-21
  script:
    - mvn clean verify -B
```

---

## Harbor (Container Registry)

### Naming

```yaml
Formato: harbor.{domain}/corporate-domains/{domain}/{produto}:{tag}

Exemplos:
✅ harbor.company.com/corporate-domains/data/rpa-exemplo:v1.0.0
✅ harbor.company.com/corporate-domains/integration/ipaas:sha-abc123
```

### Políticas

| Política | Valor |
|----------|-------|
| Vulnerability scanning | Auto (push trigger) |
| Retention | 30 days (non-semver tags) |
| Immutability | Enabled (semver tags) |
| Quota | 50GB per project |

---

## Branch Strategy

```yaml
main:          # Production-ready (protected)
  - Merge via MR only
  - Requires 1 approval
  - All security scans pass
  - Quality gate pass

develop:       # Integration branch
  - Merge via MR
  - Security scans run (non-blocking)

feature/*:     # Feature branches
  - Free push
  - Security scans on MR
```

---

## Proibições

```yaml
NUNCA:
  - Push direto para main (protected branch)
  - Skip security scans (--no-verify)
  - Deploy sem pipeline CI/CD completo
  - Usar :latest em imagens de produção
  - Commit secrets no código (TruffleHog detecta)

SEMPRE:
  - MR com review para main
  - Security template incluído
  - Immutable image tags
  - Quality gate SonarQube
```

---

## Monitoring

| Métrica | Alerta | Threshold |
|---------|--------|-----------|
| Pipeline duration | `CICDPipelineSlow` | > 15min |
| Failed pipelines | `CICDPipelineFailed` | > 3 consecutive |
| Security scan findings | `CICDSecurityFindings` | Any CRITICAL |
| SonarQube Quality Gate | `SonarQubeGateFailed` | ERROR status |

---

## Referências

- [CICD-001 Developer Guide](../CICD-001-DEVELOPER-GUIDE.md)
- [ADR-081: SAST/DAST Pipeline Enforcement](../adr/adr-081-sast-dast-pipeline-enforcement.md)
- [ADR-082: SonarQube Quality Gate Policy](../adr/adr-082-sonarqube-quality-gate-policy.md)
- [ADR-084: Immutable Image Tags Enforcement](../adr/adr-084-immutable-image-tags-enforcement.md)
- [Security Scan Failures Troubleshooting](../runbooks/security-scan-failures-troubleshooting.md)
