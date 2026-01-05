# ADR-008: Escalabilidade e Performance

## Status
Aceito

## Contexto
Plataforma deve escalar horizontal e verticalmente para otimizar custos e performance. Testes de carga obrigatórios para validar.

## Decisão
- **Horizontal Scaling**: HPA obrigatório para pods
- **Vertical Scaling**: VPA para otimização de recursos
- **Testes**: K6/Locust para carga, obrigatórios por domínio

## Consequências
- **Positivo**: Custo-otimizado, alta disponibilidade
- **Negativo**: Complexidade de configuração
- **Riscos**: Over-provisioning ou under-provisioning
- **Mitigação**: Monitoring contínuo, ajustes automáticos

## Implementação
- **HPA**: CPU/memory/utilization-based
- **VPA**: Recomendações automáticas
- **Resource Limits**: Obrigatórios em todos os deployments
- **Testes de Carga**: Cenários realistas, thresholds definidos
- **Storage Classes**: Otimizadas por workload (SSD para databases, HDD para backups)

## Storage Classes por Domínio
| Domínio | Storage Class | Características | Justificativa |
|---------|---------------|-----------------|---------------|
| data-services | ssd-premium | IOPS alto, baixa latência | Databases PostgreSQL/Redis |
| data-services | backup-hdd | Custo baixo, alta durabilidade | Velero backups |
| observability | ssd-standard | Balanceado | Loki/Tempo storage |
| cicd-platform | ssd-fast | Alta performance | Artifact storage |
| platform-core | standard | Geral | Configs, secrets |
| security | encrypted-ssd | Encrypted at-rest | Compliance data |

## Thresholds por Domínio
| Domínio | CPU Target | Memory Target | Test Load |
|---------|------------|---------------|-----------|
| platform-core | 70% | 80% | 1000 req/s |
| cicd-platform | 60% | 70% | 500 builds/h |
| observability | 80% | 85% | 10k metrics/s |
| data-services | 75% | 80% | 1000 connections |
| secrets-management | 50% | 60% | 1000 secrets/h |
| security | 70% | 75% | 1000 policies/s |

## Validação
- Load testing results
- Resource utilization monitoring
- Cost optimization metrics

## Referências
- [Kubernetes HPA](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [K6 Load Testing](https://k6.io/)

Data: 2025-12-30</content>
<parameter name="filePath">\\wsl.localhost\Ubuntu\home\gilvangalindo\projects\Arquitetura\Kubernetes\SAD\docs\adrs\adr-008-escalabilidade-performance.md