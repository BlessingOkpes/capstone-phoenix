resource "aws_security_group" "cluster" {
  name        = "${var.project_name}-sg"
  description = "Least-privilege SG: 22/80/443 from the world (22 restricted to admin_cidr), everything else internal-only"
  vpc_id      = var.vpc_id

  # SSH — only from admin's IP, never the whole internet
  ingress {
    description = "SSH (admin only)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # HTTP — world (needed for Let's Encrypt HTTP-01 challenge + ingress)
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS — world (this is how the app is actually accessed)
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # k3s API server — admin only (for kubectl from your control machine), NEVER 0.0.0.0/0
  ingress {
    description = "k3s API (admin only)"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # k3s API server — nodes talking to each other (agents joining the server)
  ingress {
    description = "k3s API (cluster-internal)"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    self        = true
  }

  # Flannel VXLAN — cluster-internal only, never public
  ingress {
    description = "Flannel VXLAN (cluster-internal)"
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    self        = true
  }

  # kubelet metrics — cluster-internal only, never public
  ingress {
    description = "kubelet (cluster-internal)"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}
