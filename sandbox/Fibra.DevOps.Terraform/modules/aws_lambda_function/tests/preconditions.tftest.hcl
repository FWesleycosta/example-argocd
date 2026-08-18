########################################
# As 8 preconditions de aws_lambda_function.
#
# Diferente das validations, estas moram no lifecycle do recurso e só são
# avaliadas quando ele entra no plan (count > 0) — é o que mantém o caminho
# create_lambda_function = false funcionando.
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

run "vpc_so_com_subnet" {
  command = plan
  variables {
    subnet_ids = ["subnet-0123456789abcdef0"]
  }
  expect_failures = [aws_lambda_function.this]
}

run "vpc_so_com_security_group" {
  command = plan
  variables {
    security_group_ids = ["sg-0123456789abcdef0"]
  }
  expect_failures = [aws_lambda_function.this]
}

# layer_arns em vez de layers: evita o data source, então o teste não depende
# de nenhuma layer existir de verdade na conta.
run "mais_de_cinco_layers" {
  command = plan
  variables {
    layer_arns = [
      "arn:aws:lambda:us-east-1:123456789012:layer:l1:1",
      "arn:aws:lambda:us-east-1:123456789012:layer:l2:1",
      "arn:aws:lambda:us-east-1:123456789012:layer:l3:1",
      "arn:aws:lambda:us-east-1:123456789012:layer:l4:1",
      "arn:aws:lambda:us-east-1:123456789012:layer:l5:1",
      "arn:aws:lambda:us-east-1:123456789012:layer:l6:1",
    ]
  }
  expect_failures = [aws_lambda_function.this]
}

run "exatamente_cinco_layers_passa" {
  command = plan
  variables {
    layer_arns = [
      "arn:aws:lambda:us-east-1:123456789012:layer:l1:1",
      "arn:aws:lambda:us-east-1:123456789012:layer:l2:1",
      "arn:aws:lambda:us-east-1:123456789012:layer:l3:1",
      "arn:aws:lambda:us-east-1:123456789012:layer:l4:1",
      "arn:aws:lambda:us-east-1:123456789012:layer:l5:1",
    ]
  }

  assert {
    condition     = length(aws_lambda_function.this[0].layers) == 5
    error_message = "Cinco layers é o limite da AWS e deveria passar — o teste protege contra um off-by-one na precondition."
  }
}

# A falha esperada é no LOG GROUP, não na função: ele é planejado primeiro e
# tem a mesma precondition justamente para não deixar o template de `name`
# estourar com erro críptico antes dela.
run "function_name_nulo" {
  command = plan
  variables {
    function_name = null
  }
  expect_failures = [aws_cloudwatch_log_group.this]
}

run "role_nula" {
  command = plan
  variables {
    role = null
  }
  expect_failures = [aws_lambda_function.this]
}

run "zip_sem_handler" {
  command = plan
  variables {
    handler = null
  }
  expect_failures = [aws_lambda_function.this]
}

run "zip_sem_filename" {
  command = plan
  variables {
    filename = null
  }
  expect_failures = [aws_lambda_function.this]
}

run "image_sem_image_uri" {
  command = plan
  variables {
    package_type = "Image"
    runtime      = null
    handler      = null
    filename     = null
  }
  expect_failures = [aws_lambda_function.this]
}

run "image_com_handler_de_zip" {
  command = plan
  variables {
    package_type = "Image"
    image_uri    = "123456789012.dkr.ecr.us-east-1.amazonaws.com/tf-test:v1"
    runtime      = null
    filename     = null
    # handler continua preenchido pelo bloco variables do arquivo — é
    # exatamente o resquício de migração que a precondition existe para pegar.
  }
  expect_failures = [aws_lambda_function.this]
}

# O inverso: image_uri esquecido num módulo Zip. Sem a precondition, a AWS
# ignora o campo em silêncio e a pessoa acha que subiu container.
run "zip_com_image_uri" {
  command = plan
  variables {
    image_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/tf-test:v1"
  }
  expect_failures = [aws_lambda_function.this]
}
