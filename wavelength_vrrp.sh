#!/bin/bash
# -----------------------------------------------------------------------------
# Author:  HAPROXY Enterprise
# Script Name: wavelength_vrrp.sh
# Version: 1.0
# Created: 2025-02-20
#
# Copyright (c) 2025, HAPROXY Enterprise. All rights reserved.
#
# Subject to the terms and conditions defined in file HAPEE-AGREEMENT-LICENSE.txt, which is part of this package.
#
# 
# -----------------------------------------------------------------------------

# Help function
print_help() {
    echo "VRRP Setup Script for AWS Wavelength External Ingress Controller"
    echo ""
    echo "Required parameters:"
    echo "  -e, --eni         AWS ENI Interface ID"
    echo "  -f, --float-ip    Float IP address"
    echo "  -l, --local-ip    Local IP Device address"
    echo "  -p, --peer-ip     Peer IP address"
    echo "  -i, --interface   Network interface name"
    echo "  -r, --priority    VRRP priority"
    echo "  -g, --region      AWS region"
    echo ""
    echo "Note: This script requires:"
    echo "  - HAProxy Enterprise apt source configured"
    echo "  - AWS CLI installed"
    echo "  - IAM Role with permissions to manage ENI IP addresses"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--eni)
            ENI="$2"
            shift 2
            ;;
        -f|--float-ip)
            IP="$2"
            shift 2
            ;;
        -l|--local-ip)
            LOCALIP="$2"
            shift 2
            ;;
        -p|--peer-ip)
            PEERIP="$2"
            shift 2
            ;;
        -i|--interface)
            INTERFACE="$2"
            shift 2
            ;;
        -r|--priority)
            PRI="$2"
            shift 2
            ;;
        -g|--region)
            REGION="$2"
            shift 2
            ;;
        -h|--help)
            print_help
            ;;
        *)
            echo "Unknown parameter: $1"
            print_help
            ;;
    esac
done

# Check if script is run with sudo
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script with sudo"
    exit 1
fi

# Validate required parameters
missing_params=()
[[ -z "$ENI" ]] && missing_params+=("ENI")
[[ -z "$IP" ]] && missing_params+=("Float IP")
[[ -z "$LOCALIP" ]] && missing_params+=("Local IP")
[[ -z "$PEERIP" ]] && missing_params+=("Peer IP")
[[ -z "$INTERFACE" ]] && missing_params+=("Interface")
[[ -z "$PRI" ]] && missing_params+=("VRRP Priority")
[[ -z "$REGION" ]] && missing_params+=("AWS Region")

if [ ${#missing_params[@]} -ne 0 ]; then
    echo "Error: Missing required parameters:"
    printf '%s\n' "${missing_params[@]}"
    print_help
fi

# Check AWS CLI installation
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed"
    exit 1
fi

# Check if hapee-extras-vrrp package is available
if ! apt-cache show hapee-extras-vrrp &> /dev/null; then
    echo "Error: apt source is not installed. Please include HAProxy Enterprise apt source first"
    exit 1
fi

# Install required package
apt-get install -y hapee-extras-vrrp

# Configure sysctl
echo "net.ipv4.ip_nonlocal_bind=1" | tee -a /etc/sysctl.conf
sysctl -w net.ipv4.ip_nonlocal_bind=1

# Create IP configuration file
cat > /etc/default/ip_sec << EOF
IP=$IP
ENI=$ENI
EOF

# Configure VRRP
cat > /etc/hapee-extras/hapee-vrrp.cfg << EOF
global_defs {
    script_user keepalived_script
    enable_script_security
}

vrrp_script chk_sshd {
    script "pkill -0 sshd"
    interval 5
    weight -4
    rise 1
    fall 2
}

vrrp_script chk_lb {
    script "pkill -0 hapee-lb"
    interval 1
    weight 6
    rise 1
    fall 2
}

vrrp_instance aws_vrrp {
    notify_master "/usr/local/sbin/general/ip_sec.sh"
    state BACKUP
    interface $INTERFACE
    track_interface {
        $INTERFACE weight -4
    }
    track_script {
        chk_lb
        chk_sshd
    }
    unicast_src_ip $LOCALIP
    unicast_peer {
        $PEERIP
    }
    virtual_router_id 1
    priority $PRI
    authentication {
        auth_type PASS
        auth_pass haproxy
    }
    virtual_ipaddress_excluded {
        $IP dev $INTERFACE
    }
}
EOF

# Create keepalived_script user
useradd -m keepalived_script
passwd -d keepalived_script
usermod -aG sudo keepalived_script

# Add keepalived_script to sudoers
echo "keepalived_script ALL=(ALL) NOPASSWD:ALL" | EDITOR='tee -a' visudo

# Configure AWS region for keepalived user
sudo -u keepalived_script aws configure set region "$REGION"

# Create and configure ip_sec.sh script
mkdir -p /usr/local/sbin/general/
chmod -R +x /usr/local/sbin/general/

cat > /usr/local/sbin/general/ip_sec.sh << EOF
#!/bin/sh
. /etc/default/ip_sec
aws ec2 assign-private-ip-addresses --network-interface-id "\$ENI" --private-ip-addresses "\$IP" --allow-reassignment
sudo ip addr add "\$IP"/24 dev $INTERFACE
EOF

chmod +x /usr/local/sbin/general/ip_sec.sh

# Enable and start VRRP service
systemctl enable hapee-extras-vrrp
systemctl unmask hapee-extras-vrrp
systemctl start hapee-extras-vrrp

echo "VRRP setup completed successfully"