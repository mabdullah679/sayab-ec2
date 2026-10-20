terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.80" }
  }
  backend "s3" {
    bucket       = "pf-sayab-ec2-tfstate-346208529954"
    key          = "sayab-ec2/terraform.tfstate"
    region       = "ap-southeast-2"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region              = var.region
  allowed_account_ids = ["346208529954"]
  default_tags {
    tags = { project = "portfolio", repo = "sayab-ec2", "managed-by" = "terraform" }
  }
}
