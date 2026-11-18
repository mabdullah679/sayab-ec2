variable "region" {
  type    = string
  default = "ap-southeast-2"
}

variable "name" {
  type    = string
  default = "pf-sayab-lambda"
}

variable "zip_path" {
  description = "Zip produced by scripts/build_lambda.sh"
  type        = string
  default     = "../../dist/lambda.zip"
}

variable "reserved_concurrency" {
  description = "Hard cap on parallel executions (cost cap). Extra requests get 429."
  type        = number
  default     = 5
}
