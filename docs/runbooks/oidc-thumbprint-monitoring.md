# OIDC Thumbprint Monitoring Runbook

**Data de criação**: 2026-02-25
**Última atualização**: 2026-02-25
**Criticidade**: HIGH - Impacta IRSA (Velero, External Secrets, Cluster Autoscaler)

---

## 📋 Visão Geral

Este runbook documenta o processo de monitoramento do OIDC thumbprint do EKS, essencial para o funcionamento do IRSA (IAM Roles for Service Accounts).

### Por que este script é necessário?

**Problema**: AWS rotaciona periodicamente os certificados intermediários dos OIDC issuers do EKS **sem notificação prévia**.

**Impacto quando desatualizado**:
- ❌ IRSA para de funcionar em todos os serviços
- ❌ Velero: backups falham com `ValidationError: Request ARN is invalid`
- ❌ External Secrets: secrets não sincronizam (SecretSyncedError)
- ❌ Cluster Autoscaler: AccessDenied ao escalar nodes
- ❌ Qualquer workload com ServiceAccount annotation `eks.amazonaws.com/role-arn`

**Root Cause Técnica**:
```
STS valida o thumbprint do certificado OIDC antes de aceitar tokens JWT
Thumbprint desatualizado → STS rejeita → erro genérico "ARN invalid"
Difícil debug: erro não menciona thumbprint explicitamente
```

**Caso Real (2026-02-25)**:
- Velero não funcional por 4h
- Thumbprint configurado: `06b25927c42a721631c1efd9431e648fa62e1e39`
- Thumbprint real (atual): `37647fee5fc063960139521aa2400c75db27825b`
- Descoberta durante V-008 security remediation (Velero IRSA)

**Referência**: `/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/troubleshooting/velero-irsa-solution-2026-02-25.md`

---

## 🔧 Script de Validação

### Localização
```
/home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/validate-oidc-thumbprint.sh
```

### Como funciona

O script compara dois valores:

1. **Thumbprint ATUAL** (configurado no IAM):
   ```bash
   aws iam get-open-id-connect-provider \
     --open-id-connect-provider-arn $OIDC_ARN \
     --query 'ThumbprintList[0]' \
     --output text
   ```

2. **Thumbprint ESPERADO** (do certificado real):
   ```bash
   echo | openssl s_client -servername oidc.eks.us-east-1.amazonaws.com \
     -connect oidc.eks.us-east-1.amazonaws.com:443 2>/dev/null \
     | openssl x509 -fingerprint -noout -sha1 \
     | sed 's/://g' | sed 's/.*=//' | tr '[:upper:]' '[:lower:]'
   ```

3. **Comparação**:
   - Se diferentes → Exit 1 + mensagem de alerta
   - Se iguais → Exit 0 + confirmação

### Exit Codes
- `0`: Thumbprint OK (atualizado)
- `1`: Thumbprint desatualizado (requer ação)

---

## ⚙️ Setup como Cron Job

### Recomendação: Execução Mensal

**Por quê mensal?**
- AWS rotaciona certificados de forma **infrequente** (~ a cada 6-12 meses)
- Check mensal fornece **margem segura de detecção**
- Baixo overhead computacional (< 5s execução)

### Opção 1: Cron Local (Recomendado para Dev/Ops manual)

```bash
# Editar crontab
crontab -e

# Adicionar linha (executa dia 1 de cada mês às 9:00 AM)
0 9 1 * * /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/validate-oidc-thumbprint.sh || echo "ALERTA: OIDC thumbprint desatualizado! Verificar logs." | mail -s "EKS OIDC Thumbprint Alert" ops@example.com
```

**Alternativa com logging**:
```bash
# Executar dia 1 de cada mês às 9:00 AM e logar resultado
0 9 1 * * /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/validate-oidc-thumbprint.sh >> /var/log/oidc-thumbprint-check.log 2>&1 || echo "$(date): FALHA - OIDC thumbprint desatualizado" >> /var/log/oidc-thumbprint-check.log
```

### Opção 2: Kubernetes CronJob (Recomendado para ambientes produtivos)

