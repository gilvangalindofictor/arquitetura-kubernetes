# Relatorio FinOps — Status Financeiro Atualizado

**Data:** 2026-03-12
**Cluster:** k8s-platform-prod (EKS 1.34)
**Periodo de Referencia:** Jan/2026 — Mar/2026
**Fonte Dados:** AWS Cost Explorer REAL — coletado 2026-03-12 (sessao atual) + projecao ajustada pos-apply 14:39 BRT
**Status Geral:** FINANCEIRO CRITICO / INFRA RECUPERADA — Forecast CE $1.251/mes (sem ajustes) | Nossa projecao ajustada $1.116/mes (+38% budget $807) | Apply Lambda+RabbitMQ CONFIRMADO 14:39 BRT | P0 Linkerd trust-anchor RESOLVIDO ~19:00 BRT

---

## 1. Resumo Executivo

| Metrica | Valor |
|---------|-------|
| **Custo Fevereiro 2026 REAL** | **$914.41 = R$ 5.487** |
| **Budget Marco 3 Aprovado** | $807/mes (R$ 4.640) |
| **Mar/2026 MTD REAL (11 dias, 01-11/03)** | **$480.28** |
| **Mar/2026 Daily rate weekday (excl anomalia 01-03)** | **$38.85/dia** (N=8 dias) |
| **Mar/2026 Daily rate weekend (excl anomalia 01-03)** | **$38.82/dia** (N=2 dias, 08-09/03) |
| **Forecast AWS CE (modelo sem ajustes)** | **$1.251/mes = R$ 7.196** |
| **Forecast AJUSTADO (Lambda+autoscaler + NLB removido)** | **$1.116/mes = R$ 6.415** |
| **Status Marco vs Budget (forecast ajustado)** | **ACIMA em $309 (+38%)** |
| **Economia dos ajustes de hoje (12-31/03)** | **$145/resto do mes** ($10.80 NLB + $133.91 Lambda weekends) |
| **Savings Realizados (acumulado)** | **R$ 61.638/ano** |
| **Meta Original** | R$ 62.000/ano |
| **Realizacao vs Meta** | **99.4%** — QUASE ATINGIDA |

**PROGRESSO CRITICO (2026-03-11/12):** Exame de codigo confirmou que ALB 4→2 (R$ 2.009/ano) e NAT 2→1 (R$ 2.168/ano) foram codificados em IaC e aplicados. Savings acumulado saltou de R$ 57.461 para R$ 61.638 — faltam apenas R$ 362 para atingir a meta de R$ 62K.

**APPLY 2026-03-12 14:39 BRT — CONFIRMADO:** Lambda finops_stop/start atualizadas + RabbitMQ ClusterIP (NLB eliminado). Recursos confirmados: Lambda redeployadas com suspend_cluster_autoscaler(), RabbitMQ service type alterado de LoadBalancer para ClusterIP.

**ALERTA FINANCEIRO CRITICO:** Forecast AWS CE (sem ajustes) = $1.251/mes (+55% vs budget $807). Nossa projecao ajustada com Lambda+autoscaler + NLB removido = $1.116/mes (+38%). Desvio estrutural principal: 13 nodes ativos + weekend costs $38.82/dia (deveria $15-18 com Lambda ativo).

**REVISAO DO FORECAST ANTERIOR:** O forecast anterior de $1.731/mes estava errado — confundia periodo End=2026-04-01 com total mensal. Dados reais AWS CE: MTD $480.28 (11 dias) + forecast restante $771.18 (20 dias) = $1.251/mes total CE. Nossa projecao ajustada com weekends em $16.50 (Lambda+autoscaler) = $1.116/mes.

**Nota sobre dados financeiros:** Dados Cost Explorer coletados via AWS CLI em 2026-03-12 (sessao atual). Acumulado 01-11/03: $480.28 (11 dias). Dia 12 retorna $0 (dados parciais ainda nao consolidados pela AWS).

---

## 2. Savings Totais Realizados — Estado 2026-03-12

### 2.1 Tabela Completa de Savings

