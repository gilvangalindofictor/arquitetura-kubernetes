# Ambiente de Desenvolvimento Local

## Visão Geral

Este documento descreve o ambiente de desenvolvimento local para a plataforma de observabilidade, permitindo desenvolver e testar toda a stack **sem depender da AWS**. Utilizamos Docker Compose para orquestrar todos os componentes.

## Objetivos

- ✅ Desenvolvimento 100% local, sem custos de cloud
- ✅ Ambiente idêntico ao que será deployado no EKS
- ✅ Testes de instrumentação antes do deploy
- ✅ Prototipação de dashboards e alertas
- ✅ Validação do fluxo completo de telemetria

## Estratégia de Desenvolvimento

```
┌─────────────────────────────────────────────────────────┐
│  FASE LOCAL (Docker Compose)                            │
│  ├── Desenvolvimento da stack                           │
│  ├── Criação de dashboards                              │
│  ├── Configuração de alertas                            │
│  ├── Instrumentação de apps exemplo                     │
│  └── Testes de integração                               │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│  MIGRAÇÃO PARA AWS (Terraform + Helm)                   │
│  ├── Deploy infraestrutura (VPC, EKS, S3)               │
│  ├── Deploy stack via Helm                              │
│  ├── Migração de dashboards/alertas                     │
│  └── Validação em cloud                                 │
└─────────────────────────────────────────────────────────┘
```

## Requisitos de Hardware

### Mínimos (Teste Básico)
- **CPU**: 4 cores
- **RAM**: 8 GB
- **Disco**: 20 GB livres
- **Docker**: 4 GB de RAM alocada

### Recomendados (Desenvolvimento Completo)
- **CPU**: 6-8 cores
- **RAM**: 16 GB
- **Disco**: 40 GB livres (SSD recomendado)
- **Docker**: 8 GB de RAM alocada

### Ideais (Testes de Carga)
- **CPU**: 8+ cores
- **RAM**: 32 GB
- **Disco**: 80 GB livres (SSD)
- **Docker**: 16 GB de RAM alocada

## Estimativa de Recursos por Componente

| Componente | CPU (cores) | RAM (MB) | Disco (GB) | Porta |
|------------|-------------|----------|------------|-------|
| **Prometheus** | 0.5-1.0 | 1500-2000 | 10 | 9090 |
| **Grafana** | 0.2-0.5 | 500-800 | 2 | 3000 |
| **Loki** | 0.3-0.7 | 800-1200 | 5 | 3100 |
| **Tempo** | 0.3-0.7 | 800-1200 | 5 | 3200 |
| **OTel Collector** | 0.2-0.5 | 300-500 | 1 | 4317, 4318 |
| **Alertmanager** | 0.1-0.2 | 200-300 | 1 | 9093 |
| **MinIO (S3 local)** | 0.2-0.4 | 500-800 | 10 | 9000, 9001 |
| **App Exemplo** | 0.1-0.2 | 200-300 | 0.5 | 8080 |
| **TOTAL** | **2.0-4.2** | **4800-7100** | **34.5** | - |

### Perfis de Uso

#### Profile: Development (Padrão)
- **Uso**: Desenvolvimento diário, testes unitários
- **Requisitos**: 4 cores, 8 GB RAM, 20 GB disco
- **Configuração**: Retenção de 1 dia, sem persistência

#### Profile: Testing
- **Uso**: Testes de integração, validação de alertas
- **Requisitos**: 6 cores, 12 GB RAM, 30 GB disco
- **Configuração**: Retenção de 3 dias, persistência básica

#### Profile: Production-like
- **Uso**: Simulação de carga, testes de performance
- **Requisitos**: 8 cores, 16 GB RAM, 40 GB disco
- **Configuração**: Retenção de 7 dias, persistência completa

## Stack de Componentes

```yaml
┌─────────────────────────────────────────────────────────┐
│                    Grafana (Visualização)                │
│                    http://localhost:3000                 │
└────────────┬────────────────┬───────────────┬───────────┘
             │                │               │
             ▼                ▼               ▼
┌────────────────┐  ┌─────────────┐  ┌──────────────┐
│  Prometheus    │  │    Loki     │  │    Tempo     │
│   (Métricas)   │  │   (Logs)    │  │  (Traces)    │
│  localhost:9090│  │localhost:3100│ │localhost:3200│
└───────┬────────┘  └──────┬──────┘  └──────┬───────┘
        │                  │                 │
        └──────────────────┼─────────────────┘
                           ▼
              ┌─────────────────────────┐
              │  OpenTelemetry Collector│
              │    localhost:4317/4318  │
              └────────────┬────────────┘
                           │
                           ▼
              ┌─────────────────────────┐
              │   Aplicação Exemplo     │
              │    localhost:8080       │
              └─────────────────────────┘
                           │
                           ▼
              ┌─────────────────────────┐
              │   MinIO (S3 Local)      │
              │    localhost:9000       │
              └─────────────────────────┘
```

