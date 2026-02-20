# TASK-004: Criar Bucket S3 fct-proposals

**Prioridade:** 🟡 ALTA
**Estimativa:** 2-3 horas
**Responsável:** TBD
**Criado:** 2026-02-19
**Devido:** 2026-02-26 (1 semana)
**Dependências:** Credenciais AWS configuradas, região definida
**Bloqueios:** Nenhum

---

## 📋 Contexto

**Problema Atual:**
- Hatch ETL e VemSoft ETL salvam arquivos de propostas em volumes locais separados
- VemSoft já extraiu ~70GB de arquivos de propostas VemCard localmente (`/mnt/e/vemsoft_downloads`)
- Não existe storage centralizado nem rastreabilidade de qual sistema extraiu cada arquivo

**Motivação:**
- Unificar storage de propostas em bucket S3 compartilhado entre Hatch e VemSoft
- Habilitar rastreabilidade via manifests (`_manifest_hatch.json` / `_manifest_vemsoft.json`) e Object Tags
- Preparar infraestrutura para carga inicial de 70GB (Sprint-004 BucketConnector) e alimentação contínua (Sprint-5.5 Hatch)

**Estratégia de Pastas:**
```
s3://fct-proposals/
└── {CNPJ_ORIGINADORA}_{ID_PROPOSTA}/
    ├── _manifest_hatch.json    ← escrito pelo Hatch
    ├── _manifest_vemsoft.json  ← escrito pelo VemSoft
    └── *.pdf / *.jpg / ...
```

**Referências:**
- Sprint-004 BucketConnector: `Utils/BucketConnector/docs/sprints/sprint-004-spec.md`
- Sprint-5.5 Hatch: `ETL/Hatch/docs/sprints/SPRINT_5.5_S3_BUCKET_INTEGRATION.md`
- Feature VemSoft: `ETL/VemSoft/docs/features/FEATURE-S3-BUCKET-INTEGRATION.md`

---

## 🎯 Objetivos

### Objetivo Principal
Criar e configurar o bucket S3 `fct-proposals` com lifecycle, IAM e validação de acesso
para suportar a estratégia de storage unificado de propostas.

### Objetivos Secundários

- [ ] Bucket privado, sem acesso público
- [ ] S3 Intelligent-Tiering configurado (reduz custo em ~40% para objetos frios)
- [ ] IAM Policy criada para o role do Hatch ETL
- [ ] BucketConnector CLI consegue listar e fazer upload no bucket
- [ ] Documentação atualizada (copilot-context.md + ADR se aplicável)

---

## 📝 Tarefas

### 1. Criação do Bucket (30min)

- [ ] **1.1** Definir região de deployment
  - Preferir `sa-east-1` (São Paulo) para menor latência e conformidade LGPD
  - Verificar custo: S3 SA-East-1 ≈ $0,026/GB/mês vs $0,023/GB US-East-1

- [ ] **1.2** Criar bucket com configurações de segurança
  ```bash
  # Criar bucket
  aws s3api create-bucket \
    --bucket fct-proposals \
    --region sa-east-1 \
    --create-bucket-configuration LocationConstraint=sa-east-1

  # Bloquear acesso público (obrigatório)
  aws s3api put-public-access-block \
    --bucket fct-proposals \
    --public-access-block-configuration \
      "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

  # Habilitar versionamento (opcional - decide equipe)
  aws s3api put-bucket-versioning \
    --bucket fct-proposals \
    --versioning-configuration Status=Enabled
  ```

- [ ] **1.3** Habilitar Server-Side Encryption (SSE-S3)
  ```bash
  aws s3api put-bucket-encryption \
    --bucket fct-proposals \
    --server-side-encryption-configuration '{
      "Rules": [{
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        },
        "BucketKeyEnabled": true
      }]
    }'
  ```

### 2. Configurar S3 Intelligent-Tiering (30min)

