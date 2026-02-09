# GAP-004: SonarQube Deployment - Workflow Prompt

**Status**: 🟢 PRONTO PARA EXECUÇÃO
**Pré-requisito**: ✅ GAP-001 (Keycloak) completo
**Duração Estimada**: 2h
**Custo**: +$50/mês

---

## 📋 Prompt para o Agente

```
Implemente o GAP-004: SonarQube Deploy conforme especificação abaixo.

CONTEXTO:
- Keycloak SSO já está operacional em staging
- Módulo Terraform modules/sonarqube/ já existe (scaffold)
- Bootstrap script já existe: scripts/sonarqube/bootstrap-database.sh
- Database PostgreSQL RDS já existe
- Vault + ESO operacionais

OBJETIVO:
Deploy completo do SonarQube Community Edition com integração OIDC Keycloak para code quality analysis.

REQUISITOS TÉCNICOS:

1. Database Bootstrap:
   - Database: sonarqube
   - User: sonarqube_user
   - Password: gerar com openssl rand -base64 32
   - Script: ✅ JÁ EXISTE scripts/sonarqube/bootstrap-database.sh
   - Executar: ./bootstrap-database.sh (já está pronto)

2. Vault Secrets:
   - Path: secret/sonarqube/postgresql (username, password, host, port, database)
   - Path: secret/sonarqube/oidc (client_id=sonarqube, client_secret=<do keycloak>)
   - Recuperar client_secret: kubectl get secret sonarqube-oidc -n keycloak -o jsonpath='{.data.client-secret}' | base64 -d

3. Terraform Module (modules/sonarqube/):
   - Completar scaffold existente
   - ExternalSecret para PostgreSQL credentials
   - ExternalSecret para OIDC credentials
   - Helm release: sonarqube/sonarqube (chart oficial)
   - PersistentVolumeClaim: 20Gi (data, extensions, logs)
   - values.yaml.tpl com:
     * PostgreSQL external (RDS)
     * OIDC Keycloak integration
     * Issuer: http://keycloak-http.keycloak.svc.cluster.local/auth/realms/platform
     * Auto-provisioning: sync groups (developers)

4. SonarQube Configuration:
   - Quality Gates padrão
   - Quality Profiles: Sonar way (default)
   - Projects: criar exemplo "platform-infra"

5. Integração Terraform:
   - Adicionar module call em environments/staging/main.tf
   - Dependencies: postgresql_staging, keycloak_staging

6. Validação:
   - SonarQube UI acessível (port-forward)
   - Login OIDC funcional com usuário Keycloak
   - Análise de código teste (exemplo project)
   - Quality gates configurados

ENTREGÁVEIS:

1. Database Bootstrap:
   - ✅ Script já existe: scripts/sonarqube/bootstrap-database.sh
   - Executar e validar

2. Módulo Terraform completo:
   - modules/sonarqube/main.tf
   - modules/sonarqube/variables.tf
   - modules/sonarqube/outputs.tf
   - modules/sonarqube/values.yaml.tpl
   - modules/sonarqube/manifests/external-secret-db.yaml
   - modules/sonarqube/manifests/external-secret-oidc.yaml
   - modules/sonarqube/manifests/pvc.yaml

3. Integration:
   - environments/staging/main.tf (module sonarqube_staging)

4. Documentação:
   - modules/sonarqube/README.md (atualizar com deployment real)
   - Logbook: docs/logbook/2026-02-0X-sonarqube-deployment.md
   - ADR-035 atualizado com PostgreSQL RDS

5. Validação:
   - Port-forward: kubectl port-forward -n sonarqube svc/sonarqube 9000:9000
   - Login OIDC testado
   - Project exemplo analisado

CONSTRAINTS:

- Usar External PostgreSQL (RDS), NÃO embedded H2
- OIDC obrigatório (não usar admin password)
- Persistent storage obrigatório (20Gi PVC)
- Secrets via Vault + ESO (não K8s secrets diretos)
- System node tolerations (ADR-042)
- ServiceMonitor para Prometheus

CONFIGURAÇÃO SONARQUBE:

Environment variables necessárias:
```yaml
sonar.web.javaOpts: "-Xmx2048m -Xms512m"
sonar.ce.javaOpts: "-Xmx1024m -Xms512m"

# OIDC Configuration
sonar.auth.oidc.enabled: true
sonar.auth.oidc.issuerUri: http://keycloak-http.keycloak.svc.cluster.local/auth/realms/platform
sonar.auth.oidc.clientId.secured: sonarqube
sonar.auth.oidc.clientSecret.secured: <from-vault>
sonar.auth.oidc.groupsSync: true
sonar.auth.oidc.groupsSync.claimName: groups

