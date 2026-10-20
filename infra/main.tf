data "aws_availability_zones" "available" { state = "available" }
data "aws_caller_identity" "me" {}
data "aws_iam_policy" "boundary" { name = "portfolio-ci-boundary" }
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  azs        = slice(data.aws_availability_zones.available.names, 0, 2)
  ssm_prefix = "/${trimsuffix(var.name_prefix, "-")}/config"
}

# ---------------------------------------------------------------- network
resource "aws_vpc" "main" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.name_prefix}vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name_prefix}igw" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  availability_zone       = local.azs[count.index]
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.name_prefix}public-${count.index}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.name_prefix}public" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------- security groups
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}alb"
  description = "Public HTTP to the load balancer"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.name_prefix}alb" }
}
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}
resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"
}

resource "aws_security_group" "app" {
  name        = "${var.name_prefix}app"
  description = "App instances: only the ALB may reach port 8000; no SSH (use SSM)"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.name_prefix}app" }
}
resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"
}
# Outbound HTTPS for SSM, S3, CloudWatch, PyPI; HTTP for dnf mirrors.
resource "aws_vpc_security_group_egress_rule" "app_https" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}
resource "aws_vpc_security_group_egress_rule" "app_http" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

# ---------------------------------------------------------------- config in SSM
resource "aws_ssm_parameter" "max_body_bytes" {
  name  = "${local.ssm_prefix}/MAX_BODY_BYTES"
  type  = "String"
  value = var.max_body_bytes
}

# ---------------------------------------------------------------- instance role
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name                 = "${var.name_prefix}instance"
  assume_role_policy   = data.aws_iam_policy_document.ec2_trust.json
  permissions_boundary = data.aws_iam_policy.boundary.arn
}
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy_attachment" "cw_agent" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
data "aws_iam_policy_document" "app" {
  statement {
    sid       = "ReadReleases"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.artifact_bucket}/releases/*"]
  }
  statement {
    sid       = "ReadConfig"
    actions   = ["ssm:GetParametersByPath", "ssm:GetParameter"]
    resources = ["arn:aws:ssm:${var.region}:${data.aws_caller_identity.me.account_id}:parameter${local.ssm_prefix}*"]
  }
}
resource "aws_iam_role_policy" "app" {
  name   = "app"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app.json
}
resource "aws_iam_instance_profile" "app" {
  name = "${var.name_prefix}instance"
  role = aws_iam_role.app.name
}

# ---------------------------------------------------------------- logs
resource "aws_cloudwatch_log_group" "app" {
  name              = "/${trimsuffix(var.name_prefix, "-")}/app"
  retention_in_days = 14
}

# ---------------------------------------------------------------- compute
resource "aws_launch_template" "app" {
  name                   = "${var.name_prefix}lt"
  image_id               = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  update_default_version = true
  vpc_security_group_ids = [aws_security_group.app.id]

  iam_instance_profile { name = aws_iam_instance_profile.app.name }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 8
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  monitoring { enabled = false }

  user_data = base64encode(templatefile("${path.module}/scripts/user_data.sh.tftpl", {
    bucket      = var.artifact_bucket
    release_key = var.release_key
    region      = var.region
    ssm_path    = local.ssm_prefix
    log_group   = aws_cloudwatch_log_group.app.name
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.name_prefix}app" }
  }
  tag_specifications {
    resource_type = "volume"
    tags          = { Name = "${var.name_prefix}app" }
  }
}

resource "aws_lb" "app" {
  name                       = "${var.name_prefix}alb"
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = aws_subnet.public[*].id
  idle_timeout               = 30
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "app" {
  name                 = "${var.name_prefix}tg"
  port                 = 8000
  protocol             = "HTTP"
  vpc_id               = aws_vpc.main.id
  deregistration_delay = 15
  health_check {
    path                = "/readyz"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_autoscaling_group" "app" {
  name                      = "${var.name_prefix}asg"
  min_size                  = 1
  max_size                  = 1
  desired_capacity          = 1
  vpc_zone_identifier       = aws_subnet.public[*].id
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 180

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 100 # launch the replacement first,
      max_healthy_percentage = 200 # then retire the old instance: no downtime
      instance_warmup        = 120
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}app"
    propagate_at_launch = true
  }
}

# ---------------------------------------------------------------- alarms
resource "aws_sns_topic" "alarms" {
  name = "${var.name_prefix}alarms"
}

resource "aws_cloudwatch_metric_alarm" "unhealthy" {
  alarm_name          = "${var.name_prefix}unhealthy-hosts"
  alarm_description   = "No healthy app target behind the ALB for 2 minutes"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  dimensions          = { LoadBalancer = aws_lb.app.arn_suffix, TargetGroup = aws_lb_target_group.app.arn_suffix }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "elb_5xx" {
  alarm_name          = "${var.name_prefix}alb-5xx"
  alarm_description   = "ALB returned 5xx responses"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  dimensions          = { LoadBalancer = aws_lb.app.arn_suffix }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
}
