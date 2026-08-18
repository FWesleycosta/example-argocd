########################################
# As 7 validations de variável.
#
# expect_failures = [var.X] afirma que o plan DEVE falhar na validação daquela
# variável. Se alguém afrouxar um validation, o run correspondente passa a
# planejar com sucesso e o teste quebra.
########################################

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

variables {
  function_name = "tf-test-lambda"
  role          = "arn:aws:iam::123456789012:role/tf-test-exec"
  runtime       = "dotnet8"
  handler       = "App::App.Function::Handler"
  filename      = "app.zip"
}

run "package_type_invalido" {
  command = plan
  variables {
    package_type = "Docker"
  }
  expect_failures = [var.package_type]
}

run "image_uri_fora_do_ecr" {
  command = plan
  variables {
    package_type = "Image"
    image_uri    = "docker.io/library/nginx:latest"
    runtime      = null
    handler      = null
    filename     = null
  }
  expect_failures = [var.image_uri]
}

run "ephemeral_storage_abaixo_do_minimo" {
  command = plan
  variables {
    ephemeral_storage = 100
  }
  expect_failures = [var.ephemeral_storage]
}

run "ephemeral_storage_acima_do_maximo" {
  command = plan
  variables {
    ephemeral_storage = 20480
  }
  expect_failures = [var.ephemeral_storage]
}

run "tracing_config_invalido" {
  command = plan
  variables {
    tracing_config = "Enabled"
  }
  expect_failures = [var.tracing_config]
}

# 45 não está na lista fechada da AWS, ainda que pareça um número razoável.
run "log_retention_days_fora_da_lista" {
  command = plan
  variables {
    log_retention_days = 45
  }
  expect_failures = [var.log_retention_days]
}

# 0 significa "nunca expira" e É válido — protege contra alguém "consertar"
# a lista removendo o zero por achar que é valor não preenchido.
run "log_retention_days_zero_e_valido" {
  command = plan
  variables {
    log_retention_days = 0
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].retention_in_days == 0
    error_message = "log_retention_days = 0 (nunca expira) deveria ser aceito e chegar ao log group."
  }
}

run "arquitetura_invalida" {
  command = plan
  variables {
    architectures = ["mips"]
  }
  expect_failures = [var.architectures]
}

run "update_runtime_on_auto_rejeitado" {
  command = plan
  variables {
    update_runtime_on = "Auto"
  }
  expect_failures = [var.update_runtime_on]
}

run "update_runtime_on_manual_rejeitado" {
  command = plan
  variables {
    update_runtime_on = "Manual"
  }
  expect_failures = [var.update_runtime_on]
}