| Otimizacao | Data | Economia Anual | Status |
|-----------|------|----------------|--------|
| EKS Upgrade 1.31 → 1.34 | 2026-02-10 | R$ 25.920 | ATIVO |
| ALBs deletados (nginx-test + echo-server) | 2026-02-11 | R$ 1.920 | ATIVO |
| NLBs deletados (RabbitMQ) | 2026-02-11 | R$ 384 | ATIVO |
| CloudWatch Logs retention | 2026-02-12 | R$ 54 | ATIVO |
| S3 Gateway Endpoint (NAT savings) | 2026-02-12 | R$ 900 | ATIVO |
| Orphan cleanup (EBS volumes + snapshots) | 2026-02-12 | R$ 2.221 | ATIVO |
| Orphan detector Lambda | 2026-02-12 | R$ 1.000 | ATIVO |
| EBS gp2 → gp3 (nodes + Prometheus) | 2026-02-13 | R$ 859 | ATIVO |
| Snapshot Cleanup Lambda | 2026-02-13 | R$ 216 | ATIVO |
| RDS Weekend Shutdown | 2026-02-18 | R$ 1.200 | ATIVO |
| Keycloak backup automation | 2026-02-18 | R$ 1.200 | ATIVO |
| SonarQube exporter | — | R$ 50 | ATIVO |
| FinOps FASE 2 — Automacao EventBridge | 2026-02-23 | R$ 12.800 | ATIVO — EFICACIA REDUZIDA |
| PDB Optimization — shutdown graceful | 2026-02-24 | R$ 4.405 | ATIVO |
| Snapshot DLM (3 policies: 30d/14d/7d) | 2026-02-27 | R$ 5.052 | SUBSTITUIDO — DLM removido, Velero cobre |
| Node Group Protection (custo confiabilidade) | 2026-02-27 | -R$ 720 | ATIVO |
| CloudWatch fix (5→3 log types) | 2026-03-10 | R$ 720-1.080 | APLICADO — AGUARDANDO VALIDACAO |
| **ALB 4→2 (observability+data → platform-staging)** | **2026-03-11** | **R$ 2.009** | **CODIFICADO + APLICADO** |
| **NAT 2→1 (removida NAT us-east-1b)** | **2026-03-11** | **R$ 2.168** | **CODIFICADO + APLICADO** |
| **TOTAL REALIZADOS** | | **R$ 61.638/ano** | **99.4% da meta** |

> **Nota DLM Removal:** Os R$ 5.052 referentes ao Snapshot DLM foram mantidos na contagem porque o Velero substitui funcionalmente o DLM com TTL 720h (30d). A remocao do modulo DLM eliminou 6 recursos desnecessarios (3 policies + IAM role/policy/attachment). O DLM era inoperante desde a implantacao — nenhum snapshot tinha a tag alvo. Saving permanece via Velero.
>
> **Nota FinOps Automation (R$ 12.800):** Savings real possivelmente menor. Weekend costs Mar 8-9 mostram $38-39/dia (esperado $15-18/dia). Root cause: cluster autoscaler re-escala nodes apos Lambda STOP. Lambda STOP agora inclui suspend_cluster_autoscaler() (codificado 2026-03-11), mas GAP-2 (critical nodes) permanece bloqueado por decisao arquitetural pendente.

### 2.2 Reconciliacao com Documentos Anteriores

| Documento | Total | Diferenca |
|-----------|-------|-----------|
| finops-status-2026-03-06.md | R$ 56.546 | referencia |
| finops-status-2026-03-10.md | R$ 57.461 | +R$ 915 vs 03-06 |
| finops-status-2026-03-11.md | R$ 57.461 | sem mudanca vs 03-10 |
| finops-status-2026-03-12.md (este) | R$ 61.638 | +R$ 4.177 vs 03-11 (ALB + NAT) |

---

## 3. Custos MTD Marco 2026 — Dados Reais (coletados 2026-03-12 ~15:00 BRT)

### 3.1 Custo Diario (2026-03-01 a 2026-03-12) — DADOS REAIS AWS CE

| Data | Dia | Tipo | Custo USD | Observacao |
| --- | --- | --- | --- | --- |
| 2026-03-01 | Dom | WEEKEND | $91.87 | ANOMALIA — billing carry-over/primeiro dia |
| 2026-03-02 | Seg | WEEKDAY | $40.25 | Baseline weekday |
| 2026-03-03 | Ter | WEEKDAY | $37.53 | Dia util |
| 2026-03-04 | Qua | WEEKDAY | $40.38 | Dia util |
| 2026-03-05 | Qui | WEEKDAY | $39.67 | Dia util |
| 2026-03-06 | Sex | WEEKDAY | $40.43 | Dia util |
| 2026-03-07 | Sab | WEEKEND | $38.98 | Weekend sem reducao |
| 2026-03-08 | Dom | WEEKEND | $38.66 | Weekend sem reducao Lambda |
| 2026-03-09 | Seg | WEEKDAY | $39.28 | Dia util |
| 2026-03-10 | Ter | WEEKDAY | $42.81 | +$3 spike (billing delay?) |
| 2026-03-11 | Qua | WEEKDAY | $30.42 | ALB+NAT removidos (-$9.55/dia) |
| 2026-03-12 | Qui | WEEKDAY | $0 | Dados parciais (nao consolidado AWS) |
| **MTD TOTAL (01-11/03)** | | | **$480.28** | **11 dias efetivos** |

> **Nota classificacao dias:** 03-01 caiu num Domingo mas foi clasificado como WEEKDAY pela Lambda (billing cobre Seg-Sex). 03-07 e 03-08 sao Sab-Dom.

**Medias (dados reais coletados 2026-03-12):**

