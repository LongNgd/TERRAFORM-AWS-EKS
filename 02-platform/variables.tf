variable "aws_region" {
  type        = string
  description = "AWS Region containing the EKS cluster and Terraform state."
  default     = "ap-southeast-1"
}

variable "certificate_arn" {
  type        = string
  description = "Optional ACM certificate ARN. When set, the sample ALB listens on HTTPS 443 and redirects HTTP to HTTPS."
  default     = ""
}

variable "deploy_sample_app" {
  type        = bool
  description = "Deploy a small echoserver workload, Service, and ALB Ingress for validation."
  default     = true
}

variable "infrastructure_state_bucket" {
  type        = string
  description = "S3 bucket containing the 01-infrastructure Terraform state."
}

variable "infrastructure_state_key" {
  type        = string
  description = "S3 key containing the 01-infrastructure Terraform state."
  default     = "longnd/dev/infrastructure.tfstate"
}

variable "load_balancer_controller_chart_version" {
  type        = string
  description = "AWS Load Balancer Controller Helm chart version."
  default     = "3.4.2"
}

variable "load_balancer_controller_replica_count" {
  type        = number
  description = "Number of AWS Load Balancer Controller replicas. Use at least two for high availability."
  default     = 2

  validation {
    condition     = var.load_balancer_controller_replica_count >= 1
    error_message = "load_balancer_controller_replica_count must be at least 1."
  }
}
