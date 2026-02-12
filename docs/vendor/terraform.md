# Terraform — trechos pinados


version: 1.14
source: https://www.terraform.io/
link: https://developer.hashicorp.com/terraform
providers:
	- aws: https://registry.terraform.io/providers/hashicorp/aws/latest
	- kubernetes: https://registry.terraform.io/providers/hashicorp/kubernetes/latest
	- helm: https://registry.terraform.io/providers/hashicorp/helm/latest

Trechos úteis:


- Init/backend: `terraform init -backend-config="bucket=..."` (ver 1.x backend docs)
- Plan: `terraform plan -out=tfplan` — em 1.x, `-out` produz plan legível pelo `apply`.
- Apply background: `terraform apply -auto-approve tfplan`

Locking: DynamoDB table recommended for remote state locking in AWS (ver provider aws vX.Y).

Breaking changes: registrar aqui mudanças relevantes após upgrade de major.
