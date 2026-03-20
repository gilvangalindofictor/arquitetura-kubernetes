# Strategies History — Platform Engineering

Registro consolidado de padroes, estrategias e licoes aprendidas ao longo das sessoes de implementacao da plataforma.

Formato de cada entrada:

- **Tipo**: categoria do trabalho
- **Padrao**: sequencia de passos que funcionou
- **Licoes aprendidas**: o que foi descoberto, o que nao funciona e por que

---

## 2026-03-19 — ECR Pull-Through Cache: Registry Hibrido

**Tipo:** Registry Cache Architecture

**Contexto:** Docker Hub rate limit (429) afetando 30 imagens / 48 pods em ImagePullBackOff. Mesa tecnica com 3 agentes (AWS, Security, SRE) convocada para avaliar arquitetura de registry. Harbor-only rejeitado por 3 bloqueadores arquiteturais. Modelo hibrido aceito com ECR Public Gallery como upstream (sem Docker Hub).

**Padrao que funcionou:**

```text
Mesa Tecnica (3 agentes) → Harbor-only REJEITADO → Modelo Hibrido → ECR Public (sem Docker Hub) → Modulo TF → Kyverno safety net
```

1. Avaliar Harbor-only com 3 agentes especialistas (AWS, Security, SRE)
2. Identificar bloqueadores arquiteturais (DNS, bootstrap, SPOF)
3. Decidir modelo hibrido com ECR Public (sem Docker Hub)
4. Criar modulo TF parametrizado com 4 upstreams sem credenciais
5. Rewrite gradual de imagens (menor risco primeiro)
6. Kyverno MutatingPolicy como safety net

**Artefatos:** modulo `modules/ecr-pull-through-cache/`, ADR-0XX, ADR-0YY

**Referencias:**

- logbook: `2026-03-19-ecr-pull-through-cache.md`

---

### Licao 18 — ECR Public Gallery elimina dependencia de Docker Hub

**Problema:** ECR Pull-Through Cache para Docker Hub requer PAT (Personal Access Token) — bloqueador operacional.

**Causa raiz:** Docker Hub exige autenticacao para pull-through cache rules. Gerar e manter PAT valido e overhead operacional (expiracao, rotacao, Secrets Manager).

**Solucao:** Usar `public.ecr.aws` como upstream. AWS mantem mirror de todas Docker Official Library images. Vendors (HashiCorp, Grafana, Bitnami, etc) publicam diretamente no ECR Public. Zero credenciais, zero rate limit.

**Regra geral:** Sempre preferir ECR Public Gallery sobre Docker Hub para pull-through cache. Zero credenciais, zero rate limit. Criar 4 rules sem credenciais: ecr-public, k8s (registry.k8s.io), quay, ghcr.

---

### Licao 19 — Harbor Proxy Cache: 3 bloqueadores arquiteturais para node-level mirror

**Problema:** Tentativa de usar Harbor como unico registry (substituir ECR) para resolver Docker Hub rate limit.

**Causa raiz:** 3 bloqueadores intransponiveis:

1. containerd nao resolve DNS do cluster (`svc.cluster.local`) — roda no host, usa DNS do VPC
2. Deadlock circular no bootstrap: Harbor precisa de imagens para subir, mas E a fonte de imagens
3. SPOF: registry/jobservice single-replica sem PDB — outage do Harbor = outage de todos os pulls

**Solucao:** Modelo hibrido — Harbor para custom images (builds internos, CI/CD artifacts), ECR Pull-Through Cache para imagens publicas (Docker Official Library, vendors).

**Regra geral:** Harbor serve pods (via CoreDNS). ECR serve nodes (via DNS AWS). Nunca misturar papeis. Para node-level registry mirror, usar APENAS registries acessiveis via DNS do host: ECR, registries publicos, ou registries com IP fixo.

**Anti-pattern:** Configurar Harbor Proxy Cache como `mirror` no containerd config do node. O node nao resolve DNS do CoreDNS do cluster.

---

## 2026-03-05 — K8s Workload Deploy: Backstage IDP

**Tipo:** K8s Workload Deploy (Backstage IDP)

**Contexto:** Primeiro deploy do Backstage como Internal Developer Platform no cluster `k8s-platform-prod` (EKS us-east-1, conta 891377105802). Namespace padrao `staging-platform-*`, service mesh Linkerd ativo, Kyverno como policy engine.

**Padrao que funcionou:**

```text
Namespace → RBAC → Kyverno Exception → Vault Bootstrap → ExternalSecret → Helm
```

1. Patch na ClusterPolicy Kyverno para adicionar o novo namespace na exclusion list
2. Criar namespace com annotation Linkerd inject
3. Criar ClusterRole + ClusterRoleBinding com escopo completo (inclui CRDs de ArgoCD e ESO)
4. Criar PDB (minAvailable=1) antes do deploy
5. Criar PolicyException para o namespace (Linkerd proxy-init precisa de NET_ADMIN/NET_RAW)
6. Executar bootstrap Vault com token admin (script pronto)
7. Aplicar ExternalSecret apontando para Vault KV v2
8. Deploy Helm com `--dry-run` antes do deploy real

