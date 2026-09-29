output "redis_url" {
  description = "rediss:// (two s's) means TLS, since transit encryption is on"
  value       = "rediss://${aws_elasticache_replication_group.this.primary_endpoint_address}:6379"
}