mock_provider "aws" {}

variables {
  name = "fn"
}

run "name_and_retention" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/aws/lambda/fn"
    error_message = "log group name must be /aws/lambda/<name>"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 7
    error_message = "retention must be 7 days"
  }
}