**Referencias:**

- logbook: `2026-03-05-backstage-deploy.md`
- ADR-055
- Scripts: `docs/plan/backstage/bootstrap-vault-setup.sh`, `docs/plan/backstage/bootstrap-credentials.sh`

---

### Licao 1 — Kyverno validate-namespace-naming pode bloquear nomes validos

**Problema:** A ClusterPolicy `validate-namespace-naming` bloqueava a criacao do namespace `staging-platform-backstage` mesmo sendo um nome valido e conforme ao padrao `staging-platform-*` definido pelo ADR-048.

**Causa raiz:** A policy tinha uma lista estatica de namespaces permitidos. Novos namespaces validos nao eram aceitos automaticamente — a lista precisava ser atualizada manualmente a cada novo namespace de plataforma.

**Solucao aplicada:** Patch na ClusterPolicy para adicionar `staging-platform-backstage` a lista de exclusoes (campo `exclude`). Operacao cirurgica, sem impacto em outros namespaces.

**Regra geral:** Ao criar qualquer namespace `staging-platform-*` novo, verificar primeiro se a ClusterPolicy `validate-namespace-naming` tem uma exclusion list e adicionar o namespace antes de tentar criar o namespace.

**Comando de diagnostico:**

```bash
kubectl get clusterpolicy validate-namespace-naming -o yaml | grep -A 20 exclude
```

---

### Licao 2 — Vault sem root token acessivel: usar bootstrap script com comandos prontos

**Problema:** O root token do Vault nao estava armazenado (boa pratica de seguranca). O agente automatizado nao consegue executar comandos privilegiados no Vault sem um token admin valido. O deploy ficou bloqueado no Bloco B.

**Causa raiz:** Vault em producao nao deve ter root token persistente. Tokens admin sao obtidos pontualmente pelo operador humano via metodo seguro da organizacao.

**Solucao aplicada:** Criar um script `bootstrap-vault-setup.sh` com todos os comandos necessarios ja prontos, documentados e sequenciados. O admin executa o script uma unica vez com seu token. O script e idempotente (verifica antes de criar).

**Padrao recomendado para futuros deploys:**

1. Agente cria o script de bootstrap com todos os comandos Vault
2. Agente documenta no logbook o que o script faz
3. Admin executa com seu token: `VAULT_TOKEN=<token> ./bootstrap-vault-setup.sh`
4. Agente verifica resultado via `kubectl get externalsecret` (sem precisar de token Vault)

**Anti-pattern:** Tentar armazenar ou recuperar o root token automaticamente. Nunca fazer isso.

---

### Licao 3 — Sessao AWS SSO expira durante deploys longos: protocolo auto-renewal funciona

**Problema:** Sessao AWS SSO expirou durante a execucao do deploy do Backstage (sessao de varias horas). Comandos `kubectl`, `helm` e `aws` passaram a falhar com erros de autenticacao.

**Causa raiz:** Tokens AWS SSO tem TTL limitado (tipicamente 8h, configuravel). Deploys complexos com multiplos blocos podem ultrapassar esse limite.

**Solucao aplicada:** Protocolo AML de auto-renewal ativado. Polling detectou o login renovado em 75 segundos. Execucao retomada sem perda de estado.

**Boas praticas para evitar interrupcao:**

- Iniciar sessoes longas de deploy com `aws sso login` fresco
- Usar `aws sts get-caller-identity` periodicamente para verificar validade da sessao
- Manter o protocolo AML ativo em sessoes de deploy estimadas em mais de 4 horas

**Tempo de recuperacao observado:** 75 segundos (login detectado pelo polling).

---

## 2026-02-18 — SSO: SonarQube SAML + Keycloak

**Tipo:** SSO Integration (SAML 2.0)

**Padrao que funcionou:**

```text
SP cert/key (PKCS8) → Vault KV → ESO template secret.properties → Helm sonarSecretProperties → Keycloak SAML client
```

**Licoes aprendidas:**

- `sonarSecretKey` e para chave AES de decrypt do DB, NAO para injetar sonar.properties
- Key do K8s Secret deve ser `secret.properties`, nao `sonar-secret.txt`
- `sonar.core.serverBaseURL` deve usar hostname externo (`*.staging.internal`), nunca `localhost`
- `saml.client.signature=true` no Keycloak requer upload do SP cert
- GitLab OAuth direto no SonarQube 10.3 Community nao funciona (plugin ausente) — usar federacao via Keycloak

**Referencias:**

- logbook: `2026-02-18-sonarqube-saml-fix.md`
- strategies: `strategies-saml-sso.md`
- DEC-062

---

## 2026-02-13 — SSO: GitLab OIDC via Keycloak

**Tipo:** SSO Integration (OIDC)

**Padrao que funcionou:**

```text
Keycloak realm platform → Client confidential + PKCE → GitLab OmniAuth OIDC → Vault KV → ESO
```

