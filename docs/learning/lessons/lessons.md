# Lições Aprendidas — Kubernetes Platform

> Este arquivo é atualizado automaticamente pelo sistema de aprendizagem.
> Lições são extraídas após tasks com problemas (retries, refactoring, erros recorrentes).

---

## Como Funciona

O sistema analisa cada task executada e identifica sinais de aprendizagem:

**Sinais**:
- Task precisou de retry
- Diff desproporcional (muito código para escopo simples)
- Refatoração imediata após implementação
- Mesmo erro > 2 vezes
- Feedback negativo do usuário
- Feedback positivo do usuário (reforço)

**Severity**:
- 🔴 **Critical**: Nunca perdem peso, sempre aplicadas
- 🟡 **Warning**: Aplicadas quando relevante
- 🔵 **Info**: Reforço positivo ou dicas

**Decay**:
- Lições perdem peso se não forem aplicadas
- Após 20 execuções sem uso → arquivadas (peso 0.2)
- Exceções: Critical, Pinned pelo usuário, originadas de feedback negativo

---

## Critical

_Nenhuma lição crítica registrada ainda._

---

## Warnings

_Nenhuma warning registrada ainda._

---

## Info

_Nenhuma info registrada ainda._

---

## Estatísticas

| Métrica            | Valor      |
| ------------------ | ---------- |
| Total de lições    | 0          |
| Critical           | 0          |
| Warnings           | 0          |
| Info               | 0          |
| Arquivadas         | 0          |
| Última atualização | 2026-02-06 |

---

_Este arquivo é gerado automaticamente. Para adicionar lições manualmente, inclua na seção "Pinned" do perfil do agente em `docs/learning/agents/{agente}.md`._
