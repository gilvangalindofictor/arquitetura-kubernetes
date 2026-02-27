# Configuração MCP

Ferramentas disponíveis:
- `terraform` (IaC) — módulos para VPC, EKS, S3, IAM
- `awscli` — operações AWS ad-hoc e scripting
- `kubectl` / `helm` — deploys em clusters
- `grafana-cli` / dashboards import
- `prometheus` / `prometheus-operator` / `alertmanager`
- `loki` / `tempo` / `opentelemetry-collector`
- `s3` (AWS) para retenção e backups

Permissões:
- Executor deve operar com IAM role temporária com escopo mínimo para aplicar mudanças aprovadas.
- Separar contas/roles para ambientes quando decidido pela mesa técnica.

Restrições:
- Nenhuma alteração sem PR e aprovação do Gestor/Arquiteto.
- Mudanças de produção exigem checklist de rollback e janela aprovada.

Observação:
- Apesar do uso da AWS, toda automação deve ser escrita com portabilidade em mente (módulos Terraform parametricamente agnósticos quando possível).
