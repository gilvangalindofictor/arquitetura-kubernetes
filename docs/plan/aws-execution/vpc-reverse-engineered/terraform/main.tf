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
  source   = "./modules/internet-gateway"
  vpc_id   = module.vpc.vpc_id
  name     = "fictor-igw"
}

module "subnets" {
  source   = "./modules/subnets"
  vpc_id   = module.vpc.vpc_id
  subnets = [
    {
      cidr_block        = "10.0.0.0/20"
      availability_zone = "us-east-1a"
      map_public_ip     = false
      name              = "fictor-subnet-public1-us-east-1a"
    },
    {
      cidr_block        = "10.0.16.0/20"
      availability_zone = "us-east-1b"
      map_public_ip     = false
      name              = "fictor-subnet-public2-us-east-1b"
    },
    {
      cidr_block        = "10.0.128.0/20"
      availability_zone = "us-east-1a"
      map_public_ip     = false
      name              = "fictor-subnet-private1-us-east-1a"
    },
    {
      cidr_block        = "10.0.144.0/20"
      availability_zone = "us-east-1b"
      map_public_ip     = false
      name              = "fictor-subnet-private2-us-east-1b"
    }
  ]
}

module "nat_gateways" {
  source = "./modules/nat-gateways"
  nat_gateways = [
    {
      subnet_id = module.subnets.subnet_ids["0"]  # public1 us-east-1a
      name      = "fictor-nat-public1-us-east-1a"
    },
    {
      subnet_id = module.subnets.subnet_ids["1"]  # public2 us-east-1b
      name      = "fictor-nat-public2-us-east-1b"
    }
  ]
}

module "route_tables" {
  source   = "./modules/route-tables"
  vpc_id   = module.vpc.vpc_id
  route_tables = [
    {
      name = "fictor-rtb-public"
      routes = [
        {
          cidr_block = "0.0.0.0/0"
          gateway_id = module.internet_gateway.igw_id
        }
      ]
      subnet_ids = [module.subnets.subnet_ids["0"], module.subnets.subnet_ids["1"]]  # public subnets
    },
    {
      name = "fictor-rtb-private1-us-east-1a"
      routes = [
        {
          cidr_block     = "0.0.0.0/0"
          nat_gateway_id = module.nat_gateways.nat_gateway_ids["0"]
        }
      ]
      subnet_ids = [module.subnets.subnet_ids["2"]]  # private1 us-east-1a
    },
    {
      name = "fictor-rtb-private2-us-east-1b"
      routes = [
        {
          cidr_block     = "0.0.0.0/0"
          nat_gateway_id = module.nat_gateways.nat_gateway_ids["1"]
        }
      ]
      subnet_ids = [module.subnets.subnet_ids["3"]]  # private2 us-east-1b
    }
  ]
}