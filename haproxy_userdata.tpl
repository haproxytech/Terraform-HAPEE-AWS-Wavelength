#!/bin/bash

###### ADD AWS Region ######
# Ensure the AWS directory exists
mkdir -p /root/.aws

# Write the credentials file
cat <<EOF > /root/.aws/credentials
[default]
region = ${region}
EOF

# Set permissions for security
chmod 600 /root/.aws/credentials
###### ADD AWS Region ######

#Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
apt install -y unzip
unzip awscliv2.zip
sudo ./aws/install
alias aws=/usr/local/bin/aws 

#Install Kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Create an EKS Access Entry
aws eks create-access-entry \
    --cluster-name ${cluster_name} \
    --principal-arn ${haproxy_role_arn} \
    --type STANDARD \
    --region ${region}

# Associate the EKS Cluster Admin Policy
aws eks associate-access-policy \
    --cluster-name ${cluster_name} \
    --principal-arn ${haproxy_role_arn} \
    --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
    --access-scope type=cluster \
    --region ${region}
#Revise Ingress Manifest
cat << EOF > /etc/hapee-3.0/kubernetes-ingress.yml 
version: 1
controller:
  ingress.class: haproxy
  kubeconfig: /root/.kube/config
network:
  disable-https: true
  http-bind-port: 80
  ipv4-bind-address: 0.0.0.0
path:
  hapee: /opt/hapee-3.0/sbin/hapee-lb
  config-file: /etc/hapee-3.0/haproxy.cfg
  config-dir: /etc/hapee-3.0
runtime-dir: /var/run/hapee-3.0
hapee:
  start: systemctl start hapee-3.0-lb.service
  stop: systemctl stop hapee-3.0-lb.service
  reload: systemctl reload hapee-3.0-lb.service
  restart: systemctl restart hapee-3.0-lb.service
debug:
  loglevel: trace
EOF
sudo touch /etc/hapee-extras/wavelength_vrrp.sh
echo "${vrrp_script}" | base64 --decode | sudo tee /etc/hapee-extras/wavelength_vrrp.sh > /dev/null
sudo chmod +x /etc/hapee-extras/wavelength_vrrp.sh


######### Install the kube conf at the end #########
# Configure Kubeconfig for Root
sudo mkdir -p /root/.kube
sudo touch /root/.kube/config  # Ensure the config file exists
sudo chmod 600 /root/.kube/config

# Update Kubeconfig
sudo aws eks update-kubeconfig --name ${cluster_name} --region ${region} --kubeconfig /root/.kube/config
######### Install the kube conf at the end #########

## Disable hapee-lb
systemctl disable hapee-3.0-lb
systemctl stop hapee-3.0-lb
##################

sudo systemctl enable hapee-3.0-kubernetes-ingress
sudo systemctl restart hapee-3.0-kubernetes-ingress