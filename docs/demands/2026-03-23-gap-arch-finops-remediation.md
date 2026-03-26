# GAP-ARCH FinOps & Architecture Remediation — 2026-03-23

**Data:** 2026-03-23
**Sessão:** Varredura FinOps & Segurança + Remediação TF
**Agentes:** 5 (FinOps+Arch, Cloud Debug, Security, Vault, Loki TF)
**Status:** Em andamento — P0/P1 remediados em TF; vault_root_token requer ação manual

## Sumário Executivo

20 GAPs identificados em varredura completa de boas práticas. 13 remediados nesta sessão via TF code changes. 7 pendentes para próxima sessão (requerem ACM certs, migração de IAM, ou decisão arquitetural).

**Ação bloqueante imediata:** vault_root_token expirado — executar procedimento de refresh antes do próximo terraform apply.

## GAPs por Status

### P0 — Críticos (remediados nesta sessão)

| GAP | Descrição | Status |
|-----|-----------|--------|
| GAP-ARCH-003 | NetworkPolicy staging→prod comentada — egress livre para data-services-prod | Remediado (TF) |
| GAP-ARCH-001 | Loki IRSA compartilhada staging/prod — role staging acessa S3 prod | Remediado (TF) |
| GAP-VAULT-TOKEN-001 | vault_root_token expirado — bloqueia TODO terraform plan | **Ação manual pendente** |

### P1 — Altos (remediados nesta sessão)

| GAP | Descrição | Status |
|-----|-----------|--------|
| GAP-VAULT-KMS-S3-001 | Colisão nomes KMS alias + S3 bucket (cluster_name sem env discriminador) | Remediado (TF) |
| GAP-ARCH-006 | Vault module default storage_class gp2 | Remediado → gp3 |
| GAP-ARCH-007 | Harbor staging em gp2 | Remediado → gp3 |
| GAP-PROM-ADM-001 | Prometheus admission webhook ErrImagePull | Remediado (ECR k8s/) |
| GAP-KYVERNO-GHCR-001 | Kyverno redireciona GHCR→ECR mas pull-through GHCR desabilitado | Remediado (sincronizado) |
| GAP-ARCH-014 | Loki S3 tag hardcoded Environment=production | Remediado → var.environment |

### P2 — Médios (remediados nesta sessão)

| GAP | Descrição | Status |
|-----|-----------|--------|
| GAP-ARCH-012 | node_group_common_tags CostCenter divergente (Engineering→development) | Remediado (TF) |
| GAP-ARCH-013 | Node groups em 2 subnets hardcoded | Remediado → var.private_subnet_ids |
| GAP-ARCH-015 | Keycloak prod sem backup de realm | Remediado (keycloak-backup.tf criado) |
| GAP-ARCH-017 | FinOps Automation system max_size=6 vs ASG max=4 | Remediado → 4 |
| GAP-LOKI-PROD-TF-001 | loki prod não gerenciado por TF | prod/loki.tf criado; import pendente |

### Pendentes — Próxima Sessão

| GAP | Descrição | Bloqueador |
|-----|-----------|------------|
| GAP-ARCH-002 | Vault prod IAM role sem prefixo env | Renomeação brownfield — risky; requer janela de manutenção |
| GAP-ARCH-004 | DynamoDB lock table compartilhada staging/prod | Decisão arquitetural |
| GAP-ARCH-005 | GitLab shared no state prod | **RESOLVIDO por decisão arquitetural (2026-03-24)** — GitLab CE = 1 instância shared, managed no state staging; remover module.gitlab_staging (DEC-2026-03-24-GITLAB). Ver ADR-046 Complemento 2026-03-24. |
| GAP-ARCH-008 | TLS em Keycloak prod | ACM cert pendente |
| GAP-ARCH-009 | TLS em GitLab | ACM cert pendente |
| GAP-ARCH-010 | TLS ESO→Vault | ACM cert pendente |
| GAP-ARCH-011 | ClusterSecretStore sem namespace isolation | Refatoração ESO |
| GAP-ARCH-016 | VPA sem ciclo de aplicação (R$ 8.712/ano pendente) | Ciclo VPA não implementado |
| GAP-ARCH-018 | VPN Site-to-Site comentada | Dependência de decisão de rede |
| GAP-ARCH-019 | vault_config localhost hardcoded | Requer vault_root_token válido |
| GAP-ARCH-020 | OIDC desabilitado no vault_config | Requer vault_root_token válido |

