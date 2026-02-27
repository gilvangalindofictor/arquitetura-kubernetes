# Skill: Análise de Requisitos
Responsável por coletar, organizar e validar requisitos funcionais e não funcionais para a plataforma de observabilidade.

Método:
1. Analisar `docs/context/context-generator.md` e reuniões com stakeholders (CTO, SREs, desenvolvedores).
2. Identificar requisitos mínimos: níveis de retenção, cardinalidade, canais de alertas, SLIs iniciais.
3. Produzir artefatos: tabela de SLIs/SLOs iniciais, matriz de retenção por dado (métricas/logs/traces), requisitos de segurança e compliance.
4. Validar com ADR e atualizar `execution-plan.md`.

Exemplos concretos a gerar:
- SLI: Percentual de requisições com latência < 300ms por serviço
- SLO: 99.9% das requisições sob 300ms por mês
- Retenção: métricas 15d por padrão, logs 7d (configurável), traces 7d
