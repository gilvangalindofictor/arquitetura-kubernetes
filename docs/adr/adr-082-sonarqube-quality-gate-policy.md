# ADR-082: SonarQube Quality Gate Enforcement Policy (CICD-002)

**Data**: 2026-02-26
**Status**: Proposto
**Decisor**: Platform SRE Team
**Contexto**: CICD-002 — Quality gate enforcement para todos os projetos da plataforma
**Relacionado**: ADR-081 (CICD-001 SAST/DAST), ADR-075 (SonarQube Prometheus Exporter)

---

## Contexto

### Problema

O CICD-001 (ADR-081) estabeleceu security scanning com 4 scanners, mas a **política de quality
gate do SonarQube não estava formalmente definida**:

1. O quality gate "Sonar way" (padrão) tem thresholds muito permissivos para produção
2. Não havia gate específico para os padrões de qualidade da plataforma
3. As condições (coverage, bugs, vulnerabilidades, smells) não estavam documentadas ou codificadas
4. Desenvolvedores não tinham clareza sobre **quais critérios** bloqueam o merge e **por que**
5. Ausência de observabilidade granular por métrica (apenas gate pass/fail no CICD-001)

### Estado Anterior (pré-CICD-002)

| Aspecto | Estado |
|---------|--------|
| Quality Gate padrão | "Sonar way" (permissivo, não customizado) |
| Coverage mínima | Não definida formalmente |
| Política de bugs | Não especificada |
| Política de vulnerabilidades | Tratada no CICD-001 (new_vulnerabilities > 0) |
| Code smells | Sem threshold definido |
| Security hotspots | Sem threshold definido |
| Automação do gate | Script manual (configure-blocking.sh) sem documentação de thresholds |
| Observabilidade por métrica | Ausente (apenas gate status agregado) |
| Guia para desenvolvedores | Ausente |

### Requisitos do CICD-002

1. **Quality gate codificado**: Thresholds versionados em código, não configurados manualmente via UI
2. **Cobertura mínima**: 80% em código novo (industry standard para projetos de produção)
3. **Zero bugs**: Tolerância zero para bugs em código novo (reliability policy)
4. **Zero vulnerabilidades**: Tolerância zero para vulnerabilidades (security policy)
5. **Limite de code smells**: Máximo de 10 por PR (maintainability gate)
6. **Security hotspots**: Mínimo 80% revisados (security review gate)
7. **Observabilidade granular**: Alertas individuais por métrica, não apenas gate status
8. **Developer experience**: Guia claro sobre como interpretar e corrigir falhas
9. **Exclusão temporária**: Processo formal para exceções com SLA e accountability

---

## Decisão

**Criar o quality gate "Production" via API** com os thresholds definidos abaixo, configurá-lo
como padrão para todos os projetos, e implementar observabilidade granular via Prometheus alerts
e Grafana dashboard dedicado.

### Thresholds Decididos

| Condição | Métrica SonarQube | Threshold | Tipo | Razão |
|----------|-------------------|-----------|------|-------|
| Coverage on New Code | `new_coverage` | >= 80% | ERROR (bloqueia) | Industry standard para projetos produção |
| New Bugs | `new_bugs` | = 0 | ERROR (bloqueia) | Zero tolerância: bugs indicam falhas de lógica |
| New Vulnerabilities | `new_vulnerabilities` | = 0 | ERROR (bloqueia) | Zero tolerância: security-first policy |
| New Code Smells | `new_code_smells` | <= 10 | ERROR (bloqueia) | Previne acumulação de dívida técnica |
| Security Hotspots Reviewed | `new_security_hotspots_reviewed` | >= 80% | ERROR (bloqueia) | Garante revisão de código sensível |

**Todos os thresholds são ERROR** (bloqueantes). Não há condições de WARNING no gate, pois
WARNING no SonarQube apenas informa — não bloqueia pipelines. Alertas informativos são
gerenciados via PrometheusRules (CICD-002).

---

## Justificativa dos Thresholds

### Coverage >= 80%

