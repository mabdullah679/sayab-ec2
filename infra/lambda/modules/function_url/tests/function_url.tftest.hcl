mock_provider "aws" {}

variables {
  name                 = "fn"
  role_arn             = "arn:aws:iam::111111111111:role/fn-exec"
  zip_path             = "../../tests/fixtures/dummy.zip"
  reserved_concurrency = -1
}

run "function_url_and_permissions" {
  command = plan

  assert {
    condition     = aws_lambda_function.this.function_name == "fn" && aws_lambda_function.this.runtime == "python3.12" && aws_lambda_function.this.handler == "lambda_handler.handler"
    error_message = "function name/runtime/handler wrong"
  }

  assert {
    condition     = aws_lambda_function.this.reserved_concurrent_executions == -1
    error_message = "reserved concurrency must pass through"
  }

  assert {
    condition     = aws_lambda_function_url.this.authorization_type == "NONE"
    error_message = "function URL auth type must be NONE (public demo)"
  }

  assert {
    condition     = aws_lambda_permission.url_invoke_url.function_url_auth_type == "NONE" && aws_lambda_permission.url_invoke.invoked_via_function_url == true
    error_message = "both public-URL permissions must exist"
  }
}
