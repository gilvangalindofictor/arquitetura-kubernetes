# FinOps Automation Scripts

Suite completa de scripts para auditoria e cleanup automático de recursos AWS órfãos.

## 📋 Scripts Disponíveis

### Cleanup Scripts (podem deletar recursos)

| Script | Recursos Verificados | Savings Estimados | Dry-run Default |
|--------|---------------------|-------------------|-----------------|
| **cleanup-orphan-resources.sh** | EBS volumes, Snapshots, Load Balancers | R$ 0-2.000/ano | ✅ Yes |
| **cleanup-elastic-ips.sh** | Elastic IPs não associados | R$ 0-500/ano | ✅ Yes |
| **cleanup-nat-gateways.sh** | NAT Gateways órfãos | R$ 0/ano (audit) | ✅ Yes |
| **cleanup-cloudwatch-logs.sh** | Log Groups sem retention, grandes | R$ 0-1.000/ano | ✅ Yes |
| **cleanup-ecr-images.sh** | Imagens ECR não taggeadas, antigas | R$ 0-300/ano | ✅ Yes |
| **cleanup-all.sh** | **TODOS os recursos acima** | **CONSOLIDADO** | ✅ Yes |

### Audit Scripts (apenas relatórios)

| Script | Recursos Verificados | Ação |
|--------|---------------------|------|
| **audit-security-groups.sh** | Security Groups não utilizados, permissivos | Manual review |

### Reporting Scripts

| Script | Descrição | Custo API |
|--------|-----------|-----------|
| **weekly-cost-report.sh** | Relatório de custos AWS (7-30 dias) | $0.01/request |
| **apply-tags.sh** | Aplicar tags FinOps em recursos | FREE |

### VPA Optimization Scripts

| Script | Descrição | Frequência | Exit Codes |
|--------|-----------|-----------|-----------|
| **vpa-phase0-validation.sh** | Valida VPA FASE 0 baseline convergence e calcula savings | Manual / CronJob (2026-02-27) | 0=target ✅, 1=partial ⚠️, 2=error ❌ |

---

## 🚀 Quick Start

### 1. Scan Completo (Dry-run, Seguro)
```bash
# Executar auditoria completa SEM modificar nada
DRY_RUN=true bash scripts/finops/cleanup-all.sh
```

**Output**: Relatórios JSON em `reports/aws-costs/` + estimativa de savings.

### 2. Executar Cleanup Real (⚠️ CUIDADO)
```bash
# Após revisar relatórios, executar cleanup REAL
DRY_RUN=false bash scripts/finops/cleanup-all.sh
```

**IMPORTANTE**: 
- ⚠️ Elastic IPs: Requer confirmação manual (IPs são liberados permanentemente)
- ✅ Outros recursos: Deletados automaticamente após confirmação

---

## 📊 Uso Individual

### Cleanup Orphan Resources (Original)
```bash
# Scan EBS volumes, snapshots, ALBs
DRY_RUN=true bash scripts/finops/cleanup-orphan-resources.sh

# Execute cleanup
DRY_RUN=false bash scripts/finops/cleanup-orphan-resources.sh
```

### Elastic IPs
```bash
# Scan unattached Elastic IPs
DRY_RUN=true bash scripts/finops/cleanup-elastic-ips.sh

# Release (requires manual confirmation)
DRY_RUN=false bash scripts/finops/cleanup-elastic-ips.sh
```

### CloudWatch Logs
```bash
# Scan log groups sem retention, grandes, vazios
DRY_RUN=true bash scripts/finops/cleanup-cloudwatch-logs.sh

# Set 30d retention + delete empty
DRY_RUN=false bash scripts/finops/cleanup-cloudwatch-logs.sh
```

### ECR Images
```bash
# Scan untagged images, old images
DRY_RUN=true bash scripts/finops/cleanup-ecr-images.sh

# Delete untagged images
DRY_RUN=false bash scripts/finops/cleanup-ecr-images.sh
```

### Security Groups Audit
```bash
# Audit security groups (no deletion, manual review)
bash scripts/finops/audit-security-groups.sh
```

### Weekly Cost Report
```bash
# Last 7 days
bash scripts/finops/weekly-cost-report.sh

# Last 30 days
bash scripts/finops/weekly-cost-report.sh 30
```

### VPA Phase 0 Validation

Validates VPA baseline requests convergence and calculates actual savings from rightsizing.

```bash
# Manual validation (run anytime)
bash scripts/finops/vpa-phase0-validation.sh

# With Slack notification
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..." bash scripts/finops/vpa-phase0-validation.sh
```

**Output**: Generates detailed markdown report in `docs/finops/vpa-phase0-validation-report-YYYYMMDD.md`

**Expected Schedule**: Automated run on 2026-02-27 02:00 UTC (via Kubernetes CronJob)

**Report Includes**:
- Target achievement status (≥R$ 15.000/ano target)
- Per-workload resource recommendations
- Savings breakdown by container/pod
- Recommendations for FASE 1 rightsizing
- Health checks and troubleshooting guide

---

## 📁 Relatórios Gerados

