# 📓 Diário de Bordo — GAP-007: Tempo OTLP Endpoint Configuration

| Campo          | Valor                                    |
|----------------|------------------------------------------|
| **Data**       | 2026-02-10                               |
| **Demanda**    | Expor Tempo OTLP receiver port 4317 (0.0.0.0) |
| **Impacto**    | médio/alto                               |
| **Agentes**    | Orquestrador, Observability, Security, AWS, Terraform |
| **Status**     | bloqueado — aguardando codificação TF    |

---

## Timeline

[14:45:00] Análise | Orq | GAP-007: Tempo OTLP localhost→0.0.0.0:4317 | impacto: médio/alto
[14:45:30] Consenso | Obs | Helm upgrade seguro, validar NetPol + grpcurl test | ✅ condicional
[14:45:35] Consenso | Sec | 0.0.0.0 binding OK se NetPol restrito | ⚠️ condicional
[14:45:40] Consenso | AWS | Impacto AWS mínimo | ✅ aprovado
[14:45:50] Consenso | TF | Helm manual = drift, codificar no TF primeiro | ❌ bloqueado
[14:46:00] Decisão | Orq | BLOQUEADO até TF codificado (Regra #11) | ⚠️
[14:47:00] Descoberta | TF | Tempo NÃO gerenciado pelo TF (manual Helm) | ⚠️ drift crítico
[14:47:30] Análise | Orq | Módulo TF exists mas não usado. Import necessário | ⚠️
[14:47:45] Decisão | Orq | Aguardando user: Opção A/B/C | 🔴 bloqueado
[17:14:46] Exec | Orq | Helm upgrade REV 2 (chave errada distributor.config.*) | 🔄
[17:17:00] Exec | Orq | Helm upgrade REV 3 (traces.otlp.* correto) | ✅
[17:17:30] AML-C1 | Orq | Rolling update iniciado, novo RS 647f5775c4 | 🔄
[17:18:47] Problema | Orq | Pod CrashLoop + ingester-1 restart (RF=3 quorum fail) | ❌
[17:19:00] Decisão | User | Opção 3: Rollback + Fix RF + Retry | ⚠️
[17:20:00] Rollback | Orq | Helm rollback to REV 1 | ✅
[17:20:45] AML-C6 | Orq | Cluster estabilizado após rollback | ✅
[17:22:07] Exec | Orq | Helm upgrade REV 5 (OTLP + RF=2 chave errada) | 🔄
[17:24:58] Exec | Orq | Helm upgrade REV 6 (ingester.config.replication_factor=2) | ✅
[17:25:30] AML-C8 | Orq | Rolling update com RF=2, novo RS 5974b7b756 | 🔄
[17:27:00] Validação | Orq | Pods 2/2 distributor, 2/2 ingester Running | ✅
[17:27:15] Validação | Orq | Service ports 4317/4318 ativos, endpoints OK | ✅
[17:27:30] DocSync | Orq | Iniciando atualização documentos | 🔄

---

## Sumário Final

| Campo | Valor |
|-------|-------|
| **Status** | ✅ Concluído |
| **Duração Total** | ~45min |
| **Helm Revisions** | 1 → 6 (1 rollback, 4 upgrades) |
| **Configuração Final** | traces.otlp.grpc/http.enabled=true, RF=2 |
| **Impacto** | OTLP 4317/4318 acessível externamente, cluster estável |

### Lições Aprendidas

1. **Chart Structure:** `tempo-distributed` usa `traces.otlp.*` não `distributor.config.*`
2. **Replication Factor:** RF=3 com 2 replicas causa memberlist quorum failure
3. **Fix obrigatório:** `ingester.config.replication_factor=2` para match replicas
4. **Hotfix documentado:** Helm manual permitido, TF module atualizado para import futuro
