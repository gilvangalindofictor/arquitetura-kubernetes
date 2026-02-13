# Logbook: Keycloak Startup Resilience Fix

**Data**: 2026-02-13
**Duração**: ~2h
**Tipo**: Bug Fix + Hardening
**Componente**: Keycloak SSO (keycloak namespace)
**Status**: Aplicado via kubectl (Terraform atualizado, apply pendente)

---

## Contexto

Keycloak 26.5.1 (Quarkus) apresentava **118 restarts** no pod `keycloak-0`. Investigação revelou múltiplas causas raiz combinadas, todas relacionadas ao ciclo de startup automatizado pelo FinOps (EventBridge liga cluster 07:30 BRT).

### Sintomas Observados

- Pod `keycloak-0`: 118 restarts, último exit code 1
- Logs: `JDBC connection timeout` durante startup (PostgreSQL RDS ainda não disponível)
- Health probes: HTTP 404 em `/auth/health/ready` (smallrye-health desabilitado)
- Scheduling: Pod ficava Pending quando sem toleration para nodes t3.xlarge

---

## Análise de Causa Raiz

### 1. Race Condition FinOps/RDS (Causa Principal)

O FinOps Automation (EventBridge + Lambda) inicia o cluster na ordem:
1. ASG scale-up (nodes)
2. RDS start

Keycloak tentava conectar ao PostgreSQL RDS antes do RDS estar pronto, causando:
```
org.postgresql.util.PSQLException: Connection refused
```

### 2. Health Endpoints Retornando 404

Keycloak 26.x (Quarkus) requer `--health-enabled=true` para ativar o módulo `smallrye-health`. Sem isso, os endpoints `/auth/health/ready` e `/auth/health/live` retornam HTTP 404, fazendo as probes falharem.

Referência: logbook `2026-02-11-keycloak-26-deployment-final.md` documenta que health endpoints herdam o prefixo `--http-relative-path=/auth`.

### 3. startupProbe Insuficiente

A startupProbe anterior tinha `failureThreshold: 30` com `periodSeconds: 5` = 150s de tolerância. Insuficiente para cold starts com migração Liquibase + Quarkus build + RDS warmup.

### 4. Scheduling em Nodes Sem CPU

Nodes `system` e `workloads` estavam com CPU saturada. Nodes `critical` (t3.xlarge) tinham 2.5+ vCPU livres mas possuem taint `workload=critical:NoSchedule`. Keycloak não tinha toleration correspondente.

---

## Correções Aplicadas

### Fix 1: initContainer `wait-for-db`

Adicionado initContainer que aguarda PostgreSQL RDS estar acessível via TCP antes de iniciar o Keycloak.

```yaml
initContainers:
  - name: wait-for-db
    image: busybox:1.36
    command:
      - sh
      - -c
      - |
        echo "Waiting for PostgreSQL..."
        until nc -z <rds-host> 5432; do
          echo "DB not ready, retrying in 5s..."
          sleep 5
        done
        echo "DB is ready!"
    resources:
      requests:
        cpu: 10m
        memory: 16Mi
      limits:
        cpu: 50m
        memory: 32Mi
```

**Aplicado via**: `kubectl patch statefulset keycloak -n keycloak --type='json'`

### Fix 2: `--health-enabled=true`

Adicionado argumento ao container Keycloak para habilitar smallrye-health.

```
args: ["start", "--http-relative-path=/auth", "--health-enabled=true"]
```

**Aplicado via**: `kubectl patch statefulset keycloak -n keycloak --type='json'`

### Fix 3: startupProbe Expandida

```yaml
startupProbe:
  httpGet:
    path: /auth/health/ready
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 5
  timeoutSeconds: 5
  failureThreshold: 60  # 330s total (era 150s)
```

Liveness e readiness probes tiveram `initialDelaySeconds` removido (startupProbe já faz o gate).

**Aplicado via**: `kubectl patch statefulset keycloak -n keycloak --type='json'`

### Fix 4: Toleration `workload=critical`

```yaml
tolerations:
  - key: workload
    operator: Equal
    value: critical
    effect: NoSchedule
```

Permite scheduling nos nodes t3.xlarge que possuem CPU livre.

**Aplicado via**: `kubectl patch statefulset keycloak -n keycloak --type='json'`

---

## Resultado

Após `kubectl delete pod keycloak-0 -n keycloak` para forçar recriação:

- Pod `keycloak-0`: **Running, 0 restarts**
- Startup time: **~20s** (Quarkus optimized)
- Health probes: HTTP 200 em `/auth/health/ready` e `/auth/health/live`
- Node scheduling: `critical` nodes (t3.xlarge) com CPU livre
- initContainer: Validou conectividade PostgreSQL antes do start

---

## Persistência no Terraform

### Arquivos Modificados

1. **`modules/keycloak/values.yaml.tpl`**:
   - Adicionado `--health-enabled=true` ao command
   - Adicionado `extraInitContainers` com wait-for-db
   - startupProbe: `failureThreshold: 60` (330s)
   - liveness/readiness: `initialDelaySeconds: 0`
   - Adicionado `tolerations` para `workload=critical`

2. **`modules/keycloak/main.tf`**:
   - Adicionado `postgresql_host` e `postgresql_port` ao templatefile()

3. **`environments/staging/main.tf`**:
   - Alterado `replicas = 2` para `replicas = 1` (staging aceito)

### Status Terraform Apply

**NÃO APLICADO** — Keycloak foi deployado manualmente (kubectl), não via Helm/Terraform. Um `terraform apply` tentaria criar o Helm release do zero, conflitando com o deployment manual existente.

**Ação Futura**: Em janela de manutenção, importar o release existente (`terraform import`) ou recriar via Terraform (destroy manual + apply).

---

## Bloqueadores Resolvidos Nesta Sessão

| # | Bloqueador | Status Anterior | Status Atual | Resolução |
|---|-----------|----------------|-------------|-----------|
| 1 | Security Groups Dependencies (T5) — 10 orphan SGs | ABERTO (docs) | **RESOLVIDO** | Confirmado via logbook `2026-02-13-security-groups-cleanup-completion.md`. Docs atualizados. |
| 2 | Keycloak restarts (118) + CPU insuficiente | ABERTO | **RESOLVIDO** | 4 fixes aplicados (initContainer, health, startupProbe, toleration). CPU não é mais bloqueador. |
| 3 | Prometheus Operator stuck Pending | ABERTO (docs) | **RESOLVIDO** | Já resolvido em 2026-02-09 (ADR-042). Docs atualizados. |

---

## Documentos de Contexto Atualizados

- `docs/context/current_state.md`: Versão Keycloak 26.5.1, seção Bloqueadores Conhecidos, CI/CD Platform table
- `docs/context/architecture.md`: GAP-001 Keycloak section com startup resilience
- `docs/KEYCLOAK-SONARQUBE-QUICK-REFERENCE.md`: Critical issues resolvidos, facts atualizados

---

## Commit

```
Commit: 4b2b0a3
Mensagem: fix(keycloak): add startup resilience - initContainer wait-for-db, health probes, tolerations
Co-Authored-By: Claude <noreply@anthropic.com>
```

---

## Validação Pendente

- [ ] Confirmar 0 restarts após próximo ciclo FinOps (shutdown 20:00 → startup 07:30 BRT)
- [ ] Terraform import ou recriação em janela de manutenção
- [ ] Monitorar Grafana dashboard Keycloak por 48h

---

**Autor**: Claude (AI) + Gilvan Galindo
**Co-Authored-By**: Claude <noreply@anthropic.com>
