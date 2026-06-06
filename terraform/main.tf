resource "aws_vpc" "meditrack_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "meditrack-vpc"
  }
}

# =========================
# SUBNET PUBLIC
# =========================

resource "aws_subnet" "meditrack_subnet" {
  vpc_id                  = aws_vpc.meditrack_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-west-3a"
  map_public_ip_on_launch = true

  tags = {
    Name = "meditrack-public-subnet"
  }
}

# =========================
# SUBNETS PRIVÉS POUR RDS
# =========================

resource "aws_subnet" "meditrack_private_1" {
  vpc_id            = aws_vpc.meditrack_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-west-3a"

  tags = {
    Name = "meditrack-private-1"
  }
}

resource "aws_subnet" "meditrack_private_2" {
  vpc_id            = aws_vpc.meditrack_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "eu-west-3b"

  tags = {
    Name = "meditrack-private-2"
  }
}

# =========================
# DB SUBNET GROUP
# =========================

resource "aws_db_subnet_group" "meditrack_db_subnet_group" {
  name = "meditrack-db-subnet-group"

  subnet_ids = [
    aws_subnet.meditrack_private_1.id,
    aws_subnet.meditrack_private_2.id
  ]

  tags = {
    Name = "meditrack-db-subnet-group"
  }
}

# =========================
# RDS SECURITY GROUP
# =========================

resource "aws_security_group" "meditrack_rds_sg" {
  name   = "meditrack-rds-sg"
  vpc_id = aws_vpc.meditrack_vpc.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.meditrack_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "meditrack-rds-sg"
  }
}

# =========================
# RDS POSTGRESQL INSTANCE
# =========================

resource "aws_db_instance" "meditrack_db" {
  identifier              = "meditrack-db"
  engine                  = "postgres"
  engine_version          = "16"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  storage_type            = "gp2"
  username                = "meditrackadmin"
  password                = var.db_password
  db_name                 = "meditrack"
  db_subnet_group_name    = aws_db_subnet_group.meditrack_db_subnet_group.name
  vpc_security_group_ids  = [aws_security_group.meditrack_rds_sg.id]
  publicly_accessible     = false
  skip_final_snapshot     = true
  deletion_protection     = true
  backup_retention_period = 1

  tags = {
    Name = "meditrack-db"
  }
}

# =========================
# INTERNET GATEWAY
# =========================

resource "aws_internet_gateway" "meditrack_igw" {
  vpc_id = aws_vpc.meditrack_vpc.id

  tags = {
    Name = "meditrack-igw"
  }
}

# =========================
# ROUTE TABLE PUBLIC
# =========================

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

# =========================
# SECURITY GROUP EC2
# =========================

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

# =========================
# INSTANCE EC2
# =========================

resource "aws_instance" "meditrack_ec2" {
  ami                         = "ami-0f46eced18e562eef"
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.meditrack_subnet.id
  vpc_security_group_ids      = [aws_security_group.meditrack_sg.id]
  associate_public_ip_address = true
  key_name                    = var.key_name

  tags = {
    Name = "meditrack-ec2"
  }
}

# =========================
# CLOUDFRONT
# =========================

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

################################
# SECOND PUBLIC SUBNET (ALB REQUIREMENT)
################################

resource "aws_subnet" "meditrack_subnet_2" {
  vpc_id                  = aws_vpc.meditrack_vpc.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = "eu-west-3b"
  map_public_ip_on_launch = true

  tags = {
    Name = "meditrack-public-subnet-2"
  }
}

resource "aws_route_table_association" "meditrack_rta_2" {
  subnet_id      = aws_subnet.meditrack_subnet_2.id
  route_table_id = aws_route_table.meditrack_rt.id
}

################################
# ECS CLUSTER
################################

resource "aws_ecs_cluster" "meditrack" {
  name = "meditrack-cluster"
}

################################
# IAM ROLE FOR ECS TASK
################################

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole-meditrack"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

################################
# ECS TASK DEFINITION
################################

resource "aws_ecs_task_definition" "meditrack_task" {
  family                   = "meditrack-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "meditrack-container"
      image     = "682135518833.dkr.ecr.eu-west-3.amazonaws.com/meditrack-api:latest"
      essential = true

      portMappings = [{
        containerPort = 3000
        hostPort      = 3000
      }]

      environment = [
        { name = "DB_HOST", value = aws_db_instance.meditrack_db.address },
        { name = "DB_USER", value = "meditrackadmin" },
        { name = "DB_NAME", value = "meditrack" },
        { name = "DB_PASSWORD", value = var.db_password }
      ]
    }
  ])
}

################################
# SECURITY GROUP ALB
################################

resource "aws_security_group" "meditrack_alb_sg" {
  name   = "meditrack-alb-sg"
  vpc_id = aws_vpc.meditrack_vpc.id

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
}

################################
# SECURITY GROUP ECS
################################

resource "aws_security_group" "meditrack_ecs_sg" {
  name   = "meditrack-ecs-sg"
  vpc_id = aws_vpc.meditrack_vpc.id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.meditrack_alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

################################
# APPLICATION LOAD BALANCER
################################

resource "aws_lb" "meditrack_alb" {
  name               = "meditrack-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.meditrack_alb_sg.id]

  subnets = [
    aws_subnet.meditrack_subnet.id,
    aws_subnet.meditrack_subnet_2.id
  ]
}

################################
# TARGET GROUP
################################

resource "aws_lb_target_group" "meditrack_tg" {
  name        = "meditrack-tg"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.meditrack_vpc.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

################################
# LISTENER
################################

resource "aws_lb_listener" "meditrack_listener" {
  load_balancer_arn = aws_lb.meditrack_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.meditrack_tg.arn
  }
}

################################
# ECS SERVICE
################################

resource "aws_ecs_service" "meditrack_service" {
  name            = "meditrack-service"
  cluster         = aws_ecs_cluster.meditrack.id
  task_definition = aws_ecs_task_definition.meditrack_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets = [
      aws_subnet.meditrack_subnet.id,
      aws_subnet.meditrack_subnet_2.id
    ]

    security_groups  = [aws_security_group.meditrack_ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.meditrack_tg.arn
    container_name   = "meditrack-container"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.meditrack_listener]
}