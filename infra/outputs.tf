output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "db_endpoint" {
  value = module.rds.endpoint
}

output "redis_url" {
  value = module.redis.redis_url
}

output "sqs_queue_url" {
  value = module.sqs.queue_url
}

output "alb_dns_name" {
  value = module.alb.alb_dns_name
}

output "api_url" {
  value = "https://${local.api_hostname}"
}

output "dashboard_url" {
  value = "https://${local.dashboard_hostname}"
}