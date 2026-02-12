# Redis — trechos pinados

version: SpotaHome-operator v3.3.0 (operator, chart v3.3.0)
server: operator-managed (Redis server image tag is not set in the CR; operator/chart defaults apply — module forces `image.tag=latest`)
source: https://redis.io/
link: https://github.com/spotahome/redis-operator/releases
releases_page: https://github.com/spotahome/redis-operator/releases

Trechos úteis:

- Backup (dump): `redis-cli BGSAVE` then copy `dump.rdb` from pod
- Restore: `redis-cli --raw RESTORE <key> <ttl> <serialized-value>` (verify operator docs)
- Operator: SpotaHome Redis Operator v3.3.0 referenced in `domains/data-services/docs/STAGING-BACKUP-STRATEGY.md`

Referências locais (Data Services):
- `domains/data-services/docs/TERRAFORM-SOURCE-OF-TRUTH.md`
- `domains/data-services/docs/STAGING-BACKUP-STRATEGY.md`
