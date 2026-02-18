AWS Costs — Consolidated Report (2026-02)

Resumo: consolida MTD (2026-02-01 → 2026-02-18), recorte últimos 4 dias e detalhe diário.

PERÍODO MTD: 2026-02-01 → 2026-02-18
MÉTRICA: `UnblendedCost` (USD)

TOTAL MTD: 578.5874581253 USD

Top serviços (MTD, USD):
- Amazon Elastic Container Service for Kubernetes: 155.11820139
- Amazon Elastic Compute Cloud - Compute: 148.7783783720
- EC2 - Other: 71.7531309134
- Tax: 70.31
- Amazon Elastic Load Balancing: 46.6025351016
- Amazon Virtual Private Cloud: 43.4795729077
- Amazon Relational Database Service: 17.3094913816
- AmazonCloudWatch: 15.6333893647
- AWS Key Management Service: 3.9077379952
- Amazon Simple Storage Service: 3.4627636328

DETALHE: Últimos 4 dias (2026-02-14 → 2026-02-17)
- Período: 2026-02-14 → 2026-02-17 (últimos 4 dias considerados)
- Total (4d): 49.2403516325 USD

Por serviço (4d):
- Amazon Virtual Private Cloud: 11.7054079709
- EC2 - Other: 9.9267310889
- Amazon Elastic Container Service for Kubernetes: 8.8
- Amazon Elastic Load Balancing: 7.9206295838
- Amazon Elastic Compute Cloud - Compute: 4.6383884456
- AmazonCloudWatch: 2.2600207754
- Amazon Relational Database Service: 1.8523232185
- AWS Key Management Service: 0.8958333104
- Amazon Simple Storage Service: 0.7931974280
- AWS Secrets Manager: 0.4190476224
- (demais serviços com valores menores ou zero)

DETALHE POR DIA (MTD - totais diários):
- 2026-02-01: 105.9481094154
- 2026-02-02: 39.6352251515
- 2026-02-03: 47.1703450341
- 2026-02-04: 47.3557501086
- 2026-02-05: 41.0590203960
- 2026-02-06: 38.5258095143
- 2026-02-07: 25.7434417567
- 2026-02-08: 25.7434594385
- 2026-02-09: 40.5867861323
- 2026-02-10: 36.9705614310
- 2026-02-11: 24.1287744610
- 2026-02-12: 26.6115251987
- 2026-02-13: 29.8682984547
- 2026-02-14: 12.1058409899
- 2026-02-15: 12.1058182557
- 2026-02-16: 15.8282231681
- 2026-02-17: 9.2004692188
- 2026-02-18: 0 (dados podem estar pendentes)

OBSERVAÇÕES IMPORTANTES:
- Alguns valores são estimados (`Estimated: true` no Cost Explorer).
- `Tax` aparece separadamente no agregado MTD.
- Picos: 2026-02-01 (105.95 USD) é o dia com maior custo no período — investigar origem (EKS/EC2/Tax).

ARQUIVOS E FONTES:
- Relatórios individuais consolidados: `docs/reports/aws-costs-last-4-days.md`, `docs/reports/aws-costs-last-4-days-detailed.md`, `docs/reports/aws-costs-mtd-2026-02-01_18.md`
- Resumos brutos gerados:
	- `/tmp/ce-2026-02-14_18.json` (raw CE last4)
	- `/tmp/ce-mtd-2026-02-01_18.json` (raw CE MTD)
	- `/tmp/ce-mtd-summary.json` (resumo processado)
	- Consolidado no repositório: `docs/reports/aws-costs-raw-consolidated-2026-02.json`
	- Consolidado no repositório: `docs/reports/aws-costs-raw-consolidated-2026-02.json`
	- JSON/CSV adicionais consolidados: `docs/reports/aws-costs-raw-all-2026-02.json` (inclui dashboard grafana e CSV `reports/aws-costs-latest.csv`)
- Para exportar CSV detalhado (date,service,amount) ou gráficos, eu gero ao confirmar.

Ação recomendada curta:
- Investigar 2026-02-01 (EKS vs EC2 vs Tax) | AÇÃO: rodar `aws ce get-cost-and-usage` com filter por serviço e detalhe de tags para esse dia.

Relatório gerado automaticamente e consolidado em: `docs/reports/aws-costs-consolidated-2026-02.md`
