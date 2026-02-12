# AWS — trechos pinados


version: ~>5.0 (provider)
source: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
link: https://registry.terraform.io/providers/hashicorp/aws/latest/docs

Trechos úteis:


- CLI: `aws sts get-caller-identity` — confirmar credenciais
- RDS status: `aws rds describe-db-instances --db-instance-identifier <id>`
- ECS: `aws ecs describe-services --cluster <c> --services <s>`

Limits & pricing: referenciar pricing API/version quando necessário.
