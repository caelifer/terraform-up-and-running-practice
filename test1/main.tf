provider "aws" {
  region = "us-east-2"
}

variable "int_http_port" {
  default     = 8080
  description = "Internal web-server port to service HTTP requests from"
  type        = number
}

variable "ext_http_port" {
  default     = 80
  description = "External publicly accessible HTTP port"
  type        = number
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

resource "aws_launch_configuration" "test1" {
  image_id        = "ami-0c55b159cbfafe1f0"
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.web_sg.id]

  user_data = <<-EOF
    #!/bin/bash
    echo "Hello, world!" > index.html
    nohup busybox httpd -f -p ${var.int_http_port} &
    EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "test1_web_asg" {
  launch_configuration = aws_launch_configuration.test1.name
  vpc_zone_identifier  = data.aws_subnet_ids.default.ids

  target_group_arns = [aws_lb_target_group.test1_ltg.arn]
  health_check_type = "ELB"

  min_size = 2
  max_size = 10

  tag {
    key                 = "cname"
    value               = "tf-asg-test1"
    propagate_at_launch = true
  }
}

resource "aws_security_group" "web_sg" {
  name = "test1-web-sg"
  ingress {
    from_port   = var.int_http_port
    to_port     = var.int_http_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb_listener" "test1_http" {
  load_balancer_arn = aws_lb.test1_lb.arn
  port              = var.ext_http_port
  protocol          = "HTTP"

  # By default return simple 404 page
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  }
}

resource "aws_security_group" "test1_alb_sg" {
  name = "tf-alb-test1"

  # Allow inbound HTTP requests
  ingress {
    from_port   = var.ext_http_port
    to_port     = var.ext_http_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "test1_lb" {
  name               = "tf-lb-test1"
  load_balancer_type = "application"
  subnets            = data.aws_subnet_ids.default.ids
  security_groups    = [aws_security_group.test1_alb_sg.id]
}

resource "aws_lb_target_group" "test1_ltg" {
  name     = "tf-ltg-test1"
  port     = var.int_http_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 2
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener_rule" "test1_llr" {
  listener_arn = aws_lb_listener.test1_http.arn
  priority     = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.test1_ltg.arn
  }
}

output "public_url" {
  value       = "http://${aws_lb.test1_lb.dns_name}:${var.ext_http_port}/"
  description = "Public URL for test1 web"
}

# vim: :ts=4:sw=4:ai:
