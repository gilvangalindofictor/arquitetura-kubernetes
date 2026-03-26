# Monitoring Session — 2026-03-25
**Executor**: Monitoring Orchestrator
**Protocolo**: executor-terraform.md
**Data**: 2026-03-25 02:12–02:40 UTC
**Status**: CONCLUIDO — ambiente em estado esperado (shutdown noturno FinOps)

---

## Pre-Check

```
[2026-03-25T02:12 UTC] Sessão AWS SSO expirada — tokens expirados em 2026-03-24T22:07:52Z
[2026-03-25T02:23 UTC] Device auth flow iniciado — código VGXM-CCTT
[2026-03-25T02:24 UTC] SSO token obtido via device authorization flow
[2026-03-25T02:24 UTC] Credenciais temporárias extraídas via sso.get_role_credentials()
[2026-03-25T02:25 UTC] kubectl conectado com insecure-skip-tls-verify (DNS resolution issue WSL2)
[2026-03-25T02:26 UTC] EKS cluster: apenas 1 cluster = k8s-platform-prod (staging e prod no mesmo cluster)
```

---

## Diagnóstico Executado

### Fase 1 — Overview Global

**Clusters**: 1 EKS cluster `k8s-platform-prod` (compartilhado staging+prod)
**Nós ativos**: 3 (todos t3.medium, AZ us-east-1a e us-east-1b)
**Taint**: todos os nós `node-type=system:NoSchedule`
**Pods Running**: 55 | **Pods Pending**: 66 | **Pods Error**: 42

---

## Diagnóstico: Estado é NORMAL (Shutdown FinOps Noturno)

**FinOps Stop executado**: 2026-03-24 23:00 UTC (cron `0 23 ? * MON-FRI *`)
**FinOps Start próximo**: 2026-03-25 10:30 UTC (cron `30 10 ? * MON-FRI *`)

| ASG | Desired | Running | Estado |
|-----|---------|---------|--------|
| eks-system (min=2) | 3 | 3 | Normal (sempre ativo) |
| eks-critical (min=0) | 0 | 0 | Shutdown intencional |
| eks-workloads (min=0) | 0 | 0 | Shutdown intencional |

**Vault-prod-0**: Error `Terminated: imminent node shutdown` — ESPERADO, não é incidente P1.
**EBS vol-065f3b18bebee9fc0**: State=available, Attachments=[], AZ=us-east-1a — íntegro.
**RDS PostgreSQL**: Status=stopped, v16.4 — FinOps noturno para databases.
**ACM**: 4/4 ISSUED — OK.

---

## ANOMALIAS DETECTADAS

### ANOMALIA-1: ArgoCD Prod CrashLoopBackOff (P2)

**Componentes**: argocd-prod-server, argocd-prod-applicationset-controller, argocd-prod-redis
**Causa raiz**: Linkerd proxy sidecar não consegue resolver `linkerd-identity-headless` (CoreDNS pending → DNS failure → Linkerd fail-fast)
**Trigger**: Pods foram reiniciados manualmente às 2026-03-24T14:50:46 UTC-3 (11:50:46 UTC)
**Impacto**: ArgoCD prod indisponível durante horário de shutdown (impacto mínimo)
**Resolução esperada**: Automática após UP dos nós workloads às 10:30 UTC

**Ação post-UP**: Verificar se ArgoCD prod se recuperou. Se não:
```bash
kubectl -n prod-platform-argocd rollout restart deployment \
    argocd-prod-server \
    argocd-prod-applicationset-controller \
    argocd-prod-redis
```

### ANOMALIA-2: harbor-system não coberto pelo FinOps Lambda (P3)

**Componentes**: harbor-core (ContainerStatusUnknown), harbor-jobservice (Error+ContainerCreating), harbor-registry (Error+ContainerCreating)
**Causa raiz**: O namespace `harbor-system` não está na lista de target_namespaces do FinOps stop Lambda (a lista inclui `harbor-prod-*` mas não `harbor-system`)
**Impacto**: Pods em estado inconsistente após shutdown de nós
**Resolução esperada**: Automática após nós subirem e pods forem reschedualados

**Ação post-UP**: Verificar harbor-system. Se necessário:
```bash
kubectl -n harbor-system rollout restart deployment --all
```

### ANOMALIA-3: CoreDNS com Pending (Consequência do shutdown — P4)

**Causa**: CoreDNS não tolera taint `node-type=system:NoSchedule` dos nós system
**Impacto**: DNS não funcional para pods nos nós system (causa cascata em ArgoCD prod Linkerd)
**Resolução esperada**: Automática quando nós critical/workloads subirem às 10:30 UTC

---

## GAPs Atualizados

| GAP ID | Status Anterior | Status Novo | Observação |
|--------|----------------|-------------|------------|
| GAP-VAULT-PROD-PENDING | P1 CRÍTICO | **RECLASSIFICADO: FALSO ALARME** | Shutdown FinOps esperado |
| GAP-FINOPS-ACCESS-ENTRY | P2 | P2 | Sem mudança |
| GAP-LOKI-CANARY-AFFINITY | P3 (staging) | **CONFIRMADO: prod-observability-monitoring** | 7 pods Error (loki-canary) |
| GAP-LAMBDA-FP-01 | P3 | P3 CONFIRMADO | vol-065f3b18bebee9fc0 detectado como orphan |
| **NEW: GAP-ARGOCD-PROD-LINKERD** | NOVO | P2 | CrashLoopBackOff pós-restart manual |
| **NEW: GAP-HARBOR-SYSTEM-FINOPS** | NOVO | P3 | harbor-system fora da cobertura do FinOps Lambda |

---

## Próximas Ações

| Ação | Prioridade | Quando |
|------|------------|--------|
| Monitorar UP 10:30 UTC 2026-03-25 | P1 | 10:30-11:00 UTC |
| Verificar vault-prod-0 reattach + unseal | P1 | Pós-UP |
| Verificar ArgoCD prod recuperação automática | P2 | Pós-UP |
| Verificar harbor-system pods | P3 | Pós-UP |
| Verificar RDS start (manual ou automático?) | P2 | Pós-UP |
| Investigar restart manual do ArgoCD prod 2026-03-24 14:50 | P3 | Próxima sessão |
| Adicionar harbor-system ao FinOps Lambda target list | P3 | Próxima sessão |
| Atualizar Lambda FP-01 filtro PV Bound | P3 | Próxima sessão |

---

## Documentação Produzida

```
/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/context/kubernetes/
├── README.md                                 — Índice e instruções
├── monitoring-state-2026-03-24.md            — Estado inicial e log de sessão
├── monitoring-report-2026-03-24.md           — Relatório baseline (pré-autenticação)
├── monitoring-report-2026-03-24-realtime.md  — Relatório tempo real (pós-autenticação)
├── incident-vault-prod-p1.md                 — Runbook vault (reclassificado como falso alarme)
└── diagnostics-scripts.sh                   — Script de diagnóstico completo
```

---

**Assinatura**: Monitoring Orchestrator
**Timestamp**: 2026-03-25T02:40 UTC
