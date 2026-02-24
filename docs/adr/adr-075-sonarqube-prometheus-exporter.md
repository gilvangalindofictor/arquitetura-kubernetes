# ADR-075: SonarQube Prometheus Native Metrics Integration (GAP-008)

**Status:** Accepted — Implemented  
**Data:** 2026-02-24  
**Deciders:** Platform Team  
**Tags:** monitoring, sonarqube, prometheus, gap-008  
**Implementado:** kubectl apply — ServiceMonitor live, target UP, 21 métricas coletadas

---

## Contexto

O SonarQube estava operacional no cluster (namespace `sonarqube`) com SSO via Keycloak (SAML 2.0) e persistência no RDS PostgreSQL, porém **sem exposição de métricas ao Prometheus**. Isso criava um gap de observabilidade (GAP-008): sem visibilidade de qualidade de código, saúde do Compute Engine, Elasticsearch e integrações no Grafana unificado.

### Discovery During Implementation

Durante a execução, identificou-se que o **SonarQube 10.3+ possui endpoint Prometheus nativo** em `/api/monitoring/metrics`, eliminando a necessidade de exporter externo. O endpoint já estava funcional com passcode `SONAR_WEB_SYSTEMPASSCODE` configurado via Helm.

### Opções Consideradas

| Opção | Descrição | Prós | Contras | Decisão |
|-------|-----------|------|---------|---------|
| A | Community exporter `dmeiners88/sonarqube-prometheus-exporter` | Simples | Exporter extra, imagem `latest`, requer token de usuário admin | Descartada |
| **B** | **SonarQube 10.3+ native `/api/monitoring/metrics`** | **Zero footprint extra, sem credenciais admin, secret já existe** | Métricas de sistema (não por projeto) | **ESCOLHIDA** |
| C | Custom exporter Python/Go | Controle total | Manutenção adicional | Descartada |

## Decisão

**Opção B aprovada:** ServiceMonitor apontando para o endpoint nativo `/api/monitoring/metrics` do SonarQube 10.3, usando o secret `sonarqube-sonarqube-monitoring-passcode` já existente no namespace.

**Rationale:**
- Zero workloads adicionais criados (sem deployment extra, sem pod)
- Zero novas credenciais necessárias (secret já existe, gerenciado pelo Helm)
- Prometheus Operator configurado com `serviceMonitorSelector: {}` — aceita todos os namespaces
- Service `sonarqube-sonarqube` já expõe port `http:9000` — mesmo service, novo path
- Implementação imediata: 1 manifesto, sem bloqueio de token admin

## Arquitetura

```
SonarQube Pod (10.3.0.82913)
  └── /api/monitoring/metrics (Prometheus format)
        ↑ Bearer Token: SONAR_WEB_SYSTEMPASSCODE
              ↑
        sonarqube-sonarqube-monitoring-passcode (Secret, Helm-managed)
              ↑
        ServiceMonitor: sonarqube-native-metrics
              ↓ scrape 30s
        Prometheus (monitoring namespace)
              ↓
        Grafana Dashboard
```

## Componentes

| Recurso | Kind | Namespace | Arquivo | Ação |
|---------|------|-----------|---------|------|
| sonarqube-native-metrics | ServiceMonitor | sonarqube | service-monitor-native.yaml | `kubectl apply` ✅ |
| sonarqube-sonarqube-monitoring-passcode | Secret | sonarqube | (Helm-managed, pré-existente) | Referenciado |
| sonarqube-sonarqube | Service | sonarqube | (Helm-managed, pré-existente) | Referenciado |

## Métricas Coletadas (21 total)

| Métrica | Descrição | Valor Observado |
|---------|-----------|-----------------|
| `sonarqube_web_uptime_minutes` | Uptime da instância | 659 min |
| `sonarqube_health_web_status` | Web process up/down | 1 (UP) |
| `sonarqube_health_compute_engine_status` | Compute Engine up/down | 1 (UP) |
| `sonarqube_health_elasticsearch_status` | Elasticsearch up/down | 1 (UP) |
| `sonarqube_elasticsearch_disk_space_total_bytes` | Disco total | 21 GB |
| `sonarqube_elasticsearch_disk_space_free_bytes` | Disco livre | 20 GB |
| `sonarqube_compute_engine_pending_tasks_total` | Tasks CE pendentes | 0 |
| `sonarqube_license_number_of_lines_analyzed_total` | LOC analisadas | 0 |
| `sonarqube_health_integration_gitlab_status` | GitLab integration | 1 (OK) |
| `sonarqube_health_integration_github_status` | GitHub integration | 0 |
| `sonarqube_number_of_connected_sonarlint_clients` | SonarLint clients | 0 |
| + 10 métricas adicionais | CE tasks, license, etc. | — |

## Validação Executada

```bash
# Target discoverd by Prometheus:
# Health: up | LastScrape: 2026-02-24T21:33:02Z
# Job: sonarqube-sonarqube | Namespace: sonarqube
# ScrapeURL: http://10.0.137.187:9000/api/monitoring/metrics

# Query confirmada:
# sonarqube_web_uptime_minutes = 659
# Total metrics: 21
```

## Segurança

- Passcode armazenado em Secret Kubernetes gerenciado pelo Helm chart
- Bearer token usado apenas internamente (scrape dentro do cluster)
- Endpoint `/api/monitoring/metrics` não exposto externamente (apenas ClusterIP)
- Nenhuma credencial admin necessária

## Próximos Passos (Recomendados)

1. **Hardening do passcode:** Alterar `SONAR_WEB_SYSTEMPASSCODE` de `define_it` para valor seguro via ESO/Vault
2. **Grafana Dashboard:** Criar dashboard com métricas de saúde do SonarQube
3. **Alertas:** PrometheusRule para `sonarqube_health_web_status == 0` e `sonarqube_health_compute_engine_status == 0`

## Impacto

- **Observabilidade:** Fecha GAP-008 — 21 métricas de saúde disponíveis no Prometheus/Grafana
- **Custo:** R$ 0/ano (zero recursos adicionais criados)
- **Compliance:** Alinha com estratégia de monitoring da plataforma (Prometheus Operator + ServiceMonitor)

## Referências

- GAP-008 (Monitoring Gap — SonarQube)
- ADR-003 (Secrets Management Strategy — ESO + Vault)
- [SonarQube 10.3 Monitoring API](https://docs.sonarsource.com/sonarqube/latest/instance-administration/monitoring/prometheus-exporter/)
