# ADR-081: SAST/DAST Pipeline Enforcement Strategy (CICD-001)

**Data**: 2026-02-26
**Atualizado**: 2026-03-03 — SonarQube 10.x API compatibility fix (gateId -> gateName)
**Status**: Proposto
**Decisor**: Platform SRE Team
**Contexto**: CICD-001 — Security scanning enforcement in GitLab CI/CD pipelines

---

## Contexto

### Problema

O pipeline CI/CD da plataforma (GAP-002/005 completos) executa build, test e deploy sem nenhuma
barreira de segurança obrigatória. O resultado atual:

- SonarQube deployado (GAP-004/GAP-008) mas `allow_failure: true` — qualquer código com
  vulnerabilidades passa livremente para produção
- Harbor com Trivy integrado mas sem threshold de severidade configurado — imagens com CVEs
  CRITICAL são aceitas
- Zero detecção de secrets em commits — credenciais podem vazar via git history sem alerta
- Zero varredura de CVEs em dependências (npm, maven, pip) — supply chain attack possível
- Sem observabilidade de scans: nenhuma métrica, nenhum alerta, nenhum dashboard

### Estado Atual da Infraestrutura

| Componente | Status | Observação |
|---|---|---|
| GitLab CI/CD | Operacional (GAP-002/005) | Pipeline funcional, sem security stage |
| SonarQube 10.3.0 | Deployado (GAP-004) | allow_failure: true (não bloqueia) |
| Harbor + Trivy | Operacional | Sem severity threshold |
| Vault + ESO | Operacional (100% secrets) | Secrets gerenciados corretamente |
| Prometheus + Grafana | Operacional | Sem métricas de security scan |
| GitLab Runner | Kubernetes executor | namespace: staging-platform-gitlab |

### Requisitos

1. **Blocking obrigatório**: Qualquer vulnerabilidade HIGH/CRITICAL ou Quality Gate ERROR deve
   bloquear o merge. `allow_failure: false` em todos os scanners.
2. **4 scanners**: SAST (SonarQube), container scan (Trivy), CVE de dependências (OWASP DC),
   detecção de secrets (TruffleHog)
3. **Observabilidade**: Métricas Prometheus, alertas, dashboard Grafana
4. **Developer experience**: Mecanismos de suppression claros, feedback rápido em PRs
5. **Image pinning**: Versões fixas para reproducibilidade e supply chain security

---

## Decisão

**Implementar `security-scan` como stage obrigatório no pipeline**, com 4 scanners, todos
com `allow_failure: false`, métricas via PushGateway, e suppression mecanismos bem documentados.

### Arquitetura

```
GitLab MR Push
      │
      ▼
┌─────────────────────────────────────────────────────────────────┐
│                      GitLab CI Pipeline                          │
│                                                                  │
│  [build] → [test] → [security-scan] → [deploy]                  │
│                           │                                      │
│              ┌────────────┼────────────┐                         │
│              │            │            │                          │
│         ┌────▼───┐  ┌────▼────┐  ┌───▼──────────────────┐      │
│         │SONAR-  │  │TRIVY    │  │OWASP DC   │TruffleHog│      │
│         │QUBE    │  │CONTAINER│  │DEPENDENCY │SECRET    │      │
│         │SAST    │  │SCAN     │  │CHECK      │SCAN      │      │
│         └────┬───┘  └────┬────┘  └─────┬─────┴────┬─────┘      │
│              │            │              │          │             │
│         allow_failure: false (ALL scanners — CRITICAL)           │
└──────────────┼────────────┼──────────────┼──────────┼────────────┘
               │            │              │          │
               └────────────┴──────────────┴──────────┘
                                    │
                          Prometheus PushGateway
                          (métricas por scanner/projeto)
                                    │
                          Grafana Dashboard + Alerts
```

---

## Scanners: Decisões Técnicas

### 1. SonarQube SAST — `sonarqube/sonar-scanner-cli:5.0`

**Decisão**: Usar SonarQube existente com `-Dsonar.qualitygate.wait=true`

**Justificativa**:
- SonarQube 10.3.0 já deployado e integrado (GAP-004/GAP-008)
- Native quality gate wait: bloqueia o scanner até o gate ser avaliado
- Evita custo de tool adicional
- Quality Gate "Platform Security Gate" criado via API (script configure-blocking.sh)

**SonarQube 10.x API Compatibility (2026-03-03 fix)**:

SonarQube 10.x introduced breaking changes to the Quality Gate API parameters.
The `configure-blocking.sh` script was updated to use the v10.x API exclusively:

| API Endpoint | v9.x Parameter | v10.x Parameter (current) |
|---|---|---|
| `qualitygates/create_condition` | `gateId=<numeric-id>` | `gateName=<gate-name>` |
| `qualitygates/set_as_default` | `id=<numeric-id>` | `name=<gate-name>` |
| `qualitygates/show` | `id=<numeric-id>` | `name=<gate-name>` |

