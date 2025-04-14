locals {
  # Determine how many instances to create based on HA setting
  instance_count = var.ha == "yes" ? 2 : 1

  # Create a map for the instances
  instance_map = {
    for idx in range(local.instance_count) :
    idx == 0 ? "primary" : "secondary" => idx
  }
}

# New resource: Network interface for primary instance with secondary IP
resource "aws_network_interface" "primary_interface" {
  count           = var.ha == "yes" ? 1 : 0
  subnet_id       = values(aws_subnet.local_subnets)[0].id
  security_groups = [module.eks.node_security_group_id]

  # This explicitly configures a secondary private IP
  private_ips_count = 1 # This will assign 1 secondary IP in addition to the primary

  tags = {
    Name = "HAProxy Primary Network Interface"
  }
}

# Get all private IPs assigned to the network interface
# This is needed because private_ips is a set and cannot be indexed
data "aws_network_interface" "primary_interface_data" {
  count = var.ha == "yes" ? 1 : 0
  id    = aws_network_interface.primary_interface[0].id

  depends_on = [aws_network_interface.primary_interface]
}

# Use locals to extract the primary and secondary IPs
locals {
  primary_ip = var.ha == "yes" ? data.aws_network_interface.primary_interface_data[0].private_ip : null
  secondary_ip = var.ha == "yes" ? tolist(setsubtract(
    toset(data.aws_network_interface.primary_interface_data[0].private_ips),
    toset([data.aws_network_interface.primary_interface_data[0].private_ip])
  ))[0] : null
}

resource "aws_instance" "HAProxyL4LB" {
  for_each = {
    for k, v in local.instance_map : k => v
    if k == "primary" || (k == "secondary" && var.ha == "yes")
  }

  ami           = data.aws_ami.haproxy_enterprise.id
  instance_type = var.haproxy_instance_type

  # Use the custom network interface for primary instance, otherwise use subnet_id
  dynamic "network_interface" {
    for_each = each.key == "primary" && var.ha == "yes" ? [1] : []
    content {
      network_interface_id = aws_network_interface.primary_interface[0].id
      device_index         = 0
    }
  }

  # Only use subnet_id when not using network_interface
  subnet_id = each.key == "primary" && var.ha == "yes" ? null : (
    each.key == "primary" ? values(aws_subnet.local_subnets)[0].id : values(aws_subnet.local_subnets)[1 % length(aws_subnet.local_subnets)].id
  )

  vpc_security_group_ids = each.key == "primary" && var.ha == "yes" ? null : [module.eks.node_security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.haproxy_profile.id
  key_name               = var.worker_key_name
  metadata_options {
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
    http_tokens                 = "required"
  }
  root_block_device {
    volume_size = 10
    volume_type = "gp2"
    encrypted   = true
    kms_key_id  = data.aws_kms_key.current.arn
  }
  ebs_optimized = true
  monitoring    = true
  user_data_base64 = base64encode(templatefile("${path.module}/haproxy_userdata.tpl", {
    region           = var.region,
    cluster_name     = var.cluster_name,
    haproxy_role_arn = aws_iam_role.haproxy_role.arn,
    vrrp_script      = base64encode(file("${path.module}/wavelength_vrrp.sh"))
  }))
  tags = {
    Name = "HAProxy Enterprise Load Balancer - ${each.key}"
  }
  depends_on = [
    module.eks
  ]
}


# Create Carrier IP address in Wavelength Zone
resource "aws_eip" "tf-wavelength-ip" {
  for_each             = local.instance_map
  domain               = "vpc"
  network_border_group = each.key == "primary" ? element(values(var.wavelength_zones), 0).nbg : element(values(var.wavelength_zones), 1 % length(var.wavelength_zones)).nbg
}

# Attach Carrier IP address to Wavelength Zone instance
resource "aws_eip_association" "eip_assoc" {
  for_each = local.instance_map

  # For primary instance with network interface, use network_interface_id
  network_interface_id = each.key == "primary" && var.ha == "yes" ? aws_network_interface.primary_interface[0].id : null
  private_ip_address   = each.key == "primary" && var.ha == "yes" ? local.primary_ip : null

  # For secondary instance, use instance_id
  instance_id = each.key != "primary" || var.ha != "yes" ? aws_instance.HAProxyL4LB[each.key].id : null

  allocation_id = aws_eip.tf-wavelength-ip[each.key].id
}

# Create a secondary EIP for the primary instance when HA is enabled
resource "aws_eip" "ha_floating_ip" {
  count                = var.ha == "yes" ? 1 : 0
  domain               = "vpc"
  network_border_group = element(values(var.wavelength_zones), 0).nbg

  tags = {
    Name = "HAProxy Floating IP"
  }
}

# Secondary IP association for the primary instance
resource "aws_eip_association" "ha_floating_ip_assoc" {
  count = var.ha == "yes" ? 1 : 0

  # Use network_interface_id instead of instance_id
  network_interface_id = aws_network_interface.primary_interface[0].id
  private_ip_address   = local.secondary_ip
  allocation_id        = aws_eip.ha_floating_ip[0].id
  depends_on = [
    aws_instance.HAProxyL4LB["primary"]
  ]
}

data "aws_kms_key" "current" {
  key_id = data.aws_ebs_default_kms_key.current.key_arn
}

data "aws_ami" "haproxy_enterprise" {
  most_recent = true
  owners      = ["679593333241"] # HAProxy Enterprise AMI owner ID

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "name"
    values = ["hapee-ubuntu-noble-amd64-hvm-3.0r1-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

data "aws_ebs_default_kms_key" "current" {}

resource "aws_iam_role" "haproxy_role" {
  name = "haproxy-eks-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "haproxy_profile" {
  name = "haproxyProfile"
  role = aws_iam_role.haproxy_role.name
}

# Copy the necessary policies from the EKS cluster role
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.haproxy_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.haproxy_role.name
}

resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.haproxy_role.name
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.haproxy_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.haproxy_role.name
}

# Add custom policy for EKS access entry operations
resource "aws_iam_role_policy" "eks_access_entry_policy" {
  name = "eks-access-entry-policy"
  role = aws_iam_role.haproxy_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:CreateAccessEntry",
          "eks:DeleteAccessEntry",
          "eks:AssociateAccessPolicy",
          "eks:DisassociateAccessPolicy",
          "eks:ListAccessPolicies",
          "eks:TagResource",
          "eks:ListTagsForResource",
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:AccessKubernetesApi",
          "eks:DescribeAccessEntry",
          "eks:ListAccessEntries",
          "eks:DescribeUpdate",
          "ec2:DescribeInstances",
          "ec2:AssignPrivateIpAddresses",
        ]
        Resource = "*"
      }
    ]
  })
}

# Add additional policy for EC2 network interface operations
resource "aws_iam_role_policy" "ec2_network_policy" {
  name = "ec2-network-policy"
  role = aws_iam_role.haproxy_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeNetworkInterfaces",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses"

        ]
        Resource = "*"
      }
    ]
  })
}
# Create access entries for the HAProxy instances to authenticate with the EKS cluster
resource "aws_eks_access_entry" "haproxy_access_entry" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.haproxy_role.arn
  type          = "STANDARD"
  depends_on = [
    module.eks
  ]
}

# Create an access policy association with ClusterAdminPolicy 
resource "aws_eks_access_policy_association" "haproxy_admin_access" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.haproxy_role.arn
  access_scope {
    type = "cluster"
  }
  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  depends_on = [
    aws_eks_access_entry.haproxy_access_entry
  ]
}