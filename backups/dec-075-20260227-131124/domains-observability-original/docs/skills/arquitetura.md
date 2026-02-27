# Skill: Arquitetura
Define componentes, padrões, modelos e estratégias para a plataforma de observabilidade.

Responsabilidades:
- Propor topologia (centralizada vs por-ambiente) — inicialmente decisão em mesa técnica.
- Projetar módulos Terraform reutilizáveis e parâmetros para portabilidade.
- Definir limites de cardinalidade e práticas para evitar explosão de métricas.
- Selecionar mecanismos de armazenamento de longo prazo (S3 + Thanos/Prometheus remote write se aplicável).

Padrões sugeridos:
- OpenTelemetry Collector como padrão de ingestão/roteamento de sinais.
- Prometheus Operator para gerenciamento de métricas em Kubernetes.
- Grafana como unico ponto de visualização (folders por ambiente/projeto).
- Loki para logs indexados por label de baixa cardinalidade; usar S3 para retenção de objetos.

Regra: Sempre gerar um ADR ao propor mudanças estruturais significativas.
