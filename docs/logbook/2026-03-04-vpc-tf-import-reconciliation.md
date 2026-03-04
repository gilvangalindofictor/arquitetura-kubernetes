# Logbook: VPC Terraform Import Reconciliation

**Data:** 2026-03-04
**Executor:** Especialista Terraform/AWS (Claude Code)
**Objetivo:** Importar VPC fictor-vpc existente na AWS para o estado Terraform (engenharia reversa)

---

## Contexto

A VPC `fictor-vpc` foi reverse-engineered em 2026-01-23 e os módulos Terraform criados em:
`docs/plan/aws-execution/vpc-reverse-engineered/terraform/`

Este logbook documenta o `terraform import` de todos os recursos para sincronizar o estado TF com a infraestrutura AWS real.

---

## Step 1: Autenticação AWS SSO

```
Profile: k8s-platform-prod
Account: 891377105802
ARN: arn:aws:sts::891377105802:assumed-role/AWSReservedSSO_AdministratorAccess_fe8afab53a6f0582/gilvan.galindo
Status: OK
```

---

## Step 2: Resource IDs Descobertos via AWS CLI

| Recurso | ID AWS | Detalhes |
|---------|--------|---------|
| VPC | `vpc-0b1396a59c417c1f0` | fictor-vpc, 10.0.0.0/16 |
| Internet Gateway | `igw-0a8a1ad9cfddd037e` | fictor-igw |
| Subnet public1-us-east-1a | `subnet-0b5e0cae5658ea993` | 10.0.0.0/20 |
| Subnet public2-us-east-1b | `subnet-07dca8ceb9882ba66` | 10.0.16.0/20 |
| Subnet private1-us-east-1a | `subnet-0472ab28726cdf745` | 10.0.128.0/20 |
| Subnet private2-us-east-1b | `subnet-0288a67cd352effa7` | 10.0.144.0/20 |
| NAT GW public1 | `nat-03512e5ee0642dcf2` | subnet-0b5e0cae5658ea993 |
| NAT GW public2 | `nat-0be570edfb2eff63e` | subnet-07dca8ceb9882ba66 |
| EIP nat public1 | `eipalloc-0a6d1fe3ec8ba217e` | fictor-eip-us-east-1a |
| EIP nat public2 | `eipalloc-01ff089c963971903` | fictor-eip-us-east-1b |
| Route Table public | `rtb-08be102870fb64de7` | fictor-rtb-public |
| Route Table private1-us-east-1a | `rtb-09656e8e3e2f44c62` | fictor-rtb-private1-us-east-1a |
| Route Table private2-us-east-1b | `rtb-00c7af803ee93ac2c` | fictor-rtb-private2-us-east-1b |
| RTB Assoc public1-subnet | `rtbassoc-0abca76ad0a268021` | subnet-0b5e0cae5658ea993 → rtb-08be102870fb64de7 |
| RTB Assoc public2-subnet | `rtbassoc-0d9e448d87c5f4f44` | subnet-07dca8ceb9882ba66 → rtb-08be102870fb64de7 |
| RTB Assoc private1-subnet | `rtbassoc-0eec0dd9ef7048acc` | subnet-0472ab28726cdf745 → rtb-09656e8e3e2f44c62 |
| RTB Assoc private2-subnet | `rtbassoc-06b7e63e4a61aee17` | subnet-0288a67cd352effa7 → rtb-00c7af803ee93ac2c |

**Nota:** A route table `rtb-0e8f3e31c8360f2ef` (sem nome, associação sem subnet_id) é a **main/default** do VPC — não gerenciada via módulo TF.

---

## Step 3: Fix Aplicado em main.tf

Durante o import, foi identificado que o módulo `route-tables` usa `for_each` com chaves derivadas de outputs de outros módulos (unknown at import time). Também `nat_gateways` referenciava `module.subnets.subnet_ids` que ainda não estava no estado.

