# Guia de Onboarding de Aplicações

> **Versão**: 1.0 | **Data**: 2026-02-09 | **Referência**: GOVERNANCE.md

## 🎯 Processo de Onboarding (5 Etapas)

### Etapa 1: Pré-Onboarding (Checklist)

```markdown
- [ ] Aplicação enquadrada em domínio (integration, data, operations, shared-services)
- [ ] Dockerfile criado e testado localmente
- [ ] Helm chart criado (ou usar chart library do domínio)
- [ ] Secrets identificados (migrar para Vault)
- [ ] Dependencies mapeadas (PostgreSQL, Redis, S3, etc)
- [ ] Naming conventions validadas (ADR-048)
- [ ] Labels obrigatórias definidas
```

### Etapa 2: Staging Deployment

```bash
# 1. Criar namespace (se necessário)
kubectl create namespace staging-{domain}-{product}

# 2. Aplicar ResourceQuota
kubectl apply -f resourcequota-staging.yaml -n staging-{domain}-{product}

# 3. Deploy via Helm
helm install {product}-staging {chart-name} \
  --namespace staging-{domain}-{product} \
  --values values-staging.yaml

# 4. Validar deployment
kubectl get pods -n staging-{domain}-{product}
kubectl logs -f deployment/{product} -n staging-{domain}-{product}

# 5. Testes
curl https://{product}-staging.company.com/healthz
```

### Etapa 3: Production Deployment

```bash
# Deploy com Canary (ArgoCD)
argocd app create {domain}-{product}-prod \
  --repo https://gitlab.company.com/corporate-domains/{domain}/{product}-gitops.git \
  --path prod \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace prod-{domain}-{product}

# Monitoramento pós-deploy (24h)
kubectl top pods -n prod-{domain}-{product}
```

### Etapa 4: Backstage Registration

```bash
# Criar catalog-info.yaml no repo
cat > catalog-info.yaml <<EOF
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: {product}
spec:
  owner: {domain}-team
  system: {domain}-{product}
EOF

# Commit e push
git add catalog-info.yaml
git commit -m "[{domain}:chore] add Backstage catalog"
git push
```

### Etapa 5: Documentação

```markdown
- [ ] README.md no repo (setup local, deploy, troubleshooting)
- [ ] Runbook em `/docs/runbooks/{product}-runbook.md`
- [ ] Atualizar `/corporate-domains/{domain}/README.md`
```

## ✅ Critérios de Aprovação

**Staging**: Tech Lead do domínio
**Production**: Platform Team + Tech Lead

## 📚 Referências

- [GOVERNANCE.md](./GOVERNANCE.md)
- [Naming Conventions](./naming-conventions.md)
- [RBAC Matrix](./rbac-matrix.md)
