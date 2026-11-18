# Old flat addresses -> module addresses, so existing state migrates with no destroy/create.
# (data.aws_iam_policy_document.* are data sources: not movable, re-read on plan, no infra effect.)
moved {
  from = aws_iam_role.exec
  to   = module.exec_role.aws_iam_role.this
}

moved {
  from = aws_iam_role_policy.logs
  to   = module.exec_role.aws_iam_role_policy.logs
}

moved {
  from = aws_cloudwatch_log_group.app
  to   = module.log_group.aws_cloudwatch_log_group.this
}

moved {
  from = aws_lambda_function.app
  to   = module.function_url.aws_lambda_function.this
}

moved {
  from = aws_lambda_function_url.app
  to   = module.function_url.aws_lambda_function_url.this
}

moved {
  from = aws_lambda_permission.url_invoke
  to   = module.function_url.aws_lambda_permission.url_invoke
}

moved {
  from = aws_lambda_permission.url_invoke_url
  to   = module.function_url.aws_lambda_permission.url_invoke_url
}
