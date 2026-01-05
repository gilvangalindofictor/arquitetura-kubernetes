# ADR-004: IaC e GitOps

## Status
Aceito | **Atualizado** 2026-01-05 (v1.1)

## Contexto
Para garantir rastreabilidade, consistência e automação, toda infraestrutura deve ser versionada e deployments automatizados. GitOps permite deployments declarativos e rollback fácil.

**Atualização v1.1**: Esclarecer escopo de IaC para clusters vs domínios (ver ADR-020).

## Decisão
- **IaC**: Terraform como padrão para infraestrutura
- **Packaging**: Helm para aplicações Kubernetes
- **GitOps**: ArgoCD como operador de deployment
- **Versionamento**: Git como fonte da verdade

### Separação de Escopo (v1.1)

#### Platform Provisioning (`/platform-provisioning`)
- **Responsabilidade**: Clusters Kubernetes, VPC, IAM base
- **Terraform Providers**: `aws`, `google`, `azurerm` (cloud-specific)
- **Output**: Kubeconfig, storage classes, endpoints

#### Domain Provisioning (`/domains/{domain}/infra`)
- **Responsabilidade**: Recursos Kubernetes nativos
- **Terraform Providers**: `kubernetes`, `helm`, `kubectl` APENAS
- **Input**: Kubeconfig (do platform provisioning)
- **Recursos**: Namespaces, RBAC, Services, PVCs (parametrizados)

## Consequências
- **Positivo**: Rastreabilidade total, automação, consistência
- **Negativo**: Curva de aprendizado, complexidade inicial
- **Riscos**: Drift entre código e estado real
- **Mitigação**: Drift detection obrigatória, hooks de validação

## Implementação
- **Estrutura Git**: /infra/terraform, /infra/helm, /infra/argocd
- **Pipelines**: GitLab CI para validate/plan/apply
- **Drift Detection**: Terraform plan diário
- **Secrets**: External Secrets Operator para credenciais

## Validação
- Testes de deployment via ArgoCD
- Drift checks automatizados
- Rollback validation

## Referências
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/)
- [ArgoCD GitOps](https://argo-cd.readthedocs.io/)

Data: 2025-12-30</content>
<parameter name="filePath">\\wsl.localhost\Ubuntu\home\gilvangalindo\projects\Arquitetura\Kubernetes\SAD\docs\adrs\adr-004-iac-gitops.md