**Justificativa**:
- 80% é o padrão amplamente adotado na indústria como threshold de produção (Google, Microsoft, Martin Fowler)
- Cobertura < 80% indica código não testado que pode ter comportamento indefinido em produção
- A métrica usa `new_coverage` (apenas código novo), não cobertura total do projeto
- Código legado com cobertura baixa não é impactado imediatamente — apenas novo código deve atender

**Por que não 90%?**:
- 90% frequentemente leva a testes de baixa qualidade escritos apenas para atingir a métrica
- 80% foca em cobertura **significativa** — testa fluxos principais e casos de erro
- Time de produto pode priorizar funcionalidades em sprints sem sacrificar testes

**Por que não 70%?**:
- 70% deixa 30% de código novo sem testes — risco elevado para produção
- 80% é o mínimo que demonstra que o desenvolvedor testou os caminhos principais

### New Bugs = 0

**Justificativa**:
- Bugs detectados pelo SonarQube são falhas de lógica comprovadas (não style issues)
- Exemplos: null pointer, stream não fechado, comparação incorreta, divisão por zero
- Introduzir bugs em MRs compromete a confiabilidade do sistema
- Zero tolerance é o padrão de plataformas mature (Google, Netflix, Spotify)

**Alternativas rejeitadas**:
- Bugs <= 5: Permite acumulação gradual. Em 10 MRs = 50 bugs não corrigidos.
- Severity-based: SonarQube já classifica bugs por severity internamente; nosso gate é direto.

### New Vulnerabilities = 0

**Justificativa**:
- Vulnerabilidades são falhas de segurança exploráveis (OWASP Top 10: SQL injection, XSS, etc.)
- Zero tolerância alinhada com ADR-081 (CICD-001) que também usa `new_vulnerabilities > 0`
- Complementar ao Trivy (container scan): SonarQube detecta vulnerabilidades em código-fonte;
  Trivy detecta em packages OS. Cobertura complementar.

### New Code Smells <= 10

**Justificativa**:
- Code smells são issues de maintainability (métodos longos, classes God, duplicação)
- Threshold de 10 permite PRs com refatorações menores sem bloquear
- Mais de 10 smells num PR indica que o desenvolvedor não está controlando a qualidade
- Previne acumulação: em 20 PRs sem controle = 200+ smells, tornando o projeto difícil de manter

**Por que não <= 5?**:
- Muito restritivo para PRs legítimos que tocam código existente com smells
- 10 oferece flexibilidade enquanto mantém controle

**Por que não <= 20?**:
- 20 por PR = acumulação rápida em projetos ativos
- 10 é o ponto de equilíbrio validado por práticas de mercado

### Security Hotspots Reviewed >= 80%

**Justificativa**:
- Security hotspots são construções que **podem** ser vulnerabilidades dependendo do contexto
- Exemplos: `Math.random()`, operações de hash, uso de `exec()`, desserialização
- 80% garante que a maioria dos hotspots seja avaliada por um desenvolvedor
- 100% seria ideal mas pode ser muito restritivo para projetos com hotspots em código legado
- Hotspots revisados como "Safe" não bloqueiam; apenas os não-revisados bloqueiam

---

## Relação com CICD-001

O CICD-001 (ADR-081) criou o gate "Platform Security Gate" com foco em **segurança**:
- new_vulnerabilities > 0 (BLOCKING)
- new_bugs > 0 (BLOCKING)
- new_security_hotspots_reviewed < 100% (BLOCKING)
- new_coverage < 80% (BLOCKING)
- new_reliability_rating > A (BLOCKING)
- new_security_rating > A (BLOCKING)
- new_code_smells > 20 (non-critical)

O CICD-002 cria o gate "Production" com foco em **qualidade e manutenibilidade**:
- Coverage >= 80% (BLOCKING — mesmo que CICD-001)
- Bugs = 0 (BLOCKING — mesmo que CICD-001)
- Vulnerabilities = 0 (BLOCKING — mesmo que CICD-001)
- Code Smells <= 10 (BLOCKING — mais restritivo que CICD-001 que usava 20)
- Hotspots Reviewed >= 80% (BLOCKING — menos restritivo que CICD-001 que usava 100%)

**Resolução**: O CICD-002 "Production" gate **substitui** o "Platform Security Gate" como gate
padrão. O "Platform Security Gate" pode coexistir para projetos que optarem por thresholds mais
restritivos. O "Production" gate é o padrão para todos os novos projetos.