## Estrutura de Arquivos

```
localstack/                          # Ambiente local (será renomeado)
├── docker-compose.yml               # Stack completa
├── docker-compose.dev.yml           # Override para desenvolvimento
├── docker-compose.testing.yml       # Override para testes
├── .env.example                     # Variáveis de ambiente
├── README.md                        # Guia de uso
├── init/                            # Scripts de inicialização
│   ├── minio/                       # Setup MinIO (buckets)
│   ├── grafana/                     # Dashboards provisionados
│   ├── prometheus/                  # Configuração Prometheus
│   └── loki/                        # Configuração Loki
├── configs/                         # Arquivos de configuração
│   ├── prometheus.yml
│   ├── loki.yml
│   ├── tempo.yml
│   ├── otel-collector.yml
│   └── alertmanager.yml
├── volumes/                         # Dados persistentes (git-ignored)
│   ├── prometheus/
│   ├── grafana/
│   ├── loki/
│   ├── tempo/
│   └── minio/
└── examples/                        # Aplicações exemplo
    ├── python-app/                  # App Python instrumentado
    ├── load-generator/              # Gerador de carga
    └── synthetic-telemetry/         # Dados sintéticos
```

## Comandos Principais

```bash
# Iniciar stack completa (profile: development)
docker-compose up -d

# Iniciar com profile específico
docker-compose --profile testing up -d

# Ver logs em tempo real
docker-compose logs -f

# Parar stack
docker-compose down

# Parar e limpar volumes (reset completo)
docker-compose down -v

# Ver uso de recursos
docker stats

# Verificar saúde dos serviços
docker-compose ps
```

## Acesso aos Serviços

| Serviço | URL | Credenciais |
|---------|-----|-------------|
| **Grafana** | http://localhost:3000 | admin / admin123 |
| **Prometheus** | http://localhost:9090 | - |
| **Alertmanager** | http://localhost:9093 | - |
| **Loki** | http://localhost:3100 | - |
| **Tempo** | http://localhost:3200 | - |
| **MinIO Console** | http://localhost:9001 | minioadmin / minioadmin |
| **OTel Collector** | localhost:4317 (gRPC), 4318 (HTTP) | - |
| **App Exemplo** | http://localhost:8080 | - |

## Próximos Passos

1. [Configuração Inicial](./setup-guide.md)
2. [Docker Compose Completo](./docker-compose-guide.md)
3. [Configuração VS Code](./vscode-setup.md)
4. [Workflow de Desenvolvimento](./development-workflow.md)
5. [Instrumentação de Apps](./instrumentation-guide.md)
6. [Troubleshooting](./troubleshooting.md)

## Vantagens do Desenvolvimento Local

✅ **Zero custos** - Sem gastar budget AWS durante desenvolvimento  
✅ **Feedback rápido** - Iteração imediata sem esperar deploys  
✅ **Isolamento** - Ambiente próprio sem afetar outros  
✅ **Portabilidade** - Funciona em qualquer máquina com Docker  
✅ **Reprodutibilidade** - Ambiente consistente entre devs  
✅ **Offline-first** - Desenvolvimento sem internet  

## Limitações vs AWS

| Aspecto | Local | AWS/EKS |
|---------|-------|---------|
| **Escalabilidade** | Limitada ao hardware | Auto-scaling |
| **Alta disponibilidade** | Single-point of failure | Multi-AZ |
| **Storage** | Disco local | S3 durável |
| **Network** | Localhost | VPC privada |
| **IAM** | Não aplicável | IRSA granular |
| **Observabilidade da infra** | Básica | CloudWatch integrado |

## Quando Migrar para AWS?

- ✅ Dashboards e alertas validados localmente
- ✅ Instrumentação de apps testada
- ✅ Runbooks escritos e revisados
- ✅ Performance adequada com carga sintética
- ✅ Equipe treinada no uso das ferramentas

---

**Próximo documento**: [Setup Guide](./setup-guide.md)
