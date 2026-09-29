locals {
  services = {
    api       = var.api
    dashboard = var.dashboard
  }
}

# ---- Security group: open to the internet on 80/443, and only able to reach the services ----

resource "aws_security_group" "alb" {
  name        = "${var.project}-alb"
  description = "Public HTTP/HTTPS in, service ports out"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project}-alb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from anywhere, redirected to HTTPS"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from anywhere"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "to_service" {
  for_each = local.services

  security_group_id            = aws_security_group.alb.id
  description                  = "To the ${each.key} tasks"
  referenced_security_group_id = each.value.security_group_id
  from_port                    = each.value.port
  to_port                      = each.value.port
  ip_protocol                  = "tcp"
}

# The other side of the same connection: each service accepts traffic only from the ALB
resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  for_each = local.services

  security_group_id            = each.value.security_group_id
  description                  = "From the ALB"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = each.value.port
  to_port                      = each.value.port
  ip_protocol                  = "tcp"
}

# ---- Load balancer ----

resource "aws_lb" "this" {
  name                       = "${var.project}-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.public_subnet_ids
  drop_invalid_header_fields = true
}

# ---- Target groups ----
# API: blue and green. CodeDeploy starts the new version in the idle one, then shifts traffic.
# Dashboard: one group, since it uses rolling deploys.

resource "aws_lb_target_group" "api_blue" {
  name        = "${var.project}-api-blue"
  port        = var.api.port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  # Default is 300s. Shorter means faster deploys and faster destroys
  deregistration_delay = 30

  health_check {
    path                = "/healthz"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group" "api_green" {
  name        = "${var.project}-api-green"
  port        = var.api.port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  deregistration_delay = 30

  health_check {
    path                = "/healthz"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group" "dashboard" {
  name        = "${var.project}-dashboard"
  port        = var.dashboard.port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  deregistration_delay = 30

  health_check {
    path                = "/healthz"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# ---- Listeners ----

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# The API lives on the default action because CodeDeploy can only shift traffic there, not on rules.
# CodeDeploy flips it between blue and green on every deploy, so Terraform ignores it after creation.
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_blue.arn
  }

  lifecycle {
    ignore_changes = [default_action]
  }

  # After a deploy the listener may point at green. This makes destroy remove the listener
  # before the green target group, otherwise AWS refuses to delete a target group still in use.
  depends_on = [aws_lb_target_group.api_green]
}

resource "aws_lb_listener_rule" "dashboard" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  condition {
    host_header {
      values = [var.dashboard.hostname]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dashboard.arn
  }
}

# ---- DNS ----

resource "aws_route53_record" "service" {
  for_each = local.services

  zone_id = var.zone_id
  name    = each.value.hostname
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}