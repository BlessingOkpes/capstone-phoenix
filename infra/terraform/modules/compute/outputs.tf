output "server_public_ip" {
  value = aws_instance.server.public_ip
}

output "server_private_ip" {
  value = aws_instance.server.private_ip
}

output "agent_public_ips" {
  value = aws_instance.agent[*].public_ip
}

output "agent_private_ips" {
  value = aws_instance.agent[*].private_ip
}

output "agent_names" {
  value = aws_instance.agent[*].tags.Name
}

output "private_key_path" {
  value = local_sensitive_file.private_key.filename
}
