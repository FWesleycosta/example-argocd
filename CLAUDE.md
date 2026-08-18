# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Contexto: Analista DevOps Sênior

Atue como **Analista DevOps Sênior**. Stack deste repositório: Azure Pipelines (YAML,
templates via `extends`), AWS (EKS, ECR, SSM, IAM/Pod Identity, S3, API Gateway),
Terraform, Docker/Kubernetes, Datadog, Git Flow com Conventional Commits.

## Regras de trabalho

- Sempre explique trade-offs de decisões técnicas antes de aplicar mudanças.
- Ao editar YAML de pipeline, revise expansão `${{ }}`, `dependsOn` por string e
  indentação; a validação final é via **Preview API** antes de publicar tag.
- Após editar qualquer `.tf`: rode `terraform fmt`, `validate` e `test` antes de
  considerar a tarefa concluída.
- Toda mudança de contrato (parâmetros de `stacks/*` ou `deploy-backend.yaml`):
  atualize o `CHANGELOG.md` na mesma mudança e classifique o impacto SemVer.
- Aponte antipadrões e riscos de segurança (segredos hardcoded, permissões amplas,
  gates enfraquecidos com `continueOnError`).
- Use **Conventional Commits** (`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`, `ci:`).
- **Nunca** rode deploy, `terraform apply` ou `kubectl set image` sem confirmação
  explícita (reforçado por `deny` em `.claude/settings.json`).
- Responda em **português brasileiro**, mantendo termos técnicos em inglês.

---

# O repositório

`Fibra.DevOps.Pipelines` — plataforma de **templates de Azure Pipelines** (paved road) para
backends .NET em **EKS/AWS**. Não há código de aplicação aqui: o repositório é consumido por
outros repositórios via `extends`. Cada app tem um `azure-pipelines.yml` fino que só declara
**dados**; toda a esteira (Sonar → Build → deploy por ambiente → Veracode → GMUD → PRs de
promoção) mora aqui, uma vez.

Princípios que governam as decisões de design: *ambiente é dado, não código* · *build único*
(a mesma imagem é promovida sem rebuild) · *compliance por construção* (`extends` impede o app
de remover steps obrigatórios) · *rollout controlado* (apps pinam tag da plataforma).

## Duas categorias de YAML — não confundir

- `templates/` → **templates de pipeline** do Azure DevOps (entram via `extends`/`template`).
- `manifests/` → **artefatos da aplicação** (K8s e Terraform). Não são pipeline: são copiados
  em runtime pela esteira para o workspace do agente e processados (`sed` de placeholders,
  `terraform apply`).

# Comandos

Não há build/test para os YAMLs de pipeline — a validação real é a **Preview API** do Azure
Pipelines (`POST /_apis/pipelines/{id}/preview` com `previewRun=true`) contra um app de exemplo,
antes de publicar uma tag.

Terraform (módulo em `sandbox/`, e mesmo fluxo aplicável a `manifests/terraform/`):

```bash
cd sandbox/Fibra.DevOps.Terraform/modules/aws_lambda_function
terraform fmt -check -recursive       # formatação
terraform init -backend=false         # plugins, sem tocar no state remoto
terraform validate                    # sintaxe + validations de variável
terraform test                        # suíte completa (exige Terraform >= 1.6)
terraform test -filter=tests/validations.tftest.hcl   # um arquivo de teste só
```

Os testes rodam **offline**: todos usam `command = plan`, com credenciais falsas e `skip_*` no
provider, então não criam nada na AWS e não exigem segredo. **Todos devem passar** — qualquer
falha é regressão.

# Arquitetura

## Fluxo de um run (roteamento por branch)

`templates/stacks/dotnet-backend.yaml` é o **entrypoint** e o único lugar que decide o caminho.
O roteamento é **compile-time** (`${{ if startsWith(variables['Build.SourceBranch'], ...) }}`),
ou seja, os stages que não pertencem à branch nem existem no run:

| Branch | Caminho |
|---|---|
| `develop` / `sandbox` | Validate → SonarQube → Build → Deploy DEV |
| `sandbox/*` | Validate → SonarQube → Build → Deploy **SDX** (infra de DEV, nomes isolados) |
| `release/X.Y.Z` | … → Build → Deploy HML + Veracode → **gate GMUD** → Deploy PRD → PR release→main |
| `hotfix/*` | … → Build → Veracode → Deploy PRD → aprovação → PR hotfix→main → delete da branch |
| qualquer, com `rollbackImageTag` preenchido | **só** `stages/rollback.yaml` (pula Sonar/Build) |

