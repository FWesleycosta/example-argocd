########################################
# Entradas inválidas devem falhar no plan (validations e preconditions).
########################################

provider "aws" {
  region                      = "us-east-2"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

mock_provider "aws" {
  alias = "mock"

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  app_name             = "app"
  project_name         = "Proj"
  function_name_prefix = "app"
  package_file         = "package/app.zip"
  environment          = "dev"
  aws_region           = "us-east-2"
  lambda               = { handlers = { principal = "App::App.Handler::Run" } }
}

run "handlers_vazio" {
  command = plan
  variables {
    lambda = { handlers = {} }
  }
  expect_failures = [var.lambda]
}

run "handler_com_maiuscula" {
  command = plan
  variables {
    lambda = { handlers = { SalvarPg = "App::App.Handler::Run" } }
  }
  expect_failures = [var.lambda]
}

run "architecture_invalida" {
  command = plan
  variables {
    lambda = { handlers = { principal = "App::App.Handler::Run" }, architecture = "amd64" }
  }
  expect_failures = [var.lambda]
}

run "tracing_invalido" {
  command = plan
  variables {
    lambda = { handlers = { principal = "App::App.Handler::Run" }, tracing_config = "Passthrough" }
  }
  expect_failures = [var.lambda]
}

run "memoria_fora_da_faixa" {
  command = plan
  variables {
    lambda = { handlers = { principal = "App::App.Handler::Run" }, memory_size = 64 }
  }
  expect_failures = [var.lambda]
}

run "environment_invalido" {
  command = plan
  variables {
    environment = "prod"
  }
  expect_failures = [var.environment]
}

run "nome_de_funcao_acima_de_64" {
  command = plan
  variables {
    function_name_prefix = "fibra-operacoes-boletador-fct-com-prefixo-muito-longo-mesmo"
    lambda               = { handlers = { "vincular-sacados-titulos-sybase" = "App::App.Handler::Run" } }
  }
  expect_failures = [aws_iam_role.lambda]
}

run "subnets_sem_vpc" {
  command = plan
  variables {
    subnet_ids_csv = "subnet-0a"
    vpc_id         = ""
  }
  expect_failures = [aws_iam_role.lambda]
}

run "assinatura_em_fila_nao_gerenciada" {
  command   = plan
  providers = { aws = aws.mock }
  variables {
    resources = {
      sns_topics            = [{ topic_name = "resultado" }]
      sns_sqs_subscriptions = [{ topic_name = "resultado", queue_name = "fila-externa" }]
    }
  }
  expect_failures = [aws_sns_topic_subscription.sqs]
}

run "trigger_para_handler_inexistente" {
  command = plan
  variables {
    resources = {
      sqs          = [{ queue_name = "fila" }]
      sqs_triggers = [{ handler = "nao-existe", queue_name = "fila" }]
    }
  }
  expect_failures = [aws_lambda_event_source_mapping.sqs]
}

run "step_function_sem_definicao" {
  command = plan
  variables {
    resources       = { step_functions = [{ name = "fluxo", definition_file = "nao-existe.asl.json" }] }
    definitions_dir = "tests/fixtures"
  }
  expect_failures = [aws_sfn_state_machine.this]
}

run "pipe_para_fila_nao_gerenciada" {
  command   = plan
  providers = { aws = aws.mock }
  variables {
    resources = {
      step_functions = [{ name = "fluxo", definition_file = "exemplo.asl.json" }]
      sns_topics     = [{ topic_name = "resultado" }]
      pipes          = [{ name = "fluxo", source_queue = "fila-externa", target_step_function = "fluxo" }]
    }
    definitions_dir = "tests/fixtures"
    lambda          = { handlers = { processar = "App::App.Handler::Run" } }
  }
  expect_failures = [aws_pipes_pipe.this]
}