**Solução:** Hardcoded os IDs estáticos reais diretamente em `main.tf` para permitir o import:
- `subnet_ids` nas route tables → IDs reais das subnets
- `subnet_id` nos nat_gateways → IDs reais das subnets públicas
- `gateway_id` no route public → `igw-0a8a1ad9cfddd037e`
- `nat_gateway_id` nas routes privadas → IDs reais dos NAT GWs
- `vpc_id` em todos os módulos filhos → `vpc-0b1396a59c417c1f0`

---

## Step 4: Terraform Imports Executados

| Recurso TF | ID Importado | Status |
|-----------|-------------|--------|
| `module.vpc.aws_vpc.main` | `vpc-0b1396a59c417c1f0` | OK |
| `module.internet_gateway.aws_internet_gateway.igw` | `igw-0a8a1ad9cfddd037e` | OK |
| `module.subnets.aws_subnet.subnets["0"]` | `subnet-0b5e0cae5658ea993` | OK |
| `module.subnets.aws_subnet.subnets["1"]` | `subnet-07dca8ceb9882ba66` | OK |
| `module.subnets.aws_subnet.subnets["2"]` | `subnet-0472ab28726cdf745` | OK |
| `module.subnets.aws_subnet.subnets["3"]` | `subnet-0288a67cd352effa7` | OK |
| `module.nat_gateways.aws_eip.nat_eip["0"]` | `eipalloc-0a6d1fe3ec8ba217e` | OK |
| `module.nat_gateways.aws_eip.nat_eip["1"]` | `eipalloc-01ff089c963971903` | OK |
| `module.nat_gateways.aws_nat_gateway.nat["0"]` | `nat-03512e5ee0642dcf2` | OK |
| `module.nat_gateways.aws_nat_gateway.nat["1"]` | `nat-0be570edfb2eff63e` | OK |
| `module.route_tables.aws_route_table.rtb["0"]` | `rtb-08be102870fb64de7` | OK |
| `module.route_tables.aws_route_table.rtb["1"]` | `rtb-09656e8e3e2f44c62` | OK |
| `module.route_tables.aws_route_table.rtb["2"]` | `rtb-00c7af803ee93ac2c` | OK |
| `module.route_tables.aws_route_table_association.assoc["0-subnet-0b5e0cae5658ea993"]` | `subnet-0b5e0cae5658ea993/rtb-08be102870fb64de7` | OK |
| `module.route_tables.aws_route_table_association.assoc["0-subnet-07dca8ceb9882ba66"]` | `subnet-07dca8ceb9882ba66/rtb-08be102870fb64de7` | OK |
| `module.route_tables.aws_route_table_association.assoc["1-subnet-0472ab28726cdf745"]` | `subnet-0472ab28726cdf745/rtb-09656e8e3e2f44c62` | OK |
| `module.route_tables.aws_route_table_association.assoc["2-subnet-0288a67cd352effa7"]` | `subnet-0288a67cd352effa7/rtb-00c7af803ee93ac2c` | OK |

**Total:** 17 recursos importados com sucesso | 0 falhas

---

## Step 5: Terraform Plan — Resultado Inicial

**Comando:** `terraform plan -out=vpc-reconciliation.tfplan`

```
Plan: 0 to add, 6 to change, 0 to destroy.
```

### Drift Inicial Detectado (tag-only) — RESOLVIDO ✅

**Drift NÃO CRÍTICO** — apenas tags ausentes no código TF:

| Recurso | Drift | Tipo |
|---------|-------|------|
| `aws_eip.nat_eip["0"]` (eipalloc-0a6d1fe3ec8ba217e) | Tag `Name=fictor-eip-us-east-1a` presente na AWS, ausente no TF | Tag drift |
| `aws_eip.nat_eip["1"]` (eipalloc-01ff089c963971903) | Tag `Name=fictor-eip-us-east-1b` presente na AWS, ausente no TF | Tag drift |
| `aws_subnet.subnets["0"]` (subnet-0b5e0cae5658ea993) | Tags `kubernetes.io/cluster/k8s-platform-prod=shared` e `kubernetes.io/role/elb=1` | EKS-managed tags |
| `aws_subnet.subnets["1"]` (subnet-07dca8ceb9882ba66) | Tags `kubernetes.io/cluster/k8s-platform-prod=shared` e `kubernetes.io/role/elb=1` | EKS-managed tags |
| `aws_subnet.subnets["2"]` (subnet-0472ab28726cdf745) | Tags `kubernetes.io/cluster/k8s-platform-prod=shared` e `kubernetes.io/role/internal-elb=1` | EKS-managed tags |
| `aws_subnet.subnets["3"]` (subnet-0288a67cd352effa7) | Tags `kubernetes.io/cluster/k8s-platform-prod=shared` e `kubernetes.io/role/internal-elb=1` | EKS-managed tags |

