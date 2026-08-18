
variable "function_name" {
  type        = string
  description = "Nome da função Lambda. Obrigatório quando create_lambda_function = true."
  default     = null
}

variable "role" {
  type        = string
  description = <<-EOT
    ARN da IAM role de execução da Lambda. Obrigatório quando
    create_lambda_function = true.

    O módulo NÃO cria a role e NÃO anexa nenhuma política a ela. A role precisa
    existir antes, já com tudo que a função vai precisar em runtime: escrita no
    log group, permissões de ENI se rodar na VPC, leitura de segredos, acesso a
    filas, etc. Se a função falhar com AccessDenied em produção, é aqui que se
    procura — não no módulo.
  EOT
  default     = null
}

variable "memory_size" {
  type        = number
  description = "Memória alocada para a função, em MB. A CPU é proporcional à memória, então subir esse valor também acelera função que não consome memória."
  default     = 128
}

variable "timeout" {
  type        = number
  description = "Tempo máximo de execução da função, em segundos. Se a função for chamada por API Gateway, lembre que o gateway corta em 30s independentemente do que estiver aqui."
  default     = 30
}

variable "handler" {
  type        = string
  description = "Método que a Lambda invoca para iniciar a execução. Obrigatório com package_type = \"Zip\"; proibido com \"Image\"."
  default     = null
}

variable "description" {
  type        = string
  description = "Descrição da função Lambda, exibida no console da AWS."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = <<-EOT
    Tags aplicadas a TODOS os recursos criados pelo módulo que aceitam tag —
    a função Lambda e o log group. Servem para governança, rateio de custo e
    rastreabilidade.

    O módulo SOMA estas tags à sua base (hoje, ManagedBy = "Terraform") em vez
    de substituí-la, então passar tags = { Team = "..." } não faz o ManagedBy
    desaparecer. Em caso de chave repetida, a sua vence.

    O default é vazio porque a base do módulo mora em local.tags — declarar
    ManagedBy aqui também criaria duas fontes de verdade para a mesma tag.

    Para tags que valem para toda a esteira (Environment, CostCenter), prefira
    default_tags no bloco do provider: elas se somam a estas e não dependem de
    cada chamada do módulo estar correta.
  EOT
  default     = {}
}

variable "package_type" {
  type        = string
  description = "Formato de empacotamento da função: \"Zip\" para artefato, \"Image\" para container no ECR."
  default     = "Zip"

  validation {
    condition     = contains(["Zip", "Image"], var.package_type)
    error_message = "package_type deve ser \"Zip\" ou \"Image\"."
  }
}

variable "runtime" {
  type        = string
  description = "Runtime de execução da função (ex.: dotnet8, python3.12, nodejs20.x). Obrigatório com package_type = \"Zip\"; proibido com \"Image\"."
  default     = null
}

variable "publish" {
  type        = bool
  description = <<-EOT
    Publica uma nova versão imutável da função a cada mudança de código.

    O default é false porque versão só serve para quem usa alias — deploy
    gradual, canário, rollback apontando alias para versão anterior. Sem
    alias, cada apply criava uma cópia que ninguém invoca e que ninguém
    limpa.

    O custo de deixar true sem usar: cada versão guarda uma cópia do pacote e
    conta contra o limite de 75 GB de código por REGIÃO — limite da conta
    inteira, não do time. Um pacote .NET de 60 MB, em 3 funções que
    compartilham o zip, a 20 deploys por mês, são 3,6 GB por mês. Quem estoura
    trava o deploy de todo mundo na região, não só o próprio.

    Ligue true quando for usar alias de verdade. Nesse caso, os outputs
    Version e Qualified_ARN passam a devolver o número da versão; com false
    eles devolvem "$LATEST".
  EOT
  default     = false
}

variable "filename" {
  type        = string
  description = "Caminho do pacote de deploy no filesystem local. Obrigatório com package_type = \"Zip\"; proibido com \"Image\"."
  default     = null
}

variable "source_code_hash" {
  type        = string
  description = "Hash do pacote, usado para a Lambda perceber que o código mudou e atualizar a função. Sem ele, um deploy com o mesmo nome de arquivo não gera diff no plan (somente Zip)."
  default     = null
}

variable "image_uri" {
  type        = string
  description = <<-EOT
    URI da imagem no ECR. Obrigatório com package_type = "Image"; proibido com
    "Zip". Hoje a empresa só usa Zip — a variável existe para o dia em que
    alguma função for empacotada como container, sem precisar mexer no módulo.

    A Lambda só aceita repositório ECR PRIVADO, na mesma conta e região da
    função (ECR público e Docker Hub não funcionam).

    Prefira referenciar por digest (@sha256:...) em vez de tag: tag é mutável,
    então um `terraform apply` sem diff pode subir uma imagem diferente da que
    você revisou, e o rollback deixa de ser determinístico.
  EOT
  default     = null

  validation {
    condition = var.image_uri == null || can(regex(
      "^[0-9]{12}\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com/[^:@]+(:[^:@]+|@sha256:[a-f0-9]{64})$",
      var.image_uri,
    ))
    error_message = "image_uri deve ser um ECR privado no formato <conta>.dkr.ecr.<regiao>.amazonaws.com/<repo>:<tag> ou <...>@sha256:<digest>."
  }
}

