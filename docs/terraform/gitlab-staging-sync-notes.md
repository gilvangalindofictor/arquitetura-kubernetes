# GitLab Terraform Sync Notes
**Data:** 2026-02-13
**Status:** GitLab instalado via Helm manual (não gerenciado pelo Terraform)
**Motivo:** Terraform PostgreSQL provider timeout ao tentar conectar no RDS da workstation local

## Configuração Atual (Funcionando)

### Helm Release
- **Chart:** gitlab/gitlab 8.7.0
- **Namespace:** gitlab-staging
- **Revision:** 2 (deployed)
- **Método:** Helm manual (`helm install gitlab gitlab/gitlab -f values.yaml`)

### Mudanças Críticas vs Template Terraform

#### 1. Domain Configuration
```yaml
# Template atual (ERRADO):
global:
  hosts:
    domain: example.com

# Configuração funcionando (CORRETO):
global:
  hosts:
    domain: staging.internal
    https: false
```

#### 2. Redis Authentication
```yaml
# Template atual (ERRADO):
global:
  redis:
    host: ${redis_host}
    port: ${redis_port}
    password:
      enabled: true
      secret: ${redis_password_secret}
      key: password

# Configuração funcionando (CORRETO):
global:
  redis:
    host: redis.data-services.svc.cluster.local
    port: 6379
    auth:
      enabled: true
      secret: gitlab-redis-password
      key: password
```

**Nota:** OT-Container-Kit Redis operator (novo, migrado de SpotaHome) requer `auth` ao invés de `password`.

#### 3. Ingress Group Name
```yaml
# Configuração funcionando:
global:
  ingress:
    annotations:
      alb.ingress.kubernetes.io/group.name: gitlab-staging
```

Isso agrupa todos os ingresses GitLab (webservice, kas, minio) no **mesmo ALB**, economizando custos (~R$ 1.920/ano).

#### 4. Resources Otimizados para Staging

```yaml
# webservice (principal ajuste):
gitlab:
  webservice:
    minReplicas: 1
    maxReplicas: 1
    resources:
      requests:
        cpu: 300m        # Reduzido de 500m
        memory: 1536Mi   # Reduzido de 2Gi
      limits:
        cpu: 2000m
        memory: 4Gi

# gitaly (storage):
  gitaly:
    persistence:
      enabled: true
      storageClass: gp3
      size: 50Gi
    resources:
      requests:
        cpu: 100m        # Reduzido de 200m
        memory: 384Mi    # Reduzido de 512Mi
      limits:
        cpu: 500m
        memory: 1Gi

# sidekiq (background jobs):
  sidekiq:
    minReplicas: 1
    maxReplicas: 1
    resources:
      requests:
        cpu: 500m
        memory: 1Gi
      limits:
        cpu: 1000m
        memory: 2Gi
```

#### 5. HPAs para Staging (1 replica)

```yaml
# gitlab-shell HPA:
gitlab-shell:
  hpa:
    minReplicas: 1    # Reduzido de 2
    maxReplicas: 1    # Reduzido de 10

# gitlab-kas HPA:
gitlab-kas:
  hpa:
    minReplicas: 1    # Reduzido de 2
    maxReplicas: 1    # Reduzido de 10
```

**Nota:** Template atual pode não ter essas configurações de HPA explícitas.

#### 6. Componentes Desabilitados

```yaml
# Já correto no template:
postgresql:
  install: false

redis:
  install: false

nginx-ingress:
  enabled: false

certmanager:
  install: false

prometheus:
  install: false

registry:
  enabled: false

# gitlab-runner mantido:
gitlab-runner:
  install: true
  replicas: 1
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
```

## Secrets Existentes (Não Recriar)

```bash
# Já existem no cluster:
gitlab-postgresql-password     # PostgreSQL RDS
gitlab-redis-password          # Redis OT-Container-Kit
gitlab-oidc-keycloak          # Keycloak SSO
gitlab-object-storage         # S3 IRSA
gitlab-root-password          # Admin inicial
```

## Próximos Passos (Quando Aplicar Terraform)

1. **Opção A: Importar Release Helm para Terraform State**
   ```bash
   terraform import module.gitlab_staging.helm_release.gitlab gitlab-staging/gitlab
   ```
   - ⚠️ Complexo, pode causar conflitos

2. **Opção B: Manter Helm Manual (Recomendado para agora)**
   - Atualizar código Terraform com configurações acima
   - Deixar preparado para futuras aplicações
   - Não forçar import até resolver timeout PostgreSQL provider

3. **Resolver Timeout PostgreSQL Provider**
   - Opção 1: Bastion host na VPC para rodar Terraform
   - Opção 2: VPN para acessar VPC privada
   - Opção 3: Remover provider PostgreSQL do módulo (databases já existem)

## Validação

```bash
# Verificar estado atual:
helm list -n gitlab-staging
kubectl get pods -n gitlab-staging
kubectl get ingress -n gitlab-staging
kubectl get hpa -n gitlab-staging

# Acesso:
http://gitlab.staging.internal
# Login: root / <ver secret gitlab-root-password>
```

## FinOps Impact

- **Recursos Liberados:** ~200m CPU + ~256Mi RAM (HPAs ajustados de 2→1)
- **ALB Consolidation:** 3 ALBs → 1 ALB = R$ 1.920/ano economizados
- **Total Pods:** 11 (9 Running + 2 Completed)

## Referências

- Values usados: `/tmp/gitlab-restore-values.yaml`
- Logbook: `docs/logbook/2026-02-13-gitlab-vault-restoration.md`
- Template Terraform: `modules/gitlab/values.yaml.tpl`
