# Fix: harbor-core CrashLoopBackOff — Trivy Scanner Registration Duplicada

**Data:** 2026-03-04
**Namespace:** harbor-system
**Severidade:** P1 — Impacto em alta disponibilidade do Harbor (1 de 2 réplicas em CrashLoop)
**Duração do incidente:** ~41h (pod tjpv8 em CrashLoop desde 2026-03-03T14:30)
**Resolução:** ~15 min

---

## Sintoma

```
harbor-core-6c48d776bd-tjpv8   0/1   CrashLoopBackOff   55 (4m34s ago)   41h
harbor-core-6c48d776bd-g6xcl   1/1   Running            0                41h
```

O deployment harbor-core com `replicas: 2` estava com uma réplica em CrashLoopBackOff
enquanto a outra permanecia Running, causando degradação de HA.

---

## Root Cause

### Log do pod crashando (tjpv8)

```
2026-03-04T14:50:23Z [INFO]  [/core/main.go:318]: Registering Trivy scanner
2026-03-04T14:50:23Z [FATAL] [/core/main.go:336]: failed to register scanners:
  creating registration Trivy at http://harbor-trivy:8080 failed:
  dao: create registration: registration name or url already exists
```

### Causa raiz identificada

O banco de dados `harbor.scanner_registration` continha um registro com nome `"Trivy Scanner"`
e URL `http://harbor-trivy:8080` criado manualmente (via Harbor UI ou API) com nome não-padrão.

O harbor-core (v2.10.0) ao iniciar executa `main.go:318` que tenta registrar o scanner
interno com o **nome reservado `"Trivy"`** e a mesma URL `http://harbor-trivy:8080`.

O PostgreSQL retorna UNIQUE constraint violation porque a URL já estava em uso por `"Trivy Scanner"`.

### Por que o pod g6xcl (Running) não crashou?

O pod g6xcl subiu em 2026-03-02 (antes do scanner "Trivy Scanner" ser criado manualmente).
Quando reiniciou depois, o path de código `init.go:64` verificou por URL e encontrou o registro
existente, executando `Skipped setting Trivy as the default scanner` sem FATAL.

O pod tjpv8 usou o path `main.go:336` (INSERT antes de verificar) → colisão.

### Scanner conflitante

| Campo | Valor |
|-------|-------|
| UUID | `82288804-170d-11f1-81cb-3a77f7c3897a` |
| Name | `Trivy Scanner` (nome não-padrão, criado manualmente) |
| URL | `http://harbor-trivy:8080` |
| Created | `2026-03-03T14:30:21Z` |
| Default | `true` |

---

## Fix Aplicado

### Abordagem: Harbor REST API (sem acesso direto ao DB)

O fix foi aplicado sem necessidade de Job temporário de SQL, usando a Harbor API
acessível via `kubectl port-forward` para a réplica Running.

**Passo 1: Port-forward para harbor-core Running**

```bash
kubectl port-forward svc/harbor-core 9080:80 -n harbor-system
```

**Passo 2: Verificar scanners existentes**

```bash
curl -s -u "admin:${HARBOR_ADMIN_PASS}" \
     "http://localhost:9080/api/v2.0/scanners?page_size=100"
# Resultado: 1 scanner "Trivy Scanner" UUID 82288804-...
```

**Passo 3: Deletar o scanner conflitante**

```bash
curl -s -X DELETE \
     -u "admin:${HARBOR_ADMIN_PASS}" \
     "http://localhost:9080/api/v2.0/scanners/82288804-170d-11f1-81cb-3a77f7c3897a"
# HTTP 200 OK
```

**Passo 4: Reiniciar o deployment harbor-core**

```bash
kubectl rollout restart deployment/harbor-core -n harbor-system
kubectl rollout status deployment/harbor-core -n harbor-system --timeout=120s
# deployment "harbor-core" successfully rolled out
```

---

## Resultado

```
harbor-core-9577c8bd8-njh7z   1/1   Running   0   35s
harbor-core-9577c8bd8-tdzm6   1/1   Running   0   15s
```

### Logs pós-fix (pod njh7z — primeiro a subir)

```
[INFO] [/core/main.go:318]: Registering Trivy scanner
[INFO] [/pkg/scan/init.go:56]: Successfully registered Trivy scanner at http://harbor-trivy:8080
[INFO] [/core/main.go:340]: Setting Trivy as default scanner
[I] http server Running on http://:8080
```

### Logs pós-fix (pod tdzm6 — segundo a subir)

```
[INFO] [/core/main.go:318]: Registering Trivy scanner
[INFO] [/core/main.go:340]: Setting Trivy as default scanner
[INFO] [/pkg/scan/init.go:79]: Skipped setting Trivy as the default scanner. The default scanner is already set to http://harbor-trivy:8080
[I] http server Running on http://:8080
```

### Scanner registrado corretamente após fix

| Campo | Valor |
|-------|-------|
| UUID | `18fc4fe1-17da-11f1-af26-4e47367eaf53` |
| Name | `Trivy` (nome interno correto) |
| URL | `http://harbor-trivy:8080` |
| Created | `2026-03-04T14:54:51Z` |
| Default | `true` |
| use_internal_addr | `true` |

---

## Registrations

| | Antes | Depois |
|---|---|---|
| Total registrations | 1 (`"Trivy Scanner"` — nome errado) | 1 (`"Trivy"` — nome correto) |
| CrashLoopBackOff pods | 1 | 0 |
| Running pods | 1/2 | 2/2 |

---

## Prevenção

1. **Nunca criar scanner "Trivy" manualmente via Harbor UI/API.** O harbor-core gerencia este
   registro internamente ao iniciar. Criar manualmente com nome diferente (ex: "Trivy Scanner")
   causa conflito de URL na reinicialização.

2. **harbor-core não suporta registro manual de scanner com mesma URL do Trivy built-in.**
   O nome `"Trivy"` é reservado pela API (`BAD_REQUEST: name "Trivy" is reserved`).

3. **Se necessário recriar o scanner:** usar `kubectl rollout restart deployment/harbor-core`
   após garantir que não há scanner com a URL `http://harbor-trivy:8080` no banco.

4. **Harbor com `replicas: 2`:** o segundo pod usa `init.go:64` (URL check → skip) se o
   primeiro já registrou. A condição de race só ocorre se o scanner foi criado com nome
   diferente do esperado pelo core.
