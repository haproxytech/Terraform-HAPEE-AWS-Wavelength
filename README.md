# AWS EKS with HAProxy Enterprise in Wavelength Zones

## Overview

This project deploys a complete edge computing solution in AWS consisting of:

- **EKS Cluster** for container orchestration
- **VPC with availability zones** in AWS Wavelength
- **HAProxy Enterprise (HAPEE)** in Wavelength zones for load balancing pods in the EKS cluster

This architecture enables low-latency load balancing at the network edge, allowing clients to efficiently access applications running in EKS clusters through AWS Wavelength zones.

## Prerequisites

Before deployment, ensure you have:

- **HAPEE License**: Valid license for HAProxy Enterprise Edition
- **AWS Access**:
  - AWS Wavelength services access
  - EKS creation and management permissions
  - EC2 management permissions
  - Carrier Gateway access (if using AWS Wavelength's Carrier Gateway)

## Configuration

1. `cluster_name`: EKS cluster name
2. `worker_key_name`: EC2 key pair for node access
3. `region`: AWS region for deployment
4. `wavelength_zones`: Wavelength zones compatible with your region
5. `ha`: Boolean to determine HAProxy installation mode (HA or standalone)

## Components

### Terraform

Open-source infrastructure as code (IaC) tool used to define and deploy the AWS resources.

### HAProxy Enterprise Kubernetes Ingress Controller (HAPEE)

High-performance TCP/HTTP load balancer and proxy that manages ingress traffic for Kubernetes workloads, integrated with AWS Wavelength for edge computing.

### AWS Wavelength

Brings AWS services to the edge of telecom networks, enabling ultra-low latency applications by running them closer to mobile devices.

### AWS EKS (Elastic Kubernetes Service)

Managed Kubernetes service that simplifies running containerized applications on AWS.

### AWS EC2

Provides compute capacity for both the EKS worker nodes and supporting services.

### AWS CLI

Command-line tool for programmatic interaction with AWS services.

## Installation

### Step 1: Install Terraform

#### For macOS:

```bash
# Install via Homebrew
brew install terraform

# Or manually
tar -xvzf terraform_*.zip
sudo mv terraform /usr/local/bin/
```

#### For Linux:

```bash
unzip terraform_*.zip
sudo mv terraform /usr/local/bin/
```

#### For Windows:

1. Download the .zip file from the Terraform website.
2. Extract to a directory of your choice.
3. Add the directory to your system PATH environment variable.

#### Verify Installation:

```bash
terraform -v
```

### Step 2: Download and Configure the Code

```bash
# Clone repository
git clone https://github.com/haproxytech/Terraform-HAPEE-AWS-Wavelength.git
cd wavelength-terraform-hapee-aws

# Modify configuration files:
# - Copy example.tfvars to terraform.tfvars
# - Adjust settings in terraform.tfvars for your environment
```

### Step 3: Run the Terraform Recipe

```bash
# Initialize Terraform
terraform init

# Configure AWS credentials (if not already configured)
aws configure

# Alternatively, set environment variables:
export AWS_ACCESS_KEY_ID="your-access-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-access-key"
export AWS_DEFAULT_REGION="your-region"

# Create a Terraform plan
terraform plan -out planfile

# Apply the Terraform plan
terraform apply -auto-approve planfile
```

### Step 4: Post-Deployment Configuration

After successful deployment, follow these instructions to complete the configuration:

#### Configure kubectl and Access Your Cluster

```bash
# Update your kubeconfig
aws eks update-kubeconfig --name YOUR-EKS-CLUSTER-NAME --region YOUR-REGION

# Verify cluster access
kubectl get nodes

# View your Wavelength Zone nodes
kubectl get nodes -L topology.kubernetes.io/zone

# Apply the sample workload
kubectl apply -f sample-workload.yaml

# Visit the HAProxy endpoint to view your application
# http://HAPROXY-FLOATING-IP (Floating HA IP)
```

#### Configure UDP LoadBalancer
```bash
# Apply the UDP sample workload:
kubectl apply -f udp-sample-workload.yml

# Get the NodePort and Node IP for your UDP service:
kubectl get svc udp-service -o jsonpath='{.spec.ports[0].nodePort}'
kubectl get nodes -o wide

# Modify the aux.cfg file to add UDP servers using the NodePort and define the Frontend IP:Port:
server udpserver NODE_IP:NODE_PORT

# Apply the sample workload
kubectl apply -f sample-workload.yaml

# SSH into your HAPEE machines

# Copy the modified aux.cfg file to the instance(s) in the following path /etc/hapee-3.0/

# Restart the HAPEE Kubernetes ingress service
sudo systemctl restart hapee-3.0-kubernetes-ingress

#Test the UDP connection:
echo "hello" | nc -u IP PORT

```


**Note**: Ensure your AWS CLI is configured with the correct region and credentials.

### High Availability Setup Instructions

To configure VRRP for high availability between your HAProxy instances:

```bash
# SSH into your primary instance
ssh ec2-user@PRIMARY-INSTANCE-IP

# Run the following command to configure the primary instance
sudo bash /etc/hapee-extras/wavelength_vrrp.sh -e PRIMARY-ENI-ID -f FLOATING-IP -l PRIMARY-LOCAL-IP -p SECONDARY-IP -i INTERFACE-NAME -r PRIORITY-VALUE -g YOUR-REGION

# SSH into your secondary instance
ssh ec2-user@SECONDARY-INSTANCE-IP

# Run the following command to configure the secondary instance
sudo bash /etc/hapee-extras/wavelength_vrrp.sh -e SECONDARY-ENI-ID -f FLOATING-IP -l SECONDARY-LOCAL-IP -p PRIMARY-IP -i INTERFACE-NAME -r PRIORITY-VALUE -g YOUR-REGION

# Verify the setup by checking the status of keepalived on both instances
sudo systemctl status hapee-extras-vrrp
```

Replace the placeholder values with your actual configuration values from the Terraform output.

## License


## Author Information

HAProxy Technologies