**Licoes aprendidas:**

- Qualquer URL que o browser precisa resolver DEVE usar hostname externo (`*.staging.internal`), nunca `svc.cluster.local` nem `localhost`
- PKCE (S256) obrigatorio em Keycloak 26 para clients confidenciais com redirect via browser
- Validar `/.well-known/openid-configuration` antes de qualquer integracao OIDC

**Referencias:**

- logbook: `2026-02-13-sso-e2e-conformidade-keycloak.md`
- strategies: `strategies-gitlab-sso.md`

---

## 2026-03-12 — FinOps Code Review: Exame IaC + GAPs + Apply 14:39 BRT

**Tipo:** FinOps — Exame de Código + Apply parcial + Health Status

**Exame realizado:** Análise completa do código IaC para verificar status dos itens P0/P1 FinOps codificados na sessão anterior (2026-03-11).

**Status P0/P1 confirmados no código:**

- P0-001: EKS log_types codificado (eks/main.tf) — aguardando apply
- P0-004: RabbitMQ NLB→ClusterIP codificado (rabbitmq/main.tf)
- P1-001: Lambda suspend_cluster_autoscaler() codificado (lambda_stop.py + variables.tf)
- ALB 4→2: codificado em staging/main.tf
- NAT 2→1: codificado no módulo NAT

**Total savings confirmados no código: R$ 61.638/ano (99.4% da meta R$ 62K)**

**5 GAPs detectados (estado inicial):**

- GAP-2 (ALTO): excluded_node_groups = ["system","critical"] — RESOLVIDO no IaC
- GAP-1 (MÉDIO): suspend_autoscaler_on_stop não explícito — RESOLVIDO no IaC
- GAP-3 (MÉDIO): fct-0001/fct-0002 lifecycle rules — FORA DE ESCOPO
- GAP-4 (BAIXO): gp2→gp3 sem TF — drift latente
- GAP-5 (MÉDIO): snapshots migração — FECHADO como falso positivo

**Validação AWS ~14:00 BRT:**

- Lambda OK: STOP 2026-03-11T23:00 UTC SUCCESS + START 2026-03-12T10:30 UTC SUCCESS. Zero erros em 7 dias (131+100 eventos).
- GAP-5 FECHADO — falso positivo: 173 snapshots reais (163 EBS CSI/DLM + 10 Velero), 0 órfãos verdadeiros.
- GAP-1 e GAP-2 RESOLVIDOS no IaC: `excluded_node_groups=["system"]` + `suspend_autoscaler_on_stop=true` codificados. Aguardando apply.
- NLB RabbitMQ ainda ativo (USD 16,20/mês) — eliminado no apply de 14:39.

**Apply 2026-03-12 14:39 BRT — CONFIRMADO:**

- Lambda finops_stop: REDEPLOY (suspend_cluster_autoscaler() ativo em produção)
- Lambda finops_start: REDEPLOY
- RabbitMQ service: LoadBalancer → ClusterIP (NLB eliminado, -$16.20/mês)

**Custos diários 01-11/03 (Cost Explorer coletado ~15:00 BRT):**

- Acumulado: $480.28 (11 dias)
- Weekday avg (excl 03-11): $39.97/dia | Weekend avg (excl anomalia): $39.40/dia
- 03-11: $30.42 — queda de $9.55/dia confirmada pós ALB+NAT
- Forecast AWS CE Marco: $1.731/mes (+115% vs budget $807)

**Health Status ~15:00 BRT:**

- Nodes: 12/12 Ready (EKS v1.34.2) | PVCs: todos Bound
- P0: linkerd-trust-anchor secret AUSENTE → cascade CrashLoop GitLab+Linkerd (36-103 restarts)
- P1: VaultDown + RDSPostgreSQLPlatformWideOutage alerts firing (cascata Linkerd)
- P2: KubeJobFailed x4, linkerd-cni Pending, promtail Pending x3
- 58 alertas firing: 11 CRITICAL + 42 WARNING + 5 INFO

**P0 Recovery ~17:00-19:00 BRT:**

- linkerd-trust-anchor recreado com cert correto (trailing newline preservado via `--from-file`)
- SHA256 bug: `echo "$CERT"` stripa newline → hash errado. Fix: extrair de TF state via `--from-file`
- System ASG Max=4→5 (identity pod Unschedulable, 17/17 pods/nó). TF já tem max_size=6 — dentro do range
- Linkerd control plane: destination 4/4, identity 2/2, proxy-injector 2/2 ✅
- VaultDown alert → FALSO POSITIVO (scrape 403 sem token). Fix: telemetry `unauthenticated_metrics_access=true` adicionado em vault/values.yaml.tpl
- RDS alert → FALSO POSITIVO (cascata Linkerd). RDS AVAILABLE confirmado
- Keycloak backup script: 4x `/auth/` removidos (KC 17+ eliminou prefixo em todos os endpoints)

**IaC Codificada nesta Sessão (apply pendente — SSO expirado):**

