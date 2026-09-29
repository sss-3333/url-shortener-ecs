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