# 🚀 Guia Rápido - Comandos Essenciais

## Setup Inicial (Uma Vez)

```bash
# 1. Clonar e entrar no diretório
cd Observabilidade/local-dev

# 2. Configurar ambiente
cp .env.example .env

# 3. Criar estrutura de volumes (opcional, Docker cria automático)
mkdir -p volumes/{prometheus,grafana,loki,tempo,minio}

# 4. Validar configuração
docker-compose config
```

## Gerenciamento da Stack

### Iniciar

```bash
# Stack básica
docker-compose up -d

# Com app exemplo
docker-compose --profile with-app up -d

# Ver logs durante inicialização
docker-compose up
```

### Parar

```bash
# Parar mantendo volumes (dados persistem)
docker-compose down

# Parar e limpar volumes (CUIDADO: perde dados)
docker-compose down -v
```

### Status

```bash
# Ver status de todos os serviços
docker-compose ps

# Ver uso de recursos
docker stats

# Ver uso de recursos (snapshot)
docker stats --no-stream
```

### Restart

```bash
# Reiniciar tudo
docker-compose restart

# Reiniciar serviço específico
docker-compose restart prometheus
docker-compose restart grafana
```

## Logs

```bash
# Logs de todos os serviços (tempo real)
docker-compose logs -f

# Logs de serviço específico
docker-compose logs -f prometheus
docker-compose logs -f grafana
docker-compose logs -f otel-collector

# Últimas 50 linhas
docker-compose logs --tail=50

# Logs com timestamp
docker-compose logs -f --timestamps

# Filtrar por palavra
docker-compose logs -f | grep -i error
docker-compose logs -f | grep -i warning
```

## Health Checks

```bash
# Verificar todos os serviços
curl http://localhost:9090/-/healthy    # Prometheus
curl http://localhost:3000/api/health   # Grafana
curl http://localhost:3100/ready        # Loki
curl http://localhost:3200/ready        # Tempo
curl http://localhost:13133/            # OTel Collector
curl http://localhost:9000/minio/health/live  # MinIO

# Script automatizado (criar em tests/health-check.sh)
for port in 9090 3000 3100 3200 13133; do
  echo -n "Port $port: "
  curl -s -o /dev/null -w "%{http_code}" http://localhost:$port && echo " ✅" || echo " ❌"
done
```

## Aplicar Mudanças de Configuração

```bash
# 1. Editar arquivo de config
vim configs/prometheus.yml

# 2. Validar sintaxe (se ferramenta disponível)
promtool check config configs/prometheus.yml

# 3. Recarregar config sem reiniciar (Prometheus)
curl -X POST http://localhost:9090/-/reload

# 4. Ou reiniciar o container
docker-compose restart prometheus

# 5. Verificar logs
docker-compose logs -f prometheus | head -20
```

## Debug de Containers

```bash
# Entrar no container
docker exec -it obs-prometheus sh
docker exec -it obs-grafana bash

# Ver variáveis de ambiente
docker exec obs-prometheus env

# Ver logs do Docker (não compose)
docker logs obs-prometheus

# Inspecionar container
docker inspect obs-prometheus | jq

# Ver processos dentro do container
docker top obs-prometheus

# Ver filesystem do container
docker exec obs-prometheus ls -la /etc/prometheus
```

## Limpeza e Manutenção

```bash
# Remover volumes não usados
docker volume prune

# Remover containers parados
docker container prune

# Limpar tudo (CUIDADO!)
docker system prune -af --volumes

# Ver espaço usado pelo Docker
docker system df

# Limpar apenas volumes do projeto
docker-compose down -v
```

## Testes

### Enviar Telemetria Manualmente

```bash
# Enviar métrica (Prometheus format)
echo "test_metric{job=\"manual\"} 42" | curl --data-binary @- http://localhost:9090/api/v1/write

# Enviar log (Loki)
curl -X POST http://localhost:3100/loki/api/v1/push \
  -H "Content-Type: application/json" \
  -d '{
    "streams": [{
      "stream": {"job": "test", "level": "info"},
      "values": [["'$(date +%s)000000000'", "Test log message"]]
    }]
  }'

# Enviar trace (OTLP HTTP)
curl -X POST http://localhost:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{"resourceSpans": []}'
```

