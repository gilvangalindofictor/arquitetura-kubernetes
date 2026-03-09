# ADR-103 — Alertas de Plataforma via Microsoft Teams (nao Slack)

**Data:** 2026-03-06
**Status:** ACEITO
**Contexto:** DT-005

## Contexto

O sistema de alertas Prometheus/Alertmanager foi inicialmente planejado para entregar
notificacoes via Slack (secret `alertmanager-slack-webhook`). Em 2026-03-06, foi decidido
que o canal oficial de comunicacao da plataforma e **Microsoft Teams**.

Estado atual do cluster (confrontacao 2026-03-05):
- 4 PrometheusRules ativas (37 alertas: Infrastructure/Application/Data Services/Security)
- AlertmanagerConfig deployada com receiver configurado para Slack
- Secret `alertmanager-slack-webhook` existe com 4 chaves (critical/warning/data-services/security)
- Todos os 4 valores sao placeholders (`REPLACE`) — alertas nao sao entregues a nenhum destino

## Decisao

Usar **Microsoft Teams Incoming Webhook** como destino dos alertas de plataforma, incluindo:
- Alertas financeiros (WAF, custos, FinOps)
- Alertas operacionais (pod crashes, node pressure, etc.)
- Alertas de seguranca (Vault, certificados)

Nao usar Slack. Nao adquirir licenca ou integracao Slack adicional.

## Implementacao (PENDENTE)

**Pre-requisito:** URL do webhook do canal Teams de alertas (a ser fornecida pela equipe responsavel)

**Mudancas necessarias quando implementar:**
1. Obter URL Incoming Webhook do canal Teams designado para alertas de plataforma
2. Atualizar secret `alertmanager-slack-webhook` com URL real Teams (ou criar novo secret `alertmanager-teams-webhook` e remover o antigo)
3. Atualizar `domains/observability/infra/alerts/dt005-alertmanager-config.yaml`: substituir receiver `slack_api_url` por `webhook_configs` HTTP apontando para URL Teams
4. Testar entrega com alert de teste manual (`amtool alert add` ou PrometheusRule temporaria)
5. Remover referencias a Slack na documentacao operacional e nos runbooks

**Nota sobre compatibilidade:** Alertmanager suporta Teams via `webhook_configs` — o endpoint
Teams aceita payload JSON via POST. Nao ha receiver nativo `msteams` no Alertmanager OSS;
usar receiver `webhook` com URL do Teams Incoming Webhook. Para formatacao rica, avaliar uso
de `alertmanager-msteams` sidecar (projeto open-source) ou template customizado no receiver.

## Alternativas Consideradas

1. **Slack** — Descartado. Empresa adota Teams como ferramenta corporativa de comunicacao.
2. **PagerDuty** — Descartado para esta demanda. Pode ser avaliado para alertas P0 no futuro (ADR separado).
3. **Email** — Descartado. Baixa visibilidade operacional vs canal de mensagens.

## Consequencias

**Positivo:**
- Alinhamento com a ferramenta de comunicacao corporativa (Teams)
- Nao requer licenca Slack adicional
- Todos os alertas visiveis no mesmo canal onde equipe ja opera

**Negativo:**
- Receiver webhook generico (nao tao rico quanto `slack_configs` nativo do Alertmanager)
- Formato de mensagem Teams requer template customizado para legibilidade adequada
- Sem suporte nativo a threading por alerta (diferente do Slack)

## Status Atual

Secret `alertmanager-slack-webhook` existe com 4 chaves (valores `REPLACE`).
Alertas nao sao entregues. Implementacao bloqueada aguardando URL Teams.
Nenhuma alteracao no cluster realizada por esta ADR — apenas decisao documentada.

## Referencias

- DT-005 em `docs/demands-backlog.md`
- `docs/finops/finops-status-2026-03-06.md` secoes 7 e 13
- `domains/observability/infra/alerts/dt005-alertmanager-config.yaml`
- `domains/observability/infra/alerts/dt005-prometheus-rules.yaml`
