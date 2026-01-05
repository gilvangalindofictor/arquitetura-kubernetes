# Domínio Security - Plataforma Corporativa Kubernetes

> **Parte da**: Plataforma Corporativa Kubernetes (6 domínios)  
> **Governança**: SAD v1.2 - `/SAD/docs/sad.md`  
> **Status**: 🚧 Em Construção | 🛡️ Policies & Compliance

Este domínio fornece **políticas de segurança, runtime security e vulnerability scanning** transversal para toda a plataforma.

## 🎯 Missão

Fornecer **segurança em múltiplas camadas**:
- **Policy Enforcement**: OPA/Kyverno admission controllers
- **Runtime Security**: Falco (detecção de ameaças)
- **Vulnerability Scanning**: Trivy (images, IaC, misconfigurations)
- **Compliance**: Auditoria e relatórios

## 📦 Stack de Tecnologia

| Componente | Ferramenta | Propósito |
|------------|-----------|-----------|
| **Policy Engine** | Kyverno ou OPA Gatekeeper | Admission policies (deny by default) |
| **Runtime Security** | Falco | Detecção de anomalias, syscall monitoring |
| **Image Scanning** | Trivy Operator | Vulnerability scanning contínuo |
| **Compliance** | Starboard ou Falco Sidekick | Relatórios de compliance |
| **Network Policies** | Calico ou Cilium | Microsegmentação |

## 🏗️ Arquitetura

### Namespaces
- `security-kyverno` - Policy engine
- `security-falco` - Runtime security
- `security-trivy` - Vulnerability scanning

### Camadas de Segurança

```
┌─────────────────────────────────────────┐
│  Admission (Kyverno/OPA)                │ ← Policies
├─────────────────────────────────────────┤
│  Runtime (Falco)                        │ ← Threat detection
├─────────────────────────────────────────┤
│  Scanning (Trivy)                       │ ← CVE detection
├─────────────────────────────────────────┤
│  Network (Calico/Cilium)                │ ← Microsegmentation
└─────────────────────────────────────────┘
```

## 📚 Contratos com Outros Domínios

### Contratos Fornecidos (Provider) - TRANSVERSAL
| Serviço | API/Interface | SLA | Consumidores |
|---------|---------------|-----|--------------|
| Policies | Kyverno/OPA admission | 99.9% | **TODOS** |
| Scanning | Trivy integration | 99.9% | cicd-platform |
| Runtime Security | Falco alerts | 99.9% | observability |

### Contratos Consumidos
| Serviço | Provider | Interface |
|---------|----------|-----------|
| Alerting | observability | Prometheus Alertmanager |
| CI Integration | cicd-platform | GitLab CI scans |

## 🔐 Políticas Padrão

### Kyverno Policies (Admission)
- ✅ Require resource limits (CPU/memory)
- ✅ Disallow privileged containers
- ✅ Require non-root user
- ✅ Disallow hostPath/hostNetwork
- ✅ Require security context
- ✅ Enforce image pull policy (Always)

### Falco Rules (Runtime)
- ⚠️ Shell spawned in container
- ⚠️ Sensitive file access (/etc/shadow, /root/.ssh)
- ⚠️ Kubernetes API access anomalies
- ⚠️ Network connections to suspicious IPs

### Trivy Scans
- ❌ CRITICAL vulnerabilities (block deploy)
- ⚠️ HIGH vulnerabilities (alert)
- ℹ️ MEDIUM/LOW vulnerabilities (report)

## 📖 Referências
- [SAD v1.2](../../../SAD/docs/sad.md)
- [ADR-005: Segurança Sistêmica](../../../SAD/docs/adrs/adr-005-seguranca-sistemica.md)
- [ADR-014: Compliance Regulatória](../../../SAD/docs/adrs/adr-014-compliance-regulatoria.md)

---
**Status**: 🚧 Em Construção  
**ADR Pendente**: Escolha Kyverno vs OPA Gatekeeper