## Invariante de branches — `release/*` e `feature/*` nascem do `main`

**Não é convenção, é requisito do modelo.** A esteira **não faz back-merge** `main → develop`
(removido em `2.0.0`), e ela só continua correta porque a propagação para produção não passa
por `develop`:

- `release/X.Y.Z` é cortada do **`main`** e recebe apenas as features escolhidas para o GMUD.
  Como nasce do `main`, ela já contém todo hotfix e toda correção de estabilização anterior —
  é isso que dispensa o back-merge.
- `feature/*` também é cortada do **`main`**. Cortada de `develop`, o merge na release arrasta
  junto tudo que estava em `develop`, quebrando o isolamento do pacote de GMUD.
- `develop` é **sandbox de integração** (ambiente DEV) e **não é caminho para produção**. Ele
  diverge do `main` por natureza: acumula features que podem nunca subir e não recebe hotfixes.

**O que quebra se o invariante for violado:** cortar `release/*` de `develop` inverte o modelo —
a release passa a depender de `develop` estar atualizado, e sem back-merge o hotfix que está em
produção some da próxima release. O bug volta. Se alguém precisar mudar isso, o back-merge tem
de voltar junto.

**Ressincronizar `develop`** é tarefa fora da esteira (PR `main → develop` periódico, ou recorte
do `develop` a partir do `main` ao fechar cada release). Deliberadamente não automatizado: como
`main` e `develop` divergem por construção, o PR dá conflito com frequência — e resolver conflito
no meio de um deploy de produção era o que fazia o pipeline ficar vermelho **depois** de a versão
já estar no ar.

`release/*` roda em **CI com `batch: true`, mas só até HML**. `Deploy_prd` e `PR_Main` exigem
`Build.Reason == 'Manual'`: a promoção para produção é um "Run pipeline" selecionando a branch da
release, e é esse run que passa pelo approval do Environment `prd` (gate de GMUD). Mudança
expressa/emergencial não usa esse caminho — vai por `hotfix/*`, que sobe em PRD no próprio run de
CI. O `batch: true` é por branch: enquanto um run da release estiver em andamento, pushes seguintes
se acumulam num único run em vez de abrir execuções concorrentes.

O procedimento de promoção (para devs) e o checklist de configuração do portal do ADO — approvals,
Exclusive Lock, permissões, notificações — estão em [`PROMOCAO-PRD.md`](PROMOCAO-PRD.md).
**Checks de Environment não existem no YAML**: sem a configuração daquele checklist, o gate de GMUD
simplesmente não acontece e `Deploy_prd` sobe direto.

## O motor de deploy

`stages/deploy.yaml` é o **único** stage de deploy, parametrizado por `environment`. Ele carrega
`variables/env/<env>.yaml` por caminho dinâmico e delega para `deploy-backend.yaml`, que orquestra
os steps na ordem:

```
image-promote  →  copiar manifests/terraform  →  tfvars de runtime  →  terraform-apply
                                                    (init→validate→plan→apply)
               →  k8s-render (PLACEHOLDER_* + ConfigMap)  →  k8s-deploy (apply + annotations)
               →  record-prod-release   [somente prd]
```

Consequência prática: mudanças de comportamento de deploy quase sempre pertencem a um `steps/*`,
não ao stack nem ao stage.

## Contratos que quebram silenciosamente

- **O alias do repositório precisa ser `templates`.** `stages/deploy.yaml` faz
  `- checkout: templates` e os steps montam caminhos com `$(Build.SourcesDirectory)/templates`.
  Renomear o alias no app quebra o checkout interno.
- **`PLACEHOLDER_*`**: `k8s-render.yaml` falha se sobrar qualquer token não substituído **e**
  falha se algum valor de substituição chegar vazio. Adicionar um placeholder em
  `manifests/k8s/` exige adicionar a origem em `deploy-backend.yaml` (mapa `substitutions`) —
  o contrato está tabelado em `manifests/k8s/README.md`.
- **Manifests obrigatórios**: `deployment.yaml`, `service.yaml`, `hpa.yaml`, `configmap.yaml`,
  `ingress.yaml`. O `configmap-app-vars.yaml` é **gerado** a partir de `config.env_vars`.
- **Nomes de stage são referenciados por string** em `dependsOn` (`Build`, `Deploy_hml`,
  `Veracode`, `Deploy_prd`). Renomear um stage exige varrer os `dependsOn` do stack e do hotfix.
