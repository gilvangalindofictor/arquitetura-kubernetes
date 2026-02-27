# Domínio Observability - Plataforma Corporativa Kubernetes

> **Parte da**: Plataforma Corporativa Kubernetes (6 domínios)  
> **Governança**: SAD (Software Architecture Document) v1.2 - `/SAD/docs/sad.md`  
> **Status**: ✅ Integrado | ✅ Conformidade Total com SAD v1.2  
> **Última Validação**: 2026-01-05 - Validação #3 (ADR-005)  
> **Última Refatoração**: 2026-01-05 - Terraform Cloud-Agnostic (ADR-006)

Este domínio fornece **observabilidade full-stack** (métricas, logs, traces) para todos os domínios da plataforma corporativa, usando stack open source **100% cloud-agnostic** e **Kubernetes-native**.

## 🎯 Missão
Coletar, processar, armazenar e visualizar sinais de telemetria (métricas, logs, traces) de todos os domínios e aplicações da plataforma usando **OpenTelemetry** como padrão único.

## ✅ Conformidade com SAD v1.2

### Princípios Arquiteturais Atendidos
- ✅ **Cloud-Agnostic** ([ADR-003](../../../SAD/docs/adrs/adr-003-cloud-agnostic.md)): Terraform usa apenas `kubernetes` + `helm` providers
- ✅ **Provisionamento Separado** ([ADR-020](../../../SAD/docs/adrs/adr-020-provisionamento-clusters.md)): Cluster provisionado em `/platform-provisioning/`
- ✅ **Kubernetes-Native** ([ADR-021](../../../SAD/docs/adrs/adr-021-orquestracao-kubernetes.md)): Stack 100% Kubernetes-native
- ✅ **OpenTelemetry Padrão Único** (ADR-006): OTEL Collector como gateway central
- ✅ **Contratos entre Domínios**: APIs expostas conforme `/SAD/docs/architecture/domain-contracts.md`
- ⚠️ **Isolamento** (ADR-005): **GAPS** - Falta RBAC explícito, Network Policies e Service Mesh
- ⚠️ **GitOps** (ADR-004): **PENDENTE** - ArgoCD será integrado após cicd-platform

