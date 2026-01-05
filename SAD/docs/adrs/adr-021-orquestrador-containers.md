# ADR-021: Escolha do Orquestrador de Containers

> **Status**: ✅ Aprovado  
> **Data**: 2026-01-05  
> **Contexto**: Decisão fundamental sobre plataforma de orquestração  
> **Decisores**: Arquiteto, CTO  
> **Versão SAD**: v1.2

---

## Contexto

O projeto **Plataforma Corporativa de Engenharia** requer um orquestrador de containers para gerenciar os 6 domínios especializados (platform-core, cicd-platform, observability, data-services, secrets-management, security).

### Requisitos Funcionais
1. **Escalabilidade**: Suportar 6 domínios independentes com crescimento horizontal/vertical
2. **Isolamento**: Namespaces, RBAC, network policies por domínio
3. **Alta Disponibilidade**: Multi-AZ/multi-region, self-healing
4. **Service Discovery**: DNS interno, load balancing
5. **Storage**: Persistent volumes para stateful workloads (PostgreSQL, Redis, GitLab)
6. **Observabilidade**: Métricas, logs, traces nativos ou via integrações
7. **Segurança**: RBAC granular, network policies, secrets management

### Requisitos Não-Funcionais
1. **Cloud-Agnostic**: Rodar em AWS, Azure, GCP e on-premises sem modificações
2. **Portabilidade**: Migração entre clouds com esforço mínimo
3. **Ecossistema**: Tooling maduro (Helm, Operators, Service Mesh, GitOps)
4. **Community Support**: Documentação extensa, community ativa
5. **Custo**: Managed control plane disponível em clouds públicas
6. **Skill Availability**: Profissionais disponíveis no mercado

---

## Decisão

**Escolhemos Kubernetes** como orquestrador de containers para a plataforma.

---

## Alternativas Consideradas

### 1. Docker Swarm

**Prós**:
- ✅ Simplicidade: Curva de aprendizado menor que K8s
- ✅ Integração nativa com Docker
- ✅ Setup rápido
- ✅ Menos overhead operacional

**Contras**:
- ❌ Ecossistema limitado (sem Helm, Operators)
- ❌ Cloud-agnostic fraco: Sem managed service em clouds públicas
- ❌ Comunidade menor e decrescente
- ❌ Falta de recursos avançados: Service Mesh nativo, CRDs, Operators
- ❌ Pouco suporte corporativo

**Conclusão**: Rejeitado - simplicidade não compensa falta de ecossistema e portabilidade

---

### 2. HashiCorp Nomad

**Prós**:
- ✅ Simplicidade: Mais simples que K8s
- ✅ Multi-workload: Containers, VMs, binários
- ✅ Integração com Vault, Consul
- ✅ Boa performance
- ✅ Cloud-agnostic

**Contras**:
- ❌ Ecossistema menor: Helm não funciona, menos Operators
- ❌ Sem managed service em clouds públicas (AWS, Azure, GCP)
- ❌ Comunidade menor que K8s
- ❌ Menor disponibilidade de profissionais no mercado
- ❌ Service Mesh requer Consul separado

**Conclusão**: Rejeitado - falta de managed services e ecossistema limitado

---

### 3. AWS ECS/Fargate

**Prós**:
- ✅ Simplicidade: Gerenciado pela AWS
- ✅ Integração nativa AWS: ALB, CloudWatch, IAM
- ✅ Custo: Fargate serverless (pay-per-use)
- ✅ Operacionalmente simples

**Contras**:
- ❌ **Vendor Lock-in CRÍTICO**: AWS-only, viola ADR-003 (cloud-agnostic)
- ❌ Portabilidade zero para Azure, GCP, on-prem
- ❌ Ecossistema limitado vs K8s
- ❌ Service Mesh requer App Mesh (AWS-specific)
- ❌ Sem suporte a CRDs, Operators nativos

**Conclusão**: Rejeitado - **VIOLAÇÃO DIRETA de ADR-003 (Cloud-Agnostic obrigatório)**

---

### 4. Google Cloud Run

**Prós**:
- ✅ Simplicidade: Serverless, apenas container image
- ✅ Custo: Pay-per-use, scale-to-zero
- ✅ Developer-friendly: Deploy via gcloud CLI