- `vault/values.yaml.tpl`: telemetry stanza com `unauthenticated_metrics_access=true`
- `keycloak-backup.tf`: endpoints sem prefixo `/auth/`
- `node-groups.tf`: max_size=6 já existia desde 2026-03-05 ✅ (sem mudança necessária)

**P0 Recovery ~17:00-19:00 BRT — CONCLUÍDO:**

- linkerd-trust-anchor recriado com cert correto (SHA256 trailing newline bug resolvido via `--from-file`)
- CNI deadlock fix: `skip-outbound-ports=8080` em destination + proxy-injector
- System ASG Max=4→5 (identity Unschedulable) — module.linkerd apply confirmado (1 changed)
- Vault: `unauthenticated_metrics_access=true` — module.vault_staging apply confirmado (1 changed)
- Ambos os módulos: zero drift pós-apply confirmado
- Root token Vault revogado pós-apply
- GitLab 11/11 pods 2/2 ou 3/3 Running (recuperado da cascata Linkerd)
- Keycloak backup: 4x `/auth/` removidos nos endpoints (KC 17+ eliminou prefixo)

**Referências:**

- logbook: `2026-03-12-finops-code-review.md`
- logbook: `2026-03-12-linkerd-p0-recovery.md`
- finops: `docs/finops/finops-status-2026-03-12.md`

---

### Licao 4 — SHA256 trailing newline bug: echo stripa newline, --from-file preserva

**Problema:** Ao recriar o secret `linkerd-trust-anchor`, o hash SHA256 do certificado calculado via `echo "$CERT" | sha256sum` não correspondia ao hash esperado pelo Linkerd. Resultado: trust anchor inválido, control plane inteiro em CrashLoop.

**Causa raiz:** O comando `echo "$CERT"` stripa o trailing newline do conteúdo da variável antes de calcular o hash. Como o certificado PEM termina com `\n`, o hash resultante é diferente do hash do arquivo original. O Linkerd valida o hash do cert no momento de inject do proxy — qualquer divergência causa `InvalidContentType` / `CertificateInvalid`.

**Solucao aplicada:**

```bash
# ERRADO — stripa trailing newline:
CERT=$(cat trust-anchor.crt)
echo "$CERT" | sha256sum  # hash ERRADO

# CORRETO — preserva trailing newline:
kubectl create secret generic linkerd-trust-anchor \
  --from-file=ca.crt=trust-anchor.crt \  # --from-file preserva o conteudo exato
  --namespace=linkerd --dry-run=client -o yaml | kubectl apply -f -
```

**Regra geral:** Sempre usar `--from-file=<key>=<arquivo>` ao criar secrets com certificados. Nunca usar variáveis shell interpoladas via `echo` para conteúdo binário ou com trailing newlines significativos.

**Diagnóstico:** Comparar hash no secret com hash do arquivo original:

```bash
kubectl get secret linkerd-trust-anchor -n linkerd -o jsonpath='{.data.ca\.crt}' | base64 -d | sha256sum
sha256sum trust-anchor.crt
# Se diferentes → trailing newline bug
```

---

### Licao 5 — CNI deadlock Linkerd: porta 8080 (identity headless) interceptada pelo próprio proxy

**Problema:** Após o Linkerd CNI ser habilitado (modo iptables), o pod `destination` e o `proxy-injector` entravam em loop de erro `InvalidContentType` ao tentar conectar no `identity` service via a porta headless 8080. O erro era: outbound traffic na porta 8080 interceptado pelo próprio proxy Linkerd antes de chegar ao identity service.

**Causa raiz:** Com CNI iptables, todo tráfego outbound do pod é redirecionado pelo proxy Linkerd antes de sair. A porta 8080 é usada pelo `identity` service como porta headless para comunicação interna do control plane. O proxy do `destination` tentava conectar no `identity:8080` — o iptables redirecionava para o próprio proxy (loopback), que não sabia processar o protocolo gRPC interno → `InvalidContentType` em loop.

**Solucao aplicada:**

```yaml
# Em destination deployment e proxy-injector deployment:
annotations:
  config.linkerd.io/skip-outbound-ports: "8080"
```

Isso instrui o CNI a não interceptar tráfego outbound na porta 8080, permitindo que a comunicação interna do control plane chegue diretamente ao identity service sem passar pelo proxy.

**Regra geral:** Ao usar Linkerd CNI (não init container), verificar se os componentes do control plane têm `skip-outbound-ports` configurado para portas de comunicação interna. Especialmente crítico para: identity (8080), destination (8086), proxy-injector (8443).

**Diagnóstico:**

```bash
# Ver se há InvalidContentType loops:
kubectl logs -n linkerd deployment/linkerd-destination -c linkerd-proxy | grep InvalidContent
# Ver se skip-outbound-ports está configurado:
kubectl get deploy -n linkerd linkerd-destination -o jsonpath='{.spec.template.metadata.annotations}'
```

---

