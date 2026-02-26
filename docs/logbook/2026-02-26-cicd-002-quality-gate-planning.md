# Logbook: CICD-002 — SonarQube Quality Gate Enforcement

**Date**: 2026-02-26
**Demand**: CICD-002 — SonarQube Quality Gate Enforcement Policy
**Status**: Artefatos completos — aguardando cluster UP para deploy
**Effort**: ~2.5h (script + template + alertas + dashboard + documentação)
**ADR**: [ADR-082](../adr/adr-082-sonarqube-quality-gate-policy.md)
**Previous**: [CICD-001 Logbook](2026-02-26-cicd-001-sast-dast-planning.md)

---

## Objetivo

Complementar o CICD-001 (SAST/DAST enforcement) com uma **política formal de quality gate**
para o SonarQube: definir os thresholds específicos da plataforma, codificá-los em script,
integrá-los ao pipeline e criar observabilidade granular por métrica.

## Contexto

**Estado anterior (pré-CICD-002)**:
- CICD-001: 4 scanners com `allow_failure: false`, SonarQube gate genérico
- Quality gate "Sonar way" padrão (permissivo, sem thresholds corporativos)
- Script configure-blocking.sh do CICD-001 criava gate mas sem documentação formal de thresholds
- Sem observabilidade por métrica individual (coverage, bugs, smells separadamente)
- Sem guia para desenvolvedores sobre como corrigir falhas específicas

**Estado após CICD-002**:
- Quality gate "Production" codificado com 5 condições formalizadas
- Script configure-quality-gate.sh com thresholds parametrizáveis e idempotente
- Template GitLab CI dedicado ao quality gate enforcement
- 8 alertas Prometheus granulares (por métrica + por pipeline)
- Grafana dashboard "Code Quality Trends" (uid: cicd002-quality-gate)
- ADR-082 com justificativa dos thresholds e policy de exclusão
- Developer guide completo com exemplos por linguagem e processo de FP

---

## Decisões Técnicas

### Thresholds Escolhidos e Justificativas

| Condição | Threshold | Justificativa |
|----------|-----------|---------------|
| Coverage >= 80% | 80% | Industry standard (Google, Martin Fowler); equilíbrio entre rigor e agilidade |
| New Bugs = 0 | 0 | Tolerância zero: bugs do SonarQube são falhas de lógica comprovadas |
| New Vulnerabilities = 0 | 0 | Tolerância zero: alinhado com ADR-081/CICD-001 |
| Code Smells <= 10 | 10 | Previne acumulação; mais restritivo que CICD-001 (20) |
| Hotspots Reviewed >= 80% | 80% | Menos restritivo que CICD-001 (100%) — permite revisão incremental |

**Decisão sobre 90% vs 80% coverage**:
Consideramos 90% mas rejeitamos. 90% incentiva "gaming" da métrica (testes sem assertions reais).
80% foca em cobertura significativa dos fluxos principais + tratamento de erros.

**Decisão sobre Code Smells <= 10 vs <= 20**:
CICD-001 usa 20 mas era uma condição informativa (não bloqueante com WARNING). CICD-002 usa 10
como condição ERROR (bloqueante) porque 20 smells/PR em projetos ativos = acumulação rápida.

### Nome do Quality Gate: "Production"

Escolhido sobre "Platform Quality Gate" porque:
- Mais intuitivo para desenvolvedores
- Indica claramente para que ambiente serve
- Distingue de "Platform Security Gate" (CICD-001) sem ambiguidade

### Relação com o Gate do CICD-001

"Platform Security Gate" (CICD-001) e "Production" (CICD-002) podem coexistir.
"Production" se torna o gate **default** para todos os novos projetos, substituindo
"Platform Security Gate" como padrão. Projetos que precisam de rigor extra de segurança
(100% hotspots reviewed, reliability/security ratings) podem usar "Platform Security Gate".

### Template GitLab CI separado vs integrado ao CICD-001

