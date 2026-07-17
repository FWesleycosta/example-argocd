## [1.1.0] - 2026-07-17

### Adicionado

- **Registro rastreável de releases em PRD** (`templates/steps/record-prod-release.yaml`), injetado automaticamente pela esteira em todo caminho que toca produção (release, hotfix e rollback — o app não configura nada):
  - **`DEPLOY-PRD.md` na raiz do repositório da aplicação**: seção "Último deploy" (situação deploy/hotfix/rollback, data, imagem/tag ECR, digest, commit + mensagem, link do run, autor) sobrescrita a cada subida, e seção "Histórico" acumulando as últimas 50 entradas. O commit entra na branch deployada com `[skip ci]` e chega à `main`/`develop` pelos PRs que a esteira já abre; se o push for bloqueado por branch policy (ex.: rollback executado na `main`), o registro é publicado na branch `release-record/<buildId>` e um PR é aberto automaticamente via REST.
  - **Resumo na aba Summary do run** (`task.uploadsummary`) e **artefato `prod-release`** com `latest.json` (estruturado, para automação), `latest.txt` e `latest.md`.
  - **Tag móvel `prod` no ECR** sempre apontando para o digest em produção (o rollback reaponta a tag para a imagem restaurada).
  - **Carimbo do run**: Build Number ganha sufixo `· prd` e tags `prod`/`<app>`, permitindo filtrar na lista de runs o que foi para produção.
  - Parâmetros: `deployType` (`auto` distingue deploy × hotfix pelo branch; rollback é explícito), `updateReleaseLog`, `recordBranch`, `prodTag`, `stampRun`.

### Alterado

- `templates/stages/deploy.yaml`: passa a incluir o `record-prod-release.yaml` em compile-time quando `environment == prd` (DEV/HML não são afetados).

### Notas de adoção

- **Azure DevOps**: usuário *Build Service* com permissão **Contribute** e **Contribute to pull requests** no repositório do app; opção *"Allow scripts to access the OAuth token"* habilitada (ambos já necessários aos PRs automáticos da esteira).
- **AWS (conta PRD)**: a service account precisa de `ecr:DescribeImages`, `ecr:BatchGetImage` e `ecr:PutImage` (leitura do digest + tag móvel `prod`).
- O `[skip ci]` no commit do registro é o que impede o redisparo da esteira em `hotfix/*`; não remova.
- Registro é **best-effort**: falha em qualquer etapa do registro vira warning e não bloqueia o deploy.