### Licao 6 — Keycloak 26: senha admin so é definida no primeiro boot — rotacao exige argon2id no PostgreSQL

**Problema:** Após rotacionar o secret K8s `keycloak-admin-credentials` (V-006), o login no Keycloak continuava falhando com credenciais inválidas. O pod não reiniciou e continuou usando a senha antiga.

**Causa raiz:** O Keycloak 26 (modo quarkus) define a senha do admin **apenas no primeiro boot** via variável de ambiente `KC_BOOTSTRAP_ADMIN_PASSWORD`. Se o pod já está Running e o secret é alterado, o Keycloak ignora completamente a nova variável — a senha permanece no banco PostgreSQL como hash argon2id.

**Solução aplicada:**

```sql
-- Conectar no RDS PostgreSQL, database keycloak
-- Gerar hash argon2id da nova senha (Python 3):
python3 -c "
import argon2
ph = argon2.PasswordHasher(time_cost=3, memory_cost=65536, parallelism=1, hash_len=32, salt_len=16)
print(ph.hash('NOVA_SENHA'))
"

-- Atualizar diretamente no banco:
UPDATE credential SET secret_data = '{"value":"<hash_argon2id>","salt":"","additionalParameters":{}}',
  credential_data = '{"hashIterations":3,"algorithm":"argon2","additionalParameters":{"hashLength":["32"],"memory":["65536"],"type":["id"],"version":["19"],"parallelism":["1"]}}'
WHERE type = 'password' AND user_id = (
  SELECT id FROM user_entity WHERE username = 'admin' AND realm_id = 'master'
);
```

**Regra geral:** Para rotacionar a senha admin do Keycloak 26 em produção: (1) gerar hash argon2id em Python com `argon2-cffi`; (2) atualizar a tabela `credential` no PostgreSQL; (3) testar login imediatamente sem reiniciar o pod.

**Anti-pattern:** Deletar/recriar o pod esperando que KC 26 leia o novo secret. Só funciona em primeiro boot.

---

### Licao 7 — AlertManager inhibitRules para componentes EKS managed (falsos positivos permanentes)

**Problema:** Alertas `KubeSchedulerDown` e `KubeControllerManagerDown` disparam constantemente em clusters EKS porque o kube-scheduler e kube-controller-manager são gerenciados pela AWS no control plane (não expostos como pods no data plane). O Prometheus não consegue scrapeá-los.

**Causa raiz:** EKS managed control plane — scheduler e controller-manager rodam em infraestrutura AWS interna. Os ServiceMonitors tentam scrape em targets que nunca existirão → alerta permanente.

**Solução aplicada (AlertmanagerConfig CRD):**

```yaml
inhibitRules:
  - sourceMatch:
      - name: alertname
        value: Watchdog
        matchType: "="
    targetMatch:
      - name: alertname
        value: KubeSchedulerDown
        matchType: "=~"
    equal: []
  - sourceMatch:
      - name: alertname
        value: Watchdog
        matchType: "="
    targetMatch:
      - name: alertname
        value: KubeControllerManagerDown
        matchType: "=~"
    equal: []
```

**Rationale:** `Watchdog` está sempre firing em clusters saudáveis — serve como fonte de inibição permanente. `equal: []` garante que a supressão seja global (sem matching por labels adicionais).

**Regra geral:** Em clusters EKS, sempre adicionar inhibitRules para `KubeSchedulerDown` e `KubeControllerManagerDown` usando `Watchdog` como sourceMatch. Codificar no AlertmanagerConfig CRD (não no values.yaml do kube-prometheus-stack, que pode ser sobrescrito por TF apply).

---

### Licao 8 — Vault generate-root via recovery keys: processo completo para obter root token temporário

**Problema:** Para executar `terraform apply` no módulo vault (que requer root token como variável), o root token já havia sido revogado (boa prática). O processo de regeneração via recovery keys não era conhecido.

**Causa raiz:** Vault HA com KMS auto-unseal usa recovery keys (não unseal keys). O root token pode ser gerado via `generate-root` endpoint usando 3 das 5 recovery keys (threshold 3).

**Processo:**

```bash
# 1. Iniciar generate-root
curl -s -X PUT localhost:8200/v1/sys/generate-root/attempt \
  -d '{"pgp_key": ""}' | jq -r '.otp'  # Guardar OTP

# 2. Submeter 3 recovery keys (do /tmp/vault-init.json)
for key in KEY1 KEY2 KEY3; do
  curl -s -X PUT localhost:8200/v1/sys/generate-root/update \
    -d "{\"key\": \"$key\", \"nonce\": \"$NONCE\"}"
done

# 3. Pegar encoded_token e fazer XOR com OTP
python3 -c "
import base64
encoded = base64.b64decode('ENCODED_TOKEN')
otp = base64.b64decode('OTP_BASE64')
root = bytes(a ^ b for a, b in zip(encoded, otp))
print(base64.b64encode(root).decode())
"

# 4. Usar root token — e REVOGAR imediatamente após apply
vault token revoke -self
```

