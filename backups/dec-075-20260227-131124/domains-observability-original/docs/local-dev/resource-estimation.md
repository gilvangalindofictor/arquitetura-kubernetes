# Estimativa de Recursos - Desenvolvimento Local

## 📊 Resumo Executivo

| Aspecto | Valor |
|---------|-------|
| **Viabilidade** | ✅ **VIÁVEL** para desenvolvimento |
| **CPU Mínima** | 4 cores |
| **RAM Mínima** | 8 GB |
| **Disco Mínimo** | 20 GB livres |
| **Recomendado** | 6+ cores, 16 GB RAM, 40 GB disco |

## 🎯 Análise de Viabilidade

### ✅ Cenários VIÁVEIS

#### 1. Desenvolvimento Básico
- **Hardware**: Laptop moderno (4 cores, 8 GB RAM)
- **Uso**: Editar configs, criar dashboards, testes unitários
- **Limitações**: Sem testes de carga pesados
- **Recomendação**: Profile "development"

#### 2. Desenvolvimento Completo
- **Hardware**: Workstation (6+ cores, 16 GB RAM)
- **Uso**: Desenvolvimento full-stack, testes integração
- **Limitações**: Testes de carga moderados
- **Recomendação**: Profile "testing"

#### 3. Testes de Performance
- **Hardware**: Workstation potente (8+ cores, 32 GB RAM)
- **Uso**: Simulação de produção, load testing
- **Limitações**: Escalabilidade limitada ao hardware
- **Recomendação**: Profile "production-like"

### ❌ Cenários NÃO VIÁVEIS Localmente

- Testes com **volume real de produção**
- Simulação de **múltiplas regiões/AZs**
- Testes de **disaster recovery**
- **Alta disponibilidade** (clustering)
- **Retenção longa** (anos de dados)

## 📈 Consumo Detalhado por Componente

### Stack Básica (7 containers)

| Componente | CPU (cores) | RAM (MB) | Disco (GB) | Status |
|------------|-------------|----------|------------|--------|
| Prometheus | 0.5-1.0 | 1500-2000 | 10 | Crítico |
| Grafana | 0.2-0.5 | 500-800 | 2 | Essencial |
| Loki | 0.3-0.7 | 800-1200 | 5 | Essencial |
| Tempo | 0.3-0.7 | 800-1200 | 5 | Essencial |
| OTel Collector | 0.2-0.5 | 300-500 | 1 | Crítico |
| Alertmanager | 0.1-0.2 | 200-300 | 1 | Opcional* |
| MinIO | 0.2-0.4 | 500-800 | 10 | Essencial |
| **TOTAL BASE** | **1.8-4.0** | **4600-6800** | **34** | - |

*Opcional em ambiente de dev puro

### Com Aplicação Exemplo (+2 containers)

| Componente | CPU (cores) | RAM (MB) | Disco (GB) |
|------------|-------------|----------|------------|
| Example App | 0.1-0.2 | 200-300 | 0.5 |
| Load Generator | 0.1-0.2 | 100-200 | 0.5 |
| **TOTAL COMPLETO** | **2.0-4.4** | **4900-7300** | **35** |

## 🖥️ Perfis de Hardware

### Profile 1: Mínimo (Viável com Limitações)

```yaml
Hardware:
  CPU: 4 cores @ 2.5 GHz
  RAM: 8 GB
  Disco: 20 GB (HDD aceitável)
  Docker: 4 GB RAM limit

Uso:
  - Edição de configs
  - Criação de dashboards
  - Validação de queries
  - Testes básicos

Limitações:
  - Sem testes de carga
  - Retenção: 1 dia
  - Sem persistência em volumes
  - Performance degradada

Custo: $0 (laptop comum)
```

### Profile 2: Recomendado (Desenvolvimento Full)

```yaml
Hardware:
  CPU: 6-8 cores @ 2.8 GHz+
  RAM: 16 GB
  Disco: 40 GB SSD
  Docker: 8 GB RAM limit

Uso:
  - Desenvolvimento completo
  - Testes de integração
  - Instrumentação de apps
  - Load tests moderados

Limitações:
  - Retenção: 3-7 dias
  - Load tests até 100 RPS
  - Traces com sampling 10%

Custo: $0 (workstation moderna)
```

### Profile 3: Ideal (Testes de Performance)

```yaml
Hardware:
  CPU: 8+ cores @ 3.0 GHz+
  RAM: 32 GB
  Disco: 80 GB NVMe SSD
  Docker: 16 GB RAM limit

Uso:
  - Simulação de produção
  - Testes de carga pesados
  - Prototipação avançada
  - Múltiplas instâncias

Limitações:
  - Retenção: 7 dias
  - Load tests até 500 RPS
  - Ainda single-node

Custo: $0 (workstation high-end)
```

## 📉 Otimizações Possíveis

### Reduzir Footprint

