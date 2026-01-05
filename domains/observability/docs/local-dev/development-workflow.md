# Workflow de Desenvolvimento - Local

## Visão Geral

Este documento descreve o fluxo de trabalho completo para desenvolver, testar e validar mudanças no ambiente local antes de fazer deploy na AWS.

## Ciclo de Desenvolvimento

```
┌──────────────────────────────────────────────────────────┐
│ 1. SETUP INICIAL                                         │
│    └─ Clonar repo → Configurar env → Iniciar stack      │
└────────────────┬─────────────────────────────────────────┘
                 ▼
┌──────────────────────────────────────────────────────────┐
│ 2. DESENVOLVIMENTO                                       │
│    ├─ Editar configs                                     │
│    ├─ Criar dashboards                                   │
│    ├─ Definir alertas                                    │
│    └─ Instrumentar apps                                  │
└────────────────┬─────────────────────────────────────────┘
                 ▼
┌──────────────────────────────────────────────────────────┐
│ 3. TESTE LOCAL                                           │
│    ├─ Validar configs                                    │
│    ├─ Testar queries                                     │
│    ├─ Simular alertas                                    │
│    └─ Gerar telemetria                                   │
└────────────────┬─────────────────────────────────────────┘
                 ▼
┌──────────────────────────────────────────────────────────┐
│ 4. VALIDAÇÃO                                             │
│    ├─ Smoke tests                                        │
│    ├─ Load tests                                         │
│    └─ Revisão de peers                                   │
└────────────────┬─────────────────────────────────────────┘
                 ▼
┌──────────────────────────────────────────────────────────┐
│ 5. MIGRAÇÃO PARA AWS                                     │
│    ├─ Atualizar Terraform                                │
│    ├─ Atualizar Helm values                              │
│    └─ Deploy via CI/CD                                   │
└──────────────────────────────────────────────────────────┘
```

## 1. Setup Inicial

### Primeira Vez

```bash
# 1. Clonar repositório
git clone <repo-url>
cd Observabilidade

# 2. Configurar ambiente
cd local-dev
cp .env.example .env
# Edite .env se necessário

# 3. Criar estrutura de volumes
mkdir -p volumes/{prometheus,grafana,loki,tempo,minio}

# 4. Validar configurações
docker-compose config

# 5. Iniciar stack
docker-compose up -d

# 6. Verificar saúde
docker-compose ps
docker-compose logs -f | grep -i error
```

### Validação do Setup

```bash
# Health checks
curl -f http://localhost:9090/-/healthy  # Prometheus
curl -f http://localhost:3000/api/health # Grafana
curl -f http://localhost:3100/ready      # Loki
curl -f http://localhost:3200/ready      # Tempo
curl -f http://localhost:13133/          # OTel Collector

# Ou use o script de validação
./validate-stack.sh
```

## 2. Fluxo de Desenvolvimento

### Modificar Configurações

```bash
# 1. Editar arquivo de config
vim local-dev/configs/prometheus.yml

# 2. Validar sintaxe (se disponível)
promtool check config local-dev/configs/prometheus.yml

# 3. Aplicar mudança (restart container)
docker-compose restart prometheus

# 4. Verificar logs
docker-compose logs -f prometheus

# 5. Testar no UI
# Abrir http://localhost:9090
```

### Criar Dashboards

```bash
# Workflow 1: Criar no Grafana UI
# 1. Acesse http://localhost:3000
# 2. Crie o dashboard visualmente
# 3. Exporte como JSON (Share → Export → Save to file)
# 4. Salve em: infra/grafana/dashboards/
# 5. Commit no Git

# Workflow 2: Editar JSON diretamente
# 1. Edite o arquivo JSON
# 2. Importe no Grafana (+ → Import → Upload JSON file)
# 3. Valide visualmente
# 4. Ajuste e re-exporte se necessário
```

### Definir Alertas

