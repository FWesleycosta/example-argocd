## [1.3.2] - 2026-08-03

Correção de robustez no registro de release em PRD. O step deixa de poder reprovar um deploy que
já subiu com sucesso, e as falhas de registro passam a nomear a permissão que faltou.
**Nenhuma mudança de contrato**: nenhum parâmetro adicionado, removido ou renomeado; nenhum
stage, `dependsOn` ou condição alterada.

### Corrigido

- **`steps/record-prod-release.yaml` não era best-effort, apesar do princípio estar documentado
  no próprio arquivo.** A task principal roda sob `set -euo pipefail` e não tinha
  `continueOnError`: uma falha em `aws ecr describe-images` — permissão `ecr:DescribeImages`
  ausente, imagem já removida pela lifecycle policy, throttling do ECR — matava o script e
  reprovava o stage `Deploy_prd` **depois** de o `kubectl apply` ter subido a versão com sucesso.
  Resultado: cluster atualizado e saudável, painel vermelho, e o Environment `prd` registrando
  como falha uma implantação que funcionou. Pior efeito colateral: `PR_Main` e
  `BackMerge_Develop` dependem de `Deploy_prd` com `succeeded()` e não rodavam — a release ficava
  em produção sem chegar à `main` nem à `develop`. A task passa a ter `continueOnError: true`.
- **Leitura do digest guardada.** Falha vira warning citando a permissão e o registro segue com
  `image_digest` vazio, em vez de abortar — `latest.json`, `latest.md` e `DEPLOY-PRD.md`
  continuam sendo gerados. O retorno `"None"` do `--query` (que sai com código 0 quando o
  JMESPath não encontra nada) passa a ser tratado como falha, em vez de virar digest literal no
  registro. `image_ref_by_digest` fica vazio nesse caso, em vez da string truncada
  `<registry>/<repo>@`.
- **Leitura do manifesto (`aws ecr batch-get-image`) guardada.** Antes era captura direta sob
  `set -e` e matava o step inteiro.
- **Falha de `ecr:PutImage` deixa de se disfarçar de operação normal.** Quando o `put-image`
  recusava, o step imprimia `"Tag 'prod' já aponta para este digest (nada a fazer)"` — mensagem
  correta para `ImageAlreadyExistsException`, mas **idêntica** no caso de permissão negada. A tag
  móvel `prod` podia ficar congelada numa versão antiga com o log dizendo que estava tudo certo —
  defeito que só se manifesta durante um incidente, quando alguém usa a tag para escolher o alvo
  do rollback. Os dois casos passam a ser distinguidos pelo erro retornado pelo ECR: o benigno
  mantém a mensagem informativa; o resto vira warning citando `ecr:PutImage`.

### Notas de adoção

- **O stage passa a exibir "succeeded with issues"** quando o registro falha, e a implantação
  aparece como *partially succeeded* no Environment. `succeeded()` continua verdadeiro para esse
  resultado, então `PR_Main` e `BackMerge_Develop` seguem rodando normalmente.
- Ausência de registro deixa de ser silenciosa: todo caminho de falha emite `##[warning]` nomeando
  a permissão ou a condição que faltou, com os 500 primeiros caracteres do erro do ECR.
- **Revise as permissões da service account de PRD** na primeira execução após adotar esta versão.
  Warnings que antes apareciam como falha de stage (ou não apareciam) ficam visíveis agora:
  `ecr:DescribeImages`, `ecr:BatchGetImage` e `ecr:PutImage`.
- `update_release_log` já estava protegida (chamada em `||`, o que suspende o `set -e` dentro da
  função) — nada muda naquele bloco, inclusive no `curl` de criação de PR.
- A geração dos arquivos (`jq` / `latest.*`) segue sem guarda própria por decisão: não é chamada
  externa e o `continueOnError` da task já cobre.
- Vale igualmente para o **rollback**, que usa o mesmo step via `stages/rollback.yaml`. Sem efeito
  em `dev`/`hml`, onde o step não é invocado.
