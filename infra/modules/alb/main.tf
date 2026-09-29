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
  for_each = var.services

  security_group_id            = aws_security_group.alb.id
  description                  = "To the ${each.key} tasks"
  referenced_security_group_id = each.value.security_group_id
  from_port                    = each.value.port
  to_port                      = each.value.port
  ip_protocol                  = "tcp"
}

# The other side of the same connection: each service accepts traffic only from the ALB
resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  for_each = var.services

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

# ---- Target groups: blue and green per service ----
# CodeDeploy starts the new version in whichever group is idle, then moves traffic across.
# The two roles alternate: after one deploy green is live, on the next deploy blue takes over again.

resource "aws_lb_target_group" "blue" {
  for_each = var.services

  name        = "${var.project}-${each.key}-blue"
  port        = each.value.port
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

resource "aws_lb_target_group" "green" {
  for_each = var.services

  name        = "${var.project}-${each.key}-green"
  port        = each.value.port
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

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  # Requests for any hostname we don't serve (e.g. the raw ALB address) get a 404
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not found"
      status_code  = "404"
    }
  }
}

# Host-based routing: each hostname goes to its own service.
# Starts on blue. CodeDeploy then switches this rule between blue and green on every deploy,
# so Terraform ignores the action, otherwise the next apply would undo a live deploy.
resource "aws_lb_listener_rule" "host" {
  for_each = var.services

  listener_arn = aws_lb_listener.https.arn
  priority     = each.value.priority

  condition {
    host_header {
      values = [each.value.hostname]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue[each.key].arn
  }

  lifecycle {
    ignore_changes = [action]
  }
}

# ---- DNS ----

resource "aws_route53_record" "service" {
  for_each = var.services

  zone_id = var.zone_id
  name    = each.value.hostname
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}