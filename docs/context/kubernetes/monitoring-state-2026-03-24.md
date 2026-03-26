# Monitoring State — k8s-platform (staging + prod)
**Data**: 2026-03-24
**Orquestrador**: Monitoring Orchestrator v1
**Sessão iniciada**: 2026-03-24T23:12 UTC (aprox)
**Método de diagnóstico**: kubectl + aws CLI (profile k8s-platform-prod)

---

## Status de Autenticação

| Sistema | Estado | Observação |
|---------|--------|------------|
| AWS SSO | EXPIRADO — aguardando renovação | Tokens expirados em 2026-03-24T22:07:52Z |
| kubectl (prod) | BLOQUEADO — depende de AWS SSO | Context: arn:aws:eks:us-east-1:891377105802:cluster/k8s-platform-prod |
| kubectl (staging) | BLOQUEADO — depende de AWS SSO | Context: k8s-platform-staging |

**Ação em andamento**: Device authorization flow iniciado — URL: `https://d-906621cd5f.awsapps.com/start/#/device?user_code=NZMC-FZHZ`

---

## Estado Inicial Construído (baseline 2026-03-21)

### Componentes Esperados

| Componente | Namespace | Esperado | Último estado conhecido (2026-03-21) |
|---|---|---|---|
| Backstage | staging-platform-backstage | 2/2 Running | v1.48.0-s6c |
| Harbor staging | staging-data-harbor | 7/7 Running | Recreate strategy fix |
| Harbor prod | prod-platform-harbor | 8/8 Running | ExternalSecret fix |
| Linkerd | linkerd | 3/3 Running | Recreate strategy fix |
| linkerd-viz | linkerd-viz | 4/4 Running | restarts decrescentes |
| Calico | calico-system | 15/15 Running | ECR mirror |
| ESO Controller | kube-system ou dedicated | 1/1 Running | v0.9.11 |
| SonarQube | staging-platform-sonarqube | 1/1 Running | — |
| Tempo staging | staging-observability-monitoring | 6+ Running | labels Kyverno fix |
| Tempo prod | production | 5 Running | — |
| External-DNS staging | external-dns | 1/1 Running | chart kubernetes-sigs |
| Velero | kube-system | 1 server + 15 node-agents | — |
| GitLab Runner | staging-platform-gitlab | Running | — |
| Hatch ETL | staging-data-hatch | HOLD intencional | replicas=0, ETL_AUTO_RUN=false |
| vault-prod-0 | prod-security-vault | **ALERTA P1** | Pending 13h — vol-065f3b18bebee9fc0 |

### GAPs Conhecidos Pré-Monitoramento

| GAP ID | Descrição | Prioridade | Status |
|--------|-----------|------------|--------|
| GAP-VAULT-PROD-PENDING | vault-prod-0 Pending 13h — EBS vol-065f3b18bebee9fc0 aguarda reattach | **P1** | INVESTIGANDO |
| GAP-FINOPS-ACCESS-ENTRY | EKS auth mode CONFIG_MAP (precisa API_AND_CONFIG_MAP) | P2 | CONHECIDO |
| GAP-LOKI-CANARY-AFFINITY | 1 pod loki-canary Pending por NodeAffinity | P3 | CONHECIDO |
| GAP-KYVERNO-POLICY-SPAM | validate-service-naming gera eventos spam prometheus-operated | P3 | CONHECIDO |
| GAP-LAMBDA-FP-01 | Lambda detector não filtra PV Bound — falsos positivos EBS | P3 | CONHECIDO |

---

## Fase 1 — Detecção (PENDENTE — aguarda autenticação AWS)

### Queries Planejadas

```bash
# PROD context
kubectl --context arn:aws:eks:us-east-1:891377105802:cluster/k8s-platform-prod \
  get pods -A --field-selector=status.phase!=Running -o wide

# vault-prod-0 investigation (P1)
kubectl -n prod-security-vault describe pod vault-prod-0
kubectl -n prod-security-vault get pvc
kubectl -n prod-security-vault describe pvc

# Node status
kubectl get nodes -o wide

# All pods summary
kubectl get pods -A -o wide | grep -v Running | grep -v Completed

# STAGING context
kubectl --context k8s-platform-staging get pods -A --field-selector=status.phase!=Running -o wide

# EBS volume status
aws ec2 describe-volumes --volume-ids vol-065f3b18bebee9fc0 \
  --profile k8s-platform-prod --region us-east-1
```

---

## Incidentes Detectados (PRÉ-INVESTIGAÇÃO)

### INC-001 — vault-prod-0 Pending P1

**Descrição**: Pod vault-prod-0 no namespace prod-security-vault em estado Pending há 13h.
O volume EBS vol-065f3b18bebee9fc0 aguarda reattach.

**Impacto potencial**:
- Vault prod com capacidade reduzida (sem HA completo)
- ExternalSecrets que dependem do Vault prod podem estar degradados
- Serviços prod que usam secrets via ESO podem ter problemas de renovação

**Diagnóstico necessário**:
1. Estado atual do pod (pode ter recuperado desde 2026-03-21)
2. Estado do PVC/PV associado
3. Estado do volume EBS na AWS
4. Nó onde estava agendado vs nó disponível

**Hipóteses de causa**:
- Node onde o volume estava attached foi removido/substituído (FinOps down/up cycle)
- Volume EBS em estado "in-use" por nó que não existe mais (multi-attach não habilitado)
- AZ mismatch entre volume EBS e nodes disponíveis

---

## Próximas Ações

1. [BLOQUEADO] Completar autenticação AWS SSO
2. [BLOQUEADO] Executar Fase 1 — kubectl diagnostics completos
3. [PENDENTE] Investigar vault-prod-0 (P1)
4. [PENDENTE] Gerar relatório de status completo
5. [PENDENTE] Orquestrar agentes de remediação se necessário

---

## Log de Sessão

| Timestamp | Ação | Resultado |
|-----------|------|-----------|
| 2026-03-25T02:12 UTC | update-kubeconfig staging + prod | FALHOU — SSO expirado |
| 2026-03-25T02:14 UTC | aws sso login --profile k8s-platform-prod | Aguardando browser (WSL2 sem browser) |
| 2026-03-25T02:15 UTC | Device auth flow iniciado (JNDR-XLTG) | Timeout sem resposta do usuário |
| 2026-03-25T02:20 UTC | Novo device auth (NZMC-FZHZ) | Aguardando resposta do usuário |
| 2026-03-25T02:25 UTC | Estrutura de documentação criada | OK |
