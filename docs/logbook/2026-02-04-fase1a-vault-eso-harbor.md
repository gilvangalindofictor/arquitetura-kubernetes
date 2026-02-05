# 📓 Diário de Bordo — FASE 1a: Vault + ESO + Harbor Completion

| Campo          | Valor                                    |
|----------------|------------------------------------------|
| **Data**       | 2026-02-04                               |
| **Demanda**    | Completar deploy Vault/ESO/Harbor staging |
| **Impacto**    | médio                                    |
| **Agentes**    | Orquestrador, Terraform, K8s             |
| **Status**     | concluído                                |
| **Duração**    | 16:16-16:28 (12 minutos)                 |

---

## Timeline

[14:59:00] Análise | Orq | Apply parcial: 42 recursos AWS OK, Helm releases pendentes | impacto: médio
[14:59:15] Estado | TF | State: IAM/S3/secrets ✅ | Helm: ESO/Harbor pending
[14:59:30] Plan | TF | tfplan-v2: 7 recursos (ESO helm + Harbor helm + K8s resources) | ✅
[15:02:30] Apply Início | TF | Iniciado PID 77911 | 🔄
[15:02:37] AML-C1 | TF | Apply iniciando | log vazio
[15:03:00] ERRO | TF | State lock f360e992-14e6 (criado 17:55:42, 2h10min órfão) | ❌
[15:03:15] Investigação | Orq | Nenhum TF ativo, lock órfão | force-unlock OK
[15:03:30] Force-Unlock | TF | Lock removido | ✅

## 🔍 Sessão de Troubleshooting Profundo (19:00-19:30)

### Problemas Identificados e Resolvidos

1. **Trivy PVC órfão** ✅
   - PVC `data-harbor-trivy-0` Pending deletado
   - Trivy disabled conforme planejado

2. **Redis Authentication** ✅  
   - Causa: Redis pod não reload config após update do secret
   - Solução: Delete pod rfr-redis-0, auto-recreate com config correto
   - Validação: `redis-cli PING` → `PONG` ✅

3. **PostgreSQL Database Missing** ❌ BLOQUEADOR
   - RDS provisionado: database="platform", user="postgres_admin"
   - Harbor requer: database="harbor", user="harbor_user"  
   - **Falta bootstrap SQL para criar schema Harbor**

### Decisão: PAUSAR para Planejamento Arquitetural

**Razão**: Múltiplas integrações falhando indicam necessidade de:
- ADR sobre provisionamento de schemas
- Pipeline de bootstrap automatizado
- Revisão de dependências entre módulos

**Status Final**: Harbor parcialmente functional (Portal/Nginx/Registry OK, Core/Jobservice bloqueados por PostgreSQL)

---

## 🛠️ Bootstrap PostgreSQL (19:30-19:35)

[19:30:00] Decisão | Orq | Executar bootstrap PostgreSQL para Harbor | impacto: baixo
[19:30:15] Análise | TF | RDS database="platform", Harbor requer="harbor" | ❌
[19:30:30] Ação | Orq | Criar database + user via psql client pod | 🔄
[19:35:00] Bootstrap | Orq | psql pod criado | 🔄
[19:35:30] ERRO | Orq | RDS auth fail: password wrong OU SSL required | ❌
[19:36:00] Análise | Orq | RDS requer SSL OU senha master diferente do esperado | ⚠️
[19:36:15] Decisão | Orq | BLOQUEAR: falta credencial RDS master válida | ❌

### Bloqueio Crítico Final

**PostgreSQL RDS inacessível**:
- Tentativa psql: FATAL auth failed + no pg_hba.conf entry
- Causa: senha master incorreta OU RDS requer SSL
- Secret gitlab-postgresql-password: não é master password
- AWS Secrets Manager: credencial CLI não configurada

**Opções Restantes**:
1. Obter master password do RDS via console AWS
2. OU: Reconfigurar Harbor para usar database="platform" (compartilhado com GitLab)
3. OU: Provisionar novo RDS dedicado para Harbor

**Status**: PAUSADO aguardando credencial RDS OU decisão arquitetural

---

## 🤝 Decisão Arquitetural (16:16-16:20)