**Regra geral:** Manter `/tmp/vault-init.json` (ou equivalente seguro) com as 5 recovery keys. Nunca armazenar o root token — sempre gerar pontualmente e revogar após uso. Port-forward obrigatório para `localhost:8200` antes de qualquer operação Vault via TF.

---

## 2026-03-19 — Prod Readiness: Vault HA + Keycloak HA + Docker Hub Rate Limit

**Tipo:** Plataforma — Deploy HA + Mesa Técnica Docker Hub

**Contexto:** Sessão de produção readiness com 3 fases executadas. Vault HA 3/3 + Keycloak HA 2/2 + ArgoCD 10/10 + Harbor 9/9 + SonarQube 1/1 deployados. Mesa técnica convocada para resolver Docker Hub rate limit (429) afetando 30 imagens / 48 pods em ImagePullBackOff.

**GAPs novos detectados:**

- GAP-SEC-REGISTRY-01: Harbor Proxy Cache nao funciona como registry mirror para kubelet/containerd
- GAP-SEC-REGISTRY-02: Docker Hub rate limit (429) — 30 imagens afetadas
- GAP-SEC-REGISTRY-03: ECR Pull-Through Cache como solucao permanente
- GAP-SEC-REGISTRY-04: 48 pods em ImagePullBackOff

**Fase 4 — Observabilidade (2026-03-19):**

- kube-prometheus-stack prod 5/5 Ready (Prometheus, Grafana, Alertmanager, Operator, KSM)
- Loki prod 10/10 Ready (S3 backend k8s-platform-loki-prod-891377105802, IRSA LokiS3Role)
- Tempo prod 12/12 Ready (S3 backend k8s-platform-tempo-prod-891377105802, IRSA TempoS3Role)
- OTel Collector prod 2/2 Ready
- Total: 29/29 core pods + 6 loki-canary Pending (DaemonSet nodeAffinity, non-blocking)
- Node-exporter desabilitado em prod (hostNetwork conflito com staging)
- ECR Pull-Through Cache: regra criada, credenciais Docker Hub invalidas (pendente PAT)

**Commits:** 3a5912b, 0e51582, b46c064 + pendente

**Pendentes:** TF state imports, ECR Pull-Through Cache PAT Docker Hub, 6 loki-canary Pending

**Referencias:**

- logbook: sessao 2026-03-19

---

### Licao 9 — Harbor Proxy Cache NAO funciona como registry mirror para kubelet/containerd

**Problema:** Tentativa de usar Harbor Proxy Cache como registry mirror para resolver Docker Hub rate limit (429). Pods continuaram com ImagePullBackOff mesmo com o proxy configurado.

**Causa raiz:** containerd/kubelet roda no host (node EC2), fora do pod network do cluster. O Harbor Proxy Cache é acessível via DNS do CoreDNS (dentro do cluster), mas o containerd usa o DNS do host (/etc/resolv.conf do node). O node nao resolve nomes de servicos internos do Kubernetes (e.g., `harbor-core.harbor-system.svc.cluster.local`).

**Solucao permanente:** ECR Pull-Through Cache — registry AWS nativo acessivel via endpoint regional, sem dependencia de DNS de cluster. containerd no node resolve `891377105802.dkr.ecr.us-east-1.amazonaws.com` normalmente via DNS publico/VPC.

**Regra geral:** Para substituir registry mirrors em nivel de node (containerd/kubelet), usar APENAS registries acessiveis via DNS do host: ECR, registries publicos, ou registries com IP fixo. Harbor Proxy Cache so serve para pulls feitos de dentro de pods (via CoreDNS).

**Anti-pattern:** Configurar Harbor Proxy Cache como `mirror` no containerd config do node. O node nao resolve DNS do CoreDNS do cluster.

---

### Licao 10 — Docker Hub rate limit (429) afeta pulls em escala: ECR Pull-Through Cache como solucao

**Problema:** 30 imagens Docker Hub atingiram rate limit (429 Too Many Requests) simultaneamente, causando ImagePullBackOff em 48 pods. Cluster ficou parcialmente degradado.

**Causa raiz:** Docker Hub impoe limite de 100 pulls/6h para IPs anonimos e 200 pulls/6h para contas free. Clusters com muitos pods fazendo pull simultaneo (scale-up, node replacement, rollout) esgotam o limite rapidamente via NAT Gateway IP unico.

**Solucao:** ECR Pull-Through Cache — AWS gerencia cache local das imagens Docker Hub na mesma regiao. Pulls subsequentes vem do ECR (sem rate limit Docker Hub). Configuracao via `aws ecr create-pull-through-cache-rule`.

**Regra geral:** Todo cluster EKS em producao deve usar ECR Pull-Through Cache para Docker Hub. Nao depender de pulls diretos ao Docker Hub — o rate limit e inevitavel em escala.

---

### Licao 11 — Modulos TF com providers internos sao incompativeis com depends_on

