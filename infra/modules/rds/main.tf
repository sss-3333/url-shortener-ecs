resource "aws_db_subnet_group" "this" {
  name       = "${var.project}-db"
  subnet_ids = var.subnet_ids
}

resource "aws_security_group" "db" {
  name        = "${var.project}-db"
  description = "Postgres, reachable only from the ECS services"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project}-db"
  }
}

resource "aws_vpc_security_group_ingress_rule" "postgres" {
  for_each = var.allowed_security_group_ids

  security_group_id            = aws_security_group.db.id
  description                  = "Postgres from ${each.key}"
  referenced_security_group_id = each.value
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# No special characters: the password goes inside a URL, where symbols like @ : / would break parsing
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_db_instance" "this" {
  identifier     = "${var.project}-db"
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.instance_class

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  # Trade-offs for a demo that is destroyed and rebuilt often. For production:
  # multi_az = true, deletion_protection = true, skip_final_snapshot = false
  multi_az                = false
  deletion_protection     = false
  skip_final_snapshot     = true
  backup_retention_period = 1
  apply_immediately       = true
}

# The services read DATABASE_URL, so store the full connection string rather than just the password.
# ECS injects it into the containers at startup, so it never appears in the task definition or the repo.
resource "aws_secretsmanager_secret" "database_url" {
  name = "${var.project}/database-url"

  # Delete immediately on destroy, otherwise the name is reserved for 7+ days and the next apply fails
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id     = aws_secretsmanager_secret.database_url.id
  secret_string = "postgresql://${var.db_username}:${random_password.db.result}@${aws_db_instance.this.address}:${aws_db_instance.this.port}/${var.db_name}?sslmode=require"
}