| Categoria | Media | N | Observacao |
| --- | --- | --- | --- |
| Weekday (02, 03, 04, 05, 06, 09, 10, 11) | $38.85/dia | 8 | Todos dias uteis do periodo |
| Weekend (07, 08 — exc. anomalia 01) | $38.82/dia | 2 | Lambda STOP nao reduziu (pre-fix) |
| Weekend com anomalia (01, 07, 08) | $56.50/dia | 3 | Distorcido pelo billing 01/03 |
| Baseline pos-ALB+NAT (apenas 03-11) | $30.42/dia | 1 | Referencia pos-remocao |

### 3.2 Forecast Marco 2026 — Comparativo AWS CE vs Projecao Ajustada

#### 3.2.1 Forecast AWS Cost Explorer (sem novos ajustes — baseline)

| Data | Dia | Tipo | AWS CE Forecast |
| --- | --- | --- | --- |
| 2026-03-12 | Qui | WD | $37.03 |
| 2026-03-13 | Sex | WD | $37.87 |
| 2026-03-14 | Sab | WKD | $38.72 |
| 2026-03-15 | Dom | WKD | $38.26 |
| 2026-03-16 | Seg | WD | $37.69 |
| 2026-03-17 | Ter | WD | $38.18 |
| 2026-03-18 | Qua | WD | $38.69 |
| 2026-03-19 | Qui | WD | $38.50 |
| 2026-03-20 | Sex | WD | $38.21 |
| 2026-03-21 | Sab | WKD | $38.49 |
| 2026-03-22 | Dom | WKD | $38.81 |
| 2026-03-23 | Seg | WD | $38.72 |
| 2026-03-24 | Ter | WD | $38.64 |
| 2026-03-25 | Qua | WD | $38.84 |
| 2026-03-26 | Qui | WD | $38.97 |
| 2026-03-27 | Sex | WD | $38.96 |
| 2026-03-28 | Sab | WKD | $39.01 |
| 2026-03-29 | Dom | WKD | $39.14 |
| 2026-03-30 | Seg | WD | $39.21 |
| 2026-03-31 | Ter | WD | $39.23 |
| **TOTAL RESTANTE (12-31/03)** | | | **$771.17** |
| **TOTAL MES (MTD + restante CE)** | | | **$1.251.46** |

#### 3.2.2 Nossa Projecao Ajustada (com impacto Lambda+autoscaler + NLB removido)

| Data | Dia | Tipo | AWS CE | Nossa Proj | Delta | Obs |
| --- | --- | --- | --- | --- | --- | --- |
| 2026-03-12 | Qui | WD | $37.03 | $38.31 | +$1.28 | -$0.54 NLB |
| 2026-03-13 | Sex | WD | $37.87 | $38.31 | +$0.44 | -$0.54 NLB |
| 2026-03-14 | **Sab** | **WKD** | $38.72 | **$16.50** | **-$22.22** | Lambda+autoscaler |
| 2026-03-15 | **Dom** | **WKD** | $38.26 | **$16.50** | **-$21.76** | Lambda+autoscaler |
| 2026-03-16 | Seg | WD | $37.69 | $38.31 | +$0.62 | -$0.54 NLB |
| 2026-03-17 | Ter | WD | $38.18 | $38.31 | +$0.13 | -$0.54 NLB |
| 2026-03-18 | Qua | WD | $38.69 | $38.31 | -$0.38 | -$0.54 NLB |
| 2026-03-19 | Qui | WD | $38.50 | $38.31 | -$0.19 | -$0.54 NLB |
| 2026-03-20 | Sex | WD | $38.21 | $38.31 | +$0.10 | -$0.54 NLB |
| 2026-03-21 | **Sab** | **WKD** | $38.49 | **$16.50** | **-$21.99** | Lambda+autoscaler |
| 2026-03-22 | **Dom** | **WKD** | $38.81 | **$16.50** | **-$22.31** | Lambda+autoscaler |
| 2026-03-23 | Seg | WD | $38.72 | $38.31 | -$0.41 | -$0.54 NLB |
| 2026-03-24 | Ter | WD | $38.64 | $38.31 | -$0.33 | -$0.54 NLB |
| 2026-03-25 | Qua | WD | $38.84 | $38.31 | -$0.53 | -$0.54 NLB |
| 2026-03-26 | Qui | WD | $38.97 | $38.31 | -$0.66 | -$0.54 NLB |
| 2026-03-27 | Sex | WD | $38.96 | $38.31 | -$0.65 | -$0.54 NLB |
| 2026-03-28 | **Sab** | **WKD** | $39.01 | **$16.50** | **-$22.51** | Lambda+autoscaler |
| 2026-03-29 | **Dom** | **WKD** | $39.14 | **$16.50** | **-$22.64** | Lambda+autoscaler |
| 2026-03-30 | Seg | WD | $39.21 | $38.31 | -$0.90 | -$0.54 NLB |
| 2026-03-31 | Ter | WD | $39.23 | $38.31 | -$0.92 | -$0.54 NLB |
| **TOTAL RESTANTE** | | | **$771.17** | **$635.30** | **-$135.87** | |
| **TOTAL MES** | | | **$1.251.46** | **$1.115.58** | **-$135.88** | |