- [ ] **2.1** Aplicar configuração de Intelligent-Tiering
  ```bash
  aws s3api put-bucket-intelligent-tiering-configuration \
    --bucket fct-proposals \
    --id "proposals-tiering" \
    --intelligent-tiering-configuration '{
      "Id": "proposals-tiering",
      "Status": "Enabled",
      "Tierings": [
        {
          "Days": 30,
          "AccessTier": "ARCHIVE_ACCESS"
        },
        {
          "Days": 90,
          "AccessTier": "DEEP_ARCHIVE_ACCESS"
        }
      ]
    }'
  ```

- [ ] **2.2** Validar configuração aplicada
  ```bash
  aws s3api get-bucket-intelligent-tiering-configuration \
    --bucket fct-proposals \
    --id "proposals-tiering"
  ```

> **Nota de Custo**: Intelligent-Tiering cobra $0,0025/1.000 objetos/mês para monitoramento.
> Para arquivos PDF de propostas (geralmente > 128KB), o benefício supera o custo.
> Objetos < 128KB não são elegíveis para tiering (ficam em Standard).

### 3. Criar IAM Policy e Role (45min)

- [ ] **3.1** Criar policy para o Hatch ETL
  ```bash
  aws iam create-policy \
    --policy-name hatch-etl-s3-fct-proposals \
    --policy-document '{
      "Version": "2012-10-17",
      "Statement": [
        {
          "Sid": "ListBucket",
          "Effect": "Allow",
          "Action": ["s3:ListBucket"],
          "Resource": "arn:aws:s3:::fct-proposals"
        },
        {
          "Sid": "ObjectOperations",
          "Effect": "Allow",
          "Action": [
            "s3:PutObject",
            "s3:GetObject",
            "s3:DeleteObject",
            "s3:PutObjectTagging",
            "s3:GetObjectTagging"
          ],
          "Resource": "arn:aws:s3:::fct-proposals/*"
        }
      ]
    }'
  ```

- [ ] **3.2** Criar policy para o BucketConnector (carga inicial + operações admin)
  ```bash
  aws iam create-policy \
    --policy-name bucketconnector-s3-fct-proposals \
    --policy-document '{
      "Version": "2012-10-17",
      "Statement": [
        {
          "Sid": "FullBucketAccess",
          "Effect": "Allow",
          "Action": [
            "s3:ListBucket",
            "s3:PutObject",
            "s3:GetObject",
            "s3:DeleteObject",
            "s3:PutObjectTagging",
            "s3:GetObjectTagging"
          ],
          "Resource": [
            "arn:aws:s3:::fct-proposals",
            "arn:aws:s3:::fct-proposals/*"
          ]
        }
      ]
    }'
  ```

- [ ] **3.3** Anexar policy ao role existente do Hatch ETL (ou criar novo se não existir)
  ```bash
  # Se Hatch já tem um IAM role:
  aws iam attach-role-policy \
    --role-name hatch-etl-role \
    --policy-arn arn:aws:iam::{ACCOUNT_ID}:policy/hatch-etl-s3-fct-proposals
  ```

### 4. Validação de Acesso (30min)

- [ ] **4.1** Testar upload com BucketConnector CLI
  ```bash
  # Criar arquivo de teste
  echo '{"test": true}' > /tmp/test-manifest.json

  # Upload via BucketConnector
  bucketconnector -op upload \
    -file /tmp/test-manifest.json \
    -bucket fct-proposals \
    -key "00000000000000_TEST001/_manifest_vemsoft.json"

  # Verificar
  aws s3 ls s3://fct-proposals/00000000000000_TEST001/
  ```

- [ ] **4.2** Verificar Object Tags
  ```bash
  # Upload com tags (via AWS CLI para validar suporte)
  aws s3 cp /tmp/test-manifest.json \
    s3://fct-proposals/00000000000000_TEST001/_manifest_hatch.json \
    --tagging "source=hatch&env=test"

  # Verificar tags
  aws s3api get-object-tagging \
    --bucket fct-proposals \
    --key "00000000000000_TEST001/_manifest_hatch.json"
  ```

