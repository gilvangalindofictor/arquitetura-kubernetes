# Demanda: Harbor Helm Values Drift + Auditoria Linkerd Annotations

**Data**: 2026-03-17
**Prioridade**: P2
**Tipo**: Platform Reliability
**Componentes afetados**: harbor-system, linkerd
**Origem**: Mesa Técnica — Sessão de Health Check 2026-03-17
**Status**: BACKLOG
**Arquivo**: `docs/demands/2026-03-17-harbor-helm-linkerd-audit.md`

---

## 1. Contexto e Motivação

Durante a sessão de health check de 2026-03-17, o componente `harbor-jobservice` entrou em
`CrashLoopBackOff` com 32 restarts após um `rollout restart` executado às 09:50 BRT.

A investigação revelou que a annotation `config.linkerd.io/skip-outbound-ports: "80"` era
necessária para o funcionamento correto do harbor-jobservice com o service mesh Linkerd. Essa
annotation estava presente no Deployment em execução no cluster, mas **não estava registrada nos
Helm values** do chart Harbor.

O `rollout restart` recria o pod a partir dos Helm values atuais. Como a annotation não estava
nos values, ela foi perdida no restart, causando falha de conectividade via Linkerd e o consequente
CrashLoopBackOff.

Um fix manual foi aplicado: a annotation foi restaurada no Deployment e um `helm upgrade` foi
executado para persistir a configuração nos values. O incidente foi mitigado, mas o problema
estrutural permanece: outros componentes Harbor e da plataforma podem ter annotations Linkerd
críticas presentes apenas nos Deployments, criando risco latente de regressão a cada restart ou
upgrade.

Além disso, foi identificado um segundo drift: a estratégia de deployment do `harbor-jobservice`
está configurada como `Recreate` nos Helm values, enquanto o Deployment atual no cluster mostra
`RollingUpdate`. Essa divergência indica que o estado do cluster não reflete os values declarados
— drift de configuração clássico.

---

## 2. Problema Atual

### 2.1 Annotations Linkerd fora dos Helm values

| Sintoma | Impacto |
|---|---|
| Annotation `skip-outbound-ports` presente no Deployment, ausente nos values | Perdida a cada rollout restart ou helm upgrade |
| CrashLoopBackOff 32 restarts em 2026-03-17 09:50 BRT | Downtime harbor-jobservice (~30min) |
| Outros componentes Harbor não auditados | Risco de regressão latente não mapeado |

### 2.2 Drift de estratégia de deployment

| Componente | Values declarado | Deployment atual |
|---|---|---|
| harbor-jobservice | `Recreate` | `RollingUpdate` |

O drift indica que ou os values foram modificados sem `helm upgrade`, ou o `helm upgrade` foi
executado sem os values corretos. Em ambos os casos, o estado real diverge do estado declarado,
violando o princípio de GitOps e dificultando o rastreamento de mudanças.

### 2.3 Ausência de processo preventivo

Não existe auditoria periódica de annotations críticas em Deployments versus Helm values. Não há
mecanismo automatizado que detecte drift de annotations Linkerd antes que ele cause incidentes.

---

## 3. Solução Proposta

### 3.1 Auditoria manual imediata (fase 1)

- Listar todos os Deployments nos namespaces `harbor-system`, `linkerd`, `linkerd-viz` e outros
  namespaces críticos da plataforma.
- Para cada Deployment, extrair annotations Linkerd presentes (`config.linkerd.io/*`).
- Comparar com os Helm values correspondentes (via `helm get values`).
- Gerar relatório de divergências com classificação de criticidade.

### 3.2 Correção do drift harbor-jobservice (fase 2)

- Confirmar qual estratégia é correta: `Recreate` (adequada para jobservice, evita jobs duplicados)
  ou `RollingUpdate`.
- Atualizar os Helm values para refletir o estado desejado.
- Executar `helm upgrade` e validar com `helm diff` + `kubectl get deploy`.
- Garantir que `terraform plan` retorne "No changes" (zero drift IaC).

### 3.3 Padronização de annotations Linkerd nos values (fase 3)

