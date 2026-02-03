# 📓 Marco 2 Fase 7 - Test Applications

| Campo          | Valor                                    |
|----------------|------------------------------------------|
| **Data**       | 2026-01-28                               |
| **Demanda**    | Validar stack end-to-end com aplicações de teste |
| **Impacto**    | Alto (Validação completa da plataforma)  |
| **Agentes**    | DevOps Team, QA                          |
| **Status**     | ✅ Concluído (HTTP-only, TLS pendente)   |
| **Duração**    | ~3 minutos (+ troubleshooting TLS)       |

---

## Contexto

Validação end-to-end da plataforma Kubernetes através do deploy de aplicações de teste (nginx e echo-server) com exposição via AWS Application Load Balancer.

---

## Objetivo

Validar integração completa do stack:
```
Ingress → ALB → Network Policies → Pods → Prometheus Metrics → Loki Logs
```

---

## Problema TLS Identificado

### Sintoma

ALBs não foram provisionados inicialmente devido a configuração incorreta de TLS com domínios fake (.local) sem DNS real.

### Causa Raiz

- Cert-Manager não conseguiu gerar certificados válidos para domínios `.local`
- ALB Controller bloqueou criação de HTTPS listeners
- Ingresses ficaram sem ADDRESS

### Solução Temporária

1. Removida TLS section de ambos Ingresses
2. Alterado `listen-ports` para HTTP-only `[{"HTTP": 80}]`
3. Removido annotation `alb.ingress.kubernetes.io/ssl-redirect`
4. ALBs provisionados com sucesso em HTTP-only mode

**Nota:** TLS será implementado posteriormente na Fase 7.1

---

## Recursos Criados

### Namespace

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: test-apps
  labels:
    name: test-apps
    monitoring: "true"
```

### Aplicação 1: NGINX Test

**4 manifests criados:**
1. **Deployment** (2 replicas)
   - Container: `nginx:alpine`
   - Sidecar: `nginx/nginx-prometheus-exporter:1.1.0`
   - Resources: 100m CPU / 128Mi RAM

2. **Service** (ClusterIP)
   - Port: 80 → targetPort 80
   - Selector: `app=nginx-test`

3. **ServiceMonitor** (Prometheus)
   - Endpoint: `:9113/metrics` (nginx-exporter sidecar)
   - Interval: 30s

4. **Ingress** (ALB)
   - Host: `nginx-test.example.com` (HTTP-only)
   - IngressClass: `alb`
   - Scheme: `internet-facing`

### Aplicação 2: Echo Server

**4 manifests criados:**
1. **Deployment** (2 replicas)
   - Container: `ealen/echo-server:latest`
   - Resources: 50m CPU / 64Mi RAM

2. **Service** (ClusterIP)
   - Port: 80 → targetPort 3000

3. **ServiceMonitor** (Prometheus)
   - Endpoint: `/metrics`
   - Interval: 30s

4. **Ingress** (ALB)
   - Host: `echo-server.example.com` (HTTP-only)
   - IngressClass: `alb`
   - Scheme: `internet-facing`

### Network Policy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-alb-and-prometheus
  namespace: test-apps
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    # Allow ALB (from kube-system)
    - from:
      - namespaceSelector:
          matchLabels:
            name: kube-system
    # Allow Prometheus scraping
    - from:
      - namespaceSelector:
          matchLabels:
            name: monitoring
      ports:
        - protocol: TCP
          port: 9113  # nginx-exporter
        - protocol: TCP
          port: 3000  # echo-server metrics
```

---

## Resultado Final

### Pods Status

```bash
kubectl get pods -n test-apps

NAME                           READY   STATUS    RESTARTS   AGE
nginx-test-7b8f5c9d6b-4xk2p    2/2     Running   0          3m12s
nginx-test-7b8f5c9d6b-8mn4t    2/2     Running   0          3m12s
echo-server-6c9d4f8b7d-5qw9x   1/1     Running   0          3m10s
echo-server-6c9d4f8b7d-9tn2k   1/1     Running   0          3m10s
```

**Total:** 4 pods Running (6 containers)

### ALBs Provisionados

**NGINX Test ALB:**
```
http://k8s-testapps-nginxtes-bf6521357f-267724084.us-east-1.elb.amazonaws.com
```
- Status: ✅ HTTP 200
- Response: NGINX default page