## Lições Aprendidas

- **Lição 26:** Módulos multi-ambiente no mesmo cluster DEVEM usar `var.environment` como discriminador em nomes de recursos AWS (KMS, S3, IAM, DynamoDB). Apenas `cluster_name` gera colisão.
- **Lição 27:** Kyverno MutatingPolicy de redirect e pull-through rules ECR são par inseparável — alterar um requer revisar o outro imediatamente.
- **Lição 28:** vault_root_token expirado = bloqueio total do terraform (sem workaround via -target). Refresh é pré-requisito de qualquer sessão TF.

## Próximos Passos Prioritários

1. **Refresh vault_root_token** (manual — recovery keys necessárias) → desbloqueia TODO o TF
2. `terraform plan + apply` para confirmar zero drift nos fixes P0 (GAP-ARCH-003, GAP-VAULT-KMS-S3-001)
3. `terraform import` do loki prod helm_release no state TF (prod/loki.tf já criado)
4. Resolver ACM certs para habilitar TLS em Keycloak prod (GAP-ARCH-008) e GitLab (GAP-ARCH-009)
5. GAP-ARCH-002 — janela de manutenção para renomear IAM role Vault prod
6. GAP-ARCH-016 — implementar ciclo VPA (R$ 8.712/ano de saving projetado)

## Artefatos Criados/Modificados Nesta Sessão

- `platform-provisioning/aws/kubernetes/terraform/environments/prod/keycloak-backup.tf` — novo
- `platform-provisioning/aws/kubernetes/terraform/environments/prod/loki.tf` — novo
- `platform-provisioning/aws/kubernetes/terraform/modules/vault/variables.tf` — storage_class default gp2→gp3
- `platform-provisioning/aws/kubernetes/terraform/environments/staging/node-groups.tf` — subnets var + CostCenter fix
- `platform-provisioning/aws/kubernetes/terraform/modules/finops-automation/variables.tf` — system max_size 6→4
- `platform-provisioning/aws/kubernetes/terraform/modules/loki/main.tf` — S3 tag fix var.environment

---

## NOVA VARREDURA — Mesa Técnica 4 Agentes (2026-03-23 Tarde)

**Agentes:** FinOps Specialist + AWS Architecture + Security & Compliance + Terraform Specialist
**Total novos GAPs:** 34 | **P0:** 2 | **P1:** 14 | **P2:** 14 | **P3:** 4

---

### ⚡ P0 NOVO — AÇÃO IMEDIATA

#### GAP-HARBOR-REDIS-001 (= GAP-ARCH-002 / GAP-SEC-NET-001)

Harbor Prod usa Redis de STAGING — falha toda noite às 20h BRT

- `prod/main.tf:596`: `addr: "redis.data-services.svc.cluster.local:6379"`
- Namespace `data-services` = Redis de **staging** (não prod)
- FinOps automation desliga staging às 20h → Harbor prod perde cache/sessões diariamente
- **Fix:** `redis.data-services-prod.svc.cluster.local:6379`
- **Status: PENDENTE — fix urgente necessário**

---

### P1 NOVOS — PRÓXIMA SPRINT

