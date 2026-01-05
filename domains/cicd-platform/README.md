# Domínio CI/CD Platform - Plataforma Corporativa Kubernetes

> **Parte da**: Plataforma Corporativa Kubernetes (6 domínios)  
> **Governança**: SAD (Software Architecture Document) v1.2 - `/SAD/docs/sad.md`  
> **Status**: 🚧 Em Construção | 🎯 Primeiro Objetivo  
> **Prioridade**: **MÁXIMA** - Esteira CI/CD Completa

Este domínio fornece a **esteira CI/CD completa** para todos os domínios e aplicações da plataforma corporativa, incluindo governança via Backstage.

## 🎯 Missão

Fornecer uma **esteira CI/CD moderna, automatizada e auditável** que permita:
- **Integração Contínua** (CI): Build, testes automatizados, análise de código
- **Entrega Contínua** (CD): Deploy automatizado via GitOps (ArgoCD)
- **Governança via Backstage**: Catálogo de serviços, criação padronizada de aplicações
- **Quality Gates**: SonarQube, testes de segurança, aprovações

## ✅ Conformidade com SAD v1.2

### Princípios Arquiteturais
- ✅ **Cloud-Agnostic** ([ADR-003](../../../SAD/docs/adrs/adr-003-cloud-agnostic.md)): Terraform usa apenas `kubernetes` + `helm` providers
- ✅ **Provisionamento Separado** ([ADR-020](../../../SAD/docs/adrs/adr-020-provisionamento-clusters.md)): Cluster provisionado em `/platform-provisioning/`
- ✅ **Kubernetes-Native** ([ADR-021](../../../SAD/docs/adrs/adr-021-orquestracao-kubernetes.md)): Stack 100% Kubernetes-native
- ✅ **GitOps** ([ADR-004](../../../SAD/docs/adrs/adr-004-iac-gitops.md)): ArgoCD como padrão obrigatório
- ⏳ **Observabilidade** ([ADR-006](../../../SAD/docs/adrs/adr-006-observabilidade-transversal.md)): Integração com domínio observability (pendente)
- ⏳ **Segurança** ([ADR-005](../../../SAD/docs/adrs/adr-005-seguranca-sistemica.md)): RBAC, Network Policies, Service Mesh (pendente)

## 📦 Stack de Tecnologia

| Componente | Ferramenta | Propósito |
|------------|-----------|-----------|
| **Git Repository** | GitLab Community Edition | Repositórios Git, CI pipelines |
| **CI Pipelines** | GitLab CI/CD | Build, test, scan |
| **Code Quality** | SonarQube | Análise estática, code smells, vulnerabilities |
| **Artifact Registry** | Harbor | Container registry, Helm charts |
| **GitOps CD** | ArgoCD | Continuous Deployment, drift detection |
| **Service Catalog** | Backstage | Developer portal, catálogo de serviços |
| **Secrets** | External Secrets Operator | Integração com secrets-management domain |
| **Storage** | Parametrizado via platform-provisioning | Volumes persistentes (PVC) |

## 🏗️ Arquitetura

### Namespaces
- `cicd-gitlab` - GitLab (CE), runners
- `cicd-sonarqube` - SonarQube, PostgreSQL
- `cicd-harbor` - Harbor registry
- `cicd-argocd` - ArgoCD, ApplicationSets
- `cicd-backstage` - Backstage portal

### Fluxo CI/CD

```
┌─────────────┐      ┌──────────────┐      ┌─────────────┐      ┌──────────┐
│   Developer │─────▶│ GitLab Repo  │─────▶│  GitLab CI  │─────▶│ SonarQube│
│  (git push) │      │   (main/dev) │      │  (pipeline) │      │  (scan)  │
└─────────────┘      └──────────────┘      └─────────────┘      └──────────┘
                                                   │
                                                   ▼
                                            ┌─────────────┐
                                            │   Harbor    │
                                            │  (registry) │
                                            └─────────────┘
                                                   │
                                                   ▼
                                            ┌─────────────┐      ┌──────────────┐
                                            │   ArgoCD    │─────▶│  Kubernetes  │
                                            │  (GitOps)   │      │  (clusters)  │
                                            └─────────────┘      └──────────────┘
                                                   ▲
                                                   │
                                            ┌─────────────┐
                                            │  Backstage  │
                                            │ (Catalog)   │
                                            └─────────────┘
```

## 🚀 Como Começar

### Pré-requisitos
1. **Cluster Kubernetes** provisionado via [Platform Provisioning](../../../platform-provisioning/)
2. **Outputs capturados**: `cluster_endpoint`, `storage_class_name`, etc.
3. **Secrets configurados**: Credenciais GitLab, Harbor, SonarQube

### Deploy

```bash
# 1. Capturar outputs do cluster (executar UMA VEZ)
cd /platform-provisioning/aws/kubernetes/terraform/  # ou /azure/ ou /gcp/
terraform output cluster_endpoint
terraform output storage_class_name

# 2. Deploy domínio cicd-platform
cd /domains/cicd-platform/infra/terraform/

# Editar terraform.tfvars com outputs capturados
cat <<EOF > terraform.tfvars
cluster_endpoint        = "https://YOUR-CLUSTER-ENDPOINT"
cluster_ca_certificate  = "YOUR-CA-CERT"
storage_class_name      = "gp3"  # ou "managed-premium" (Azure) ou "pd-ssd" (GCP)

# Configurações específicas
gitlab_domain           = "gitlab.example.com"
harbor_domain           = "harbor.example.com"
argocd_domain           = "argocd.example.com"
backstage_domain        = "backstage.example.com"
EOF

terraform init
terraform apply
```