Optamos por template **separado** porque:
- CICD-001 template já é completo com 4 scanners — adicionar quality gate aumentaria complexidade
- Projetos podem adotar quality gate enforcement sem todos os 4 scanners do CICD-001
- Manutenção independente: thresholds do quality gate evoluem separadamente de scanner versions
- Permite inclusão incremental: primeiro quality gate, depois full security scan

### Emergency Bypass via variável CI/CD

Implementado `SONAR_QUALITY_GATE_BYPASS=true` (requer `SONAR_BYPASS_REASON`) no lugar de
modificar o template. Razões:
- Auditável: variáveis GitLab ficam no log da pipeline
- Não requer modificação de código
- BYPASS_REASON obrigatório garante accountability
- Platform SRE pode remover a variável após SLA sem tocar no código

---

## Artefatos Criados

### 1. Script de Automação

**Arquivo**: `scripts/sonarqube/configure-quality-gate.sh`

Script completo para criar/atualizar o gate "Production" via SonarQube API.

**Características**:
- Idempotente: remove condições existentes antes de recriar (clean slate approach)
- Parametrizável: `--coverage 90 --max-smells 5` (todos os thresholds via flags)
- `--dry-run`: preview sem alterações reais
- `--validate`: relatório do estado atual sem alterações
- `--no-set-default`: não define como gate padrão (útil para ambientes de teste)
- URL encoding correto para nomes de gates com espaços
- Error handling completo (curl exit codes, HTTP status, jq parsing)
- Output colorido com seções claramente identificadas

**Novidades vs configure-blocking.sh (CICD-001)**:
- Parametrização de todos os thresholds (CICD-001 tinha valores hardcoded)
- Validação de tipo (thresholds devem ser inteiros)
- `--no-set-default` flag
- Seções coloridas para output mais legível
- Imprime thresholds summary antes de executar

### 2. GitLab CI Template

**Arquivo**: `domains/cicd-platform/infra/gitlab-ci/templates/sonarqube-quality-gate.gitlab-ci.yml`

**Stage**: `quality-gate` (separado de `security-scan`)

**Features**:
- `allow_failure: false` — bloqueia merge se quality gate falhar
- `sonar.qualitygate.wait=true` — polling síncrono até gate ser avaliado
- Auto-detection do formato de coverage report (XML, lcov, .out) por extensão de arquivo
- Branch/MR-aware: adiciona labels corretos para análise incremental
- Emergency bypass: `SONAR_QUALITY_GATE_BYPASS=true` requer `SONAR_BYPASS_REASON`
- Output detalhado: mensagem clara de erro com link direto para SonarQube
- Artifact: `quality-gate-results/` com JSON + texto
- Metrics: push para PushGateway após cada run