Todos os scripts salvam relatórios JSON em:
```
reports/aws-costs/
├── cleanup-YYYY-MM-DD.json                    # Orphan resources
├── cleanup-elastic-ips-YYYY-MM-DD.json        # Elastic IPs
├── cleanup-nat-gateways-YYYY-MM-DD.json       # NAT Gateways
├── cleanup-cloudwatch-logs-YYYY-MM-DD.json    # CloudWatch Logs
├── cleanup-ecr-images-YYYY-MM-DD.json         # ECR Images
├── audit-security-groups-YYYY-MM-DD.json      # Security Groups
├── cleanup-all-YYYY-MM-DD.json                # Consolidated report
└── weekly-YYYY-MM-DD.json                     # Cost report
```

**Formato JSON**:
```json
{
  "scan_date": "2026-02-12T17:00:00-03:00",
  "dry_run": true,
  "findings": [
    {
      "type": "resource_type",
      "count": 10,
      "items": [...],
      "savings_annual_brl": 1200
    }
  ],
  "total_savings_annual_brl": 1200
}
```

---

## ⚙️ Configuração

Scripts usam `platform-config.yaml` para AWS profile e region:
```yaml
aws:
  region: us-east-1
  profile: default
```

**Fallback**: Environment variables `AWS_REGION` e `AWS_PROFILE`.

---

## 🔐 Requisitos

1. **AWS CLI** instalado e configurado
2. **jq** para JSON parsing
3. **Active AWS SSO session**:
   ```bash
   aws sso login --profile default
   aws sts get-caller-identity  # Verificar autenticação
   ```

4. **bc** (para cálculos, scripts CloudWatch/ECR)

---

## 🤖 Automação Planejada / Implementada

### VPA Phase 0 Validation Automation (2026-02-25)

✅ **Implemented**: Kubernetes CronJob for automated validation

```bash
# Deploy CronJob to cluster
kubectl apply -f platform-provisioning/aws/kubernetes/manifests/finops/vpa-phase0-validation-cronjob.yaml

# Check CronJob status
kubectl get cronjobs -n finops
kubectl describe cronjob vpa-phase0-validation -n finops

# View job history
kubectl get jobs -n finops -l app=vpa-phase0-validator

# View job logs
kubectl logs -n finops -l app=vpa-phase0-validator --tail=100
```

**Schedule**: 2026-02-27 02:00 UTC (monthly, day 27 at 2:00 AM)
**Runtime**: ~5 minutes
**Exit Codes**: 0=success, 1=warning, 2=error

### Lambda Automation (TODO)
```bash
# TODO: Implementar Lambda function para cleanup periódico
# EventBridge: Weekly scan + cleanup
# SNS: Notify antes de deletar recursos
```

### AWS Config Rules (TODO)
```bash
# TODO: Implementar Config Rules
# - ec2-volume-inuse-check (alert volumes available >7d)
# - eip-attached (alert unattached Elastic IPs)
```

### Lifecycle Policies (TODO)
```bash
# TODO: Implementar lifecycle policies
# - ECR: Delete untagged images after 7d
# - CloudWatch Logs: 30d retention default
# - S3 Snapshots: Glacier after 30d
```

---

## 📈 Savings Históricos

| Data | Cleanup | Savings |
|------|---------|---------|
| 2026-02-11 | Orphan volumes + snapshots | R$ 2.106/ano |
| 2026-02-12 | Scan completo (zero findings) | R$ 0/ano |

**Total Savings Acumulados**: R$ 30.006/ano (incluindo EKS 1.34, gp3, RDS shutdown).

---

## ⚠️ Avisos Importantes

1. **Dry-run SEMPRE primeiro**: Nunca executar cleanup sem revisar relatórios
2. **Elastic IPs são permanentes**: IPs liberados voltam ao pool AWS (irreversível)
3. **Snapshots críticos**: Verificar se snapshots não são usados por AMIs antes deletar
4. **Security Groups**: Deletar apenas após confirmar não utilizados
5. **CloudWatch Logs**: Exportar para S3 antes deletar log groups grandes
6. **ECR Images**: Verificar se imagens não são usadas por deployments ativos

---

## 🐛 Troubleshooting

### Session Expired
```bash
# Error: "Your session has expired"
aws sso login --profile default

# Verificar autenticação
aws sts get-caller-identity
```

### Permission Denied
```bash
# Verificar IAM permissions necessárias:
# - ec2:DescribeVolumes, ec2:DeleteVolume
# - ec2:DescribeSnapshots, ec2:DeleteSnapshot
# - elasticloadbalancing:DescribeLoadBalancers, elasticloadbalancing:DeleteLoadBalancer
# - ec2:DescribeAddresses, ec2:ReleaseAddress
# - logs:DescribeLogGroups, logs:PutRetentionPolicy, logs:DeleteLogGroup
# - ecr:DescribeImages, ecr:BatchDeleteImage
```

### jq Not Found
```bash
# Ubuntu/Debian
sudo apt-get install jq

# macOS
brew install jq
```

---

## 📞 Support

- **Issues**: Report bugs via GitHub issues
- **Documentation**: See `/docs/finops/` for detailed guides
- **Slack**: #finops-automation (internal)

---

**Última Atualização**: 2026-02-25
**Versão**: 2.1.0
**Autor**: DevOps Team, VPA Automation Team
