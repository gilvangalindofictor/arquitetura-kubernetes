# CICD-002: SonarQube Quality Gate Enforcement — Deployment Guide

**Demand**: CICD-002
**ADR**: [ADR-082](../../../docs/adr/adr-082-sonarqube-quality-gate-policy.md)
**Date**: 2026-02-26
**Status**: Artefatos prontos — aguardando cluster UP

---

## Overview

CICD-002 formaliza a política de quality gate do SonarQube na plataforma. Cria o gate
"Production" com thresholds específicos e o define como padrão para todos os projetos.

### Thresholds do Gate "Production"

| Condição | Threshold | Tipo |
|----------|-----------|------|
| New Code Coverage | >= 80% | BLOCKING (error) |
| New Bugs | = 0 | BLOCKING (error) |
| New Vulnerabilities | = 0 | BLOCKING (error) |
| New Code Smells | <= 10 | BLOCKING (error) |
| Security Hotspots Reviewed | >= 80% | BLOCKING (error) |

---

## Artefatos Criados

| Artefato | Localização |
|----------|-------------|
| Script de automação | `scripts/sonarqube/configure-quality-gate.sh` |
| GitLab CI template | `domains/cicd-platform/infra/gitlab-ci/templates/sonarqube-quality-gate.gitlab-ci.yml` |
| PrometheusRule | `domains/observability/infra/alerts/sonarqube-quality-gate-prometheus-rules.yaml` |
| Grafana dashboard | `monitoring/grafana/dashboards/cicd-quality-gate-trends.json` |
| ADR | `docs/adr/adr-082-sonarqube-quality-gate-policy.md` |
| Developer guide | `docs/guides/quality-gate-compliance.md` |
| Logbook | `docs/logbook/2026-02-26-cicd-002-quality-gate-planning.md` |

---

## Deploy (quando cluster UP)

### Pré-requisitos

Verificar antes de iniciar:

```bash
# 1. SonarQube está running
kubectl get pods -n sonarqube

# 2. PrometheusRule CRD disponível
kubectl get crd prometheusrules.monitoring.coreos.com

# 3. GitLab Runner configurado com envFrom (SONAR_HOST_URL, SONAR_TOKEN)
kubectl get configmap -n staging-platform-gitlab | grep runner

# 4. PushGateway disponível
kubectl get svc -n monitoring | grep pushgateway
```

### Passo 1: Configurar Quality Gate no SonarQube

```bash
# Porta-forward para SonarQube
kubectl port-forward svc/sonarqube 9000:9000 -n sonarqube &

# Obter o token admin (uma das opções abaixo):

# Opção A: Via Vault (método preferido)
vault kv get -field=admin-password secret/sonarqube/admin
# Usar esse password para gerar token em: http://localhost:9000 → My Account → Security → Tokens

# Opção B: Via kubectl secret
kubectl get secret sonarqube-admin-secret -n sonarqube -o jsonpath='{.data.password}' | base64 -d

# Configurar quality gate
export SONAR_TOKEN="squ_<seu-token-aqui>"
./scripts/sonarqube/configure-quality-gate.sh

# Exemplo de output esperado:
# [INFO]    Checking prerequisites...
# [OK]      Prerequisites satisfied (curl, jq, token provided)
# [INFO]    Testing SonarQube: http://localhost:9000
# [OK]      SonarQube is UP (version: 10.3.0.xxxx)
# [INFO]    Looking for quality gate: 'Production'
# [INFO]    Quality gate 'Production' not found — creating...
# [OK]      Created quality gate 'Production' with ID: <id>
# ... (5 conditions added)
# [OK]      Gate 'Production' is now the default for all new projects
# [OK]      CICD-002: Quality gate 'Production' configuration complete
```

### Passo 2: Validar configuração

```bash
./scripts/sonarqube/configure-quality-gate.sh --validate

# Output esperado:
# ======================================================================
#  CICD-002: SonarQube Quality Gate Validation Report
# ...
# Available Quality Gates:
#   [DEFAULT]  Production (ID: <id>)
#              Sonar way (ID: ...)
#              Platform Security Gate (ID: ...)
#
# Default Gate: Production
#
# Conditions for 'Production' (ID: <id>):
#   [LT] metric=new_coverage threshold=80 (error: 80)
#   [GT] metric=new_bugs threshold=0 (error: 0)
#   [GT] metric=new_vulnerabilities threshold=0 (error: 0)
#   [GT] metric=new_code_smells threshold=10 (error: 10)
#   [LT] metric=new_security_hotspots_reviewed threshold=80 (error: 80)
#
# Total conditions: 5
# [OK]      Gate 'Production' is correctly set as DEFAULT
```

### Passo 3: Aplicar PrometheusRule

