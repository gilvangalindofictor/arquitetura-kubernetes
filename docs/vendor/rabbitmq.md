# RabbitMQ — trechos pinados

operator_version: 2.19.0
server_version: 3.13-management
source: https://www.rabbitmq.com/
link: https://github.com/rabbitmq/cluster-operator/releases
releases_page: https://github.com/rabbitmq/cluster-operator/releases

Trechos úteis:

- Export definitions: `rabbitmqctl export_definitions /tmp/definitions.json`
- Backup flow: export_definitions → kubectl cp → `aws s3 cp` to backup bucket
- Operator: RabbitMQ Cluster Operator 2.19.0 (modules/rabbitmq/main.tf)

Referências locais (Data Services):
- `domains/data-services/docs/TERRAFORM-SOURCE-OF-TRUTH.md`
- `domains/data-services/docs/VERSIONS-AND-FEATURES.md`