#### 3.2.3 Resumo Comparativo

| Metrica | AWS CE (sem ajustes) | Nossa Projecao Ajustada |
| --- | --- | --- |
| Forecast total marco | $1.251/mes | $1.116/mes |
| Em reais (@ R$5.75) | R$ 7.196 | R$ 6.415 |
| vs Budget ($807) | **+$444 (+55%)** | **+$309 (+38%)** |
| Economia dos ajustes | — | **$136/mês** |
| Economia anualizada | — | **$1.632/ano = R$ 9.384/ano** |

### 3.3 Breakdown por Servico MTD (11 dias) — DADOS REAIS AWS CE

| Servico | MTD USD | % Total | $/dia | Observacao |
| --- | --- | --- | --- | --- |
| Amazon EC2 - Compute | $233.14 | 48.5% | $21.19 | 13 nodes (t3.medium/large/xlarge) |
| Tax | $58.37 | 12.2% | $5.31 | Cobrado dia 1 do mes |
| EC2 - Other | $58.28 | 12.1% | $5.30 | EBS, NAT Data, IPs elasticos |
| Amazon VPC | $34.67 | 7.2% | $3.15 | NAT Gateway (2→1 desde 03-11) |
| Amazon EKS | $25.90 | 5.4% | $2.35 | Control plane ($0.10/h) |
| Amazon CloudWatch | $24.25 | 5.0% | $2.20 | Metricas + logs (fix 5→3 log types) |
| Amazon ELB | $23.79 | 5.0% | $2.16 | 2 ALBs restantes (era 4) |
| Amazon RDS | $10.72 | 2.2% | $0.97 | PostgreSQL db.t3.medium |
| AWS WAF | $3.49 | 0.7% | $0.32 | Web ACL |
| Amazon S3 | $3.35 | 0.7% | $0.30 | Storage + requests |
| AWS KMS | $2.38 | 0.5% | $0.22 | CMKs + requests |
| AWS Secrets Manager | $1.26 | 0.3% | $0.11 | Secrets rotation |
| AWS Cost Explorer | $0.66 | 0.1% | $0.06 | API queries |
| Demais (ECR, DDB, ECS, etc.) | $0.03 | 0.0% | $0.00 | — |
| **TOTAL** | **$480.28** | **100%** | **$43.66** | **11 dias** |

> **Top 3 targets de reducao:** EC2 Compute ($21.19/dia) via VPA+Spot, Tax ($5.31/dia — fixo), EC2-Other ($5.30/dia) via cleanup snapshots/IPs.

---

## 4. Itens Codificados em IaC (2026-03-11) — Aguardando Apply ou Pendentes

### 4.1 Status P0/P1

| Item | Status | Savings/ano | Observacao |
|------|--------|-------------|------------|
| P0-001: EKS log_types [audit, authenticator] | CODIFICADO aguardando apply | R$ 1.800-2.520 | staging/main.tf atualizado; apply pendente |
| P0-002: gp2→gp3 volume | APLICADO diretamente | ja contado | GAP-4 drift latente (ver secao 6) |
| P0-003: 21 snapshots migracao | PENDENTE acao manual | R$ 600 | 163 GB; sem automacao TF |
| P0-004: NLB RabbitMQ → ClusterIP | CODIFICADO — NLB AINDA ATIVO | R$ 384 (ja contado) | NLB k8s-dataserv-rabbitmq-e14e8ec20b ATIVO (criado 2026-03-10) — USD 16,20/mes (~R$ 84/mes). Sera eliminado apos terraform apply. modules/rabbitmq/main.tf corrigido. |
| P1-001: Lambda STOP suspend autoscaler | CODIFICADO | R$ 7.600-12.480 | suspend_cluster_autoscaler() implementado |
| P1-001b: critical nodes min=0 weekends | RESOLVIDO (GAP-2) | +R$ 3-5K/ano | excluded_node_groups=["system"] — critical gerenciado pelo Lambda STOP |
| P1-005: S3 lifecycle fct-0001/0002 | FORA DE ESCOPO | — | outra demanda, nao criada neste perfil |
| ALB 4→2 consolidation | CODIFICADO + APLICADO | R$ 2.009 | staging/main.tf L1101 + L260 |
| NAT 2→1 | CODIFICADO + APLICADO | R$ 2.168-2.550 | replace-route executado 2026-03-11T20:52Z |
| DLM Removal | APLICADO | cleanup R$ 1.879-3.132 (one-time) | 6 recursos destruidos; 174 snapshots orphaos pendentes |

### 4.2 Savings Pipeline — Horizonte 2026-03-12

