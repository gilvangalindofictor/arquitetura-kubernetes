# Strategies History — Platform Engineering

Registro consolidado de padroes, estrategias e licoes aprendidas ao longo das sessoes de implementacao da plataforma.

Formato de cada entrada:
- **Tipo**: categoria do trabalho
- **Padrao**: sequencia de passos que funcionou
- **Licoes aprendidas**: o que foi descoberto, o que nao funciona e por que

---

## 2026-03-05 — K8s Workload Deploy: Backstage IDP

**Tipo:** K8s Workload Deploy (Backstage IDP)

**Contexto:** Primeiro deploy do Backstage como Internal Developer Platform no cluster `k8s-platform-prod` (EKS us-east-1, conta 891377105802). Namespace padrao `staging-platform-*`, service mesh Linkerd ativo, Kyverno como policy engine.

**Padrao que funcionou:**

```
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

```
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

```
Keycloak realm platform → Client confidential + PKCE → GitLab OmniAuth OIDC → Vault KV → ESO
```

**Licoes aprendidas:**
- Qualquer URL que o browser precisa resolver DEVE usar hostname externo (`*.staging.internal`), nunca `svc.cluster.local` nem `localhost`
- PKCE (S256) obrigatorio em Keycloak 26 para clients confidenciais com redirect via browser
- Validar `/.well-known/openid-configuration` antes de qualquer integracao OIDC

**Referencias:**
- logbook: `2026-02-13-sso-e2e-conformidade-keycloak.md`
- strategies: `strategies-gitlab-sso.md`
