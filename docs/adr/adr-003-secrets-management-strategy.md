# ADR-003: Estratégia de Secrets Management

**Data:** 2026-01-26
**Status:** Accepted
**Autor:** DevOps Team
**Contexto:** Marco 2 - Platform Services

---

## Contexto

Durante a implementação do Marco 2 (Platform Services), identificamos a necessidade de gerenciar credenciais sensíveis de forma segura e em conformidade com as melhores práticas de segurança. Especificamente:

1. **Senha do Grafana**: Inicialmente definida diretamente no arquivo `terraform.tfvars` como variável sensível
2. **Email Let's Encrypt**: Usado para notificações de certificados, requer proteção de dados pessoais
3. **Conformidade com o plano aprovado**: [aws-console-execution-plan.md](../plan/aws-console-execution-plan.md) §3.12 especifica o uso de AWS Secrets Manager

### Problemas Identificados

- ❌ Senhas hardcoded em `terraform.tfvars` (mesmo marcadas como `sensitive`)
- ❌ Histórico Git pode conter valores sensíveis
- ❌ Não há rotação automática de credenciais
- ❌ Ausência de auditoria de acesso a secrets
- ❌ Não conformidade com o plano arquitetural aprovado

---

## Decisão

**Migrar todas as credenciais sensíveis para AWS Secrets Manager**, com as seguintes diretrizes:

### 1. Secrets a Serem Migrados

| Secret | Nome no Secrets Manager | Uso |
|--------|------------------------|-----|
| `grafana_admin_password` | `k8s-platform-prod/grafana-admin-password` | Senha do admin do Grafana |
| Futuros: `alertmanager_slack_webhook` | `k8s-platform-prod/alertmanager-slack-webhook` | Webhook do Slack para alertas |
| Futuros: `gitlab_root_password` | `k8s-platform-prod/gitlab-root-password` | Senha root do GitLab |

### 2. Variáveis Sensíveis (Não Secrets)

Variáveis que contêm dados sensíveis mas não são credenciais permanecem como variáveis Terraform marcadas com `sensitive = true`:

- `letsencrypt_email`: Email pessoal/corporativo (LGPD/GDPR compliance)
- `cluster_name`: Informação de arquitetura (não é secret, mas sensível)

### 3. Implementação Terraform

```hcl
# secrets.tf
resource "aws_secretsmanager_secret" "grafana_admin_password" {
  name                    = "k8s-platform-prod/grafana-admin-password"
  description             = "Senha de administrador do Grafana"
  recovery_window_in_days = 7

  tags = {
    Environment = "production"
    Service     = "monitoring"
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "grafana_admin_password" {
  secret_id     = aws_secretsmanager_secret.grafana_admin_password.id
  secret_string = var.grafana_admin_password
}

# main.tf - Uso no módulo
module "kube_prometheus_stack" {
  grafana_admin_password = data.aws_secretsmanager_secret_version.grafana_admin_password.secret_string
}
```

### 4. Padrão de Nomenclatura

```
<cluster-name>/<service>-<secret-type>

Exemplos:
- k8s-platform-prod/grafana-admin-password
- k8s-platform-prod/alertmanager-slack-webhook
- k8s-platform-staging/grafana-admin-password
```

---

## Rationale

### Por que AWS Secrets Manager?

1. **Integração nativa com AWS**: IAM policies, CloudTrail audit logs, KMS encryption
2. **Rotação automática**: Suporte para rotação automática de credenciais (RDS, Redis, etc.)
3. **Versionamento**: Histórico completo de alterações com rollback
4. **Recovery Window**: Proteção contra deleção acidental (7-30 dias)
5. **Custo**: $0.40/secret/mês + $0.05/10k API calls (aceitável para ~5-10 secrets)
6. **Conformidade**: Atende SOC2, PCI-DSS, HIPAA, ISO 27001

### Alternativas Consideradas

| Solução | Prós | Contras | Decisão |
|---------|------|---------|---------|
| **Kubernetes Secrets** | Nativo K8s, sem custo | Sem rotação automática, criptografia básica | ❌ Rejeitado (uso apenas para configurações não-sensíveis) |
| **HashiCorp Vault** | Poderoso, flexível | Complexidade operacional, custo de manutenção | 🔄 Futuro (Marco 3+) |
| **AWS Secrets Manager** | Gerenciado, auditável, rotação automática | Custo por secret | ✅ **ESCOLHIDO** |
| **AWS Systems Manager Parameter Store** | Mais barato ($0/secret) | Sem rotação automática, menos features | ❌ Rejeitado |

