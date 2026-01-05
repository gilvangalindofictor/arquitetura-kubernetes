# ADR-001: Estrutura Inicial do Domínio Security

**Status**: ✅ Aceito  
**Data**: 2026-01-05  

---

## Contexto

O domínio **security** fornece políticas de segurança, runtime security e vulnerability scanning transversal.

## Decisão

### Stack (Decisão Pendente ADR-002)
- **Policy Engine**: Kyverno ou OPA Gatekeeper
- **Runtime Security**: Falco
- **Image Scanning**: Trivy Operator
- **Network Policies**: Calico ou Cilium

### Camadas
1. Admission policies (deny by default)
2. Runtime threat detection
3. Vulnerability scanning contínuo
4. Network microsegmentation

## Referências
- [SAD v1.2](../../../../SAD/docs/sad.md)
- [ADR-005: Segurança Sistêmica](../../../../SAD/docs/adrs/adr-005-seguranca-sistemica.md)

---
**Versão**: 1.0