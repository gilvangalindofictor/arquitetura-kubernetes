# Relatório Consolidado de Custos AWS
Período analisado: 2026-01-11 → 2026-02-09 (30 dias)

## Visão geral
- Total (30 dias): **570.1209967226999 USD**
- Média diária aproximada: **~19 USD/day**
- Datas com pico principal: 2026-02-01, 2026-02-03, 2026-02-04, 2026-02-02, 2026-02-09

## Custos diários (detalhado)
Abaixo estão as datas e os custos diários gerais (USD) para o período analisado:

| Data       |   Custo (USD) |
| ---------- | ------------: |
| 2026-01-11 |  3.0000193163 |
| 2026-01-12 |   3.051741796 |
| 2026-01-13 |  3.0504988544 |
| 2026-01-14 |  3.0501113708 |
| 2026-01-15 |  3.0000352815 |
| 2026-01-16 |  3.0000277411 |
| 2026-01-17 |  3.0000373258 |
| 2026-01-18 |  3.0000194019 |
| 2026-01-19 |  3.0000223993 |
| 2026-01-20 |  3.0000315469 |
| 2026-01-21 |  3.0000272397 |
| 2026-01-22 |  3.0000548166 |
| 2026-01-23 |  3.0001354458 |
| 2026-01-24 |  2.9999884802 |
| 2026-01-25 |  3.0000102214 |
| 2026-01-26 | 11.1829097046 |
| 2026-01-27 |  6.1313231426 |
| 2026-01-28 | 14.0096771524 |
| 2026-01-29 | 37.3894872253 |
| 2026-01-30 | 32.0125315461 |
| 2026-01-31 | 34.5243597666 |
| 2026-02-01 | 83.8981094154 |
| 2026-02-02 | 39.6352251515 |
| 2026-02-03 | 47.1703450341 |
| 2026-02-04 | 47.3557501086 |
| 2026-02-05 |  41.059020396 |
| 2026-02-06 | 38.5258095143 |
| 2026-02-07 | 25.7434417567 |
| 2026-02-08 | 25.7434594385 |
| 2026-02-09 | 40.5867861323 |
| 2026-02-10 | 36.9705614310 |
| 2026-02-11 | 11.2849936408 |

Total (30 dias): **570.1209967226999 USD**

Fonte: `costs.json` (resumo diário fornecido pelo usuário)

## Month-to-date (MTD)

-- Período: 2026-02-01 → 2026-02-10 (inclusive)
-- MTD total: **426.6885087508 USD**
-- Valores diários (MTD): 2026-02-01: 83.8981094154, 2026-02-02: 39.6352251515, 2026-02-03: 47.1703450341, 2026-02-04: 47.3557501086, 2026-02-05: 41.059020396, 2026-02-06: 38.5258095143, 2026-02-07: 25.7434417567, 2026-02-08: 25.7434594385, 2026-02-09: 40.5867861323, 2026-02-10: 36.9705614310

Arquivo CSV com custos diários: [reports/aws-costs-daily.csv](reports/aws-costs-daily.csv)

## Top serviços (2026-02-01 — extraído de cost-2026-02-01-by-service.json)
- Tax: 48.26 USD
- Amazon Elastic Container Service for Kubernetes (EKS): 14.40 USD
- Amazon Elastic Compute Cloud - Compute (EC2): 14.2272 USD
- EC2 - Other: 4.2691029498 USD
- Amazon Elastic Load Balancing (ALB): 1.080173427 USD
- RDS, S3, VPC, KMS, Secrets Manager, ECR: valores menores (veja arquivo)

Fonte: [cost-2026-02-01-by-service.json](cost-2026-02-01-by-service.json#L1-L200)

## Top usage types (agregado 2026-01-29 → 2026-02-09 — extraído de `cost-by-usage.json`)
Principais somas no intervalo:
- USE1-AmazonEKS-Hours:extendedSupport — 132.00 USD
- BoxUsage:t3.xlarge — 60.06 USD
- BoxUsage:t3.large — 52.74 USD
- NoUsageType — 48.26 USD (impostos / itens sem usage-type)
- USE1-AmazonEKS-Hours:perCluster — 26.40 USD
- LoadBalancerUsage — 24.95 USD
- NatGateway-Hours — 23.76 USD
- USE1-PublicIPv4:InUseAddress — 14.83 USD
- EBS:VolumeUsage.gp3 — 14.67 USD

Fonte: [cost-by-usage.json](cost-by-usage.json#L1-L200)

## Top operações (agregado 2026-01-29 → 2026-02-09 — extraído de `cost-by-operation.json`)
- ExtendedSupport — 132.00 USD
- RunInstances (lançamento/horas de EC2) — 131.73 USD
- NatGateway — 27.36 USD
- CreateOperation — 26.40 USD
- LoadBalancing:Application — 21.35 USD
- CreateVolume-Gp3 — 14.67 USD
- AssociateAddressVPC (EIP) — 11.9976 USD
- CreateDBInstance:0014 — 11.4847 USD

Fonte: [cost-by-operation.json](cost-by-operation.json#L1-L200)

## Observações / interpretação rápida
- O custo de **132 USD rotulado como "ExtendedSupport"** e o agregado de **RunInstances ~131.7 USD** explicam a maior parte do pico. Isso indica cobrança de suporte/serviço adicional e muitas horas/instâncias EC2 rodando nesse intervalo.
- EKS (horas por cluster) aparece relevante; NAT Gateway e ALB também contribuem consistentemente (custos por hora e transferência).
- O agrupamento por tag `Environment` retorna `Environment$` (vazio), indicando recursos sem tag — rastreabilidade ruim.

## Ações recomendadas (curto prazo)
1. Verificar no painel Billing → Bills o detalhe do item `ExtendedSupport` para entender origem (suporte, marketplace, serviço adicional).
2. Listar instâncias EC2 criadas/rodando no intervalo e validar se podem ser encerradas ou reduzidas (rightsizing). Comandos sugeridos:
```bash
aws ec2 describe-instances --profile k8s-platform-prod --output json > instances.json
jq -r '.Reservations[].Instances[] | [.InstanceId,.InstanceType,.LaunchTime,.State.Name,(.Tags//[]|map(.Key+"="+.Value)|join(","))] | @tsv' instances.json
```
3. Verificar NAT Gateways e ALBs ociosos e remover se não necessários:
```bash
aws ec2 describe-nat-gateways --profile k8s-platform-prod --output table
aws elbv2 describe-load-balancers --profile k8s-platform-prod --output table
```
4. Habilitar/forçar tags `Environment` e `Owner` (retroativamente quando possível) e garantir novas stacks com tagging obrigatório.
5. Criar `AWS Budget` com alertas e habilitar detector de anomalias de custo.

## Próximos passos operacionais que posso executar para você
- Agrupar custo por `OPERATION=RunInstances` por dia e listar instâncias ativas/lançadas no pico. (Preciso que você confirme se quer que eu rode aqui; exige `aws sso login --profile k8s-platform-prod` no ambiente onde o agente roda.)
- Se preferir rodar localmente, cole os JSONs resultantes e eu faço a análise detalhada por recurso/ID.

## Arquivos gerados / usados
- `costs.json` (resumo diário fornecido)
- [cost-2026-02-01-by-service.json](cost-2026-02-01-by-service.json#L1-L200)
- [cost-by-tag.json](cost-by-tag.json#L1-L200)
- [cost-by-usage.json](cost-by-usage.json#L1-L200)
- [cost-by-operation.json](cost-by-operation.json#L1-L200)

---
Relatório gerado automaticamente a partir dos JSONs disponíveis no workspace.