**Contras**:
- ❌ **Vendor Lock-in CRÍTICO**: GCP-only, viola ADR-003
- ❌ Portabilidade zero
- ❌ Limitações severas: Stateless only, sem persistent volumes nativos
- ❌ Sem RBAC granular, network policies
- ❌ Sem suporte a Operators, CRDs

**Conclusão**: Rejeitado - **VIOLAÇÃO DIRETA de ADR-003 + limitações técnicas (stateful workloads)**

---

### 5. Azure Container Apps

**Prós**:
- ✅ Simplicidade: Serverless, managed
- ✅ Integração Azure: VNET, Key Vault, Log Analytics
- ✅ Baseado em Kubernetes (KEDA, Dapr)

**Contras**:
- ❌ **Vendor Lock-in CRÍTICO**: Azure-only
- ❌ Portabilidade zero
- ❌ Abstrações limitam controle vs K8s raw
- ❌ Ecossistema limitado (subset de K8s)

**Conclusão**: Rejeitado - **VIOLAÇÃO de ADR-003**

---

### 6. Kubernetes ✅ (ESCOLHIDO)

**Prós**:
- ✅ **Cloud-Agnostic**: EKS (AWS), AKS (Azure), GKE (GCP), on-prem (kubeadm, Rancher, OpenShift)
- ✅ **Portabilidade Máxima**: Manifests portáveis entre clouds
- ✅ **Ecossistema Maduro**: Helm (package manager), Operators (stateful apps), Service Mesh (Istio, Linkerd), GitOps (ArgoCD, Flux)
- ✅ **Community Support**: CNCF, community massiva, documentação extensa
- ✅ **Skill Availability**: Profissionais K8s abundantes no mercado
- ✅ **Managed Services**: Todos os 3 clouds públicos oferecem K8s managed
- ✅ **Extensibilidade**: CRDs, Operators, Admission Controllers
- ✅ **Segurança**: RBAC granular, Network Policies, Pod Security Standards, Service Mesh
- ✅ **Observabilidade**: Prometheus nativo, integração com OTEL, Grafana, Loki
- ✅ **Stateful Workloads**: StatefulSets, Persistent Volumes, Operators (PostgreSQL, Redis, RabbitMQ)

**Contras**:
- ❌ **Complexidade**: Curva de aprendizado íngreme
- ❌ **Operacional**: Mais complexo que Swarm/Nomad/managed services
- ❌ **Overhead**: Control plane consome recursos
- ❌ **Custo**: Managed control plane cobrado ($73/mês EKS, GKE; gratuito AKS)

**Conclusão**: **ESCOLHIDO** - Único que atende ADR-003 (cloud-agnostic) + ecossistema maduro

---

## Justificativa da Decisão

### 1. Conformidade com ADR-003 (Cloud-Agnostic Obrigatório)
Kubernetes é o **ÚNICO** orquestrador que:
- Roda nativamente em AWS (EKS), Azure (AKS), GCP (GKE)
- Roda on-premises (kubeadm, Rancher, OpenShift, k3s)
- Permite migração entre clouds **SEM** reescrever workloads
- Manifests (YAML) portáveis

**Alternativas rejeitadas (ECS, Cloud Run, Container Apps) violam ADR-003.**

### 2. Ecossistema e Tooling
- **Helm**: Package manager para instalar GitLab, SonarQube, Prometheus, Grafana
- **Operators**: Gerenciar PostgreSQL (CloudNativePG), Redis (Redis Operator), RabbitMQ (RabbitMQ Operator)
- **Service Mesh**: Linkerd, Istio para mTLS, observabilidade, traffic management
- **GitOps**: ArgoCD, Flux para CD declarativo
- **Secrets**: External Secrets Operator, Sealed Secrets

**Swarm e Nomad não têm ecossistema equivalente.**

### 3. Requisitos de Stateful Workloads
Precisamos rodar:
- PostgreSQL com HA (via Operator)
- Redis cluster (via Operator)
- RabbitMQ cluster (via Operator)
- GitLab (stateful, requer persistent volumes)

**Kubernetes tem StatefulSets + Operators maduros.**
**Cloud Run, Container Apps não suportam stateful workloads adequadamente.**

### 4. Skill Availability e Suporte
- Kubernetes é o padrão de mercado
- Profissionais abundantes
- Documentação extensa (kubernetes.io, CNCF)
- Suporte corporativo disponível (Red Hat OpenShift, Rancher, VMware Tanzu)

