output "server_public_ip" {
  value = module.compute.server_public_ip
}

output "server_private_ip" {
  value = module.compute.server_private_ip
}

output "agent_public_ips" {
  value = module.compute.agent_public_ips
}

output "agent_private_ips" {
  value = module.compute.agent_private_ips
}

output "agent_names" {
  value = module.compute.agent_names
}

output "ssh_private_key_path" {
  value = module.compute.private_key_path
}

output "nip_io_domain" {
  description = "Your free TLS-ready domain — use this in your Ingress"
  value       = "taskapp.${module.compute.server_public_ip}.nip.io"
}
