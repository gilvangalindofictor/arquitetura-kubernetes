# GAP-003: ArgoCD Deployment - Workflow Prompt

**Status**: 🟢 PRONTO PARA EXECUÇÃO
**Pré-requisito**: ✅ GAP-001 (Keycloak) completo
**Duração Estimada**: 2h
**Custo**: +$15/mês

---

## 📋 Prompt para o Agente

```
Implemente o GAP-003: ArgoCD Deploy conforme especificação abaixo.

CONTEXTO:
- Keycloak SSO já está operacional em staging
- Módulo Terraform modules/argocd/ já existe (scaffold)
- Database PostgreSQL RDS já existe
- Vault + ESO operacionais

OBJETIVO:
Deploy completo do ArgoCD com integração OIDC Keycloak para GitOps.

REQUISITOS TÉCNICOS:

1. Database Bootstrap:
   - Database: argocd
   - User: argocd_user
   - Password: gerar com openssl rand -base64 32
   - Script: usar mesmo padrão do keycloak bootstrap

2. Vault Secrets:
   - Path: secret/argocd/postgresql (username, password, host, port, database)
   - Path: secret/argocd/oidc (client_id=argocd, client_secret=<do keycloak>)
   - Recuperar client_secret: kubectl get secret argocd-oidc -n keycloak -o jsonpath='{.data.client-secret}' | base64 -d

3. Terraform Module (modules/argocd/):
   - Completar scaffold existente
   - ExternalSecret para PostgreSQL credentials
   - ExternalSecret para OIDC credentials
   - Helm release: argo/argo-cd versão estável
   - values.yaml.tpl com:
     * PostgreSQL external (RDS)
     * OIDC Keycloak integration
     * Issuer: http://keycloak-http.keycloak.svc.cluster.local/auth/realms/platform
     * RBAC policy: argocd-admins group → role:admin

4. AppProjects:
   - Project: platform (infra components)
   - Project: applications (user apps)
   - Source repos: GitLab internal
   - Destinations: staging, production namespaces

5. Integração Terraform:
   - Adicionar module call em environments/staging/main.tf
   - Dependencies: postgresql_staging, keycloak_staging

6. Validação:
   - ArgoCD UI acessível (port-forward)
   - Login OIDC funcional com usuário Keycloak
   - Sync de app teste (nginx hello-world)
   - RBAC: argocd-admins group tem acesso admin

ENTREGÁVEIS:

1. Script bootstrap database:
   - platform-provisioning/aws/kubernetes/terraform/scripts/argocd/bootstrap-database.sh
   - Padrão keycloak bootstrap

2. Módulo Terraform completo:
   - modules/argocd/main.tf
   - modules/argocd/variables.tf
   - modules/argocd/outputs.tf
   - modules/argocd/values.yaml.tpl
   - modules/argocd/manifests/external-secret-db.yaml
   - modules/argocd/manifests/external-secret-oidc.yaml
   - modules/argocd/manifests/appproject-platform.yaml
   - modules/argocd/manifests/appproject-applications.yaml

3. Integration:
   - environments/staging/main.tf (module argocd_staging)

4. Documentação:
   - modules/argocd/README.md (atualizar com deployment real)
   - Logbook: docs/logbook/2026-02-0X-argocd-deployment.md
   - ADR-034 atualizado com OIDC Keycloak

5. Validação:
   - Port-forward: kubectl port-forward -n argocd svc/argocd-server 8080:443
   - Login OIDC testado
   - App teste synced

CONSTRAINTS:

- Usar External PostgreSQL (RDS), NÃO embedded
- OIDC obrigatório (não usar admin password)
- RBAC via Keycloak groups
- Secrets via Vault + ESO (não K8s secrets diretos)
- System node tolerations (ADR-042)
- ServiceMonitor para Prometheus

PADRÕES A SEGUIR:

1. Bootstrap database: mesmo padrão keycloak/bootstrap-database.sh
2. Vault paths: secret/argocd/* (KV v2)
3. ExternalSecret CRDs: usar ClusterSecretStore vault-backend
4. Helm values: minimal, não override defaults desnecessários
5. README: documentar Known Issues se houver

REFERÊNCIAS:

- Keycloak deployment: docs/logbook/2026-02-06-keycloak-sso-deployment.md
- Bootstrap guide: terraform/scripts/keycloak/BOOTSTRAP_GUIDE.md
- Keycloak module: modules/keycloak/README.md
- ArgoCD docs: https://argo-cd.readthedocs.io/en/stable/

WORKFLOW:

1. Criar script bootstrap database
2. Executar bootstrap (database + user)
3. Armazenar credentials no Vault
4. Recuperar OIDC client secret do Keycloak
5. Armazenar OIDC config no Vault
6. Completar módulo Terraform
7. Terraform plan
8. Obter aprovação do usuário
9. Terraform apply
10. Troubleshoot se necessário
11. Validar deployment (UI, OIDC, RBAC)
12. Criar/atualizar documentação
13. Atualizar demands-backlog.md (GAP-003 completo)

IMPORTANTE:
- Se encontrar issues com Vault permissions (como no Keycloak), criar K8s secrets diretos temporariamente
- Se pods crasharem, investigar logs antes de escalar
- Documentar TODOS os workarounds aplicados
- Atualizar ADR-034 com decisões OIDC
```

---

## 🎯 Critérios de Sucesso

- [ ] ArgoCD pod running (1/1 Ready)
- [ ] UI acessível via port-forward
- [ ] Login OIDC funcional com usuário admin@example.com (Keycloak)
- [ ] RBAC: argocd-admins group → role:admin
- [ ] App teste (nginx) synced com sucesso
- [ ] AppProjects (platform, applications) criados
- [ ] PostgreSQL RDS integration funcional
- [ ] Secrets via Vault + ESO (ou workaround documentado)
- [ ] README atualizado com deployment real
- [ ] Logbook criado
- [ ] ADR-034 atualizado

---

## 🔧 Comandos Úteis

```bash
# Bootstrap database
cd platform-provisioning/aws/kubernetes/terraform/scripts/argocd
./bootstrap-database.sh

# Recuperar OIDC client secret
kubectl get secret argocd-oidc -n keycloak -o jsonpath='{.data.client-secret}' | base64 -d

# Terraform
cd environments/staging
terraform plan -target=module.argocd_staging
terraform apply -target=module.argocd_staging

# Validação
kubectl get pods -n argocd
kubectl port-forward -n argocd svc/argocd-server 8080:443

# Login OIDC
# Browser: https://localhost:8080
# Click "LOG IN VIA KEYCLOAK"
# User: admin@example.com / password

# Sync app teste
argocd app create nginx-test \
  --repo https://github.com/argoproj/argocd-example-apps.git \
  --path guestbook \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default

argocd app sync nginx-test
```

---

## 📚 Arquivos de Referência

- [GAP-003 Spec](../demands-backlog.md#gap-003)
- [Keycloak Logbook](../logbook/2026-02-06-keycloak-sso-deployment.md)
- [ADR-034: ArgoCD ApplicationSets](../adr/adr-034-argocd-applicationsets.md)
- [Bootstrap Guide Template](../../platform-provisioning/aws/kubernetes/terraform/scripts/keycloak/BOOTSTRAP_GUIDE.md)

---

_Preparado em: 2026-02-06_
