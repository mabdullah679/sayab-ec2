mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

variables {
  name          = "fn"
  log_group_arn = "arn:aws:logs:ap-southeast-2:111111111111:log-group:/aws/lambda/fn"
}

run "role_and_policy" {
  command = plan

  assert {
    condition     = aws_iam_role.this.name == "fn-exec"
    error_message = "role name must be <name>-exec"
  }

  assert {
    condition     = aws_iam_role_policy.logs.name == "logs-only"
    error_message = "inline policy must be named logs-only"
  }

  assert {
    condition     = data.aws_iam_policy_document.logs.statement[0].resources == toset(["arn:aws:logs:ap-southeast-2:111111111111:log-group:/aws/lambda/fn:*"])
    error_message = "logging policy must be scoped to the function's own log group"
  }

  assert {
    condition     = data.aws_iam_policy_document.logs.statement[0].actions == toset(["logs:CreateLogStream", "logs:PutLogEvents"])
    error_message = "logging policy must allow only CreateLogStream and PutLogEvents"
  }
}
