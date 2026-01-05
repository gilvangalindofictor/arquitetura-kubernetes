# ADR-007: Service Mesh

## Status
Aceito

## Contexto
Service mesh necessário para isolamento de comunicação entre domínios, observabilidade de service-to-service e segurança (mTLS). Escolha entre Istio e Linkerd baseada em custo e simplicidade.

## Decisão
Adotamos **Linkerd** como service mesh padrão, por simplicidade, baixo overhead e custo operacional reduzido comparado ao Istio.

## Consequências
- **Positivo**: Simplicidade de operação, performance melhor, custo menor
- **Negativo**: Menos features avançadas que Istio oferece (ex.: advanced routing)
- **Riscos**: Limitações em cenários complexos
- **Mitigação**: Extensibilidade via WebAssembly se necessário

## Implementação
- **Injection**: Sidecar automática via annotations
- **mTLS**: Automático entre serviços
- **Observabilidade**: Métricas integradas com Prometheus
- **Policies**: Traffic splitting, retries, timeouts

## Comparação Istio vs Linkerd
| Aspecto | Istio | Linkerd |
|---------|-------|---------|
| Complexidade | Alta | Baixa |
| Overhead | Médio | Baixo |
| Features | Completo | Essencial |
| Custo Operacional | Alto | Baixo |
| Adoção | Curva íngreme | Rápida |

## Validação
- Performance benchmarks
- mTLS testing
- Observabilidade integration

## Referências
- [Linkerd Documentation](https://linkerd.io/)
- [Istio vs Linkerd](https://istio.io/latest/docs/ops/deployment/comparison/)

Data: 2025-12-30</content>
<parameter name="filePath">\\wsl.localhost\Ubuntu\home\gilvangalindo\projects\Arquitetura\Kubernetes\SAD\docs\adrs\adr-007-service-mesh.md