The script now:
- Detects SonarQube version at startup and aborts if < 10.x
- Uses `gateName`/`name` parameters throughout (not `gateId`/`id`)
- Properly URL-encodes the gate name for API calls
- Validates curl responses with proper error handling
- Is fully idempotent (removes existing conditions before re-creating)

**Condições de bloqueio (Quality Gate)**:
| Métrica | Threshold | Tipo |
|---|---|---|
| New Vulnerabilities | > 0 | BLOCKING |
| New Bugs | > 0 | BLOCKING |
| Security Hotspots Reviewed | < 100% | BLOCKING |
| New Coverage | < 80% | BLOCKING |
| New Reliability Rating | > A | BLOCKING |
| New Security Rating | > A | BLOCKING |
| New Code Smells | > 20 | WARNING (informativo) |
| New Duplicated Lines | > 5% | WARNING (informativo) |

**Alternativas rejeitadas**:
- Semgrep: Requer deployment adicional; SonarQube já cobre o caso de uso
- Checkmarx/Veracode: Custo SaaS — contrario a estrategia on-premises

### 2. Container Scan — `aquasec/trivy:0.50.0`

**Decisão**: Trivy versão 0.50.0 (pinned) com threshold HIGH,CRITICAL

**Justificativa**:
- Trivy já integrado ao Harbor (scan automático no push)
- CI scan complementar: varre a imagem após build, antes do push, com saída legível
- Dupla cobertura: CI bloqueia, Harbor bloqueia pull de imagens já registradas
- SARIF output: integração com GitLab Security tab (futura melhoria)
- `.trivyignore`: mecanismo simples de suppression sem burocracia excessiva

**Threshold**: HIGH,CRITICAL (MEDIUM e LOW não bloqueiam — relatório informativo)

**Alternativas rejeitadas**:
- Grype (Anchore): Menos maduro; menor comunidade; mesmo custo
- Snyk Container: Requer conta SaaS paga; preferimos self-hosted
- Clair: Descontinuado em favor do Trivy pelo próprio Harbor

### 3. Dependency CVE Scan — `owasp/dependency-check:latest`

**Decisão**: OWASP Dependency-Check com CVSS threshold >= 7.0

**Justificativa**:
- Cobertura de supply chain (npm, maven, pip, go.sum) não coberta pelo Trivy
- Trivy foca em OS packages; OWASP DC foca em bibliotecas da aplicação
- CVSS >= 7.0 = HIGH/CRITICAL: alinhado com threshold do Trivy
- NVD database: autoridade em CVE data
- Suppression XML: mecanismo declarativo com data de expiração obrigatória

**Nota sobre `:latest`**: Usado intencionalmente para OWASP DC. O NVD database é atualizado
diariamente; versão pinned causaria dados obsoletos. O risco de supply chain é mitigado pela
verificação de hash no GitLab cache.

**Alternativas rejeitadas**:
- Snyk: Requer token SaaS; licensing cost para projetos privados
- npm audit / pip-audit por projeto: Requer toolchain por linguagem; OWASP é agnóstico

### 4. Secret Detection — `trufflesecurity/trufflehog:latest`

**Decisão**: TruffleHog com `--only-verified` (verifica credenciais contra APIs externas)

**Justificativa**:
- Zero falsos positivos: `--only-verified` só reporta secrets que funcionam em APIs reais
- Ampla cobertura: 700+ detectores (AWS, GCP, GitHub, Slack, Stripe, etc.)
- Git history: escaneia últimos N commits (configurável via TRUFFLEHOG_SCAN_DEPTH)
- Mantido pela TruffleHog Security (open source, Apache 2.0)

**Configuração `--only-verified`**: Elimina false positives ao custo de latência de rede.
Para ambientes air-gapped, remover `--only-verified` e usar `--fail` apenas.

**Alternativas rejeitadas**:
- GitLeaks: Menor cobertura de detectores; sem verificação via API
- GitLab Secret Detection: Requer GitLab Ultimate; preferimos open source
- detect-secrets (Yelp): Sem verificação; alta taxa de falso positivo

---

## Image Pinning Strategy

| Scanner | Imagem | Tag Policy | Razão |
|---|---|---|---|
| SonarQube | `sonarqube/sonar-scanner-cli:5.0` | Minor pinned | Scanner estável; minor version = compatível |
| Trivy | `aquasec/trivy:0.50.0` | Patch pinned | Formato saída fixo; CVE DB separada |
| OWASP DC | `owasp/dependency-check:latest` | latest | NVD DB atualizado diariamente |
| TruffleHog | `trufflesecurity/trufflehog:latest` | latest | Detectores em constante evolução |