---

## Step 6: Fix de Drift — Módulos Corrigidos

**Root cause:** Módulos TF não contemplavam as tags EKS-managed nas subnets e a tag `Name` nos EIPs.

### Fix 1: `modules/nat-gateways/main.tf`

Adicionado campo `eip_name` (optional) ao tipo do objeto `nat_gateways` e tag condicional no recurso `aws_eip`:

```hcl
variable "nat_gateways" {
  type = list(object({
    subnet_id = string
    name      = string
    eip_name  = optional(string, "")
  }))
}

resource "aws_eip" "nat_eip" {
  for_each = { for idx, ngw in var.nat_gateways : idx => ngw }
  domain   = "vpc"

  tags = each.value.eip_name != "" ? {
    Name = each.value.eip_name
  } : {}
}
```

### Fix 2: `modules/subnets/main.tf`

Adicionado campo `extra_tags` (optional map) e merge no bloco `tags`:

```hcl
variable "subnets" {
  type = list(object({
    cidr_block        = string
    availability_zone = string
    map_public_ip     = bool
    name              = string
    extra_tags        = optional(map(string), {})
  }))
}

resource "aws_subnet" "subnets" {
  ...
  tags = merge(
    { Name = each.value.name },
    each.value.extra_tags
  )
}
```

### Fix 3: `main.tf` — Valores para EIPs e Subnets

- `nat_gateways`: adicionado `eip_name = "fictor-eip-us-east-1a/1b"` em cada entrada
- `subnets`: adicionado `extra_tags` com as tags EKS corretas por tipo (public: `elb=1`, private: `internal-elb=1`)

---

## Step 7: Terraform Plan Final — ZERO DRIFT ✅

**Comando:** `terraform plan -out=vpc-import.tfplan`

```
No changes. Your infrastructure matches the configuration.
```

**Resultado:** 0 to add, 0 to change, 0 to destroy.

### Configurações Verificadas — ZERO DRIFT

| Configuração | Status |
|-------------|--------|
| VPC CIDR (10.0.0.0/16) | ZERO DRIFT |
| Subnet CIDRs | ZERO DRIFT |
| Availability Zones | ZERO DRIFT |
| Route table entries (0.0.0.0/0) | ZERO DRIFT |
| NAT Gateway associations | ZERO DRIFT |
| IGW attachment | ZERO DRIFT |
| Subnet-RTB associations | ZERO DRIFT |
| EIP Name tags | ZERO DRIFT (corrigido) |
| EKS Kubernetes subnet tags | ZERO DRIFT (corrigido) |

---

## Resumo Final

- **Import:** 17/17 recursos — 100% sucesso
- **terraform plan:** No changes (zero-drift)
- **Drift inicial:** 6 recursos (tag-only, todos corrigidos nos módulos)
- **Status:** COMPLETO ✅

---

## Arquivos Modificados

- `docs/plan/aws-execution/vpc-reverse-engineered/terraform/main.tf` — IDs hardcoded + eip_name + extra_tags EKS
- `docs/plan/aws-execution/vpc-reverse-engineered/terraform/modules/nat-gateways/main.tf` — suporte a eip_name + tags EIP
- `docs/plan/aws-execution/vpc-reverse-engineered/terraform/modules/subnets/main.tf` — suporte a extra_tags via merge()
- `docs/plan/aws-execution/vpc-reverse-engineered/terraform/terraform.tfstate` — 17 recursos importados
- `docs/plan/aws-execution/vpc-reverse-engineered/terraform/vpc-import.tfplan` — plano zero-drift salvo
