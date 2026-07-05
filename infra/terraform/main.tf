terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "network" {
  source = "./modules/network"
}

module "security_group" {
  source       = "./modules/security_group"
  vpc_id       = module.network.vpc_id
  project_name = var.project_name
  admin_cidr   = var.admin_cidr
}

module "compute" {
  source             = "./modules/compute"
  project_name       = var.project_name
  instance_type      = var.instance_type
  subnet_id          = module.network.subnet_id
  security_group_id  = module.security_group.security_group_id
}
