# ADR-004: Terraform vs Helm para Platform Services

**Data:** 2026-01-26
**Status:** Accepted
**Autor:** DevOps Team
**Contexto:** Marco 2 - Platform Services

---

## Contexto

Durante a implementação do Marco 2 (Platform Services), identificamos uma divergência entre:

1. **Plano Original** ([aws-eks-gitlab-quickstart.md](../plan/quickstart/aws-eks-gitlab-quickstart.md)): Especificava instalação de Platform Services via **Helm Charts diretamente**
2. **Implementação Real** (Marco 2): Platform Services instalados via **Terraform com Helm Provider**

### Componentes Afetados

| Componente | Plano Original | Implementação Marco 2 |
|------------|---------------|----------------------|
| AWS Load Balancer Controller | Helm chart manual | Terraform module + Helm provider |
| Cert-Manager | Helm chart manual | Terraform module + Helm provider |
| Kube-Prometheus-Stack | Helm chart manual | Terraform module + Helm provider |

### Problema

A divergência entre plano e implementação pode causar:
- ❌ Confusão sobre qual abordagem seguir em futuros componentes
- ❌ Inconsistência na documentação e scripts de validação
- ❌ Duplicação de esforços (código Terraform + scripts Helm)

---

## Decisão

**Manter abordagem Terraform para Platform Services**, com as seguintes diretrizes:

### 1. Separação de Responsabilidades

| Tipo de Componente | Ferramenta | Justificativa |
|-------------------|-----------|---------------|
| **Platform Services** | Terraform + Helm Provider | Infraestrutura base, versionamento de estado, integração AWS |
| **Application Deployments** | Helm (direto) ou ArgoCD | Deployments dinâmicos, CI/CD, valores por ambiente |

### 2. Platform Services (Terraform)

Componentes instalados via Terraform:

- ✅ **AWS Load Balancer Controller**: Requer IRSA (IAM Role for Service Account) criado via Terraform
- ✅ **Cert-Manager**: Integração com Route53 para DNS01 challenges (IAM policies)
- ✅ **Kube-Prometheus-Stack**: Configuração fixa, storage classes AWS, node selectors
- ✅ **External Secrets Operator** (futuro): Integração com AWS Secrets Manager (IAM)
- ✅ **Velero** (futuro): Backup para S3, IAM policies

**Características:**
- Infraestrutura como código (IaC)
- State management via S3 + DynamoDB
- Dependências entre recursos (OIDC → IAM → Helm Release)
- Integração profunda com AWS (IAM, KMS, S3)

### 3. Application Deployments (Helm ou ArgoCD)

Aplicações instaladas via Helm direto ou ArgoCD:

- 🔄 **GitLab**: Umbrella chart com múltiplos subcharts, valores dinâmicos
- 🔄 **Redis**: Bitnami chart para cache/sessions, configurações por aplicação
- 🔄 **RabbitMQ**: Messaging queue para microserviços
- 🔄 **PostgreSQL Operator**: Provisionamento dinâmico de databases
- 🔄 **Aplicações customizadas**: Deployments de equipes de desenvolvimento

**Características:**
- Valores dinâmicos por ambiente (dev/staging/prod)
- Rollback rápido via `helm rollback`
- Deploys frequentes (CI/CD pipelines)
- Não requer integração AWS profunda

---

## Rationale

### Por que Terraform para Platform Services?

1. **Integração AWS Nativa**
   - IRSA (IAM Roles for Service Accounts) requer criação de OIDC Provider, IAM Policy e IAM Role
   - Trust relationships entre EKS e IAM são complexos, melhor gerenciados via Terraform
   - Exemplo: AWS Load Balancer Controller precisa de IAM policy com 50+ permissions

2. **Dependências Complexas**
   ```
   OIDC Provider → IAM Policy → IAM Role → Service Account → Helm Release
   ```
   - Terraform gerencia essas dependências automaticamente via `depends_on` e referências
   - Helm sozinho não consegue criar recursos AWS (IAM, S3, KMS)