---

## Automação e IaC

### Script configure-quality-gate.sh

**Arquivo**: `scripts/sonarqube/configure-quality-gate.sh`

**Características**:
- Idempotente: remove condições existentes antes de recriar (clean slate)
- Parametrizável: todos os thresholds configuráveis via flags (para projetos que precisam de exceções)
- `--dry-run`: preview sem alterações
- `--validate`: relatório do estado atual sem alterações
- `--no-set-default`: não define como gate padrão (para testes)
- URL encoding correto para nomes com espaços

**Exemplo de execução**:
```bash
# Configuração padrão
SONAR_TOKEN=<admin-token> ./scripts/sonarqube/configure-quality-gate.sh

# Com thresholds customizados
SONAR_TOKEN=<token> ./scripts/sonarqube/configure-quality-gate.sh \
  --coverage 90 \
  --max-smells 5

# Validação sem alterações
SONAR_TOKEN=<token> ./scripts/sonarqube/configure-quality-gate.sh --validate

# Preview
SONAR_TOKEN=<token> ./scripts/sonarqube/configure-quality-gate.sh --dry-run
```

### GitLab CI Template

**Arquivo**: `domains/cicd-platform/infra/gitlab-ci/templates/sonarqube-quality-gate.gitlab-ci.yml`

**Job**: `sonarqube-quality-gate`
- Image: `sonarqube/sonar-scanner-cli:5.0` (pinned para reproducibilidade)
- `allow_failure: false` (CRÍTICO: bloqueia merge)
- `sonar.qualitygate.wait=true` (polling síncrono — bloqueia até gate ser avaliado)
- Coverage report auto-detection (XML, lcov, .out) baseado em extensão
- Branch/MR-aware analysis com labels corretos
- Artifact: `quality-gate-results/` (JSON + texto com resultado)
- Metrics: push para Prometheus PushGateway após cada run
- Emergency bypass: variável `SONAR_QUALITY_GATE_BYPASS=true` com `SONAR_BYPASS_REASON` obrigatório

---

## Exclusão Temporária (Exceções)

### Processo de Exclusão

Para projetos que não podem atingir os thresholds imediatamente (legacy code, sprints críticos):

1. **Solicitar via MR**: criar um MR com justificativa técnica para exclusão temporária
2. **Aprovação**: Platform SRE ou Tech Lead deve aprovar explicitamente
3. **Definir SLA**: prazo máximo para atingir o threshold (máx 30 dias para coverage; máx 5 dias para bugs/vulnerabilidades)
4. **Issue de acompanhamento**: criar issue com SLA e assignee
5. **Implementar bypass**: definir variável CI/CD `SONAR_QUALITY_GATE_BYPASS=true` + `SONAR_BYPASS_REASON`

### Categorias de Exceção

| Categoria | Quem Aprova | SLA Máximo | Renovável? |
|-----------|-------------|------------|------------|
| Coverage < 80% (código legado) | Tech Lead | 30 dias | Sim (com nova justificativa) |
| Code Smells > 10 (débito técnico existente) | Tech Lead | 30 dias | Sim |
| Bug ou Vulnerability (false positive confirmado) | Platform SRE + Segurança | 5 dias | Não (marcar como FP em SonarQube) |

### False Positives em SonarQube

Para marcar um issue como false positive no SonarQube:

1. Acessar: SonarQube → Projeto → Issues → [issue específico]
2. Clicar em "Won't Fix" ou "False Positive"
3. Adicionar comentário explicativo **obrigatório**:
   ```
   False Positive: [razão específica]
   Revisado por: [nome] em [data]
   Aprovado por: [tech lead ou platform sre]
   ```
4. O gate passará automaticamente após essa marcação

---

## Observabilidade

### PrometheusRules (cicd002-quality-gate-alerts)

**Arquivo**: `domains/observability/infra/alerts/sonarqube-quality-gate-prometheus-rules.yaml`

