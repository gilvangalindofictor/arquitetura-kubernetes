# Kubernetes Monitoring Context
**Criado**: 2026-03-24
**Maintainer**: Monitoring Orchestrator

## Arquivos Neste Diretório

| Arquivo | Descrição |
|---------|-----------|
| `monitoring-state-2026-03-24.md` | Estado inicial do ambiente — baseline e log de sessão |
| `incident-vault-prod-p1.md` | Runbook detalhado para INC-001 vault-prod-0 Pending |
| `monitoring-report-template.md` | Template para relatórios de monitoramento |
| `diagnostics-scripts.sh` | Script de diagnóstico kubectl/aws completo |
| `README.md` | Este arquivo |

## Como Usar

### 1. Autenticação AWS SSO
```bash
aws sso login --profile k8s-platform-prod
# ou device flow:
python3 -c "
import boto3, json
sso = boto3.client('sso-oidc', region_name='us-east-1')
c = sso.register_client(clientName='test', clientType='public')
d = sso.start_device_authorization(clientId=c['clientId'], clientSecret=c['clientSecret'], startUrl='https://d-906621cd5f.awsapps.com/start/')
print('URL:', d['verificationUriComplete'])
print('Code:', d['userCode'])
"
```

### 2. Executar Diagnóstico Completo
```bash
./diagnostics-scripts.sh all
```

### 3. Diagnóstico Apenas Staging
```bash
./diagnostics-scripts.sh staging
```

### 4. Diagnóstico Apenas Prod
```bash
./diagnostics-scripts.sh prod
```

## Contextos Kubernetes

| Context | Cluster | Uso |
|---------|---------|-----|
| `arn:aws:eks:us-east-1:891377105802:cluster/k8s-platform-prod` | k8s-platform-prod | Prod |
| `k8s-platform-staging` | k8s-platform-prod (shared) | Staging |

## Incidentes P1 Ativos

- INC-001: vault-prod-0 Pending — ver `incident-vault-prod-p1.md`

## Contatos de Escalonamento

- AWS Account: 891377105802
- AWS Profile: k8s-platform-prod
- Região: us-east-1
- TF dir staging: `Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/environments/staging`