```bash
kubectl apply -f domains/observability/infra/alerts/sonarqube-quality-gate-prometheus-rules.yaml

# Verificar que foi criada
kubectl get prometheusrule cicd002-quality-gate-alerts -n monitoring

# Verificar alertas carregados no Prometheus
# Prometheus UI → Alerts → buscar "SonarQube" ou "QualityGate"
# http://prometheus.staging.internal/alerts
```

### Passo 4: Importar Grafana dashboard

```bash
# Opção A: Via UI (recomendado)
# Grafana → Dashboards → Import → Upload JSON
# File: monitoring/grafana/dashboards/cicd-quality-gate-trends.json

# Opção B: Via API
curl -s -u admin:"${GRAFANA_ADMIN_PASSWORD}" \
  -X POST \
  -H "Content-Type: application/json" \
  -d "{\"dashboard\": $(cat monitoring/grafana/dashboards/cicd-quality-gate-trends.json), \"overwrite\": true, \"folderId\": 0}" \
  http://grafana.monitoring.svc.cluster.local:3000/api/dashboards/import

# Verificar
curl -s -u admin:"${GRAFANA_ADMIN_PASSWORD}" \
  http://grafana.monitoring.svc.cluster.local:3000/api/dashboards/uid/cicd002-quality-gate \
  | jq '.meta.slug'
```

### Passo 5: Validar end-to-end

```bash
# Teste de validação: criar um MR com cobertura abaixo de 80%
# A pipeline deve:
# 1. Executar o job sonarqube-quality-gate
# 2. Falhar com "Quality Gate FAILED" na saída
# 3. Mostrar link para SonarQube dashboard

# Verificar métricas PushGateway após pipeline falhar:
curl -s http://prometheus-pushgateway.monitoring.svc:9091/metrics \
  | grep gitlab_ci_quality_gate

# Verificar alertas no Prometheus:
# SonarQubeQualityGateFailed deve aparecer se gate está em ERROR
```

---

## Adicionar ao Projeto

### Inclusão mínima (.gitlab-ci.yml)

```yaml
include:
  - project: 'platform/templates'
    file: '/gitlab-ci/templates/sonarqube-quality-gate.gitlab-ci.yml'

stages:
  - build
  - test
  - quality-gate   # obrigatório para o job do template
  - deploy
```

### Inclusão completa com coverage (Python)

```yaml
include:
  - project: 'platform/templates'
    file: '/gitlab-ci/templates/sonarqube-quality-gate.gitlab-ci.yml'

stages:
  - build
  - test
  - quality-gate
  - deploy

test:
  stage: test
  image: python:3.11
  script:
    - pip install -r requirements-dev.txt
    - pytest --cov=src --cov-report=xml:coverage/coverage.xml
  artifacts:
    paths:
      - coverage/
    expire_in: 1 day

sonarqube-quality-gate:
  extends: .sonarqube-quality-gate
  variables:
    SONAR_COVERAGE_REPORT: "coverage/coverage.xml"
    SONAR_EXTRA_PROPS: "-Dsonar.exclusions=**/migrations/**,**/tests/**"
  needs:
    - job: test
      artifacts: true
```

### Inclusão completa com coverage (Node.js/TypeScript)

```yaml
include:
  - project: 'platform/templates'
    file: '/gitlab-ci/templates/sonarqube-quality-gate.gitlab-ci.yml'

stages:
  - build
  - test
  - quality-gate
  - deploy

test:
  stage: test
  image: node:20
  script:
    - npm ci
    - npm test -- --coverage --coverageReporters=lcov,text
  artifacts:
    paths:
      - coverage/
    expire_in: 1 day

sonarqube-quality-gate:
  extends: .sonarqube-quality-gate
  variables:
    SONAR_COVERAGE_REPORT: "coverage/lcov.info"
    SONAR_EXTRA_PROPS: "-Dsonar.exclusions=**/node_modules/**,**/*.spec.ts"
  needs:
    - job: test
      artifacts: true
```

### Inclusão completa com coverage (Java/Maven)

```yaml
include:
  - project: 'platform/templates'
    file: '/gitlab-ci/templates/sonarqube-quality-gate.gitlab-ci.yml'

stages:
  - build
  - test
  - quality-gate
  - deploy

test:
  stage: test
  image: maven:3.9-openjdk-17
  script:
    - mvn test jacoco:report -B
  artifacts:
    paths:
      - target/site/jacoco/
      - target/classes/
    expire_in: 1 day

sonarqube-quality-gate:
  extends: .sonarqube-quality-gate
  variables:
    SONAR_COVERAGE_REPORT: "target/site/jacoco/jacoco.xml"
    SONAR_EXTRA_PROPS: >-
      -Dsonar.java.binaries=target/classes
      -Dsonar.java.libraries=~/.m2
      -Dsonar.exclusions=**/generated/**
  needs:
    - job: test
      artifacts: true
```

---

## Combinação com CICD-001

CICD-001 e CICD-002 são complementares. Para projetos que precisam de ambos:

