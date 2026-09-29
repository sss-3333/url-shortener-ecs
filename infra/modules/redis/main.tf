resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.project}-redis"
  subnet_ids = var.subnet_ids
}

resource "aws_security_group" "redis" {
  name        = "${var.project}-redis"
  description = "Redis, reachable only from the API"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project}-redis"
  }
}

resource "aws_vpc_security_group_ingress_rule" "redis" {
  for_each = var.allowed_security_group_ids

  security_group_id            = aws_security_group.redis.id
  description                  = "Redis from ${each.key}"
  referenced_security_group_id = each.value
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

# A replication group (rather than a single cache cluster) is needed for encryption in transit
resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.project}-redis"
  description          = "Redirect cache for ${var.project}"

  engine             = "redis"
  engine_version     = "7.1"
  node_type          = var.node_type
  num_cache_clusters = 1
  port               = 6379

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  # Single node to keep costs down. Failover needs at least 2 nodes
  automatic_failover_enabled = false
  apply_immediately          = true
}