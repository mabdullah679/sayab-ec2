data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name}-exec"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

# Logging only: write to this function's own log group, nothing else.
data "aws_iam_policy_document" "logs" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${var.log_group_arn}:*"]
  }
}

resource "aws_iam_role_policy" "logs" {
  name   = "logs-only"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.logs.json
}