3. **Infraestrutura como Código (IaC)**
   - State management: Terraform rastreia todos os recursos (AWS + Kubernetes)
   - Drift detection: `terraform plan` detecta alterações manuais
   - Rollback controlado: State versionado no S3

4. **Consistência com Marco 0 e Marco 1**
   - Marco 0: Backend Terraform, VPC via Terraform
   - Marco 1: EKS Cluster, Node Groups, Add-ons via Terraform
   - Marco 2: Platform Services via Terraform (consistência arquitetural)

5. **Separação de Ambientes**
   - Cada ambiente (marco1, marco2) tem seu próprio state file
   - Isolamento completo: `terraform destroy` no marco2 não afeta marco1
   - Facilita experimentação e rollback

### Por que Helm para Aplicações?

1. **Flexibilidade de Deployments**
   - Helm charts são templates, suportam valores dinâmicos
   - Ideal para aplicações com configurações que mudam frequentemente
   - Exemplo: GitLab com diferentes replicas em staging vs prod

2. **Velocidade de Iteração**
   - `helm upgrade` é mais rápido que `terraform apply`
   - Não requer state locking (DynamoDB)
   - Ideal para CI/CD pipelines com múltiplos deploys por dia

3. **Rollback Rápido**
   - `helm rollback gitlab 5` volta para revisão anterior instantaneamente
   - Terraform rollback requer reverter código Git e re-aplicar

4. **Ecossistema Maduro**
   - Helm charts oficiais para GitLab, Redis, RabbitMQ são bem mantidos
   - Valores bem documentados, exemplos de configuração
   - Comunidade ativa (stack overflow, GitHub issues)

---

## Alternativas Consideradas

### Opção A: Helm puro (conforme plano original)

| Prós | Contras |
|------|---------|
| ✅ Simplicidade inicial | ❌ Não cria recursos AWS (IAM, S3, KMS) |
| ✅ Consistência com plano | ❌ Requer scripts shell para IAM/OIDC |
| ✅ Velocidade de deploy | ❌ Sem state management |
| | ❌ Difícil gerenciar dependências |

**Decisão:** ❌ Rejeitado - Complexidade de gerenciar IAM manualmente é muito alta

### Opção B: Terraform puro (sem Helm provider)

| Prós | Contras |
|------|---------|
| ✅ IaC completo | ❌ Não usa Helm charts oficiais |
| ✅ State management | ❌ Requer manutenção de manifestos YAML |
| | ❌ Perde benefícios do ecossistema Helm |

**Decisão:** ❌ Rejeitado - Recriar charts em Terraform é impraticável

### Opção C: Terraform + Helm Provider (implementação atual)

| Prós | Contras |
|------|---------|
| ✅ Melhor dos dois mundos | ⚠️ Diverge do plano original |
| ✅ IaC + Helm charts oficiais | ⚠️ Complexidade do Helm provider |
| ✅ Dependências gerenciadas | ⚠️ Precisa de cluster ativo para `terraform plan` |
| ✅ Integração AWS nativa | |

**Decisão:** ✅ **ESCOLHIDO** - Benefícios superam os contras

---

## Consequências

### Positivas

✅ **Separação clara de responsabilidades**: Ops gerencia Platform Services (Terraform), Devs gerenciam Apps (Helm/ArgoCD)
✅ **Rastreabilidade completa**: Terraform state registra todos os recursos (AWS + K8s)
✅ **Dependências automáticas**: Terraform garante ordem correta de criação (OIDC → IAM → Helm)
✅ **Conformidade IaC**: 100% dos recursos versionados em Git
✅ **Disaster Recovery**: `terraform apply` recria infraestrutura idempotentemente

### Negativas

⚠️ **Divergência do plano**: Requer atualização de [aws-eks-gitlab-quickstart.md](../plan/quickstart/aws-eks-gitlab-quickstart.md)
⚠️ **Complexidade inicial**: Curva de aprendizado do Helm provider Terraform
⚠️ **Dependência de cluster ativo**: `terraform plan` falha se cluster não existe ou está inacessível