variable "ephemeral_storage" {
  type        = number
  description = "Tamanho do armazenamento efêmero montado em /tmp, em MB. Os primeiros 512 MB não são cobrados à parte; acima disso a cobrança é proporcional ao tempo de execução."
  default     = 512

  validation {
    condition     = var.ephemeral_storage >= 512 && var.ephemeral_storage <= 10240
    error_message = "ephemeral_storage deve estar entre 512 e 10240 MB."
  }
}

variable "create_lambda_function" {
  description = "Controla se o módulo cria a função. Com false, nada é criado — serve para desligar o recurso sem remover a chamada do módulo do código."
  type        = bool
  default     = true
}

variable "environment" {
  description = "Mapa de variáveis de ambiente entregues à função. Prefira manter segredos no Secrets Manager e passar aqui só o nome/ARN do segredo."
  type        = map(string)
  default     = null
  sensitive   = true
}


variable "tracing_config" {
  description = "Modo de tracing no X-Ray. \"Active\" liga o tracing na própria função; \"PassThrough\" apenas propaga o tracing de quem a invocou, sem iniciar um novo."
  type        = string
  default     = "Active"

  validation {
    condition     = contains(["Active", "PassThrough"], var.tracing_config)
    error_message = "tracing_config deve ser \"Active\" ou \"PassThrough\"."
  }
}

variable "security_group_ids" {
  description = "IDs dos security groups associados à função. Só tem efeito em conjunto com subnet_ids — a AWS exige os dois para rodar a função na VPC."
  type        = list(string)
  default     = null
}

variable "subnet_ids" {
  description = "IDs das subnets em que a função roda. Só tem efeito em conjunto com security_group_ids — a AWS exige os dois para rodar a função na VPC."
  type        = list(string)
  default     = null
}

variable "log_retention_days" {
  description = <<-EOT
    Tempo de retenção dos logs no CloudWatch, em dias. Use 0 para nunca expirar.

    A lista aceita é fechada pela AWS — não é qualquer número. Valores aceitos:
    0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096,
    1827, 2192, 2557, 2922, 3288 e 3653.

    Retenção longa (ou 0) vira custo de armazenamento que só aparece na fatura
    meses depois. Para guardar log por anos, costuma sair mais barato exportar
    para o S3 com lifecycle policy do que segurar tudo no CloudWatch.
  EOT
  type        = number
  default     = 30
  validation {
    condition = contains(
      [0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653],
      var.log_retention_days,
    )
    error_message = "log_retention_days inválido. Valores aceitos: 0 (nunca expira), 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288 e 3653."
  }
}

variable "architectures" {
  description = "Arquitetura do processador em que a função roda. arm64 (Graviton) sai mais barato, mas exige que o pacote tenha sido compilado para essa arquitetura."
  type        = list(string)
  default     = ["arm64"]
  validation {
    condition     = alltrue([for arch in var.architectures : contains(["x86_64", "arm64"], arch)])
    error_message = "Arquitetura inválida. Valores aceitos: \"x86_64\" e \"arm64\"."
  }
}

variable "update_runtime_on" {
  description = <<-EOT
    Quando o runtime gerenciado da função recebe patch da AWS.

    Este módulo aceita um único valor, "FunctionUpdate": o patch entra no
    próximo deploy da função. Assim a troca de runtime viaja pela esteira,
    aparece no plan e é revertida pelo mesmo caminho de qualquer outra mudança.

    Os outros dois modos da AWS ficaram de fora por decisão de plataforma:

      Auto   - a AWS troca o runtime na janela dela, sem passar pela esteira.
      Manual - trava a função em runtime_version_arn e PARA de receber patch de
               segurança do runtime até alguém atualizar o ARN na mão.

    A variável continua existindo (em vez de virar um local) para não quebrar
    chamadas que já a passam explicitamente. Para liberar outro modo, ajuste o
    validation abaixo — lembrando que "Manual" exige expor runtime_version_arn,
    hoje não suportado pelo módulo.

    Só se aplica a package_type = "Zip": imagem de container não tem runtime
    gerenciado pela AWS, e nesse caso nenhum aws_lambda_runtime_management_config
    é criado.
  EOT
  type        = string
  default     = "FunctionUpdate"

  validation {
    condition     = var.update_runtime_on == "FunctionUpdate"
    error_message = "update_runtime_on aceita apenas \"FunctionUpdate\" neste módulo. \"Auto\" deixaria a AWS trocar o runtime fora da esteira; \"Manual\" exigiria runtime_version_arn, que o módulo não expõe."
  }
}

variable "layers" {
  description = "Layers resolvidas via data source pelo nome (e opcionalmente versão). Sem a versão, o módulo pega a mais recente publicada no momento do plan."
  type = list(object({
    name    = string
    version = optional(number)
  }))
  default = []
}

variable "layer_arns" {
  description = "ARNs de layers externas ou públicas para adicionar diretamente, sem data source. Somam-se às de var.layers, respeitando o limite de 5 por função."
  type        = list(string)
  default     = []
}
