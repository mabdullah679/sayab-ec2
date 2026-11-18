data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "exec" {
  name               = "${var.name}-exec"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

# Logging only: write to this function's own log group, nothing else.
data "aws_iam_policy_document" "logs" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.app.arn}:*"]
  }
}

resource "aws_iam_role_policy" "logs" {
  name   = "logs-only"
  role   = aws_iam_role.exec.id
  policy = data.aws_iam_policy_document.logs.json
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/aws/lambda/${var.name}"
  retention_in_days = 7
}

resource "aws_lambda_function" "app" {
  function_name                  = var.name
  role                           = aws_iam_role.exec.arn
  runtime                        = "python3.12"
  architectures                  = ["arm64"]
  handler                        = "lambda_handler.handler"
  filename                       = var.zip_path
  source_code_hash               = filebase64sha256(var.zip_path)
  memory_size                    = 256
  timeout                        = 10
  reserved_concurrent_executions = var.reserved_concurrency

  environment {
    variables = {
      FRONTEND_DIR = "/var/task/frontend"
    }
  }

  depends_on = [aws_cloudwatch_log_group.app, aws_iam_role_policy.logs]
}

# Public on purpose: this is a public demo page. Auth NONE needs both permissions below.
resource "aws_lambda_function_url" "app" {
  function_name      = aws_lambda_function.app.function_name
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "url_invoke_url" {
  statement_id           = "AllowPublicFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.app.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "url_invoke" {
  statement_id             = "AllowPublicInvokeViaUrl"
  action                   = "lambda:InvokeFunction"
  function_name            = aws_lambda_function.app.function_name
  principal                = "*"
  invoked_via_function_url = true
}
