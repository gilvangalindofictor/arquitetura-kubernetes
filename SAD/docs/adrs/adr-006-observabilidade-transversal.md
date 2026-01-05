# ADR-006: Observabilidade Transversal

## Status
Aceito

## Contexto
Observabilidade unificada necessária para troubleshooting, performance monitoring e alertas. OpenTelemetry como padrão garante interoperabilidade entre domínios.

## Decisão
Adotamos OpenTelemetry como padrão único para métricas, logs e traces, com Prometheus/Grafana/Loki/Tempo como backends.

## Consequências
- **Positivo**: Observabilidade completa, vendor-neutral, escalável
- **Negativo**: Complexidade de setup inicial
- **Riscos**: Overhead de instrumentação
- **Mitigação**: Auto-instrumentation onde possível

## Implementação
- **Collector**: OpenTelemetry Collector central
- **Métricas**: Prometheus + exporters obrigatórios
- **Logs**: Loki + fluent-bit
- **Traces**: Tempo + OTEL SDKs
- **Visualização**: Grafana dashboards padronizados

## Padrões por Domínio
- **Métricas**: Golden Signals (latency, traffic, errors, saturation)
- **Logs**: Structured logging obrigatório
- **Traces**: Service-to-service spans

## Validação
- Coverage de métricas >95%
- Alertas funcionais
- Dashboards operacionais

## Referências
- [OpenTelemetry](https://opentelemetry.io/)
- [Prometheus Best Practices](https://prometheus.io/docs/practices/)

Data: 2025-12-30</content>
<parameter name="filePath">\\wsl.localhost\Ubuntu\home\gilvangalindo\projects\Arquitetura\Kubernetes\SAD\docs\adrs\adr-006-observabilidade-transversal.md