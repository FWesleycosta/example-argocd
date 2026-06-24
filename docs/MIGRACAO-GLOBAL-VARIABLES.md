# Plano de Migração — `templates/variables/global-variables.yaml`

> **Status:** proposta / ADR para execução faseada.
> **Escopo de risco:** arquivo **compartilhado** por múltiplos pipelines/repos
> (backend .NET, SPA/frontend, PIX). Toda mudança aqui tem **blast radius cross-repo**.
> Por isso: migração **incremental**, um consumidor por vez, com verificação a cada passo.
> **Princípio-guia:** o mesmo do refactor da esteira — *ambiente é dado, não código*.

---

## 1. Diagnóstico (o que está errado hoje)

`global-variables.yaml` é uma lista plana de ~417 pares `name/value` carregada por
**toda** pipeline. Três problemas, em ordem de gravidade:

| # | Problema | Evidência | Risco |
|---|---|---|---|
| 🔴 **A** | **Segredos em texto plano no git** | `clientId-prod`, `tenantId-prod`, `applicationId-prod`, `fibraApiKey-prod`, `tokenApi-prod`, `firebase.apiKey-prod`, `objectId-hml` (GUID) | Vazamento de credencial; compile-time (`${{ }}`) ainda *imprime o valor* no YAML compilado |
| 🟠 **B** | **Baixa coesão (mistura de domínios)** | backend AWS/EKS + frontend SPA (Firebase/B2C/Vite/Hotjar/Zendesk) + PIX no mesmo arquivo | Deploy de backend .NET carrega config de Firebase que não usa; cada mudança tem superfície enorme |
| 🟡 **C** | **Convenções inconsistentes** | `DevAwsAccID` × `PrdAwsAccId`; typo `PIxPrdServiceAccountTerraform`; 3 esquemas de ambiente (prefixo `Dev*`, sufixo `-prod`, arquivo `env/<env>.yaml`) | Expressão resolve para **vazio silenciosamente**; bugs latentes |

---

## 2. Arquitetura-alvo

```
templates/variables/
├── env/{dev,hml,prd}.yaml        # infra BACKEND por ambiente (valores reais inline)
├── frontend/{dev,hml,prd}.yaml   # Firebase/B2C/Vite/Hotjar/Zendesk — só pipelines SPA
├── pix/{dev,hml,prd}.yaml        # variantes PIX
└── global-variables.yaml         # SÓ constantes realmente cross-cutting (idealmente vazio)
```

- **Não-segredos por ambiente** → vivem no `env/<env>.yaml` daquele domínio (já é o padrão
  adotado pelo refactor). Some o esquema de prefixo `Dev*/Hml*/Prd*`.
- **Segredos** → **Azure DevOps variable group ligado ao Azure Key Vault**, consumido via
  `- group: <nome>` e referenciado em **runtime** como `$(secret)` — nunca `${{ }}`, nunca em YAML.
- **Convenção única de nome:** `PascalCase`, **sem** sufixo de ambiente (o ambiente é o arquivo).

---

## 3. Migração faseada (com portões de verificação)

> Regra geral: **nunca apague do `global-variables` antes do consumidor migrar**. Durante a
> transição, o valor pode existir nos dois lugares (o escopo mais específico vence). Cada fase
> termina com **Preview API** (`POST /_apis/pipelines/{id}/preview`, `previewRun=true`) contra
> um app real para compilar sem executar.

### Fase 0 — Inventário e congelamento (pré-requisito)
- [ ] Mapear **quem consome** `global-variables.yaml` (grep por repo / busca cross-repo no ADO).
- [ ] Classificar cada variável: `infra-backend` | `frontend` | `pix` | `secret` | `morta`.
- [ ] Pinar todos os consumidores numa **tag** da plataforma (já é a prática do refactor) para
      que a migração não vaze para quem não optou.

### Fase 1 — Segredos → Key Vault (🔴 maior prioridade)
- [ ] Criar/identificar o Key Vault por ambiente e o **variable group** ligado a ele no ADO.
- [ ] Mover cada segredo (B2C, API keys, tokens, Firebase) para o cofre; remover do YAML.
- [ ] Trocar o consumo: `${{ variables.fibraApiKey-prod }}` → `- group: fibra-secrets-prd` + `$(fibraApiKey)`.
- [ ] **Rotacionar** os segredos que estiveram no git (assuma comprometidos).
- [ ] Portão: pipeline compila e os jobs enxergam os segredos em runtime.

### Fase 2 — Split por domínio (🟠 um consumidor por vez)
- [ ] Criar `variables/frontend/<env>.yaml` e `variables/pix/<env>.yaml`.
- [ ] Migrar **um pipeline consumidor de cada vez** para o arquivo de domínio + remover daquele
      domínio no `global-variables` só após todos os consumidores migrarem.
- [ ] Backend: garantir que `env/<env>.yaml` tenha os valores reais (hoje faz *alias* para os
      macros `Dev*/Hml*/Prd*`; inline os valores e remova o alias).
- [ ] Portão a cada consumidor: Preview API verde.

### Fase 3 — Normalização de nomes (🟡 por último, mecânico)
- [ ] Corrigir `DevAwsAccID`/`HmlAwsAccID` → `…AccId` (alinhar a `PrdAwsAccId`) **ou** vice-versa,
      e atualizar os consumidores no mesmo commit.
- [ ] Corrigir typo `PIxPrdServiceAccountTerraform`.
- [ ] Eliminar o sufixo `-hml/-prod` (o ambiente passa a ser o arquivo).
- [ ] Padronizar região: hoje `dev`/`hml` usam `AwsRegion` e `prd` usa `PrdAwsRegion`
      — unificar para `awsRegion` por arquivo de env.

### Fase 4 — Encolher o `global-variables`
- [ ] Remover seções migradas; manter só o que é genuinamente cross-cutting (ou esvaziar).
- [ ] Remover variáveis mortas identificadas na Fase 0.

---

## 4. Rollback

- Cada fase é um PR isolado e reversível; como os consumidores estão **pinados por tag**, um app
  só pega a mudança quando bumpa a tag → rollback = manter a tag anterior.
- Durante a transição os valores coexistem (origem antiga + nova), então reverter o consumidor
  não deixa variável órfã.

## 5. Definição de pronto

- [ ] Nenhum segredo em YAML versionado (varredura limpa).
- [ ] Backend/SPA/PIX consomem só o arquivo do seu domínio.
- [ ] Uma única convenção de nome; sem assimetrias `ID`/`Id`.
- [ ] `global-variables.yaml` reduzido a cross-cutting real (ou removido).
- [ ] Todos os pipelines compilam via Preview API.
