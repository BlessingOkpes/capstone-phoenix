variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "capstone-phoenix"
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "admin_cidr" {
  description = "Your public IP as x.x.x.x/32. Find it with: curl -s ifconfig.me"
  type        = string
  # No default on purpose — you must set this in terraform.tfvars
}
