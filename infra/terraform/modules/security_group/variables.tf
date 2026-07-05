variable "vpc_id" {
  type = string
}

variable "project_name" {
  type = string
}

variable "admin_cidr" {
  description = "Your IP (as x.x.x.x/32) allowed to SSH and reach the k3s API server"
  type        = string
}
