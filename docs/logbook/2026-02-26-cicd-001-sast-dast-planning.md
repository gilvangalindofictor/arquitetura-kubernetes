# Logbook: CICD-001 — SAST/DAST Security Scanning Enforcement

**Date**: 2026-02-26
**Demand**: CICD-001 — SAST/DAST Pipeline Enforcement Strategy
**Status**: Artefatos completos — aguardando cluster UP para deploy
**Effort**: ~3h (artefatos + documentação completa)
**ADR**: [ADR-081](../adr/adr-081-sast-dast-pipeline-enforcement.md)

---

## Objetivo

Implementar enforcement de segurança obrigatório no pipeline GitLab CI/CD da plataforma.
Todos os projetos devem ter 4 scanners de segurança bloqueantes antes de qualquer deploy.

## Contexto

**Estado anterior**:
- SonarQube deployado (GAP-004) com `allow_failure: true` — não bloqueava nada
- Harbor + Trivy integrados mas sem severity threshold
- Zero detecção de secrets em git
- Zero CVE scan em dependências
- Sem observabilidade de security scans

**Estado após CICD-001**:
- 4 scanners com `allow_failure: false`
- Quality Gate "Platform Security Gate" via API (configure-blocking.sh)
- Harbor Trivy threshold: HIGH,CRITICAL (configure-trivy-blocking.sh)
- Métricas Prometheus via PushGateway
- Dashboard Grafana: uid=cicd001-security-scans
- 8 alertas Prometheus (PrometheusRule)
- Runbook completo + Developer Guide

---

## Decisões Técnicas

### Scanners Escolhidos

| Scanner | Decisão | Razão |
|---|---|---|
| SonarQube SAST | sonarqube/sonar-scanner-cli:5.0 | Já deployado, native quality gate wait |
| Container | aquasec/trivy:0.50.0 | Já integrado ao Harbor, output machine-readable |
| Dependencies | owasp/dependency-check:latest | Cobre supply chain (npm/maven/pip) que Trivy não cobre |
| Secrets | trufflesecurity/trufflehog:latest | --only-verified elimina false positives |

### Image Pinning

- SonarQube e Trivy: versão minor/patch pinned para reproducibilidade
- OWASP DC e TruffleHog: `:latest` intencional (BD de CVEs/detectores evolui diariamente)

### Supressão de False Positives

Cada scanner tem mecanismo próprio:
- SonarQube: "Won't Fix" no UI com comentário obrigatório
- Trivy: `.trivyignore` com CVE ID e justificativa
- OWASP DC: `dependency-check-suppression.xml` com data de expiração
- TruffleHog: `# trufflehog:ignore` inline

### Emergency Bypass

Processo documentado para situações críticas com:
- Aprovação explícita de Platform SRE ou EM
- SLA máximo de 5 dias úteis para resolução
- Tracking issue obrigatório

---

## Artefatos Criados

### 1. GitLab CI Template

**Arquivo**: `domains/cicd-platform/infra/gitlab-ci/templates/security.gitlab-ci-security-template.yml`

Template principal com 4 hidden jobs (`.sonarqube-sast`, `.trivy-container-scan`,
`.owasp-dependency-check`, `.trufflehog-secret-scan`) e 4 concrete jobs que os extendem.