```yaml
# docker-compose.override.yml - Profile Light
version: "3.8"
services:
  prometheus:
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 1G
    command:
      - '--storage.tsdb.retention.time=1d'  # Reduzir retenção

  loki:
    deploy:
      resources:
        limits:
          cpus: '0.3'
          memory: 512M

  tempo:
    deploy:
      resources:
        limits:
          cpus: '0.3'
          memory: 512M

  grafana:
    deploy:
      resources:
        limits:
          cpus: '0.2'
          memory: 256M
    environment:
      - GF_ANALYTICS_ENABLED=false
      - GF_ANALYTICS_CHECK_FOR_UPDATES=false

  # Desabilitar componentes opcionais
  alertmanager:
    profiles: [full]  # Só inicia com --profile full
```

### Sampling Agressivo

```yaml
# configs/tempo.yml
overrides:
  defaults:
    ingestion:
      rate_strategy: local
      rate_limit_bytes: 1000000
      burst_size_bytes: 2000000
    sampling:
      probabilistic_sampler:
        sampling_percentage: 5  # 5% dos traces (padrão: 10%)
```

### Limitar Cardinalidade

```yaml
# configs/prometheus.yml
global:
  scrape_interval: 30s  # Reduzir frequência (padrão: 15s)

scrape_configs:
  - job_name: 'prometheus'
    metric_relabel_configs:
      # Dropar métricas high-cardinality desnecessárias
      - source_labels: [__name__]
        regex: 'go_.*'
        action: drop
```

## 💰 Comparação: Local vs AWS

### Desenvolvimento Local

| Aspecto | Valor |
|---------|-------|
| **Custo inicial** | $0 |
| **Custo mensal** | $0 |
| **Setup time** | ~10 minutos |
| **Limitações** | Hardware local |
| **Vantagens** | Feedback imediato, offline |

### AWS/EKS (Prod)

| Aspecto | Valor |
|---------|-------|
| **Custo inicial** | ~$50-100 (primeiro mês) |
| **Custo mensal** | ~$180-200 |
| **Setup time** | ~30-60 minutos |
| **Limitações** | Budget, latência |
| **Vantagens** | Escalável, HA, durabilidade |

## 🎯 Recomendações

### Para Time de 1-2 Pessoas
✅ **Desenvolvimento local é IDEAL**
- Zero custos
- Feedback rápido
- Ambiente controlado
- Deploy AWS só para homologação/produção

### Para Time de 3-5 Pessoas
✅ **Híbrido: Local + AWS Dev**
- Cada dev tem ambiente local
- AWS Dev compartilhado para integração
- Custos: ~$100-150/mês

### Para Time 6+ Pessoas
⚠️ **Considerar AWS Dev Dedicado**
- Ambientes locais individuais
- AWS Dev para testes integrados
- AWS Staging/Prod separados
- Custos: ~$400-500/mês total

## 📋 Checklist de Viabilidade

Seu ambiente é viável se:

- [ ] CPU: Pelo menos 4 cores físicos
- [ ] RAM: Pelo menos 8 GB total (6 GB livre)
- [ ] Disco: 20+ GB livres (40+ GB recomendado)
- [ ] Docker: Instalado e funcional
- [ ] Docker: 4+ GB RAM alocada
- [ ] SO: Linux, macOS, ou Windows 10+ Pro com WSL2
- [ ] Internet: Para download de imagens (primeira vez)

## 🚀 Próximos Passos

Se seu hardware atende os requisitos mínimos:

1. ✅ [Setup do Ambiente](./README.md)
2. ✅ [Configuração VS Code](../docs/local-dev/vscode-setup.md)
3. ✅ [Workflow de Desenvolvimento](../docs/local-dev/development-workflow.md)

Se não atende:

- **Opção 1**: Usar AWS Dev (budget $100-150/mês)
- **Opção 2**: Fazer upgrade de hardware
- **Opção 3**: Usar máquina remota/cloud (EC2 spot)

---

## 🆘 Dúvidas Frequentes

### Posso usar Windows?
✅ Sim, com **Windows 10+ Pro** e **WSL2 + Docker Desktop**
⚠️ Performance pode ser 10-20% inferior ao Linux nativo

### Posso usar Raspberry Pi?
❌ Não recomendado (ARM64, recursos limitados)
⚠️ Possível com stack mínima (sem Tempo/Loki)

### Funciona em Mac M1/M2/M3?
✅ Sim, perfeitamente (ARM64 nativo)
✅ Performance excelente

### Preciso de GPU?
❌ Não, observabilidade não usa GPU

### Quanto de internet preciso?
- **Download inicial**: ~2-3 GB (imagens Docker)
- **Uso diário**: Mínimo (sem upload de telemetria para cloud)

---

**Conclusão**: Desenvolvimento local é **100% viável** e **recomendado** para este projeto! 🎉
