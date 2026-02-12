# Scripts - Data Services Domain

Scripts utilitários para gerenciamento do domínio data-services.

## 📜 Scripts Disponíveis

### `check-versions.sh`
Verifica as versões instaladas dos componentes data-services comparando com as versões mais recentes disponíveis.

**Uso:**
```bash
./scripts/check-versions.sh
```

**Pré-requisitos:**
- `helm` instalado e configurado
- `kubectl` instalado e configurado
- `jq` instalado
- Acesso ao cluster Kubernetes

**Output:**
- Status de cada componente (Atualizado/Desatualizado/Não Instalado)
- Resumo geral
- Recomendações de ação

**Exemplo:**
```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/domains/data-services
./scripts/check-versions.sh
```

## 🔄 Próximos Scripts Planejados

### `upgrade-operator.sh`
Script para realizar upgrade de operators de forma segura.

### `backup-pre-upgrade.sh`
Backup automatizado antes de upgrades.

### `validate-deployment.sh`
Valida deployment após upgrade.

---

**Documentação Relacionada:**
- [VERSION-CONTROL.md](../docs/VERSION-CONTROL.md) - Plano de atualização
- [VALIDATION-REPORT.md](../docs/VALIDATION-REPORT.md) - Relatório de validação