**Problema:** `terraform plan` falhava com erro ao usar `depends_on` entre modulos que declaram providers internos (ex: vault-config, keycloak-clients).

**Causa raiz:** Terraform exige que modulos referenciados em `depends_on` NAO possuam `configuration_aliases` ou providers internos com config dinamica. Quando um modulo define providers que dependem de outputs de outros modulos, o Terraform nao consegue resolver a ordem de avaliacao — resulta em ciclo ou erro de validacao.

**Solucao aplicada:** Remover `depends_on` e usar data sources ou `terraform_remote_state` para criar dependencias implicitas. Alternativamente, separar em applies distintos (ex: `terraform apply -target=module.vault` seguido de `terraform apply -target=module.vault_config`).

**Regra geral:** Nunca usar `depends_on` com modulos que declaram `required_providers` com `configuration_aliases` ou providers customizados. Usar dependencias implicitas via references ou applies separados.

---

### Licao 12 — AWS SSO cached credentials em ~/.aws/credentials tem prioridade sobre SSO tokens

**Problema:** Terraform falhava com `ExpiredToken` mesmo apos `aws sso login` bem-sucedido. O `aws sts get-caller-identity` funcionava, mas o Terraform nao.

**Causa raiz:** O arquivo `~/.aws/credentials` continha credenciais cacheadas (access key + secret key + session token) de uma sessao SSO anterior expirada. O provider AWS do Terraform lê `~/.aws/credentials` com PRIORIDADE sobre o cache SSO (`~/.aws/sso/cache/`). Como as credenciais no credentials file estavam expiradas, o TF falhava — mesmo com um SSO token valido disponivel.

**Solucao aplicada:**

```bash
# Remover credenciais cacheadas expiradas:
rm ~/.aws/credentials
# OU remover apenas a secao do profile:
sed -i '/\[k8s-platform-staging\]/,/^\[/d' ~/.aws/credentials
# Depois: aws sso login --profile k8s-platform-staging
```

**Regra geral:** Antes de qualquer sessao Terraform com AWS SSO, verificar se `~/.aws/credentials` nao contem credenciais stale do mesmo profile. Se existir, deletar o arquivo ou a secao correspondente.

**Diagnostico:**

```bash
# Verificar se ha credentials file com tokens expirados:
cat ~/.aws/credentials | grep -A3 "\[k8s-platform"
# Se existir session_token → provavelmente stale → deletar
```

---

### Licao 13 — Vault Helm chart cria ClusterRoles cluster-scoped: segunda instancia requer fullnameOverride

**Problema:** Deploy de segunda instancia do Vault (ex: para DR ou ambiente separado) falhava com erro de recurso duplicado em ClusterRole e ClusterRoleBinding.

**Causa raiz:** O Helm chart do Vault cria ClusterRoles e ClusterRoleBindings com nomes fixos baseados no release name. Como sao cluster-scoped (sem namespace), uma segunda instancia com nome default colide com a primeira.

**Solucao aplicada:**

```yaml
# values.yaml da segunda instancia:
fullnameOverride: "vault-dr"  # Garante nomes unicos para ClusterRole/CRB
injector:
  enabled: false  # Desabilitar injector se ja existe um ativo (cluster-scoped)
```

**Regra geral:** Ao deployar multiplas instancias do Vault no mesmo cluster: (1) usar `fullnameOverride` unico; (2) desabilitar o injector na segunda instancia (injector e cluster-scoped, so pode ter um ativo).

---

### Licao 14 — ESO e cluster-wide operator: nao instalar segunda instancia, criar novo ClusterSecretStore

**Problema:** Tentativa de instalar segunda instancia do External Secrets Operator (ESO) para um novo Vault resultou em conflitos de CRDs e webhook duplicado.

**Causa raiz:** ESO instala CRDs e webhooks cluster-scoped. Uma segunda instancia tenta registrar os mesmos CRDs e webhooks, causando conflito. O ESO foi desenhado para ser singleton no cluster.

**Solucao aplicada:** Nao instalar segundo ESO. Criar apenas um novo `ClusterSecretStore` apontando para o segundo Vault backend:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-dr-backend
spec:
  provider:
    vault:
      server: "http://vault-dr.staging-security-vault-dr.svc:8200"
      path: "secret"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "eso-reader"
```

**Regra geral:** ESO = 1 instancia por cluster. Para multiplos backends (Vault, AWS SM, etc), criar multiplos ClusterSecretStore/SecretStore. Os ExternalSecrets referenciam o store desejado via `spec.secretStoreRef`.

---

### Licao 15 — Kyverno require-corporate-labels em Enforce bloqueia Helm deploys: usar MutatingPolicy

**Problema:** Helm deploys falhavam com erro do Kyverno: pods/deployments rejeitados por nao terem labels corporativos obrigatorios (`domain`, `owner`, `environment`).

**Causa raiz:** A ClusterPolicy `require-corporate-labels` estava em modo `Enforce` (rejeita recursos sem labels). Helm charts de terceiros (Vault, Keycloak, Harbor, etc) nao incluem esses labels nativamente. Resultado: todo `helm install/upgrade` falhava na admission.

**Solucao aplicada:** Criar uma MutatingPolicy (ClusterPolicy com `mutate`) que injeta automaticamente os labels corporativos baseado no namespace:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: inject-corporate-labels
spec:
  rules:
    - name: add-labels
      match:
        any:
          - resources:
              kinds: ["Deployment", "StatefulSet", "DaemonSet", "Job", "CronJob"]
      mutate:
        patchStrategicMerge:
          metadata:
            labels:
              domain: "{{request.namespace | split('-') | [1]}}"
              owner: "platform-team"
              environment: "staging"
```

