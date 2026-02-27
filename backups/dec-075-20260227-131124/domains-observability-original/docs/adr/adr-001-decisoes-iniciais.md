# ADR 001 – Decisões Iniciais

> **Status**: Superseded by SAD Corporativo (`/SAD/docs/sad.md` v1.0)
> **Migrado para**: Domínio da Plataforma Corporativa Kubernetes
> **Conformidade**: Ver ADR-003 (Validação contra SAD)

## Contexto
É necessário provisionar uma fundação de observabilidade aberta, de baixo custo e portável (cloud-agnostic) utilizando AWS como plataforma inicial. Equipe com acesso total à AWS, mas sem time dedicado imediato para operação. Aplicações futuras usarão OpenTelemetry para instrumentação.

**Nota**: Este ADR foi criado quando observability era projeto independente. Após migração para a Plataforma Corporativa, decisões arquiteturais sistêmicas são regidas pelo **SAD** (`/SAD/docs/sad.md`).

## Decisão
Adotar uma arquitetura baseada em componentes open source: Prometheus (métricas), Loki (logs), Tempo/Jaeger (traces) e Grafana (visualização). Provisionamento via Terraform e deploy em Kubernetes (EKS) como padrão recomendável, mantendo módulos e configurações portáveis para outras clouds.

## Alternativas Consideradas e Rejeitadas
- Usar soluções SaaS comerciais (Datadog, NewRelic) — rejeitado por custo e vendor lock-in.
- Usar ELK (Elasticsearch) para logs em vez de Loki — considerado, mas Loki foi escolhido inicialmente por menor custo operacional e integração mais simples com Grafana; ELK pode ser adotado posteriormente se requisitos de pesquisa/texto exigirem.

## Consequências
- Pró: Baixo custo inicial, fácil integração com OpenTelemetry, forte comunidade open source.
- Contra: Requer esforço operacional para manter, monitorar e dimensionar; risco de custos de armazenamento com crescimento de dados.

## Próximos Passos
1. Mesa técnica para decidir modelos de contas AWS, isolamento por ambiente e estratégia multi-região.
2. Criar módulos Terraform iniciais (VPC, EKS, S3 para long-term storage, IAM minimal).
3. Deploy de PoC (Prometheus, Grafana, Loki, Tempo, OpenTelemetry Collector) em ambiente de teste.
4. Definir política de retenção e limites de cardinalidade para métricas e logs.