| Alert | Severidade | Trigger |
|-------|-----------|---------|
| SonarQubeQualityGateFailed | warning | gate status > 0 (WARN ou ERROR) |
| SonarQubeCoverageDropped | warning | coverage < 80% |
| SonarQubeNewBugs | warning | bugs > 0 |
| SonarQubeNewVulnerabilities | critical | vulnerabilities > 0 |
| SonarQubeHighDebtAccumulation | warning | code smells > 10 |
| QualityGatePipelineBlocked | warning | CI pipeline bloqueada |
| QualityGateScanTimeout | warning | scan > 5 minutos |
| QualityGateScanMissing | warning | sem scan há 48h |

### Grafana Dashboard

**Arquivo**: `monitoring/grafana/dashboards/cicd-quality-gate-trends.json`
**UID**: `cicd002-quality-gate`
**Título**: `CICD-002: Code Quality Trends`

5 seções:
1. Quality Gate Overview (stat panels: status, coverage, bugs, vulns, smells)
2. Quality Gate Pass/Fail Over Time (timeseries por projeto + pass rate 7d)
3. Coverage Trends (timeseries com threshold em 80%)
4. Bugs and Vulnerabilities (bar charts por projeto)
5. Technical Debt — Code Smells (timeseries + total)
6. Pipeline Quality Gate History (CI job pass/fail + scan duration)

---

## Alternativas Consideradas

### Opção A: Manter "Sonar way" gate sem customização (Rejeitada)

**Prós**: Zero configuração
**Contras**:
- "Sonar way" tem coverage threshold de 80% mas sem thresholds para bugs/vulnerabilidades
- Não estabelece política corporativa clara
- Não é versionado em código

**Decisão**: Rejeitada. Gate corporativo versionado é obrigatório para compliance.

### Opção B: Coverage >= 90% (Rejeitada)

**Prós**: Cobertura mais alta = mais confiança
**Contras**:
- Leva a testes de baixa qualidade ("cobertura por coverage") — testes sem assertions reais
- Time de produto perde agilidade
- 90% é inatingível para projetos com UI complexa e código de integração

**Decisão**: 80% é o threshold correto. Prioridade é qualidade dos testes, não percentagem.

### Opção C: Thresholds diferentes por projeto (Rejeitada para primeira versão)

**Prós**: Flexibilidade para projetos em diferentes estágios
**Contras**:
- Overhead de governança: quem define e aprova thresholds por projeto?
- Fragmentação: sem padrão corporativo
- Implementação mais complexa

**Decisão**: Gate único "Production" para todos. Exceções via processo formal documentado.
Thresholds por projeto podem ser implementados em sprint futuro se necessário.

---

## Deployment Architecture

```
SonarQube (namespace: sonarqube)
  └── Quality Gate: "Production" [DEFAULT]
      ├── new_coverage >= 80%
      ├── new_bugs = 0
      ├── new_vulnerabilities = 0
      ├── new_code_smells <= 10
      └── new_security_hotspots_reviewed >= 80%

GitLab CI (namespace: staging-platform-gitlab)
  └── Template: sonarqube-quality-gate.gitlab-ci.yml
      └── Job: sonarqube-quality-gate [allow_failure: false]
          ├── sonar-scanner -Dsonar.qualitygate.wait=true
          ├── Artifact: quality-gate-results/
          └── Metrics → Prometheus PushGateway

Monitoring (namespace: monitoring)
  ├── PrometheusRule: cicd002-quality-gate-alerts
  │   └── 8 alertas por métrica individual
  └── Grafana Dashboard: cicd002-quality-gate
      └── 6 seções de visualização de trends
```

---

## Riscos e Mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|-------|--------------|---------|-----------|
| Projetos legados bloqueados por coverage < 80% | Alta | Médio | Processo de exclusão temporária com SLA |
| False positives em bugs/vulnerabilidades | Média | Baixo | Marcação "Won't Fix" no SonarQube UI |
| SonarQube indisponível bloqueia todos os merges | Baixa | Alto | Alert SonarQubeDown (CICD-001); SRE notificado |
| qualitygate.timeout atingido (scan lento) | Baixa | Médio | SONAR_TIMEOUT configurável por projeto |
| Developer produtividade afetada | Média | Médio | Developer guide, feedback claro, processo de exceção ágil |

---

## Implementação

