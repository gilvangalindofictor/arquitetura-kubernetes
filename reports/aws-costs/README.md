# Relatórios de Custos AWS

## 📊 Descrição

Este diretório contém os relatórios de custos AWS gerados pelos scripts de FinOps automation.

**Referência:** [ADR-022 - FinOps Automation Strategy](../../docs/adr/adr-022-finops-automation-strategy.md)

## 📁 Estrutura de Arquivos

### Relatórios Consolidados
- `costs.json` - Custos gerais consolidados
- `costs-mtd.json` - Custos month-to-date (acumulado do mês)

### Relatórios por Dimensão
- `cost-by-service.json` - Custos agrupados por serviço AWS
- `cost-by-operation.json` - Custos agrupados por operação/API calls
- `cost-by-usage.json` - Custos agrupados por tipo de uso
- `cost-by-tag.json` - Custos agrupados por tags AWS

### Relatórios MTD (Month-to-Date)
- `cost-mtd-by-service.json` - Custos MTD por serviço
- `cost-mtd-by-operation.json` - Custos MTD por operação

### Relatórios com Data Específica
- `cost-{YYYY-MM-DD}-by-service.json` - Snapshot de custos por serviço em data específica
- `cost-{YYYY-MM-DD}-by-usage.json` - Snapshot de custos por uso em data específica

### Relatórios de Recursos
- `cost-resources.json` - Detalhamento de custos por recurso AWS específico

## 🔄 Atualização

Estes arquivos são gerados automaticamente pelos scripts de FinOps:
- `scripts/finops/startup-marco2.sh` - Coleta métricas ao iniciar ambiente staging
- `scripts/finops/shutdown-marco2.sh` - Coleta métricas ao desligar ambiente staging

**Frequência:** Diária (horário comercial - 08:00 BRT startup, 18:00 BRT shutdown)

## 📝 Formato

Todos os arquivos seguem o formato JSON retornado pela AWS Cost Explorer API:

```json
{
  "ResultsByTime": [
    {
      "TimePeriod": {
        "Start": "YYYY-MM-DD",
        "End": "YYYY-MM-DD"
      },
      "Groups": [...],
      "Total": {
        "UnblendedCost": {
          "Amount": "XX.XX",
          "Unit": "USD"
        }
      }
    }
  ]
}
```

## 🎯 Uso

### Análise Manual
```bash
# Ver custos consolidados
cat costs.json | jq '.ResultsByTime[0].Total'

# Ver custos por serviço
cat cost-by-service.json | jq '.ResultsByTime[0].Groups'

# Calcular total MTD
cat costs-mtd.json | jq '.ResultsByTime[].Total.UnblendedCost.Amount' | \
  awk '{sum+=$1} END {print "Total MTD: $"sum}'
```

### Integração com Dashboards
Estes arquivos podem ser consumidos por:
- Grafana (via JSON datasource)
- Scripts de análise personalizados
- Ferramentas de BI
- Sistemas de alertas

## 🔒 Considerações de Segurança

- ✅ Arquivos contêm apenas dados de custos (sem credenciais)
- ✅ Safe para commit no Git (dados públicos internos)
- ⚠️  Considerar adicionar ao `.gitignore` se os valores forem sensíveis

## 📚 Referências

- [ADR-022: FinOps Automation Strategy](../../docs/adr/adr-022-finops-automation-strategy.md)
- [ADR-024: FinOps Scheduler Implementation](../../docs/adr/adr-024-finops-scheduler-implementation.md)
- [AWS Cost Explorer API Docs](https://docs.aws.amazon.com/cost-management/latest/APIReference/API_GetCostAndUsage.html)

## 📊 Economia Atual

**Status:** Staging environment com FinOps automation ativo

**Economia Projetada:**
- **Mensal:** R$ 850 (USD $142)
- **Anual:** R$ 10.200 (USD $1.700)

**Horário de Operação:**
- Segunda-Sexta: 08:00 - 18:00 BRT
- Fim de semana: Desligado
- Feriados: Desligado (via brasilapi.com.br)
