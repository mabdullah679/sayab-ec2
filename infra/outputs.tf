output "url" { value = "http://${aws_lb.app.dns_name}" }
output "asg_name" { value = aws_autoscaling_group.app.name }
output "log_group" { value = aws_cloudwatch_log_group.app.name }
