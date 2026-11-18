resource "aws_lambda_function" "this" {
  function_name                  = var.name
  role                           = var.role_arn
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
}

# Public on purpose: this is a public demo page. Auth NONE needs both permissions below.
resource "aws_lambda_function_url" "this" {
  function_name      = aws_lambda_function.this.function_name
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "url_invoke_url" {
  statement_id           = "AllowPublicFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.this.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "url_invoke" {
  statement_id             = "AllowPublicInvokeViaUrl"
  action                   = "lambda:InvokeFunction"
  function_name            = aws_lambda_function.this.function_name
  principal                = "*"
  invoked_via_function_url = true
}