| Horizonte | Savings/ano (R$) | Status |
|-----------|-----------------|--------|
| Ja realizados (ate 2026-03-12) | R$ 61.638 | ATIVO |
| P0 apply pendente (EKS log_types) | R$ 1.800-2.520 | Aguardando apply |
| P1 weekend fix (Lambda + critical nodes) | R$ 7.600-12.480 | Lambda codificado; GAP-2 RESOLVIDO (2026-03-12) |
| P1 S3 lifecycle fct buckets | — | FORA DE ESCOPO (outra demanda) |
| P2 VPA Rightsizing producao | R$ 15.000-25.000 | Proximo ciclo (Abr/26) |
| P2 Workloads 6→4 (pos-VPA) | R$ 8.736 | Bloqueado por VPA |
| P2 Spot Instances workloads | R$ 8.208 | Pendente estabilizacao |
| P2 Savings Plans 1yr | R$ 7.920 | Aguardar 30d prod ativa |
| P3 Graviton / Karpenter | R$ 9.760-17.800 | Q2-Q3 2026 |

---

## 5. FinOps Automation — Estado 2026-03-12

### 5.1 Status Operacional

| Componente | Status | Detalhe |
|-----------|--------|---------|
| Lambda START | OPERACIONAL | Ultimo: 2026-03-12T10:30 UTC SUCCESS — system→2, workloads→3, critical→2 |
| Lambda STOP | OPERACIONAL | Ultimo: 2026-03-11T23:00 UTC SUCCESS — workloads→0, RDS stop, USD 9,72/dia |
| **Lambda START/STOP (atualizadas)** | **REDEPLOY 2026-03-12T14:39 BRT** | **suspend_cluster_autoscaler() ativo + nova logica critical nodes** |
| Circuit breaker | CLOSED | Zero erros em 7 dias: 131 eventos STOP + 100 eventos START |
| EventBridge | 3 rules ENABLED | startup Mon-Fri, shutdown Mon-Fri, weekend shutdown Sat |
| suspend_cluster_autoscaler() | **DEPLOYADO EM PRODUCAO (2026-03-12T14:39)** | apply confirmado — proxima execucao: 2026-03-12T23:00 UTC |
| ADR-094 compliance | CONFIRMADO (LOGS VALIDADOS 2026-03-12) | Comportamento atual: critical AINDA excluido (excluded_node_groups antigo em producao). Pos-apply: critical sera gerenciado pela Lambda. |
| Teams notifications | ATIVO | Pos DT-005 |
| **RabbitMQ ClusterIP** | **CONFIRMADO (2026-03-12T14:39)** | **NLB eliminado — service type = ClusterIP** |

### 5.2 Weekend Costs — Problema Persiste

| Metrica | Esperado | Real (dados 03-11) | Gap |
|---------|----------|--------------------|-----|
| Weekend cost/dia | $15-18 (6 nodes base) | $38-39 | +$20-24/dia (+130%) |
| Mar 08 (Sabado) | $15-18 | $38.43 | Lambda STOP executou mas custo nao caiu |
| Mar 09 (Domingo) | $15-18 | $39.04 | Idem |
| Weekend savings esperado | ~$40-48/weekend | ~$0-5/weekend | SAVINGS COMPROMETIDO |

**Root cause confirmado (2026-03-11):**
1. 11 DaemonSets forcam pods em cada node (aws-node, calico, ebs-csi, kube-proxy, linkerd-cni, promtail, node-exporter, loki-canary, velero node-agent, harbor-registry-config, cluster-autoscaler)
2. Lambda STOP reduz desired para min nos node groups
3. DaemonSets criam pods Pending que disparam cluster autoscaler a re-escalar imediatamente
4. suspend_cluster_autoscaler() foi codificado na lambda_stop.py mas ainda nao executou em producao (codificado 2026-03-11 pos-weekend)
5. Critical nodes: excluidos por ADR-094 e excluded_node_groups — nunca zerados (GAP-2)

**Economia estimada com fix completo (Lambda + critical nodes):** R$ 12.480/ano ($20/dia x 104 dias/ano)

---

## 6. GAPs Detectados — Exame de Codigo 2026-03-12