### Gerar Carga

```bash
# Usando hey (instalar: go install github.com/rakyll/hey@latest)
hey -n 100 -c 10 http://localhost:8080/api/health

# Usando Apache Bench
ab -n 1000 -c 50 http://localhost:8080/

# Usando curl em loop
for i in {1..100}; do
  curl http://localhost:8080/api/users
  sleep 0.1
done
```

## Queries Úteis

### Prometheus (http://localhost:9090)

```promql
# Ver todos os targets up
up

# Ver uso de memória dos containers
container_memory_usage_bytes

# Taxa de requisições por segundo
rate(http_requests_total[5m])

# Latência P95
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
```

### Loki (http://localhost:3100 ou via Grafana)

```logql
# Todos os logs
{job="prometheus"}

# Logs com erro
{job="prometheus"} |= "error"

# Logs JSON parseados
{job="app"} | json | level="error"

# Rate de logs
rate({job="app"}[1m])
```

### Tempo (via Grafana → Explore → Tempo)

```
# Buscar por service name
{service.name="example-app"}

# Buscar por span name
{name="GET /api/users"}

# Buscar traces com erro
{status=error}
```

## Acessos Rápidos (Bookmarks)

```bash
# Grafana
open http://localhost:3000
# Login: admin / admin123

# Prometheus
open http://localhost:9090

# Prometheus Targets
open http://localhost:9090/targets

# Alertmanager
open http://localhost:9093

# MinIO Console
open http://localhost:9001
# Login: minioadmin / minioadmin

# Loki (via Grafana Explore)
open http://localhost:3000/explore?orgId=1&left=%7B%22datasource%22:%22loki%22%7D
```

## Troubleshooting Rápido

### Porta já em uso

```bash
# Descobrir o que está usando a porta
sudo lsof -i :3000
sudo netstat -tulpn | grep :3000

# Matar processo
sudo kill -9 <PID>

# Ou mudar porta no .env
echo "GRAFANA_PORT=3001" >> .env
docker-compose up -d
```

### Container não inicia

```bash
# Ver erro
docker-compose logs <service-name>

# Ver eventos do Docker
docker events --since 5m

# Verificar recursos
docker stats --no-stream

# Tentar iniciar manualmente
docker-compose up <service-name>
```

### Reset completo

```bash
# Parar tudo
docker-compose down -v

# Limpar Docker
docker system prune -af --volumes

# Reiniciar Docker (macOS/Windows)
# Docker Desktop → Restart

# Iniciar novamente
docker-compose up -d
```

## Atalhos úteis (Adicionar ao .bashrc/.zshrc)

```bash
# Aliases
alias dc='docker-compose'
alias dcup='docker-compose up -d'
alias dcdown='docker-compose down'
alias dclogs='docker-compose logs -f'
alias dcps='docker-compose ps'
alias dcrestart='docker-compose restart'

# Funções
dclog() {
  docker-compose logs -f "$1"
}

dcexec() {
  docker-compose exec "$1" sh
}

# Uso:
# dclog prometheus
# dcexec grafana
```

## VS Code Tasks (Ctrl+Shift+P → Tasks: Run Task)

Se você configurou o `.vscode/tasks.json`:

- `Start Observability Stack`
- `Stop Observability Stack`
- `View Logs - All Services`
- `Check Stack Health`
- `Reset Environment`

Ou use os atalhos de teclado:
- `Ctrl+Shift+D S` - Start
- `Ctrl+Shift+D Q` - Stop
- `Ctrl+Shift+D L` - Logs
- `Ctrl+Shift+D H` - Health

---

## 🆘 Precisa de Ajuda?

1. Consulte [Workflow - Troubleshooting](./development-workflow.md#4-debug-e-troubleshooting)
2. Veja logs: `docker-compose logs -f | grep -i error`
3. Valide configs: `docker-compose config`
4. Reset completo: `docker-compose down -v && docker-compose up -d`

---

**Dica**: Imprima esta página ou mantenha aberta durante desenvolvimento! 📌