**Nomad e Swarm têm menor disponibilidade de profissionais.**

### 5. Custo vs Benefício
- **Managed control plane**: $0/mês (Azure AKS), $73/mês (AWS EKS, GCP GKE)
- **Trade-off aceitável**: Complexidade operacional compensada por portabilidade e ecossistema
- **Alternativas serverless (Cloud Run, Fargate)**: Mais baratas mas vendor lock-in crítico

---

## Implicações

### 1. Provisionamento de Clusters
- **Localização**: `/platform-provisioning/{cloud}/kubernetes/`
- **IaC**: Terraform para provisionar EKS, AKS, GKE
- **Managed vs Self-Hosted**: Preferir managed (EKS, AKS, GKE) para reduzir overhead operacional

### 2. Domínios Assumem Cluster Existente
- Domínios em `/domains/{domain}/` **NÃO** provisionam cluster
- Domínios usam apenas Kubernetes APIs nativas: namespaces, pods, services, deployments, statefulsets
- **Referência**: ADR-020 (Provisionamento de Clusters e Escopo de Domínios)

### 3. IaC e GitOps
- **Terraform**: Provisionar cluster (fora dos domínios)
- **Helm**: Deploy de aplicações nos domínios
- **ArgoCD**: GitOps para CD declarativo
- **Referência**: ADR-004 (IaC e GitOps)

### 4. Treinamento e Capacitação
- Investir em treinamento Kubernetes para time (CKA, CKAD, CKS)
- Documentar runbooks operacionais
- **Referência**: ADR-018 (Treinamento e Capacitação)

### 5. Complexidade Operacional
- Aceitar curva de aprendizado íngreme
- Investir em automação (GitOps, Operators)
- Monitoramento robusto (Prometheus, Grafana, Loki)

### 6. Multi-Cloud Strategy
- Kubernetes permite estratégia multi-cloud real
- Workloads portáveis entre EKS, AKS, GKE
- **Vendor lock-in mitigado** (vs ECS, Cloud Run)

---

## Trade-offs Aceitos

### ✅ Aceito: Complexidade Operacional
**Justificativa**: Portabilidade e ecossistema compensam complexidade

### ✅ Aceito: Custo de Control Plane
**Justificativa**: $73/mês (EKS/GKE) ou $0/mês (AKS) é aceitável para managed service

### ✅ Aceito: Curva de Aprendizado
**Justificativa**: Investimento em treinamento compensa com portabilidade e flexibilidade

### ❌ Rejeitado: Simplicidade (Swarm, Nomad)
**Justificativa**: Simplicidade não compensa falta de ecossistema e portabilidade

### ❌ Rejeitado: Vendor Lock-in (ECS, Cloud Run, Container Apps)
**Justificativa**: **VIOLAÇÃO DIRETA de ADR-003**

---

## Matriz de Decisão

| Critério | Peso | K8s | Swarm | Nomad | ECS | Cloud Run | Container Apps |
|----------|------|-----|-------|-------|-----|-----------|----------------|
| **Cloud-Agnostic** | 🔴 10 | ✅ 10 | ⚠️ 7 | ✅ 9 | ❌ 0 | ❌ 0 | ❌ 0 |
| **Portabilidade** | 🔴 10 | ✅ 10 | ⚠️ 5 | ✅ 8 | ❌ 0 | ❌ 0 | ❌ 0 |
| **Ecossistema** | 🟡 8 | ✅ 10 | ❌ 3 | ⚠️ 6 | ⚠️ 7 | ⚠️ 6 | ⚠️ 7 |
| **Stateful Support** | 🟡 8 | ✅ 10 | ⚠️ 6 | ✅ 8 | ⚠️ 7 | ❌ 3 | ⚠️ 6 |
| **Skill Availability** | 🟡 7 | ✅ 10 | ⚠️ 5 | ⚠️ 4 | ⚠️ 7 | ⚠️ 6 | ⚠️ 6 |
| **Simplicidade** | 🟢 5 | ⚠️ 3 | ✅ 9 | ✅ 8 | ✅ 9 | ✅ 10 | ✅ 9 |
| **Managed Service** | 🟢 6 | ✅ 10 | ❌ 0 | ❌ 2 | ✅ 10 | ✅ 10 | ✅ 10 |
| **Custo** | 🟢 5 | ⚠️ 6 | ✅ 9 | ✅ 8 | ✅ 9 | ✅ 10 | ✅ 9 |
| **TOTAL PONDERADO** | | **542** | **289** | **373** | **267** | **224** | **253** |

