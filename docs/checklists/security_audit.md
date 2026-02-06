# Security Audit Completo

> Executar ao FINAL de cada Sprint/Marco

## 1. OWASP Top 10 (2021)

- [ ] **A01: Broken Access Control**: Verificar autorização em todos os endpoints
- [ ] **A02: Cryptographic Failures**: Verificar encriptação de dados sensíveis
- [ ] **A03: Injection**: Verificar parametrização de queries, command injection
- [ ] **A04: Insecure Design**: Revisar design patterns de segurança
- [ ] **A05: Security Misconfiguration**: Verificar configs default, headers, CORS
- [ ] **A06: Vulnerable Components**: Scan de dependências (ver seção 4)
- [ ] **A07: Auth Failures**: Verificar mecanismos de autenticação
- [ ] **A08: Software Data Integrity**: Verificar pipelines CI/CD, supply chain
- [ ] **A09: Logging Failures**: Verificar logs de segurança e monitoring
- [ ] **A10: SSRF**: Verificar requisições server-side

## 2. SAST - Static Analysis Security Testing

### Ferramentas por Stack

```bash
# Python
bandit -r . -f json -o security-report.json
semgrep --config=auto .

# Node/TypeScript
npm audit
eslint --plugin security .
semgrep --config=auto .

# .NET
dotnet security-scan
semgrep --config=auto .

# Go
gosec ./...
semgrep --config=auto .

# Genérico (sempre executar)
semgrep --config=auto . --json -o semgrep-report.json
```

### Ações

- [ ] Executar ferramenta apropriada para a stack
- [ ] Analisar HIGH e CRITICAL findings
- [ ] Criar tasks para remediar ou justificar accept risk

## 3. DAST - Dynamic Analysis Security Testing

**Se aplicável** (para aplicações com endpoints HTTP):

```bash
# OWASP ZAP
docker run -t owasp/zap2docker-stable zap-baseline.py \
  -t https://staging.example.com \
  -r zap-report.html

# Ou nikto para scan rápido
nikto -h https://staging.example.com -output nikto-report.txt
```

- [ ] Executar DAST em ambiente de staging
- [ ] Analisar vulnerabilidades encontradas
- [ ] Remediar HIGH/CRITICAL antes de produção

## 4. Dependency Check

```bash
# Python
pip-audit

# Node
npm audit --audit-level=high
npm audit fix

# .NET
dotnet list package --vulnerable

# Go
go list -json -m all | nancy sleuth

# Terraform modules
checkov -d platform-provisioning/
```

- [ ] Executar scan de dependências
- [ ] Atualizar dependências com CVEs críticas
- [ ] Documentar accepts de vulnerabilidades se não puder atualizar (com mitigação)

## 5. Infrastructure Security (Terraform/K8s)

```bash
# Terraform
checkov -d platform-provisioning/ --output json --output-file checkov-report.json
tfsec platform-provisioning/

# Kubernetes manifests
kubesec scan k8s/apps/**/*.yaml
trivy config k8s/
```

- [ ] Executar scan de IaC
- [ ] Verificar configurações de rede (security groups, network policies)
- [ ] Verificar IAM/RBAC (least privilege)
- [ ] Verificar secrets management (não hardcoded)

## 6. Container Security (se aplicável)

```bash
# Scan de imagens
trivy image <image:tag>
```

- [ ] Scan de imagens Docker
- [ ] Sem vulnerabilidades HIGH/CRITICAL em imagens de produção
- [ ] Usar distroless ou imagens mínimas quando possível

## 7. Relatório Final

Gerar relatório em `docs/security/audit_sprint_N.md`:

```markdown
# Security Audit - Sprint N

**Data**: YYYY-MM-DD
**Escopo**: <descrição>

## Sumário Executivo
- Vulnerabilidades encontradas: X HIGH, Y MEDIUM, Z LOW
- Vulnerabilidades remediadas: X
- Accept risk documentados: Y

## Findings

### HIGH
1. [Tipo] Descrição - Status: Fixed/Accepted
   - Impacto: ...
   - Mitigação: ...

### MEDIUM
...

## Ações Recomendadas
- [ ] Task 1
- [ ] Task 2

## Ferramentas Utilizadas
- SAST: semgrep v...
- Dependency: npm audit
- IaC: checkov v...
```

## Critério de Aprovação

Sprint/Marco só pode ser considerado COMPLETO se:
- ✅ Todas vulnerabilidades HIGH remediadas OU com accept risk documentado
- ✅ Relatório de audit gerado e revisado
- ✅ Tasks de remediação criadas para MEDIUM (se necessário)
