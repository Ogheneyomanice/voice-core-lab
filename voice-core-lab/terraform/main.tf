data "aws_availability_zones" "available" {
  state = "available"
}

# Latest Amazon Linux 2023 AMI, resolved through the public SSM parameter.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  azs  = slice(data.aws_availability_zones.available.names, 0, 2)
  tags = {
    Project   = var.project
    ManagedBy = "terraform"
  }
}

########## Network: one VPC, two availability zones ##########

resource "aws_vpc" "main" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = "${var.project}-vpc" })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, { Name = "${var.project}-igw" })
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.tags, { Name = "${var.project}-public-${count.index + 1}" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(local.tags, { Name = "${var.project}-public-rt" })
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

########## Security ##########

resource "aws_security_group" "sip" {
  name        = "${var.project}-sip"
  description = "SIP signalling to the Kamailio nodes"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SIP over UDP from the allowed client range"
    from_port   = 5060
    to_port     = 5060
    protocol    = "udp"
    cidr_blocks = [var.allowed_cidr]
  }

  ingress {
    description = "SIP over TCP from the allowed client range"
    from_port   = 5060
    to_port     = 5060
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  ingress {
    description = "Load balancer health checks (TCP 5060) from inside the VPC"
    from_port   = 5060
    to_port     = 5060
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${var.project}-sip-sg" })
}

# Session Manager access, so no SSH port is ever opened.
resource "aws_iam_role" "ssm" {
  name = "${var.project}-ssm"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  name = "${var.project}-ssm"
  role = aws_iam_role.ssm.name
}

########## Compute: one Kamailio node per availability zone ##########

resource "aws_instance" "kamailio" {
  count                       = 2
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public[count.index].id
  vpc_security_group_ids      = [aws_security_group.sip.id]
  iam_instance_profile        = aws_iam_instance_profile.ssm.name
  user_data                   = templatefile("${path.module}/user_data.sh.tftpl", { repo_url = var.repo_url })
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    encrypted   = true
    volume_size = 12
  }

  tags = merge(local.tags, { Name = "${var.project}-kamailio-${count.index + 1}" })
}

########## Network Load Balancer in front of both nodes ##########

resource "aws_lb" "sip" {
  name                             = "${var.project}-nlb"
  load_balancer_type               = "network"
  internal                         = false
  subnets                          = aws_subnet.public[*].id
  enable_cross_zone_load_balancing = true

  tags = local.tags
}

resource "aws_lb_target_group" "udp" {
  name        = "${var.project}-udp"
  port        = 5060
  protocol    = "UDP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  # UDP target groups health-check over TCP; Kamailio listens on TCP 5060 too.
  health_check {
    protocol = "TCP"
    port     = "5060"
  }

  tags = local.tags
}

resource "aws_lb_target_group" "tcp" {
  name        = "${var.project}-tcp"
  port        = 5060
  protocol    = "TCP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    protocol = "TCP"
    port     = "5060"
  }

  tags = local.tags
}

resource "aws_lb_target_group_attachment" "udp" {
  count            = 2
  target_group_arn = aws_lb_target_group.udp.arn
  target_id        = aws_instance.kamailio[count.index].id
  port             = 5060
}

resource "aws_lb_target_group_attachment" "tcp" {
  count            = 2
  target_group_arn = aws_lb_target_group.tcp.arn
  target_id        = aws_instance.kamailio[count.index].id
  port             = 5060
}

resource "aws_lb_listener" "udp" {
  load_balancer_arn = aws_lb.sip.arn
  port              = 5060
  protocol          = "UDP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.udp.arn
  }
}

resource "aws_lb_listener" "tcp" {
  load_balancer_arn = aws_lb.sip.arn
  port              = 5060
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tcp.arn
  }
}
