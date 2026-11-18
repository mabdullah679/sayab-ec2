terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
  # No remote backend on purpose: local state, a throwaway free demo.
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { project = "portfolio", repo = "sayab-ec2", "managed-by" = "terraform", stack = "lambda-free" }
  }
}
