variable "name" {
  description = "Function name; the role is <name>-exec."
  type        = string
}

variable "log_group_arn" {
  description = "ARN of the only log group the role may write to."
  type        = string
}