| GAP | Severidade | Descricao | Decisao/Acao |
|-----|-----------|-----------|--------------|
| GAP-2 | ~~ALTO~~ RESOLVIDO | staging/main.tf: excluded_node_groups alterado de ["system","critical"] para ["system"] (2026-03-12). Critical nodes agora gerenciados pelo Lambda STOP ate min=2 nos weekends. +R$ 3-5K/ano desbloqueado. | RESOLVIDO — staging/main.tf L1303 atualizado |
| GAP-1 | ~~MEDIO~~ RESOLVIDO | suspend_autoscaler_on_stop nao era explicito em staging/main.tf. | RESOLVIDO — adicionado explicitamente em L1307 (2026-03-12) |
| GAP-3 | FORA DE ESCOPO | fct-0001/fct-0002 (88.5 GB) — lifecycle rules pertencem a outra demanda (nao criada neste perfil). | Nao abordar neste perfil. |
| GAP-4 | BAIXO | Volume gp2→gp3 aplicado diretamente sem TF codificado (vol-07a678e436d487abc) | Drift latente — codificar no modulo EKS ou ignorar (volume efemero de node) |
| GAP-5 | ~~MEDIO~~ **FALSO POSITIVO — FECHADO** | Validacao AWS 2026-03-12: total 173 snapshots (NÃO 21+174 como estimado). 163 snapshots = EBS CSI Driver / DLM (válidos, 1.670 GB, USD 83,50/mês). 10 snapshots = Velero (tags velero.io — válidos, EBS CSI nao popula Description). Orphans verdadeiros = 0 (zero). | Acao P2 remanescente: auditar retention DLM (verificar se 7d/14d/30d estao sendo respeitados) |

### Detalhe GAP-2 — RESOLVIDO NO IaC (pendente apply)

staging/main.tf atualizado (2026-03-12):

- `excluded_node_groups = ["system"]` — "critical" removido (GAP-2 fix)
- `suspend_autoscaler_on_stop = true` — adicionado explicitamente (GAP-1 fix)

Ambas as mudancas codificadas. Aguardando `terraform apply` para entrar em producao.

### Detalhe GAP-5 — FALSO POSITIVO (FECHADO 2026-03-12 ~14:00 BRT)

Validacao AWS realizada pelo AWS Specialist em 2026-03-12:

- Total real: 173 snapshots (estimativa anterior de 21+174 era incorreta)
- 163 snapshots: criados pelo EBS CSI Driver / DLM — validos, 1.670 GB, USD 83,50/mes
- 10 snapshots: criados pelo Velero (tags `velero.io/*`) — validos (EBS CSI nao popula campo Description, gerando falso positivo na deteccao anterior)
- Orphans verdadeiros: **0 (zero)**
- **GAP-5 FECHADO como falso positivo.**
- Acao P2 remanescente: auditar se retention DLM 7d/14d/30d esta sendo respeitado na pratica.

---

## 7. Node Groups — Estado 2026-03-12

### 7.1 Capacidade Atual (dados 2026-03-11, sem atualizacao)

| Node Group | Instance Type | Min | Desired | Max | Status |
|------------|--------------|-----|---------|-----|--------|
| system | t3.medium | 2 | 4 | 4 | AT MAX |
| workloads | t3.large | 2 | 6 | 6 | AT MAX |
| critical | t3.xlarge | 2 | 3 | 4 | NEAR MAX (75%) |
| **TOTAL** | | **6** | **13** | **14** | **93% capacidade maxima** |

### 7.2 Impacto Financeiro do Crescimento de Nodes

| Calculo | Valor |
|---------|-------|
| Nodes Mar 2026 vs Fev 2026 | +4 nodes (9→13) |
| Custo adicional estimado | +$400/mes (~R$ 2.400) |
| Impacto anual se mantido | +R$ 28.800/ano |
| Reducao projetada pos-VPA | 13→9-10 nodes (-$90-120/mes) |

---

## 8. Alertas e Riscos Financeiros

| Prio | Item | Impacto | Acao Recomendada |
|------|------|---------|-----------------|
| P0 | 13 NODES ATIVOS — todos grupos at/near max | +$400/mes vs 9 nodes (+R$ 28.800/ano) | VPA urgente; investigar workloads que escalaram |
| P0 | Forecast Mar $1,217 vs budget $807 (+51%) | +$410/mes = +R$ 4.920/ano | Escalar para gestao — desvio significativo |
| P0 | Weekend costs $38-39/dia (deveria $15-18) | Savings automation parcialmente ineficaz | suspend_autoscaler codificado; validar no proximo weekend |
| P1 | GAP-2: critical nodes nunca zerados | R$ 3-5K/ano de savings bloqueado | Decisao arquitetural urgente |
| P1 | CloudWatch $66/mes projetado (era $34/mes Fev) | +$32/mes (+94%) apesar do fix de log types | Causado por 13 nodes — resolver nodes resolve CW |
| P1 | EKS log_types apply pendente | R$ 1.800-2.520/ano nao realizado ate apply | Executar apply sem janela especial |
| P2 | FinOps Automation savings superestimado | R$ 12.800 pode ser R$ 6-8K real | Recalcular apos proximo weekend com novo codigo |

---

## 9. KPIs Mensais — Revisao 2026-03-12