```yaml
# k8s/monitoring/oidc-thumbprint-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: oidc-thumbprint-validator
  namespace: kube-system
spec:
  schedule: "0 9 1 * *"  # Dia 1 de cada mês às 9:00 AM
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: oidc-validator-sa
          restartPolicy: Never
          containers:
          - name: validator
            image: amazon/aws-cli:2.15.0
            command:
            - /bin/bash
            - -c
            - |
              # Install openssl
              yum install -y openssl

              # Run validation script
              OIDC_ARN="arn:aws:iam::891377105802:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EC913B145BF356481CBE823532F09150"

              CURRENT=$(aws iam get-open-id-connect-provider --open-id-connect-provider-arn $OIDC_ARN --query 'ThumbprintList[0]' --output text)
              EXPECTED=$(echo | openssl s_client -servername oidc.eks.us-east-1.amazonaws.com -connect oidc.eks.us-east-1.amazonaws.com:443 2>/dev/null | openssl x509 -fingerprint -noout -sha1 | sed 's/://g' | sed 's/.*=//' | tr '[:upper:]' '[:lower:]')

              if [ "$CURRENT" != "$EXPECTED" ]; then
                echo "⚠️ OIDC thumbprint desatualizado!"
                echo "Atual: $CURRENT"
                echo "Esperado: $EXPECTED"
                exit 1
              fi

              echo "✅ OIDC thumbprint OK"
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: oidc-validator-sa
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::891377105802:role/k8s-platform-oidc-validator
---
# IAM Role necessário (Terraform):
# resource "aws_iam_role" "oidc_validator" {
#   name = "k8s-platform-oidc-validator"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect = "Allow"
#       Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
#       Action = "sts:AssumeRoleWithWebIdentity"
#       Condition = {
#         StringEquals = {
#           "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:oidc-validator-sa"
#           "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
#         }
#       }
#     }]
#   })
# }
#
# resource "aws_iam_role_policy_attachment" "oidc_validator" {
#   role       = aws_iam_role.oidc_validator.name
#   policy_arn = "arn:aws:iam::aws:policy/IAMReadOnlyAccess"
# }
```

### Opção 3: AWS EventBridge + Lambda (Recomendado para multi-cluster)

```python
# lambda/oidc-thumbprint-validator.py
import boto3
import ssl
import socket
import hashlib
from datetime import datetime

def lambda_handler(event, context):
    iam = boto3.client('iam')

    oidc_arn = "arn:aws:iam::891377105802:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EC913B145BF356481CBE823532F09150"

    # Get current thumbprint
    response = iam.get_open_id_connect_provider(OpenIDConnectProviderArn=oidc_arn)
    current_thumbprint = response['ThumbprintList'][0]

    # Get expected thumbprint from certificate
    hostname = "oidc.eks.us-east-1.amazonaws.com"
    port = 443

    context = ssl.create_default_context()
    with socket.create_connection((hostname, port)) as sock:
        with context.wrap_socket(sock, server_hostname=hostname) as ssock:
            cert_der = ssock.getpeercert(binary_form=True)
            expected_thumbprint = hashlib.sha1(cert_der).hexdigest()

    if current_thumbprint != expected_thumbprint:
        print(f"⚠️ OIDC thumbprint desatualizado!")
        print(f"Atual: {current_thumbprint}")
        print(f"Esperado: {expected_thumbprint}")

        # Send SNS alert
        sns = boto3.client('sns')
        sns.publish(
            TopicArn='arn:aws:sns:us-east-1:891377105802:platform-alerts',
            Subject='[ALERTA] EKS OIDC Thumbprint Desatualizado',
            Message=f"""
            OIDC Thumbprint desatualizado detectado em {datetime.now().isoformat()}

            Thumbprint atual (IAM): {current_thumbprint}
            Thumbprint esperado (certificado): {expected_thumbprint}

            AÇÃO REQUERIDA:
            aws iam update-open-id-connect-provider-thumbprint \\
              --open-id-connect-provider-arn {oidc_arn} \\
              --thumbprint-list {expected_thumbprint}

            Impacto se não corrigido:
            - Velero backups falharão
            - External Secrets não sincronizarão
            - Cluster Autoscaler não funcionará
            - Qualquer IRSA parará de funcionar
            """
        )
        return {'statusCode': 500, 'body': 'Thumbprint desatualizado'}

    print("✅ OIDC thumbprint OK")
    return {'statusCode': 200, 'body': 'Thumbprint atualizado'}
```

**EventBridge Rule (Terraform)**:
```hcl
resource "aws_cloudwatch_event_rule" "oidc_thumbprint_check" {
  name                = "oidc-thumbprint-monthly-check"
  description         = "Valida OIDC thumbprint mensalmente"
  schedule_expression = "cron(0 9 1 * ? *)"  # Dia 1 de cada mês às 9:00 AM UTC
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.oidc_thumbprint_check.name
  target_id = "OIDCThumbprintValidator"
  arn       = aws_lambda_function.oidc_thumbprint_validator.arn
}
```

