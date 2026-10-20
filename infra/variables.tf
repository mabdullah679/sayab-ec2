variable "region" {
  type    = string
  default = "ap-southeast-2"
}
variable "name_prefix" {
  type    = string
  default = "pf-sayab-ec2-"
}
variable "instance_type" {
  description = "Graviton burstable; 1 GiB RAM is enough for gunicorn (2 workers) + CloudWatch agent."
  type        = string
  default     = "t4g.micro"
}
variable "artifact_bucket" {
  type    = string
  default = "pf-sayab-ec2-artifacts-346208529954"
}
variable "release_key" {
  description = "S3 key of the release tarball to run, e.g. releases/<git-sha>.tar.gz (set by CI)."
  type        = string
}
variable "max_body_bytes" {
  description = "App config pushed to SSM Parameter Store and read by the instance at boot."
  type        = string
  default     = "4096"
}
