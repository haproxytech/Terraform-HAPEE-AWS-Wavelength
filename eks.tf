data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {}
data "http" "myip" {
  url = "https://api64.ipify.org?format=text"
}

##############################################################################
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

module "eks" {
  source                                   = "terraform-aws-modules/eks/aws"
  version                                  = "~> 20.0"
  cluster_name                             = var.cluster_name
  cluster_version                          = "1.30"
  control_plane_subnet_ids                 = module.vpc.private_subnets
  vpc_id                                   = module.vpc.vpc_id
  cluster_endpoint_public_access           = true
  cluster_endpoint_private_access          = true
  cluster_enabled_log_types                = ["audit", "api", "authenticator"]
  cluster_encryption_config                = { "resources" : ["secrets"] }
  create_iam_role                          = true
  create_node_security_group               = true
  enable_cluster_creator_admin_permissions = true
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
  }

  self_managed_node_group_defaults = {
    autoscaling_group_tags = {
      "k8s.io/cluster-autoscaler/enabled" : true,
      "k8s.io/cluster-autoscaler/${var.cluster_name}" : "owned",
    }
  }

  eks_managed_node_groups = {
    eks-mng-parent-region = {
      subnet_ids     = module.vpc.private_subnets
      min_size       = 1
      max_size       = 5
      desired_size   = 2
      instance_types = [var.managed_node_instance_type]
      capacity_type  = "SPOT"
      update_config = {
        max_unavailable_percentage = 33
      }
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
        instance_metadata_tags      = "disabled"
      }
    }
  }

  self_managed_node_groups = {
    eks-wlz-node-group = {
      name                        = "eks-ng-wavelength"
      instance_type               = var.self_managed_node_instance_type
      desired_size                = 0
      key_name                    = var.worker_key_name
      launch_template_name        = "self-managed-eks-ng"
      launch_template_description = "Self managed node group example launch template"
      ebs_optimized               = true
      enable_monitoring           = true
      subnet_ids                  = [for subnet in aws_subnet.local_subnets : subnet.id]
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 20
            volume_type           = "gp2"
            encrypted             = true
            kms_key_id            = module.ebs_kms_key.key_arn
            delete_on_termination = true
          }
        }
      }
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
        instance_metadata_tags      = "disabled"
      }
      create_iam_role          = true
      iam_role_name            = "self-managed-node-group-role"
      iam_role_use_name_prefix = false
      iam_role_description     = "Self managed node group complete example role"
      iam_role_additional_policies = {
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
      }
    }
  }
  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"] #["${chomp(data.http.myip.body)}/32"]
}



############################################################
module "ebs_kms_key" {
  source      = "terraform-aws-modules/kms/aws"
  version     = "~> 1.5"
  description = "Customer managed key to encrypt EKS managed node group volumes"
  # Policy
  key_administrators = [
    data.aws_caller_identity.current.arn
  ]
  key_service_roles_for_autoscaling = [
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling",
    module.eks.cluster_iam_role_arn,
  ]
  aliases = ["eks/${module.eks.cluster_name}/ebs"]
}

################################################################################
# Helm charts
################################################################################
data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
  registry {
    url      = "oci://public.ecr.aws"
    username = "AWS"
    password = data.aws_ecrpublic_authorization_token.token.password
  }
}

###############################################################################
# Security Group Rule to Allow Incoming Traffic on Port 80
################################################################################
resource "aws_security_group_rule" "allow_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = module.eks.node_security_group_id
}
resource "aws_security_group_rule" "allow_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["${chomp(data.http.myip.body)}/32"]  # Restricts to your current IP
  security_group_id = module.eks.node_security_group_id
}