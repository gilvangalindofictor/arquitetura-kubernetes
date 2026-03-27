# =============================================================================
# GAP-CONF-016 (P2): EKS Cluster — Terraform Import Block
# =============================================================================
# O cluster EKS "k8s-platform-prod" foi criado fora do Terraform (bootstrapped
# via AWS CLI / Marco0). Atualmente, o TF state nao possui o recurso
# aws_eks_cluster, gerando:
#   - Impossibilidade de gerenciar access_config, logging, addons nativamente
#   - Dependencia de null_resource workarounds (ex: eks_auth_mode_api_and_configmap)
#   - Drift detection ausente para configuracoes do control plane
#
# Solucao: Usar import block (Terraform 1.5+) para importar o cluster existente
# para o state SEM destrui-lo ou recria-lo.
#
# PROCEDIMENTO DE IMPORT:
#   1. Descomentar o bloco "import" e o "resource" abaixo
#   2. Executar: terraform plan (verificar que import sera realizado, sem destroy)
#   3. Revisar o plan — deve mostrar "will be imported" e possiveis updates in-place
#   4. Executar: terraform apply (importa o cluster para o state)
#   5. Apos apply, o null_resource.eks_auth_mode_api_and_configmap pode ser removido
#      (a config authentication_mode passa a ser gerenciada nativamente)
#
# COMANDO ALTERNATIVO (import manual pre-1.5):
#   terraform import aws_eks_cluster.main k8s-platform-prod
#
# IMPORTANTE:
#   - NAO alterar parametros criticos (vpc_config, encryption_config) no primeiro apply
#   - Revisar lifecycle ignore_changes para evitar drift em campos gerenciados fora do TF
#   - O cluster compartilha state entre staging e prod (single cluster, multi-tenant)
#
# Ref: GAP-FINOPS-ACCESS-ENTRY (node-groups.tf) — null_resource workaround
#      que sera eliminado apos este import.
# =============================================================================

# --- Import Block (Terraform 1.5+) ---
# Descomentar para importar o cluster existente para o TF state.
# Apos o primeiro apply com import, comentar ou remover o bloco import
# (ele so e necessario na primeira execucao).

# import {
#   to = aws_eks_cluster.main
#   id = "k8s-platform-prod"
# }

# --- EKS Cluster Resource ---
# Descomentar junto com o import block acima.
# Os valores abaixo refletem a configuracao real do cluster (capturada via
# aws eks describe-cluster --name k8s-platform-prod).

# resource "aws_eks_cluster" "main" {
#   name     = local.cluster_name
#   role_arn = "arn:aws:iam::891377105802:role/k8s-platform-eks-cluster-role"
#   version  = "1.34"
#
#   vpc_config {
#     subnet_ids              = local.private_subnets
#     endpoint_private_access = true
#     endpoint_public_access  = true  # TODO: avaliar restringir para false apos VPN (GAP-CONF-023)
#     security_group_ids      = []    # TODO: capturar SG real via describe-cluster
#   }
#
#   access_config {
#     authentication_mode                         = "API_AND_CONFIG_MAP"
#     bootstrap_cluster_creator_admin_permissions  = true
#   }
#
#   # Apenas authenticator habilitado (D2: EKS audit log BACEN — apenas authenticator)
#   enabled_cluster_log_types = ["authenticator"]
#
#   tags = merge(local.common_tags, {
#     Name = local.cluster_name
#   })
#
#   lifecycle {
#     ignore_changes = [
#       # Evitar force-replacement em campos imutaveis
#       vpc_config[0].subnet_ids,
#       # EKS managed upgrades alteram a versao do cluster
#       version,
#     ]
#   }
# }

# =============================================================================
# NOTAS POS-IMPORT:
# 1. Apos import + apply bem sucedido:
#    - Remover null_resource.eks_auth_mode_api_and_configmap de node-groups.tf
#    - Descomentar o resource aws_eks_cluster.main acima
#    - terraform plan deve retornar "No changes" (zero drift)
# 2. Atualizar data sources existentes para referenciar aws_eks_cluster.main:
#    - data "aws_eks_cluster" "cluster" pode ser substituido por reference direta
#    - Manter data source temporariamente para backward compat (prod main.tf usa)
# =============================================================================
