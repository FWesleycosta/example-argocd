########################################
# Caminho feliz: nomes derivados, VPC opcional, sandbox, filas/tópicos, triggers,
# step function + pipe. Todos os runs usam `command = plan` — nada é criado na AWS.
# Sem zip no workdir o hash fica nulo (plan válido). Requer Terraform >= 1.7
# (mock_provider) e o override de source do módulo (ver README).
########################################

provider "aws" {
  region                      = "us-east-2"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

# Provider simulado para os runs que exercitam lookup de recurso externo: o data source
# responde com valores fictícios em vez de chamar a AWS.
mock_provider "aws" {
  alias = "mock"

  # O provider real valida o JSON das policies mesmo com CRUD simulado: sem isto o mock devolve
  # uma string aleatória e o plan falha em assume_role_policy.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  app_name             = "fibra-operacoes-boletador-fct"
  project_name         = "Fibra.Operacoes"
  function_name_prefix = "fibra-operacoes-boletador-fct"
  package_file         = "package/fibra-operacoes-boletador-fct.zip"
  environment          = "dev"
  aws_region           = "us-east-2"
  subnet_ids_csv       = "subnet-0a, subnet-0b"
  vpc_id               = "vpc-01"
  sistema              = "operacoes"
  owner                = "squad-boletador"

  lambda = {
    # chaves só da esteira (src_path, dotnet_version) chegam junto e são ignoradas pelo tipo
    src_path = "src/App/App.csproj"
    handlers = {
      processar = "App::App.Handlers.Processar::ExecutarAsync"
      notificar = "App::App.Handlers.Notificar::ExecutarAsync"
    }
    memory_size = "1024" # como o Azure DevOps interpola números
  }

  environment_variables_common = [{ name = "LOG_LEVEL", value = "Information" }, { name = "REGIAO", value = "comum" }]
  environment_variables_env    = [{ name = "REGIAO", value = "dev" }]
  ssm_parameters = [
    { name = "/Operacoes/Boletador/FCT/SybaseEnabled", value = "true" },
    { name = "/dev/Operacoes/Boletador/FCT/Timeout", value = "30", type = "String" },
  ]

  resources = {
    sqs = [
      { queue_name = "boletador-salvar", dlq_queue_name = "boletador-salvar-dlq" },
      { queue_name = "sacado-falha" },
    ]
    sns_topics            = [{ topic_name = "resultado" }]
    sns_sqs_subscriptions = [{ topic_name = "resultado", queue_name = "sacado-falha" }]
    sqs_triggers          = [{ handler = "notificar", queue_name = "sacado-falha", batch_size = 5 }]
    step_functions        = [{ name = "boleto-salvar", definition_file = "exemplo.asl.json" }]
    pipes                 = [{ name = "boleto-salvar", source_queue = "boletador-salvar", target_step_function = "boleto-salvar" }]
  }
  definitions_dir = "tests/fixtures"
}

run "dev_com_vpc" {
  command = plan

  assert {
    condition     = local.function_names["processar"] == "fibra-operacoes-boletador-fct-processar"
    error_message = "Função deve ser <prefix>-<handler> (sem sufixo fora do sandbox)."
  }
  assert {
    condition     = length(module.lambda) == 2 && var.lambda.memory_size == 1024 && var.lambda.runtime == "dotnet10"
    error_message = "Uma função por chave de handlers; número como string converte; defaults do objeto valem."
  }
  assert {
    condition     = length(aws_security_group.lambda) == 1 && length(aws_iam_role_policy_attachment.lambda_vpc) == 1
    error_message = "subnet_ids_csv preenchido deve criar o SG e anexar a policy de VPC."
  }
  assert {
    condition     = local.subnet_ids == tolist(["subnet-0a", "subnet-0b"])
    error_message = "subnet_ids_csv deve ser dividido por vírgula com trim."
  }
  assert {
    condition     = local.env_vars == { LOG_LEVEL = "Information", REGIAO = "dev" }
    error_message = "Env vars do ambiente devem sobrescrever as comuns de mesmo nome."
  }
  assert {
    condition     = aws_sqs_queue.this["boletador-salvar"].name == "sqs-dev-us-east-2-boletador-salvar" && aws_sqs_queue.dlq["boletador-salvar"].name == "sqs-dev-us-east-2-boletador-salvar-dlq"
    error_message = "Fila e DLQ devem seguir sqs-<env>-<region>-<nome>."
  }
  assert {
    condition     = keys(local.dlq_queues) == ["boletador-salvar"] && length(aws_sqs_queue.dlq) == 1
    error_message = "DLQ (e redrive) só na fila que declarou dlq_queue_name."
  }
  assert {
    condition     = aws_sns_topic.this["resultado"].name == "sns-dev-us-east-2-resultado"
    error_message = "Tópico deve seguir sns-<env>-<region>-<nome>."
  }
  assert {
    condition     = length(aws_sqs_queue_policy.from_sns) == 1 && contains(keys(aws_sqs_queue_policy.from_sns), "sacado-falha")
    error_message = "Fila assinante de tópico deve receber policy liberando o SNS."
  }
  assert {
    condition     = aws_lambda_event_source_mapping.sqs["notificar-sacado-falha"].batch_size == 5
    error_message = "Trigger SQS deve respeitar batch_size."
  }
  assert {
    condition     = aws_sfn_state_machine.this["boleto-salvar"].name == "fibra-operacoes-boletador-fct-boleto-salvar" && length(aws_iam_role.sfn) == 1
    error_message = "State machine deve ser <prefix>-<name> com role própria."
  }
  assert {
    condition     = aws_pipes_pipe.this["boleto-salvar"].name == "fibra-operacoes-boletador-fct-boleto-salvar" && length(aws_iam_role.pipes) == 1
    error_message = "Pipe deve ser <prefix>-<name> com role própria."
  }
  assert {
    condition     = aws_ssm_parameter.this["/Operacoes/Boletador/FCT/SybaseEnabled"].name == "/Operacoes/Boletador/FCT/SybaseEnabled"
    error_message = "Fora do sandbox o nome do SSM é o declarado."
  }
  assert {
    condition     = length(data.aws_sqs_queue.existing) == 0 && length(data.aws_sns_topic.existing) == 0
    error_message = "Só referências gerenciadas: nenhum lookup externo."
  }
  assert {
    condition     = aws_iam_role.lambda.tags["Sistema"] == "operacoes" && aws_iam_role.lambda.tags["Owner"] == "squad-boletador" && aws_iam_role.lambda.tags["Ambiente"] == "dev"
    error_message = "Tags de governança devem ser aplicadas."
  }
  assert {
    condition     = local.package_hash == null
    error_message = "Sem o zip no workdir o hash deve ser nulo (plan/test sem artefato)."
  }
}

run "sem_vpc" {
  command = plan

  variables {
    subnet_ids_csv = ""
    vpc_id         = ""
  }

  assert {
    condition     = length(aws_security_group.lambda) == 0 && length(aws_iam_role_policy_attachment.lambda_vpc) == 0
    error_message = "Sem subnets não deve haver SG nem policy de VPC."
  }
}

run "config_omitido_chega_como_string_vazia" {
  command = plan

  # Chave omitida em `config` no azure-pipelines.yml chega como "" (não null) via convertToJson.
  variables {
    environment_variables_common = ""
    environment_variables_env    = ""
    ssm_parameters               = ""
  }

  assert {
    condition     = local.env_vars == {} && length(aws_ssm_parameter.this) == 0
    error_message = "\"\" nas listas de config deve valer como lista vazia."
  }
}

run "sdx_sufixa_nomes_e_prefixa_ssm" {
  command = plan

  variables {
    environment     = "sdx"
    resource_suffix = "-sdx"
  }

  assert {
    condition     = local.function_names["processar"] == "fibra-operacoes-boletador-fct-processar-sdx"
    error_message = "No sandbox a função recebe o sufixo."
  }
  assert {
    condition     = aws_iam_role.lambda.name == "lambda-fibra-operacoes-boletador-fct-sdx" && aws_security_group.lambda[0].name == "fibra-operacoes-boletador-fct-sdx-lambda"
    error_message = "Role e SG (nomes sem ambiente) devem receber o sufixo."
  }
  assert {
    condition     = aws_sqs_queue.this["boletador-salvar"].name == "sqs-sdx-us-east-2-boletador-salvar-sdx"
    error_message = "Filas do sandbox: env sdx no prefixo e sufixo no fim."
  }
  assert {
    condition     = aws_sfn_state_machine.this["boleto-salvar"].name == "fibra-operacoes-boletador-fct-boleto-salvar-sdx" && aws_pipes_pipe.this["boleto-salvar"].name == "fibra-operacoes-boletador-fct-boleto-salvar-sdx"
    error_message = "State machine e pipe devem receber o sufixo."
  }
  assert {
    condition     = aws_ssm_parameter.this["/Operacoes/Boletador/FCT/SybaseEnabled"].name == "/sdx/Operacoes/Boletador/FCT/SybaseEnabled"
    error_message = "SSM sem segmento de ambiente deve ganhar o prefixo /sdx."
  }
  assert {
    condition     = aws_ssm_parameter.this["/dev/Operacoes/Boletador/FCT/Timeout"].name == "/sdx/Operacoes/Boletador/FCT/Timeout"
    error_message = "SSM com segmento /dev/ deve trocá-lo por /sdx/."
  }
}

run "fila_externa_vira_lookup" {
  command   = plan
  providers = { aws = aws.mock }

  variables {
    resources = {
      sqs          = [{ queue_name = "boletador-salvar", dlq_queue_name = "boletador-salvar-dlq" }]
      sqs_triggers = [{ handler = "processar", queue_name = "fila-de-outro-app" }]
    }
  }

  assert {
    condition     = contains(local.external_queue_names, "fila-de-outro-app")
    error_message = "Fila não declarada em resources.sqs deve virar lookup externo."
  }
  assert {
    condition     = data.aws_sqs_queue.existing["fila-de-outro-app"].name == "sqs-dev-us-east-2-fila-de-outro-app"
    error_message = "Lookup externo deve usar a convenção sqs-<env>-<region>-<nome>, sem sufixo."
  }
  assert {
    condition     = length(aws_lambda_event_source_mapping.sqs) == 1
    error_message = "Trigger em fila externa deve criar o event source mapping."
  }
}

run "sem_recursos_opcionais" {
  command = plan

  variables {
    ssm_parameters = []
    resources      = {}
    lambda = {
      handlers       = { processar = "App::App.Handlers.Processar::ExecutarAsync" }
      tracing_config = "Active"
    }
  }

  assert {
    condition     = length(aws_iam_role_policy.lambda) == 0
    error_message = "Sem recursos declarados a policy inline não deve existir (evita Statement vazio)."
  }
  assert {
    condition     = length(aws_iam_role.sfn) == 0 && length(aws_iam_role.pipes) == 0 && length(aws_sqs_queue.this) == 0
    error_message = "resources = {} deve valer como 'nenhum recurso' (atributos opcionais)."
  }
  assert {
    condition     = length(aws_iam_role_policy_attachment.lambda_xray) == 1
    error_message = "tracing_config=Active deve anexar a policy do X-Ray."
  }
}