- **`backend.tf` é gerado** pela esteira (bucket `tfstate-<app>-<env>`, key `<app>/terraform.tfstate`).
  Nunca versionar `backend.tf` em `manifests/terraform/`.
- **`rollbackImageTag`**: default `'none'` no stack e `''` no app; o `if` testa os dois. Qualquer
  outro valor dispara rollback.

## Convenções de nomes derivados (não são parâmetros)

Derivam de variáveis do ADO em runtime — mudar isso afeta ECR, namespace e state:

- imagem/repositório ECR = `$(Build.Repository.Name)`; tag da imagem = `$(Build.BuildId)`
- namespace K8s = `<repo>-<env>`; bucket de state = `tfstate-<repo>-<env>`
- `app_name`/`namespace`/`project_name` entram no Terraform via `_app.auto.tfvars.json` gerado
  em runtime; os demais via `_pipeline.auto.tfvars.json` (qualquer `*.auto.tfvars.json` no
  diretório é carregado)
- **sandbox (`sdx`)**: os nomes acima já isolam por embutirem o env; o que **não** embute
  (IAM, log group do APIGW, DynamoDB, Secrets, SSM, `base_path`, nome da REST API) é sufixado
  via `resource_suffix` no Terraform (default `""`; `sdx` envia `-sdx` via `resourceSuffix`
  do `variables/env/sdx.yaml`). Recurso novo no `manifests/terraform/` com nome sem
  `var.environment` **deve** receber `${var.resource_suffix}`, senão colide com dev na conta
  compartilhada.

## Políticas centrais embutidas na esteira

- **Réplicas**: em `prd` usa `pod.min_replicas`/`max_replicas` do app (deve ser ≥ 2); em
  `dev`/`hml` a esteira **força 1 pod** (min=max=1). O objeto `pod` do app representa sizing de
  PRODUÇÃO. Decisão em `stages/deploy.yaml`, compile-time.
- **SSM por ambiente**: o app declara `config.ssm_parameters.{dev,hml,prd}` e o stack repassa
  apenas o do ambiente do stage.
- **Registro de deploy** (`steps/record-prod-release.yaml`, último step do stage — nunca
  bloqueia): roda em **prd e hml**, com perfis diferentes decididos em `stages/deploy.yaml`:
  - **prd** (perfil completo): carimba o run (`· prd` + build tags), resolve o **digest**, move a
    tag móvel `prod` no ECR, publica o artefato `prod-release`, sobe o resumo na aba **Summary**,
    grava a entrada no **`.deploy/history.jsonl`** do repo do app e **renderiza** o
    `DEPLOY-PRD.md` a partir desse JSONL (commit com `[skip ci]`; policy bloqueou → PR de
    `release-record/<buildId>`). Captura aprovador do gate via timeline→approvals
    (**best-effort, ainda não validado em run real** — falha vira `approval: null`).
  - **hml** (perfil reduzido): linha no `history.jsonl` + artefato `hml-release` + re-render do
    `DEPLOY-PRD.md` (`prodTag: ''`, `stampRun/captureApproval: false`; `updateMarkdown` fica no
    default `true`). Existe para decompor o lead time DORA (`commit → hml → prd`).
  - O `DEPLOY-PRD.md` é **função pura do JSONL**: "Último deploy" = última entrada `prd` (nunca
    as variáveis do run — é o que permite ao hml re-renderizar sem corromper os dados de
    produção), "Histórico" = `prd` (50), "Homologação" = `hml` (20).
  - Parâmetros: `environment` (`prd`), `historyFile` (`.deploy/history.jsonl`), `updateMarkdown`,
    `captureApproval`, além dos anteriores; `prodTag: ''` = não mover tag móvel. `deployType`
    distingue `deploy` × `hotfix` × `rollback`. Schema (`schema_version: 1`) e consultas `jq` de
    métricas: ver entrada `2.1.0` do `CHANGELOG.md`.
  - **Pré-requisito**: a service connection de **hml** precisa de `ecr:DescribeImages` e
    `ecr:BatchGetImage` (hoje só a de prd tem) — sem isso, `digest: null` + warning.
- **Rollback rastreado**: `stages/rollback.yaml` faz `kubectl set image` para uma tag que já
  existe no ECR, passando pelo Environment `prd` (mesmo gate de GMUD) — assim o painel
  Environments do ADO continua refletindo o que está live.
- **Annotations de rastreabilidade** no Deployment: `deploy.fibra.io/{build-id,commit,branch,triggered-by}`
  e, no rollback, `deploy.fibra.io/{rollback,image-tag}`.

