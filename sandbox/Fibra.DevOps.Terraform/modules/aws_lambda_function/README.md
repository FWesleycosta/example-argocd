# Módulo `aws_lambda_function`

> Este módulo cria uma função **AWS Lambda** já pronta para produção: com o registro de
> logs configurado, com prazo de descarte desses logs definido e com uma série de
> verificações que barram configurações erradas **antes** de qualquer coisa ser criada
> na AWS.

**O que é uma Lambda?** É um jeito de rodar um pedaço de código na nuvem sem ter um
servidor ligado esperando.

**E o que é este módulo?** É um "formulário padrão" para pedir uma dessas funções. Em vez
de cada time preencher 30 campos na AWS e esquecer metade, o time preenche 5 campos aqui e
o resto vem certo por padrão.

---

## Para quem é este documento

| Se você é… | Leia | Vai conseguir |
|---|---|---|
| **Gestão / Produto** | ["O que este módulo faz"](#o-que-este-módulo-faz) e ["Quanto custa"](#quanto-custa) | Entender o que a equipe está usando e o que gera custo. |
| **Arquitetura** | ["O que este módulo faz"](#o-que-este-módulo-faz), ["Conceitos"](#conceitos-por-que-funciona-assim) e ["Limitações conhecidas"](#limitações-conhecidas) | Avaliar se o módulo atende o padrão da casa e onde ele ainda é curto. |
| **Dev (usa, mas não é de infra)** | ["Início rápido"](#início-rápido-5-minutos) e ["Guias práticos"](#guias-práticos) | Colocar sua função no ar copiando exemplos prontos. |
| **DevOps júnior/pleno** | O documento inteiro | Operar o módulo com segurança e entender por que ele barra o que barra. |
| **Tech lead** | ["Referência"](#referência-completa), ["Testes automatizados"](#testes-automatizados) e ["Limitações"](#limitações-conhecidas) | Revisar PRs e saber o que o módulo garante e o que não garante. |

> **Aviso de mudança incompatível.** Os nomes das saídas do módulo mudaram. Se o seu código
> usa `module.x.arn`, `module.x.function_name` ou qualquer nome em minúsculas, ele **vai
> quebrar**. Veja [Migração dos nomes de saída](#migração-dos-nomes-de-saída).

---

## O que este módulo faz

Ele cria **três coisas** (duas, no caso de container):

| O que é criado | Em linguagem simples | Quando |
|---|---|---|
| A função Lambda | O seu código, hospedado e pronto para ser chamado. | Sempre (se o módulo estiver ligado). |
| Um "log group" no CloudWatch | O caderno onde a função anota tudo que acontece — erros, mensagens, tempo de execução. O módulo já define **por quantos dias** essas anotações são guardadas. | Sempre (se o módulo estiver ligado). |
| Uma configuração de atualização de runtime | Uma regra dizendo *quando* a AWS pode atualizar a versão da linguagem (Python, .NET, Node…) que sua função usa. | Apenas com `package_type = "Zip"`. Container não tem runtime gerenciado. |

> **Por que o log group importa tanto?** Se ninguém criar esse caderno, a AWS cria um
> sozinha na primeira vez que a função roda — e sem prazo de validade. As anotações ficam
> lá para sempre, sendo cobradas para sempre. O módulo cria antes, com prazo definido.

### O que o módulo não faz

Esta é a parte mais importante para não haver surpresa. O módulo é **deliberadamente
estreito**: ele cria a função e o caderno de logs. Tudo abaixo é responsabilidade de quem
usa o módulo:

| Não faz | O que isso significa na prática |
|---|---|
| Não cria a permissão de acesso (IAM role) | Você precisa criar o "crachá" da função separadamente e passar o identificador dele em `role`. |
| Não anexa nenhuma política de permissão | Se a função precisa ler um segredo, escrever no log ou acessar uma fila, **você** concede isso na role. |
| Não cria gatilhos (triggers) | Nada faz a função ser chamada. Conectar a uma fila SQS, a um bucket S3 ou a uma API é passo separado. |
| Não cria `aws_lambda_permission` | Para o API Gateway poder chamar a função, você declara essa permissão à parte (veja o [guia](#como-conectar-a-função-a-uma-api-api-gateway)). |
| Não cria aliases nem faz deploy gradual (canário) | Não há blue-green nem canário embutidos. |
| Não cria alarmes nem dashboards | Monitoramento e alertas ficam fora. |
| Não cria a VPC, subnets ou security groups | Ele apenas **usa** os que você informar. |
| Não empacota seu código | Gerar o arquivo `.zip` é trabalho da esteira de build, não do Terraform. |

> **Onde procurar quando a função falha com "AccessDenied" em produção:** na role, não no
> módulo. Como o módulo não anexa política nenhuma, toda permissão de runtime — inclusive
> a de escrever no próprio log group e a de criar interfaces de rede quando a função roda
> na VPC — precisa já existir na role que você passou.

---

## Antes de começar (pré-requisitos)

- [ ] **Terraform instalado.** Baixe em [developer.hashicorp.com/terraform/install](https://developer.hashicorp.com/terraform/install).
      Confira com `terraform version`.
      O módulo exige **>= 1.3.0**, declarado em `versions.tf`. Verificado nas versões
      1.3.0, 1.5.7 e 1.9.8.
- [ ] **Uma conta AWS e credenciais configuradas** na sua máquina ou na esteira. Sem isso o
      `terraform plan` falha. Teste com `aws sts get-caller-identity`.
- [ ] **Acesso ao repositório Azure DevOps** de onde o módulo é baixado — o campo `source`
      aponta para lá.
- [ ] **Uma IAM role já criada** para a função usar. O módulo não cria essa role.
- [ ] **Seu código empacotado num arquivo `.zip`** (para o modo padrão). O Terraform não
      empacota nada; ele apenas envia o arquivo pronto.

**Glossário rápido para esta seção:** *Terraform* é a ferramenta que descreve
infraestrutura em arquivo de texto e a cria na nuvem. *IAM role* é o crachá que diz o que
a função tem permissão de fazer. Os dois estão no [Glossário](#glossário) completo.

---

## Início rápido (5 minutos)

O objetivo aqui é sair do zero e ver o Terraform aprovar sua configuração.

### 1. Crie uma pasta e entre nela

```bash
mkdir minha-lambda && cd minha-lambda
```

### 2. Crie o arquivo `main.tf`

Copie exatamente o conteúdo abaixo, trocando apenas os valores comentados:

```hcl
# Diz em qual região da AWS tudo será criado.
provider "aws" {
  region = "sa-east-1" # São Paulo
}

module "minha_funcao" {
  # De onde o módulo vem. O "?ref=" trava a versão — veja a dica abaixo.
  source = "git::https://dev.azure.com/bancofibra/Fibra.DevOps/_git/Fibra.DevOps.Terraform//modules/aws_lambda_function?ref=v2.0.0"

  function_name = "minha-primeira-funcao"          # nome da função na AWS
  role          = aws_iam_role.lambda_exec.arn     # o "crachá" que você já criou

  handler  = "index.handler"                       # qual função do seu código roda primeiro
  runtime  = "python3.12"                          # a linguagem e versão
  filename = "${path.module}/dist/pkg.zip"         # caminho do seu .zip

  # SEM ESTA LINHA, TROCAR O CÓDIGO NÃO ATUALIZA NADA. Veja "Conceitos".
  source_code_hash = filebase64sha256("${path.module}/dist/pkg.zip")
}
```

> **Sempre trave a versão no `?ref=`.** Sem isso, o módulo pode mudar de comportamento
> amanhã sem você ter alterado uma linha sequer do seu código. Como as saídas já mudaram de
> nome uma vez, essa trava é o que separa um deploy tranquilo de um pipeline vermelho.

### 3. Baixe o módulo e os plugins

```bash
terraform init
```

**Resultado esperado:** termina com `Terraform has been successfully initialized!`.

**Se aparecer `Could not download module` ou erro de autenticação:** você não tem acesso
ao repositório Azure DevOps. Peça acesso ao time de DevOps e confira se seu Git está
autenticado (`git ls-remote <url do repo>` deve funcionar).

### 4. Confira se a configuração está válida

```bash
terraform validate
```

**Resultado esperado:** `Success! The configuration is valid.`

**Se aparecer `Invalid value for variable`:** você passou um valor fora da lista
permitida. A mensagem diz qual variável e qual valor — compare com a
[tabela de referência](#parâmetros-opcionais).

### 5. Veja o que será criado (sem criar nada ainda)

```bash
terraform plan
```

**Resultado esperado:** uma lista terminando em `Plan: 3 to add, 0 to change, 0 to destroy`
— a função, o log group e a configuração de atualização de runtime. Com
`package_type = "Image"` são 2, porque container não tem runtime gerenciado.

**Se aparecer `InvalidClientTokenId` ou `retrieving caller identity from STS`:** suas
credenciais da AWS não estão configuradas ou expiraram. Rode `aws sts get-caller-identity`
para confirmar.

**Se aparecer `Resource precondition failed`:** o módulo barrou sua configuração de
propósito. A mensagem explica exatamente o que corrigir — a lista completa está em
[Regras que barram o plan](#regras-que-barram-o-plan).

### 6. Crie de verdade

```bash
terraform apply
```

Ele mostra o plano novamente e pede confirmação. Digite `yes`.

**Resultado esperado:** `Apply complete! Resources: 3 added, 0 changed, 0 destroyed.`

---

## Guias práticos

Receitas objetivas, uma por tarefa. Todas assumem que você já fez o [Início rápido](#início-rápido-5-minutos).

### Como fazer a função acessar o banco de dados (rodar dentro da VPC)

**Quando você precisa disso:** sua função precisa falar com um banco RDS, um Redis
(ElastiCache) ou qualquer coisa que não tenha endereço público na internet.

**VPC** é a rede privada da empresa dentro da AWS — como a rede interna de um escritório.
Por padrão a função roda **fora** dessa rede.

```hcl
module "ledger_sync" {
  source = "git::https://dev.azure.com/bancofibra/Fibra.DevOps/_git/Fibra.DevOps.Terraform//modules/aws_lambda_function?ref=v2.0.0"

  function_name = "ledger-sync"
  role          = aws_iam_role.lambda_exec.arn

  handler          = "app.lambda_handler"
  runtime          = "python3.12"
  filename         = "${path.module}/dist/pkg.zip"
  source_code_hash = filebase64sha256("${path.module}/dist/pkg.zip")

  memory_size = 512
  timeout     = 60

  # Os DOIS são obrigatórios juntos — a AWS exige, e o módulo confere.
  subnet_ids         = ["subnet-0a1b2c3d", "subnet-4e5f6a7b"]
  security_group_ids = ["sg-0123456789abcdef0"]
}
```

**Se aparecer `Para rodar a Lambda na VPC informe subnet_ids E security_group_ids`:**
você passou só um dos dois. Preencha os dois.

**Atenção — a role precisa de permissão de rede.** Para rodar na VPC, a função cria
interfaces de rede. Sem as permissões de ENI na role, o `apply` até funciona, mas a função
falha na primeira execução.

> **Isso custa caro.** Uma função dentro da VPC precisa de um **NAT Gateway** para
> alcançar serviços públicos da AWS. O NAT costuma custar mais que a própria função. Só
> coloque na VPC se realmente houver um destino privado.

### Como passar configurações e segredos para a função

Use `environment` para configurações. Elas chegam ao seu código como variáveis de ambiente.

```hcl
environment = {
  APP_ENV       = "prd"
  LOG_LEVEL     = "INFO"
  DB_SECRET_ARN = aws_secretsmanager_secret.db.arn  # o ENDEREÇO do segredo, não o segredo
}
```

**Nunca coloque senha, token ou chave aqui.** Mesmo o módulo marcando essa variável como
sensível (o valor não aparece no `plan`), o conteúdo fica **legível na AWS** para qualquer
pessoa que consiga ver a configuração da função. Guarde o segredo no Secrets Manager e
passe aqui apenas o endereço (ARN) dele; seu código busca o valor ao rodar.

A role precisa de `secretsmanager:GetSecretValue` sobre esse ARN. O módulo **não** concede
isso — você adiciona na role.

### Como reaproveitar bibliotecas entre funções (layers)

Uma **layer** é um pacote de bibliotecas compartilhado entre várias funções — como uma
estante comum de onde várias pessoas pegam o mesmo livro, em vez de cada uma comprar o seu.

Há duas formas, e elas podem ser combinadas:

```hcl
# Forma 1: pelo NOME — o módulo descobre o endereço sozinho.
layers = [
  { name = "common-utils" },              # sem versão = sempre a mais recente
  { name = "db-drivers", version = 7 },   # versão travada
]

# Forma 2: pelo endereço completo — para layers de terceiros.
layer_arns = [
  "arn:aws:lambda:sa-east-1:464622532012:layer:Datadog-Extension:60",
]
```

**Se aparecer `A AWS permite no máximo 5 layers por função`:** some `layers` +
`layer_arns` — o total precisa ser 5 ou menos. A mensagem informa quantas você passou.

> **Layer sem `version` é um alvo móvel.** O módulo resolve para a versão mais recente
> *no momento do plan*. Um `apply` amanhã pode trocar a biblioteca sem nenhuma mudança sua.
> Em produção, sempre trave a versão.

### Como aplicar tags nos recursos

**Tags** são etiquetas coladas no recurso (time dono, ambiente, o que o seu time achar
útil). Elas ajudam a organizar e a saber de quem é cada gasto na fatura da AWS.

Preencha `tags` e pronto — o mesmo conjunto vai para a função **e** para o log group:

```hcl
tags = {
  Team = "pagamentos"
}
```

Repare que o exemplo **não** declara `ManagedBy`: o módulo já o adiciona sozinho. Suas tags
são **somadas** à base do módulo, não substituem. Em caso de chave repetida, a sua vence —
`tags = { ManagedBy = "Terragrunt" }` sobrescreve a base sem erro.

> **Dica para tags que valem para a esteira inteira.** Se uma chave deve ir para todos os
> recursos do ambiente, e não só para esta Lambda, prefira o bloco `default_tags` do
> provider AWS. Assim você não depende de cada chamada do módulo estar correta.
>
> Uma observação ao usar `default_tags`: essas tags são aplicadas pelo provider e aparecem
> no atributo `tags_all` do recurso, não em `tags`. Como o output `Tags` do módulo lê
> `tags`, elas não aparecem nele — o que não impede nada, mas engana quem usa o output para
> conferir governança. Verificado por teste.

> **O módulo não exige tag nenhuma.** Não há chave obrigatória: se você não passar `tags`,
> a função sai com apenas o `ManagedBy` da base. Se o seu time precisar tornar alguma chave
> obrigatória, isso hoje é feito fora do módulo (numa política de organização ou num wrapper
> da esteira).

### Como desligar a função sem apagar o código

Útil para funcionalidades experimentais ou recursos que só existem em certos ambientes:

```hcl
create_lambda_function = var.habilitar_experimental  # false = nada é criado
```

Com `false`, **zero recursos** são criados e todas as saídas devolvem `null`. Isso permite
continuar referenciando o módulo em outros lugares sem quebrar o código — há teste
automatizado cobrindo exatamente esse caminho.

### Como conectar a função a uma API (API Gateway)

O módulo **não** cria a permissão de invocação — ela é sua:

```hcl
# Autoriza o API Gateway a chamar a função. Sem isso, a API responde erro.
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = module.api_backend.Name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = module.api_backend.Invoke_ARN # <- Invoke_ARN, NAO ARN
}
```

> **Erro mais comum da integração:** usar `ARN` no lugar de `Invoke_ARN`. São endereços
> diferentes: `ARN` identifica o recurso; `Invoke_ARN` é o formato que API Gateway e ALB
> esperam para chamar a função.

**Atenção ao timeout:** o API Gateway corta a requisição em 30 segundos, independentemente
do que estiver em `timeout`. Não adianta configurar 300 se quem chama é o gateway.

### Como criar várias funções parecidas de uma vez

```hcl
locals {
  functions = {
    ingest    = { handler = "ingest.handler",    memory = 256,  timeout = 30 }
    transform = { handler = "transform.handler", memory = 1024, timeout = 300 }
    publish   = { handler = "publish.handler",   memory = 256,  timeout = 60 }
  }
}

module "pipeline_functions" {
  source   = "git::https://dev.azure.com/bancofibra/Fibra.DevOps/_git/Fibra.DevOps.Terraform//modules/aws_lambda_function?ref=v2.0.0"
  for_each = local.functions

  function_name = "data-pipeline-${each.key}"
  role          = aws_iam_role.lambda_exec.arn

  handler          = each.value.handler
  runtime          = "python3.12"
  filename         = "${path.module}/dist/${each.key}.zip"
  source_code_hash = filebase64sha256("${path.module}/dist/${each.key}.zip")

  memory_size = each.value.memory
  timeout     = each.value.timeout
}

output "arns_das_funcoes" {
  value = { for k, m in module.pipeline_functions : k => m.ARN }
}
```

### Como adotar o módulo numa função que já existe

Se a função já foi criada na mão, o log group dela provavelmente já existe também. O
`apply` vai falhar com *ResourceAlreadyExistsException*. Traga o log group para o Terraform
antes:

```bash
terraform import 'module.minha_fn.aws_cloudwatch_log_group.this[0]' /aws/lambda/minha-fn
```

*(Comando não executado nesta documentação — exige acesso à conta AWS real.)*

### Como validar suas mudanças localmente antes do PR

```bash
# 1. Verifica a formatação dos arquivos.
terraform fmt -check -diff

# 2. Baixa os plugins sem se conectar ao armazenamento de estado remoto.
terraform init -backend=false

# 3. Confere sintaxe e as regras de validação das variáveis.
terraform validate

# 4. Roda a suíte de testes do módulo (exige Terraform 1.6 ou superior).
terraform test
```

**Resultado esperado do passo 4:** `Success! 29 passed, 0 failed.`

---

## Referência completa

### Parâmetros obrigatórios

Tecnicamente eles têm valor padrão `null`, mas o módulo barra o `plan` se ficarem vazios.

| Nome | Tipo | Descrição em linguagem simples | Exemplo |
|---|---|---|---|
| `function_name` | `string` | O nome da função na AWS. Também define o nome do caderno de logs (`/aws/lambda/<nome>`). | `"order-processor"` |
| `role` | `string` | O endereço (ARN) do crachá de permissões. O módulo não cria a role nem anexa políticas. | `"arn:aws:iam::123456789012:role/lambda-exec"` |

Com `package_type = "Zip"` (o padrão), tornam-se obrigatórios também **`runtime`**,
**`handler`** e **`filename`**.

### Parâmetros opcionais

| Nome | Tipo | Padrão | Descrição em linguagem simples |
|---|---|---|---|
| `create_lambda_function` | `bool` | `true` | Liga/desliga o módulo inteiro. `false` = nada é criado. |
| `package_type` | `string` | `"Zip"` | Como o código é entregue: `"Zip"` (arquivo) ou `"Image"` (container). Validado. |
| `runtime` | `string` | `null` | Linguagem e versão. Ex.: `python3.12`, `nodejs20.x`, `dotnet8`. Obrigatório no Zip, proibido no Image. |
| `handler` | `string` | `null` | Qual função do seu código é chamada primeiro. Obrigatório no Zip, proibido no Image. |
| `filename` | `string` | `null` | Caminho do arquivo `.zip` na sua máquina/esteira. Obrigatório no Zip, proibido no Image. |
| `source_code_hash` | `string` | `null` | "Impressão digital" do zip. Sem ela o Terraform não percebe que o código mudou. |
| `image_uri` | `string` | `null` | Endereço da imagem de container no ECR privado. Obrigatório no Image, proibido no Zip. Formato validado. |
| `description` | `string` | `null` | Descrição livre da função, exibida no console da AWS. |
| `memory_size` | `number` | `128` | Memória em MB. A CPU cresce junto com a memória — subir memória muitas vezes **reduz** o custo total, pois a função termina antes. Faixa aceita pelo provider: 128–32768. |
| `timeout` | `number` | `30` | Tempo máximo de execução em segundos. Faixa aceita pelo provider: 1–900. |
| `ephemeral_storage` | `number` | `512` | Espaço de disco temporário (`/tmp`) em MB. Validado: 512–10240. Os primeiros 512 MB não são cobrados à parte. |
| `architectures` | `list(string)` | `["arm64"]` | Tipo de processador: `["arm64"]` ou `["x86_64"]`. Validado. O arm64 (Graviton) é mais barato, mas exige o pacote compilado para ARM. |
| `environment` | `map(string)` | `null` | Configurações entregues à função. Marcada como sensível. O bloco só é criado se o mapa não estiver vazio. |
| `tags` | `map(string)` | `{}` | Etiquetas aplicadas à função **e** ao log group. **Somam-se** à base do módulo (`ManagedBy = "Terraform"`); em caso de chave repetida, a sua vence. |
| `publish` | `bool` | `true` | Publica uma versão nova a cada mudança. Consome cota da conta — veja [Conceitos](#publish--true-consome-uma-cota-que-é-da-conta-inteira). |
| `tracing_config` | `string` | `"Active"` | Rastreamento detalhado (X-Ray): `"Active"` inicia um rastro na função; `"PassThrough"` apenas propaga o de quem chamou. Validado. |
| `log_retention_days` | `number` | `30` | Por quantos dias os logs são guardados. `0` = nunca expira. Lista fechada — veja abaixo. Validado. |
| `update_runtime_on` | `string` | `"FunctionUpdate"` | Quando a AWS pode atualizar a linguagem. **Só aceita `"FunctionUpdate"`** — veja [Conceitos](#update_runtime_on-aceita-um-único-valor). |
| `subnet_ids` | `list(string)` | `null` | Sub-redes da VPC. Exige `security_group_ids` junto. |
| `security_group_ids` | `list(string)` | `null` | Grupos de segurança (as "regras de firewall"). Exige `subnet_ids` junto. |
| `layers` | `list(object)` | `[]` | Bibliotecas compartilhadas, informadas por nome: `{ name, version (opcional) }`. |
| `layer_arns` | `list(string)` | `[]` | Bibliotecas compartilhadas, informadas por endereço completo. |

**Valores aceitos em `log_retention_days`:** 0 (nunca expira), 1, 3, 5, 7, 14, 30, 60, 90,
120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288 e 3653. Qualquer
outro número é rejeitado — a lista é fechada pela AWS, então 45 não vale mesmo parecendo
razoável.

### Saídas (outputs)

Valores que o módulo devolve para você usar em outros lugares do seu código. A convenção é
**inicial maiúscula, underscores preservados e acrônimos em caixa alta** (ARN, URI).

Todas devolvem `null` quando `create_lambda_function = false`.

| Nome | O que é |
|---|---|
| `ARN` | Endereço único da função na AWS. |
| `Name` | Nome da função. |
| `Invoke_ARN` | Endereço de **invocação** — use este no API Gateway e no ALB. |
| `Qualified_ARN` | Endereço incluindo o número da versão publicada. |
| `Version` | Última versão publicada (`"$LATEST"` se `publish = false`). |
| `Role` | Endereço do crachá anexado. |
| `Memory` | Memória configurada, em MB. |
| `Description` | Descrição da função. |
| `Image_URI` | Endereço da imagem de container. `null` quando `package_type = "Zip"`. |
| `Last_modified` | Data/hora da última alteração. |
| `Tags` | Etiquetas efetivamente aplicadas. |
| `Log_group_name` | Nome do caderno de logs criado pelo módulo. |
| `Log_group_ARN` | Endereço do caderno de logs. |

### Regras que barram o plan

O módulo tem duas camadas de proteção. **As duas foram verificadas pela suíte de testes.**

**Camada 1 — `validation`, por variável.** Roda cedo, olhando uma variável isolada.

| Variável | Só aceita |
|---|---|
| `package_type` | `Zip` ou `Image` |
| `image_uri` | Endereço de ECR **privado**, por tag ou por digest |
| `ephemeral_storage` | Entre 512 e 10240 |
| `tracing_config` | `Active` ou `PassThrough` |
| `log_retention_days` | A lista fechada da AWS (veja acima) |
| `architectures` | `x86_64` ou `arm64` |
| `update_runtime_on` | Apenas `FunctionUpdate` |

**Camada 2 — `precondition`, na combinação de variáveis.** Roda no `plan` e enxerga várias
variáveis ao mesmo tempo.

| # | O que é verificado | Mensagem quando falha |
|---|---|---|
| 1 | VPC ligada implica `subnet_ids` **e** `security_group_ids` preenchidos | *Para rodar a Lambda na VPC informe subnet_ids E security_group_ids…* |
| 2 | `layers` + `layer_arns` menor ou igual a 5 | *A AWS permite no máximo 5 layers por função. Você passou N.* |
| 3 | `function_name` não nulo | *function_name não pode ser nulo.* |
| 4 | `role` não nulo | *role não pode ser nulo.* |
| 5 | Zip implica `runtime`, `handler` e `filename` preenchidos | *Para package_type = "Zip", runtime, handler e filename não podem ser nulos.* |
| 6 | Image implica `image_uri` preenchido | *Para package_type = "Image", image_uri é obrigatório.* |
| 7 | Image implica `runtime`, `handler`, `filename` **vazios** | *Com package_type = "Image", runtime/handler/filename devem ficar nulos…* |
| 8 | Zip implica `image_uri` **vazio** | *image_uri só se aplica a package_type = "Image".* |

A regra 3 aparece **duas vezes** no código: uma na função e outra no log group. Não é
descuido. O log group é planejado primeiro, e o nome dele é montado por template
(`/aws/lambda/${var.function_name}`); sem a checagem duplicada, um `function_name` nulo
estouraria com *"Cannot include a null value in a string template"* — erro críptico — antes
de a mensagem clara ter chance de aparecer.

> A regra 8 existe para evitar um erro silencioso: sem ela, um `image_uri` esquecido num
> módulo Zip seria ignorado, e a pessoa acharia que subiu um container enquanto a função
> continua rodando o zip antigo.

Além dessas, o **provider da AWS** faz suas próprias checagens no `plan`: `memory_size`
fora de 128–32768, `timeout` fora de 1–900 e nomes com caracteres inválidos são barrados
com mensagem em inglês, vinda do provider e não do módulo.

---

## Testes automatizados

O módulo tem **29 testes** que rodam **offline**, sem criar nada na AWS e sem precisar de
credencial de verdade: todos usam `command = plan`, com chaves falsas e os `skip_*` do
provider. Isso permite rodá-los em qualquer pipeline sem configurar segredo.

```bash
terraform test
```

**Resultado esperado:** `Success! 29 passed, 0 failed.`

| Arquivo | Cobre |
|---|---|
| `tests/setup.tftest.hcl` | Caminho feliz: valores padrão, nome derivado do log group, saídas expostas, `create_lambda_function = false` sem criar nada, o caminho de container e as três regras de tag (soma com a base, mesmo conjunto no log group e sobrescrita pelo chamador). |
| `tests/preconditions.tftest.hcl` | As 8 preconditions, incluindo um caso que **deve passar** (exatamente 5 layers) — protege contra erro de contagem. |
| `tests/validations.tftest.hcl` | As 7 validations de variável, incluindo que `log_retention_days = 0` **é** válido. |

> **Atenção à versão.** `terraform test` exige Terraform **1.6 ou superior**, enquanto o
> módulo em si roda a partir da 1.3. Ou seja: quem apenas consome o módulo pode usar 1.3;
> quem desenvolve e roda a suíte precisa de 1.6+.

---

## Conceitos: por que funciona assim

### Sem `source_code_hash`, seu deploy simplesmente não acontece

Este é o problema mais perigoso do módulo, porque **falha em silêncio**.

O Terraform não abre o arquivo `.zip` para ver se o conteúdo mudou — seria lento demais.
Ele compara uma "impressão digital" que **você** fornece. Se você não fornecer, o Terraform
não tem como saber que o código é outro: ele diz `No changes` e o código antigo continua
rodando em produção.

É como levar uma caixa lacrada ao correio: o atendente não abre para conferir, ele confia
na etiqueta. Sem etiqueta nova, a caixa parece a mesma de ontem.

```hcl
source_code_hash = filebase64sha256("${path.module}/dist/pkg.zip")
```

### `publish = true` consome uma cota que é da conta inteira

Com o padrão `true`, cada mudança publica uma **versão imutável** da função. Cada versão
guarda uma cópia completa do pacote de código.

O detalhe crítico: essas cópias contam contra um limite de armazenamento de código **por
região, válido para a conta inteira** — não para a função. Uma única função que faz deploy
muitas vezes por dia pode, sozinha, travar o deploy de **outros times**.

Só mantenha `true` se você realmente usa versões e aliases (deploy canário, blue-green).
Caso contrário, use `publish = false`.

> A descrição da variável no código sinaliza que o padrão deve mudar para `false` numa
> versão futura.

### `update_runtime_on` aceita um único valor

A AWS oferece três modos para decidir quando o runtime da função recebe correção de
segurança. Este módulo aceita **apenas um**, e a validação rejeita os outros dois na hora:

| Modo | Aceito? | Por quê |
|---|---|---|
| `FunctionUpdate` | Sim, é o único | A atualização entra junto com o próximo deploy. A troca de runtime viaja pela esteira, aparece no `plan` e é revertida pelo mesmo caminho de qualquer outra mudança. |
| `Auto` | Não | A AWS trocaria o runtime na janela dela, sem passar pela esteira. |
| `Manual` | Não | Travaria a função numa versão fixa via `runtime_version_arn`, que o módulo não expõe — e a função **pararia de receber correção de segurança** até alguém atualizar o ARN na mão. |

A variável continua existindo (em vez de virar um valor fixo interno) para não quebrar
chamadas que já a passam explicitamente.

### A VPC é deduzida, não declarada

Não existe uma opção `enable_vpc`. O módulo liga a VPC automaticamente se `subnet_ids`
**ou** `security_group_ids` tiver ao menos um item — e então exige os dois.

A consequência é boa: se você passar só um dos dois por engano, isso não é ignorado em
silêncio. O `plan` para e diz o que falta. Há teste cobrindo os dois casos.

### O caderno de logs é criado antes da função, de propósito

Se a função criar o próprio log group na primeira execução, ele nasce com **retenção
infinita** e fora do controle do Terraform — custo crescendo para sempre, sem ninguém dono.

Por isso o módulo cria o log group explicitamente, com prazo definido, e amarra a função a
ele com `depends_on`, garantindo a ordem.

### As tags somam, e a base do módulo mora fora da variável

O módulo mantém uma base de tags própria (hoje, `ManagedBy = "Terraform"`) e soma as suas
por cima. Duas decisões de projeto explicam o desenho:

**Por que a base não fica no `default` da variável.** Valor padrão de variável é
tudo-ou-nada: no instante em que alguém passa `tags = { Team = "..." }`, o padrão inteiro é
descartado e o `ManagedBy` some sem aviso. Mantendo a base num valor interno e fazendo o
merge ali, o padrão deixa de ser destrutível. É por isso que o `default` da variável `tags`
hoje é `{}`.

**Por que a sua tag vence a do módulo.** No merge, a base entra primeiro e as suas tags
depois, então a base funciona como piso e não como imposição — dá para sobrescrever
`ManagedBy` quando houver motivo.

O mesmo conjunto vai para todos os recursos que aceitam tag (a função e o log group), e
nenhum recurso lê a variável direto. Isso evita o erro clássico de corrigir a tag da função
e esquecer a do log group. Há teste comparando os dois conjuntos.

O módulo não valida quais chaves você usa: qualquer conjunto é aceito, e a ausência de uma
tag nunca derruba o `plan`. Regras de tag obrigatória, se o time precisar delas, vivem fora
do módulo.

---

## Quanto custa

O módulo em si não tem custo. O que gera cobrança são os recursos criados:

| Fonte de custo | O que controla | Como reduzir |
|---|---|---|
| **Execução da função** | `memory_size` vezes tempo de execução vezes número de chamadas | Contraintuitivo: **aumentar `memory_size` costuma baratear**, porque a CPU sobe junto e a função termina muito antes. Vale medir. |
| **Processador** | `architectures` | `arm64` (Graviton) é mais barato que `x86_64` pelo mesmo desempenho — é o padrão do módulo. Exige o pacote compilado para ARM. |
| **Armazenamento de logs** | `log_retention_days` | O padrão de 30 dias já evita o pior cenário. Para guardar log por anos, costuma sair mais barato exportar para o S3 com lifecycle policy do que segurar tudo no CloudWatch. |
| **Disco temporário** | `ephemeral_storage` | Os primeiros 512 MB não são cobrados à parte. Acima disso, a cobrança é proporcional ao tempo de execução. |
| **Rastreamento X-Ray** | `tracing_config` | Está `"Active"` por padrão e é cobrado por rastro registrado. Em dev, avalie `"PassThrough"`. |
| **Armazenamento de versões** | `publish` | Com `false`, você deixa de acumular cópias do pacote a cada deploy. |
| **NAT Gateway (VPC)** | `subnet_ids` / `security_group_ids` | **Costuma ser o maior item da conta.** Só use VPC se houver destino privado real. |

> **Cuidado com `log_retention_days = 0`.** Significa "nunca expira". É válido e o módulo
> aceita, mas o custo de armazenamento cresce para sempre e só aparece na fatura meses
> depois.

> **Não há valores em reais ou dólares neste documento, de propósito.** Os preços da AWS
> variam por região e mudam com o tempo. Consulte a
> [página oficial de preços do Lambda](https://aws.amazon.com/lambda/pricing/) e a
> [calculadora AWS](https://calculator.aws/) para números atuais.

---

## Limitações conhecidas

Ao longo das revisões deste documento, o módulo corrigiu: a descrição enganosa sobre uma
política do Datadog, a ausência de `versions.tf`, o data source `aws_region` que não era
usado, a falta de validação em `ephemeral_storage` e `tracing_config`, a contradição do
`update_runtime_on`, a ausência de testes, a substituição destrutiva de tags, a condição
vestigial em `locals.tf` e a mensagem da precondition de tags, que citava `var.tags` quando
a checagem já olhava o conjunto efetivo.

O que permanece hoje:

| # | Limitação | Impacto |
|---|---|---|
| 1 | **O módulo não anexa nenhuma política IAM.** É decisão de projeto, mas surpreende quem espera um módulo "completo": permissão de log, de ENI na VPC e de leitura de segredo ficam todas por conta de quem chama. | Por design, mas é a causa mais comum de falha em runtime. |
| 2 | **O módulo não impõe nenhuma regra de tag.** Uma função pode subir só com o `ManagedBy` da base, sem dono nem centro de custo. Se a organização quiser exigir chaves, isso precisa vir de fora — política de organização (SCP/Tag Policy) ou wrapper da esteira. | Médio para FinOps — nada no `plan` avisa que a função está sem identificação. |
| 3 | **`publish = true` é o padrão** e acumula versões contra a cota de armazenamento da conta inteira. | Médio — pode travar o deploy de outros times. |
| 4 | **Layer sem `version` é alvo móvel.** O data source resolve para a mais recente no momento do `plan`. | Médio em produção — a biblioteca pode trocar sem mudança no seu código. |
| 5 | **O output `Tags` não reflete o que chega na AWS.** Ele lê o atributo `tags` do recurso; tags vindas de `default_tags` do provider só aparecem em `tags_all`, que o módulo não expõe. | Baixo — mas engana quem usa o output para auditar governança. |
| 6 | **Rodar a suíte exige Terraform 1.6+**, enquanto o módulo declara piso 1.3. Quem estiver numa versão entre 1.3 e 1.5 consome o módulo, mas não consegue rodar `terraform test`. | Baixo — afeta só quem desenvolve o módulo. |
| 7 | **Não há diretório `examples/`.** Os exemplos vivem apenas neste README e não são exercitados por nenhum teste. | Baixo — exemplo pode envelhecer sem ninguém notar. |
| 8 | **`package_type = "Image"` nunca rodou em produção.** O caminho é implementado, validado e coberto por teste de `plan`, mas a empresa só usa `Zip` hoje. | Baixo — valide num ambiente de teste antes de adotar. |
| 9 | **A tag `v2.0.0` usada nos exemplos não foi verificada.** O repositório inspecionado não tem tags Git. Confirme a referência correta antes de copiar o `source`. | Baixo, mas trava o `init` se estiver errada. |

---

## Migração dos nomes de saída

**Esta é uma mudança incompatível.** O conjunto de saídas em minúsculas foi **removido**.
Código que use os nomes antigos para de funcionar com erro de referência.

| Nome antigo (removido) | Nome atual |
|---|---|
| `arn` | `ARN` |
| `function_name` | `Name` |
| `invoke_arn` | `Invoke_ARN` |
| `qualified_arn` | `Qualified_ARN` |
| `version` | `Version` |
| `role` | `Role` |
| `memory_size` | `Memory` |
| `image_uri` | `Image_URI` |
| `last_modified` | `Last_modified` |
| `tags` | `Tags` |
| `log_group_name` | `Log_group_name` |
| `log_group_arn` | `Log_group_ARN` |
| `Timeouts` | Removido, sem substituto. |

**Checklist de migração:**

- [ ] Buscar no código por `module.<nome>.` seguido de nome em minúsculas e substituir pelo
      equivalente da tabela.
- [ ] Atenção especial a `memory_size` para `Memory` e `function_name` para `Name` — mudam
      de nome, não só de caixa.
- [ ] Conferir integrações de API Gateway e ALB: `invoke_arn` virou `Invoke_ARN`.
- [ ] Rodar `terraform plan` antes do merge. Uma referência a saída inexistente falha no
      `plan`, não no `apply` — o erro aparece cedo.
- [ ] Travar o `?ref=` do `source` na versão que você testou.

---

## Perguntas frequentes (FAQ)

**Meu código quebrou com "Unsupported attribute" depois de atualizar o módulo. Por quê?**
Os nomes das saídas mudaram. Veja a [tabela de migração](#migração-dos-nomes-de-saída).

**Troquei meu código, rodei `terraform apply` e ele disse "No changes". Por quê?**
Falta o `source_code_hash`. Sem ele o Terraform não detecta que o `.zip` mudou.

**Minha função não consegue acessar o banco de dados. O que falta?**
Provavelmente ela está fora da VPC. Veja
[Como fazer a função acessar o banco](#como-fazer-a-função-acessar-o-banco-de-dados-rodar-dentro-da-vpc).
Se já estiver na VPC, confira o security group e as permissões de ENI na role.

**Minha API responde erro ao chamar a função.**
Duas causas comuns: faltou o recurso `aws_lambda_permission` (o módulo não cria isso), ou
você usou `ARN` em vez de `Invoke_ARN` na integração.

**Configurei `timeout = 300` mas a API corta em 30 segundos.**
Comportamento do API Gateway, não do módulo. O gateway tem limite próprio de 30 segundos.

**O módulo cria a IAM role para mim?**
Não. Você cria a role separadamente e passa o ARN dela em `role`. O módulo também não anexa
nenhuma política.

**Preciso declarar `ManagedBy` nas minhas tags?**
Não. O módulo adiciona sozinho e suas tags são somadas a essa base. Se quiser um valor
diferente, basta declarar `ManagedBy` — o seu vence.

**Existe alguma tag que eu seja obrigado a preencher?**
Não. O módulo não exige nenhuma chave e nunca derruba o `plan` por tag ausente. Se o seu
time precisar tornar alguma obrigatória, isso é feito fora do módulo.

**Defini tags em `default_tags` do provider e elas não aparecem no output `Tags`.**
Esperado: `default_tags` são aplicadas pelo provider e vão para o atributo `tags_all`,
enquanto o output lê `tags`. As tags chegam normalmente na AWS — só não aparecem nesse
output.

**Posso usar `update_runtime_on = "Auto"`?**
Não. A validação rejeita. Só `"FunctionUpdate"` é permitido, e isso é intencional.

**Como faço deploy canário ou blue-green?**
O módulo não faz. Ele publica versões (com `publish = true`), mas aliases e deslocamento de
tráfego ficam por sua conta, fora do módulo.

**Posso usar container em vez de zip?**
Tecnicamente sim: o caminho é validado e coberto por teste. Mas a empresa só usa `Zip` hoje
e esse caminho nunca rodou em produção. Valide em ambiente de teste antes.

**`terraform test` falhou dizendo que o comando não existe.**
Sua versão do Terraform é anterior à 1.6. O módulo roda a partir da 1.3, mas a suíte de
testes exige 1.6+.

---

## Glossário

| Termo | O que significa |
|---|---|
| **Alias** | Apelido que aponta para uma versão da função (ex.: `prod` para a versão 7). Permite trocar de versão sem mudar quem chama. |
| **ARN** | *Amazon Resource Name*. O endereço único de qualquer coisa na AWS, como um CPF do recurso. |
| **Cold start** | A demora extra na primeira chamada, quando a AWS precisa "ligar" o ambiente da função do zero. |
| **CloudWatch Logs** | O serviço da AWS onde ficam guardadas as mensagens que sua função escreve. |
| **Digest (`sha256:...`)** | Identificador imutável de uma imagem de container. Diferente da tag, nunca aponta para outra coisa. |
| **ECR** | O repositório de imagens de container da AWS. A Lambda só aceita ECR privado, na mesma conta e região. |
| **ENI** | Interface de rede virtual. A função cria uma para cada subnet quando roda dentro da VPC. |
| **Graviton** | Família de processadores ARM da AWS, correspondente à arquitetura `arm64`. |
| **Handler** | O ponto de entrada: qual função dentro do seu código a AWS chama primeiro. |
| **IAM role** | O "crachá" da função: define o que ela pode e não pode fazer na AWS. |
| **Layer** | Pacote de bibliotecas compartilhado entre funções, para não repetir o mesmo código em cada zip. |
| **Log group** | A "pasta" no CloudWatch onde os logs de uma função específica são guardados. |
| **NAT Gateway** | Componente que permite a recursos dentro da rede privada acessarem a internet. Cobrado por hora e por volume de dados. |
| **Precondition** | Verificação do Terraform que roda no `plan` e cancela a operação se a configuração estiver errada. |
| **Provider** | O plugin do Terraform que sabe conversar com uma nuvem específica (aqui, a AWS). |
| **Runtime** | A linguagem e versão em que sua função roda (ex.: `python3.12`, `dotnet8`). |
| **Security group** | Regras de firewall que dizem que tráfego entra e sai de um recurso. |
| **Secrets Manager** | Serviço da AWS para guardar senhas e chaves com segurança. |
| **Subnet** | Uma faixa da rede privada (VPC), normalmente ligada a uma zona de disponibilidade. |
| **Tag** | Etiqueta (chave/valor) colada no recurso, usada para organização e rateio de custo. |
| **Terraform** | Ferramenta que descreve infraestrutura em arquivos de texto e a cria na nuvem. |
| **Terraform plan** | Prévia: mostra o que será criado, alterado ou destruído, sem executar nada. |
| **Validation** | Regra escrita na própria variável, que rejeita valores fora do permitido antes mesmo do `plan`. |
| **VPC** | A rede privada da empresa dentro da AWS — como a rede interna de um escritório. |
| **X-Ray** | Serviço de rastreamento que mostra onde a função gastou tempo em cada chamada. |

---

## Precisa de ajuda?

- **Dono do módulo:** _[PREENCHER — time/squad responsável]_
- **Canal de suporte:** _[PREENCHER — Teams/Slack]_
- **Abrir issue ou PR:** repositório `Fibra.DevOps.Terraform`, pasta `modules/aws_lambda_function`
- **Documentação oficial:** [AWS Lambda](https://docs.aws.amazon.com/lambda/latest/dg/welcome.html) ·
  [Terraform `aws_lambda_function`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function)

---

### Sobre este documento

| | |
|---|---|
| **Última atualização** | 27/07/2026 |
| **Responsável** | _[PREENCHER — time dono]_ |
| **Terraform exigido pelo módulo** | >= 1.3.0 |
| **Provider AWS** | ~> 6.0 |

**O que foi verificado executando:** a suíte completa (`terraform test`) passou com
**29 de 29** testes, cobrindo as 8 preconditions, as 7 validations e as 3 regras de tag;
`terraform validate` passou nas versões **1.3.0** (o piso declarado), 1.5.7 e 1.9.8;
`terraform fmt -check -recursive` passou sem diferenças; o comportamento de `default_tags`
do provider — que chega em `tags_all` e não em `tags` — foi confirmado por teste escrito
para esta revisão; os limites de `memory_size`, `timeout` e formato de nome foram
confirmados como checagens do provider AWS, aplicadas no `plan`.

**O que não foi verificado:** o comando `terraform import`, os custos, a existência da tag
`v2.0.0` no repositório remoto e qualquer comportamento que exija `terraform apply` numa
conta AWS real.