**Nota**: `:latest` é aceitável para OWASP DC e TruffleHog porque o GitLab pipeline
registra a imagem digest nos logs (rastreabilidade), e esses scanners têm backward-compatible
output que não quebra nossos parsers.

---

## Métricas e Observabilidade

### Prometheus PushGateway

Métricas enviadas ao final de cada job de scan:

```
# Duração em segundos
gitlab_ci_pipeline_security_scan_duration_seconds{
  scanner="sonarqube|trivy|owasp-dependency-check|trufflehog",
  project="<project-path-slug>",
  branch="<branch>",
  status="pass|fail"
}

# Status 1=pass, 0=fail
gitlab_ci_pipeline_security_scan_status{
  scanner="...",
  project="...",
  branch="..."
}
```

### Alertas Prometheus (cicd-security-prometheus-rules.yaml)

| Alert | Severidade | Trigger |
|---|---|---|
| SonarQubeQualityGateFailed | critical | sonarqube_quality_gate_status != OK |
| TrivyCriticalVulnerabilitiesFound | critical | scan_status{scanner=trivy} == 0 |
| TruffleHogSecretDetected | critical | scan_status{scanner=trufflehog} == 0 |
| PipelineSecurityScanFailed | warning | qualquer scan_status == 0 |
| OWASPDependencyCheckFailed | warning | scan_status{scanner=owasp} == 0 |
| SecurityScanDurationAnomaly | warning | duration > 600s |
| SonarQubeDown | warning | up{job=~".*sonarqube.*"} == 0 |

### Grafana Dashboard

- **UID**: `cicd001-security-scans`
- **Arquivo**: `monitoring/grafana/dashboards/cicd-security-scan-performance.json`
- **Painéis**: Quality gate status, pass/fail ratio, scan duration, vulnerability trends

---

## Suppression Mechanisms

Cada scanner tem seu próprio mecanismo de suppression para gerenciar false positives:

### SonarQube
- Marcar issue como "Won't Fix" ou "False Positive" no UI
- Adicionar comentário explicativo obrigatório
- Revisão de peer via SonarQube UI

### Trivy
- Adicionar CVE ao `.trivyignore` com comentário:
  ```
  # CVE-2023-12345: Presente em libssl mas código vulnerável não é chamado
  # Revisado por: <nome> em <data>. Próxima revisão: <data+30dias>
  CVE-2023-12345
  ```

### OWASP Dependency-Check
- `dependency-check-suppression.xml` com data de expiração obrigatória:
  ```xml
  <suppress until="2026-05-01">
    <notes>CVE-XXXX: Revisado por <nome> em <data>. ...</notes>
    <cve>CVE-XXXX-XXXXX</cve>
  </suppress>
  ```

### TruffleHog
- Comentário inline `# trufflehog:ignore` na linha com o falso positivo
- Para strings que parecem secrets mas não são: adicionar ao `.trufflehogignore`

---

## Deployment Architecture

```
Kubernetes Namespace: staging-observability-monitoring
  ├── PrometheusRule: cicd001-security-scan-alerts
  └── Prometheus PushGateway: recebe métricas de scan

Kubernetes Namespace: sonarqube
  └── SonarQube 10.3.0 (Quality Gate: "Platform Security Gate")

Kubernetes Namespace: harbor-system
  └── Harbor + Trivy (severity threshold: HIGH,CRITICAL)

GitLab CI (namespace: staging-platform-gitlab)
  └── Templates: domains/cicd-platform/infra/gitlab-ci/templates/
      └── security.gitlab-ci-security-template.yml
```

---

## Riscos e Mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|---|---|---|---|
| OWASP DC download lento (NVD) | Alta | Médio | GitLab cache para .owasp-cache/data/ |
| Falso positivo bloqueia release crítica | Média | Alto | Processo de suppression documentado + emergency bypass |
| TruffleHog verifica secrets externos (rede) | Baixa | Baixo | Timeout de 5min; falha não catastrófica |
| SonarQube indisponível | Baixa | Alto | Alert SonarQubeDown; equipe notificada antes |
| Imagem Trivy desatualizada (CVE DB) | Baixa | Médio | Trivy atualiza DB em runtime automaticamente |

### Emergency Bypass (excepcional)

Em situações críticas de release onde um bloqueio falso ou não-corrigível deve ser contornado
temporariamente:

1. Platform SRE ou Tech Lead deve aprovar via GitLab MR review
2. Criar issue de seguimento com SLA de resolução (máx 5 dias úteis)
3. Definir variável `SECURITY_SCAN_BYPASS_REASON` no pipeline com justificativa
4. Commit na branch com mensagem `[SECURITY-BYPASS] Motivo: <justificativa>`

**NUNCA use `allow_failure: true` como workaround permanente.**

---

## Alternativas Consideradas

### Opção A: GitLab Ultimate Security Features (Rejeitada)

