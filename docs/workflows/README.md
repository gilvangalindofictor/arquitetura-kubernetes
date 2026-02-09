# Workflows - Marco 4 CI/CD Platform

**Status**: 🟢 Preparados para execução
**Data**: 2026-02-06

---

## 📋 Índice de Workflows

### Workflows Disponíveis

| GAP | Nome | Status | Duração | Custo | Prompt |
|-----|------|--------|---------|-------|--------|
| GAP-003 | ArgoCD Deploy | 🟢 Ready | 2h | +$15/mês | [gap-003-argocd-deployment-prompt.md](gap-003-argocd-deployment-prompt.md) |
| GAP-004 | SonarQube Deploy | 🟢 Ready | 2h | +$50/mês | [gap-004-sonarqube-deployment-prompt.md](gap-004-sonarqube-deployment-prompt.md) |
| GAP-005 | GitLab CI/CD Integration | 🟢 Ready | 3h | $0 | [gap-005-gitlab-cicd-integration-prompt.md](gap-005-gitlab-cicd-integration-prompt.md) |

**Total Estimado**: 7h | +$65/mês

---

## 🎯 Ordem de Execução Recomendada

### Sprint 2: Core CI/CD Components (4h)

**Execução Paralela** (pode rodar simultaneamente):

1. **GAP-003: ArgoCD** (2h)
   - ✅ Pré-requisito: GAP-001 (Keycloak) ✅ completo
   - Deploy ArgoCD com OIDC Keycloak
   - GitOps platform ready

2. **GAP-004: SonarQube** (2h)
   - ✅ Pré-requisito: GAP-001 (Keycloak) ✅ completo
   - Deploy SonarQube com OIDC Keycloak
   - Code quality analysis ready

### Sprint 3: Pipeline Integration (3h)

**Execução Sequencial** (requer GAP-002 + GAP-004):

3. **GAP-005: GitLab CI/CD** (3h)
   - ⏸️ Pré-requisito: GAP-002 (GitLab Fix) - pendente
   - ✅ Pré-requisito: GAP-004 (SonarQube) - pode iniciar após conclusão
   - Integração completa: build → test → scan → deploy

---

## 🚀 Como Usar os Workflows

### Passo 1: Escolher GAP

```bash
# Escolha qual GAP executar
GAP=gap-003  # ou gap-004, gap-005
```

### Passo 2: Ler Prompt

```bash
# Abrir arquivo do prompt
cat docs/workflows/${GAP}-*-prompt.md
```

### Passo 3: Executar com Agente

**Opção A: Copiar prompt completo**

1. Abra o arquivo do prompt
2. Copie todo o conteúdo da seção "Prompt para o Agente"
3. Cole no chat do agente DevOps
4. Agente executará autonomamente

**Opção B: Usar como referência**

1. Abra o prompt como guia
2. Execute manualmente seguindo os passos
3. Use comandos úteis como referência
4. Valide com critérios de sucesso

### Passo 4: Validação

Ao final, verificar todos critérios de sucesso marcados ✅

---

## 📚 Estrutura dos Prompts

Cada prompt contém:

### 1. Contexto
- Estado atual da plataforma
- Pré-requisitos verificados
- Recursos disponíveis

### 2. Objetivo
- O que será implementado
- Por que é necessário

### 3. Requisitos Técnicos
- Database bootstrap
- Vault secrets
- Terraform module
- Configuration
- Integração

### 4. Entregáveis
- Scripts
- Código Terraform
- Manifests K8s
- Documentação
- Validação

### 5. Constraints
- Padrões obrigatórios
- Limitações técnicas
- Segurança

### 6. Workflow
- Passo a passo detalhado
- 10-15 etapas numeradas
- Ordem de execução

### 7. Critérios de Sucesso
- Checklist de validação
- Condições obrigatórias

### 8. Comandos Úteis
- Scripts prontos para uso
- Validações
- Troubleshooting

### 9. Referências
- Links para documentos relacionados
- Exemplos anteriores
- ADRs relevantes

---

## 🎯 Padrões Aplicados

Todos os workflows seguem os mesmos padrões estabelecidos no GAP-001 (Keycloak):

### 1. Database Bootstrap
- Script bash reutilizável
- Mesmo padrão keycloak/bootstrap-database.sh
- Gera senha aleatória (openssl rand)
- Valida conexão

### 2. Vault Integration
- Paths: `secret/<service>/*`
- KV v2 engine
- ExternalSecret CRDs
- ClusterSecretStore: vault-backend

### 3. Terraform Module
- main.tf, variables.tf, outputs.tf
- values.yaml.tpl (Helm)
- manifests/ (K8s CRDs)
- README.md completo

### 4. Keycloak OIDC
- OIDC client já criado (GAP-001)
- Client secret em K8s secret
- Issuer URL padrão
- RBAC via groups

