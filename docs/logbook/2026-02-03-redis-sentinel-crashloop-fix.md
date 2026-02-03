# 📓 Diário de Bordo — Redis Sentinel CrashLoopBackOff Fix

| Campo          | Valor                                    |
|----------------|------------------------------------------|
| **Data**       | 2026-02-03                               |
| **Demanda**    | Resolver Sentinel CrashLoopBackOff       |
| **Impacto**    | Alto (HA Redis comprometida)             |
| **Agentes**    | Orquestrador, K8s Specialist, Security   |
| **Status**     | ✅ Concluído                             |
| **Duração**    | ~26min (12:33 - 13:01)                   |

---

## Timeline

```
[12:33:00] Análise | Orq | 3 Sentinels CrashLoopBackOff, erro Permission denied /redis/sentinel.conf | impacto: alto
[12:33:30] Investigação | K8s | PSS Restricted namespace, readOnlyRootFilesystem=true | ✅
[12:35:00] Diagnóstico | K8s | Init container user 1000 ≠ main container user 1001 | ⚠️ Causa raiz
[12:38:00] Fix Tentativa 1 | K8s | Patch deployment runAsUser 1000→1001 | ❌ Operator reverteu
[12:40:00] Fix v2 | K8s | Patch RedisFailover CR: user 1001→1000 (align init) | ✅
[12:42:00] Scale Test | K8s | scale 0→3 para rollout limpo | 🔄
[12:45:00] Bloqueio | Sec | Operator WRONGPASS - secret divergente | ⚠️
[12:47:00] Investigação Auth | Sec | Secret password ≠ pod REDIS_PASSWORD | ❌
[12:50:00] Fix Auth | Sec | Recreate secret com senha real do pod | ✅
[12:52:00] Bloqueio Operator | Orq | Dual operators (redisoperator + redis-operator) | ⚠️
[12:54:00] Cleanup | Orq | Scale down operator antigo, delete lease | ✅
[12:56:00] Restart Operator | Orq | Force pod recreate para reload secret | 🔄
[12:59:00] Reconciliação | Operator | "New master rfr-redis-0 10.0.144.105" - auth OK | ✅
[12:59:14] Auto-discovery | Sentinel | Sentinels descobriram master (127.0.0.1→10.0.144.105) | ✅
[13:00:00] Quorum OK | Sentinel | 3/3 Sentinels READY, quorum operational | ✅
[13:01:00] DocSync | Orq | architecture.md, decisions.md, logbook | ✅
```

---

## Problemas Identificados e Soluções

### 1. Permission Denied — Init Container User Mismatch

**Sintoma:**
```
Sentinel config file /redis/sentinel.conf is not writable: Permission denied. Exiting...
```

**Causa Raiz:**
- Spotahome Redis Operator injeta init container `sentinel-config-copy` com `runAsUser: 1000`
- RedisFailover CR configurado com `runAsUser: 1001` no main container
- Init container copia arquivo com owner 1000, main container (user 1001) não consegue escrever
- PSS Restricted impede `chown`/`chmod` no init container

**Solução:**
- Alinhar **TODO** o SecurityContext para `runAsUser: 1000` (Sentinel + Redis)
- Operador hardcodes init user, logo CR deve seguir esse padrão

**Arquivos:**
- `modules/redis/main.tf:195-205` (Sentinel securityContext)
- `modules/redis/main.tf:234-245` (Redis securityContext)

---

### 2. Operator Authentication Failure (WRONGPASS)

**Sintoma:**
```
Make new master failed, master ip: 10.0.153.5, error: WRONGPASS invalid username-password pair or user is disabled.
```

**Causa Raiz:**
- Secret `redis-password` criado pelo Terraform com senha gerada randomicamente
- Redis pods inicializados com essa senha via env `REDIS_PASSWORD`
- Secret foi modificado (manualmente ou por reconciliação) APÓS pods subirem
- Operator lê secret divergente, não consegue autenticar no Redis master

**Solução:**
1. Extrair senha REAL do pod: `kubectl exec rfr-redis-0 -- sh -c 'echo "$REDIS_PASSWORD"'`
2. Recriar secret com senha correta: `(ZqDJhlChSzP7VT)of$!rLLG8}l#eJe9`
3. Force restart operator pod para reload secret (secrets não são hot-reloaded)

---

### 3. Dual Redis Operators em Leader Election Race

**Sintoma:**
- 2 deployments: `redisoperator` (22h) + `redis-operator` (14h)
- Operator antigo com lease, mas errors WRONGPASS contínuos
- Operator novo stuck em "attempting to acquire lease"

**Causa Raiz:**
- Instalação manual antiga (`redisoperator`) não removida
- Terraform deploy criou novo operator (`redis-operator`)
- Leader election favor operator antigo quebrado

**Solução:**
```bash
kubectl scale deployment redisoperator -n redis-operator --replicas=0
kubectl delete lease redis-failover-lease -n redis-operator  # Force re-election
```

---

### 4. Sentinel Custom Config Inválido

**Sintoma:**
```
error on object processing: ERR Unknown option or number of arguments for SENTINEL SET 'sentinel'
```

