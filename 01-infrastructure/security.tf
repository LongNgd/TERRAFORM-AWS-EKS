resource "aws_security_group" "rds" {
  count = var.enable_rds ? 1 : 0

  name        = "${local.name}-rds"
  description = "Allow PostgreSQL from the EKS cluster security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name}-rds-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_eks" {
  count = var.enable_rds ? 1 : 0

  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  description                  = "PostgreSQL from EKS nodes and pods"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "rds_all" {
  count = var.enable_rds ? 1 : 0
  
  security_group_id = aws_security_group.rds.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
