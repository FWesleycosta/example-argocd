# Arquitetura de Templates — Esteira Reutilizável (Paved Road)

> **Status:** esqueleto implementado, rodando **lado a lado** com a esteira atual
> (`azure-pipeline-dotnet.yaml` permanece intacto). Objetivo: eliminar a replicação
> de templates e transformar a esteira em **produto de plataforma versionado**.

---

## 1. Problema que isto resolve

| Anti-padrão (antes) | Onde | Consequência |
|---|---|---|
| Bloco de deploy replicado 4× (DEV/HML/PRD/hotfix) | `azure-pipeline-dotnet.yaml` | Adicionar 1 parâmetro = editar 4 lugares → divergência |
| `ref: refs/heads/main` | `azure-pipeline-dotnet.yaml:6` | Todo app pega *head* de main → quebra geral sem rollout |
| App copia ~375 linhas de esteira | cada repo | Manutenção impossível de propagar |

**Princípio:** *o ambiente vira DADO, não código.* A diferença entre os deploys é só
o ambiente → um único `stages/deploy.yaml` parametrizado por `environment`.

---

## 2. Estrutura

```
templates/
├── stacks/
│   └── dotnet-backend.yaml      # ENTRYPOINT (alvo do `extends`) — esteira completa
├── stages/
│   ├── deploy.yaml              # 1 stage de deploy; param: environment
│   └── veracode.yaml            # 1 stage de SAST; reusado por release/* e hotfix
├── steps/
│   └── rollout-verify.yaml      # NOVO: kubectl rollout status + undo on fail
├── variables/                  # fatiado por DOMÍNIO × AMBIENTE (sem global-variables)
│   ├── env/                     # backend .NET/EKS — mesmos NOMES, valores por ambiente
│   │   ├── dev.yaml
│   │   ├── hml.yaml
│   │   └── prd.yaml
│   ├── frontend/                # SPA (B2C/Firebase/Vite/…) — só pipelines de frontend
│   │   ├── dev.yaml
│   │   ├── hml.yaml
│   │   └── prd.yaml
│   └── pix/                     # domínio PIX
│       ├── dev.yaml
│       ├── hml.yaml
│       └── prd.yaml
├── sonarqube/qa-sonar-dotnet.yaml
├── veracode/scanner-veracode.yaml     # steps do SAST (consumido por stages/veracode.yaml)
├── infra/setup-git-auth.yaml
├── deploy-backend.yaml          # (INALTERADO) lógica provada de ECR+TF+K8s
├── dotnet/build-backend-dotnet.yaml
├── hotfix/hotfix-backend-dotnet.yaml  # REUSA stages/veracode + stages/deploy(prd)
└── utils/create-pullrequest.yaml

examples/
└── azure-pipelines.yml          # pipeline FINO que cada app copia (~30 linhas, só dados)
```

**Camadas:** `stack` (entrypoint) → `stages` → `steps`. Config de ambiente isolada
em `variables/env/`.

---

## 3. Como o app consome (antes × depois)

- **Antes:** ~375 linhas copiadas por app.
- **Depois:** `examples/azure-pipelines.yml` — só objetos de dados, `extends` na
  plataforma pinada por tag. App novo = copiar o exemplo e ajustar valores.

`extends` (não só `template`) é proposital: a plataforma **injeta** steps
obrigatórios (Veracode, `rollout-verify`, annotations) que o time de app **não
consegue remover** — compliance do GMUD garantida por construção.

---

## 4. A técnica central: ambiente como dado

`stages/deploy.yaml` recebe `environment` e resolve as variáveis de infra via
caminho dinâmico em compile-time:

```yaml
variables:
  - template: ../variables/env/${{ parameters.environment }}.yaml
```

Cada `env/<env>.yaml` declara os **mesmos nomes** (`serviceAccount`, `clusterName`,
…) com valores do ambiente. Resultado: **4 cópias → 1 template + 3 arquivos curtos**.

Os arquivos de env são **self-contained** com os valores reais inline — não há mais
`global-variables.yaml` nem o esquema de prefixo `Dev*/Hml*/Prd*`. As variáveis foram
fatiadas por **domínio × ambiente** (`variables/env`, `variables/frontend`,
`variables/pix`), cada pipeline consumindo só o seu. Ver `MIGRACAO-GLOBAL-VARIABLES.md`.

A config do app trafega em **objetos agrupados** (`pod`, `networking`, `resources`,
`observability`, `config`) em vez de ~40 parâmetros soltos.

---

## 5. Versionamento da plataforma

- Tags imutáveis (`v2.0.0`) + tag major móvel (`v2`) para apps que querem acompanhar.
- Apps pinam `ref: refs/tags/vX.Y.Z`. **Nunca** `refs/heads/main`.
- Bump deliberado por app = rollout controlado (um app quebra por vez, não todos).

---

## 6. ⚠️ Premissas a validar antes de promover a produção

1. **Valores inline nos `env/*.yaml`** — os valores de infra ficam direto nos
   arquivos de ambiente (`name/value`, compile-time). Confira que estão corretos por
   ambiente. Itens sensíveis (B2C/Firebase/tokens em `variables/frontend/*`) hoje ficam
   em YAML por decisão de não usar *variable group*; o destino correto é Key Vault —
   ver `MIGRACAO-GLOBAL-VARIABLES.md`.
2. **Validação por Preview API** — antes de mergear mudanças na plataforma, rode
   `POST /_apis/pipelines/{id}/preview` (previewRun=true) contra um app de exemplo
   para compilar os templates sem executar. Pega erros de YAML/expressão cedo.
3. **`rollout-verify`** — exige `kubectl` no agente (já usado nos steps de K8s) e
   permissão de `rollout undo` na service account do ambiente.

---

## 7. Migração incremental (sem big-bang)

1. **Tag `v1.0.0`** no estado atual e aponte os apps para a tag → estanca o risco
   do `refs/heads/main` sem mudar comportamento.
2. Valide o esqueleto novo com **1 app piloto** (branch de teste).
3. Libere `v2.0.0` (extends + deploy único + rollout-verify).
4. Migre os apps **um a um**, bumpando a tag. Apps não migrados seguem em `v1`.

---

## 8. O que ainda NÃO está neste esqueleto (próximos passos)

- Promoção da imagem por **digest cross-account** (build-once de verdade) no lugar
  do `docker save/load` do `.tar`.
- **Desacoplar Terraform** do deploy de app (pipeline de infra separado).
- **OIDC** para AWS no lugar de credenciais longevas.
- **Concurrency/lock** por ambiente para impor "uma release por vez".
- Caches de Docker/NuGet.