**Validações Completas**:
- [Validação #1](docs/VALIDATION-REPORT.md#validação-1) - SAD v1.0 (2025-12-28)
- [Validação #2](docs/VALIDATION-REPORT.md#validação-2) - SAD v1.1 (2026-01-03)
- [Validação #3](docs/VALIDATION-REPORT.md#validação-3) - SAD v1.2 (2026-01-05) + ADR-021

**ADRs Locais**:
- [ADR-005](docs/adr/adr-005-revalidacao-sad-v12.md): Re-validação SAD v1.2 + Consolidação
- [ADR-006](docs/adr/adr-006-refatoracao-terraform-cloud-agnostic.md): Refatoração Terraform Cloud-Agnostic ✅ Implementado

> **Nota Metodológica**: Este domínio foi estruturado por IA (GitHub Copilot) seguindo metodologia "AI-First Project Orchestration" e posteriormente validado contra o SAD corporativo.

## Documentação Principal

Toda a jornada de ideação, planejamento e decisões arquitetônicas está documentada na pasta `/docs`.

-   **[Contexto do Projeto](docs/context/context-generator.md)**: A missão, escopo, restrições e o problema que estamos resolvendo.
-   **[Plano de Execução](docs/plan/execution-plan.md)**: O plano de 5 fases que guiou a construção deste projeto.
-   **[Decisões de Arquitetura (ADRs)](docs/adr/)**: Os ADRs (Architecture Decision Records) que documentam as escolhas tecnológicas e de design.
-   **[Arquitetura Lógica](docs/infra/arquitetura-logica.md)**: Um diagrama e descrição detalhada do fluxo de dados de telemetria.
-   **[Validação contra SAD](docs/VALIDATION-REPORT.md)**: Histórico de 3 validações (SAD v1.0 → v1.1 → v1.2).

## Stack de Tecnologia

| Pilar                 | Ferramenta                                                                                             | Propósito                                                       |
| --------------------- | ------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------- |
| **Provisionamento**   | [Platform Provisioning](../../../platform-provisioning/)                                               | ✅ Cluster Kubernetes (AWS/Azure/GCP) provisionado centralmente |
| **IaC Domínio**       | Terraform (kubernetes + helm providers)                                                                | ✅ Deploy cloud-agnostic do stack de observabilidade           |
| **Orquestração**      | Kubernetes (qualquer cluster)                                                                          | ✅ Plataforma para rodar os componentes (cloud-agnostic)       |
| **Coleta & Processamento** | [OpenTelemetry Collector](infra/helm/opentelemetry-collector/values.yaml) | Gateway central e agnóstico para receber toda a telemetria.     |
| **Métricas**          | [Prometheus](infra/helm/kube-prometheus-stack/values.yaml)                                             | Armazenamento e consulta de métricas de curto prazo.            |
| **Logs**              | [Loki](infra/helm/loki/values.yaml)                                                                    | Agregação e consulta de logs.                                   |
| **Traces**            | [Tempo](infra/helm/tempo/values.yaml)                                                                  | Armazenamento e consulta de traces distribuídos.                |
| **Visualização**      | [Grafana](infra/helm/kube-prometheus-stack/values.yaml)                                                | Dashboard unificado para métricas, logs e traces.               |
| **Alertas**           | [Alertmanager](infra/helm/kube-prometheus-stack/values.yaml)                                           | Gerenciamento e roteamento de alertas.                          |
| **Deploy**            | Helm                                                                                                   | Gerenciamento das aplicações no Kubernetes.                     |
| **Armazenamento (Longo Prazo)** | Object Storage (S3/Blob/GCS)                                                                  | ✅ Backend cloud-agnostic para Loki, Tempo, Prometheus          |

## Como Começar

### 🚀 Deploy em Cluster Kubernetes (Produção)

**Pré-requisito**: Cluster Kubernetes provisionado via [Platform Provisioning](../../../platform-provisioning/)

```bash
# 1. Provisionar cluster (executar UMA VEZ, reutilizável por todos os domínios)
cd /platform-provisioning/aws/kubernetes/terraform/  # ou /azure/ ou /gcp/
terraform init
terraform apply

# Capturar outputs do cluster
terraform output cluster_endpoint
terraform output storage_class_name
terraform output s3_bucket_logs
terraform output object_storage_endpoint

# 2. Deploy domínio observability (consumindo outputs do passo 1)
cd /domains/observability/infra/terraform/

# Editar terraform.tfvars com outputs capturados
cat <<EOF > terraform.tfvars
cluster_endpoint        = "https://1234567890ABCDEF.gr7.us-east-1.eks.amazonaws.com"
cluster_ca_certificate  = "LS0tLS1CRUdJTi..."
storage_class_name      = "gp3"  # ou "managed-premium" (Azure) ou "pd-ssd" (GCP)
s3_bucket_metrics       = "platform-metrics-abc123"
s3_bucket_logs          = "platform-logs-abc123"
s3_bucket_traces        = "platform-traces-abc123"
object_storage_endpoint = "https://s3.us-east-1.amazonaws.com"

environments = ["observability-production"]
EOF

terraform init
terraform apply
```

📚 **Documentação Completa**:
- [Platform Provisioning AWS](../../../platform-provisioning/aws/README.md) - Custos: $599.30/mês
- [REFACTORING-STATUS.md](infra/terraform/REFACTORING-STATUS.md) - Status da refatoração cloud-agnostic
- [ADR-006](docs/adr/adr-006-refatoracao-terraform-cloud-agnostic.md) - Decisão de refatoração

### 🏠 Desenvolvimento Local (Recomendado para MVP)

**Desenvolva e teste TUDO localmente antes de gastar recursos na cloud!**

O ambiente local permite desenvolver a stack completa de observabilidade usando Docker Compose, sem custos de cloud.

```bash
# Quick Start Local
cd local-dev
cp .env.example .env
docker-compose up -d

# Acesse:
# Grafana:    http://localhost:3000 (admin/admin123)
# Prometheus: http://localhost:9090
```

📚 **Documentação Completa**: [`local-dev/README.md`](./local-dev/README.md)

**Requisitos Mínimos**:
- CPU: 4 cores
- RAM: 8 GB
- Disco: 20 GB
- Docker instalado

✅ **Vantagens**:
- Zero custos durante desenvolvimento
- Feedback imediato (sem esperar deploys)
- Ambiente 100% reproduzível
- Trabalhe offline

➡️ **Após validar localmente**, migre para AWS usando o fluxo abaixo.

---

### ☁️ Deploy na AWS (Produção)

### 1. Pré-requisitos

Antes de começar, garanta que você tenha as seguintes ferramentas instaladas e configuradas:
-   [AWS CLI](https://aws.amazon.com/cli/) (configurado com suas credenciais)
-   [Terraform](https://www.terraform.io/downloads.html) (>= 1.5)
-   [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
-   [Helm](https://helm.sh/docs/intro/install/)

### Alternativa: Desenvolvimento com Docker

Se você prefere minimizar as instalações em sua máquina local e usar o Docker como ambiente de desenvolvimento principal, você pode substituir a instalação dos pré-requisitos acima por seus equivalentes em contêineres.

Abaixo estão os comandos e aliases sugeridos. Você pode adicionar os aliases ao seu arquivo `~/.bashrc` ou `~/.zshrc` para facilitar o uso.

**Requisito:** Apenas o [Docker](https://docs.docker.com/get-docker/) precisa estar instalado.

1.  **AWS CLI**
    -   **Comando Docker:**
        ```bash
        docker run --rm -it -v ~/.aws:/root/.aws -v $(pwd):/aws amazon/aws-cli
        ```
    -   **Alias Sugerido:**
        ```bash
        alias aws='docker run --rm -it -v ~/.aws:/root/.aws -v $(pwd):/aws amazon/aws-cli'
        ```

2.  **Terraform**
    -   **Comando Docker:**
        ```bash
        docker run --rm -it -v ~/.aws:/root/.aws -v $(pwd):/app -w /app hashicorp/terraform:latest
        ```
    -   **Alias Sugerido:**
        ```bash
        alias terraform='docker run --rm -it -v ~/.aws:/root/.aws -v $(pwd):/app -w /app hashicorp/terraform:latest'
        ```

3.  **kubectl**
    -   **Comando Docker:**
        ```bash
        docker run --rm -it -v ~/.kube:/root/.kube bitnami/kubectl
        ```
    -   **Alias Sugerido:**
        ```bash
        alias kubectl='docker run --rm -it -v ~/.kube:/root/.kube bitnami/kubectl'
        ```

4.  **Helm**
    -   **Comando Docker:**
        ```bash
        docker run --rm -it -v ~/.kube:/root/.kube -v ~/.cache/helm:/root/.cache/helm -v ~/.config/helm:/root/.config/helm -v $(pwd):/apps alpine/helm
        ```
    -   **Alias Sugerido:**
        ```bash
        alias helm='docker run --rm -it -v ~/.kube:/root/.kube -v ~/.cache/helm:/root/.cache/helm -v ~/.config/helm:/root/.config/helm -v $(pwd):/apps alpine/helm'
        ```

Com esses aliases configurados, você pode seguir o restante do tutorial usando os comandos `aws`, `terraform`, `kubectl` e `helm` normalmente, e eles serão executados dentro de contêineres Docker isolados.

### 2. Validar o Ambiente AWS

Um script de validação foi criado para garantir que seu ambiente está pronto para o deploy.

```bash
# Navegue até a pasta de validação
cd infra/validation

# Torne o script executável
chmod +x validate.sh

# Execute o script
./validate.sh
```
O script verificará as ferramentas, a configuração da AWS e fará um "dry-run" do Terraform e Helm. Revise a saída do `terraform plan` para entender os recursos que serão criados.

### 3. Deploy da Infraestrutura (Terraform)

Após a validação bem-sucedida, provisione a infraestrutura na AWS.

```bash
# Navegue até a pasta do Terraform
cd infra/terraform

# Aplique a configuração (será necessário confirmar com 'yes')
terraform apply
```
Este processo criará a VPC, o cluster EKS, os buckets S3 e as roles IAM. Pode levar de 15 a 20 minutos.

### 4. Configurar o `kubectl`

Após a criação do cluster, configure seu `kubectl` para se conectar a ele.

```bash
aws eks --region $(terraform output -raw region) update-kubeconfig --name $(terraform output -raw cluster_name)
```

### 5. Deploy da Stack de Observabilidade (Helm)

Com o `kubectl` configurado, instale a stack de observabilidade usando Helm.

```bash
# Navegue até a pasta do Helm
cd infra/helm

# Crie o namespace no Kubernetes
kubectl create namespace observability

# Instale os charts
helm install otel-collector ./opentelemetry-collector -n observability
helm install prometheus-stack ./kube-prometheus-stack -n observability
helm install loki ./loki -n observability
helm install tempo ./tempo -n observability
```

### 6. Acessar o Grafana

Para acessar o Grafana, você pode usar o port-forward.

```bash
kubectl port-forward svc/prometheus-stack-grafana 3000:80 -n observability
```
Abra [http://localhost:3000](http://localhost:3000) no seu navegador. O usuário padrão é `admin` e a senha é a que foi definida em `infra/helm/kube-prometheus-stack/values.yaml` (`adminPassword`).

---

## 🚀 Estratégia de Desenvolvimento Recomendada

```
FASE 1: Desenvolvimento Local (0-2 semanas)
├─ Configurar ambiente local (Docker Compose)
├─ Criar dashboards no Grafana
├─ Definir alertas no Prometheus
├─ Instrumentar aplicação exemplo
└─ Validar fluxo completo de telemetria

FASE 2: Migração para AWS (1 semana)
├─ Deploy infraestrutura (Terraform)
├─ Deploy stack observabilidade (Helm)
├─ Migrar dashboards e alertas
└─ Validar em cloud

FASE 3: Refinamento (contínuo)
├─ Otimizar queries e dashboards
├─ Ajustar políticas de retenção
├─ Criar runbooks operacionais
└─ Instrumentar apps reais
```

**Economize tempo e dinheiro**: Desenvolva 100% local primeiro! 💰

---

## 📚 Documentação Completa

### Desenvolvimento Local
- [**Local Dev - README**](./local-dev/README.md) - Quick start do ambiente local
- [**Estimativa de Recursos**](./docs/local-dev/resource-estimation.md) - Requisitos de hardware
- [**Setup VS Code**](./docs/local-dev/vscode-setup.md) - Configuração do editor
- [**Workflow de Desenvolvimento**](./docs/local-dev/development-workflow.md) - Processos diários

### Arquitetura & Planejamento
- [**Contexto do Projeto**](./docs/context/context-generator.md) - Missão e escopo
- [**Plano de Execução**](./docs/plan/execution-plan.md) - Roadmap em 5 fases
- [**ADRs**](./docs/adr/) - Decisões arquitetônicas
- [**Arquitetura Lógica**](./docs/infra/arquitetura-logica.md) - Fluxo de dados

### Instrumentação & Operação
- [**Instrumentação Python**](./docs/instrumentation/instrumentation-python.md) - Apps Python
- [**Runbooks**](./docs/runbooks/) - Guias operacionais

## Próximos Passos

-   **Instrumentação**: Siga os guias em `docs/instrumentation` para começar a enviar dados de suas aplicações para o OpenTelemetry Collector.
-   **Runbooks**: Familiarize-se com os `docs/runbooks` para saber como agir quando os alertas dispararem.
-   **Customização**:
    -   Ajuste os `values.yaml` na pasta `infra/helm` para customizar as configurações.
    -   Crie novos dashboards em `infra/grafana/dashboards`.
    -   Defina novas regras de alerta em `infra/grafana/alerts`.