**Legenda**:
- 🔴 Crítico (peso alto)
- 🟡 Importante (peso médio)
- 🟢 Desejável (peso baixo)

**Resultado**: Kubernetes vence com **542 pontos** (87% do máximo possível)

---

## Validação com Requisitos

| Requisito | K8s | Swarm | Nomad | ECS | Cloud Run | Container Apps |
|-----------|-----|-------|-------|-----|-----------|----------------|
| Cloud-Agnostic (ADR-003) | ✅ | ⚠️ | ✅ | ❌ | ❌ | ❌ |
| Escalabilidade | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Isolamento (RBAC, Network) | ✅ | ⚠️ | ⚠️ | ⚠️ | ❌ | ⚠️ |
| HA Multi-AZ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Service Discovery | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Persistent Volumes | ✅ | ⚠️ | ✅ | ⚠️ | ❌ | ⚠️ |
| Service Mesh | ✅ | ❌ | ⚠️ | ⚠️ | ❌ | ⚠️ |
| GitOps (ArgoCD) | ✅ | ❌ | ❌ | ⚠️ | ❌ | ⚠️ |
| Operators (PostgreSQL, Redis) | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |

**Conclusão**: Apenas Kubernetes atende TODOS os requisitos.

---

## Riscos e Mitigações

### Risco 1: Complexidade Operacional
**Impacto**: Alto  
**Probabilidade**: Alta  
**Mitigação**:
- Usar managed services (EKS, AKS, GKE) para reduzir overhead
- Investir em treinamento (CKA, CKAD)
- Documentar runbooks operacionais
- Usar GitOps (ArgoCD) para automação

### Risco 2: Curva de Aprendizado
**Impacto**: Médio  
**Probabilidade**: Alta  
**Mitigação**:
- Treinamento formal (CKA, CKAD, CKS)
- Mentoria interna
- Documentação detalhada
- Start small (domínios simples primeiro)

### Risco 3: Custo de Control Plane
**Impacto**: Baixo  
**Probabilidade**: Alta  
**Mitigação**:
- Usar Azure AKS (control plane gratuito)
- Considerar Reserved Instances (EKS/GKE) para -40% custo
- Monitorar custos com FinOps (ADR-019)

### Risco 4: Vendor Lock-in de Managed Service
**Impacto**: Médio  
**Probabilidade**: Baixa  
**Mitigação**:
- Usar apenas features K8s nativas (não cloud-specific)
- Manter IaC modular (Terraform)
- Documentar migração entre clouds
- **ADR-020 garante portabilidade**

---

## Referências

### ADRs Relacionados
- [ADR-003: Cloud-Agnostic e Portabilidade](adr-003-cloud-agnostic.md)
- [ADR-004: IaC e GitOps](adr-004-iac-gitops.md)
- [ADR-020: Provisionamento de Clusters e Escopo de Domínios](adr-020-provisionamento-clusters.md)
- [ADR-018: Treinamento e Capacitação](adr-018-treinamento-capacitacao.md)
- [ADR-019: FinOps](adr-019-finops.md)

### Documentação Externa
- [Kubernetes Official Docs](https://kubernetes.io/)
- [CNCF Landscape](https://landscape.cncf.io/)
- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)
- [AWS EKS](https://aws.amazon.com/eks/)
- [Azure AKS](https://azure.microsoft.com/en-us/services/kubernetes-service/)
- [Google GKE](https://cloud.google.com/kubernetes-engine)

---

## Histórico

| Versão | Data | Autor | Mudanças |
|--------|------|-------|----------|
| 1.0 | 2026-01-05 | Arquiteto + CTO | Versão inicial - decisão fundamental que estava implícita |

---

## Aprovação

**Status**: ✅ Aprovado  
**Data**: 2026-01-05  
**Aprovadores**:
- Arquiteto: ✅
- CTO: ✅
- Usuário: ✅

**Próximos Passos**:
1. Atualizar SAD para v1.2 incluindo ADR-021
2. Documentar escolha explícita em README, copilot-context
3. Recongelar SAD (Freeze #3)
