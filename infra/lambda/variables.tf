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
  description = "Reserved concurrency. -1 = unreserved (default). Set >= 0 to cap parallel executions (extra requests get 429)."
  type        = number
  # -1 on purpose: this account's total Lambda concurrency limit is 10 and AWS requires
  # >= 10 unreserved, so reserving 5 is rejected (verified 2026-11-18). Override if the limit is raised.
  default = -1
}
