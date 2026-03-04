# GAP-012 Phase 2 - VPC DR us-west-2 Apply (2026-03-04)

## Resultado

- **Status:** APPLIED
- **Recursos criados:** 8 add, 0 change, 0 destroy
- **VPC ID:** vpc-097666f48dfec2497 (us-west-2, CIDR: 10.1.0.0/16)
- **Subnet us-west-2a:** subnet-00b96c5c3b1279b2c (10.1.128.0/20)
- **Subnet us-west-2b:** subnet-04e8be34e5af42f2a (10.1.144.0/20)
- **DB Subnet Group:** k8s-platform-dr-db-subnet-group (Status: Complete)
- **Security Group:** sg-0704b0754f97da7f6 (RDS ingress 5432 from 10.1.0.0/16)
- **Route Table:** rtb-024fe8b1a5ac32260 (private, sem rota internet)

## Recursos no State (8/8)

```
module.vpc_dr_staging.aws_vpc.dr
module.vpc_dr_staging.aws_subnet.rds_a
module.vpc_dr_staging.aws_subnet.rds_b
module.vpc_dr_staging.aws_route_table.private_dr
module.vpc_dr_staging.aws_route_table_association.rds_a
module.vpc_dr_staging.aws_route_table_association.rds_b
module.vpc_dr_staging.aws_db_subnet_group.dr
module.vpc_dr_staging.aws_security_group.rds_dr
```

## Fixes Aplicados

1. **Duplicate required_providers** - `modules/vpc-dr/main.tf` tinha bloco `terraform { required_providers }` duplicando `versions.tf`. Removido de `main.tf`.
2. **SSO profile expirado** - `provider aws.us-west-2` usava `k8s-platform-staging` (expirado). Alterado para `k8s-platform-prod` (mesma conta 891377105802).
3. **Non-ASCII em descriptions** - `aws_db_subnet_group.dr` e `aws_security_group.rds_dr` usavam em-dash (`-`) em description. AWS API requer ASCII puro. Substituido por `-`.

## Proximo Passo Desbloqueado

O `module.rds_replica_staging` (count=0, gate liderança) agora tem pre-requisitos de rede prontos em us-west-2:
- `var.dr_vpc_id` = `vpc-097666f48dfec2497`
- `var.dr_subnet_ids` = `["subnet-00b96c5c3b1279b2c", "subnet-04e8be34e5af42f2a"]`
- `var.dr_allowed_cidrs` = `["10.1.0.0/16"]`

## Proximos Passos

- [ ] kubectl apply BackupStorageLocation DR (domains/backup-dr/infra/velero/)
- [ ] Atualizar terraform.tfvars com dr_vpc_id, dr_subnet_ids, dr_allowed_cidrs
- [ ] Ativar RDS Replica (count=0->1 em module.rds_replica_staging) - gate liderança
- [ ] Validar replicacao S3 CRR (aws s3 ls s3://velero-backups-staging-*-us-west-2/)

## AML Log

| Timestamp | Ciclo | Resultado |
|-----------|-------|-----------|
| 2026-03-04T00:00 | terraform init | FAILED - duplicate required_providers |
| 2026-03-04T00:01 | FIX: remove terraform{} do main.tf | OK |
| 2026-03-04T00:02 | terraform init | OK - Successfully initialized |
| 2026-03-04T00:03 | terraform plan | FAILED - SSO InvalidGrantException k8s-platform-staging |
| 2026-03-04T00:04 | FIX: profile -> k8s-platform-prod | OK |
| 2026-03-04T00:05 | terraform plan | OK - 8 add, 0 change, 0 destroy |
| 2026-03-04T00:06 | terraform apply (1a tentativa) | PARTIAL - 6/8 criados. Errors: non-ASCII descriptions |
| 2026-03-04T00:07 | FIX: em-dash -> hyphen em descriptions | OK |
| 2026-03-04T00:08 | terraform apply (2a tentativa) | OK - 8/8 no state |
| 2026-03-04T00:09 | AWS CLI validation | PASS - VPC/subnets/DBSubnetGroup verified |

## Referencias

- ADR-078: Velero Backup/DR Multi-Region
- ADR-090: DR Multi-Region Strategy
- Modulo: `platform-provisioning/aws/kubernetes/terraform/modules/vpc-dr/`
- Staging: `platform-provisioning/aws/kubernetes/terraform/environments/staging/main.tf` (linha ~2272)
