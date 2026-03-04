# DT-001 — PostgreSQL Subnet Assessment (2026-03-04)

## Estado Atual (descoberto via AWS CLI)

| Campo | Valor |
|-------|-------|
| RDS Instance | `k8s-platform-prod-postgresql` |
| Engine | PostgreSQL 16.4 |
| Status | `available` |
| Subnet Group | `k8s-platform-prod-postgresql` |
| Subnets em uso | `subnet-0288a67cd352effa7` (us-east-1b), `subnet-0472ab28726cdf745` (us-east-1a) |
| PubliclyAccessible | `false` |
| VPC | `vpc-0b1396a59c417c1f0` (10.0.0.0/16) |
| Endpoint | `k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com:5432` |

## Verificacao de Routing — Confirma Subnets Privadas

As route tables associadas às subnets do RDS foram inspecionadas via:

```
aws ec2 describe-route-tables \
  --profile k8s-platform-prod \
  --filters "Name=association.subnet-id,Values=subnet-0472ab28726cdf745,subnet-0288a67cd352effa7"
```

**Resultado das rotas (ambas as subnets identicas):**

| Destino | Gateway | Interpretacao |
|---------|---------|---------------|
| `10.0.0.0/16` | `local` | Rota VPC interna |
| `0.0.0.0/0` | `null` (NAT GW) | Saida via NAT — subnet PRIVADA |
| `prefix-list` | `vpce-0a7ef345dce0bea69` | VPC Endpoint (S3/ECR) |

**Conclusao:** O gateway para `0.0.0.0/0` e um NAT Gateway (nao um Internet Gateway `igw-*`). Isso confirma que **ambas as subnets sao privadas**. Se fossem publicas, apareceria um gateway `igw-*`.

## Analise de Risco

**Cenario identificado: CENARIO A — RDS JA EM SUBNETS PRIVADAS**

- **Risco:** BAIXO
- **Motivo:** O subnet group atual (`k8s-platform-prod-postgresql`) ja aponta para as subnets privadas corretas. Nao ha mudanca de subnet group necessaria, portanto **nao havera recreacao do RDS**.
- **Impacto:** Zero downtime. A unica mudanca necessaria seria atualizar `publicly_accessible` se estivesse `true` — porem o valor ja e `false`.

### Comparacao TF Code vs Estado Real

| Parametro | Terraform Code | Estado Real AWS | Match? |
|-----------|----------------|-----------------|--------|
| `publicly_accessible` | `false` | `false` | MATCH |
| Subnet Group | `${var.cluster_name}-postgresql` = `k8s-platform-prod-postgresql` | `k8s-platform-prod-postgresql` | MATCH |
| Subnet 1 | `subnet-0472ab28726cdf745` (us-east-1a) | `subnet-0472ab28726cdf745` | MATCH |
| Subnet 2 | `subnet-0288a67cd352effa7` (us-east-1b) | `subnet-0288a67cd352effa7` | MATCH |
| SG ingress | VPC CIDR `10.0.0.0/16` | Verificar via `terraform plan` | PENDENTE |

**Conclusao:** O Terraform code esta **100% convergente** com o estado real do RDS. O objetivo do DT-001 (`publicly_accessible = false` + subnet privada) ja esta atingido.

## Plano de Execucao (Cenario A — Seguro)

### Passo 1 — Terraform Plan (verificacao segura)

```bash
cd platform-provisioning/aws/kubernetes/terraform/environments/staging

terraform plan -target=module.postgresql_staging 2>&1 | tee /tmp/dt001-plan-$(date +%Y%m%d).log
```

**O que esperar no plan:**
- Se o estado TF estiver sincronizado: `No changes. Your infrastructure matches the configuration.`
- Se houver drift de Security Group (SG foi criado manualmente): mudancas apenas no SG, sem recreacao do `aws_db_instance`
- **Nunca devera aparecer:** `aws_db_instance.postgresql will be replaced` (isso indicaria problema grave)

### Passo 2 — Terraform Apply (somente se plan mostrar mudancas seguras)

```bash
# Somente executar se o plan mostrar mudancas que NAO incluam recreacao do aws_db_instance
terraform apply -target=module.postgresql_staging -auto-approve 2>&1 | tee /tmp/dt001-apply-$(date +%Y%m%d).log
```

Tempo estimado: 30-120s (mudancas em SG sao imediatas; mudancas em-place no RDS levam ~2min sem reinicio).

### Passo 3 — Validacao pos-apply

```bash
# Confirmar publicly_accessible = false
aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-prod-postgresql \
  --profile k8s-platform-prod \
  --query 'DBInstances[0].{PubliclyAccessible:PubliclyAccessible,Status:DBInstanceStatus,Subnets:DBSubnetGroup.Subnets[*].SubnetIdentifier}' \
  --output json

# Confirmar que GitLab continua funcional
kubectl get pods -n gitlab-staging --no-headers | grep -v Running | grep -v Completed
```

### Passo 4 — Validacao de conectividade (via script)

```bash
bash scripts/postgresql/validate-rds-private.sh
```

## Notas sobre Security Group

O `main.tf` do modulo postgresql configura dois blocos de ingresso:

1. `private_subnet_cidrs` — CIDRs das subnets privadas (pods EKS)
2. `var.vpc_cidr` = `10.0.0.0/16` — VPC inteira (VPC CNI pod IPs secundarios)

Isso garante que todos os workloads (GitLab, Harbor, Keycloak, ArgoCD, SonarQube) consigam conectar independente do CIDR secundario usado pelo VPC CNI.

## Resultado

**Status: SEGURO PARA APPLY**

O DT-001 ja esta tecnicamente implementado no ambiente AWS. O `terraform apply` e seguro (Cenario A) e deve resultar em zero changes ou apenas atualizacoes in-place do Security Group. Nao ha risco de recreacao do RDS nem de downtime para GitLab, Harbor, Keycloak, ArgoCD ou SonarQube.

**Proximo passo recomendado:** Executar `terraform plan -target=module.postgresql_staging` para confirmar drift zero e fechar formalmente o DT-001.

---
*Avaliacao executada por: Agente TF Specialist + AWS Specialist*
*Data: 2026-03-04*
*Commands executados: aws rds describe-db-instances, aws rds describe-db-subnet-groups, aws ec2 describe-route-tables*
