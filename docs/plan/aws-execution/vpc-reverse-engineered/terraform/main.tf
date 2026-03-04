terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "vpc" {
  source   = "./modules/vpc"
  vpc_cidr = "10.0.0.0/16"
  vpc_name = "fictor-vpc"
}

module "internet_gateway" {
  source = "./modules/internet-gateway"
  vpc_id = "vpc-0b1396a59c417c1f0" # hardcoded for import
  name   = "fictor-igw"
}

module "subnets" {
  source = "./modules/subnets"
  vpc_id = "vpc-0b1396a59c417c1f0" # hardcoded for import
  subnets = [
    {
      cidr_block        = "10.0.0.0/20"
      availability_zone = "us-east-1a"
      map_public_ip     = false
      name              = "fictor-subnet-public1-us-east-1a"
      extra_tags = {
        "kubernetes.io/cluster/k8s-platform-prod" = "shared"
        "kubernetes.io/role/elb"                  = "1"
      }
    },
    {
      cidr_block        = "10.0.16.0/20"
      availability_zone = "us-east-1b"
      map_public_ip     = false
      name              = "fictor-subnet-public2-us-east-1b"
      extra_tags = {
        "kubernetes.io/cluster/k8s-platform-prod" = "shared"
        "kubernetes.io/role/elb"                  = "1"
      }
    },
    {
      cidr_block        = "10.0.128.0/20"
      availability_zone = "us-east-1a"
      map_public_ip     = false
      name              = "fictor-subnet-private1-us-east-1a"
      extra_tags = {
        "kubernetes.io/cluster/k8s-platform-prod" = "shared"
        "kubernetes.io/role/internal-elb"         = "1"
      }
    },
    {
      cidr_block        = "10.0.144.0/20"
      availability_zone = "us-east-1b"
      map_public_ip     = false
      name              = "fictor-subnet-private2-us-east-1b"
      extra_tags = {
        "kubernetes.io/cluster/k8s-platform-prod" = "shared"
        "kubernetes.io/role/internal-elb"         = "1"
      }
    }
  ]
}

module "nat_gateways" {
  source = "./modules/nat-gateways"
  nat_gateways = [
    {
      subnet_id = "subnet-0b5e0cae5658ea993" # public1 us-east-1a (hardcoded for import)
      name      = "fictor-nat-public1-us-east-1a"
      eip_name  = "fictor-eip-us-east-1a"
    },
    {
      subnet_id = "subnet-07dca8ceb9882ba66" # public2 us-east-1b (hardcoded for import)
      name      = "fictor-nat-public2-us-east-1b"
      eip_name  = "fictor-eip-us-east-1b"
    }
  ]
}

module "route_tables" {
  source = "./modules/route-tables"
  vpc_id = "vpc-0b1396a59c417c1f0" # hardcoded for import
  route_tables = [
    {
      name = "fictor-rtb-public"
      routes = [
        {
          cidr_block = "0.0.0.0/0"
          gateway_id = "igw-0a8a1ad9cfddd037e" # hardcoded for import (igw-0a8a1ad9cfddd037e)
        }
      ]
      # Hardcoded subnet IDs to allow terraform import (static keys required for for_each)
      subnet_ids = ["subnet-0b5e0cae5658ea993", "subnet-07dca8ceb9882ba66"] # public1 us-east-1a, public2 us-east-1b
    },
    {
      name = "fictor-rtb-private1-us-east-1a"
      routes = [
        {
          cidr_block     = "0.0.0.0/0"
          nat_gateway_id = "nat-03512e5ee0642dcf2" # hardcoded for import (public1)
        }
      ]
      # Hardcoded subnet ID to allow terraform import (static keys required for for_each)
      subnet_ids = ["subnet-0472ab28726cdf745"] # private1 us-east-1a
    },
    {
      name = "fictor-rtb-private2-us-east-1b"
      routes = [
        {
          cidr_block     = "0.0.0.0/0"
          nat_gateway_id = "nat-0be570edfb2eff63e" # hardcoded for import (public2)
        }
      ]
      # Hardcoded subnet ID to allow terraform import (static keys required for for_each)
      subnet_ids = ["subnet-0288a67cd352effa7"] # private2 us-east-1b
    }
  ]
}