## Débitos conhecidos (não redescobrir; não tratar como decisão de design)

- **`rollout-verify` desativado**: deploy fica verde mesmo com pod em CrashLoop.
  Reativação é o débito #1 da esteira.
- **Rollback sem undo automático** se a versão restaurada não ficar saudável.
- **Segredos em texto plano** em `variables/env/*.yaml` — migração para Azure Key Vault
  via variable group pendente. Ao mexer nesses arquivos, não introduza segredos novos.
- **Sem scan de imagem de container** (Trivy / ECR enhanced scanning) na esteira.
- **`GIT_PAT` de longa duração** no variable group `git-credentials` — sem rotação
  automática; alternativa desejada é token efêmero ou artefato de módulo versionado.
- **Terraform sem state locking** (decisão de 2026-08: não resolver agora): o `backend.tf`
  gerado em `steps/terraform-apply.yaml` não tem `use_lockfile` nem `dynamodb_table`, e o
  `-lock-timeout=5m` é inócuo sem backend de lock. O `batch: true` do trigger mitiga **apenas**
  colisão entre runs de CI da mesma branch. **Risco residual**: run manual de promoção disparado
  com run de CI da mesma release em andamento → dois `terraform apply` no mesmo
  `tfstate-<app>-hml`; state corrompido é recuperação manual. O Exclusive Lock no Environment
  `hml` (portal, ver `PROMOCAO-PRD.md`) é a proteção que cobre esse caso.

## Variáveis e segredos

`templates/variables/env/{dev,hml,prd,sdx}.yaml` — mesmos **nomes** nos quatro, só os valores
mudam (`serviceAccount`, `clusterName`, `awsRegion`, `awsAccID`, ARNs de ALB/certificado, VPC
link…). Ao adicionar uma variável, adicione **nos quatro arquivos**, senão o deploy de um
ambiente quebra em tempo de compilação. `sdx` reusa a infra de DEV (conta/cluster) e é o único
com `resourceSuffix: '-sdx'`; seu `albSharedDns`/`albSharedListener` exigem bootstrap (ALB do
grupo `sdx-eks-shared-alb`, criado no primeiro deploy — ver cabeçalho do `sdx.yaml`).

`setup-git-auth.yaml` consome `GIT_PAT` do variable group **`git-credentials`** (declarado em
`stacks/dotnet-backend.yaml`) para o `terraform init` conseguir clonar os módulos privados via
`git::https://dev.azure.com/bancofibra/...`. Sem esse grupo vinculado ao pipeline do app, o
deploy falha no init.

## Terraform

`manifests/terraform/` é o **root module** da aplicação (API Gateway público ou privado conforme
`api_type`, IAM role + EKS Pod Identity, SSM, DynamoDB, S3, SQS/SNS, Secrets, Lambda). Ele
referencia módulos reutilizáveis do repositório **separado** `Fibra.DevOps/Fibra.DevOps.Terraform`
por `source = "git::https://..."`. Recursos públicos/privados usam `count` sobre
`local.is_public` / `local.is_private`.

`sandbox/` é cópia local de trabalho de módulos daquele outro repositório (hoje
`aws_lambda_function`, com suíte `terraform test` e README extenso). **Não é consumido pela
esteira** — o `source` aponta para o repositório remoto. O `.gitignore` bloqueia
`sandbox/.validate/` e `**/*override.tf` justamente para que o override que troca `source` por
caminho local nunca vaze para `manifests/terraform/` e quebre PRD.

# Versionamento e mudanças

- Plataforma versionada por **tags imutáveis** (`vX.Y.Z`); apps pinam `ref: refs/tags/vX.Y.Z`,
  **nunca** `refs/heads/main`. Bump é deliberado por app.
- Critério de MAJOR/MINOR/PATCH e o histórico completo estão em `CHANGELOG.md` — atualize-o ao
  mudar contrato de parâmetros ou fluxo de stages.
- Remover/renomear parâmetro de `stacks/*` ou de `deploy-backend.yaml` é **breaking change**:
  todo app pinado que subir de tag quebra no parse. Prefira parâmetro novo com default.
- O `README.md` e a pasta `docs/` foram removidos **de propósito** — não recriar. Este `CLAUDE.md`
  e o `CHANGELOG.md` são a documentação corrente. O conteúdo antigo (arquitetura da paved road,
  fluxo de release, plano de migração das variáveis) segue no histórico, se precisar consultar:
  `git show 914994f:README.md`, `git show 914994f:docs/ARQUITETURA-TEMPLATES.md`.
