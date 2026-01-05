# Ambiente de Desenvolvimento Local - Observabilidade

Este diretório contém toda a configuração necessária para rodar a stack de observabilidade **100% localmente** usando Docker Compose, sem depender da AWS.

## 🚀 Quick Start

```bash
# 1. Configure o ambiente
cp .env.example .env

# 2. Inicie a stack
docker-compose up -d

# 3. Aguarde ~30 segundos para todos os serviços iniciarem

# 4. Acesse os serviços
# Grafana:      http://localhost:3000 (admin/admin123)
# Prometheus:   http://localhost:9090
# Alertmanager: http://localhost:9093
# MinIO:        http://localhost:9001 (minioadmin/minioadmin)
```

## 📊 Serviços Disponíveis

| Serviço | Porta | Descrição |
|---------|-------|-----------|
| **Grafana** | 3000 | Dashboards e visualização |
| **Prometheus** | 9090 | Armazenamento de métricas |
| **Alertmanager** | 9093 | Gerenciamento de alertas |
| **Loki** | 3100 | Agregação de logs |
| **Tempo** | 3200 | Distributed tracing |
| **OTel Collector** | 4317, 4318 | Hub de telemetria |
| **MinIO** | 9000, 9001 | S3-compatible storage |

## 📋 Requisitos

### Mínimos (Teste Básico)
- **CPU**: 4 cores
- **RAM**: 8 GB
- **Disco**: 20 GB livres
- **Docker**: 4 GB de RAM alocada

### Recomendados (Desenvolvimento)
- **CPU**: 6-8 cores
- **RAM**: 16 GB
- **Disco**: 40 GB livres (SSD)
- **Docker**: 8 GB de RAM alocada

## 📁 Estrutura

```
local-dev/
├── docker-compose.yml           # Stack completa
├── .env.example                 # Variáveis de ambiente
├── configs/                     # Configurações dos serviços
│   ├── prometheus.yml
│   ├── loki.yml
│   ├── tempo.yml
│   ├── otel-collector.yml
│   └── alertmanager.yml
├── init/                        # Scripts de inicialização
│   ├── grafana/
│   │   ├── datasources/
│   │   └── dashboards/
│   └── minio/
├── examples/                    # Aplicações exemplo
│   ├── python-app/
│   └── load-generator/
├── tests/                       # Scripts de teste
│   ├── smoke-test.sh
│   └── test-alerts.sh
└── volumes/                     # Dados persistentes (git-ignored)
```

## 🛠️ Comandos Principais

```bash
# Iniciar stack
docker-compose up -d

# Ver status dos serviços
docker-compose ps

# Ver logs
docker-compose logs -f

# Ver logs de um serviço específico
docker-compose logs -f prometheus

# Parar stack
docker-compose down

# Parar e limpar volumes (reset completo)
docker-compose down -v

# Verificar uso de recursos
docker stats

# Reiniciar serviço específico
docker-compose restart prometheus

# Validar configurações
docker-compose config
```

## 🧪 Profiles de Execução

### Profile: Development (Padrão)
Stack básica para desenvolvimento:

```bash
docker-compose up -d
```

### Profile: With App
Inclui aplicação exemplo instrumentada:

```bash
docker-compose --profile with-app up -d
```

### Profile: Load Test
Inclui gerador de carga para testes:

```bash
docker-compose --profile load-test up -d
```

## ✅ Validação

### Health Checks Manuais

```bash
# Prometheus
curl http://localhost:9090/-/healthy

# Grafana
curl http://localhost:3000/api/health

# Loki
curl http://localhost:3100/ready

# Tempo
curl http://localhost:3200/ready

# OTel Collector
curl http://localhost:13133/
```

### Script de Validação

```bash
./tests/smoke-test.sh
```

## 🐛 Troubleshooting

### Porta já em uso

```bash
# Verificar qual processo está usando a porta
sudo lsof -i :3000

# Ou
sudo netstat -tulpn | grep :3000
```

### Container não inicia

```bash
# Ver logs detalhados
docker-compose logs <service-name>

# Exemplo
docker-compose logs prometheus
```

### Recursos insuficientes

```bash
# Ver uso atual
docker stats --no-stream

# Aumentar recursos do Docker Desktop:
# Settings → Resources → Ajustar CPU/Memory
```

### Reset completo

```bash
# Para e remove tudo (containers, volumes, networks)
docker-compose down -v

# Limpa recursos não utilizados
docker system prune -af --volumes

# Reinicia do zero
docker-compose up -d
```

## 📚 Documentação Completa

Para informações detalhadas:

- [Visão Geral do Ambiente Local](../docs/local-dev/README.md)
- [Configuração do VS Code](../docs/local-dev/vscode-setup.md)
- [Workflow de Desenvolvimento](../docs/local-dev/development-workflow.md)
- [Exemplos de Instrumentação](../docs/instrumentation/README.md)

## 🔄 Workflow Recomendado

1. **Desenvolvimento Local**
   - Edite configurações
   - Crie dashboards
   - Defina alertas
   - Teste instrumentação

2. **Validação**
   - Execute smoke tests
   - Faça load tests
   - Valide alertas

3. **Migração para AWS**
   - Atualize Terraform
   - Atualize Helm values
   - Deploy via CI/CD

## 💡 Dicas

- Use `docker-compose logs -f` para debug em tempo real
- Limpe volumes periodicamente: `docker-compose down -v`
- Monitore recursos: `docker stats`
- Configure atalhos no VS Code (veja [vscode-setup.md](../docs/local-dev/vscode-setup.md))
- Use profiles para diferentes cenários de teste

## 🆘 Suporte

Para problemas comuns:
1. Verifique os [health checks](#validação)
2. Consulte [Troubleshooting](#troubleshooting)
3. Veja os logs: `docker-compose logs -f`
4. Abra uma issue no repositório

---

**Próximo passo**: [Setup do VS Code](../docs/local-dev/vscode-setup.md)
