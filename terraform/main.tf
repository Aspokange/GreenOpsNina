resource "aws_vpc" "meditrack_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "meditrack-vpc"
  }
}

resource "aws_subnet" "meditrack_subnet" {
  vpc_id                  = aws_vpc.meditrack_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-west-3a"
  map_public_ip_on_launch = true

  tags = {
    Name = "meditrack-subnet"
  }
}

resource "aws_internet_gateway" "meditrack_igw" {
  vpc_id = aws_vpc.meditrack_vpc.id

  tags = {
    Name = "meditrack-igw"
  }
}

resource "aws_route_table" "meditrack_rt" {
  vpc_id = aws_vpc.meditrack_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.meditrack_igw.id
  }

  tags = {
    Name = "meditrack-rt"
  }
}

resource "aws_route_table_association" "meditrack_rta" {
  subnet_id      = aws_subnet.meditrack_subnet.id
  route_table_id = aws_route_table.meditrack_rt.id
}

resource "aws_security_group" "meditrack_sg" {
  vpc_id = aws_vpc.meditrack_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "meditrack-sg"
  }
}

resource "aws_instance" "meditrack_ec2" {
  ami                         = "ami-0f46eced18e562eef"
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.meditrack_subnet.id
  vpc_security_group_ids      = [aws_security_group.meditrack_sg.id]
  associate_public_ip_address = true
  key_name                    = var.key_name

  user_data = <<-EOF
              #!/bin/bash
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "GreenOpsNina works 🚀" > /var/www/html/index.html
              EOF

  tags = {
    Name = "meditrack-ec2"
  }
}

resource "aws_cloudfront_distribution" "meditrack_cdn" {

  depends_on = [aws_instance.meditrack_ec2]

  origin {
    domain_name = aws_instance.meditrack_ec2.public_dns
    origin_id   = "meditrack-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "meditrack-origin"

    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}