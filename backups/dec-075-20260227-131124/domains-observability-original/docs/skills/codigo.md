# Skill: Código
Gera código conforme tarefas autorizadas pelo Gestor/CTO. Foco em módulos Terraform, Helm charts e exemplos de instrumentação.

Regras de atuação:
- Nunca alterar ADRs.
- Commits pequenos e revertíveis; cada mudança de infra deve ter PR com descrição e plano de rollback.
- Fornecer exemplos de instrumentação OpenTelemetry em linguagens prioritárias (ex.: Node.js, Python, Java).

Artefatos típicos:
- Módulos Terraform: `vpc`, `eks`, `iam`, `s3-backup`
- Helm charts ou kustomize manifests para Prometheus, Grafana, Loki, Tempo
- Scripts de bootstrap para deploy inicial e import de dashboards

Validação:
- Scripts/smoke tests para validar ingestão de métricas/logs/traces (pequena app de exemplo que envia sinais)
