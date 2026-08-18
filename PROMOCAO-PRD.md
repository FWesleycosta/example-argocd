# Promoção para produção

Documento operacional da esteira a partir da versão **2.0.0**.

- **Parte 1 — Runbook do dev**: como promover uma release para PRD. Leitura obrigatória antes da
  primeira promoção.
- **Parte 2 — Configuração do Azure DevOps**: o que o administrador configura **no portal**
  (checks de Environment não vivem no YAML). Setup único por projeto.

---

# Parte 1 — Runbook: como promover sua release para PRD

## Quando este caminho se aplica

| Situação | Caminho | Este runbook? |
|---|---|---|
| Fechar a versão e subir o pacote do GMUD | **promoção manual da `release/X.Y.Z`** | ✅ sim |
| Corrigir algo urgente em produção | `hotfix/*` (sobe em PRD no run automático) | ❌ não |
| Voltar produção para uma versão anterior | Run pipeline com `rollbackImageTag` preenchido | ❌ não |
| Validar o pacote em HML | acontece sozinho a cada merge na release | ❌ não precisa |

## Pré-condições

Antes de disparar a promoção, confirme:

- [ ] **A release está fechada** — todas as features do GMUD já mergeadas na `release/X.Y.Z`.
      Depois de disparar, merges novos **não** entram nesta subida.
- [ ] **A QA validou a HML** — a HML é implantada a cada merge na release, então ela já reflete o
      pacote. É exatamente esta imagem que vai para produção, sem rebuild.
- [ ] **O último run de CI da branch está verde** — Sonar, Build, Deploy HML e Veracode.
      Se estiver vermelho, corrija antes: a promoção vai repetir a mesma falha.
- [ ] **A GMUD está aberta** e você sabe a janela de mudança.

## Passo a passo

1. Azure DevOps → **Pipelines** → pipeline da sua aplicação → **Run pipeline**.
2. Em **Branch/tag**, selecione a branch da release: `release/X.Y.Z`.
   *(Selecionar `develop` ou `main` aqui não promove nada — o caminho de PRD só existe em
   `release/*`.)*
3. Deixe **"Rollback PRD: tag/versão a restaurar"** **vazio**. Preenchido, o run vira rollback e
   pula Sonar/Build/HML.
4. **Run**.

O run executa `Validate → SonarQube → Build → Deploy HML → Veracode` e **para** em `Deploy_prd`,
aguardando aprovação.

> **Por que o run repete Build e HML?** Porque a promoção é um run completo, e é ele que carrega
> a evidência de ponta a ponta para a auditoria do GMUD. A imagem que sobe em PRD é a construída
> neste run — a mesma que passou pela HML dele.

## O que acontece no gate

`Deploy_prd` está vinculado ao **Environment `prd`**, que tem um check de aprovação. O run fica em
*Waiting* até alguém aprovar.

- **Quem aprova:** tech leads das squads + time de sustentação. Basta **um** do grupo.
- **Você não pode aprovar o seu próprio run.** A opção *"aprovadores podem aprovar os próprios
  runs"* está desligada de propósito — quem promove não é quem autoriza.
- **Prazo:** 7 dias. Sem aprovação nesse período o run é **cancelado**.

### Alinhar a aprovação à janela de GMUD (deferred approval)

Não é preciso alguém estar disponível no minuto exato da janela. Ao aprovar, o aprovador pode
**adiar o efeito da aprovação** para uma data/hora futura: ele aprova hoje, informa o horário da
janela, e o run segue sozinho naquele momento.

⚠️ **O adiamento tem de caber dentro dos 7 dias do timeout.** Agendar para além disso faz o run
expirar antes de executar.

### Enquanto espera aprovação

**Não faça novos merges na `release/X.Y.Z`.** Eles não entram nesta subida — a imagem já foi
construída — e o resultado é uma branch de release com conteúdo que não está em produção. Se
precisar mesmo incluir algo, cancele o run, mergeie e dispare uma nova promoção.

## Se o approval expirar

O run é cancelado. **Nada foi para produção** — o `Deploy_prd` nem chegou a iniciar. Não é
incidente, não gera GMUD de emergência, não precisa de rollback.

Para retomar: repita o passo a passo. Um run novo é gerado, com imagem nova a partir do estado
atual da branch.

## Depois da promoção

Concluído o `Deploy_prd`, a esteira ainda:

1. **Registra o release em produção** — move a tag `prod` no ECR para o digest que subiu, publica
   o artefato `prod-release` e atualiza o `DEPLOY-PRD.md` na raiz do repositório da aplicação.
2. **Abre e conclui o PR `release/X.Y.Z → main`** automaticamente, com merge commit verdadeiro
   (sem squash).

E — importante — **a `develop` não recebe nada.** A esteira não faz back-merge `main → develop`.
Isso é intencional: como toda `release/*` nasce do `main`, o que está em produção já entra na
próxima release por construção. A `develop` é sandbox do ambiente DEV e ressincroniza fora da
esteira (PR `main → develop` periódico, ou recorte da `develop` a partir do `main` ao fechar cada
release).

