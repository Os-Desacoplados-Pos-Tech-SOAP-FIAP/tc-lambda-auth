# Role de execução: logs + ENIs na VPC + leitura dos 2 secrets.
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.project_name}-lambda-auth"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "vpc_access" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

data "aws_secretsmanager_secret" "database_url" {
  name = local.database_url_secret
}

data "aws_secretsmanager_secret" "jwt_secret" {
  name = local.jwt_secret_name
}

resource "aws_iam_role_policy" "secrets" {
  name = "read-app-secrets"
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = [
        data.aws_secretsmanager_secret.database_url.arn,
        data.aws_secretsmanager_secret.jwt_secret.arn,
      ]
    }]
  })
}

# SG da Lambda + liberação do 5432 no SG do RDS.
resource "aws_security_group" "lambda" {
  name        = "${var.project_name}-lambda-auth"
  description = "Lambda de autenticacao por CPF"
  vpc_id      = local.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_lambda" {
  security_group_id            = local.rds_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.lambda.id
  description                  = "Postgres 5432 a partir da Lambda de auth"
}

# Bundles gerados pelo `npm run build` (a esteira builda antes do terraform).
data "archive_file" "auth" {
  type        = "zip"
  source_dir  = "${path.module}/../dist/auth"
  output_path = "${path.module}/../dist/auth.zip"
}

data "archive_file" "authorizer" {
  type        = "zip"
  source_dir  = "${path.module}/../dist/authorizer"
  output_path = "${path.module}/../dist/authorizer.zip"
}

resource "aws_lambda_function" "auth" {
  function_name    = "${var.project_name}-auth-cpf"
  role             = aws_iam_role.lambda.arn
  runtime          = "nodejs20.x"
  handler          = "index.handler"
  filename         = data.archive_file.auth.output_path
  source_code_hash = data.archive_file.auth.output_base64sha256
  timeout          = 15
  memory_size      = 256

  vpc_config {
    subnet_ids         = local.private_subnets
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DATABASE_URL_SECRET_ID = local.database_url_secret
      JWT_SECRET_ID          = local.jwt_secret_name
    }
  }
}

# O authorizer só valida assinatura — fora da VPC (cold start menor).
resource "aws_lambda_function" "authorizer" {
  function_name    = "${var.project_name}-authorizer-cliente"
  role             = aws_iam_role.lambda.arn
  runtime          = "nodejs20.x"
  handler          = "index.handler"
  filename         = data.archive_file.authorizer.output_path
  source_code_hash = data.archive_file.authorizer.output_base64sha256
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      JWT_SECRET_ID = local.jwt_secret_name
    }
  }
}