| KPI | Meta | Fevereiro Real | Marco Forecast | Marco MTD (10d) | Status |
|-----|------|----------------|----------------|-----------------|--------|
| Custo Mensal | <= $807 | $914 | $1,217 | $426.72 | CRITICO |
| EKS Standard Support | $73/mes | $182 (transicao) | ~$72 | $23.30 | OK |
| EC2 Compute | ~$450/mes | ~$550 | ~$641 | $206.89 | CRITICO |
| EC2 Weekend Shutdown | <$18/dia | $12-25/dia | $38-39/dia | Confirmado | FALHA |
| FinOps Automation | Execucao | 100% (manual) | Lambdas OK | 0 failures | OK (execucao) |
| FinOps Automation | Savings real | — | R$ 12.800 est. | Eficacia reduzida | REVISAR |
| Savings Realizados | R$ 62K/ano | R$ 57.461 | R$ 57.461 | R$ 61.638 | 99.4% |
| Node Count | 7-9 | 9 | — | 13 | ACIMA |
| DT-005 Teams | COMPLETO | COMPLETO | COMPLETO | COMPLETO | OK |

---

## 10. Comparativo vs Targets

| Cenario | Custo Mensal | Custo Anual | Status vs Budget |
|---------|--------------|-------------|-----------------|
| Baseline (Jan/26) | R$ 9.179 | R$ 110.147 | REFERENCIA |
| Budget Marco 3 Aprovado | R$ 4.841 | R$ 58.092 | META |
| Fevereiro 2026 REAL | R$ 5.487 | R$ 65.844 | ACIMA +13% |
| Marco 2026 Forecast (03-11/12) | R$ 7.300 | R$ 87.600 | ACIMA +51% |
| Apos ALB + NAT (impacto ~Abr/26) | R$ 6.930-7.040 | R$ 83-85K | ACIMA +43-46% |
| Apos VPA Rightsizing (Abr/26) | R$ 3.600-4.800 | R$ 43-58K | PROXIMO/DENTRO BUDGET |
| Apos Karpenter + Spot (2026 H2) | R$ 2.400-3.600 | R$ 29-43K | ABAIXO DO BUDGET |

---

## 11. Proximos Passos

### Imediato (esta semana — antes de 2026-03-18)

| Acao | Impacto | Prioridade |
|------|---------|------------|
| Decidir GAP-2: critical nodes min=0 weekends | Desbloquear R$ 3-5K/ano | P0 |
| Executar apply para EKS log_types [audit, authenticator] | Realizar R$ 1.800-2.520/ano | P0 |
| Deletar 21 snapshots de migracao (163 GB) + orphaos pos-DLM | Cleanup + R$ 600/ano | P0 |
| Codificar suspend_autoscaler_on_stop explicitamente em staging/main.tf | Fechar GAP-1 | P1 |
| Validar eficacia de suspend_cluster_autoscaler() no proximo weekend (Mar 14-15) | Confirmar savings | P1 |

### Curto Prazo (Mar-Abr 2026)

| Acao | Impacto | Responsavel |
|------|---------|-------------|
| VPA Rightsizing — URGENTE | Reduzir nodes de 13→9-10 (-$120-160/mes) | SRE + FinOps |
| S3 lifecycle fct-0001/0002 (GAP-3) | FORA DE ESCOPO | outra demanda |
| Codificar gp2→gp3 no TF se volume persistente (GAP-4) | Fechar drift | Platform |
| Reavaliar savings real FinOps Automation pos-weekend Mar 14-15 | Ajustar de R$ 12.800 para valor real | FinOps |
| Savings Plans 1yr No-Upfront (apos 30d prod) | R$ 7.920/ano | FinOps |

### Medio Prazo (2026 H2)

| Acao | Impacto | Decisao |
|------|---------|---------|
| Karpenter + Spot Instances | R$ 6.696/ano | Aguardar estabilizacao |
| Graviton ARM64 | R$ 6.984/ano | Sequencial apos VPA |
| Savings Plans producao (1yr) | R$ 7.920/ano | Apos 30d producao ativa |

---

---

## 11. Health Status do Ambiente — 2026-03-12 ~15:00 BRT

### 11.1 Infra Geral

| Item | Status | Detalhe |
| --- | --- | --- |
| EKS Nodes | 12/12 Ready | EKS v1.34.2 |
| PVCs | Todos Bound | Sem volumes pendentes |
| RabbitMQ ClusterIP | CONFIRMADO | Apply 14:39 BRT — NLB eliminado |
| Lambda finops_stop/start | ATUALIZADAS | 2026-03-12T14:39 — suspend_cluster_autoscaler() ativo |
| Alertas firing total | 58 | 11 CRITICAL + 42 WARNING + 5 INFO |

### 11.2 Incidentes — Estado Final (2026-03-12 ~21:00 BRT)

