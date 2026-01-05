# ADR-013: Disaster Recovery

## Status
Aceito

## Contexto
Para garantir business continuity, precisamos de estratégias de backup, restore e failover cross-region. Especialmente crítico para data-services e compliance.

## Decisão
- **Ferramenta**: Velero para backup/restore
- **Estratégia**: Multi-region com failover automático
- **RTO/RPO**: <4 horas / <1 hora por domínio

## Consequências
- **Positivo**: Recuperação rápida, compliance atendida
- **Negativo**: Custo de storage adicional, complexidade
- **Riscos**: Dados inconsistentes em failover
- **Mitigação**: Testes regulares, point-in-time recovery

## Implementação
- **Backup**: Schedules diários/semanal via Velero
- **Storage**: S3-compatible multi-region
- **Failover**: ArgoCD sync para região secundária
- **Testes**: Restore drills mensais

## RTO/RPO por Domínio
| Domínio | RTO | RPO | Justificativa |
|---------|-----|-----|---------------|
| platform-core | 1h | 15min | Crítico para autenticação |
| cicd-platform | 2h | 30min | Impacto em deployments |
| observability | 4h | 1h | Dados históricos toleráveis |
| data-services | 1h | 15min | Dados críticos |
| secrets-management | 30min | 5min | Segurança crítica |
| security | 2h | 30min | Policies recuperáveis |

## Validação
- Restore testing
- Failover simulation
- Compliance audits

## Referências
- [Velero Documentation](https://velero.io/)
- [Kubernetes Disaster Recovery](https://kubernetes.io/docs/tasks/administer-cluster/)

Data: 2025-12-30</content>
<parameter name="filePath">\\wsl.localhost\Ubuntu\home\gilvangalindo\projects\Arquitetura\Kubernetes\SAD\docs\adrs\adr-013-disaster-recovery.md