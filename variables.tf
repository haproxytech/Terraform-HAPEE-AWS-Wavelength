variable "profile" {
  type        = string
  description = "AWS Credentials Profile to use"
  default     = "default"
}

variable "region" {
  type        = string
  description = "This is the AWS region."
  validation {
    condition     = contains(["us-east-1", "us-west-2", "ap-northeast-1", "ap-northeast-2", "eu-west-2", "eu-central-1", "eu-west-3"], var.region)
    error_message = "Valid values for regions supporting local Zones are: us-east-1, us-west-2, ap-northeast-1, ap-northeast-2, eu-west-2, eu-west-3 and eu-central-1"
  }
}

variable "worker_key_name" {
  type        = string
  description = "This is your EC2 key name."
}

variable "cluster_name" {
  type        = string
  description = "This is the name of your EKS cluster deployed to the parent region."
}

variable "managed_node_instance_type" {
  type        = string
  default     = "t3.large"
  description = "This is the instance type for your EKS managed nodes."
}
variable "haproxy_instance_type" {
  type        = string
  default     = "r5.2xlarge"
  description = "This is the instance type for your HAPROXY managed nodes."
}

variable "self_managed_node_instance_type" {
  type        = string
  default     = "r5.2xlarge"
  description = "This is the instance type for your EKS self-managed nodes."
}

variable "wavelength_zones" {
  description = "This is the metadata for your Wavelength Zone subnets."
  type        = map(object({
                  availability_zone    = string
                  nbg                  = string
                  availability_zone_id = string
                  worker_nodes         = number
                  cidr_block           = string
                }))
}

# Create variable for HA mode
variable "ha" {
  description = "Enable High Availability mode (yes/no)"
  type        = string
  default     = "yes"
}