---

## 🚨 O que fazer se a validação falhar?

### 1. Confirmar o problema

```bash
# Executar script manualmente para ver detalhes
/home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/validate-oidc-thumbprint.sh

# Output esperado quando desatualizado:
# ⚠️ OIDC thumbprint desatualizado!
# Atual: 06b25927c42a721631c1efd9431e648fa62e1e39
# Esperado: 37647fee5fc063960139521aa2400c75db27825b
```

### 2. Verificar impacto nos serviços

```bash
# Verificar Velero BackupStorageLocation
kubectl get backupstoragelocation -n velero
# Se Phase = Unavailable → impactado

# Verificar External Secrets
kubectl get externalsecrets -A | grep -v SecretSynced
# Se existirem erros → impactado

# Verificar logs do Cluster Autoscaler
kubectl logs -n kube-system deployment/cluster-autoscaler | grep -i "AccessDenied"
# Se existirem → impactado
```

### 3. Atualizar thumbprint (Solução)

```bash
# Obter novo thumbprint
NEW_THUMBPRINT=$(echo | openssl s_client -servername oidc.eks.us-east-1.amazonaws.com \
  -connect oidc.eks.us-east-1.amazonaws.com:443 2>/dev/null \
  | openssl x509 -fingerprint -noout -sha1 \
  | sed 's/://g' | sed 's/.*=//' | tr '[:upper:]' '[:lower:]')

echo "Novo thumbprint: $NEW_THUMBPRINT"

# Atualizar no IAM
aws iam update-open-id-connect-provider-thumbprint \
  --open-id-connect-provider-arn arn:aws:iam::891377105802:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EC913B145BF356481CBE823532F09150 \
  --thumbprint-list $NEW_THUMBPRINT

# Aguardar 30-60 segundos para propagação
sleep 60
```

### 4. Validar correção

```bash
# Re-executar script de validação
/home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/validate-oidc-thumbprint.sh
# Deve retornar: ✅ OIDC thumbprint OK

# Verificar Velero
kubectl get backupstoragelocation -n velero
# Phase deve voltar para Available

# Testar backup
kubectl -n velero exec deploy/velero -- /velero backup create test-thumbprint-fix \
  --include-namespaces velero-test --wait
# Deve completar com status: Completed

# Verificar External Secrets
kubectl get externalsecrets -A
# Todos devem voltar para SecretSynced
```

### 5. Pods que requerem restart (se necessário)

```bash
# Se serviços ainda falharem após update, reiniciar pods IRSA:

# Velero
kubectl rollout restart deployment/velero -n velero

# External Secrets Operator (se afetado)
kubectl rollout restart deployment/external-secrets -n external-secrets

# Cluster Autoscaler
kubectl rollout restart deployment/cluster-autoscaler -n kube-system

# Aguardar pods ficarem Ready
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=velero -n velero --timeout=120s
```

### 6. Documentar incidente

```bash
# Criar registro em docs/troubleshooting/
cat > docs/troubleshooting/oidc-thumbprint-rotation-$(date +%Y-%m-%d).md <<EOF
# OIDC Thumbprint Rotation - $(date +%Y-%m-%d)

**Detectado em**: $(date)
**Thumbprint antigo**: [INSERIR AQUI]
**Thumbprint novo**: $NEW_THUMBPRINT
**Serviços impactados**: [LISTAR]
**Tempo de resolução**: [INSERIR]
**Downtime**: [INSERIR]

## Ação tomada
1. Validação com script
2. Update IAM thumbprint
3. Restart pods (se necessário)
4. Validação final

## Prevenção futura
- Cron job configurado: [SIM/NÃO]
- Alertas configurados: [SIM/NÃO]
EOF
```

---

## 📊 Monitoramento e Alertas

### Métricas para monitorar

1. **Script exit code** (cron/K8s CronJob):
   - Exit 0 → OK
   - Exit 1 → ALERTA

2. **Velero BackupStorageLocation status**:
   ```bash
   kubectl get backupstoragelocation -n velero -o jsonpath='{.items[0].status.phase}'
   # Esperado: Available
   ```

3. **External Secrets sync status**:
   ```bash
   kubectl get externalsecrets -A -o json | jq '.items[] | select(.status.conditions[0].type == "SecretSynced" and .status.conditions[0].status != "True")'
   # Esperado: sem output (todos synced)
   ```

