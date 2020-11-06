data "http" "myip" {
  url = "http://ipv4.icanhazip.com"
}

data "http" "dd_ip_ranges" {
  url = "https://ip-ranges.datadoghq.com/"
}

# data "dns_a_record_set" "proxy" {
#   host = "proxy.azure.pipsquack.ca"
# }

data "aws_availability_zones" "available" {
  state                = "available"
  exclude_zone_ids = ["us-west-2d"]
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = "true"

  tags = {
    Name    = var.cluster_name
    Creator = "alex.fernandes"
  }
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  availability_zone_id    = data.aws_availability_zones.available.zone_ids[0]
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name    = var.cluster_name
    Creator = "alex.fernandes"
  }
}

resource "aws_security_group" "main" {
  vpc_id = aws_vpc.main.id
  name   = "main_security_group"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${chomp(data.http.myip.body)}/32"]
    self        = true
  }

  // Datadog webhooks origins
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = jsondecode(data.http.dd_ip_ranges.body).webhooks.prefixes_ipv4
    self        = true
  }

  // Kubernetes default Nodeport range
  # ingress {
  #   from_port   = 30000
  #   to_port     = 32767
  #   protocol    = "tcp"
  #   cidr_blocks = ["${data.dns_a_record_set.proxy.addrs[0]}/32"]
  # }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  // Explicitly opens DNS ports so we can safely close broad Internet access (rule above)
  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "6"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "17"
    cidr_blocks = ["0.0.0.0/0"]
  }

  //  Opening BGP port for Calico
  egress {
    from_port   = 179
    to_port     = 179
    protocol    = "6"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = var.cluster_name
    Creator = "alex.fernandes"
  }
}

resource "aws_security_group" "proxy" {
  vpc_id = aws_vpc.main.id
  name   = "proxy_security_group"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${chomp(data.http.myip.body)}/32"]
    self        = true
  }

  ingress {
    from_port         = 0
    to_port           = 0
    protocol          = "-1"
    security_groups = [aws_security_group.main.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.cluster_name} proxy"
    Creator = "alex.fernandes"
  }
}

resource "aws_security_group_rule" "proxy" {
  type                     = "egress"
  from_port                = 3128
  to_port                  = 3128
  protocol                 = "tcp"
  security_group_id        = aws_security_group.main.id
  source_security_group_id = aws_security_group.proxy.id
  // Avoid cycle dependency when destroying the environemnt
  depends_on = [aws_security_group.main, aws_security_group.proxy]
}


resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = var.cluster_name
    Creator = "alex.fernandes"
  }
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name    = var.cluster_name
    Creator = "alex.fernandes"
  }
}

resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}
