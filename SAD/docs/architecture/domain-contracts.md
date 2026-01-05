# Contratos entre Domínios - SAD

> **Localização**: `/SAD/docs/architecture/domain-contracts.md`
> **Propósito**: Definir contratos formais entre domínios para comunicação e dependências controladas
> **Fonte Suprema**: SAD congelado

---

## Princípios dos Contratos

### Sem Dependências Diretas
- Domínios operam de forma independente
- Comunicação via APIs padronizadas, métricas, eventos
- Contratos versionados e testáveis

### Versionamento
- **Semântico**: MAJOR.MINOR.PATCH
- **Compatibilidade**: Backward compatible dentro de MAJOR
- **Deprecation**: 6 meses notice para breaking changes

### SLAs Obrigatórios
- **Availability**: 99.9% uptime mínimo
- **Latency**: P95 <100ms para APIs críticas
- **Throughput**: Definido por contrato
- **Support**: 24/7 para domínios críticos

---

## Contratos por Domínio

### 1. platform-core (Provider)
**Responsabilidade**: Infraestrutura base para todos

#### Contratos Fornecidos
| Serviço | API/Interface | SLA | Consumidores |
|---------|---------------|-----|--------------|
| Authentication | Keycloak OIDC/OAuth2 | 99.95% | Todos |
| API Gateway | Kong REST API | 99.9% | Todos |
| Service Mesh | Linkerd mTLS | 99.9% | Todos |
| Certificates | cert-manager ACME | 99.9% | Todos |
| Ingress | NGINX HTTP/HTTPS | 99.9% | Todos |

#### Dependências Externas
- **Nenhuma**: Domínio fundacional

### 2. cicd-platform (Provider/Consumer)
**Responsabilidade**: CI/CD e governança

#### Contratos Fornecidos
| Serviço | API/Interface | SLA | Consumidores |
|---------|---------------|-----|--------------|
| Git Repository | GitLab REST API | 99.9% | Developers |
| CI Pipelines | GitLab CI YAML | 99.5% | Applications |
| Artifact Registry | Harbor REST API | 99.9% | Deployments |
| Backstage Catalog | Backstage API | 99.9% | Teams |

#### Contratos Consumidos
| Serviço | Provider | Interface | SLA Required |
|---------|----------|-----------|--------------|
| Secrets | secrets-management | External Secrets API | 99.9% |
| Authentication | platform-core | Keycloak | 99.95% |
| Monitoring | observability | Prometheus metrics | 99.9% |

### 3. observability (Provider)
**Responsabilidade**: Monitoramento unificado

#### Contratos Fornecidos
| Serviço | API/Interface | SLA | Consumidores |
|---------|---------------|-----|--------------|
| Metrics Collection | OpenTelemetry gRPC | 99.9% | Todos |
| Log Aggregation | Loki HTTP API | 99.9% | Todos |
| Trace Storage | Tempo gRPC | 99.9% | Todos |
| Dashboards | Grafana HTTP API | 99.5% | Teams |
| Alerting | Alertmanager API | 99.9% | On-call |

#### Contratos Consumidos
| Serviço | Provider | Interface | SLA Required |
|---------|----------|-----------|--------------|
| Service Mesh | platform-core | Linkerd metrics | 99.9% |

### 4. data-services (Provider)
**Responsabilidade**: DBaaS, Cache, MQ

#### Contratos Fornecidos
| Serviço | API/Interface | SLA | Consumidores |
|---------|---------------|-----|--------------|
| PostgreSQL | PostgreSQL protocol | 99.9% | Applications |
| Redis | Redis protocol | 99.9% | Applications |
| RabbitMQ | AMQP/STOMP | 99.9% | Applications |
| Backup/Restore | Velero API | 99.9% | Operations |

#### Contratos Consumidos
| Serviço | Provider | Interface | SLA Required |
|---------|----------|-----------|--------------|
| Monitoring | observability | Prometheus exporters | 99.9% |
| Authentication | platform-core | Keycloak | 99.95% |

### 5. secrets-management (Provider)
**Responsabilidade**: Cofre centralizado

#### Contratos Fornecidos
| Serviço | API/Interface | SLA | Consumidores |
|---------|---------------|-----|--------------|
| Secret Storage | Vault/K8s API | 99.95% | Todos |
| Secret Injection | External Secrets API | 99.9% | CI/CD |
| Rotation | Automated webhooks | 99.9% | Applications |
| Audit Logs | Structured events | 99.9% | Security |

#### Contratos Consumidos
| Serviço | Provider | Interface | SLA Required |
|---------|----------|-----------|--------------|
| Authentication | platform-core | Keycloak | 99.95% |
| Monitoring | observability | Prometheus metrics | 99.9% |

### 6. security (Provider)
**Responsabilidade**: Policies e compliance

#### Contratos Fornecidos
| Serviço | API/Interface | SLA | Consumidores |
|---------|---------------|-----|--------------|
| Policy Engine | OPA REST API | 99.9% | Todos |
| Vulnerability Scans | Trivy API | 99.9% | CI/CD |
| Runtime Security | Falco events | 99.9% | Observability |
| Compliance Reports | REST API | 99.9% | Governance |

#### Contratos Consumidos
| Serviço | Provider | Interface | SLA Required |
|---------|----------|-----------|--------------|
| Monitoring | observability | Prometheus metrics | 99.9% |
| Authentication | platform-core | Keycloak | 99.95% |

---

## Matriz de Dependências

```
platform-core ← cicd-platform ← secrets-management
              ← observability
              ← data-services
              ← security

cicd-platform ← applications (via Backstage)
observability ← all domains (metrics/logs/traces)
data-services ← applications
secrets-management ← cicd-platform, applications
security ← all domains (policies/scanning)
```

### Regras de Dependência
- **Máximo 2 níveis**: Evitar cadeias longas
- **Ciclicas proibidas**: Dependências unidirecionais
- **Testabilidade**: Contratos mockáveis para testing
- **Fallbacks**: Graceful degradation em falhas

---

## Versionamento e Compatibilidade

### Estratégia de Versionamento
- **API Versions**: v1, v2, etc. no path
- **Deprecation Policy**: 6 meses para removal
- **Breaking Changes**: Major version bump

### Testing de Contratos
- **Contract Tests**: Automatizados em CI/CD
- **Integration Tests**: Entre domínios em staging
- **Load Tests**: SLAs validados
- **Chaos Engineering**: Failure injection

---

## Monitoramento de Contratos

### Métricas Obrigatórias
- **Uptime**: Por serviço/contrato
- **Latency**: P50/P95/P99
- **Error Rates**: 4xx/5xx por endpoint
- **Throughput**: Requests per second

### Alerting
- **SLA Breach**: Imediato para critical
- **Degradation**: Warning para non-critical
- **Trend Analysis**: Weekly reports

---

## Processo de Mudança

1. **Proposta**: Novo contrato via ADR
2. **Impact Analysis**: Domínios afetados
3. **Implementation**: Backward compatible primeiro
4. **Testing**: Contract tests atualizados
5. **Deployment**: Rollout gradual
6. **Monitoring**: SLA tracking pós-deploy

---

**Mantenedor**: Architect Guardian
**Última Atualização**: 2025-12-30
**Status**: Parte do SAD congelado</content>
<parameter name="filePath">\\wsl.localhost\Ubuntu\home\gilvangalindo\projects\Arquitetura\Kubernetes\SAD\docs\architecture\domain-contracts.md