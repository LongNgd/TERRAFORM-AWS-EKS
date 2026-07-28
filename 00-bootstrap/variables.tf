variable "aws_region" {
  type        = string
  description = "AWS Region used for the Terraform state bucket."
  default     = "ap-southeast-1"
}

variable "bucket_name" {
  type        = string
  description = "Optional globally unique S3 bucket name. Leave empty to derive it from project, account, and Region."
  default     = ""
}

variable "project_name" {
  type        = string
  description = "Project identifier used in resource names and tags."
  default     = "do2603-ndlong-project"
}