**Regra geral:** Kyverno `Enforce` + labels obrigatorios = INCOMPATIVEL com Helm charts de terceiros sem customizacao. Criar MutatingPolicy para injetar labels ANTES da validacao. Ordem: Mutate → Validate → Enforce.

---

### Licao 16 — Node-exporter compartilhado em cluster multi-env: hostNetwork conflito de porta

**Problema:** Ao deployar kube-prometheus-stack em produção (namespace separado do staging), o node-exporter falhava com erro de porta já em uso. DaemonSet ficava em CrashLoopBackOff.

**Causa raiz:** node-exporter usa `hostNetwork: true` e porta fixa 9100 no host. Como staging e prod compartilham os mesmos nodes físicos (cluster EKS único multi-environment), dois DaemonSets node-exporter tentavam bind na mesma porta 9100 — conflito direto.

**Solucao aplicada:** Desabilitar node-exporter no kube-prometheus-stack de prod (`nodeExporter.enabled: false`). O node-exporter do staging já cobre todos os 13 nodes do cluster (DaemonSet = 1 pod por node, independente de namespace). Métricas de node são globais (CPU, memória, disco, rede do host) — não há distinção staging/prod no nível do node.

**Regra geral:** Em clusters EKS multi-environment (staging + prod no mesmo cluster), deployar node-exporter em APENAS UM kube-prometheus-stack. O segundo ambiente deve desabilitar node-exporter e consumir métricas via federation ou remote-write do Prometheus que já tem os dados. Mesma regra aplica-se a qualquer DaemonSet com `hostNetwork: true` e porta fixa (e.g., promtail, fluent-bit).

**Diagnostico:**

```bash
# Verificar se já existe node-exporter rodando:
kubectl get ds -A | grep node-exporter
# Se retornar mais de 1 DaemonSet → conflito de porta garantido
```

---

### Licao 17 — ECR Pull-Through Cache requer PAT Docker Hub válido (não username/password)

**Problema:** ECR Pull-Through Cache rule criada com sucesso (`aws ecr create-pull-through-cache-rule`), mas pulls via ECR falhavam com erro de autenticação no upstream Docker Hub.

**Causa raiz:** O ECR Pull-Through Cache requer um Personal Access Token (PAT) do Docker Hub armazenado no AWS Secrets Manager — não aceita username/password tradicionais. O secret deve ter o formato `{"username":"<dockerhub-user>","accessToken":"<PAT>"}`. Credenciais de login normais (senha da conta Docker Hub) são rejeitadas pelo Docker Hub API v2 quando usadas como access token.

**Solucao aplicada:**

```text
1. Criar PAT no Docker Hub: hub.docker.com → Account Settings → Security → New Access Token
2. Criar secret no Secrets Manager:
   aws secretsmanager create-secret \
     --name ecr-pullthroughcache/docker-hub \
     --secret-string '{"username":"<user>","accessToken":"<PAT>"}'
3. Criar/atualizar a regra:
   aws ecr create-pull-through-cache-rule \
     --ecr-repository-prefix docker-hub \
     --upstream-registry-url registry-1.docker.io \
     --credential-arn arn:aws:secretsmanager:us-east-1:891377105802:secret:ecr-pullthroughcache/docker-hub-XXXXXX
```

**Regra geral:** Antes de criar ECR Pull-Through Cache rules para Docker Hub, gerar um PAT (Read-only scope suficiente) e armazená-lo no Secrets Manager. Nunca usar senha da conta Docker Hub — será rejeitada. Validar com `aws ecr batch-get-image` após configuração.

**Anti-pattern:** Criar a regra de pull-through cache sem credenciais ou com credenciais inválidas — pulls falham silenciosamente e pods ficam em ImagePullBackOff sem mensagem clara sobre credenciais.

---

## 2026-03-11 — Auditoria Pós-Entrega + Planejamento S6

**Auditoria S0→S5:** 34 GAPs identificados, 30 corrigidos em paralelo.
Sprints S3/S4 e S5 aprovados com ressalvas; S0+S1 e S2 em correção.

**S6 Backstage IDP:** Planejado (4 micro-sprints). Bloqueado por:
deploy Backstage (Vault bootstrap + Keycloak client + Helm), GitLab Group Token,
repo backstage-catalog.

**Ação:** Resolver desbloqueadores do Backstage para iniciar S6-A.
