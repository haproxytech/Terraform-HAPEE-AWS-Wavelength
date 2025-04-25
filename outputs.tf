locals {
  # Use lazy evaluation with conditionals to prevent evaluation of resources that don't exist
  ha_instructions = var.ha == "yes" ? (<<-EOT
    ## High Availability Setup Instructions
    
    To configure VRRP for high availability between your HAProxy instances:
    
    1. SSH into your primary instance:
       ssh -i /path/to/your/key ubuntu@${aws_eip.tf-wavelength-ip["primary"].carrier_ip}
    
    2. Run the following command to configure the primary instance:
       sudo bash /etc/hapee-extras/wavelength_vrrp.sh -e ${aws_instance.HAProxyL4LB["primary"].primary_network_interface_id} -f ${local.secondary_ip} -l ${aws_instance.HAProxyL4LB["primary"].private_ip} -p ${aws_instance.HAProxyL4LB["secondary"].private_ip} -i ens5 -r 51 -g ${var.region}
    
    3. SSH into your secondary instance:
       ssh -i /path/to/your/key ubuntu@${aws_eip.tf-wavelength-ip["secondary"].carrier_ip}
    
    4. Run the following command to configure the secondary instance:
       sudo bash /etc/hapee-extras/wavelength_vrrp.sh -e ${aws_instance.HAProxyL4LB["secondary"].primary_network_interface_id} -f ${local.secondary_ip} -l ${aws_instance.HAProxyL4LB["secondary"].private_ip} -p ${aws_instance.HAProxyL4LB["primary"].private_ip} -i ens5 -r 49 -g ${var.region}
    
    5. Verify the setup by checking the status of keepalived on both instances:
       sudo systemctl status hapee-extras-vrrp
   
    EOT
  ) : ""

  non_ha_instructions = <<-EOT
    ## HAProxy Instance Access Instructions
    
    To access your HAProxy instance:
    
    1. SSH into your instance:
       ssh -i /path/to/your/key ubuntu@${aws_eip.tf-wavelength-ip["primary"].carrier_ip}
    
    2. Verify the HAProxy service is running:
       sudo systemctl status hapee-3.0-lb
   
  EOT
}

output "ha_setup_instructions" {
  description = "Instructions for setting up High Availability with VRRP"
  value       = var.ha == "yes" ? local.ha_instructions : local.non_ha_instructions
}

output "vrrp_commands" {
  description = "Commands to configure VRRP for high availability"
  value = var.ha == "yes" ? {
    primary_command = "sudo bash /etc/hapee-extras/wavelength_vrrp.sh -e ${aws_instance.HAProxyL4LB["primary"].primary_network_interface_id} -f ${local.secondary_ip} -l ${aws_instance.HAProxyL4LB["primary"].private_ip} -p ${aws_instance.HAProxyL4LB["secondary"].private_ip} -i ens5 -r 51 -g ${var.region}"

    secondary_command = "sudo bash /etc/hapee-extras/wavelength_vrrp.sh -e ${aws_instance.HAProxyL4LB["secondary"].primary_network_interface_id} -f ${local.secondary_ip} -l ${aws_instance.HAProxyL4LB["secondary"].private_ip} -p ${aws_instance.HAProxyL4LB["primary"].private_ip} -i ens5 -r 49 -g ${var.region}"
  } : null
}

output "configure_kubectl" {
  description = "Instructions to access the EKS cluster"
  value       = <<-EOT
    Congratulations on extending an Amazon EKS cluster to AWS Wavelength Zones!
        
    To configure kubectl and access your cluster, run the following commands:
    
    1. Update your kubeconfig:
       aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.region}
        
    **Note: Ensure your AWS CLI is configured with the correct region and credentials.
    
    2. Verify cluster access:
       kubectl get nodes
    
    3. View your Wavelength Zone nodes:
       kubectl get nodes -L topology.kubernetes.io/zone
    
    4. Apply the sample workload:
       kubectl apply -f sample-workload.yaml
    
    5. Visit the HAProxy endpoint to view your application:
       ${var.ha == "yes" ? "http://${aws_eip.ha_floating_ip[0].carrier_ip} (Floating HA IP)" : "http://${aws_eip.tf-wavelength-ip["primary"].carrier_ip}"}
  EOT
}
output "udp_hapee_instructions" {
  description = "Instructions for setting up UDP in HAPEE External Ingress controller"
  value       = <<-EOT    
    To configure UDP support in your HAPEE External Ingress controller:
    
    1. Apply the UDP sample workload:
       kubectl apply -f udp-sample-workload.yml
    
    2. Get the NodePort and Node IP for your UDP service:
       kubectl get svc udp-service -o jsonpath='{.spec.ports[0].nodePort}'
       kubectl get nodes -o wide
    
    3. Modify the aux.cfg file to add UDP servers using the NodePort:
       server udpserver NODE_IP:NODE_PORT
       
       Replace NODE_IP with your node's IP address and NODE_PORT with the NodePort number.
       
    4. SSH into your HAPEE machines
    
    5. Copy the modified aux.cfg file to the instance(s) in the following path /etc/hapee-3.0/
    
    6. Restart the HAPEE Kubernetes ingress service:
       sudo systemctl restart hapee-3.0-kubernetes-ingress
    
    7. Test the UDP connection:
       echo "hello" | nc -u localhost 9090
    
    8. Important: Remember to modify your security groups to allow UDP traffic on the required ports
  EOT
}