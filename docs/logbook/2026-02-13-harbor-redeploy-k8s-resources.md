# Harbor Redeploy - K8s Resources Missing

| Campo       | Valor                                                  |
| ----------- | ------------------------------------------------------ |
| **Data**    | 2026-02-13                                             |
| **Demanda** | Harbor inacessivel via http://harbor.staging.internal/ |
| **Impacto** | Alto - Container Registry indisponivel                 |
| **Agentes** | Claude (executor-terraform)                            |
| **Status**  | Concluido                                              |
| **Duracao** | ~25 minutos                                            |

---

## Timeline

```
[20:10] Diagnostico | Verificacao de recursos Harbor no cluster
[20:11] Diagnostico | kubectl get svc/pods/ingress -A | grep harbor → VAZIO
[20:12] Diagnostico | terraform state list | grep harbor → apenas AWS (IAM, S3), sem K8s
[20:14] STOP-AND-FIX | Redis module: depends_on referencia quebrada redis_failover
[20:15] Fix | network-policies.tf + prometheus-rules.tf: redis_failover → redis
[20:18] Plan 1 | terraform plan -target=module.harbor_staging → 18 add, 11 change
[20:20] Apply 1 | FALHA: PostgreSQL RDS i/o timeout (local sem acesso VPC privada)
[20:22] Apply 1 | FALHA: Redis operator timeout (pod Pending, CPU insufficient)
[20:25] Workaround | kubectl rollout undo redis-operator
[20:26] Workaround | Comentar depends_on no harbor module (staging main.tf)
[20:28] Plan 2 | terraform plan -target=module.harbor_staging → 5 add, 0 change
[20:30] Apply 2 | SUCESSO: 5 added, 0 changed, 0 destroyed
[20:31] Restaurar | depends_on restaurado no staging main.tf
[20:32] Validacao | 7 pods Running, Ingress ativo no ALB platform-staging
```

---

## Problemas Identificados e Solucoes

### 1. Harbor K8s Resources Ausentes do State

**Sintoma:**
Harbor listado como operacional nos docs de contexto, mas zero recursos no cluster (sem namespace, pods, services, ingress).

**Causa Raiz:**
O Terraform state continha apenas recursos AWS do Harbor (IAM role, policy, S3 bucket) mas nenhum recurso Kubernetes (namespace, SA, secret, helm_release, configmap). Os recursos K8s foram removidos/destruidos em algum momento sem que os docs fossem atualizados.

**Solucao:**
Recrear os 5 recursos K8s via `terraform apply -target=module.harbor_staging`:
- `kubernetes_namespace.harbor` (harbor-system)
- `kubernetes_service_account.harbor`
- `kubernetes_secret.harbor_admin_password`
- `kubernetes_config_map.harbor_setup`
- `helm_release.harbor` (chart harbor v1.14.0, image v2.10.0)

**Arquivos:**
- `environments/staging/main.tf` (depends_on temporariamente removido e restaurado)

### 2. Redis Module - Broken Reference to redis_failover

**Sintoma:**
`terraform plan` falhava com "Reference to undeclared resource kubectl_manifest.redis_failover" em 7 resources.

**Causa Raiz:**
Migracao Redis SpotaHome → OT-Container-Kit renomeou o CR de `kubectl_manifest.redis_failover` para `kubectl_manifest.redis`, mas `network-policies.tf` e `prometheus-rules.tf` nao foram atualizados.

**Solucao:**
Atualizar `depends_on = [kubectl_manifest.redis_failover]` → `depends_on = [kubectl_manifest.redis]` nos 2 arquivos.

**Arquivos:**
- `modules/redis/network-policies.tf` (6 resources)
- `modules/redis/prometheus-rules.tf` (1 resource)

### 3. PostgreSQL Provider Timeout

**Sintoma:**
`terraform apply` falha com `dial tcp 10.0.129.202:5432: i/o timeout` para postgresql_role resources.

**Causa Raiz:**
TF executado de maquina local (WSL) sem acesso direto ao RDS em subnet privada. O `-target=module.harbor_staging` incluia dependencias do `module.postgresql_staging` via `depends_on`.

**Solucao:**
Remover temporariamente o `depends_on` do harbor module para isolar o plan apenas nos recursos Harbor. Restaurar apos apply.

### 4. Redis Operator Pod Pending

**Sintoma:**
Novo pod redis-operator Pending: "0/7 nodes are available: 3 Insufficient cpu"

**Causa Raiz:**
CPU requests excediam capacidade disponivel nos nodes. O `helm_release.redis_operator` forcava um rolling update a cada apply.

**Solucao:**
`kubectl rollout undo deployment redis-operator -n redis-operator` para manter o pod original Running.

---

## Licoes Aprendidas

### Terraform

| #   | Licao                                                                                                             | Impacto |
| --- | ----------------------------------------------------------------------------------------------------------------- | ------- |
| 1   | `depends_on` em modulos puxa TODAS as mudancas pendentes dos modulos dependentes no plan, mesmo com `-target`     | Alto    |
| 2   | Apos migracao de operadores (SpotaHome → OT-Kit), verificar TODOS os arquivos que referenciam recursos renomeados | Medio   |
| 3   | Manter state e cluster sincronizados - docs mostravam "Operacional" mas recursos K8s nao existiam                 | Alto    |

### Operacional

| #   | Licao                                                                                       | Impacto |
| --- | ------------------------------------------------------------------------------------------- | ------- |
| 1   | Validar acesso a backends (RDS, Redis) antes de rodar `terraform apply` de maquina local    | Medio   |
| 2   | Cluster com capacity constraints: nodes com CPU requests no limite impactam rolling updates | Medio   |

---

## Metricas

| Metrica             | Valor                                             |
| ------------------- | ------------------------------------------------- |
| Tempo total         | ~25 minutos                                       |
| Tentativas de apply | 2 (1 falha, 1 sucesso)                            |
| Recursos criados    | 5 (K8s)                                           |
| Pods deployados     | 7                                                 |
| Downtime Harbor     | indeterminado (sem dados de quando foi destruido) |

---

## Validacao Final

```
$ kubectl get pods -n harbor-system
NAME                                 READY   STATUS    RESTARTS
harbor-core-5bf56ffccc-q2gxt         1/1     Running   0
harbor-core-5bf56ffccc-v8fgg         1/1     Running   0
harbor-exporter-79b57c45dc-r9hg6     1/1     Running   0
harbor-jobservice-6cf94c6fd6-8wl2q   1/1     Running   1
harbor-portal-5bbddd48df-44mf9       1/1     Running   0
harbor-portal-5bbddd48df-5vnq9       1/1     Running   0
harbor-registry-664b8758b4-79nhq     2/2     Running   0

$ kubectl get ingress -n harbor-system
NAME             CLASS   HOSTS                     ADDRESS                                                                PORTS
harbor-ingress   alb     harbor.staging.internal   k8s-platformstaging-00e0ecf3b4-279144409.us-east-1.elb.amazonaws.com   80
```

---

## Referencias

- ADR existentes sobre Harbor: logbooks 2026-02-04 e 2026-02-05
- Modulo Terraform: `modules/harbor/` (main.tf, values.yaml.tpl, variables.tf)
- Redis migration: `docs/logbook/2026-02-13-redis-migration-spotahome-to-otkit.md`
- ALB group: `platform-staging` (compartilhado com Keycloak, ArgoCD, Vault, SonarQube)
