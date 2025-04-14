# Name of your EKS cluster
cluster_name = "ex-eks-cluster"

# Your EC2 key pair for node access
worker_key_name = "demo-key"

# When changing region also adjust `wavelength_zones`
region = "eu-west-3"

# This is the metadata for your Wavelength Zone subnets
wavelength_zones = {
  cmn = {
    availability_zone    = "eu-west-3-cmn-wlz-1a",
    nbg                  = "eu-west-3-cmn-wlz-1",
    availability_zone_id = "euw3-cmn1-wlz1",
    worker_nodes         = 1,
    cidr_block           = "10.0.100.0/24"
  }
}

# HAProxy High Availability mode (yes/no)
ha = "yes"