GitLab Ultimate inclui SAST, DAST, Container Scanning nativamente.

**Prós**: Integrado ao UI, relatórios automáticos, nenhuma configuração de scanners
**Contras**:
- Custo: ~$99/usuário/mês (vs $0 para open source)
- Vendor lock-in
- Já temos SonarQube + Trivy deployados e funcionais

**Decisão**: Rejeitada. Open source stack mais econômico e sem lock-in.

### Opção B: Apenas SonarQube (Rejeitada)

Usar somente SonarQube sem Trivy, OWASP DC ou TruffleHog.

**Prós**: Simplicidade
**Contras**:
- SonarQube não varre OS packages em containers
- SonarQube não varre dependências transitivas com CVE database
- SonarQube não detecta secrets com verificação
- Cobertura incompleta para CWE e OWASP Top 10

**Decisão**: Rejeitada. Defesa em profundidade requer múltiplos scanners.

### Opção C: allow_failure: true com alertas (Rejeitada)

Manter scanners não-bloqueantes mas alertar no Slack/PagerDuty.

**Prós**: Zero friction para developers
**Contras**:
- Alert fatigue leva a ignorar alertas
- Sem garantia de resolução antes do deploy
- Viola princípio de "shift-left security"

**Decisão**: Rejeitada. Security deve ser enforced, não apenas observado.

---

## Implementação

### Fase 1 — Artefatos (2026-02-26) ✅ COMPLETO

- [x] `domains/cicd-platform/infra/gitlab-ci/templates/security.gitlab-ci-security-template.yml`
- [x] `scripts/sonarqube/configure-blocking.sh`
- [x] `scripts/harbor/configure-trivy-blocking.sh`
- [x] `domains/observability/infra/alerts/cicd-security-prometheus-rules.yaml`
- [x] `monitoring/grafana/dashboards/cicd-security-scan-performance.json`
- [x] `docs/runbooks/security-scan-failures-troubleshooting.md`
- [x] `docs/CICD-001-DEVELOPER-GUIDE.md`

### Fase 2 — Deploy (quando cluster estiver UP)

1. Aplicar PrometheusRule:
   ```bash
   kubectl apply -f domains/observability/infra/alerts/cicd-security-prometheus-rules.yaml
   ```
2. Configurar SonarQube Quality Gate (SonarQube 10.x API - gateName):
   ```bash
   SONAR_TOKEN=<token> ./scripts/sonarqube/configure-blocking.sh
   ```
   Note: Script updated 2026-03-03 for SonarQube 10.x compatibility.
   Uses `gateName`/`name` parameters (not `gateId`/`id` from v9.x).
3. Configurar Harbor Trivy:
   ```bash
   HARBOR_ADMIN_PASSWORD=<pass> ./scripts/harbor/configure-trivy-blocking.sh
   ```
4. Importar Grafana dashboard via UI ou API
5. Adicionar template include aos projetos piloto

### Fase 3 — Adoção (Sprint+1)

- Onboarding dos 3 primeiros projetos (piloto)
- Ajuste de thresholds baseado em feedback
- Rollout para todos os projetos

---

## Consequências

### Positivas

- **Segurança**: Vulnerabilidades HIGH/CRITICAL não chegam à produção
- **Compliance**: Evidência auditável de security scanning em cada deploy
- **Developer awareness**: Feedback imediato sobre code quality e security
- **Observabilidade**: Dashboard centralizado de postura de segurança

### Negativas (aceitas)

- **Pipeline mais lento**: +3-15min por pipeline (OWASP DC pode ser lento na primeira run)
- **Setup por projeto**: Cada projeto precisa incluir o template e configurar stages
- **False positives**: Requerem processo formal de suppression (documentado)

---

## Referências

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [CWE/SANS Top 25](https://cwe.mitre.org/top25/)
- [Trivy Documentation](https://aquasecurity.github.io/trivy/)
- [SonarQube Quality Gates](https://docs.sonarqube.org/latest/user-guide/quality-gates/)
- [TruffleHog Documentation](https://github.com/trufflesecurity/trufflehog)
- [OWASP Dependency-Check](https://jeremylong.github.io/DependencyCheck/)
- [ADR-075: SonarQube Prometheus Exporter](docs/adr/adr-075-sonarqube-prometheus-exporter.md)
- [GAP-008: SonarQube Exporter](docs/logbook/2026-02-24-gap008-dashboards.md)
- [Runbook: Security Scan Failures](docs/runbooks/security-scan-failures-troubleshooting.md)
- [Developer Guide: CICD-001](docs/CICD-001-DEVELOPER-GUIDE.md)

---

**Implementado por**: Platform SRE Team
**Data**: 2026-02-26
**Atualizado**: 2026-03-03 — SonarQube 10.x API fix (gateId -> gateName/name)
**Status**: Artefatos prontos — aguardando cluster UP para deploy