> **Consequência prática:** não estranhe a `develop` estar "atrás" da produção. É o desenho. O que
> **não** pode acontecer é alguém cortar uma `release/*` ou uma `feature/*` a partir da `develop` —
> aí o modelo inverte e correções somem da próxima release. Toda branch nasce do `main`.

## Se algum stage falhar

| Stage vermelho | Produção afetada? | O que fazer |
|---|---|---|
| `Validate`, `SonarQube`, `Build` | não | corrigir na release e disparar de novo |
| `Deploy_hml` | não | investigar HML; PRD não iniciou |
| `Veracode` | não | tratar os findings; PRD não iniciou |
| `Deploy_prd` | **possivelmente** | verificar o cluster; considerar rollback pela tag anterior |
| `PR_Main` | **não** — produção está no ar | concluir o PR `release → main` manualmente |

O `PR_Main` é o último stage: vermelho ali significa que a versão **está em produção** e só faltou
registrar o merge em `main`. Não faça rollback por causa disso.

---

# Parte 2 — Configuração do Azure DevOps (portal)

Checks de Environment, permissões e notificações **não existem no YAML** — são configuração do
projeto. Sem eles, o fluxo da 2.0.0 não funciona como descrito.

## O que é repositório × o que é portal

| Camada | Onde | Exemplos |
|---|---|---|
| Fluxo de stages, condições, dependências | **repositório** (`templates/`) | `Build.Reason == 'Manual'`, `dependsOn` |
| Trigger e `batch` | **repositório da aplicação** | `azure-pipelines.yml` |
| **Gate de GMUD, locks, permissões, notificações** | **portal do ADO** | tudo abaixo |

## Environment `prd`

**Pipelines → Environments → `prd` → Approvals and checks**

- [ ] **Approvals** — adicionar check:
  - **Approvers**: grupo com tech leads das squads + time de sustentação.
  - **Qualquer um do grupo aprova** (não exigir todos). Exigir unanimidade transforma férias de
    uma pessoa em bloqueio de produção.
  - **"Allow approvers to approve their own runs"**: **DESLIGADO**. Quem dispara a promoção não
    autoriza a si mesmo — é o que sustenta a segregação de função no GMUD.
  - **Timeout**: **7 dias**.
  - **Instructions**: link do procedimento de GMUD e da Parte 1 deste documento.
- [ ] *(Opcional)* **Business Hours**, se houver janela formal de mudança e vocês quiserem impedir
      execução fora dela mesmo com aprovação dada.

## Environment `hml`

- [ ] **Exclusive Lock** — serializa deploys concorrentes em HML.
- [ ] **SEM approval.** HML é contínua por desenho; um approval ali pararia todo run de CI e
      anularia o feedback rápido que o trigger em `release/*` existe para dar.

> O Exclusive Lock é a única proteção contra dois `terraform apply` simultâneos no mesmo state de
> HML — ver "Débitos conhecidos" no `CLAUDE.md`.

## Permissões

- [ ] **Queue do pipeline** — liberar para **todos os devs dos squads** (Contributors).

  *Racional:* o controle de produção é o **approval do Environment**, não o botão de disparo.
  Restringir quem dispara não adiciona segurança — todo run ainda passa pelo mesmo gate — e cria
  gargalo em pessoa. Promoção é **self-service**; a autorização é que é controlada.

  *Alternativa, se optarem por transição gradual:* restringir a DevOps + tech leads nas primeiras
  releases e abrir depois. Custo: promoção deixa de ser self-service e o time de plataforma vira
  intermediário de agenda.

- [ ] **Build Service** no repositório da aplicação:
  - **Contribute** e **Contribute to pull requests** — para o registro em `DEPLOY-PRD.md` e para
    os PRs automáticos.
  - **Bypass policies when completing pull requests** = **Allow**, na branch `main`.
    Sem isso o `PR_Main` falha **com produção já implantada**: a esteira conclui o PR usando
    `--bypass-policy true`, e a permissão é o que autoriza esse bypass.

## Notificações

- [ ] Assinatura para **approval expirado**. Com timeout de 7 dias, o modo de falha mais provável
      é o silencioso: ninguém aprova, o run é cancelado, e a release fica parada sem que nenhum
      alarme dispare. Sem essa notificação, a descoberta acontece na reunião de GMUD seguinte.
- [ ] *(Recomendado)* Assinatura para **falha de stage em `prd`**.

## Verificação do setup

Depois de configurar, valide com uma release de teste:

1. Push numa `release/0.0.1-teste` → deve rodar até HML e **parar** (sem pedir aprovação).
2. Run pipeline manual na mesma branch → deve **pedir aprovação** no `Deploy_prd`.
3. Tentar aprovar com o mesmo usuário que disparou → deve ser **recusado**.
4. Deixar expirar (ou cancelar) → confirmar que a notificação chega.
