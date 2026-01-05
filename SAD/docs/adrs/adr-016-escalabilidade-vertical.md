# ADR-016: Escalabilidade Vertical

## Status
Aceito

## Contexto
Otimização de recursos via vertical scaling necessária para reduzir custos e melhorar eficiência, complementando horizontal scaling.

## Decisão
Adotamos Vertical Pod Autoscaler (VPA) para recomendações automáticas de CPU/memory, com limits obrigatórios em todos os deployments.

## Consequências
- **Positivo**: Custo reduzido, resource efficiency
- **Negativo**: Possíveis restarts durante scaling
- **Riscos**: Application instability
- **Mitigação**: Graceful shutdown, testing rigoroso

## Implementação
- **VPA**: Recomendações automáticas
- **Resource Limits**: CPU/memory requests/limits obrigatórios
- **Monitoring**: Resource utilization tracking
- **Policies**: Admission controllers para enforcement

## Estratégia por Tipo de Workload
| Workload Type | CPU Strategy | Memory Strategy |
|---------------|--------------|-----------------|
| Web Services | Burstable | Guaranteed |
| Batch Jobs | Best-effort | Burstable |
| Databases | Guaranteed | Guaranteed |
| Caches | Burstable | Guaranteed |

## Validação
- Resource optimization metrics
- Application stability testing
- Cost savings measurement

## Referências
- [Vertical Pod Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)
- [Resource Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)

Data: 2025-12-30</content>
<parameter name="filePath">\\wsl.localhost\Ubuntu\home\gilvangalindo\projects\Arquitetura\Kubernetes\SAD\docs\adrs\adr-016-escalabilidade-vertical.md