### 5. Documentação
- Logbook detalhado
- ADR atualizado
- README com Known Issues
- demands-backlog.md atualizado

---

## ⚠️ Issues Conhecidos (Keycloak)

Aprendizados do GAP-001 aplicados aos workflows:

### 1. Vault Permissions Issue
**Workaround**: Se Vault root token retornar 403, criar K8s secrets diretos temporariamente

### 2. Probe Timeouts
**Workaround**: Ajustar initialDelaySeconds e failureThreshold para apps lentos (SonarQube ~5min)

### 3. ExternalSecret Wrong Value
**Workaround**: Validar Vault secret value antes de criar ExternalSecret, ou usar K8s secret direto

### 4. HA Issues
**Workaround**: Iniciar com 1 replica, escalar após validação funcional

---

## 🔄 Dependências Entre GAPs

```
┌─────────────┐
│  GAP-001    │ ✅ COMPLETO
│  Keycloak   │
└──────┬──────┘
       │
       ├──────────────┬──────────────┐
       │              │              │
       ▼              ▼              ▼
┌──────────┐   ┌──────────┐   ┌──────────┐
│ GAP-003  │   │ GAP-004  │   │ GAP-002  │
│ ArgoCD   │   │SonarQube │   │GitLab Fix│
└──────────┘   └─────┬────┘   └─────┬────┘
                     │              │
                     └──────┬───────┘
                            │
                            ▼
                     ┌──────────┐
                     │ GAP-005  │
                     │GitLab CI │
                     └──────────┘
```

**Execução Possível**:

- **Paralelo**: GAP-003 + GAP-004 (ambos dependem só de GAP-001)
- **Sequencial**: GAP-005 (depende de GAP-002 + GAP-004)

---

## 📊 Progresso Marco 4

### Status Atual

| Item | Status | Duração | Custo |
|------|--------|---------|-------|
| ✅ GAP-001: Keycloak | ✅ Completo | 6h | +$35/mês |
| 🟢 GAP-003: ArgoCD | Ready | 2h | +$15/mês |
| 🟢 GAP-004: SonarQube | Ready | 2h | +$50/mês |
| ⏸️ GAP-002: GitLab Fix | Pendente | 2-4h | $0 |
| ⏸️ GAP-005: GitLab CI | Bloqueado | 3h | $0 |

**Completude Marco 4**: 20% (1/5 GAPs)

### Próxima Ação

**Recomendado**: Executar GAP-003 e GAP-004 em paralelo (4h total)

```bash
# Terminal 1
# Executar GAP-003 (ArgoCD)

# Terminal 2
# Executar GAP-004 (SonarQube)
```

---

## 🛠️ Ferramentas Necessárias

Para executar os workflows, garanta que as ferramentas estão disponíveis:

- ✅ kubectl (1.24+)
- ✅ terraform (1.0+)
- ✅ helm (3.0+)
- ✅ aws-cli (2.x)
- ✅ psql (PostgreSQL client)
- ✅ jq (JSON processor)
- ⚠️ argocd CLI (para GAP-003)
- ⚠️ sonar-scanner CLI (para GAP-005)

---

## 📖 Documentação Relacionada

- [Demands Backlog](../demands-backlog.md) - Todas as demandas Marco 4
- [Keycloak Deployment](../logbook/2026-02-06-keycloak-sso-deployment.md) - Referência de execução
- [ADR-046: Keycloak SSO](../adr/adr-046-keycloak-sso-strategy.md) - Decisões arquiteturais
- [Bootstrap Guide](../../platform-provisioning/aws/kubernetes/terraform/scripts/keycloak/BOOTSTRAP_GUIDE.md) - Padrão de bootstrap

---

## 💡 Dicas de Execução

### 1. Preparação
- Ler prompt completo antes de iniciar
- Verificar pré-requisitos
- Preparar ambiente (terminal, ferramentas)

### 2. Execução
- Seguir workflow passo a passo
- Documentar desvios/workarounds
- Validar cada etapa antes de avançar

### 3. Troubleshooting
- Consultar seção "TROUBLESHOOTING COMUM" no prompt
- Revisar logs Kubernetes
- Comparar com Keycloak deployment (referência)

### 4. Documentação
- Criar logbook ao final
- Atualizar demands-backlog.md
- Documentar Known Issues

---

## 🎓 Aprendizado Contínuo

Cada deployment adiciona conhecimento à base:

- **GAP-001 (Keycloak)**: Estabeleceu padrões e workarounds
- **GAP-003 (ArgoCD)**: OIDC integration, RBAC patterns
- **GAP-004 (SonarQube)**: Persistent storage, slow startup
- **GAP-005 (GitLab CI)**: Pipeline templates, integrations

**Princípio**: Cada issue resolvido → documentado → evitado nos próximos

---

_Última atualização: 2026-02-06_