### Fase 1 — Artefatos (2026-02-26) — Cluster OFFLINE

- [x] `scripts/sonarqube/configure-quality-gate.sh` — Script de automação
- [x] `domains/cicd-platform/infra/gitlab-ci/templates/sonarqube-quality-gate.gitlab-ci.yml`
- [x] `domains/observability/infra/alerts/sonarqube-quality-gate-prometheus-rules.yaml`
- [x] `monitoring/grafana/dashboards/cicd-quality-gate-trends.json`
- [x] `docs/adr/adr-082-sonarqube-quality-gate-policy.md` (este arquivo)
- [x] `docs/guides/quality-gate-compliance.md`
- [x] `docs/logbook/2026-02-26-cicd-002-quality-gate-planning.md`

### Fase 2 — Deploy (quando cluster UP)

```bash
# 1. Configurar Quality Gate no SonarQube
kubectl port-forward svc/sonarqube 9000:9000 -n sonarqube &
export SONAR_TOKEN=$(kubectl exec -n sonarqube deploy/sonarqube -- \
  curl -s -u admin:admin http://localhost:9000/api/user_tokens/generate \
  -d 'name=cicd002-setup&login=admin' | jq -r '.token')
./scripts/sonarqube/configure-quality-gate.sh

# 2. Validar configuração
./scripts/sonarqube/configure-quality-gate.sh --validate

# 3. Aplicar PrometheusRule
kubectl apply -f domains/observability/infra/alerts/sonarqube-quality-gate-prometheus-rules.yaml

# 4. Verificar alertas
kubectl get prometheusrule cicd002-quality-gate-alerts -n monitoring

# 5. Importar Grafana dashboard
# Grafana UI → Dashboards → Import → Upload JSON:
# monitoring/grafana/dashboards/cicd-quality-gate-trends.json

# 6. Adicionar template aos projetos
# Em .gitlab-ci.yml de cada projeto:
# include:
#   - project: 'platform/templates'
#     file: '/gitlab-ci/templates/sonarqube-quality-gate.gitlab-ci.yml'
```

### Fase 3 — Adoção (Sprint+1)

1. Onboarding dos 3 primeiros projetos piloto (baixo risco)
2. Acompanhar metrics por 2 semanas
3. Ajustar thresholds se necessário (com nova ADR se mudança significativa)
4. Rollout para todos os projetos da plataforma

---

## Consequências

### Positivas

- **Qualidade codificada**: Thresholds versionados em git, não configurados manualmente
- **Developer feedback**: Feedback específico sobre qual condição falhou e como corrigir
- **Observabilidade**: Dashboard dedicado com trends por projeto e métrica
- **Compliance**: Evidence trail de que cada MR passou no quality gate
- **Manutenibilidade**: Code smells gate previne acumulação de dívida técnica

### Negativas (aceitas)

- **Onboarding de projetos legados**: Projetos existentes precisarão de avaliação inicial
- **Curva de aprendizado**: Desenvolvedores precisam entender SonarQube UI e como corrigir issues
- **Dependência do SonarQube**: Se SonarQube estiver indisponível, merges ficam bloqueados

---

## Referências

- [SonarQube Quality Gates Documentation](https://docs.sonarqube.org/latest/user-guide/quality-gates/)
- [SonarQube Metrics API](https://docs.sonarqube.org/latest/user-guide/metric-definitions/)
- [Google Engineering Practices: Code Coverage](https://testing.googleblog.com/2020/08/code-coverage-best-practices.html)
- [Martin Fowler on Test Coverage](https://martinfowler.com/bliki/TestCoverage.html)
- [ADR-081: SAST/DAST Pipeline Enforcement](docs/adr/adr-081-sast-dast-pipeline-enforcement.md)
- [ADR-075: SonarQube Prometheus Exporter](docs/adr/adr-075-sonarqube-prometheus-exporter.md)
- [Developer Guide: Quality Gate Compliance](docs/guides/quality-gate-compliance.md)
- [CICD-001 Developer Guide](docs/CICD-001-DEVELOPER-GUIDE.md)

---

**Implementado por**: Platform SRE Team
**Data**: 2026-02-26
**Status**: Artefatos prontos — aguardando cluster UP para deploy
