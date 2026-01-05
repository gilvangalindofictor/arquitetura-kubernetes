# ADR-001: Estrutura Inicial do Domínio CI/CD Platform

**Status**: ✅ Aceito  
**Data**: 2026-01-05  
**Contexto**: Criação do domínio cicd-platform conforme SAD v1.2  
**Decisores**: Arquiteto de Plataforma  

---

## Contexto

Conforme definido no [SAD v1.2](../../../../SAD/docs/sad.md), o domínio **cicd-platform** é o **PRIMEIRO OBJETIVO** da plataforma corporativa Kubernetes, fornecendo a esteira CI/CD completa para todos os domínios e aplicações.

### Prioridade
Este é o domínio de **maior prioridade** após observability, pois permite:
- Automatização de deployments (GitOps via ArgoCD)
- Quality gates (SonarQube)
- Governança (Backstage)
- Continuous Integration (GitLab CI)

## Decisão

Criar estrutura base do domínio **cicd-platform** seguindo padrão estabelecido pelo domínio observability (cloud-agnostic, terraform kubernetes/helm only).

### Estrutura
```
/domains/cicd-platform/
├── README.md
├── docs/
│   └── adr/
│       └── adr-001-estrutura-inicial.md (este arquivo)
├── infra/
│   ├── terraform/      # Cloud-agnostic (kubernetes/helm providers only)
│   └── helm/           # Custom values
└── local-dev/          # Docker Compose (desenvolvimento)
```

### Stack Tecnológico
1. **GitLab Community Edition** - Git repository + CI/CD
2. **SonarQube** - Code quality + security scanning
3. **Harbor** - Container registry + Helm charts
4. **ArgoCD** - GitOps continuous deployment
5. **Backstage** - Developer portal + service catalog

### Conformidade SAD v1.2
- ✅ **ADR-003 (Cloud-Agnostic)**: Terraform usa apenas `kubernetes` + `helm` providers
- ✅ **ADR-004 (GitOps)**: ArgoCD como padrão obrigatório
- ✅ **ADR-020 (Provisionamento)**: Cluster provisionado externamente em `/platform-provisioning/`
- ✅ **ADR-021 (Kubernetes)**: Stack 100% Kubernetes-native

## Consequências

### Positivas
- ✅ Estrutura padronizada (reutiliza pattern do observability)
- ✅ Cloud-agnostic desde o início
- ✅ Pronto para consumir outputs de `/platform-provisioning/`
- ✅ Conformidade total com SAD v1.2

### Negativas
- ⚠️ Complexidade inicial (5 componentes principais)
- ⚠️ Dependências entre componentes (GitLab → Harbor → ArgoCD)

### Próximos Passos
1. Criar terraform cloud-agnostic (main.tf, variables.tf)
2. Deploy GitLab via Helm
3. Deploy SonarQube via Helm
4. Deploy Harbor via Helm
5. Deploy ArgoCD via Helm
6. Deploy Backstage via Helm

## Referências
- [SAD v1.2](../../../../SAD/docs/sad.md)
- [ADR-003: Cloud-Agnostic](../../../../SAD/docs/adrs/adr-003-cloud-agnostic.md)
- [ADR-004: IaC e GitOps](../../../../SAD/docs/adrs/adr-004-iac-gitops.md)
- [Domain Contracts](../../../../SAD/docs/architecture/domain-contracts.md)
- [Observability Domain](../../observability/README.md) (referência de estrutura)

---
**Aprovado**: 2026-01-05  
**Versão**: 1.0
