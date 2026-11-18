variable "name" {
  type = string
}

variable "role_arn" {
  description = "Execution role ARN."
  type        = string
}

variable "zip_path" {
  type = string
}

variable "reserved_concurrency" {
  description = "-1 = unreserved; >= 0 reserves that many executions."
  type        = number
}