4. **STS errors nos logs de pods IRSA**:
   ```bash
   kubectl logs -n velero deployment/velero | grep -i "ValidationError.*ARN.*invalid"
   # Esperado: sem output
   ```

### Alertas recomendados (Prometheus)

```yaml
# prometheus-rules/oidc-thumbprint-alerts.yaml
groups:
- name: oidc-thumbprint
  interval: 5m
  rules:
  - alert: OIDCThumbprintValidationFailed
    expr: kube_job_status_failed{job_name=~"oidc-thumbprint-validator.*"} > 0
    for: 5m
    labels:
      severity: critical
      component: iam
    annotations:
      summary: "OIDC thumbprint desatualizado detectado"
      description: "Job oidc-thumbprint-validator falhou. IRSA pode parar de funcionar em breve."
      runbook: "https://github.com/yourorg/kubernetes/blob/main/docs/runbooks/oidc-thumbprint-monitoring.md"

  - alert: VeleroBackupStorageUnavailable
    expr: velero_backup_storage_location_available == 0
    for: 10m
    labels:
      severity: warning
      component: velero
    annotations:
      summary: "Velero BackupStorageLocation indisponível"
      description: "BSL {{ $labels.storage_location }} está Unavailable. Pode ser OIDC thumbprint desatualizado."
      runbook: "https://github.com/yourorg/kubernetes/blob/main/docs/runbooks/oidc-thumbprint-monitoring.md"
```

---

## 🔍 Troubleshooting Avançado

### Problema: Script retorna erro mesmo após update

**Possíveis causas**:

1. **Propagação IAM lenta** (30-60s):
   ```bash
   # Aguardar e re-testar
   sleep 60
   /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/validate-oidc-thumbprint.sh
   ```

2. **Certificado intermediário vs root**:
   ```bash
   # Validar cadeia completa
   echo | openssl s_client -showcerts -servername oidc.eks.us-east-1.amazonaws.com \
     -connect oidc.eks.us-east-1.amazonaws.com:443 2>/dev/null
   # Verificar qual certificado da cadeia está sendo usado
   ```

3. **OIDC ARN incorreto no script**:
   ```bash
   # Obter ARN correto do cluster
   CLUSTER_NAME="k8s-platform-prod"
   OIDC_ISSUER=$(aws eks describe-cluster --name $CLUSTER_NAME --query 'cluster.identity.oidc.issuer' --output text)
   OIDC_ID=$(echo $OIDC_ISSUER | cut -d'/' -f5)

   echo "OIDC ARN correto:"
   echo "arn:aws:iam::891377105802:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/$OIDC_ID"

   # Atualizar script com ARN correto
   ```

### Problema: Serviços continuam falhando após thumbprint correto

**Verificar formato ARN do role**:
```bash
# ARN INCORRETO (causa "Request ARN is invalid")
kubectl get sa velero-server -n velero -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
# Se retornar: arn:aws:iam::ACCOUNT:role:ROLE_NAME (dois pontos)
# → ERRADO

# Corrigir para formato correto (barra)
kubectl annotate sa velero-server -n velero \
  eks.amazonaws.com/role-arn=arn:aws:iam::891377105802:role/k8s-platform-prod-velero-role \
  --overwrite

# Deletar pod para aplicar
kubectl delete pod -n velero -l app.kubernetes.io/name=velero
```

---

## 📚 Referências

- **Troubleshooting case**: `docs/troubleshooting/velero-irsa-solution-2026-02-25.md`
- **AWS IRSA Troubleshooting**: https://repost.aws/knowledge-center/eks-troubleshoot-irsa-errors
- **OIDC Provider Management**: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html
- **IAM ARN Format Spec**: https://docs.aws.amazon.com/IAM/latest/UserGuide/reference-arns.html
- **EKS Best Practices - IRSA**: https://aws.github.io/aws-eks-best-practices/security/docs/iam/#irsa

---

## ✅ Checklist de Setup

- [ ] Script criado em `/scripts/validate-oidc-thumbprint.sh`
- [ ] Script testado manualmente (exit 0)
- [ ] Cron job configurado (mensal)
- [ ] Alertas Prometheus configurados
- [ ] SNS topic criado para notificações (opcional)
- [ ] Runbook compartilhado com time de Ops
- [ ] Teste de rotação simulado (alterar thumbprint manualmente e corrigir)
- [ ] Documentação de incidentes template criada

---

**Criado por**: Claude Sonnet 4.5
**Revisado por**: Platform Team
**Próxima revisão**: 2026-08-25 (6 meses)
