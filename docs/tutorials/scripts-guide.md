# Scripts de Provisionamento - Kubernetes Platform

Este diretório contém scripts para automação de configuração do ambiente WSL.

## 📜 Scripts Disponíveis

### 1. `setup-wsl-environment.sh` (Completo - Interativo)

Script completo e interativo com interface colorida que instala todas as ferramentas e configura aliases.

**⚠️ Requer sudo interativo** (solicita senha durante execução)

```bash
bash scripts/setup-wsl-environment.sh
```

### 2. `install-tools.sh` (Instalação de Ferramentas)

Script simplificado que apenas instala as ferramentas necessárias.

**✅ Recomendado:** Execute com sudo uma vez:

```bash
sudo bash scripts/install-tools.sh
```

**Ferramentas instaladas:**
- AWS CLI V2
- Terraform
- Helm 3
- eksctl
- k9s
- kubectx/kubens

### 3. `configure-aliases.sh` (Configuração de Aliases)

Script que configura aliases e autocompleção no `.bashrc`.

**Execute como usuário normal** (sem sudo):

```bash
bash scripts/configure-aliases.sh
```

**Configurações aplicadas:**
- Aliases para AWS, Kubernetes, Terraform, Helm, Git
- Funções auxiliares (kpf, klog, kshell, awsprofile)
- Autocompleção para todos os comandos
- Variáveis de ambiente úteis

### 4. `install-vscode-extensions.sh` (Extensões VSCode)

Script que instala todas as extensões recomendadas do VSCode.

**Execute no terminal** (Windows ou WSL):

```bash
bash scripts/install-vscode-extensions.sh
```

**Extensões instaladas:**
- Remote - WSL, Kubernetes, YAML, Terraform, Docker
- GitLens, Better Comments, Error Lens
- Python, Go, Markdown, ShellCheck
- SonarLint, EditorConfig, Prettier
- Helm Intellisense, REST Client, Todo Tree, Draw.io

**📚 Documentação completa:** [VSCode Extensions Guide](./vscode-extensions-guide.md)

## 🚀 Uso Rápido (Instalação Completa)

```bash
# 1. Instalar ferramentas (requer sudo)
sudo bash scripts/install-tools.sh

# 2. Configurar aliases
bash scripts/configure-aliases.sh

# 3. Recarregar shell
source ~/.bashrc
```

## 📝 Aliases Configurados

Após executar `configure-aliases.sh`, você terá acesso a:

### AWS
- `awswhoami` - Mostra identidade AWS atual
- `awslogin` - Login SSO
- `awslogout` - Logout SSO
- `awsprofile <nome>` - Alternar perfil AWS

### Kubernetes
- `k` - kubectl
- `kgp` - kubectl get pods
- `kgs` - kubectl get services
- `kgn` - kubectl get nodes
- `kctx` - kubectx (alternar contextos)
- `kns` - kubens (alternar namespaces)

### Terraform
- `tf` - terraform
- `tfi` - terraform init
- `tfp` - terraform plan
- `tfa` - terraform apply

### Helm
- `h` - helm
- `hls` - helm list
- `hi` - helm install
- `hu` - helm upgrade

### Navegação
- `cdproj` - cd ~/projects/Arquitetura/Kubernetes
- `cdterraform` - cd terraform/
- `cddocs` - cd docs/
- `cdscripts` - cd scripts/

## 🔧 Requisitos

- **Sistema:** Ubuntu 20.04+ (WSL2 recomendado)
- **Permissões:** Acesso sudo para instalação de ferramentas
- **Espaço:** ~500MB de disco

## 📖 Documentação Completa

Para instruções detalhadas, veja:
- [Configuração de Ambiente WSL](../docs/tutorials/wsl-environment-setup.md)
- [Instalação do AWS CLI V2](../docs/tutorials/aws-cli-v2-installation.md)
- [Plano de Execução AWS](../docs/plan/aws-console-execution-plan.md)

## ⚠️ Notas Importantes

### Line Endings (CRLF vs LF)

Os scripts podem apresentar problemas se editados no Windows sem configuração adequada. Se encontrar erros como:

```
line X: $'\r': command not found
```

**Solução:**

```bash
# Corrigir todos os scripts
sed -i 's/\r$//' scripts/*.sh
```

**Prevenção no Git:**

```bash
# Configurar Git para usar LF no WSL
git config --global core.autocrlf input
```

### Permissões de Execução

Se necessário, torne os scripts executáveis:

```bash
chmod +x scripts/*.sh
```

## 🔍 Verificação Pós-Instalação

```bash
# Verificar versões instaladas
aws --version
terraform version
kubectl version --client
helm version --short
eksctl version
k9s version -s | grep Version

# Testar aliases
k get nodes    # Deve funcionar como 'kubectl get nodes'
awswhoami      # Deve funcionar como 'aws sts get-caller-identity'
```

## 🐛 Solução de Problemas

### Script não executa

```bash
# Verificar permissões
ls -la scripts/

# Adicionar permissão de execução
chmod +x scripts/install-tools.sh
```

### Aliases não funcionam após instalação

```bash
# Recarregar .bashrc
source ~/.bashrc

# Verificar se arquivo foi criado
cat ~/.k8s_aws_aliases
```

### Ferramentas não encontradas no PATH

```bash
# Verificar instalação
which aws
which kubectl
which terraform

# Se não encontrar, adicionar ao PATH manualmente
export PATH="/usr/local/bin:$PATH"
```

## 📝 Changelog

### v1.0 (2026-01-22)
- ✅ Script inicial de provisionamento completo
- ✅ Script separado de instalação de ferramentas
- ✅ Script de configuração de aliases
- ✅ Correção automática de line endings
- ✅ Suporte a Ubuntu 24.04 LTS (WSL2)

---

**Projeto:** Arquitetura Multi-Domínio Kubernetes
**Mantido por:** DevOps Team
**Última atualização:** 2026-01-22
