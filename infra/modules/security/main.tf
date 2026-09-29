# One security group per ECS service, so each can be given exactly the access it needs.
# No inbound rules yet: the ALB rules for api and dashboard are added with the ALB.
resource "aws_security_group" "service" {
  for_each = toset(var.services)

  name        = "${var.project}-${each.key}"
  description = "ECS tasks for the ${each.key} service"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project}-${each.key}"
  }
}

# Every service pulls its image, writes logs and reads secrets through the interface endpoints
resource "aws_vpc_security_group_egress_rule" "https_endpoints" {
  for_each = aws_security_group.service

  security_group_id = each.value.id
  description       = "HTTPS to the VPC interface endpoints"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# ECR image layers are stored in S3, reached through the gateway endpoint
resource "aws_vpc_security_group_egress_rule" "https_s3" {
  for_each = aws_security_group.service

  security_group_id = each.value.id
  description       = "HTTPS to S3 through the gateway endpoint"
  prefix_list_id    = var.s3_prefix_list_id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# All three services use Postgres
resource "aws_vpc_security_group_egress_rule" "postgres" {
  for_each = aws_security_group.service

  security_group_id = each.value.id
  description       = "Postgres inside the VPC"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
}

# Only the API uses Redis
resource "aws_vpc_security_group_egress_rule" "redis_api" {
  security_group_id = aws_security_group.service["api"].id
  description       = "Redis inside the VPC"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 6379
  to_port           = 6379
  ip_protocol       = "tcp"
}