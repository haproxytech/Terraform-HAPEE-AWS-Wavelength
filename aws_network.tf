locals {
  vpc_cidr = "10.0.0.0/16"
  azs      = ["${var.region}a", "${var.region}b"]
}

module "vpc" {
  source                               = "terraform-aws-modules/vpc/aws"
  version                              = "~> 4.0"
  name                                 = "eks-module-vpc"
  cidr                                 = local.vpc_cidr
  azs                                  = local.azs
  private_subnets                      = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets                       = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]
  intra_subnets                        = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 52)]
  enable_nat_gateway                   = true
  single_nat_gateway                   = true
  enable_dns_hostnames                 = true
  enable_flow_log                      = true
  create_flow_log_cloudwatch_iam_role  = true
  create_flow_log_cloudwatch_log_group = true
}

# Create subnet for each Wavelength Zone
resource "aws_subnet" "local_subnets" {
  for_each             = var.wavelength_zones
  vpc_id               = module.vpc.vpc_id
  cidr_block           = each.value.cidr_block
  availability_zone_id = each.value.availability_zone_id
  tags = {
    Name = "local-eks-module-vpc-${each.key}"
  }
}

# Create local Route Table for local subnets
resource "aws_route_table" "WLZ_route_table" {
  vpc_id = module.vpc.vpc_id
  tags = {
    Name = "local Zone Route Table"
  }
}
resource "aws_route" "WLZ_route" {
  route_table_id         = aws_route_table.WLZ_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  # nat_gateway_id         = module.vpc.natgw_ids[0]
  carrier_gateway_id = aws_ec2_carrier_gateway.carrier_gateway.id
}

resource "aws_ec2_carrier_gateway" "carrier_gateway" {
  vpc_id = module.vpc.vpc_id
  tags = {
    Name = "wlz-carrier-gateway"
  }
}

resource "aws_route_table_association" "WLZ_route_associations" {
  for_each       = var.wavelength_zones
  subnet_id      = aws_subnet.local_subnets[each.key].id
  route_table_id = aws_route_table.WLZ_route_table.id
}

# VPC Endpoints
resource "aws_vpc_endpoint" "ec2" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.region}.ec2"
  vpc_endpoint_type = "Interface"
  subnet_ids        = module.vpc.private_subnets
  security_group_ids = [
    module.eks.cluster_security_group_id, module.eks.node_security_group_id
  ]
  private_dns_enabled = true
}
resource "aws_vpc_endpoint" "ecr-dkr-endpoint" {
  vpc_id              = module.vpc.vpc_id
  private_dns_enabled = true
  service_name        = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [module.eks.cluster_security_group_id, module.eks.node_security_group_id]
  subnet_ids          = module.vpc.private_subnets
}
resource "aws_vpc_endpoint" "ecr-api-endpoint" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [module.eks.cluster_security_group_id, module.eks.node_security_group_id]
  subnet_ids          = module.vpc.private_subnets
  private_dns_enabled = true
}
resource "aws_vpc_endpoint" "sts-endpoint" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.sts"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [module.eks.cluster_security_group_id, module.eks.node_security_group_id]
  subnet_ids          = module.vpc.private_subnets
  private_dns_enabled = true
}
resource "aws_vpc_endpoint" "ssm-endpoint" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.ssm"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [module.eks.cluster_security_group_id, module.eks.node_security_group_id]
  subnet_ids          = module.vpc.private_subnets
  private_dns_enabled = true
}
resource "aws_vpc_endpoint" "ssm-messages-endpoint" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [module.eks.cluster_security_group_id, module.eks.node_security_group_id]
  subnet_ids          = module.vpc.private_subnets
  private_dns_enabled = true
}
resource "aws_vpc_endpoint" "ec2-messages-endpoint" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [module.eks.cluster_security_group_id, module.eks.node_security_group_id]
  subnet_ids          = module.vpc.private_subnets
  private_dns_enabled = true
}
resource "aws_vpc_endpoint" "eks-endpoint" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.eks"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [module.eks.cluster_security_group_id, module.eks.node_security_group_id]
  subnet_ids          = module.vpc.private_subnets
  private_dns_enabled = true
}
resource "aws_vpc_endpoint" "elasticloadbalancing-endpoint" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.elasticloadbalancing"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [module.eks.cluster_security_group_id, module.eks.node_security_group_id]
  subnet_ids          = module.vpc.private_subnets
  private_dns_enabled = true
}
resource "aws_vpc_endpoint" "autoscaling-endpoint" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.autoscaling"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [module.eks.cluster_security_group_id, module.eks.node_security_group_id]
  subnet_ids          = module.vpc.private_subnets
  private_dns_enabled = true
}
resource "aws_vpc_endpoint" "cw-endpoint" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.logs"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [module.eks.cluster_security_group_id, module.eks.node_security_group_id]
  subnet_ids          = module.vpc.private_subnets
  private_dns_enabled = true
}
resource "aws_vpc_endpoint" "kms-endpoint" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.kms"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [module.eks.cluster_security_group_id, module.eks.node_security_group_id]
  subnet_ids          = module.vpc.private_subnets
  private_dns_enabled = true
}
resource "aws_vpc_endpoint" "s3-endpoint" {
  vpc_id          = module.vpc.vpc_id
  service_name    = "com.amazonaws.${var.region}.s3"
  route_table_ids = [aws_route_table.WLZ_route_table.id]
}