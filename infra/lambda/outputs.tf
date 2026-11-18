output "url" { value = aws_lambda_function_url.app.function_url }
output "function_name" { value = aws_lambda_function.app.function_name }
output "log_group" { value = aws_cloudwatch_log_group.app.name }