### Neutras

🔄 **Validação scripts**: Precisam validar Terraform ao invés de Helm (atualização necessária)
🔄 **Documentação**: ADRs e READMEs precisam refletir abordagem híbrida

---

## Plano de Atualização

### Fase 1 (Imediato - Marco 2)

- [x] Criar ADR-004 formalizando decisão
- [ ] Atualizar [aws-eks-gitlab-quickstart.md](../plan/quickstart/aws-eks-gitlab-quickstart.md):
  - Adicionar seção "Platform Services via Terraform"
  - Manter seção "Application Deployments via Helm"
  - Explicar rationale da abordagem híbrida
- [ ] Atualizar [domains/observability/infra/validation/validate.sh](../../domains/observability/infra/validation/validate.sh):
  - Remover validações Helm direto para Platform Services
  - Adicionar validações Terraform (`terraform plan`, `terraform validate`)
  - Manter validações Helm para aplicações (GitLab, Redis, RabbitMQ)

### Fase 2 (Marco 3)

- [ ] Criar template de módulo Terraform para Platform Services:
  ```
  modules/platform-service-template/
  ├── main.tf       # Helm release + recursos AWS
  ├── variables.tf  # Configurações do chart
  ├── outputs.tf    # ARNs, endpoints
  └── versions.tf   # Provider constraints
  ```
- [ ] Documentar guidelines: "Quando usar Terraform vs Helm"
- [ ] Criar diagrama de arquitetura mostrando separação

### Fase 3 (Futuro)

- [ ] Migrar GitLab para ArgoCD (GitOps pattern)
- [ ] Implementar External Secrets Operator (sync K8s ↔ AWS Secrets Manager)
- [ ] Avaliar Crossplane como alternativa ao Terraform (Kubernetes-native IaC)

---

## Validação

### Checklist de Conformidade

- [x] Platform Services instalados via Terraform
- [x] Helm provider usado para charts oficiais
- [x] IAM/OIDC gerenciados via Terraform
- [x] State management funcional (S3 + DynamoDB)
- [ ] Documentação atualizada (quickstart, validation scripts)
- [ ] ADR aprovado e comunicado ao time

### Testes

```bash
# Validar que Terraform gerencia Platform Services
cd platform-provisioning/aws/kubernetes/terraform/envs/marco2
terraform state list | grep helm_release
# Esperado:
# module.aws_load_balancer_controller.helm_release.aws_load_balancer_controller
# module.cert_manager.helm_release.cert_manager
# module.kube_prometheus_stack.helm_release.kube_prometheus_stack

# Validar que Helm reconhece releases gerenciadas por Terraform
helm list -A
# Esperado: Releases aparecem normalmente, mas estado é gerenciado por Terraform

# Validar que aplicações (futuras) usam Helm direto
helm install gitlab gitlab/gitlab -f values-prod.yaml
# Esperado: Funciona independente do Terraform
```

---

## Referências

- [Terraform Helm Provider Documentation](https://registry.terraform.io/providers/hashicorp/helm/latest/docs)
- [Plano Original: AWS EKS GitLab Quickstart](../plan/quickstart/aws-eks-gitlab-quickstart.md)
- [Best Practices: Terraform + Helm](https://www.hashicorp.com/blog/using-the-helm-provider-for-terraform)
- [IRSA (IAM Roles for Service Accounts)](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)

---

## Decisões Relacionadas

- [ADR-001: Setup e Governança](adr-001-setup-e-governanca.md)
- [ADR-002: Estrutura de Domínios](adr-002-estrutura-de-dominios.md)
- [ADR-003: Secrets Management Strategy](adr-003-secrets-management-strategy.md)

---

**Última atualização:** 2026-01-26
**Aprovado por:** DevOps Team
**Próxima revisão:** Marco 3 (quando adicionar novos Platform Services)