**Condições de execução**:
- MR events (primary enforcement)
- main branch (tracking de qualidade ao longo do tempo)
- release/* e hotfix/* (branches críticas)
- Não roda em feature branches fora de MR (evita ruído)

### 3. PrometheusRule (Alertas)

**Arquivo**: `domains/observability/infra/alerts/sonarqube-quality-gate-prometheus-rules.yaml`

**Nome**: `cicd002-quality-gate-alerts`
**Namespace**: `monitoring`

8 alertas em 2 grupos:

**Grupo cicd002.quality-gate.sonarqube** (métricas nativas SonarQube):
- `SonarQubeQualityGateFailed` (warning) — gate em ERROR ou WARN
- `SonarQubeCoverageDropped` (warning) — coverage < 80%, for 10m
- `SonarQubeNewBugs` (warning) — bugs > 0, for 5m
- `SonarQubeNewVulnerabilities` (critical) — vulnerabilidades > 0, for 5m
- `SonarQubeHighDebtAccumulation` (warning) — smells > 10, for 15m

**Grupo cicd002.quality-gate.pipeline** (PushGateway — CI jobs):
- `QualityGatePipelineBlocked` (warning) — pipeline CI bloqueada, for 0m
- `QualityGateScanTimeout` (warning) — scan > 5 min, for 0m
- `QualityGateScanMissing` (warning) — sem scan há 48h, for 1h

**Nota sobre SonarQubeCoverageDropped** (`for: 10m`):
Período mais longo que os outros porque coverage pode oscilar temporariamente entre
análises. 10 minutos evita alertas falsos em deploys incrementais.

### 4. Grafana Dashboard

**Arquivo**: `monitoring/grafana/dashboards/cicd-quality-gate-trends.json`
**UID**: `cicd002-quality-gate`
**Título**: `CICD-002: Code Quality Trends`
**Refresh**: 5 minutos

6 seções:
1. **Quality Gate Overview**: Stat panels — status geral, coverage, bugs, vulns, smells
   - Color thresholds: verde/amarelo/vermelho conforme thresholds do gate
2. **Quality Gate Pass/Fail Over Time**: Timeseries por projeto + pass rate 7d
   - `sonarqube_project_quality_gate_status` (0=OK, 1=WARN, 2=ERROR)
3. **Coverage Trends**: Timeseries multi-projeto com linha de threshold em 80%
   - Visualiza trajetória de coverage para identificar regressões
4. **Bugs and Vulnerabilities**: Bar charts separados por tipo e projeto
   - Fácil identificação de qual projeto introduziu problemas
5. **Technical Debt — Code Smells**: Timeseries + stat de total com threshold em 10
6. **Pipeline Quality Gate History**: Pass/fail de CI jobs + scan duration
   - Fonte: Prometheus PushGateway (gitlab_ci_quality_gate_status)

**Variáveis**:
- `datasource`: seletor de datasource Prometheus
- `project`: multi-select por label `project` (auto-populated via label_values)

### 5. ADR-082

**Arquivo**: `docs/adr/adr-082-sonarqube-quality-gate-policy.md`

Seções:
- Contexto e estado anterior
- Decisão e thresholds formalizados
- Justificativa detalhada de cada threshold (com alternativas rejeitadas)
- Relação com CICD-001 (Platform Security Gate vs Production)
- Automação e IaC
- Processo de exclusão temporária (por categoria + SLAs)
- False positives: processo e exemplos
- Observabilidade (alertas + dashboard)
- Alternativas consideradas e rejeitadas
- Deployment architecture
- Riscos e mitigações

### 6. Developer Guide

**Arquivo**: `docs/guides/quality-gate-compliance.md`

Guia completo para desenvolvedores, cobrindo:
- Quick summary e thresholds
- Como encontrar o motivo de falha (CI job, SonarQube UI, artifact)
- Fix por tipo de falha:
  - Coverage < 80%: como executar testes por linguagem, como configurar SONAR_COVERAGE_REPORT
  - New Bugs: tipos comuns + fixes em Python/Java/JavaScript
  - New Vulnerabilities: SQL injection, XSS, hardcoded credentials, weak crypto
  - Code Smells: método longo, magic numbers, duplicação, cognitive complexity
  - Security Hotspots: como revisar cada tipo
- Processo de false positives (quando marcar, como documentar)
- Processo de exclusão temporária (quando, como, SLAs por tipo)
- Local SonarQube scanning (sonar-scanner local, sonar-project.properties)
- Como incluir o template no projeto (minimal + full setup com coverage)
- FAQ (8 perguntas comuns dos desenvolvedores)

---

## Dependências para Deploy

### Sequência de deploy (quando cluster UP)

```bash
# 1. Port-forward SonarQube
kubectl port-forward svc/sonarqube 9000:9000 -n sonarqube &

# 2. Obter token admin
# SonarQube UI: http://localhost:9000 → My Account → Security → Tokens → Generate

# 3. Configurar quality gate "Production"
export SONAR_TOKEN="squ_..."
./scripts/sonarqube/configure-quality-gate.sh

# 4. Validar
./scripts/sonarqube/configure-quality-gate.sh --validate

# 5. Aplicar PrometheusRule
kubectl apply -f domains/observability/infra/alerts/sonarqube-quality-gate-prometheus-rules.yaml

# 6. Verificar PrometheusRule foi carregada
kubectl get prometheusrule cicd002-quality-gate-alerts -n monitoring

# 7. Importar dashboard Grafana
# UI: Grafana → Dashboards → Import → Upload JSON
# File: monitoring/grafana/dashboards/cicd-quality-gate-trends.json

# 8. Adicionar template ao primeiro projeto piloto
# Em .gitlab-ci.yml:
# include:
#   - project: 'platform/templates'
#     file: '/gitlab-ci/templates/sonarqube-quality-gate.gitlab-ci.yml'
```

### Pré-requisitos verificados

- [x] SonarQube 10.3.0 deployado com ServiceMonitor (GAP-008, ADR-075)
- [x] ServiceMonitor scrapa `/api/monitoring/metrics` (verificado GAP-008)
- [x] Prometheus PushGateway disponível em monitoring namespace
- [x] GitLab Runner com envFrom: gitlab-ci-credentials (SONAR_HOST_URL, SONAR_TOKEN)
- [x] NetworkPolicies permitem runner → sonarqube (GAP-007 configurado)

---

## Métricas de Sucesso

| KPI | Meta | Como medir |
|-----|------|-----------|
| Projects com quality gate passando | >= 80% | Grafana: pass rate geral |
| Tempo médio de scan | < 3 min | Grafana: scan duration |
| Coverage média da plataforma | >= 80% | Grafana: coverage trend |
| Vulnerabilidades introduzidas por sprint | 0 | PrometheusRule alert: SonarQubeNewVulnerabilities |
| False positives como % de issues | < 5% | Manual review mensal |

---

## Próximos Passos

### Imediato (cluster UP)
1. Deploy da sequência acima
2. Validar: SonarQube UI mostra gate "Production" como default
3. Testar: push MR com cobertura < 80% → confirmar que pipeline bloqueia
4. Onboarding projeto piloto de baixo risco

### Sprint+1
1. Rollout para todos os projetos da plataforma
2. Review de thresholds após 2 semanas de dados no Grafana
3. Ajustar thresholds se necessário (com MR na ADR-082)
4. Setup de `sonar-project.properties` nos projetos principais

### Médio prazo
1. PR decoration no GitLab (SonarQube comenta diretamente no diff)
2. Exclusion policy refinada baseada em dados reais
3. Per-project threshold overrides se demanda surgir
4. Integração com relatórios de sprint: coverage trend por squad

---

## Lições Aprendidas

### 1. Parametrização de thresholds via flags

O configure-blocking.sh (CICD-001) tinha thresholds hardcoded, tornando impossível criar
variações sem modificar o script. O configure-quality-gate.sh (CICD-002) usa flags
(`--coverage`, `--max-smells`, etc.) tornando-o reutilizável para diferentes contextos.

### 2. Template separado vale a complexidade

Criar `sonarqube-quality-gate.gitlab-ci.yml` separado do `security.gitlab-ci-security-template.yml`
permite adoção incremental e manutenção independente. Projetos que só precisam de quality gate
enforcement não precisam de todos os 4 scanners do CICD-001.

### 3. Auto-detection de coverage report por extensão

Em vez de forçar o desenvolvedor a conhecer a propriedade exata (`sonar.javascript.lcov.reportPaths`
vs `sonar.coverage.jacoco.xmlReportPaths`), o template detecta o formato pela extensão do arquivo.
Isso reduz a curva de aprendizado para onboarding de novos projetos.

### 4. Emergency bypass requer AMBAS as variáveis

Apenas `SONAR_QUALITY_GATE_BYPASS=true` não funciona — `SONAR_BYPASS_REASON` também é obrigatório.
Isso garante que bypasses sejam sempre documentados (accountability). Sem a razão, o job falha
com mensagem clara explicando o que falta.

### 5. Alertas com for duration diferente por tipo

- `SonarQubeNewVulnerabilities`: `for: 5m` — vulnerabilidades são críticas, alertar rápido
- `SonarQubeCoverageDropped`: `for: 10m` — coverage oscila entre análises; aguardar estabilização
- `SonarQubeHighDebtAccumulation`: `for: 15m` — debt é tendência, não evento pontual

Usar o mesmo `for` para todos os alertas geraria falsos positivos em análises incrementais.