- Adicionar todas as annotations Linkerd identificadas na auditoria aos Helm values do Harbor.
- Documentar quais annotations são obrigatórias por componente e por quê.
- Criar ADR documentando a política de annotations Linkerd na plataforma.

### 3.4 Automação de detecção de drift (fase 4 — opcional)

- Implementar script de auditoria `scripts/audit-linkerd-drift.sh` que compare annotations de
  Deployments live versus Helm values declarados.
- Integrar ao pipeline de CI ou como CronJob no cluster para detecção contínua.
- Alertar via PrometheusRule ou notificação Teams quando drift for detectado.

---

## 4. Artefatos a Criar

| Artefato | Descrição | Fase |
|---|---|---|
| `docs/runbooks/harbor-linkerd-annotations.md` | Runbook com annotations obrigatórias por componente Harbor | 1 |
| `scripts/audit-linkerd-drift.sh` | Script de auditoria annotations Deployments vs Helm values | 1 |
| `docs/adr/adr-XXX-linkerd-annotations-policy.md` | ADR política de annotations Linkerd | 3 |
| Atualização `modules/harbor/values.yaml.tpl` | Adicionar annotations Linkerd corretas | 2+3 |
| `docs/logbook/2026-03-17-harbor-linkerd-incident.md` | Logbook do incidente com RCA | 1 |

---

## 5. Critérios de Aceite

- [ ] Auditoria completa executada: todos os Deployments críticos vs Helm values verificados
- [ ] Relatório de divergências gerado com classificação de criticidade
- [ ] Drift harbor-jobservice strategy (`Recreate` vs `RollingUpdate`) corrigido
- [ ] Annotation `config.linkerd.io/skip-outbound-ports: "80"` presente nos Helm values do harbor-jobservice
- [ ] `helm diff` retorna zero divergências relevantes para harbor-system
- [ ] `rollout restart` no harbor-jobservice não causa CrashLoopBackOff (teste de regressão)
- [ ] ADR criado e aprovado pela Mesa Técnica
- [ ] Logbook do incidente documentado com RCA completo

---

## 6. Riscos e Mitigações

| Risco | Severidade | Probabilidade | Mitigação |
|---|---|---|---|
| Outros componentes Harbor com annotations Linkerd críticas ausentes nos values | Alta | Alta | Auditoria na fase 1 mapeia tudo antes de qualquer mudança |
| Helm upgrade com values incorretos causa novo incidente | Alta | Baixa | Usar `helm diff` antes de qualquer upgrade; testar em janela de manutenção |
| Estratégia Recreate causa downtime do harbor-jobservice durante upgrade | Média | Alta | Agendar upgrade em janela de baixo uso; Recreate é comportamento esperado para jobservice |
| Drift em outros componentes não Harbor descoberto na auditoria | Média | Média | Escopo da auditoria expandido se necessário; abrir demandas derivadas |

---

## 7. Estimativa de Esforço

| Fase | Descrição | Esforço estimado |
|---|---|---|
| Fase 1: Auditoria + logbook | Mapear divergências + documentar incidente | 2h |
| Fase 2: Correção drift strategy | Fix values + helm upgrade + validação | 1h |
| Fase 3: Padronização values | Adicionar annotations aos values + ADR | 2h |
| Fase 4: Automação (opcional) | Script + CronJob + alertas | 4h |
| **Total** | | **5-9h** |

---

## 8. Dependências

- Harbor operacional no namespace `harbor-system` (cluster staging UP)
- Linkerd operacional (destination + identity + proxy-injector Running)
- Acesso aos Helm values do Harbor via `helm get values harbor -n harbor-system`
- Módulo Terraform do Harbor: `modules/harbor/` (para atualizar values.yaml.tpl sem drift IaC)
- Vault operacional (para verificar se há secrets relacionadas à configuração)
- Janela de manutenção acordada para o `helm upgrade` do harbor-system

---

## Histórico de Alterações

| Data | Autor | Alteração |
|---|---|---|
| 2026-03-17 | Mesa Técnica | Criação da demanda a partir do incidente harbor-jobservice CrashLoopBackOff |