---

## Consequências

### Positivas

✅ **Segurança**: Credenciais nunca mais em plaintext no Git
✅ **Auditoria**: CloudTrail registra todos os acessos aos secrets
✅ **Rotação**: Preparado para rotação automática (futuro)
✅ **Recovery**: Proteção contra deleção acidental (7 dias de recovery window)
✅ **Conformidade**: Alinhado com plano arquitetural aprovado (§3.12)
✅ **Separação de responsabilidades**: Ops gerencia Terraform, Security gerencia secrets via console/API

### Negativas

⚠️ **Custo adicional**: ~$0.40/secret/mês (~$5/mês para 10 secrets estimados)
⚠️ **Dependência AWS**: Lock-in com AWS Secrets Manager (migração para Vault requer refactor)
⚠️ **Complexidade inicial**: Requer atualização de todos os módulos Terraform existentes

### Neutras

🔄 **Migração progressiva**: Secrets podem ser migrados incrementalmente (não é breaking change)
🔄 **Desenvolvimento local**: Devs ainda podem usar variáveis locais via `terraform.tfvars` (não commitado)

---

## Plano de Implementação

### Fase 1 (Marco 2 - Atual)

- [x] Criar `secrets.tf` no ambiente marco2
- [x] Migrar `grafana_admin_password` para Secrets Manager
- [x] Marcar `letsencrypt_email` como `sensitive = true` (não migra para Secrets Manager)
- [x] Atualizar `main.tf` para usar `data.aws_secretsmanager_secret_version`
- [x] Documentar padrão de nomenclatura

### Fase 2 (Marco 3)

- [ ] Migrar credenciais do AlertManager (Slack webhook)
- [ ] Migrar credenciais do GitLab (root password, DB connection strings)
- [ ] Implementar rotação automática para RDS passwords

### Fase 3 (Futuro)

- [ ] Avaliar migração para HashiCorp Vault (se escala de secrets > 20)
- [ ] Implementar External Secrets Operator (ESO) para sincronização K8s ↔ Secrets Manager
- [ ] Criar política de rotação obrigatória a cada 90 dias

---

## Validação

### Checklist de Conformidade

- [x] Senha Grafana no AWS Secrets Manager
- [x] `letsencrypt_email` marcado como `sensitive = true`
- [x] Nenhuma credencial em `terraform.tfvars` (exceto para initial bootstrap)
- [x] CloudTrail habilitado para auditoria de acesso
- [x] Recovery window configurado (7 dias)
- [x] Tags apropriadas (Environment, Service, ManagedBy)

### Testes

```bash
# Validar que o secret foi criado
aws secretsmanager describe-secret \
  --secret-id k8s-platform-prod/grafana-admin-password

# Validar que o valor está correto (NÃO FAZER EM PRODUÇÃO - apenas staging)
aws secretsmanager get-secret-value \
  --secret-id k8s-platform-prod/grafana-admin-password \
  --query SecretString --output text

# Validar que Terraform consegue recuperar o secret
cd platform-provisioning/aws/kubernetes/terraform/envs/marco2
terraform plan | grep "grafana_admin_password"
# Deve mostrar: "(sensitive value)" e não o valor em plaintext
```

---

## Referências

- [AWS Secrets Manager Documentation](https://docs.aws.amazon.com/secretsmanager/)
- [Terraform aws_secretsmanager_secret Resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret)
- [Plano Arquitetural Aprovado](../plan/aws-console-execution-plan.md) §3.12
- [OWASP Secrets Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)

---

## Decisões Relacionadas

- [ADR-001: Setup e Governança](adr-001-setup-e-governanca.md)
- [ADR-002: Estrutura de Domínios](adr-002-estrutura-de-dominios.md)
- ADR-004: Terraform vs Helm para Platform Services (a ser criado)

---

**Última atualização:** 2026-01-26
**Aprovado por:** DevOps Team
**Próxima revisão:** Marco 3 (quando atingir 10+ secrets)
