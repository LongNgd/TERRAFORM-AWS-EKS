variable "additional_admin_role_arns" {
  type        = set(string)
  description = "Additional IAM role ARNs that receive EKS cluster-admin access through access entries."
  default     = []
}

variable "additional_tags" {
  type        = map(string)
  description = "Additional tags applied through the AWS provider default_tags block."
  default     = {}
}

variable "app_bucket_name" {
  type        = string
  description = "Optional globally unique application S3 bucket name."
  default     = ""
}

variable "availability_zones" {
  type        = list(string)
  description = "Exactly two Availability Zones. Leave empty to select the first two available AZs in the Region."
  default     = []

  validation {
    condition     = length(var.availability_zones) == 0 || length(var.availability_zones) == 2
    error_message = "availability_zones must be empty or contain exactly two Availability Zones."
  }
}

variable "aws_region" {
  type        = string
  description = "AWS Region for the infrastructure."
  default     = "ap-southeast-1"
}

variable "cluster_public_access_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the public EKS API endpoint. Use your public IP with /32, not 0.0.0.0/0."
}

variable "db_allocated_storage" {
  type        = number
  description = "Initial RDS storage in GiB."
  default     = 50
}

variable "db_backup_retention_days" {
  type        = number
  description = "RDS automated backup retention in days."
  default     = 7
}

variable "db_deletion_protection" {
  type        = bool
  description = "Enable RDS deletion protection. Recommended for production."
  default     = false
}

variable "db_engine_version" {
  type        = string
  description = "RDS PostgreSQL major version. AWS selects a recent supported minor release."
  default     = "17"
}

variable "db_instance_class" {
  type        = string
  description = "RDS DB instance class."
  default     = "db.t4g.medium"
}

variable "db_max_allocated_storage" {
  type        = number
  description = "Maximum RDS storage autoscaling limit in GiB."
  default     = 200
}

variable "db_name" {
  type        = string
  description = "Initial PostgreSQL database name."
  default     = "appdb"
}

variable "db_skip_final_snapshot" {
  type        = bool
  description = "Skip the final RDS snapshot when destroying. Set false in production."
  default     = true
}

variable "eks_endpoint_public_access" {
  type        = bool
  description = "Expose the EKS API endpoint publicly, restricted by cluster_public_access_cidrs."
  default     = true
}

variable "eks_version" {
  type        = string
  description = "Amazon EKS Kubernetes minor version."
  default     = "1.35"
}

variable "environment" {
  type        = string
  description = "Environment identifier such as dev, staging, or prod."
  default     = "dev"
}

variable "node_capacity_type" {
  type        = string
  description = "EKS node group capacity type."
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "node_desired_size" {
  type        = number
  description = "Desired EKS managed node group size."
  default     = 2
}

variable "node_instance_types" {
  type        = list(string)
  description = "EC2 instance types used by the EKS managed node group."
  default     = ["t3.large"]
}

variable "node_max_size" {
  type        = number
  description = "Maximum EKS managed node group size."
  default     = 6
}

variable "node_min_size" {
  type        = number
  description = "Minimum EKS managed node group size."
  default     = 2
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Two private subnet CIDRs, one per Availability Zone."
  default     = ["10.20.10.0/24", "10.20.11.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) == 2
    error_message = "private_subnet_cidrs must contain exactly two CIDRs."
  }
}

variable "project_name" {
  type        = string
  description = "Project identifier used in names and tags."
  default     = "longnd"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Two public subnet CIDRs, one per Availability Zone."
  default     = ["10.20.0.0/24", "10.20.1.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "public_subnet_cidrs must contain exactly two CIDRs."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block."
  default     = "10.20.0.0/16"
}

variable "enable_rds" {
  type        = bool
  description = "Create the PostgreSQL RDS resources."
  default     = false
}