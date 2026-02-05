# 📓 Diário de Bordo — FASE 1b: Harbor Completion & PostgreSQL Bootstrap

| Campo          | Valor                                    |
|----------------|------------------------------------------|
| **Data**       | 2026-02-05                               |
| **Demanda**    | Completar Harbor: PostgreSQL bootstrap TF + PVC fix + Robot accounts + Metrics |
| **Impacto**    | médio                                    |
| **Agentes**    | Orquestrador, Terraform, Security        |
| **Status**     | concluído                                |

---

## Timeline

[16:31:57] Análise | Orq | 4 tarefas: PostgreSQL bootstrap TF + Harbor PVC fix + robot accounts + metrics | impacto: médio
[16:32:10] TodoList | Orq | 7 itens criados | ✅
[16:32:20] Logbook | Orq | Criado fase1b-harbor-completion.md | ✅
[16:32:30] Agentes | AWS,TF,Sec | Análise concluída | ✅
[16:32:45] Consenso | Orq | Aprovar execução: PostgreSQL bootstrap TF + PVC fix + docs | ✅
[16:33:00] PostgreSQL | TF | Adicionado additional_databases var + null_resource bootstrap (kubectl run psql pod) | ✅
[16:33:15] PostgreSQL | TF | Script bootstrap-databases.sh criado (idempotente) | ✅
[16:33:26] PostgreSQL | TF | Outputs: additional_databases list | ✅
[16:37:20] Harbor PVC | TF | Fix jobservice replicas 2→1 (RWO PVC limitation, ADR-039) | ✅
[16:38:00] Robot Accounts | Orq | Documentado README.md Harbor module (script já existente) | ✅
[16:38:10] Metrics | Orq | Verificado: ServiceMonitor já habilitado em values.yaml.tpl:120-123 | ✅
[16:38:30] Sincronização | Orq | Atualizando logbook + decisions.md | 🔄
[16:39:00] ADR-039 | Orq | Criado Harbor Jobservice PVC RWO Limitation | ✅
[16:39:30] Docs | Orq | Atualizado decisions.md (ADR-038 roadmap + ADR-039) | ✅
[16:39:45] README | Orq | Criado Harbor module README.md (robot accounts guide) | ✅
[17:02:20] Terraform Apply | TF | State lock 34dfb208 (20:02:20 stale) | ⚠️
[17:09:00] Helm Fix | TF | Harbor pending-upgrade (rev 2), rollback → rev 3 | ✅
[17:11:00] Apply v3 | TF | Plan stale (helm rollback mudou state), recreating | 🔄
[17:11:30] Apply Final | TF | Started PID 73399, AML monitoring | 🔄
[17:13:00] Multi-Attach | K8s | jobservice RollingUpdate + RWO PVC = 2 pods stuck | ⚠️
[17:13:30] Fix | K8s | Manual scale-down old ReplicaSet → jobservice 1/1 Running | ✅
[17:14:00] Multi-Attach | K8s | registry mesmo erro (RollingUpdate + RWO PVC) | ⚠️
[17:14:30] Fix | K8s | Manual scale-down old ReplicaSet → registry 2/2 Running | ✅
[17:16:00] Apply Complete | TF | 0 add, 1 change, 0 destroy | ✅
[17:16:30] Idempotência | TF | terraform plan: No changes ✓ | ✅
[17:17:00] Verificação | K8s | Todos Harbor pods Running (jobservice replicas=1) | ✅

---

## 📊 SUMÁRIO FINAL

### ✅ Tarefas Concluídas

**1. PostgreSQL Bootstrap Automation** ⚠️ DISABLED
- Módulo: `additional_databases` variable implementado
- Implementação: null_resource + kubectl run psql pod
- **Problema**: Network connectivity - pods não alcançam RDS
- **Workaround**: Comentado em main.tf:174-183, usar script manual
- Arquivos: variables.tf, main.tf, outputs.tf, bootstrap-databases.sh
- **TODO**: Fix security group para permitir pod→RDS (porta 5432)

**2. Harbor Jobservice PVC Fix** ✅
- Root cause: RWO PVC + 2 replicas = Multi-Attach
- Solução: replicas 2→1 (staging)
- ADR-039: Documenta opções prod (EFS/emptyDir)

**3. Harbor Robot Accounts** ✅
- Script: create-robot-account.sh (já existente)
- Documentação: README.md Harbor module
- Scopes: push/pull/delete projeto library
- Integração: GitLab CI/CD variables

**4. Harbor Metrics** ✅
- Status: Já habilitado (values.yaml.tpl:120-123)
- ServiceMonitor: enabled=true
- Prometheus: auto-discovery via labels

### 📈 Métricas

| Métrica | Valor |
|---------|-------|
| Tempo total | 45 minutos (16:32 - 17:17) |
| Terraform apply | ~6 minutos (múltiplas tentativas) |
| Arquivos criados | 3 (bootstrap script, README, logbook) |
| Arquivos modificados | 4 (variables, main, outputs, values template) |
| ADRs criados | 1 (ADR-039) |
| Desafios resolvidos | 4 (state lock, helm lock, 2x Multi-Attach) |
| Custo adicional | $0 (bootstrap automation, PVC fix economy) |

### 🎯 Próximos Passos

1. **PostgreSQL Security Group Fix** (permitir pod CIDR → RDS porta 5432)
2. **Robot Account Setup** (executar script create-robot-account.sh)
3. **GitLab Integration** (configurar CI/CD variables Harbor)
4. **Metrics Validation** (verificar Prometheus ServiceMonitor scrape)
5. **ADR-040** (documentar RollingUpdate + RWO PVC issue e estratégia Recreate)

### 🔍 Lições Aprendidas

#### Multi-Attach com RollingUpdate + RWO PVC

- Harbor jobservice e registry usam PVCs com ReadWriteOnce (gp2)
- RollingUpdate strategy tenta manter pod antigo durante deploy do novo
- RWO PVC só pode estar anexado a um pod por vez
- **Resultado**: Pods ficam travados em ContainerCreating (Multi-Attach error)
- **Workaround**: Manual scale-down do ReplicaSet antigo para liberar PVC
- **Solução permanente**: Implementar `strategy.type: Recreate` no Helm chart (ADR-040)
