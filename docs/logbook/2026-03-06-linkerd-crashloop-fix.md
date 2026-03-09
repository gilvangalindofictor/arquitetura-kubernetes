# Linkerd Control Plane CrashLoopBackOff — Fix 2026-03-06

**Duração do incidente:** ~14h (iniciou 2026-03-05 ~20:00 -03:00)
**Resolução:** 2026-03-06 ~11:00 -03:00
**Severidade:** P1 — mTLS comprometido em toda a malha

## Sintomas

3 pods do Linkerd control plane em CrashLoopBackOff com ~172 restarts:
- `linkerd-destination` — Init:CrashLoopBackOff (exit 95 no network-validator)
- `linkerd-identity` — Init:CrashLoopBackOff (exit 95 no network-validator)
- `linkerd-proxy-injector` — CrashLoopBackOff (exit 137, proxy sem identidade)
- `linkerd-viz/tap-injector` — Init:CrashLoopBackOff (exit 95, mesmo problema)

Todos schedulados no nó `ip-10-0-148-109.ec2.internal` (AGE=14h no momento do incidente).

## Causa Raiz

**Race condition entre node scale-up e Linkerd CNI plugin.**

Ao subir novos nós (cluster autoscaler), o Kubelet tenta agendar pods imediatamente. O `linkerd-network-validator` init container (exit code 95) falha porque tenta validar que o iptables redirect do CNI está funcional conectando a `1.1.1.1:20001` via porta 4140 — mas o CNI ainda não configurou as regras iptables no nó.

Evidências:
- Exit Code 95 = linkerd2-network-validator falhou em estabelecer conexão via iptables
- `--connect-addr 1.1.1.1:20001 --listen-addr 0.0.0.0:4140 --timeout 10s`
- Logs do CNI no nó mostravam `NetworkPluginNotReady` nos primeiros minutos

O mesmo problema ocorreu com `tap-injector` no nó `ip-10-0-139-148` (criado pelo autoscaler durante a remediação, AGE=2m quando o pod foi schedulado).

## Resolução

Deletar os pods crashando para que sejam recriados em nós com CNI já estabilizado:

```bash
# Ordem de deleção: identity primeiro (mais crítico para mTLS)
kubectl delete pod -n linkerd -l linkerd.io/control-plane-component=identity
# Aguardar 2/2 Running (~30s)
kubectl delete pod -n linkerd -l linkerd.io/control-plane-component=destination
# Aguardar 4/4 Running (~30s)
kubectl delete pod -n linkerd -l linkerd.io/control-plane-component=proxy-injector

# linkerd-viz
kubectl delete pod -n linkerd-viz -l linkerd.io/control-plane-component=tap-injector
# Se recriar em nó novo (race condition novamente), aguardar CNI Ready e deletar de novo
```

**Atenção:** Se o scheduler manda o pod para um nó recém-criado pelo autoscaler, a race condition se repete. Verificar AGE do nó antes de confirmar sucesso.

## Estado Pós-Fix

Todos os pods Running em `ip-10-0-148-177.ec2.internal` (nó com CNI estável):
```
linkerd-destination-658ff6c6d5-wf457      4/4 Running
linkerd-identity-85c5b77595-5jwkn         2/2 Running
linkerd-proxy-injector-65645f76d5-kb62m   2/2 Running
tap-injector-67f956584b-qqp9w             2/2 Running
```

Endpoints DNS resolvendo:
- `linkerd-identity-headless.linkerd.svc.cluster.local:8080` -> 10.0.150.78
- `linkerd-dst-headless.linkerd.svc.cluster.local:8086` -> 10.0.154.188

Certificados válidos (sem expiração):
- Trust anchor: 2026-03-03 a 2027-03-03
- Identity issuer: 2026-03-03 a 2027-03-03

## Mitigação de Longo Prazo

O problema raiz é a ausência de `podAnnotations` no control plane para atrasar o agendamento até o CNI estar pronto. Considerar:

1. **Adicionar annotation `linkerd.io/inject: disabled`** nos deployments do control plane no namespace `linkerd` (o control plane não deve depender de si mesmo para inicializar)
2. **Ou usar `cniEnabled: false` com init containers iptables** ao invés do CNI plugin
3. **PodDisruptionBudget** para evitar que todos os pods do CP sejam evictados juntos durante scale events
4. **Anti-affinity rules** para distribuir os 3 pods do CP em nós diferentes

**Nota:** O `proxyInjector.namespaceSelector` já exclui o namespace `linkerd` do webhook de injeção automática, mas os deployments têm anotações diretas que forçam injeção — revisar se isso é necessário.
