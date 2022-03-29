output "node_address" {
  description = "Bastion ip address"
  value       = "IP address Bastion ${yandex_compute_instance.bastion.network_interface[0].nat_ip_address}"
}

output "ocp_public_ip" {
  description = "IP address to connect to OpenShift cluster API externally"
  value       = "IP address to connect to OpenShift cluster API externally ${yandex_vpc_address.addr_api.external_ipv4_address[0].address}"
}