```yaml
include:
  # CICD-001: 4 security scanners (trivy, owasp, trufflehog, sonarqube SAST)
  - project: 'platform/templates'
    file: '/gitlab-ci/templates/security.gitlab-ci-security-template.yml'

  # CICD-002: Quality gate dedicated job
  - project: 'platform/templates'
    file: '/gitlab-ci/templates/sonarqube-quality-gate.gitlab-ci.yml'

stages:
  - build
  - test
  - security-scan   # CICD-001: sonarqube-sast, trivy, owasp, trufflehog
  - quality-gate    # CICD-002: sonarqube-quality-gate (with wait=true)
  - deploy
```

**Nota**: O `sonarqube-sast` do CICD-001 também usa `qualitygate.wait=true`. Incluir ambos
resulta em 2 análises SonarQube por pipeline. Para evitar isso, pode-se remover o `sonarqube-sast`
do CICD-001 se CICD-002 já cobre o quality gate. Ver ADR-082 para detalhes.

---

## Thresholds Customizados por Projeto

Para projetos com circunstâncias especiais (legado, exceção aprovada):

```bash
# Re-executar script com thresholds customizados para um gate específico por projeto
./scripts/sonarqube/configure-quality-gate.sh \
  --gate-name "Legacy Coverage Gate" \
  --coverage 60 \
  --max-smells 30 \
  --no-set-default

# Atribuir o gate customizado ao projeto via API:
curl -s -u "${SONAR_TOKEN}:" \
  -X POST \
  "http://sonarqube.staging.internal/api/qualitygates/select" \
  -d "gateId=<gate-id>&projectKey=<project-key>"
```

**ATENÇÃO**: Thresholds customizados requerem aprovação via processo formal (ver ADR-082
e docs/guides/quality-gate-compliance.md).

---

## Manutenção

### Atualizar thresholds (com nova ADR)

```bash
# Exemplo: aumentar coverage para 85% (requer decisão documentada)
SONAR_TOKEN="squ_..." ./scripts/sonarqube/configure-quality-gate.sh --coverage 85

# Script é idempotente — remove condições antigas e recria
```

### Verificar estado atual

```bash
SONAR_TOKEN="squ_..." ./scripts/sonarqube/configure-quality-gate.sh --validate
```

### Preview de mudanças sem aplicar

```bash
SONAR_TOKEN="squ_..." ./scripts/sonarqube/configure-quality-gate.sh --dry-run --coverage 90
```

---

## Troubleshooting

### Quality gate não aparece no SonarQube

```bash
# Verificar se o script rodou com sucesso
SONAR_TOKEN="squ_..." ./scripts/sonarqube/configure-quality-gate.sh --validate

# Verificar via API diretamente
curl -s -u "${SONAR_TOKEN}:" \
  "http://sonarqube.staging.internal/api/qualitygates/list" | jq '.qualitygates[].name'
```

### Pipeline não bloqueia mesmo com gate falhando

```bash
# Verificar que o template está sendo incluído
# Checar o .gitlab-ci.yml do projeto: include deve apontar para o arquivo correto

# Verificar que qualitygate.wait=true está ativo
# O job deve mostrar no log: "sonar.qualitygate.wait=true"

# Verificar se SONAR_QUALITY_GATE_BYPASS está definida acidentalmente
# GitLab: Settings → CI/CD → Variables → verificar se SONAR_QUALITY_GATE_BYPASS=true
```

### PrometheusRule não carregada

```bash
# Verificar labels corretos
kubectl get prometheusrule cicd002-quality-gate-alerts -n monitoring -o yaml | grep -A 10 labels

# Deve ter:
# app: kube-prometheus-stack
# release: kube-prometheus-stack
# role: alert-rules

# Verificar se Prometheus operator está picking up
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus-operator --tail=50 \
  | grep -i "prometheusrule"
```

### Scan timeout

```bash
# Aumentar timeout no projeto (em .gitlab-ci.yml)
sonarqube-quality-gate:
  extends: .sonarqube-quality-gate
  variables:
    SONAR_TIMEOUT: "600"  # 10 minutes
```

---

## Referências

- [ADR-082: Quality Gate Policy](../../../docs/adr/adr-082-sonarqube-quality-gate-policy.md)
- [ADR-081: SAST/DAST Pipeline](../../../docs/adr/adr-081-sast-dast-pipeline-enforcement.md)
- [ADR-075: SonarQube Prometheus](../../../docs/adr/adr-075-sonarqube-prometheus-exporter.md)
- [Developer Guide: Quality Gate Compliance](../../../docs/guides/quality-gate-compliance.md)
- [CICD-001 Deployment Guide](CICD-001-DEPLOYMENT-GUIDE.md)
- [SonarQube Quality Gates API](https://next.sonarqube.com/sonarqube/web_api/api/qualitygates)

**Demand**: CICD-002
**Owner**: Platform SRE Team
