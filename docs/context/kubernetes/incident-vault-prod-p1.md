# INC-001: vault-prod-0 Pending — EBS Volume Reattach
**Prioridade**: P1 CRÍTICO
**Detectado**: 2026-03-24 (aprox 09:00 UTC — Pending 13h)
**Status**: EM INVESTIGAÇÃO (aguarda acesso kubectl)
**Namespace**: prod-security-vault
**Componente**: vault-prod-0 (StatefulSet vault, pod index 0)

---

## Descrição

O pod `vault-prod-0` no namespace `prod-security-vault` entrou em estado `Pending` e permaneceu nesse estado por mais de 13 horas. O volume EBS `vol-065f3b18bebee9fc0` aguarda reattach ao nó.

---

## Impacto

| Serviço | Impacto | Severidade |
|---------|---------|------------|
| Vault HA | Quorum reduzido (possivelmente 2/3 réplicas) | P1 |
| ExternalSecrets prod | Renovação de secrets pode falhar | P1 |
| Harbor prod | Acesso a registry pode ser afetado via ESO | P1 |
| RabbitMQ prod | Secrets de configuração podem não renovar | P1 |
| Aplicações prod | Secrets com TTL curto podem expirar | P2 |

---

## Causa Raiz Hipotética

### Hipótese 1 (MAIS PROVÁVEL): FinOps down/up cycle
O ciclo Lambda FinOps stop/start substitui nós EC2. O nó original onde o volume estava attached foi terminado. O novo nó (mesma AZ) não conseguiu reattach automático porque o volume EBS ainda estava marcado como "in-use" pelo nó anterior (state machine AWS demorando).

### Hipótese 2: AZ Mismatch
O volume EBS foi criado na AZ `us-east-1a` mas após o ciclo FinOps, apenas nós em `us-east-1b` ou `1c` estão disponíveis para o StatefulSet.

### Hipótese 3: Node selector/affinity
O StatefulSet tem affinity rules que restringem o pod a um nó específico que foi removido.

---

## Diagnóstico Necessário

```bash
# 1. Estado atual do pod
kubectl -n prod-security-vault describe pod vault-prod-0

# 2. Estado do PVC
kubectl -n prod-security-vault get pvc

# 3. Estado do PV
kubectl get pv | grep vault

# 4. Estado do volume EBS na AWS
aws ec2 describe-volumes \
  --volume-ids vol-065f3b18bebee9fc0 \
  --profile k8s-platform-prod \
  --region us-east-1 \
  --query 'Volumes[0]'

# 5. Verificar se há attachments pendentes
aws ec2 describe-volume-status \
  --volume-ids vol-065f3b18bebee9fc0 \
  --profile k8s-platform-prod \
  --region us-east-1

# 6. Nós disponíveis e suas AZs
kubectl get nodes -o custom-columns=NAME:.metadata.name,AZ:.metadata.labels.topology\\.kubernetes\\.io/zone,INSTANCE:.metadata.labels.node\\.kubernetes\\.io/instance-type

# 7. Events do namespace
kubectl -n prod-security-vault get events --sort-by='.lastTimestamp' | tail -30
```

---

## Runbook de Remediação

### Cenário A: Volume stuck in detaching
Se o volume EBS está em estado `detaching` por mais de 2 horas:

```bash
# Forçar detach (APENAS se o nó original não existe mais)
aws ec2 detach-volume \
  --volume-id vol-065f3b18bebee9fc0 \
  --force \
  --profile k8s-platform-prod \
  --region us-east-1

# Aguardar volume ficar available
aws ec2 wait volume-available \
  --volume-ids vol-065f3b18bebee9fc0 \
  --profile k8s-platform-prod \
  --region us-east-1

# Deletar e recriar o pod para forçar novo scheduling
kubectl -n prod-security-vault delete pod vault-prod-0
```

### Cenário B: AZ Mismatch
Se o volume está em `us-east-1a` mas não há nós nessa AZ:

```bash
# Verificar AZ do volume
aws ec2 describe-volumes --volume-ids vol-065f3b18bebee9fc0 \
  --query 'Volumes[0].AvailabilityZone' --output text \
  --profile k8s-platform-prod --region us-east-1

# Verificar nós por AZ
kubectl get nodes -o custom-columns=NAME:.metadata.name,AZ:.metadata.labels.topology\\.kubernetes\\.io/zone

# Se AZ mismatch: escalar node group na AZ correta via Terraform
# TF dir: Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/environments/staging
```

### Cenário C: Volume Available (reattach automático pendente)
Se o volume já está `available` mas o pod não agendou:

```bash
# Forçar delete do pod para novo scheduling
kubectl -n prod-security-vault delete pod vault-prod-0

# Monitorar
kubectl -n prod-security-vault get pod vault-prod-0 -w
```

### Cenário D: PVC/PV inconsistente
```bash
# Verificar PVC bound
kubectl -n prod-security-vault get pvc

# Se PVC em Lost state: recriar PV manualmente apontando para o volume correto
# ATENÇÃO: operação de risco - escalar para engenheiro sênior
```

---

## Verificação Pós-Remediação

```bash
# 1. Pod Running
kubectl -n prod-security-vault get pod vault-prod-0

# 2. Vault unsealed
kubectl -n prod-security-vault exec vault-prod-0 -- vault status

# 3. Vault cluster HA
kubectl -n prod-security-vault exec vault-prod-0 -- vault status -format=json | jq '.ha_enabled, .is_performance_standby, .active_time'

# 4. ExternalSecrets sincronizados
kubectl get externalsecrets -A | grep -v SecretSynced

# 5. Vault pod logs
kubectl -n prod-security-vault logs vault-prod-0 --tail=50
```

---

## Escalonamento

Se remediação não for possível em < 30min:
- Verificar se vault-prod-1 e vault-prod-2 estão Running e um deles é active
- Se sim: impacto mitigado temporariamente (HA ativo)
- Avisar equipe de infraestrutura prod

---

## Histórico

| Data | Evento |
|------|--------|
| 2026-03-24 ~09:00 UTC | vault-prod-0 detectado em Pending (13h depois do último UP finops) |
| 2026-03-25T02:12 UTC | Investigação iniciada pelo Monitoring Orchestrator |
| 2026-03-25T02:25 UTC | BLOQUEADO — aguarda autenticação AWS SSO |
