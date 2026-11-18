output "url" { value = aws_lambda_function_url.this.function_url }
output "function_name" { value = aws_lambda_function.this.function_name }
output "auth_type" { value = aws_lambda_function_url.this.authorization_type }
output "reserved_concurrency" { value = aws_lambda_function.this.reserved_concurrent_executions }
