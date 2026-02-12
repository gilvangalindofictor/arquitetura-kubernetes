# Plano de Ação — 2026-02-12 (Simplificado)

**Status Consolidado**: [../STATUS-2026-02-12.md](../STATUS-2026-02-12.md)
**Economias Realizadas**: R$ 34.462/ano (115% da meta)
**Pendências**: 2 tasks (2h15min total)

---

## ✅ Economias Já Realizadas

| Iniciativa                 | Economia/ano      | Status        |
| -------------------------- | ----------------- | ------------- |
| **EKS Control Plane 1.34** | **R$ 18.468**     | ✅ COMPLETO   |
| **EC2 Rightsizing 10 → 7** | **R$ 13.104**     | ✅ COMPLETO   |
| **RDS Weekend Shutdown**   | **R$ 2.890**      | ✅ COMPLETO   |
| **TOTAL**                  | **R$ 34.462/ano** | **115% meta** |

---

## ⚠️ Pendências Hoje (2h15min)

### 1. 🔥 GitLab OIDC Integration (45min)

**Status**: Helm release em `pending-upgrade`, bloqueia Terraform apply

#### Execução

```bash
# 1. Rollback Helm (10min)
helm rollback gitlab 1 -n gitlab-staging --wait --timeout=5m
helm status gitlab -n gitlab-staging

# 2. Terraform Apply OIDC (20min)
cd platform-provisioning/aws/kubernetes/terraform/environments/staging
terraform apply -target=module.keycloak_staging -target=module.gitlab_staging -auto-approve

# 3. E2E Test SSO (15min)
kubectl port-forward -n gitlab-staging svc/gitlab-webservice-default 8080:8080
# Browser: http://localhost:8080 → "Sign in with OpenID Connect"
# Expected: Redirect to Keycloak → Login → Redirect back authenticated
```

#### Success Criteria

- [ ] Helm rollback success (status: deployed)
- [ ] Terraform apply success
- [ ] SSO button visible on GitLab login
- [ ] E2E test: Login via Keycloak successful

---

### 2. ⚠️ Node Groups Upgrade para v1.34 (1h30min)

**Status**: Control plane v1.34 ✅, Nodes v1.31 ⚠️

**Impacto**: Desalinhamento de versões (funcional, mas não ideal)

#### Execução

```bash
# 1. Backup pré-upgrade (15min)
kubectl get all -A -o yaml > /tmp/k8s-backup-$(date +%Y%m%d).yaml
for ns in gitlab-staging keycloak vault-system monitoring; do
  kubectl get all,cm,secret,pvc -n $ns -o yaml > /tmp/backup-$ns-$(date +%Y%m%d).yaml
done

# 2. Terraform Apply (30min)
cd platform-provisioning/aws/kubernetes/terraform/environments/staging
terraform plan -var="cluster_version=1.34"
terraform apply -var="cluster_version=1.34" -auto-approve

# 3. Monitor Rolling Replacement (45min)
# Expected: ~15min/node × 7 nodes = 1.75h total
kubectl get nodes -w
kubectl get pods -n gitlab-staging -w
kubectl get pods -n keycloak -w

# 4. Validate (10min)
kubectl get nodes -o wide | awk '{print $1, $5}'  # Expected: v1.34.x
kubectl get pods -A | grep -vE 'Running|Completed'  # Expected: empty
```

#### Success Criteria

- [ ] Backup completo criado
- [ ] Terraform apply success
- [ ] All nodes running v1.34.x
- [ ] All pods Running (no CrashLoopBackOff)
- [ ] GitLab + Keycloak UI accessible

---

## 📊 Timeline Hoje

| Horário       | Task                   | Duração | Status      |
| ------------- | ---------------------- | ------- | ----------- |
| 11:00 - 11:45 | GitLab OIDC Completion | 45min   | ⏸️ Pendente |
| 11:45 - 12:00 | ☕ Break               | 15min   | -           |
| 12:00 - 13:30 | Node Groups Upgrade    | 1h30min | ⏸️ Pendente |

**Total**: 2h15min

---

## 🎯 Critérios de Sucesso Dia

1. ✅ **GitLab OIDC Funcional** (SSO login E2E working)
2. ✅ **Nodes v1.34** (todos nodes upgraded, zero downtime)

**Após Conclusão**: Quickstart MVP **100% completo** (exceto Velero diferido)

---

## 📝 Próximos Passos (Semana)

### Otimizações Adicionais (4h5min, R$ 9.319/ano)

1. **ALB IngressGroup** (3h) - Consolidar 10 → 4 ALBs = R$ 5.847/ano
2. **EBS gp2 → gp3** (1h) - Migrar volumes = R$ 1.520/ano
3. **Delete Test ALBs** (5min) - Cleanup 2 units = R$ 1.952/ano

**Total Economia Potencial**: R$ 43.781/ano (quando completo)

---

## 🚧 Rollback Plans

### GitLab OIDC

Se SSO falhar, desabilitar temporariamente:

```bash
kubectl edit secret -n gitlab-staging gitlab-gitlab-omniauth
# Set allowSingleSignOn: false
kubectl rollout restart deployment -n gitlab-staging gitlab-webservice-default
```

### Node Groups Upgrade

Se upgrade falhar:

```bash
# Terraform NÃO suporta downgrade 1.34 → 1.31
# Opções:
# 1. Restore from backup: kubectl apply -f /tmp/k8s-backup-*.yaml
# 2. Create new 1.31 cluster and migrate (4h+ effort)
# Prevention: Ensure backups exist before upgrade ✅
```

---

**Criado**: 2026-02-12 11:00 BRT
**Baseado**: [STATUS-2026-02-12.md](../STATUS-2026-02-12.md), AWS validation real
**Arquivos Obsoletos**: Movidos para [archive/2026-02-12/](../../archive/2026-02-12/)
