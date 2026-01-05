# ADR-003: Cloud-Agnostic e Portabilidade

## Status
Aceito | **Atualizado** 2026-01-05 (v1.1)

## Contexto
A plataforma Kubernetes deve operar em múltiplos ambientes cloud (AWS EKS, Google GKE, Azure AKS) e on-premises sem modificações específicas. Isso garante flexibilidade, reduz vendor lock-in e permite migração fácil entre provedores.

**Atualização v1.1**: Validação do domínio observability revelou necessidade de diretrizes práticas mais claras. Ver ADR-020 para detalhes de implementação.

## Decisão
Adotamos arquitetura 100% cloud-agnostic, utilizando exclusivamente APIs Kubernetes nativas e recursos multi-cloud via Terraform providers genéricos.

### Diretrizes Práticas (v1.1)

#### 1. Separação de Responsabilidades
- **Clusters Kubernetes**: Provisionados EXTERNAMENTE aos domínios (ver ADR-020)
- **Domínios**: Assumem cluster existente, usam apenas APIs Kubernetes nativas
- **Localização IaC**: 
  - Clusters: `/platform-provisioning/{aws,gcp,azure,on-premises}`
  - Domínios: `/domains/{domain}/infra/terraform/` (apenas K8s resources)

#### 2. Storage Classes
- **Proibido**: Hardcoding storage classes (`storageClassName: gp2`)
- **Obrigatório**: Parametrização por variável
  ```yaml
  storageClassName: {{ .Values.storageClass }}
  ```
- **Deploy**: Valores específicos por cloud (`values-aws.yaml`, `values-gcp.yaml`)

#### 3. Object Storage
- **Padrão**: S3-compatible API (MinIO, AWS S3, GCS, Azure Blob)
- **Parametrização**: Endpoint, bucket, credenciais via variáveis
- **Buckets**: Criados em `/platform-provisioning`, não nos domínios

#### 4. Terraform nos Domínios
- **Providers Permitidos**: `kubernetes`, `helm`, `kubectl`
- **Providers Proibidos**: `aws`, `google`, `azurerm`
- **Recursos Permitidos**: Namespaces, RBAC, Services, PVCs (parametrizados)
- **Recursos Proibidos**: EKS, IAM, VPC, cloud-specific resources

## Consequências
- **Positivo**: Portabilidade total, custo reduzido, futuro-proof
- **Negativo**: Limitações em recursos nativos avançados (ex.: AWS ALB, GCP Load Balancer)
- **Riscos**: Complexidade em multi-cloud deployment
- **Mitigação**: Estratégia de deployment multi-cloud definida em ADR-003 (este mesmo)

## Estratégia de Multi-Cloud Deployment
- **Clusters**: Um por região/cloud, conectados via service mesh
- **Load Balancing**: NGINX Ingress Controller (não cloud-specific)
- **Storage**: Persistent Volumes via CSI drivers genéricos
- **Networking**: Calico/Cilium para CNI (não cloud-specific)
- **DNS**: External-DNS com providers múltiplos
- **Backup**: Velero com storage backends multi-cloud

## Validação
- Testes de deployment em EKS/GKE/AKS/on-prem
- Drift detection via Terraform
- Custo comparison entre clouds

## Referências
- [Terraform Multi-Cloud](https://www.terraform.io/docs/providers/)
- [Kubernetes Cloud Agnostic](https://kubernetes.io/docs/concepts/cluster-administration/cloud-providers/)

Data: 2025-12-30</content>
<parameter name="filePath">\\wsl.localhost\Ubuntu\home\gilvangalindo\projects\Arquitetura\Kubernetes\SAD\docs\adrs\adr-003-cloud-agnostic.md