```bash
# 1. Criar arquivo de alerta
cat > local-dev/configs/alerts/custom-alerts.yml <<EOF
groups:
  - name: custom_alerts
    interval: 30s
    rules:
      - alert: HighMemoryUsage
        expr: container_memory_usage_bytes / container_spec_memory_limit_bytes > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage detected"
          description: "Container {{ \$labels.container }} memory usage is above 90%"
EOF

# 2. Recarregar configuração do Prometheus
curl -X POST http://localhost:9090/-/reload

# 3. Verificar regra carregada
curl http://localhost:9090/api/v1/rules | jq

# 4. Simular condição de alerta (gerar carga)
docker-compose --profile load-test up -d

# 5. Verificar alerta no Alertmanager
curl http://localhost:9093/api/v2/alerts | jq
```

### Instrumentar Aplicação

```bash
# 1. Criar app exemplo
cd local-dev/examples/python-app

# 2. Adicionar dependências
cat > requirements.txt <<EOF
opentelemetry-api==1.23.0
opentelemetry-sdk==1.23.0
opentelemetry-instrumentation-flask==0.44b0
opentelemetry-exporter-otlp==1.23.0
flask==3.0.0
EOF

# 3. Implementar instrumentação (ver exemplo completo abaixo)
vim app.py

# 4. Testar localmente
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python app.py

# 5. Containerizar
docker build -t example-app:local .

# 6. Executar com stack
docker-compose --profile with-app up -d

# 7. Gerar requisições
curl http://localhost:8080/api/users
curl http://localhost:8080/api/health

# 8. Visualizar traces no Grafana
# Grafana → Explore → Tempo → Query
```

## 3. Testes

### Smoke Tests

```bash
#!/bin/bash
# local-dev/tests/smoke-test.sh

echo "=== Smoke Tests ==="

# 1. Todos os serviços estão rodando?
if [ $(docker-compose ps | grep -c "Up") -lt 7 ]; then
  echo "❌ Nem todos os serviços estão rodando"
  exit 1
fi
echo "✅ Todos os serviços estão up"

# 2. Prometheus tem targets?
targets=$(curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length')
if [ "$targets" -lt 5 ]; then
  echo "❌ Prometheus tem poucos targets: $targets"
  exit 1
fi
echo "✅ Prometheus tem $targets targets"

# 3. Grafana tem datasources?
datasources=$(curl -s -u admin:admin123 http://localhost:3000/api/datasources | jq 'length')
if [ "$datasources" -lt 3 ]; then
  echo "❌ Grafana tem poucos datasources: $datasources"
  exit 1
fi
echo "✅ Grafana tem $datasources datasources"

# 4. Loki está ingerindo logs?
# Enviar log de teste
echo '{"streams": [{"stream": {"source": "test"}, "values": [["'$(date +%s)000000000'", "test message"]]}]}' | \
  curl -X POST -H "Content-Type: application/json" -d @- http://localhost:3100/loki/api/v1/push

sleep 2

# Query logs
log_count=$(curl -s 'http://localhost:3100/loki/api/v1/query?query={source="test"}' | jq '.data.result | length')
if [ "$log_count" -eq 0 ]; then
  echo "❌ Loki não está ingerindo logs"
  exit 1
fi
echo "✅ Loki está ingerindo logs"

echo "=== Todos os testes passaram! ==="
```

### Load Tests

```bash
# Usando hey (HTTP load generator)
# Instalar: go install github.com/rakyll/hey@latest

# Teste básico - 100 requests, 10 concurrent
hey -n 100 -c 10 http://localhost:8080/api/users

# Teste de stress - 10k requests, 50 concurrent, 30s
hey -z 30s -c 50 http://localhost:8080/api/users

# Durante o teste, monitore:
# - Grafana: Dashboard "Golden Signals"
# - Prometheus: Queries de latência e taxa de erro
# - Docker stats: Uso de recursos
watch -n 2 'docker stats --no-stream'
```

### Teste de Alertas