**Echo Server ALB:**
```
http://k8s-testapps-echoserv-d5229efc2b-1385371797.us-east-1.elb.amazonaws.com
```
- Status: ✅ HTTP 200
- Response: JSON com request headers/body

### Observabilidade

**Prometheus Metrics:**
```bash
# ServiceMonitors descobertos
kubectl get servicemonitor -n test-apps

NAME          AGE
nginx-test    3m45s
echo-server   3m42s
```

**Métricas NGINX Visíveis:**
- `nginx_connections_active`
- `nginx_http_requests_total`
- `nginx_up`

**Logs no Grafana Explore:**
```logql
{namespace="test-apps"}
```

✅ Fluent Bit coletando e enviando logs corretamente

---

## Problemas Resolvidos Durante Deploy

### 1. ImagePullBackOff - Echo Server

**Erro:** `echo-server:0.9.4` não existia

**Solução:** Corrigido para `ealen/echo-server:latest`

### 2. TLS Blocker

**Erro:** ALB Controller não criou ALB com domínios `.local`

**Solução:** Removido TLS, alterado para HTTP-only (temporário)

### 3. Network Policy

**Status:** Já configurada para permitir tráfego `kube-system → test-apps`

---

## Status Checklist

- [x] Namespace test-apps criado
- [x] 4 pods Running
- [x] 2 Services criados (ClusterIP)
- [x] 2 Ingresses criados (ingressClassName: alb)
- [x] 2 ALBs provisionados e Active
- [x] HTTP 200 responses de ambos ALBs
- [x] Network Policy permitindo tráfego
- [x] 2 ServiceMonitors criados
- [x] Métricas NGINX visíveis no Prometheus
- [x] Logs visíveis no Grafana
- [ ] ⚠️ TLS configurado (removido temporariamente - pendente Fase 7.1)

---

## Lições Aprendidas

### 🔒 TLS/DNS

| # | Lição | Impacto |
|---|-------|---------|
| 1 | **Domínios fake (.local, .internal) bloqueiam Let's Encrypt** - impossível validar certificados | 🔴 Crítico |
| 2 | ALB Controller requer domínio real OU remoção completa de TLS section | 🔴 Crítico |
| 3 | HTTP-only é solução viável para test applications não-públicas | 🟡 Médio |

### 🏗️ Arquitetura

| # | Lição | Impacto |
|---|-------|---------|
| 4 | Sidecar nginx-exporter expõe métricas sem modificar container principal | 🟡 Médio |
| 5 | ServiceMonitor discovery automático funciona com label `monitoring: "true"` no namespace | 🟢 Baixo |
| 6 | Network Policies devem permitir tráfego de kube-system para ALB funcionarem | 🔴 Crítico |

### ⚙️ Troubleshooting

| # | Lição | Impacto |
|---|-------|---------|
| 7 | ImagePullBackOff pode indicar tag inexistente - verificar Docker Hub primeiro | 🟡 Médio |
| 8 | Ingress sem ADDRESS indica problema com ALB Controller - verificar logs | 🟡 Médio |

---

## Métricas

| Métrica | Valor |
|---------|-------|
| Tempo de deploy | ~3 minutos |
| Pods criados | 4 (6 containers) |
| ALBs provisionados | 2 |
| ServiceMonitors | 2 |
| Network Policies | 1 |
| Métricas expostas | 3+ por app |

---

## Custo Adicional

| Item | Quantidade | Custo Mensal |
|------|------------|--------------|
| Application Load Balancer | 2 | 2 × $16.20 = **$32.40/mês** |
| EC2 (pods) | Incluído | $0 (roda em nodes existentes) |

**Total:** **$32.40/mês**

---

## Próximos Passos (Fase 7.1)

1. Analisar soluções TLS viáveis:
   - Route53 + Let's Encrypt DNS-01
   - AWS ACM (Amazon Certificate Manager)
   - Self-signed certificates
   - Wildcard certificate

2. Criar **ADR-008:** TLS Strategy for ALB Ingresses

3. Implementar solução TLS escolhida

4. Validar HTTPS funcionando

---

## Referências

- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [NGINX Prometheus Exporter](https://github.com/nginxinc/nginx-prometheus-exporter)
- [Cert-Manager Let's Encrypt](https://cert-manager.io/docs/configuration/acme/)