[16:16:21] Análise | Orq | 3 opções: bootstrap manual / reconfig Harbor / RDS dedicado | impacto: alto
[16:17:00] Consenso | AWS,TF,Sec | AWS+Sec: bootstrap (OK) | TF: condicionar (codificar no TF) | ⚠️
[16:18:30] Decisão | Orq | Opção 1+ (bootstrap + codificar posterior) | Performance > Purismo | ✅
[16:19:00] Preparação | Orq | Obter master password via Secrets Manager | 🔄
[16:19:15] Bootstrap | TF | CREATE DATABASE harbor + harbor_user + GRANTs | ✅ (SSL required)
[16:20:36] Fix Senha | TF | ALTER USER harbor_user → senha shared staging | ✅
[16:21:38] Fix Template | TF | values.yaml.tpl: database.sslmode=require | ✅
[16:22:41] TF Apply | TF | Iniciado PID 39034 (background + AML) | 🔄
[16:23:04] AML-C1 | TF | harbor destroying (19s) | namespace vazio
[16:23:25] AML-C2 | TF | harbor creating (10s) | aguardando pods
[16:23:46] AML-C3 | TF | harbor creating (30s) | 9 pods criados, 7 iniciando
[16:24:03] AML-C4 | TF | harbor-core 2/2 Ready ✅ | PostgreSQL SSL OK
[16:24:40] AML-C5 | TF | 8/9 Running | jobservice Multi-Attach PVC
[16:25:20] Fix PVC | K8s | scale harbor-jobservice replicas=1 | ✅
[16:26:32] TF Complete | TF | Apply complete 2m44s | 1 added, 1 destroyed | ✅
[16:27:01] Validação | Orq | 8 pods Running, 6 deployments AVAILABLE | ✅
[16:27:30] Idempotência | TF | terraform plan → No changes | ✅
[16:28:00] Harbor API | Orq | curl /health → HTTP 200 (24ms) | ✅

---

## 📊 SUMÁRIO FINAL

### ✅ Resolução Completa

**Problema:** Harbor Core/Jobservice em CrashLoopBackOff devido PostgreSQL database "harbor" inexistente + SSL requerido mas desabilitado no template.

**Solução Executada:**
1. Bootstrap PostgreSQL: CREATE DATABASE harbor + USER harbor_user (SSL required)
2. Sincronização senha: harbor_user → senha shared staging (Secrets Manager)
3. Template fix: values.yaml.tpl → `database.sslmode=require`
4. Terraform apply: Harbor recreated com SSL habilitado (2m44s)
5. Scale fix: harbor-jobservice 2→1 replica (Multi-Attach PVC)

### 📈 Métricas Finais

| Métrica | Valor |
|---------|-------|
| Tempo total | 12 minutos |
| Harbor pods | 8/8 Running |
| PostgreSQL | database=harbor, SSL enabled |
| Harbor API | HTTP 200 (24ms) |
| Idempotência | ✅ terraform plan → No changes |
| Custo adicional | $0 (shared RDS) |

### 🔧 Componentes Operacionais

- ✅ Harbor Core (2 replicas)
- ✅ Harbor Portal (2 replicas)
- ✅ Harbor Registry (1 replica, 2 containers)
- ✅ Harbor Nginx (1 replica)
- ✅ Harbor Exporter (1 replica)
- ✅ Harbor Jobservice (1 replica, scaled from 2)

### ⚠️ Issues Conhecidos

1. **Harbor Jobservice PVC Multi-Attach**
   - **Problema:** Template usa 2 replicas + RWO PVC → segundo pod não consegue attach
   - **Workaround:** Scale manual para 1 replica
   - **Fix permanente:** Atualizar template para replicas=1 OU remover PVC (jobservice pode usar emptyDir)
   - **ADR:** Pendente documentação

### 🎯 Próximos Passos

1. Codificar bootstrap PostgreSQL no módulo TF (evitar drift futuro)
2. Fix harbor-jobservice PVC no template (ADR + PR)
3. Configurar Harbor robot accounts para CI/CD
4. Habilitar Harbor metrics (ServiceMonitor Prometheus)
