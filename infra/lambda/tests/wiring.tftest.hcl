# Parent wiring, offline: mock_provider, no AWS calls. Run: terraform test
# (the root can only see child outputs; resource-level asserts live in modules/*/tests).
mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/mock" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:ap-southeast-2:111111111111:log-group:/aws/lambda/mock" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

variables {
  zip_path = "tests/fixtures/dummy.zip"
}

run "defaults_wiring" {
  command = plan

  assert {
    condition     = module.log_group.name == "/aws/lambda/pf-sayab-lambda"
    error_message = "log group name must be /aws/lambda/<name>"
  }

  assert {
    condition     = module.exec_role.name == "pf-sayab-lambda-exec"
    error_message = "role name must be <name>-exec"
  }

  assert {
    condition     = module.function_url.function_name == "pf-sayab-lambda"
    error_message = "function name must be var.name"
  }

  assert {
    condition     = module.function_url.reserved_concurrency == -1
    error_message = "reserved concurrency default must be -1 (unreserved)"
  }

  assert {
    condition     = module.function_url.auth_type == "NONE"
    error_message = "function URL auth type must be NONE (public demo)"
  }

  assert {
    condition     = output.function_name == "pf-sayab-lambda" && output.log_group == "/aws/lambda/pf-sayab-lambda"
    error_message = "outputs function_name/log_group wrong"
  }
}

run "overrides_flow_through" {
  command = plan

  variables {
    name                 = "other"
    reserved_concurrency = 3
  }

  assert {
    condition     = module.function_url.reserved_concurrency == 3
    error_message = "reserved_concurrency must be overridable"
  }

  assert {
    condition     = module.exec_role.name == "other-exec" && module.log_group.name == "/aws/lambda/other" && module.function_url.function_name == "other"
    error_message = "name must flow to every child"
  }
}

run "url_output_is_exposed" {
  command = apply

  assert {
    condition     = output.url == module.function_url.url && output.url != ""
    error_message = "url output must come from the function_url module"
  }
}