**Features**:
- `allow_failure: false` em todos os jobs
- PushGateway metrics via YAML anchor `*push_metric`
- Cache configurado para Trivy DB e OWASP NVD DB
- SARIF output para Trivy (integração futura com GitLab Security tab)
- Rules: scan em MR, main, release/*, hotfix/*

### 2. Scripts de Automação

**SonarQube** (`scripts/sonarqube/configure-blocking.sh`):
- Cria Quality Gate "Platform Security Gate" via API
- Adiciona 8 condições de bloqueio (vulnerabilities, bugs, coverage, ratings)
- Set as default gate para novos projetos
- Flags: `--dry-run`, `--validate`, `--gate-name`
- Idempotente: remove condições existentes antes de recriar

**Harbor** (`scripts/harbor/configure-trivy-blocking.sh`):
- Configura severity threshold HIGH,CRITICAL via Harbor API v2.0
- Habilita auto-scan on push para todos os projetos
- Flags: `--dry-run`, `--validate`, `--project <name>`
- Idempotente: safe to re-run

### 3. Observabilidade

**PrometheusRule** (`domains/observability/infra/alerts/cicd-security-prometheus-rules.yaml`):

8 alertas em 3 grupos:
- `cicd.sonarqube`: SonarQubeQualityGateFailed (critical), SonarQubeNewVulnerabilitiesHigh (warn), SonarQubeDown (warn)
- `cicd.pipeline-security`: PipelineSecurityScanFailed (warn), TrivyCriticalVulnerabilitiesFound (critical), TruffleHogSecretDetected (critical), OWASPDependencyCheckFailed (warn), SecurityScanDurationAnomaly (warn)
- `cicd.harbor-security`: HarborScannerDown (warn)

**Grafana Dashboard** (`monitoring/grafana/dashboards/cicd-security-scan-performance.json`):

UID: `cicd001-security-scans`, 5 seções:
1. Overview — Quality Gate Status (stat panels por scanner)
2. Quality Gate Pass/Fail Ratio (timeseries: overall + por scanner)
3. Scan Duration Trends (timeseries + stat de média por scanner)
4. SonarQube Metrics (native exporter: gate status, vulnerabilities, bugs, trend)
5. Recent Scan History (tabela: todos projetos × scanners)

### 4. ADR

**Arquivo**: `docs/adr/adr-081-sast-dast-pipeline-enforcement.md`

Seções: contexto, decisão, arquitetura, escolha de scanners, image pinning, métricas,
mecanismos de supressão, deployment, riscos, alternativas rejeitadas, próximos passos.

### 5. Documentação

**Runbook** (`docs/runbooks/security-scan-failures-troubleshooting.md`):
- Quick diagnosis guide
- Per-scanner troubleshooting (SonarQube, Trivy, OWASP DC, TruffleHog)
- False positive suppression process com templates
- Infrastructure issues (PushGateway, NetworkPolicy)
- Emergency bypass process
- Contacts

**Developer Guide** (`docs/CICD-001-DEVELOPER-GUIDE.md`):
- TL;DR minimum setup (2 linhas)
- Full setup guide com exemplos
- Pipeline flow diagram
- Interpreting scan results
- FAQ (8 perguntas comuns)
- Advanced configuration (override por scanner, branches)
- Métricas e observabilidade

---

## Dependências para Deploy

### Cluster deve estar UP para:

1. **PrometheusRule** — requer cluster running:
   ```bash
   kubectl apply -f domains/observability/infra/alerts/cicd-security-prometheus-rules.yaml
   ```

2. **SonarQube Quality Gate** — requer SonarQube acessível:
   ```bash
   # Port-forward ou dentro do cluster
   SONAR_TOKEN=<admin-token> ./scripts/sonarqube/configure-blocking.sh
   # Validate:
   SONAR_TOKEN=<token> ./scripts/sonarqube/configure-blocking.sh --validate
   ```

3. **Harbor Trivy** — requer Harbor acessível:
   ```bash
   HARBOR_ADMIN_PASSWORD=<pass> ./scripts/harbor/configure-trivy-blocking.sh
   # Validate:
   HARBOR_ADMIN_PASSWORD=<pass> ./scripts/harbor/configure-trivy-blocking.sh --validate
   ```

4. **Grafana Dashboard** — importar via UI (Dashboards → Import → Upload JSON):
   `monitoring/grafana/dashboards/cicd-security-scan-performance.json`

5. **Template Include** — adicionar aos projetos piloto:
   ```yaml
   include:
     - project: 'platform/templates'
       file: '/gitlab-ci/templates/security.gitlab-ci-security-template.yml'
   ```

### Pré-requisitos verificados:

- [x] SonarQube 10.3.0 deployado com ServiceMonitor (GAP-008)
- [x] Harbor com Trivy integrado
- [x] Prometheus PushGateway disponível em monitoring namespace
- [x] GitLab Runner com `envFrom: gitlab-ci-credentials` (HARBOR_*, SONAR_*)
- [x] NetworkPolicies não bloqueiam runner → sonarqube/harbor/pushgateway

---

## Performance Esperada

| Scanner | Duração Estimada | Cache? |
|---|---|---|
| SonarQube SAST | 1-3 min | SonarQube cache de análise |
| Trivy Container | 30s-2min | GitLab cache (.trivy-cache/) |
| OWASP DC | 30s (cached) / 15min (cold) | GitLab cache (.owasp-cache/data/) |
| TruffleHog | 30s-2min | Sem cache necessário |
| **Total (parallel)** | **~3-8 min** | Após warm cache |

Pipeline total com security-scan: +3-8min vs pipeline sem security.

---

## Próximos Passos

### Imediato (quando cluster UP)

1. Deploy PrometheusRule
2. Configurar SonarQube Quality Gate (configure-blocking.sh)
3. Configurar Harbor Trivy (configure-trivy-blocking.sh)
4. Importar Grafana dashboard
5. Onboarding projeto piloto (1 projeto de baixo risco)

### Sprint+1

1. Rollout para todos os projetos ativos
2. Review thresholds após 2 semanas de dados
3. Adicionar `sonar-project.properties` nos projetos principais
4. Setup pre-commit hooks locais para developers

### Médio Prazo

1. GitLab Security tab com SARIF output (requer upload do trivy-report.sarif)
2. SonarQube PR decoration (comments inline no diff)
3. DAST com OWASP ZAP (fase 2 do CICD-001)
4. Software Bill of Materials (SBOM) com Trivy `--format cyclonedx`

---

## Lições Aprendidas

1. **OWASP DC `:latest` intencional**: CVE database evolui diariamente; versão pinned
   causaria dados obsoletos. Rastreabilidade via digest nos logs do GitLab.

2. **TruffleHog `--only-verified`**: Elimina >90% de false positives ao custo de latência
   de rede (verifica credenciais contra APIs reais). Para air-gapped: remover flag.

3. **YAML anchors para PushGateway**: Padrão `*push_metric` reutilizado nos 4 jobs
   elimina duplicação de código de observabilidade.

4. **SonarQube `qualitygate.wait=true`**: Essencial para bloqueio síncrono. Sem isso,
   o scanner retorna 0 mesmo com Quality Gate falhando.

5. **Harbor API v2.0**: Configuração de `prevent_vul` e `severity` fica em
   `projects/{id}` → `metadata`, não em endpoint de configuração global.
