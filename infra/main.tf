# The hosted zone is created when the domain is registered, so it is looked up rather than managed here
data "aws_route53_zone" "this" {
  name = var.domain_name
}

locals {
  api_hostname       = "${var.api_subdomain}.${var.domain_name}"
  dashboard_hostname = "${var.dashboard_subdomain}.${var.domain_name}"
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source = "./modules/vpc"

  project    = var.project
  aws_region = var.aws_region
  vpc_cidr   = var.vpc_cidr
  azs        = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}

module "security" {
  source = "./modules/security"

  project           = var.project
  vpc_id            = module.vpc.vpc_id
  vpc_cidr          = module.vpc.vpc_cidr
  s3_prefix_list_id = module.vpc.s3_prefix_list_id
  services          = var.services
}

module "rds" {
  source = "./modules/rds"

  project                    = var.project
  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.private_subnet_ids
  allowed_security_group_ids = module.security.service_security_group_ids
  instance_class             = var.db_instance_class
}

module "redis" {
  source = "./modules/redis"

  project    = var.project
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  node_type  = var.redis_node_type

  allowed_security_group_ids = {
    api = module.security.service_security_group_ids["api"]
  }
}

module "sqs" {
  source = "./modules/sqs"

  project = var.project
}

module "acm" {
  source = "./modules/acm"

  domain_name               = local.api_hostname
  subject_alternative_names = [local.dashboard_hostname]
  zone_id                   = data.aws_route53_zone.this.zone_id
}

module "alb" {
  source = "./modules/alb"

  project           = var.project
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  certificate_arn   = module.acm.certificate_arn
  zone_id           = data.aws_route53_zone.this.zone_id

  services = {
    api = {
      port              = 8080
      hostname          = local.api_hostname
      priority          = 10
      security_group_id = module.security.service_security_group_ids["api"]
    }
    dashboard = {
      port              = 8081
      hostname          = local.dashboard_hostname
      priority          = 20
      security_group_id = module.security.service_security_group_ids["dashboard"]
    }
  }
}

module "waf" {
  source = "./modules/waf"

  project = var.project
  alb_arn = module.alb.alb_arn
}