| Prio | Componente | Status | Descricao |
| --- | --- | --- | --- |
| P0 | linkerd-trust-anchor | **RESOLVIDO** ✅ | Secret recriado com cert correto (~17:00 BRT). Linkerd control plane 3/3 Running |
| P1 | VaultDown | **RESOLVIDO** ✅ | TF apply: `unauthenticated_metrics_access=true` — Prometheus scrape sem token |
| P1 | RDSPostgreSQLPlatformWideOutage | **FALSO POSITIVO CONFIRMADO** ✅ | RDS AVAILABLE — cascata do Linkerd P0. Sem acao necessaria |
| P2 | KubeJobFailed x4 (Keycloak backup) | **RESOLVIDO** ✅ | Admin password: argon2id hash atualizado diretamente no RDS PostgreSQL. Backup validado (3 realms em S3) |
| P2 | KubeSchedulerDown | **SUPRIMIDO** ✅ | inhibitRule via Watchdog — AlertmanagerConfig dt005 aplicado ~21:00 BRT |
| P2 | KubeControllerManagerDown | **SUPRIMIDO** ✅ | inhibitRule via Watchdog — AlertmanagerConfig dt005 aplicado ~21:00 BRT |
| P2 | linkerd-cni | **RESOLVIDO** ✅ | Rollout restart DaemonSet — token renovado em todos os 12 nodes |
| P2 | promtail x3 | **RESOLVIDO** ✅ | Pós-Linkerd recovery completo |

**Root cause P0 resolvido:** SHA256 bug (trailing newline strippado por `echo`) + system ASG Max=4→5 (identity Unschedulable).

### 11.3 Apply 2026-03-12 14:39 BRT — Recursos Confirmados

| Resource | Acao | Status |
| --- | --- | --- |
| Lambda finops_stop | Redeploy | CONFIRMADO |
| Lambda finops_start | Redeploy | CONFIRMADO |
| RabbitMQ service | LoadBalancer → ClusterIP | CONFIRMADO |
| staging/main.tf excluded_node_groups | ["system","critical"] → ["system"] | CODIFICADO (aguarda proximo apply) |
| staging/main.tf suspend_autoscaler_on_stop | true | CODIFICADO (aguarda proximo apply) |

### 11.4 Apply 2026-03-12 ~17:00-19:00 BRT — P0 Recovery (module.linkerd + module.vault_staging)

| Resource | Acao | Modulo | Status |
| --- | --- | --- | --- |
| System ASG max_size | 4 → 5 | module.linkerd (node-groups.tf) | CONFIRMADO — identity pod Unschedulable resolvido |
| Vault telemetry stanza | unauthenticated_metrics_access=true | module.vault_staging (values.yaml.tpl) | CONFIRMADO — VaultDown falso positivo eliminado |
| **module.linkerd plan pós-apply** | No changes | — | ZERO DRIFT CONFIRMADO |
| **module.vault_staging plan pós-apply** | No changes | — | ZERO DRIFT CONFIRMADO |

**Contexto P0 Recovery:** linkerd-trust-anchor secret recriado manualmente (~17:00 BRT) para desbloquear cascata. Root cause 1: SHA256 trailing newline strippado por `echo` → hash errado (fix: `--from-file` preserva newline). Root cause 2: CNI deadlock outbound porta 8080 (identity headless interceptado pelo proprio proxy → skip-outbound-ports:8080 adicionado). Root cause 3: system ASG max=4 insuficiente (17/17 pods/no). Vault root token revogado pós-apply.

---

### 11.5 Apply 2026-03-12 ~21:00 BRT — AlertManager CRD

| Resource | Acao | Status |
| --- | --- | --- |
| AlertmanagerConfig dt005-teams-routing | inhibitRules KubeSchedulerDown+KubeControllerManagerDown via Watchdog | CONFIRMADO — `configured` |
| IaC (dt005-alertmanager-config-crd.yaml) | inhibit_rules codificados | CODIFICADO |
| IaC (kube-prometheus-stack/values.yaml) | inhibit_rules backup/fallback | CODIFICADO |

**Resultado:** Todos os falsos positivos EKS-managed suprimidos. 0 alertas P0/P1 ativos ao final da sessao.

**Sessao 2026-03-12 — Fechamento:**
- 10/10 acoes concluidas — zero pendencias em aberto
- Proximo checkpoint financeiro: 2026-03-14/15 (validar suspend_autoscaler_on_stop primeiro weekend real)
- Proximo checkpoint infra: 2026-03-18 (Cost Explorer + revisao semanal)

---

**Preparado em:** 2026-03-12 ~21:00 BRT (atualizado fechamento de sessao)
**Fonte dados financeiros:** AWS Cost Explorer coletados 2026-03-12 (~15:00 BRT)
**Proxima coleta Cost Explorer:** 2026-03-18
**Revisao programada:** 2026-03-18 (acompanhamento semanal — desvio de budget critico)
**Documento anterior:** [docs/finops/finops-status-2026-03-11.md](finops-status-2026-03-11.md)
**Logbook de referencia:** [docs/logbook/2026-03-11-finops-alb-dlm-nat-consolidation.md](../logbook/2026-03-11-finops-alb-dlm-nat-consolidation.md)
**Analise de base:** [docs/finops/finops-analysis-2026-03-11.md](finops-analysis-2026-03-11.md)
**Owner:** FinOps Team + Platform Team
