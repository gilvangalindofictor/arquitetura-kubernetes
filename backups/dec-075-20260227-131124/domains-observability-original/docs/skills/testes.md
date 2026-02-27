# Skill: Testes
Define estratégias de testes, cenários e critérios de cobertura para a plataforma de observabilidade.

Abordagem:
- Testes de integração: validar que OpenTelemetry Collector recebe e encaminha sinais para Prometheus/Loki/Tempo.
- Testes de smoke: deploy PoC + app exemplo que gera tráfego e sinais; verificar dashboards e alertas.
- Testes de carga (opcionais): simular volume de métricas/logs para estimar custos e performance.

Checks mínimos:
- Métricas básicas aparecem no Prometheus após 1-2 minutos.
- Logs enviados via Loki são pesquisáveis por labels.
- Traces aparecem no Tempo/Jaeger com parent/child corretos.
