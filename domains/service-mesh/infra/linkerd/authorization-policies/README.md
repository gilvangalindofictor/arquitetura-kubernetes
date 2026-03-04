# GAP-011: Linkerd AuthorizationPolicies — Guia de Uso

**Compliance**: BACEN BCB 85/2021 Art. 15 (segregacao de trafego por identidade)
**Versao Linkerd**: 2.16.x
**API Version**: `policy.linkerd.io/v1beta3`

---

## Como Funcionam as AuthorizationPolicies no Linkerd

O Linkerd implementa autorizacao baseada em **identidade SPIFFE** (SPIFFE ID = `spiffe://cluster.local/ns/<namespace>/sa/<serviceaccount>`).

### Hierarquia de recursos

```
MeshTLSAuthentication    →   Define QUEM pode conectar (identidade)
         +
AuthorizationPolicy      →   Define A QUEM e COMO (target + autenticacao required)
         +
Server (opcional)        →   Define QUAL porta/protocolo esta sendo protegida
```

### Fluxo de autorizacao

```
Pod A (SA: keycloak)           Pod B (SA: argocd-server)
    |                               |
    | SPIFFE ID:                    | SPIFFE ID:
    | spiffe://cluster.local/       | spiffe://cluster.local/
    | ns/staging-platform/          | ns/staging-platform/
    | sa/keycloak                   | sa/argocd-server
    |                               |
    |---- mTLS request ------------>|
                                    |
                          AuthorizationPolicy verifica:
                          1. Ha certificado mTLS valido? (MeshTLS)
                          2. A identidade SPIFFE esta autorizada?
                          3. O target (Server/Service) esta configurado?
                                    |
                          ALLOW ou DENY
```

---

## Padroes de Policy

### Padrao 1: Deny-All (baseline seguro)

Recomendado como ponto de partida. Todos os servicos de um namespace so aceitam conexoes de identidades autenticadas (nao necessariamente especificas).

```
MeshTLSAuthentication (identities: ["*"])  →  AuthorizationPolicy (target: Namespace)
```

Ver: `policy-deny-all.yaml`

### Padrao 2: Identity-Based (granular)

Permite apenas uma identidade especifica conectar a um servico especifico.

```
MeshTLSAuthentication (identidades especificas)  →  AuthorizationPolicy (target: Service)
```

Ver: `policy-keycloak-to-argocd.yaml`, `policy-gitlab-to-harbor.yaml`

### Padrao 3: Prometheus Scrape (observabilidade)

Permite que o Prometheus raspe metricas de todos os pods sem restricao de namespace.

```
MeshTLSAuthentication (SA: prometheus)  →  AuthorizationPolicy (target: Port 9090/8080)
```

Ver: `policy-prometheus-scrape.yaml`

---

## Como Aplicar

```bash
# Aplicar todas as policies de uma vez
kubectl apply -f domains/service-mesh/infra/linkerd/authorization-policies/

# Verificar policies criadas
kubectl get authorizationpolicies -A
kubectl get meshtlsauthentications -A

# Testar conectividade apos policy
linkerd viz tap deploy/keycloak -n staging-platform \
  --to deploy/argocd-server \
  --namespace staging-platform
# Esperado: linhas com [tls] no output

# Verificar bloqueios (conexoes nao autorizadas apareceram como erro)
kubectl logs -n linkerd deploy/linkerd-destination --tail=50 | grep "unauthorized"
```

---

## Ordem de Aplicacao Recomendada

1. Garantir que namespaces tem proxy injetado (Fase 1/2/3 do rollout-strategy.md)
2. Aplicar `policy-deny-all.yaml` no namespace alvo
3. Testar que conexoes legitimas ainda funcionam (sem o deny-all quebrar nada)
4. Aplicar policies granulares conforme necessidade
5. Monitorar `linkerd viz stat` por 24h

---

## Troubleshooting

### Conexao bloqueada inesperadamente

```bash
# Ver logs do proxy no pod alvo
kubectl logs <pod> -n <namespace> -c linkerd-proxy | grep -i "deny\|unauthorized\|error"

# Ver eventos de policy no control plane
kubectl logs -n linkerd deploy/linkerd-destination | grep "policy"

# Verificar identidade SPIFFE do pod chamador
kubectl exec <pod-chamador> -c linkerd-proxy -- \
  wget -qO- http://localhost:4191/metrics | grep "identity"
```

### Policy nao sendo aplicada

```bash
# Verificar se CRDs estao instalados
kubectl get crd | grep policy.linkerd.io
# Esperado: authorizationpolicies, meshtlsauthentications, servers, serverauthorizations

# Verificar se policy foi criada no namespace correto
kubectl describe authorizationpolicy <nome> -n <namespace>
```

---

## Mapeamento BACEN BCB 85/2021

| Artigo | Requisito | Implementacao |
|--------|-----------|---------------|
| Art. 15 SS I | Segregacao de trafego por identidade | `AuthorizationPolicy` com `MeshTLSAuthentication` |
| Art. 6 SS V | Autenticacao mutual | `MeshTLSAuthentication` exige certificado mTLS valido |
| Art. 11 SS II | Rastreabilidade de acesso | `linkerd viz tap` + logs do proxy |

---

## Referencias

- [AuthorizationPolicy API Reference](https://linkerd.io/2.16/reference/authorization-policy/)
- [MeshTLSAuthentication](https://linkerd.io/2.16/reference/authorization-policy/#meshtlsauthentication)
- [Server API](https://linkerd.io/2.16/reference/authorization-policy/#server)
- [SPIFFE Identity](https://linkerd.io/2.16/features/automatic-mtls/)