**Causa Raiz:**
- Tentativa de override `sentinel monitor` via `customConfig` no CR
- Sintaxe incorreta: `customConfig: ["sentinel monitor mymaster rfrm-redis... 6379 2"]`
- Redis Sentinel rejeita config inválida

**Solução:**
- Remover `customConfig` do Sentinel spec
- Operator + Sentinels fazem auto-discovery corretamente do master
- ConfigMap base (`127.0.0.1`) é sobrescrito dinamicamente pelos Sentinels após quorum

---

## Lições Aprendidas

### 🔒 Security & PSS Restricted

| # | Lição | Impacto |
|---|-------|---------|
| 1 | **Spotahome Redis Operator hardcodes init container `runAsUser: 1000`** → RedisFailover CR **DEVE** usar `runAsUser: 1000` em todo SecurityContext | 🔴 Crítico |
| 2 | PSS Restricted bloqueia `allowPrivilegeEscalation`, `chown`, `chmod` → única solução é **user alignment** | 🟡 Médio |
| 3 | `readOnlyRootFilesystem: true` no Sentinel requer init container para copiar config writable → filesystem `/redis-writable` (emptyDir) | 🟢 Baixo |

### 🔐 Secrets & Authentication

| # | Lição | Impacto |
|---|-------|---------|
| 4 | **Secrets não são hot-reloaded** → mudanças em secret requerem restart do pod consumidor | 🟡 Médio |
| 5 | Operator cria secret `redis-password` via Terraform, mas pode divergir do usado pelos pods → **sempre validar sync** com `kubectl exec -- echo "$REDIS_PASSWORD"` | 🔴 Crítico |
| 6 | ConfigMap `rfr-redis` tem senha hardcoded **diferente** do secret → Operator inconsistency conhecida | 🟡 Médio |

### 🎛️ Operator Management

| # | Lição | Impacto |
|---|-------|---------|
| 7 | **Múltiplos operators** com mesmo CRD causam reconciliation loops → garantir operator único por namespace/cluster | 🔴 Crítico |
| 8 | Leader election lease persiste após pod death → `kubectl delete lease` para forçar re-election | 🟢 Baixo |
| 9 | Operator logs são **críticos** para debug → sempre verificar `WRONGPASS`, `error on object processing` | 🟡 Médio |

### 🔄 Sentinel Auto-Discovery

| # | Lição | Impacto |
|---|-------|---------|
| 10 | ConfigMap inicial com `sentinel monitor mymaster 127.0.0.1` é **normal** → Sentinels fazem auto-discovery após quorum | 🟢 Baixo |
| 11 | Sentinels precisam quorum (2/3) para descobrir master → rollout gradual pode causar `+sdown` temporário | 🟢 Baixo |
| 12 | `customConfig` para override `sentinel monitor` **NÃO funciona** → deixar auto-discovery | 🟡 Médio |

### ⚙️ Deployment Strategies

| # | Lição | Impacto |
|---|-------|---------|
| 13 | **Scale 0→3** é mais rápido que rollout gradual quando há CrashLoopBackOff → limpa estado corrupto | 🟡 Médio |
| 14 | Operator reverte patches manuais no Deployment → **sempre patchar o CR** (`RedisFailover`), não recursos gerenciados | 🔴 Crítico |
| 15 | PVC resize warnings (`field can not be less than previous value`) são noise → storage já provisionado, ignorar | 🟢 Baixo |

---

## Métricas

| Métrica | Valor |
|---------|-------|
| Tempo total | 26 minutos |
| Tentativas de fix | 4 |
| Pods recriados | ~15 (3 Sentinels × 5 rollouts) |
| Operator restarts | 3 |
| Downtime Sentinel HA | ~20min (12:33-12:53) |
| Downtime Redis master | 0 (não afetado) |

---

## Validação Final

```bash
# Sentinels READY
kubectl get pods -n data-services -l app.kubernetes.io/component=sentinel
# 3/3 Running 1/1

# Quorum OK
kubectl exec rfs-redis-7459d89b5d-6x6fx -n data-services -c sentinel -- \
  redis-cli -p 26379 sentinel ckquorum mymaster
# OK 3 usable Sentinels. Quorum and failover authorization can be reached

# Master descoberto
kubectl exec rfs-redis-7459d89b5d-6x6fx -n data-services -c sentinel -- \
  redis-cli -p 26379 sentinel get-master-addr-by-name mymaster
# 10.0.144.105
# 6379

# Operator sem erros auth
kubectl logs -n redis-operator -l app.kubernetes.io/name=redis-operator --tail=20 | grep WRONGPASS
# (sem output = OK)
```

---

## Referências

- [ADR-024 - Redis Sentinel User Alignment for PSS Restricted](../context/decisions.md#adr-024)
- [Spotahome Redis Operator GitHub](https://github.com/spotahome/redis-operator)
- [PSS Restricted Profile](https://kubernetes.io/docs/concepts/security/pod-security-standards/#restricted)
- Terraform module: `modules/redis/main.tf`