```bash
#!/bin/bash
# local-dev/tests/test-alerts.sh

echo "=== Testando Alertas ==="

# 1. Forçar condição de alerta
# Exemplo: Alto uso de CPU
docker run -d --name stress-test --rm \
  --cpus=".5" \
  progrium/stress --cpu 2 --timeout 300s

# 2. Aguardar tempo do 'for' da regra (ex: 5m)
echo "Aguardando 5 minutos para alerta disparar..."
sleep 300

# 3. Verificar se alerta está ativo
active_alerts=$(curl -s http://localhost:9093/api/v2/alerts | jq '[.[] | select(.status.state == "active")] | length')

if [ "$active_alerts" -gt 0 ]; then
  echo "✅ Alerta disparado! $active_alerts alertas ativos"
  curl -s http://localhost:9093/api/v2/alerts | jq '.[] | {alert: .labels.alertname, severity: .labels.severity, state: .status.state}'
else
  echo "❌ Nenhum alerta disparado"
  exit 1
fi

# 4. Limpar
docker stop stress-test
```

## 4. Debug e Troubleshooting

### Logs Estruturados

```bash
# Ver logs de todos os serviços
docker-compose logs -f

# Filtrar por serviço
docker-compose logs -f prometheus

# Filtrar por nível (erro)
docker-compose logs -f | grep -i error

# Logs com timestamp
docker-compose logs -f --timestamps

# Últimas 50 linhas
docker-compose logs --tail=50
```

### Inspecionar Containers

```bash
# Ver configuração do container
docker inspect obs-prometheus | jq

# Ver variáveis de ambiente
docker exec obs-prometheus env

# Entrar no container
docker exec -it obs-prometheus sh

# Ver uso de recursos em tempo real
docker stats
```

### Queries de Debug

```promql
# Prometheus - Ver targets down
up == 0

# Loki - Ver erros recentes
{level="error"} |= "error" | json

# Tempo - Ver spans com erros
{status="error"}
```

## 5. Migração para AWS

### Checklist Pré-Migração

- [ ] Todos os dashboards testados localmente
- [ ] Alertas validados (firing + resolved)
- [ ] Queries otimizadas (< 1s de resposta)
- [ ] Retenções definidas e testadas
- [ ] Documentação atualizada (runbooks)
- [ ] Instrumentação validada com app exemplo
- [ ] Load tests executados com sucesso
- [ ] Custos estimados revisados

### Processo de Migração

```bash
# 1. Exportar dashboards do Grafana local
cd infra/grafana/dashboards
curl -u admin:admin123 \
  'http://localhost:3000/api/search?type=dash-db' | \
  jq -r '.[].uid' | \
  xargs -I {} curl -u admin:admin123 \
    'http://localhost:3000/api/dashboards/uid/{}' | \
  jq '.dashboard' > exported-dashboard.json

# 2. Atualizar Helm values com configs testadas
# Copiar de local-dev/configs/ para infra/helm/*/values.yaml
# Ajustar endpoints (minio → S3, localhost → service DNS)

# 3. Atualizar Terraform com recursos necessários
cd infra/terraform
terraform plan

# 4. Deploy
terraform apply
helm install prometheus ./helm/kube-prometheus-stack -n observability-prd
# ... outros deploys

# 5. Validar no AWS
kubectl get pods -n observability-prd
kubectl port-forward -n observability-prd svc/grafana 3000:3000
```

## Boas Práticas

### ✅ Sempre Faça

- Commit pequeno e frequente
- Teste mudanças localmente antes de commitar
- Documente decisões em ADRs
- Use branches para features grandes
- Execute smoke tests antes de push
- Mantenha .env.example atualizado
- Limpe volumes periodicamente (`docker-compose down -v`)

### ❌ Evite

- Commitar senhas/secrets
- Modificar múltiplos componentes simultaneamente
- Deploy para AWS sem testar localmente
- Ignorar warnings de recursos (CPU/RAM)
- Usar `latest` tag em imagens Docker (fixe versões)

## Comandos Rápidos

```bash
# Start stack
docker-compose up -d

# Ver status
docker-compose ps

# Logs em tempo real
docker-compose logs -f

# Restart serviço específico
docker-compose restart prometheus

# Parar tudo
docker-compose down

# Reset completo (WARNING: perde dados)
docker-compose down -v

# Ver uso de recursos
docker stats --no-stream

# Validar configs
docker-compose config

# Executar smoke tests
./tests/smoke-test.sh

# Iniciar com app exemplo
docker-compose --profile with-app up -d
```

---

**Próximo documento**: [Exemplos de Instrumentação](../instrumentation/README.md)
