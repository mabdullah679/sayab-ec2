# One-time bootstrap (run locally, local state): creates the things the CI
# pipeline needs before it can run at all -- the Terraform state bucket, the
# release-artifact bucket, and the GitHub OIDC deploy role. Everything else is
# applied by GitHub Actions from ../ .
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.80" }
  }
}

variable "name_prefix" {
  type    = string
  default = "pf-sayab-ec2-"
}
variable "github_repo" {
  type    = string
  default = "mabdullah679/sayab-ec2"
}
variable "github_branch" {
  type    = string
  default = "prod-hardening"
}

provider "aws" {
  region              = "ap-southeast-2"
  allowed_account_ids = ["346208529954"]
  default_tags {
    tags = { project = "portfolio", repo = "sayab-ec2", "managed-by" = "terraform" }
  }
}

data "aws_caller_identity" "me" {}
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}
data "aws_iam_policy" "boundary" {
  name = "portfolio-ci-boundary"
}

locals {
  acct = data.aws_caller_identity.me.account_id
}

resource "aws_s3_bucket" "tfstate" {
  bucket        = "${var.name_prefix}tfstate-${local.acct}"
  force_destroy = true
}
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = "${var.name_prefix}artifacts-${local.acct}"
  force_destroy = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    id     = "expire-old-releases"
    status = "Enabled"
    filter {}
    expiration { days = 30 }
  }
}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/${var.github_branch}"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name                 = "${var.name_prefix}github-deploy"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  permissions_boundary = data.aws_iam_policy.boundary.arn
  max_session_duration = 3600
}

data "aws_iam_policy_document" "deploy" {
  statement {
    sid       = "Workload"
    actions   = ["ec2:*", "elasticloadbalancing:*", "autoscaling:*", "logs:*", "cloudwatch:*", "sns:*", "ssm:*"]
    resources = ["*"]
  }
  statement {
    sid       = "S3OwnBuckets"
    actions   = ["s3:*"]
    resources = ["arn:aws:s3:::${var.name_prefix}*", "arn:aws:s3:::${var.name_prefix}*/*"]
  }
  statement {
    sid       = "S3List"
    actions   = ["s3:ListAllMyBuckets", "s3:GetBucketLocation"]
    resources = ["*"]
  }
  statement {
    sid = "IamOwnPrefixOnly"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole", "iam:TagRole", "iam:UntagRole",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy",
      "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole",
      "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile", "iam:TagInstanceProfile",
      "iam:PassRole", "iam:CreatePolicy", "iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicyVersions",
      "iam:CreatePolicyVersion", "iam:DeletePolicyVersion", "iam:TagPolicy",
    ]
    resources = [
      "arn:aws:iam::${local.acct}:role/${var.name_prefix}*",
      "arn:aws:iam::${local.acct}:instance-profile/${var.name_prefix}*",
      "arn:aws:iam::${local.acct}:policy/${var.name_prefix}*",
    ]
  }
  statement {
    sid       = "ServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "iam:AWSServiceName"
      values   = ["autoscaling.amazonaws.com", "elasticloadbalancing.amazonaws.com"]
    }
  }
  statement {
    sid       = "ReadOnlyIam"
    actions   = ["iam:GetOpenIDConnectProvider", "iam:ListOpenIDConnectProviders", "iam:GetPolicy", "iam:GetPolicyVersion"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "deploy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}

output "deploy_role_arn" { value = aws_iam_role.deploy.arn }
output "state_bucket" { value = aws_s3_bucket.tfstate.bucket }
output "artifact_bucket" { value = aws_s3_bucket.artifacts.bucket }