# Database
sonar.jdbc.url: jdbc:postgresql://<rds-endpoint>:5432/sonarqube
sonar.jdbc.username: <from-vault>
sonar.jdbc.password: <from-vault>
```

PADRÕES A SEGUIR:

1. Bootstrap database: usar script existente scripts/sonarqube/bootstrap-database.sh
2. Vault paths: secret/sonarqube/* (KV v2)
3. ExternalSecret CRDs: usar ClusterSecretStore vault-backend
4. Helm values: minimal, não override defaults desnecessários
5. PVC: StorageClass gp3, ReadWriteOnce
6. README: documentar Known Issues se houver

REFERÊNCIAS:

- Keycloak deployment: docs/logbook/2026-02-06-keycloak-sso-deployment.md
- Bootstrap script: terraform/scripts/sonarqube/bootstrap-database.sh (✅ JÁ EXISTE)
- Keycloak module: modules/keycloak/README.md
- SonarQube docs: https://docs.sonarsource.com/sonarqube/latest/

WORKFLOW:

1. Executar bootstrap database (script já existe)
2. Validar database e user criados
3. Armazenar credentials no Vault
4. Recuperar OIDC client secret do Keycloak
5. Armazenar OIDC config no Vault
6. Completar módulo Terraform
7. Terraform plan
8. Obter aprovação do usuário
9. Terraform apply
10. Aguardar startup (SonarQube lento ~3-5min)
11. Troubleshoot se necessário
12. Validar deployment (UI, OIDC, DB)
13. Criar project teste
14. Análise de código teste
15. Criar/atualizar documentação
16. Atualizar demands-backlog.md (GAP-004 completo)

IMPORTANTE:
- SonarQube startup é LENTO (~3-5 minutos) - ajustar probes
- PVC deve ser provisionado antes do pod start
- Se Vault permissions falharem, criar K8s secrets diretos temporariamente
- Documentar TODOS os workarounds aplicados
- Atualizar ADR-035 com decisões PostgreSQL

TROUBLESHOOTING COMUM:

1. Startup lento: normal, aguardar 5min
2. PVC pending: verificar StorageClass gp3
3. Database connection: verificar security group RDS
4. OIDC redirect: usar port-forward ou ingress correto
5. Quality gates: configurados automaticamente na primeira análise
```

---

## 🎯 Critérios de Sucesso

- [ ] SonarQube pod running (1/1 Ready) após ~5min
- [ ] UI acessível via port-forward (porta 9000)
- [ ] Login OIDC funcional com usuário admin@example.com (Keycloak)
- [ ] PostgreSQL RDS integration funcional
- [ ] PVC provisionado e bound (20Gi)
- [ ] Quality Gates configurados
- [ ] Project teste criado e analisado
- [ ] Secrets via Vault + ESO (ou workaround documentado)
- [ ] README atualizado com deployment real
- [ ] Logbook criado
- [ ] ADR-035 atualizado

---

## 🔧 Comandos Úteis

```bash
# Bootstrap database (script já existe)
cd platform-provisioning/aws/kubernetes/terraform/scripts/sonarqube
./bootstrap-database.sh

# Recuperar OIDC client secret
kubectl get secret sonarqube-oidc -n keycloak -o jsonpath='{.data.client-secret}' | base64 -d

# Terraform
cd environments/staging
terraform plan -target=module.sonarqube_staging
terraform apply -target=module.sonarqube_staging

# Validação
kubectl get pods -n sonarqube
kubectl get pvc -n sonarqube
kubectl logs -n sonarqube -l app=sonarqube --tail=100

# Port-forward
kubectl port-forward -n sonarqube svc/sonarqube 9000:9000

# Login OIDC
# Browser: http://localhost:9000
# Click "LOG IN WITH KEYCLOAK" ou "OIDC"
# User: admin@example.com / password

# Criar project teste via API
curl -u admin:<token> -X POST "http://localhost:9000/api/projects/create?name=test-project&project=test-project"

# Scanner exemplo (Java)
sonar-scanner \
  -Dsonar.projectKey=test-project \
  -Dsonar.sources=. \
  -Dsonar.host.url=http://localhost:9000 \
  -Dsonar.login=<token>
```

---

## 📚 Arquivos de Referência

- [GAP-004 Spec](../demands-backlog.md#gap-004)
- [Bootstrap Script](../../platform-provisioning/aws/kubernetes/terraform/scripts/sonarqube/bootstrap-database.sh) ✅ JÁ EXISTE
- [Keycloak Logbook](../logbook/2026-02-06-keycloak-sso-deployment.md)
- [ADR-035: SonarQube Code Quality](../adr/adr-035-sonarqube-code-quality.md)

---

## ⚠️ Avisos Importantes

1. **Startup Lento**: SonarQube pode levar 3-5 minutos para ficar ready
2. **PVC Obrigatório**: Sem persistent storage, SonarQube perde dados ao restart
3. **Memory**: Requer ~3GB RAM total (web + compute engine)
4. **Database**: PostgreSQL 11+ requerido (✅ RDS já suporta)

---

_Preparado em: 2026-02-06_
