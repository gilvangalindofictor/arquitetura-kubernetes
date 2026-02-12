# Local DNS Setup - Kubernetes Platform

**Objetivo**: Configurar DNS local para acessar serviços da plataforma K8s staging sem DNS público.

**Domínio**: `.staging.internal` (convenção corporativa)

---

## 📋 Pré-requisitos

- Acesso ao cluster Kubernetes (kubectl configurado)
- Permissões de administrador no sistema operacional

---

## 🔍 Descobrir IP do ALB

Execute no terminal:

```bash
kubectl get ingress -n gitlab-staging gitlab-webservice-default -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Copie o DNS retornado (exemplo: `k8s-gitlabstaging-xyz.us-east-1.elb.amazonaws.com`) e resolva o IP:

```bash
# Linux/Mac
dig +short k8s-gitlabstaging-xyz.us-east-1.elb.amazonaws.com

# Windows (PowerShell)
Resolve-DnsName k8s-gitlabstaging-xyz.us-east-1.elb.amazonaws.com
```

**IP Atual**: `50.17.236.17` (verificar se mudou antes de aplicar)

---

## 🖥️ Configuração por Sistema Operacional

### Linux / WSL

**Arquivo**: `/etc/hosts`

```bash
# 1. Backup
sudo cp /etc/hosts /etc/hosts.backup

# 2. Adicionar entradas (substitua <ALB-IP> pelo IP real)
sudo tee -a /etc/hosts > /dev/null <<EOF

# Kubernetes Platform - Staging Environment (.staging.internal)
50.17.236.17  gitlab.staging.internal
50.17.236.17  argocd.staging.internal
50.17.236.17  keycloak.staging.internal
50.17.236.17  sonarqube.staging.internal
50.17.236.17  harbor.staging.internal
EOF

# 3. Validar
curl -I http://gitlab.staging.internal
```

---

### macOS

**Arquivo**: `/etc/hosts`

```bash
# 1. Backup
sudo cp /etc/hosts /etc/hosts.backup

# 2. Editar
sudo nano /etc/hosts

# 3. Adicionar ao final:
# Kubernetes Platform - Staging Environment (.staging.internal)
50.17.236.17  gitlab.staging.internal
50.17.236.17  argocd.staging.internal
50.17.236.17  keycloak.staging.internal
50.17.236.17  sonarqube.staging.internal
50.17.236.17  harbor.staging.internal

# 4. Flush DNS cache
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder

# 5. Validar
curl -I http://gitlab.staging.internal
```

---

### Windows

**Arquivo**: `C:\Windows\System32\drivers\etc\hosts`

```powershell
# 1. Abrir PowerShell como Administrador

# 2. Backup
Copy-Item C:\Windows\System32\drivers\etc\hosts C:\Windows\System32\drivers\etc\hosts.backup

# 3. Adicionar entradas
Add-Content C:\Windows\System32\drivers\etc\hosts @"

# Kubernetes Platform - Staging Environment (.staging.internal)
50.17.236.17  gitlab.staging.internal
50.17.236.17  argocd.staging.internal
50.17.236.17  keycloak.staging.internal
50.17.236.17  sonarqube.staging.internal
50.17.236.17  harbor.staging.internal
"@

# 4. Flush DNS cache
ipconfig /flushdns

# 5. Validar
curl.exe -I http://gitlab.k8s.test
```

**Alternativa GUI**:
1. Notepad como Administrador
2. Abrir: `C:\Windows\System32\drivers\etc\hosts`
3. Adicionar linhas ao final
4. Salvar
5. `ipconfig /flushdns`

---

## ✅ Validação

Após configurar, testar cada serviço:

```bash
# GitLab (já deve funcionar)
curl -I http://gitlab.staging.internal
# Esperado: HTTP/1.1 302 Found

# ArgoCD (após criar ingress)
curl -I http://argocd.k8s.test
# Esperado: HTTP/1.1 200 OK ou 302

# Keycloak (após criar ingress)
curl -I http://keycloak.k8s.test
# Esperado: HTTP/1.1 200 OK
```

**Browser**: Acessar `http://gitlab.k8s.test` (deve redirecionar para UI do GitLab)

---

## 🔄 Manutenção

### Quando Atualizar

- ALB IP mudou (raro, geralmente após recriar ingress)
- Novos serviços adicionados à plataforma

### Como Atualizar

1. Obter novo IP do ALB (comando acima)
2. Substituir IP antigo pelo novo no `/etc/hosts`
3. Flush DNS cache (comando específico do SO)

### Remover Configuração

```bash
# Linux/Mac
sudo nano /etc/hosts  # Deletar linhas manualmente

# Windows (PowerShell Admin)
notepad C:\Windows\System32\drivers\etc\hosts  # Deletar linhas
ipconfig /flushdns
```

---

## 📦 Script Automatizado (Linux/WSL)

```bash
#!/bin/bash
# install-local-dns.sh

ALB_IP=$(kubectl get ingress -n gitlab-staging gitlab-webservice-default -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' | xargs dig +short | head -1)

if [ -z "$ALB_IP" ]; then
  echo "❌ Falha ao obter IP do ALB. Verifique acesso ao cluster."
  exit 1
fi

echo "✅ ALB IP: $ALB_IP"

# Backup
sudo cp /etc/hosts /etc/hosts.backup.$(date +%Y%m%d)

# Remover entradas antigas (se existirem)
sudo sed -i '/.k8s.test/d' /etc/hosts

# Adicionar entradas
sudo tee -a /etc/hosts > /dev/null <<EOF

# Kubernetes Platform - Staging Environment (.k8s.test)
# Generated: $(date)
$ALB_IP  gitlab.k8s.test
$ALB_IP  argocd.k8s.test
$ALB_IP  keycloak.k8s.test
$ALB_IP  sonarqube.k8s.test
$ALB_IP  harbor.k8s.test
EOF

echo "✅ /etc/hosts atualizado"
echo "🧪 Testando GitLab..."
curl -I http://gitlab.staging.internal 2>&1 | head -3

echo "
📋 Próximos passos:
1. Testar no browser: http://gitlab.k8s.test
2. Criar ingresses para ArgoCD/Keycloak (Marco 4)
3. Compartilhar este doc com o time
"
```

**Uso**:
```bash
chmod +x install-local-dns.sh
./install-local-dns.sh
```

---

## 🚀 Para Equipe

**Compartilhar**:
1. Este documento (`docs/operations/local-dns-setup.md`)
2. IP atual do ALB
3. Comando de validação

**Onboarding novo membro**:
```bash
# 1. Clonar repo
git clone <repo-url>

# 2. Executar script (Linux/WSL)
cd Kubernetes
bash docs/operations/install-local-dns.sh

# 3. Ou seguir instruções manuais (seção acima)
```

---

## 🔐 Segurança

- ⚠️ `/etc/hosts` NÃO deve conter credenciais
- ⚠️ IPs aqui são públicos do ALB (não é segredo)
- ✅ Security Groups controlam acesso real ao cluster
- ✅ Domínios `.test` nunca resolverão para internet pública (RFC 2606)

---

## 📚 Referências

- RFC 2606: Reserved Top Level DNS Names (`.test`, `.example`, `.invalid`, `.localhost`)
- [ADR-008: TLS Strategy for ALB Ingresses](../adr/adr-008-tls-strategy-for-alb-ingresses.md)
- [Runbook: ALB Troubleshooting](../runbooks/alb-troubleshooting.md)
