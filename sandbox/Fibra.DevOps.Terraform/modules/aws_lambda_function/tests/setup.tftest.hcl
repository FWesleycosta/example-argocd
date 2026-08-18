########################################
# Caminho feliz: defaults, nomes derivados e outputs.
#
# Todos os runs usam `command = plan` — nada é criado na AWS. As credenciais
# abaixo são falsas de propósito e os skip_* impedem o provider de tentar
# validá-las contra a AWS, então a suíte roda offline e em CI sem segredo.
#
# Requer Terraform 1.6+ (comando `terraform test`). O módulo em si roda a
# partir da 1.3 — ver versions.tf.
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

run "zip_com_defaults" {
  command = plan

  assert {
    condition     = aws_lambda_function.this[0].function_name == "tf-test-lambda"
    error_message = "A função deveria receber o nome passado em function_name."
  }

  assert {
    condition     = aws_lambda_function.this[0].memory_size == 128
    error_message = "O default de memory_size mudou sem que o teste fosse atualizado."
  }

  assert {
    condition     = aws_lambda_function.this[0].timeout == 30
    error_message = "O default de timeout mudou sem que o teste fosse atualizado."
  }

  assert {
    condition     = one(aws_lambda_function.this[0].architectures) == "arm64"
    error_message = "O default de architectures deveria ser arm64 (Graviton)."
  }

  # Versão só serve para quem usa alias. Ligar por default acumularia cópia do
  # pacote contra a cota de 75 GB por região — que é da conta inteira.
  assert {
    condition     = aws_lambda_function.this[0].publish == false
    error_message = "O default de publish deveria ser false. Voltar para true faz toda função da esteira acumular versões que ninguém invoca."
  }

  # O log group precisa existir ANTES da função: se a AWS o criar sozinha na
  # primeira invocação, ele nasce sem retenção e os logs ficam para sempre.
  assert {
    condition     = aws_cloudwatch_log_group.this[0].name == "/aws/lambda/tf-test-lambda"
    error_message = "O nome do log group precisa seguir /aws/lambda/<function_name> — é o caminho que a Lambda usa por convenção."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].retention_in_days == 30
    error_message = "O default de log_retention_days mudou sem que o teste fosse atualizado."
  }
}

run "outputs_expostos" {
  command = plan

  assert {
    condition     = output.Name == "tf-test-lambda"
    error_message = "O output Name deveria devolver o nome da função."
  }

  assert {
    condition     = output.Log_group_name == "/aws/lambda/tf-test-lambda"
    error_message = "O output Log_group_name deveria devolver o nome do log group gerenciado."
  }

  assert {
    condition     = output.Role == "arn:aws:iam::123456789012:role/tf-test-exec"
    error_message = "O output Role deveria devolver o ARN da role passada."
  }

  # Zip não tem imagem: o output existe, mas vem nulo.
  assert {
    condition     = output.Image_URI == null
    error_message = "Com package_type = Zip o output Image_URI deveria ser nulo."
  }
}

run "create_lambda_function_false_nao_cria_nada" {
  command = plan

  variables {
    create_lambda_function = false
  }

  assert {
    condition     = length(aws_lambda_function.this) == 0
    error_message = "Com create_lambda_function = false nenhuma função deveria ser planejada."
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.this) == 0
    error_message = "Com create_lambda_function = false nenhum log group deveria ser planejado."
  }

  # Os outputs precisam sobreviver ao count = 0 devolvendo null, e não
  # estourando erro de índice — é para isso que existe o try() em outputs.tf.
  assert {
    condition     = output.ARN == null
    error_message = "Com create_lambda_function = false o output ARN deveria ser nulo, não erro de índice."
  }
}

run "vpc_configurada_quando_subnet_e_sg_presentes" {
  command = plan

  variables {
    subnet_ids         = ["subnet-0123456789abcdef0"]
    security_group_ids = ["sg-0123456789abcdef0"]
  }

  assert {
    condition     = length(aws_lambda_function.this[0].vpc_config) == 1
    error_message = "Com subnet_ids e security_group_ids preenchidos o bloco vpc_config deveria ser criado."
  }
}

# A tag de governança não pode sumir quando o chamador passa as dele. Este era
# o comportamento antigo (var.tags substituía o default) e foi o que motivou o
# local.tags.
run "tags_do_chamador_somam_com_a_base_do_modulo" {
  command = plan

  variables {
    tags = { Team = "pagamentos" }
  }

  assert {
    condition     = aws_lambda_function.this[0].tags["ManagedBy"] == "Terraform"
    error_message = "O ManagedBy da base do módulo sumiu ao passar tags próprias — é exatamente a regressão que o local.tags existe para impedir."
  }

  assert {
    condition     = aws_lambda_function.this[0].tags["Team"] == "pagamentos"
    error_message = "As tags informadas pelo chamador deveriam chegar à função."
  }
}

# Todo recurso do módulo que aceita tag recebe o MESMO conjunto. Sem isso, é
# fácil corrigir a função e esquecer o log group.
run "log_group_recebe_as_mesmas_tags_da_funcao" {
  command = plan

  variables {
    tags = { Team = "pagamentos" }
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].tags == aws_lambda_function.this[0].tags
    error_message = "O log group e a função deveriam receber exatamente o mesmo conjunto de tags."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].tags["ManagedBy"] == "Terraform"
    error_message = "O log group também precisa da tag de governança."
  }
}

# A base é um piso, não uma imposição: quem precisar sobrescrever, consegue.
run "chamador_pode_sobrescrever_a_base" {
  command = plan

  variables {
    tags = { ManagedBy = "Terragrunt" }
  }

  assert {
    condition     = aws_lambda_function.this[0].tags["ManagedBy"] == "Terragrunt"
    error_message = "Em caso de chave repetida, o valor do chamador deveria vencer o da base do módulo."
  }
}

# Quem usa alias precisa continuar conseguindo ligar versão.
run "publish_pode_ser_ligado_explicitamente" {
  command = plan

  variables {
    publish = true
  }

  assert {
    condition     = aws_lambda_function.this[0].publish == true
    error_message = "publish = true deveria continuar disponível para quem usa alias e deploy gradual."
  }
}

run "image_com_digest" {
  command = plan

  variables {
    package_type = "Image"
    image_uri    = "123456789012.dkr.ecr.us-east-1.amazonaws.com/tf-test@sha256:0000000000000000000000000000000000000000000000000000000000000000"
    runtime      = null
    handler      = null
    filename     = null
  }

  assert {
    condition     = aws_lambda_function.this[0].package_type == "Image"
    error_message = "O caminho de container deveria planejar com package_type = Image."
  }

  # Image não tem runtime gerenciado pela AWS, então o recurso de runtime
  # management não deve ser criado.
  assert {
    condition     = length(aws_lambda_runtime_management_config.this) == 0
    error_message = "Com package_type = Image nenhum aws_lambda_runtime_management_config deveria ser criado."
  }
}
