# ⚠️ DIRETÓRIO DEPRECATED — NÃO USAR

**Status:** LEGACY (deprecated desde 2026-02-02)
**Motivo:** Refatoração Multi-Environment (ADR-026)
**Substituto:** `../environments/staging/` e `../environments/prod/`

---

## ❌ PROIBIDO

```bash
# ❌ NUNCA execute terraform aqui:
cd envs/marco3/
terraform plan
terraform apply

# ❌ NUNCA edite módulos aqui:
envs/marco3/modules/*
```

---

## ✅ USE A ESTRUTURA CORRETA

```bash
# ✅ Estrutura ativa (ADR-026):
cd environments/staging/
terraform plan
terraform apply

# ✅ Módulos compartilhados:
modules/gitlab/
modules/rabbitmq/
modules/redis/
modules/postgresql/
modules/s3-buckets/
```

---

## 📚 Referências

- **ADR-026:** Multi-Environment Terraform Refactoring
- **Localização:** `docs/context/decisions.md#adr-026`
- **Data migração:** 2026-02-02
- **Estrutura ativa:** `environments/{staging,prod,common}/`

---

## 🗂️ Mapeamento Legacy → Novo

| Legacy (envs/)          | Novo (environments/)     |
|-------------------------|--------------------------|
| `envs/marco3/`          | `environments/staging/`  |
| `envs/marco3/modules/*` | `modules/*` (raiz)       |
| Variáveis inline        | `common/` + env-specific |

---

**⚠️ SE VOCÊ ESTÁ LENDO ISSO E ESTÁ TENTANDO EXECUTAR ALGO AQUI, VOCÊ ESTÁ NO LUGAR ERRADO.**

**→ Vá para:** `cd ../environments/staging/`