| GAP | Descrição | Arquivo |
| --- | --------- | ------- |
| GAP-SEC-ESO-001 | Módulos keycloak/argocd/sonarqube/backstage hardcodam `vault-backend` (CSS staging) — prod usa secrets do Vault staging | modules/keycloak, argocd, sonarqube, backstage |
| GAP-SEC-IAM-002 | `ClusterSecretStore vault-backend-prod` não definido em TF (criação manual) | modules/external-secrets |
| GAP-SEC-VAULT-002 | `vault-reader` policy wildcard `secret/data/*` — qualquer usuário Keycloak lê secrets prod | modules/vault-config/vault_policies/vault-reader.hcl |
| GAP-SEC-VAULT-003 | `eso-reader` sem boundary de ambiente em service paths (harbor/*, keycloak/*, etc.) | modules/vault-config/vault_policies/eso-reader.hcl |
| GAP-SEC-AUDIT-001 | K8s audit logs desabilitados — BCB 85/2021 compliance gap | modules/eks/main.tf:139 |
| GAP-ARCH-003 | NetworkPolicy egress staging cobre apenas `staging-system`/`staging-apps` (não todos os staging-* namespaces) | staging/main.tf |
| GAP-ARCH-005 | Velero instância única sem Schedule separado por env (prod sem cobertura explícita) | velero-helm.tf |
| GAP-ARCH-008 | Vault injector staging (cluster-scoped webhook) pode bloquear pods de prod se staging Vault cair | prod/main.tf:441 |
| GAP-ARCH-009 | Linkerd mTLS prod com `mtls_namespaces = []` — enforcement em branco | prod/linkerd-mtls.tf |
| GAP-TF-003 | IAM Loki prod gerenciada no state de staging (cross-state anti-pattern) | staging/loki.tf |
| GAP-TF-006 | Tokens ativos em `secrets.auto.tfvars` em texto plano no filesystem | secrets.auto.tfvars |
| GAP-TF-007 | `ignore_changes = all` em kube-prometheus-stack e gitlab (drift invisível) | modules/kube-prometheus-stack, modules/gitlab |
| GAP-TF-010 | `prod/outputs.tf` sem nenhum `sensitive = true` | environments/prod/outputs.tf |
| GAP-TF-012 | RabbitMQ operator trigger `"latest"` fixo — `null_resource` nunca re-executa | modules/rabbitmq/main.tf |
| GAP-TF-002 | 24/53 módulos sem `versions.tf` (upgrade provider silencioso) | múltiplos modules/ |

---

### P2/P3 NOVOS — BACKLOG

| GAP | Severidade | Descrição |
|-----|-----------|-----------|
| GAP-ARCH-007 | P2 | Sem ResourceQuotas/LimitRanges (staging pode saturar cluster e bloquear pods prod) |
| GAP-SEC-NET-002 | P2 | NetworkPolicy usa label `environment:prod` mutável (Kyverno deve proteger) |
| GAP-SEC-WAF-001 | P2 | IP fixo em WAF sem procedimento de rotação |
| GAP-SEC-TLS-001 | P2 | TLS desabilitado em Harbor/Vault/Keycloak prod (dependência Linkerd mTLS não enforced) |
| GAP-SEC-KYVERNO-001 | P2 | Sem policy enforce de imagens Harbor em prod (apenas redirect mutating) |
| GAP-SEC-GITLAB-001 | P2 | GitLab runners sem isolamento staging/prod |
| GAP-SEC-LINKERD-001 | P2 | Trust anchor Linkerd compartilhado (single PKI root para staging e prod) |
| GAP-TF-001 | P2 | Bucket S3 state compartilhado (isolamento lógico apenas) |
| GAP-TF-004 | P2 | Account ID hardcoded em `prod/loki.tf` (`891377105802`) |
| GAP-TF-005 | P2 | `finops_alert_email` sem validation em prod (alerts silenciados sem aviso) |
| GAP-TF-008 | P2 | Remote state marco1 sem fallback (plan falha se marco1 indisponível) |
| GAP-TF-009 | P2 | Módulos locais sem versionamento semântico |
| GAP-TF-011 | P2 | 14+ `null_resource` substituíveis por `terraform_data` (TF >= 1.4) |
| GAP-FINOPS-003 | P3 | Karpenter + Spot 70% pendente (R$ 10-18K/ano) |
| GAP-FINOPS-004 | P3 | Savings Plans não comprados (~R$ 8.640/ano — ação manual Console) |
| GAP-FINOPS-005 | P3 | RDS Staging db.t3.medium overprovisioned vs capacidade real (~R$ 900/ano) |
| GAP-FINOPS-006 | P3 | ECR Pull-Through Cache ausente em prod |
| GAP-FINOPS-012 | P3 | `cost_center` não passado explicitamente no módulo finops-automation |

---

### BOAS PRÁTICAS CONFIRMADAS ✅

- Tagging consistente: `common_tags` + `default_tags` provider em staging e prod
- Storage 100% gp3 (zero gp2 residual após sessão anterior)
- FinOps Automation completo (4 EventBridge rules, circuit breaker DynamoDB)
- S3 lifecycle policies (staging 7d, prod 30d) + ECR lifecycle (7d untagged)
- RDS diferenciado: staging single-AZ, prod Multi-AZ
- Replicação diferenciada: Redis/RabbitMQ staging=1, prod=3+HA
- ASG right-sized (system max=4, workloads max=9)
- VPC Gateway Endpoint S3 (zero NAT cost para S3)
- State backends separados com DynamoDB locking
- KMS keys scoped por ambiente (staging vs prod separados)
- ESO namespaces separados por ambiente
- WAF em staging e prod ALBs com rule groups separados
- DataClassification/LGPD tags corretas por ambiente