- [ ] **4.3** Verificar listagem hierárquica
  ```bash
  aws s3 ls s3://fct-proposals/ --recursive
  # Esperado: 2 arquivos na pasta 00000000000000_TEST001/
  ```

- [ ] **4.4** Limpar objetos de teste
  ```bash
  aws s3 rm s3://fct-proposals/00000000000000_TEST001/ --recursive
  ```

### 5. Documentação (15min)

- [ ] **5.1** Atualizar `ai-contexts/copilot-context.md` com novo bucket
  - Adicionar seção: Storage / S3 Buckets
  - Registrar: nome, região, propósito, quem usa

- [ ] **5.2** Avaliar necessidade de ADR-025
  - Se a decisão de usar bucket único compartilhado merece registro formal → criar ADR-025
  - Referência: ADR-024 (FinOps) para padrão de custo

---

## ✅ Critérios de Sucesso

- [ ] Bucket `fct-proposals` criado em `sa-east-1` (ou região definida)
- [ ] Acesso público bloqueado
- [ ] SSE-S3 ativo
- [ ] Intelligent-Tiering configurado (30d → Archive, 90d → Deep Archive)
- [ ] IAM Policy `hatch-etl-s3-fct-proposals` criada e testada
- [ ] IAM Policy `bucketconnector-s3-fct-proposals` criada e testada
- [ ] BucketConnector CLI consegue fazer upload e listar objetos
- [ ] Object Tags funcionando
- [ ] copilot-context.md atualizado
- [ ] Sprint-004 BucketConnector pode ser iniciada

---

## ⚠️ Rollback Plan

### Se bucket causar problema de custo inesperado:

1. **Verificar Intelligent-Tiering Monitoring Fee**
   ```bash
   # Ver objetos no bucket
   aws s3api list-objects-v2 --bucket fct-proposals --query 'KeyCount'
   # > 1M objetos: considerar desabilitar monitoring e usar lifecycle simples
   ```

2. **Reverter para Lifecycle Rule simples**
   ```bash
   # Remover Intelligent-Tiering
   aws s3api delete-bucket-intelligent-tiering-configuration \
     --bucket fct-proposals --id "proposals-tiering"

   # Adicionar Lifecycle rule simples (Glacier após 90 dias)
   aws s3api put-bucket-lifecycle-configuration \
     --bucket fct-proposals \
     --lifecycle-configuration file://lifecycle-glacier.json
   ```

### Se bucket precisar ser removido (pré-produção apenas):

```bash
# ATENÇÃO: Irreversível. Só executar antes de qualquer dado real.
aws s3 rm s3://fct-proposals --recursive
aws s3api delete-bucket --bucket fct-proposals
```

---

## 🔗 Referências

### Documentação Oficial
- [S3 Intelligent-Tiering](https://docs.aws.amazon.com/AmazonS3/latest/userguide/intelligent-tiering.html)
- [S3 Pricing sa-east-1](https://aws.amazon.com/s3/pricing/)
- [IAM Policy Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)

### Documentação Interna
- Sprint-004 BucketConnector: `Utils/BucketConnector/docs/sprints/sprint-004-spec.md`
- Sprint-5.5 Hatch ETL: `ETL/Hatch/docs/sprints/SPRINT_5.5_S3_BUCKET_INTEGRATION.md`
- Feature VemSoft: `ETL/VemSoft/docs/features/FEATURE-S3-BUCKET-INTEGRATION.md`
- ADR-024 FinOps: `docs/adr/adr-024-finops-scheduler-implementation.md`

---

**Status:** 📋 TODO
**Última Atualização:** 2026-02-19
**Tracking Issue:** #TBD
