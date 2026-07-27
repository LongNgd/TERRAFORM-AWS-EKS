resource "aws_db_subnet_group" "main" {
  name       = "${local.name}-db-subnets"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${local.name}-db-subnets"
  }
}

resource "aws_db_instance" "postgresql" {
  identifier = "${local.name}-postgresql"

  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = "dbadmin"
  port     = 5432

  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = true

  backup_retention_period = var.db_backup_retention_days
  backup_window           = "18:00-19:00"
  maintenance_window      = "sun:19:30-sun:20:30"

  auto_minor_version_upgrade = true
  copy_tags_to_snapshot       = true
  deletion_protection         = var.db_deletion_protection
  skip_final_snapshot         = var.db_skip_final_snapshot
  final_snapshot_identifier   = var.db_skip_final_snapshot ? null : "${local.name}-postgresql-final"

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  performance_insights_enabled     = true

  apply_immediately = false
}