## 📚 Contratos com Outros Domínios

### Contratos Fornecidos (Provider)
| Serviço | API/Interface | SLA | Consumidores |
|---------|---------------|-----|--------------|
| Git Repository | GitLab REST API | 99.9% | Developers |
| CI Pipelines | GitLab CI YAML | 99.5% | Applications |
| Artifact Registry | Harbor REST API | 99.9% | Deployments |
| Backstage Catalog | Backstage API | 99.9% | Teams |
| GitOps Deploy | ArgoCD Applications | 99.9% | Todos os domínios |

### Contratos Consumidos (Consumer)
| Serviço | Provider | Interface | SLA Required |
|---------|----------|-----------|--------------|
| Secrets | secrets-management | External Secrets API | 99.9% |
| Authentication | platform-core | Keycloak OIDC | 99.95% |
| Monitoring | observability | Prometheus metrics | 99.9% |
| Service Mesh | platform-core | Linkerd mTLS | 99.9% |

## 🔐 Segurança

### RBAC
- ServiceAccounts dedicadas por namespace
- Roles granulares (read-only, deployer, admin)
- OIDC integration com Keycloak (platform-core)

### Network Policies
- Deny-all por padrão
- Allow GitLab → Harbor (push images)
- Allow GitLab → SonarQube (scans)
- Allow ArgoCD → Kubernetes API
- Allow Developers → GitLab/Backstage (external)

### Secrets Management
- External Secrets Operator integrado com Vault (secrets-management)
- Rotação automática de credenciais
- Auditoria de acessos

## 📊 Observabilidade

### Métricas Exportadas
- **GitLab**: Pipeline duration, success rate, jobs/s
- **SonarQube**: Code coverage, vulnerabilities, technical debt
- **Harbor**: Image pulls, storage usage, scan results
- **ArgoCD**: Sync status, deployment frequency, sync duration
- **Backstage**: Catalog size, API latency, user activity

### Dashboards
- **CI/CD Performance**: Pipeline metrics, deployment frequency (DORA)
- **Code Quality**: SonarQube metrics aggregados
- **GitOps Health**: ArgoCD sync status, drift detection

## 📁 Estrutura do Domínio

```
/domains/cicd-platform/
├── README.md                   # Este arquivo
├── docs/
│   ├── adr/                    # Architecture Decision Records locais
│   ├── VALIDATION-REPORT.md    # Validação contra SAD (futuro)
│   └── runbooks/               # Runbooks operacionais
├── infra/
│   ├── terraform/              # IaC cloud-agnostic (kubernetes/helm)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars.example
│   └── helm/                   # Helm values customizados
│       ├── gitlab/
│       ├── sonarqube/
│       ├── harbor/
│       ├── argocd/
│       └── backstage/
└── local-dev/                  # Ambiente local (Docker Compose)
    └── docker-compose.yml
```

## 🛣️ Roadmap

### Fase 1: Foundation (Atual)
- [x] Estrutura de diretórios criada
- [ ] Terraform cloud-agnostic (main.tf, variables.tf)
- [ ] GitLab deployment via Helm
- [ ] SonarQube deployment via Helm
- [ ] Harbor deployment via Helm

### Fase 2: GitOps
- [ ] ArgoCD deployment via Helm
- [ ] ApplicationSets para domínios
- [ ] Backstage integration

### Fase 3: Governança
- [ ] Backstage deployment
- [ ] Software Templates (scaffolding)
- [ ] Service Catalog integration

### Fase 4: Security & Compliance
- [ ] RBAC policies (Kyverno/OPA)
- [ ] Network Policies implementation
- [ ] Secrets rotation automation
- [ ] Vulnerability scanning automation

## 📖 Referências

### SAD (Governança)
- [SAD v1.2](../../../SAD/docs/sad.md) - Documento supremo
- [ADR-003: Cloud-Agnostic](../../../SAD/docs/adrs/adr-003-cloud-agnostic.md)
- [ADR-004: IaC e GitOps](../../../SAD/docs/adrs/adr-004-iac-gitops.md)
- [ADR-020: Provisionamento de Clusters](../../../SAD/docs/adrs/adr-020-provisionamento-clusters.md)
- [Domain Contracts](../../../SAD/docs/architecture/domain-contracts.md)

### Platform Provisioning
- [AWS](../../../platform-provisioning/aws/README.md)
- [Azure](../../../platform-provisioning/azure/README.md) (futuro)

### Outros Domínios
- [observability](../observability/README.md) - Monitoramento
- [platform-core](../platform-core/README.md) - Gateway, Auth, Service Mesh
- [secrets-management](../secrets-management/README.md) - Vault

---

**Status**: 🚧 Em Construção  
**Primeira Validação**: Pendente  
**Responsável**: Equipe Platform Engineering  
**Contato**: platform-team@example.com
