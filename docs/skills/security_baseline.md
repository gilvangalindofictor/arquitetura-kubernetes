# Skill: Security Baseline

## Princípios Gerais

1. **Defense in Depth**: Múltiplas camadas de segurança
2. **Least Privilege**: Permissões mínimas necessárias
3. **Zero Trust**: Nunca confiar, sempre verificar
4. **Secrets Management**: Vault + ESO, nunca hardcoded

## Security Layers

### 1. Network Security

**VPC & Subnets**:
- Subnets públicas: apenas ALB/NLB
- Subnets privadas: workloads
- Subnets de dados: databases (futuro)

**Security Groups**:
- Least privilege (portas específicas, sources específicos)
- Naming: `{resource}-{purpose}-sg`
- Exemplo: `postgresql-eks-access-sg`

**Network Policies (K8s)**:
- Deny all por padrão
- Allow explícito por namespace
- Isolamento entre namespaces

### 2. Identity & Access

**IAM (AWS)**:
- Roles com policies específicas
- IRSA (IAM Roles for Service Accounts) para pods
- NUNCA hardcoded AWS keys

**RBAC (Kubernetes)**:
- ServiceAccounts por namespace
- Roles/ClusterRoles granulares
- NUNCA usar `cluster-admin` em produção

**Keycloak**:
- Centralizar autenticação
- OAuth 2.0 / OIDC
- SSO para plataforma

### 3. Secrets Management

**Vault (HashiCorp)**:
- Armazenamento central de secrets
- Dynamic secrets quando possível
- Rotation automática

**External Secrets Operator**:
- Sincronizar Vault → K8s Secrets
- Refresh automático
- NUNCA Kubernetes Secrets diretos (exceto transitório)

### 4. Runtime Security (Futuro)

**Falco**:
- Detecção de comportamento anômalo
- Alertas em tempo real

**Trivy**:
- Scan de vulnerabilidades em imagens
- Integração com Harbor

### 5. Policy Enforcement (Futuro)

**Kyverno**:
- Policies declarativas
- Enforce: labels obrigatórias, resource limits
- Mutate: adicionar tolerations, labels

### 6. Service Mesh (Futuro)

**Linkerd**:
- mTLS entre serviços
- Observabilidade de tráfego
- Circuit breakers

## Checklist de Segurança

Ver `docs/checklists/security_inline.md` para checklist por task.

Ver `docs/checklists/security_audit.md` para audit completo por sprint.

## OWASP Top 10 (Compliance)

### A01: Broken Access Control
-✅ RBAC configurado
- ✅ Security groups restritivos
- ⏸️ API Gateway com autenticação (futuro)

### A02: Cryptographic Failures
- ✅ TLS em trânsito (ALB, internal)
- ✅ Encryption at rest (EBS, RDS)
- ✅ Secrets via Vault

### A03: Injection
- ✅ Helm values sanitizados
- ✅ No SQL injection (apps gerenciam DBs)

### A04: Insecure Design
- ✅ Arquitetura revisada (ADRs)
- ✅ Threat modeling básico

### A05: Security Misconfiguration
- ✅ Default passwords alterados
- ✅ Security groups não "*"
- ⏸️ Security headers (futuro, API GW)

### A06: Vulnerable Components
- ⏸️ Dependency scanning (futuro, Trivy)
- ✅ Imagens de fontes confiáveis

### A07: Identification & Authentication Failures
- ✅ Keycloak centralizado
- ✅ Vault para secrets

### A08: Software and Data Integrity
- ✅ IaC versionado (Git)
- ✅ Terraform state protegido (S3 + encryption)

### A09: Security Logging & Monitoring
- ✅ CloudTrail habilitado
- ✅ K8s audit logs
- ⏸️ SIEM (futuro)

### A10: Server-Side Request Forgery (SSRF)
- ⏸️ Mitigação via Network Policies (futuro)

## Ferramentas de Security

```bash
# SAST (Static)
semgrep --config=auto .
checkov -d platform-provisioning/
tfsec platform-provisioning/

# Dependency Check
trivy config k8s/

# Container Scan
trivy image <image:tag>
```

## Regras Invioláveis

1. **NUNCA secret hardcoded no código**
2. **NUNCA dependência com CVE HIGH sem mitigação**
3. **NUNCA bypass de auth "temporário"**
4. **NUNCA log com PII sem mascaramento**

---

_Skill v1.0 - Baseline de segurança da plataforma_
